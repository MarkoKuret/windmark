// Kinematic predictions for the AI (ai.md §7): hulls moved with constant turn rate and velocity (rules.md §3.1),
// candidate courses, tacks and the escape test the AI runs before it gains right of way (§7.3).
#pragma once

#include <cstdint>
#include <span>
#include <vector>

#include "ai/ai_internal.h"

namespace wm::ai_detail {

// One boat's predicted poses every 0.1 s, sample 0 = now.
struct Track {
  std::vector<Vec2> c;
  std::vector<float> psi;
};

// A boat on its current motion (rules.md §3.1).
void predict_ctrv(const Motion& m, std::int32_t samples, Track& out);

// Own boat turning at |v| / turn_radius_full to `psi_to` (the shorter way, or in `dir` if non-zero), then straight.
// `slow`: sails let fly, the speed decays with the deceleration law. Inside the no-go zone of `twd` (|twa| < 30°)
// the speed decays with the deceleration law.
struct OwnPlan {
  float psi_to = 0.0f;
  std::int8_t dir = 0;
  bool slow = false;
  float rate = 0.0f;     // turn rate, rad/s (0: |v| / turn_radius_full)
  float twd = 0.0f;
  float decel_linear = 0.0f, decel_const = 0.0f;
  float delay = 0.0f;    // s before acting (reaction)
  float v_target = 0.0f; // with sails drawing the speed grows towards this at `accel` (0: constant speed)
  float accel = 0.0f;
  float slow_floor = 0.0f; // `slow`: the speed the let-fly sails still drive (boat.md §9 let_fly_drive · v)
};
void predict_plan(const Motion& m, const OwnPlan& p, std::int32_t samples, Track& out);

// Minimum hull gap between two tracks over samples [k0, k1], using the bounding radii to skip far samples. Values at
// or above `cap` are not exact (the capped gap).
float tracks_gap(std::span<const Vec2> hull_a, float r_a, const Track& a, std::span<const Vec2> hull_b, float r_b,
                 const Track& b, std::int32_t k0, std::int32_t k1, float cap);

// The turning radius of a helm (boat.md §5.9 radius law).
inline float radius_for_helm(const Dynamics& d, float h) {
  const float n = h < 0.0f ? -h : h;
  if (n < 1e-5f) return 1e9f;
  return max((d.turn_radius_full + d.turn_radius_offset) / n - d.turn_radius_offset, 0.5f);
}

}  // namespace wm::ai_detail
