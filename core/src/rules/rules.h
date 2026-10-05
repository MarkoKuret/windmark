// The racing rules engine (rules.md): right of way, the limits on the right-of-way boat, room at marks and
// obstructions, exoneration, incidents, penalties and penalty turns, deadlines and disqualification. It runs in
// tick step 1 right after the race progress (race.md §1) on the poses and motion at t_n and the contact events of
// the previous tick's collision step (collisions.md §5).
#pragma once

#include <cstdint>
#include <map>
#include <span>
#include <string_view>
#include <vector>

#include "collide/collide.h"
#include "course/course.h"
#include "data/venue.h"
#include "math/wm_math.h"
#include "race/race.h"
#include "state/checksum.h"

namespace wm {

// rules.md §11.3 rule codes.
enum class RuleCode : std::uint8_t {
  none,
  r10, r11, r12, r13, r14, r15, r16_1, r16_2, r17, r18_2, r18_3, r18_4, r19, r20, r21_1, r21_2, r31,
  late,         // "44.2-late"
  c_prep,       // "C-prep"
  c_entry,      // "C-entry"
  si_boundary,  // "SI-boundary"
};
std::string_view rule_code_str(RuleCode r);

// rules.md §12, loadable from the race settings for testing.
struct RulesParams {
  float r_pair = 10.0f;          // L_max
  float r_drop = 12.0f;          // L_max
  float margin_min = 0.3f;       // m
  float margin_coef = 0.05f;     // L_max
  float h_warn = 4.0f, h_breach = 1.0f;          // s
  float delta = 10.0f * DEG, delta_warn = 20.0f * DEG;
  float t_react = 0.5f;          // s
  float escape_h = 3.0f, escape_react = 0.3f;    // s
  float proper_tol = 10.0f * DEG, proper_time = 2.0f;
  float r15_cause = 3.0f, r15_room = 4.0f;       // s
  float cc_rate = 3.0f * DEG, cc_time = 0.3f, cc_heading = 5.0f * DEG, cc_end_rate = 1.0f * DEG, cc_end_time = 1.0f;
  float r16_window = 3.0f;       // s
  float r17_dist = 2.0f, r17_clear = 2.2f;       // L of the leeward boat
  float v_damage = 1.5f;         // m/s
  float r14_window = 2.0f;       // s
  float zone_lengths = 3.0f;     // overridden by the course (courses.md §5.2)
  float doubt = 0.25f;           // s
  float room_horizon = 4.0f;     // s
  float t_persist_fast = 0.5f, t_persist_slow = 1.0f;  // s
  float incident_close = 5.0f;   // s clear
  float penalty_spacing = 3.0f;  // s
  float turn_rate_min = 2.0f * DEG, turn_start = 0.5f, turn_pause = 3.0f, turn_reversal = 20.0f * DEG;
  float turn_one = 350.0f * DEG;
  float t_serve = 120.0f;        // s from the incident (§9.4, §9.6)
  float r182d_tack = 3.0f;       // s, 18.2(d) overlap obtained by tacking (§7.3)
  std::int32_t dsq_pending = 3, dsq_total = 6;
  float protest_prompt = 8.0f;   // s
  float boundary_penalty = 15.0f, boundary_dsq = 60.0f;  // s
  float mark_touch_gap = 10.0f;  // s
  float obstruction_h = 6.0f;    // s, rule 19 approach test
};

// What the rules read of one boat each tick (rules.md §2.2 step 1).
struct RulesBoatInput {
  Vec2 pos{0.0f, 0.0f};
  float psi = 0.0f;
  float v = 0.0f;               // speed through the water
  float turn_rate = 0.0f;       // heading rate, rad/s, + clockwise (boat.md §5.9)
  Vec2 current{0.0f, 0.0f};     // the drift: current at the boat plus her sideways drift (§3.1, boat.md §6.4)
  float cog = 0.0f, sog = 0.0f;
  float tws = 0.0f, twd = 0.0f; // clean wind at the boat (race.md §0)
  float main_beta = 0.0f;
  float helm = 0.0f;            // actual helm h
  float let_fly_drive = 0.0f;   // trim_speed with the sails let fly (boat.md §9), for the slow-down escape (§3.6)
  bool ai = false;              // protest mode: the AI protests on its own (rules.md §10)
};

enum class Relation : std::uint8_t { n_a, i_astern, i_ahead, overlapped, overlapped_via };
enum class KcState : std::uint8_t { clear, warning, breach };

struct Penalty {
  RuleCode rule = RuleCode::none;
  std::int32_t other = -1;
  std::uint32_t tick = 0;
  std::int32_t count = 1;  // always 1: every penalty is one turn (§9.2)
};

// rules.md §11.1
struct PairRecord {
  std::int32_t i = -1, j = -1;
  Relation relation = Relation::n_a;
  std::int32_t kc_giver = -1, kc_holder = -1;
  RuleCode kc_rule = RuleCode::none;
  KcState kc_state = KcState::clear;
  std::int32_t room_entitled = -1, room_giver = -1;
  RuleCode room_rule = RuleCode::none;
  std::int32_t room_mark = -1;  // mark index, or -1 - obstruction id for rule 19
  KcState room_state = KcState::clear;
  std::vector<std::pair<std::int32_t, RuleCode>> limits;  // (holder, rule) breaking now
  std::int32_t rule17_holder = -1;
  bool incident = false;
  std::int32_t incident_culprit = -1;
  RuleCode incident_rule = RuleCode::none;
  std::uint32_t incident_tick = 0;
  float gap = 0.0f;
  float ttc = INFINITY;
};

// rules.md §11.2
struct BoatRules {
  std::int8_t tack = 1;         // +1 starboard, -1 port
  bool tacking = false;
  bool turning_for_penalty = false;
  float turn_progress = 0.0f;   // rad, signed
  std::int32_t turn_tacks = 0, turn_gybes = 0;
  std::vector<Penalty> pending;
  std::int32_t served = 0, received = 0;
  float deadline_s = -1.0f;     // to the oldest pending penalty's deadline (§9.4); < 0: none
  bool returning_to_start = false;
  bool dsq = false;
  bool out_of_bounds = false;
};

enum class RulesEventKind : std::uint8_t {
  rule_warning, incident, penalty, penalty_served, penalty_cancelled, penalty_late, mark_touch, protestable,
  protested, disqualified,
};

struct RulesEvent {
  RulesEventKind kind = RulesEventKind::incident;
  std::uint32_t tick = 0;
  std::int32_t boat = -1;   // holder / culprit / penalised boat
  std::int32_t other = -1;
  RuleCode rule = RuleCode::none;
  std::int32_t count = 0;
  bool contact = false;
  std::int32_t mark = -1;
  float deadline = 0.0f;    // protestable: seconds
};

enum class DsqReason : std::uint8_t { pending, total, boundary, late };

class Rules {
 public:
  // After Race::create. `venue` may be null (no land or obstacles as obstructions). Both must outlive this.
  void init(const Race& race, const VenueData* venue, const RulesParams& p = RulesParams());
  // Boats added to the race after init (joiners).
  void sync_boats(const Race& race);

  // Tick step 1.2 on the race state after Race::progress. `contacts` are the previous tick's contact events.
  void update(std::uint32_t n, const Race& race, std::span<const RulesBoatInput> boats,
              std::span<const ContactEvent> contacts);

  // Protest mode (rules.md §10): the fouled boat protests an open protestable incident.
  void protest(std::int32_t boat, std::uint32_t n);

  const RulesParams& params() const { return p_; }
  std::size_t boat_count() const { return boats_.size(); }
  const BoatRules& boat(std::size_t i) const { return rec_[i]; }
  bool penalty_pending(std::size_t i) const { return !rec_[i].pending.empty(); }
  void pending_flags(std::vector<std::uint8_t>& out) const;
  const std::vector<PairRecord>& pairs() const { return pair_rec_; }
  const PairRecord* pair(std::int32_t i, std::int32_t j) const;
  const std::vector<RulesEvent>& events() const { return events_; }
  void clear_events() { events_.clear(); }
  // Boats the engine disqualified this tick; the race makes them ghosts (race.md §6.3).
  const std::vector<std::pair<std::int32_t, DsqReason>>& dsq() const { return dsq_; }

  // Geometry exposed for tests and the HUD.
  float hull_gap(std::size_t i, std::size_t j) const;

  // rules.md §14: the rules block of the world snapshot. load() needs rules set up for the same race (init and
  // sync_boats); it overwrites every state value and clears the events, or returns false and changes nothing.
  void save(SnapshotWriter& w) const;
  bool load(SnapshotReader& r);

 private:
  struct Pose {
    Vec2 c;
    float psi;
  };

  // rules.md §2.3 per boat.
  struct BoatState {
    const PerfData* perf = nullptr;
    float L = 0.0f, B = 0.0f, r_hull = 0.0f;
    bool racing = false;
    // this tick
    std::vector<Vec2> hull;
    Vec2 c{0.0f, 0.0f}, bow{0.0f, 0.0f}, stern{0.0f, 0.0f};
    float twa = 0.0f, theta_ch = 0.7f, theta_dn = 2.6f, vmg_tws = -1.0f;
    std::vector<Pose> pred;                          // 0 .. 10 s every 0.1 s
    mutable std::vector<std::vector<Vec2>> pred_hulls;
    mutable std::vector<std::uint8_t> pred_placed;
    mutable std::vector<Pose> man[4];               // escape manoeuvres over the room horizon, this tick
    mutable bool man_valid[4] = {false, false, false, false};
    // tack and tacking (§3.4)
    bool tack_init = false;
    std::int8_t tack = 1;
    bool flipped = false, head_to_wind = false;      // this tick
    bool has_tack_change = false;
    std::uint32_t tack_change_tick = 0;
    bool tacking = false;
    std::int8_t tacking_to = 1;
    bool has_tacking_end = false;
    std::uint32_t tacking_end_tick = 0;
    float twa_prev = 0.0f, psi_prev = 0.0f;
    bool has_prev = false;
    // course change (§5.3)
    std::int32_t cc_run = 0;
    std::int8_t cc_run_dir = 0;
    bool cc_active = false, cc_started_now = false;
    std::int8_t cc_dir = 0;
    std::uint32_t cc_back = 0;  // ticks from t_c (the first tick of the detection run) to its detection
    std::int32_t cc_calm = 0;
    std::vector<float> psi_hist;  // last 41 headings (2 s), newest last
    std::vector<float> v_hist;    // last 41 speeds
    // proper course (§3.7)
    float above_time = 0.0f;
    bool above = false;
    // penalty turn (§9.3)
    std::int8_t t_dir = 0;
    std::int32_t t_run = 0, t_pause = 0, t_tacks = 0, t_gybes = 0;
    bool t_started = false;
    float t_theta = 0.0f, t_extreme = 0.0f;
    // penalties (§9)
    bool has_last_penalty = false;
    std::uint32_t last_penalty_tick = 0;
    bool dsq_done = false;
    // zones (§7.1), per course mark
    std::vector<std::uint8_t> in_zone, stbd_since_zone;
    std::vector<std::uint32_t> zone_enter;
    std::vector<float> dmin;
    std::int32_t r183_mark = -1;
    // mark touches (§8)
    std::vector<std::uint32_t> touch_tick;
    std::vector<std::uint8_t> touched;
    // boundary (courses.md §5.1)
    std::int32_t out_ticks = 0;
    // rule 15 causes: end of returning and of penalty turns
    bool returning_prev = false, pen_turn_prev = false;
    bool has_status_end = false;
    std::uint32_t status_end_tick = 0;
    // gate buoy assignment (§7.2)
    std::int32_t gate_step = -1;
    std::int8_t gate_buoy = 0;
  };

  // rules.md §7.3, §7.4: one room entitlement at a mark.
  struct MarkRoom {
    std::int32_t mark = -1;
    std::int32_t entitled = -1, giver = -1;
    RuleCode rule = RuleCode::r18_2;
    bool frozen = true;             // 18.2(b) status (false: 18.2(a) while overlapped)
    std::vector<Vec2> corridor;     // the entitled boat's mark-room path when the entitlement began
    bool could_act = false;
    KcState state = KcState::clear;
    bool breach = false;
  };

  // rules.md §2.3 per pair (i < j).
  struct PairState {
    std::int32_t i = -1, j = -1;
    bool judged = false;
    std::uint32_t first_tick = 0;
    Relation raw = Relation::n_a, raw_prev = Relation::n_a, raw_before = Relation::n_a;
    bool has_raw = false;
    std::uint32_t raw_change_tick = 0;
    Relation rel = Relation::n_a;
    std::int32_t giver = -1;
    RuleCode kc_rule = RuleCode::none;
    std::uint32_t onset_tick = 0;
    bool r15_pending = false, r15_breach = false;
    std::uint32_t r15_start = 0;
    KcState kc = KcState::clear, kc_prev = KcState::clear;
    std::uint8_t kc_hist[32] = {};  // kc state by tick n % 32 (rule 16 looks back to the start of a course change)
    bool has_breach_tick = false;
    std::uint32_t last_breach_tick = 0;
    bool w161 = false, w162 = false, r161 = false, r162 = false;
    std::uint32_t w161_start = 0, w162_start = 0;
    std::int32_t w16_holder = -1;
    std::int32_t r17_holder = -1;
    bool r17 = false;
    std::vector<MarkRoom> rooms;
    std::vector<std::int32_t> used_marks;  // marks whose 18.2(b) status has been set (until both leave the zone)
    bool r183 = false, r184 = false;
    std::int32_t r183_holder = -1, r184_holder = -1;
    bool r19_on = false, r19_could_act = false, r19_breach = false;
    std::int32_t r19_entitled = -1, r19_giver = -1, r19_obst = -1;
    KcState r19_state = KcState::clear;
    std::vector<Vec2> r19_corridor;
    // persistence and incidents (§9.1)
    std::int32_t br_culprit = -1;
    RuleCode br_rule = RuleCode::none;
    std::uint32_t br_since = 0;
    bool has_decisive = false;
    std::int32_t dec_culprit = -1;
    RuleCode dec_rule = RuleCode::none;
    std::uint32_t dec_tick = 0;
    bool inc_open = false, inc_contact = false, inc_penalised_noncontact = false;
    std::int32_t inc_culprit = -1;
    RuleCode inc_rule = RuleCode::none;
    std::uint32_t inc_tick = 0, clear_since = 0;
    bool protest_open = false;
    std::uint32_t protest_deadline = 0;
    std::int32_t protest_fouled = -1;
    float protest_min_gap = INFINITY;
    bool contact_now = false;
    bool has_contact_pen = false;
    std::int32_t contact_pen_boat = -1;
    std::uint32_t contact_pen_tick = 0;
    float gap = 0.0f, ttc = INFINITY;
  };

  // --- geometry (rules_geom.cpp) ---
  void predict(std::size_t i, const RulesBoatInput& in);
  const std::vector<Vec2>& pred_hull(std::size_t i, std::size_t k) const;
  float pred_gap(std::size_t a, std::size_t b, float H, float cap) const;
  bool turn_test_hits(std::size_t a, std::size_t b, float delta) const;
  bool escape(std::size_t a, std::size_t b, float H) const;
  bool escape_room(std::size_t g, const std::vector<Pose>& e_path, std::size_t e, float H, float margin) const;
  void manoeuvre(std::size_t a, int kind, float H, std::vector<Pose>& out) const;
  const std::vector<Pose>& manoeuvre_cached(std::size_t a, int kind) const;
  void mark_room_path(std::size_t e, std::int32_t mark, Side side, Vec2 next_ref, std::vector<Vec2>& out) const;
  void along_path(std::size_t e, const std::vector<Vec2>& path, float H, std::vector<Pose>& out) const;
  float poses_gap(std::size_t a, const std::vector<Pose>& pa, std::size_t b, const std::vector<Pose>& pb,
                  float cap) const;
  float margin(std::size_t a, std::size_t b) const;
  float theta_ch(std::size_t i) const { return st_[i].theta_ch; }

  // --- engine (rules.cpp) ---
  void boat_step(std::uint32_t n, std::size_t i, const Race& race, const RulesBoatInput& in);
  void turn_tracker(std::uint32_t n, std::size_t i, const Race& race, const RulesBoatInput& in);
  void zones(std::uint32_t n, std::size_t i, const Race& race);
  void boundary(std::uint32_t n, std::size_t i, const Race& race);
  Relation direct_relation(std::size_t a, std::size_t b) const;
  bool windward_of(std::size_t a, std::size_t b, const Race& race) const;
  void judge_pair(std::uint32_t n, PairState& ps, const Race& race, std::span<const RulesBoatInput> in);
  void mark_rules(std::uint32_t n, PairState& ps, const Race& race, std::span<const RulesBoatInput> in);
  void obstruction_rules(std::uint32_t n, PairState& ps, const Race& race, std::span<const RulesBoatInput> in);
  void contacts(std::uint32_t n, const Race& race, std::span<const ContactEvent> contacts);
  void counted_breach(std::uint32_t n, PairState& ps, std::int32_t culprit, RuleCode rule, bool contact);
  void issue(std::uint32_t n, std::int32_t boat, RuleCode rule, std::int32_t other, bool force_one);
  void penalties(std::uint32_t n, const Race& race);
  std::int32_t buoy_of(std::size_t i, const Race& race, std::int32_t& step) const;
  bool within_mark_room(std::size_t e, const MarkRoom& mr) const;
  bool rule_on(RuleCode r, const Race& race) const;
  void emit(RulesEvent e) { events_.push_back(e); }
  PairState& pair_state(std::int32_t i, std::int32_t j);

  RulesParams p_;
  const VenueData* venue_ = nullptr;
  const ResolvedCourse* course_ = nullptr;
  UmpireMode umpire_ = UmpireMode::standard;
  std::vector<BoatState> st_;
  std::vector<BoatRules> rec_;
  std::vector<const PerfData*> boats_;
  std::map<std::uint64_t, PairState> pairs_;  // key i << 32 | j, i < j (ordered: deterministic iteration)
  std::vector<PairRecord> pair_rec_;
  std::vector<RulesEvent> events_;
  std::vector<std::pair<std::int32_t, DsqReason>> dsq_;
  std::vector<RulesBoatInput> in_;  // this tick's inputs (for the geometry helpers)
  std::vector<std::uint8_t> keep_clear_;  // per boat: give-way under 21.2 in Warning or Breach last tick (§9.3)
  std::uint32_t n_ = 0;
  bool match_ = false;
  float zone_lengths_ = 3.0f;
};

}  // namespace wm
