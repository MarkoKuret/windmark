// The race flow (race.md): race-level states and the start sequence, spawning, starting with OCS and recalls,
// rounding marks and gates, finishing, closing, the live ranking and the results. It runs in tick step 1 on the
// boats' poses at t_n (race.md §1); the rules engine (rules/rules.h) runs right after it and reads its state.
#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <vector>

#include "course/course.h"
#include "data/perf.h"
#include "data/venue.h"
#include "math/wm_math.h"
#include "state/checksum.h"

namespace wm {

enum class RaceState : std::uint8_t { created, free_sailing, sequence, racing, closing, closed, abandoned };
enum class RulesLevel : std::uint8_t { none, basic, full };
enum class PenaltyKind : std::uint8_t { one_turn };  // every penalty is one 360 turn (rules.md §9.2)
enum class UmpireMode : std::uint8_t { standard, contact_only, protest };

// race.md §9, in the order non-finishers are listed.
enum class ScoreCode : std::uint8_t { none, ZFP, DNC, DNS, OCS, UFD, BFD, DNF, RET, DSQ };
std::string_view score_code_name(ScoreCode c);

enum class GhostReason : std::uint8_t { none, finished, retired, dsq, ufd, bfd, dnf, dns, left };

// race.md §2. Unset optionals take the course default (courses.md §5.2), then the race type's default.
struct RaceSettings {
  std::optional<RaceType> race_type;
  std::optional<SequenceKind> sequence;
  std::optional<PrepFlag> prep_flag;
  float free_sailing_s = 30.0f;
  bool general_recall = false;
  RulesLevel rules_level = RulesLevel::full;
  PenaltyKind penalty = PenaltyKind::one_turn;
  UmpireMode umpire = UmpireMode::standard;
  float time_limit_s = 0.0f;  // 0 = from the course
  bool finish_window = true;
  float start_limit_s = 240.0f;  // race.md §4.4
  std::uint64_t race_seed = 1;
};

// What the race reads of one boat each tick (race.md §0): the pose at t_n and the clean wind at the boat.
struct RaceBoatInput {
  Vec2 pos{0.0f, 0.0f};
  float psi = 0.0f;
  float v = 0.0f;
  float tws = 0.0f;         // clean wind speed at the boat
  float twd = 0.0f;         // clean wind direction (from)
  float main_beta = 0.0f;   // main sail angle (race.md §0 rules tack downwind)
};

enum class SignalKind : std::uint8_t { warning, prep_up, prep_down, start, general_recall, x_up, x_down };
enum class FinishBlock : std::uint8_t { penalty, ocs };

enum class RaceEventKind : std::uint8_t {
  signal,          // signal
  boat_ocs,        // boat, flag
  boat_returned,   // boat, flag
  started,         // boat, t
  rounded,         // boat, step, buoy (gates), t
  finish_blocked,  // boat, block
  finished,        // boat, t_us, place
  ghosted,         // boat, ghost
  retired,         // boat
  joined,          // boat
  left,            // boat
  window_warning,  // value = seconds left (60 or 10)
  race_closing,    // value = window length, s
  race_closed,
  abandoned,
};

struct RaceEvent {
  RaceEventKind kind = RaceEventKind::signal;
  std::uint32_t tick = 0;
  std::int32_t boat = -1;
  SignalKind signal = SignalKind::warning;
  PrepFlag flag = PrepFlag::P;
  std::int32_t step = -1;
  std::int32_t buoy = -1;  // gates: the mark index rounded
  float t = 0.0f;          // race time, s
  std::int64_t t_us = 0;   // finish time, microseconds after the gun
  std::int32_t place = 0;
  FinishBlock block = FinishBlock::penalty;
  GhostReason ghost = GhostReason::none;
  float value = 0.0f;
};

// Penalties the race hands to the rules engine: the match-race entry rules (race.md §3.4).
enum class RacePenaltyRule : std::uint8_t { c_prep, c_entry };
struct RacePenaltyRequest {
  std::int32_t boat;
  RacePenaltyRule rule;
};

// Per boat race state (race.md §4–§8).
struct RaceBoat {
  // entry
  const PerfData* perf = nullptr;
  bool human = true;
  float performance_scale = 1.0f;  // boat.md §2, fixed at spawn (§3.5); scales the projected speed (§7.2)
  float L = 0.0f, B = 0.0f;
  std::uint32_t joined_tick = 0;

  // poses: the rules hull at t_{n-1} and t_n
  bool has_prev = false;
  Vec2 c_prev{0.0f, 0.0f}, c{0.0f, 0.0f};
  float psi_prev = 0.0f, psi = 0.0f;
  std::vector<Vec2> hull_prev, hull;

  // start
  bool came_near = false;       // within 10 L of the start line after the warning (DNC otherwise)
  bool pre_seen = false;        // completely on the pre-start side at a tick at or after the gun
  bool ocs = false;             // P, rule 29.1: over at the gun, not yet returned
  bool ocs_i = false;           // I, rule 30.1, not yet returned
  bool i_around_end = false;    // the last course-to-pre-start crossing of c was around an end
  bool z_flag = false, u_flag = false, black_flag = false;
  bool ocs_scored = false;      // never returned: released onto the course at the start limit, scores OCS
  bool started = false;
  float t_start = 0.0f;
  // match entry (race.md §3.4)
  bool entry_crossed = false, entered = false;

  // course progress
  std::int32_t next = 0;        // next step; 0 = not started
  float phi[2] = {0.0f, 0.0f};  // winding per buoy
  float phi_done[2] = {0.0f, 0.0f};
  std::int32_t n_cross = 0;
  bool finish_armed = true;     // completely on the course side since the last blocked crossing
  bool rounded_this_tick = false;
  std::int32_t last_rounded = -1;  // step index of the last completed step
  std::vector<float> splits;       // race time at each completed step (index = step)

  // finish and after
  bool finished = false;
  std::int64_t t_finish_us = 0;
  std::int32_t place = 0;
  std::uint32_t finish_tick = 0;
  bool cleared = false;
  bool ghost = false;
  GhostReason ghost_reason = GhostReason::none;
  bool retired = false;
  bool dsq = false;
  ScoreCode code = ScoreCode::none;
  bool projected = false;
  float t_proj = 0.0f;

  // ranking
  float D = 0.0f;
  std::int32_t rank = 0;
};

struct ResultRow {
  std::int32_t boat = -1;
  std::int32_t place = 0;       // finishing place (0 = none)
  ScoreCode code = ScoreCode::none;
  float points = 0.0f;
  std::int64_t t_finish_us = 0;  // finishers
  bool projected = false;
};

// race.md §8.1 leg axis.
struct LegAxis {
  Vec2 e{0.0f, 1.0f};
  bool wind_axis = true;
  float length = 0.0f;
};

// Spawn grid (race.md §3.5): slots in order, and the entry order from the race seed.
std::vector<Vec2> spawn_slots(const ResolvedCourse& course, const VenueData* venue, float L_max, std::size_t n);
std::vector<std::int32_t> spawn_order(std::uint64_t race_seed, std::int32_t n);

class Race {
 public:
  // Entries are added before create(); later ones are joiners (race.md §3.5), allowed until the prep signal.
  // `performance_scale` is the boat's (boat.md §2, clamped as there); the race uses it for projected finishes.
  std::int32_t add_boat(const PerfData* perf, bool human, float performance_scale = 1.0f);

  // race.md §3.1: ticks from creation to the gun for these settings and course defaults (the course axis is laid
  // for the wind at the gun, courses.md §6.1).
  static std::int64_t gun_after_creation(const RaceSettings& s, const CourseRaceDefaults& course);

  // race.md §3.1 Created: `n_created` is this tick; `twd_mean` the race-wide wind direction now (§8.1).
  bool create(const ResolvedCourse& course, const RaceSettings& s, std::uint32_t n_created, float twd_mean,
              std::string& error);

  // Tick step 1.1 (race progress) on the poses at t_n. `penalty_pending[i]` = boat i has an unserved turn
  // penalty (rules.md §9.3). `twd_mean` is the race-wide wind direction at t_n (sampled every 10 s, §8.1).
  void progress(std::uint32_t n, std::span<const RaceBoatInput> boats, std::span<const std::uint8_t> penalty_pending,
                float twd_mean);
  // Tick step 1.3: ranking and distances (race.md §8), and the close checks that follow the rules.
  void rank(std::uint32_t n, std::span<const RaceBoatInput> boats);

  // Actions from outside the tick (menus, the rules engine, the network layer).
  void retire(std::int32_t boat, std::uint32_t n);
  void disqualify(std::int32_t boat, std::uint32_t n);  // rules.md §9.5
  void leave(std::int32_t boat, std::uint32_t n);
  void abandon(std::uint32_t n);

  // State
  RaceState state() const { return state_; }
  std::uint32_t n_created() const { return n_created_; }
  std::int64_t n_gun() const { return n_gun_; }
  float race_time(std::uint32_t n) const { return static_cast<float>(static_cast<std::int64_t>(n) - n_gun_) * DT; }
  PrepFlag prep_flag() const { return prep_flag_; }
  SequenceKind sequence() const { return sequence_; }
  RaceType race_type() const { return race_type_; }
  const RaceSettings& settings() const { return settings_; }
  const ResolvedCourse& course() const { return course_; }
  std::int32_t general_recalls() const { return recalls_; }
  bool x_flag() const { return x_flag_; }
  bool rules_live() const { return rules_live_; }
  bool after_gun(std::uint32_t n) const { return static_cast<std::int64_t>(n) >= n_gun_; }
  // rules.md §7.1: the course's zone in hull lengths in a fleet race, 2 in a match race (Appendix C).
  float zone_lengths() const { return race_type_ == RaceType::match ? 2.0f : course_.race.zone_lengths; }
  float L_max() const { return L_max_; }

  std::size_t boat_count() const { return boats_.size(); }
  const RaceBoat& boat(std::size_t i) const { return boats_[i]; }
  // A racing boat for the rules (rules.md §2.1): rules are live and she is not a ghost.
  bool racing(std::size_t i) const { return rules_live_ && !boats_[i].ghost; }
  // rule 22.1 (race.md §4.3, rules.md §4 row 2): after the gun, not started and not completely on the pre-start
  // side.
  bool returning(std::size_t i) const;
  bool collides(std::size_t i) const { return !boats_[i].ghost; }
  bool casts(std::size_t i) const { return !boats_[i].ghost; }

  const std::vector<RaceEvent>& events() const { return events_; }
  void clear_events() { events_.clear(); }
  const std::vector<RacePenaltyRequest>& penalty_requests() const { return penalty_requests_; }
  const std::vector<std::int32_t>& order() const { return order_; }  // boat indices by rank
  const std::vector<LegAxis>& legs() const { return legs_; }          // index j = leg into step j
  const std::vector<ResultRow>& results() const { return results_; }
  float twd_mean() const { return twd_mean_; }

  // Line helpers (race.md §3.3): signed distance > 0 on the course side and position along the start line.
  float start_s(Vec2 p) const;
  float start_u(Vec2 p) const;
  float finish_s(Vec2 p) const;  // > 0 beyond the finish (away from the course side)
  float finish_u(Vec2 p) const;
  Vec2 bow(std::size_t i) const;

  // race.md §13: the race block of the world snapshot. load() needs a race created from the same course with the
  // same boats; it overwrites every state value and clears the events, or returns false and changes nothing.
  void save(SnapshotWriter& w) const;
  bool load(SnapshotReader& r);

 private:
  struct Line {
    Vec2 a{0.0f, 0.0f}, b{0.0f, 0.0f}, d{1.0f, 0.0f};
    float len = 1.0f;
    float s(Vec2 p) const;  // left(p; a→b) / |b − a|
    float u(Vec2 p) const;
  };
  struct Crossing {
    bool crossed = false;
    float f = 1.0f;
  };

  void emit(RaceEvent e);
  void signal(std::uint32_t n, SignalKind k);
  void signals(std::uint32_t n);
  void place_hulls(std::span<const RaceBoatInput> in);
  void pre_start(std::uint32_t n, std::size_t i, float t);
  void at_gun(std::uint32_t n);
  void general_recall(std::uint32_t n);
  void starting(std::uint32_t n, std::size_t i, std::span<const std::uint8_t> pending);
  void sail_course(std::uint32_t n, std::size_t i, std::span<const std::uint8_t> pending);
  void after_finish(std::uint32_t n, std::size_t i);
  void begin_step(std::size_t i, std::int32_t k);
  void complete_step(std::uint32_t n, std::size_t i, std::int32_t buoy);
  void make_ghost(std::uint32_t n, std::size_t i, GhostReason r);
  void close(std::uint32_t n);
  void update_legs();
  float remaining(std::size_t i) const;
  float v_ref_time(std::size_t i, float tws) const;
  Crossing hull_cross(const std::vector<Vec2>& p0, const std::vector<Vec2>& p1, const Line& line) const;
  bool all_pre_start(const std::vector<Vec2>& hull) const;
  bool point_in_start_triangle(Vec2 p) const;
  bool any_human_racing() const;
  bool any_racing() const;

  RaceSettings settings_;
  ResolvedCourse course_;
  RaceType race_type_ = RaceType::fleet;
  SequenceKind sequence_ = SequenceKind::s5410;
  PrepFlag prep_flag_ = PrepFlag::I;
  RaceState state_ = RaceState::created;
  std::uint32_t n_created_ = 0;
  std::int64_t n_gun_ = 0;
  std::int64_t n_warning_ = 0;
  std::int32_t signals_done_ = 0;  // signals of the current sequence already given
  std::int32_t recalls_ = 0;
  bool x_flag_ = false;
  bool rules_live_ = false;
  bool any_finished_ = false;
  std::int64_t n_window_end_ = -1;
  std::int64_t n_time_limit_ = 0;
  float L_max_ = 0.0f;
  float twd_mean_ = 0.0f;
  float legs_twd_ = -1.0f;
  Line start_, finish_;
  Vec2 first_ref_{0.0f, 0.0f};  // first step's reference point (the start triangle apex)
  std::vector<RaceBoat> boats_;
  std::vector<RaceEvent> events_;
  std::vector<RacePenaltyRequest> penalty_requests_;
  std::vector<LegAxis> legs_;
  std::vector<std::int32_t> order_;
  std::vector<ResultRow> results_;
  std::vector<std::int32_t> finished_this_tick_;
};

}  // namespace wm
