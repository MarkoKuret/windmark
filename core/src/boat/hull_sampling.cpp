#include "boat/hull_sampling.h"

namespace wm {

HullPoints make_hull_points(const Dynamics& d) {
  HullPoints hp;
  if (d.has_hull_points) {
    hp.p = d.hull_points;
  } else {
    const float l = d.lwl;
    const float b = d.bwl;
    hp.p = {{0.45f * l, 0.0f},         {-0.45f * l, 0.0f},        {0.25f * l, 0.35f * b},
            {0.25f * l, -0.35f * b},   {0.0f, 0.35f * b},         {0.0f, -0.35f * b},
            {-0.25f * l, 0.35f * b},   {-0.25f * l, -0.35f * b}};
  }
  const float n = static_cast<float>(hp.p.size());
  float sx = 0.0f, sy = 0.0f;
  for (const Vec2& q : hp.p) {
    sx = sx + q.x;
    sy = sy + q.y;
  }
  hp.mx = sx / n;
  hp.my = sy / n;
  for (const Vec2& q : hp.p) {
    hp.sxx = hp.sxx + (q.x - hp.mx) * (q.x - hp.mx);
    hp.syy = hp.syy + (q.y - hp.my) * (q.y - hp.my);
  }
  return hp;
}

HullSample sample_hull(const HullPoints& hp, const SeaSurface* sea, float pos_x, float pos_y, float psi) {
  HullSample out;
  if (sea == nullptr) return out;
  const SinCos sc = wm_sincos(psi);
  const float fx = sc.s, fy = sc.c;
  const float lx = -fy, ly = fx;
  const std::size_t n = hp.p.size();
  // At most a few dozen points; a fixed buffer keeps the tick free of allocations.
  constexpr std::size_t kMax = 64;
  float h[kMax];
  float sum = 0.0f;
  const std::size_t m = n < kMax ? n : kMax;
  for (std::size_t k = 0; k < m; ++k) {
    const Vec2 q = hp.p[k];
    const float wx = (pos_x + q.x * fx) + q.y * lx;
    const float wy = (pos_y + q.x * fy) + q.y * ly;
    h[k] = sea->sea_height(wx, wy);
    sum = sum + h[k];
  }
  out.hm = sum / static_cast<float>(m);
  float gx = 0.0f, gy = 0.0f;
  for (std::size_t k = 0; k < m; ++k) {
    gx = gx + (h[k] - out.hm) * (hp.p[k].x - hp.mx);
    gy = gy + (h[k] - out.hm) * (hp.p[k].y - hp.my);
  }
  out.wave_pitch = hp.sxx > 1e-6f ? wm_atan(gx / hp.sxx) : 0.0f;
  out.wave_roll = hp.syy > 1e-6f ? wm_atan(gy / hp.syy) : 0.0f;
  return out;
}

}  // namespace wm
