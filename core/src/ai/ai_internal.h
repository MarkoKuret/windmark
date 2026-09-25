// Internals of the AI skippers shared by the ai_*.cpp files: the per boat state, the per tick context and the
// geometry helpers (ai.md). Not part of the AI's interface.
#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

#include "ai/ai.h"
#include "course/geometry.h"

namespace wm {

namespace ai_detail {

enum class Man : std::uint8_t { straight = 0, tack = 1, gybe = 2, irons = 3, penalty = 4 };
enum class Leg : std::uint8_t { beat = 0, reach = 1, run = 2 };
enum class StartPhase : std::uint8_t { free, position, hover, final_approach };

// Constant turn rate and velocity motion (rules.md §3.1) for predictions.
struct Motion {
  Vec2 c{0.0f, 0.0f};
  float psi = 0.0f;
  float v = 0.0f;
  float r = 0.0f;  // heading rate, + clockwise
  Vec2 cur{0.0f, 0.0f};
};

inline float bearing(Vec2 from, Vec2 to) { return compass(v_sub(to, from)); }
inline Vec2 right_of(Vec2 d) { return {d.y, -d.x}; }
inline Vec2 left_of(Vec2 d) { return {-d.y, d.x}; }

// Exponential filter coefficient for a time constant (s) at the tick rate.
inline float filt_a(float tau) { return DT / (tau + DT); }

}  // namespace ai_detail

struct AiSkippers::Boat {
  std::int32_t i = -1;
  AiLevel level = AiLevel::intermediate;
  AiLevelParams P;
  bool speed_only = false;
  bool autopilot_only = false;
  bool active = true;
  const AiPolar* pol = nullptr;

  // RNG draw counters per stream (ai.md §1), reset at race start.
  std::uint64_t k16 = 0, k17 = 0;

  // Perception (§3.3)
  bool init = false;
  float fx = 0.0f, fy = 0.0f;      // clean wind direction, 2 s (unit vector of the from direction)
  float rx = 0.0f, ry = 0.0f;      // 90 s: TWD_ref
  float sx = 0.0f, sy = 0.0f;      // 5 s
  float tws_f = 0.0f, tws_felt = 0.0f;
  float d_f = 0.0f;                // deficit, 2 s
  float twd_f = 0.0f, twd_ref = 0.0f, twd_5 = 0.0f, shift = 0.0f;

  // Manoeuvres (§10)
  ai_detail::Man man = ai_detail::Man::straight;
  float man_t0 = 0.0f;             // start time
  std::int8_t man_from = 1, man_to = 1;  // tack signs
  bool man_passed = false;         // the tack passed head to wind
  bool man_forced = false;
  float irons_t = 0.0f;
  float irons_until = -1e9f;
  float last_man = -1e9f;          // time of the last tack or gybe
  float low_until = -1e9f;         // entry speed build before a tack
  std::int8_t pend_tack = 0;       // a tack waiting for the speed build
  AiTactic pend_reason = AiTactic::None;
  std::int8_t turn_dir = 0;        // forced turn direction for loops (+1 clockwise), 0 = shortest

  // Strategy (§4)
  ai_detail::Leg leg = ai_detail::Leg::beat;
  std::int32_t leg_step = -1;
  bool speed_build = false;
  float headed_t = 0.0f, pressure_t = 0.0f;
  std::int32_t gate_step = -1, gate_buoy = 0;
  bool rounding = false;
  std::int32_t round_mark = -1;  // the mark of the last rounding decision

  // Start (§5)
  ai_detail::StartPhase phase = ai_detail::StartPhase::free;
  bool spot_fixed = false;
  float spot_u = 0.5f, spot_beta = 0.0f;
  bool drawn = false;
  float spread_r = 0.5f, e_start = 0.0f;
  bool go = false;
  bool loop = false;
  bool hover_fly = false;
  std::int32_t ret_stage = 0;
  std::int32_t match_stage = 0;

  // Rules (§7)
  float avoid_until = -1e9f, avoid_hold = -1e9f;
  float avoid_psi = 0.0f;
  bool avoid_slow = false;
  std::int32_t avoid_other = -1;
  AiTactic avoid_kind = AiTactic::KeepClear;

  // Bad air (§8)
  float bad_t = 0.0f;
  float foot_until = -1e9f, foot_delta = 0.0f;
  std::int32_t bad_src = -1;
  // Cover (§9)
  float opp_other_t = 0.0f;
  std::int32_t cover_opp = -1;
  std::int8_t opp_tack_prev = 0;
  float opp_tacked_at = -1e9f;
  // Penalty turns (§7.6)
  bool pen_on = false;
  float pen_t0 = 0.0f, pen_dir = 1.0f;
  bool pen_seen_turning = false;
  float pen_stall_t = 0.0f;
  std::int32_t pen_served0 = 0;
  // Sails (§6.2)
  float change_t = 0.0f;
  std::int32_t change_want = -2;

  // Outputs of the decision, applied by the helm every tick
  float psi_target = 0.0f;
  bool let_fly = false;
  float helm_fixed = NAN;          // a fixed helm (tacks, penalty turns, irons)
  bool forced = false;             // no rudder drag limit
  float r_limit = NAN;             // a turn rate limit (gybes)
  float h_int = 0.0f;              // integral of the turn rate error (weather helm)
  AiTactic tactic = AiTactic::None, prev_tactic = AiTactic::None;
  bool decided = false;

  // Telemetry
  AiTelemetry tel;
  AiDebug dbg;
  float slow_t = 0.0f;
  std::int32_t pen_seen = 0;       // penalties received already counted
  bool ocs_counted = false;
  std::int8_t tack_prev = 0;
};

struct AiSkippers::Ctx {
  World& w;
  const Race& race;
  const Rules& rules;
  const ResolvedCourse& course;
  std::uint32_t n = 0;
  float now = 0.0f;     // seconds since tick 0
  float t_race = 0.0f;  // race time (negative before the gun)
  bool created = false;
  std::vector<ShadowSource> snap;               // the other boats' shadows at t_n (built once per tick)
  std::vector<std::vector<const PairRecord*>> pairs_of;  // rules records per boat
  std::vector<float> r_hull;                    // bounding radius of each hull
  const std::vector<std::unique_ptr<AiSkippers::Boat>>* ai = nullptr;
};

}  // namespace wm
