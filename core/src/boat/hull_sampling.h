// Sampling the sea under the hull (sea.md §5): mean height and the least-squares pitch and roll of the surface
// through the hull points.
#pragma once

#include <vector>

#include "boat/boat_env.h"
#include "data/perf.h"
#include "math/wm_math.h"

namespace wm {

struct HullPoints {
  std::vector<Vec2> p;  // body frame: x forward, y port
  float mx = 0.0f, my = 0.0f, sxx = 0.0f, syy = 0.0f;
};

struct HullSample {
  float hm = 0.0f;          // mean height, m
  float wave_pitch = 0.0f;  // rad, + = bow up
  float wave_roll = 0.0f;   // rad, + = starboard down
};

// sea.md §5.1: the file's points, or 8 points from lwl and bwl; then the means and spreads, sums in point order.
HullPoints make_hull_points(const Dynamics& d);

// sea.md §5.2. `sea == nullptr` is flat water (all zero).
HullSample sample_hull(const HullPoints& hp, const SeaSurface* sea, float pos_x, float pos_y, float psi);

}  // namespace wm
