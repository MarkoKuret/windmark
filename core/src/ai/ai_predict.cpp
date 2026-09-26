#include "ai/ai_predict.h"

namespace wm::ai_detail {

namespace {
constexpr float kStep = 0.1f;
}

void predict_ctrv(const Motion& m, std::int32_t samples, Track& out) {
  const std::size_t n = static_cast<std::size_t>(samples) + 1;
  out.c.resize(n);
  out.psi.resize(n);
  Vec2 c = m.c;
  float psi = m.psi;
  out.c[0] = c;
  out.psi[0] = psi;
  for (std::size_t k = 1; k < n; ++k) {
    psi = wrap_2pi(psi + m.r * kStep);
    const Vec2 d = dir(psi);
    c = v_add(c, v_scale(v_add(v_scale(d, m.v), m.cur), kStep));
    out.c[k] = c;
    out.psi[k] = psi;
  }
}

void predict_plan(const Motion& m, const OwnPlan& p, std::int32_t samples, Track& out) {
  const std::size_t n = static_cast<std::size_t>(samples) + 1;
  out.c.resize(n);
  out.psi.resize(n);
  Vec2 c = m.c;
  float psi = m.psi;
  float v = m.v;
  out.c[0] = c;
  out.psi[0] = psi;
  bool reached = false;
  for (std::size_t k = 1; k < n; ++k) {
    const float t = static_cast<float>(k) * kStep;
    if (t > p.delay && !reached) {
      float e = wrap_pi(p.psi_to - psi);
      if (p.dir != 0 && sgn(e) != static_cast<float>(p.dir) && (e < 0.0f ? -e : e) > 0.05f) {
        e = e + static_cast<float>(p.dir) * TWO_PI;
      }
      const float rate = p.rate > 0.0f ? p.rate : m.r;
      const float step = rate * kStep;
      if ((e < 0.0f ? -e : e) <= step) {
        psi = p.psi_to;
        reached = true;
      } else {
        psi = wrap_2pi(psi + sgn(e) * step);
      }
    } else if (t <= p.delay) {
      psi = wrap_2pi(psi + m.r * kStep);
    }
    const float twa = wrap_pi(p.twd - psi);
    const bool no_go = (twa < 0.0f ? -twa : twa) < 30.0f * DEG;
    const bool no_drive = (p.slow && t > p.delay) || no_go;
    const float v_floor = no_go ? 0.0f : p.slow_floor;
    if (no_drive && v > v_floor) v = max(v_floor, v - (p.decel_linear * v + p.decel_const) * kStep);
    if (!no_drive && v < p.v_target) v = min(p.v_target, v + p.accel * kStep);
    const Vec2 d = dir(psi);
    c = v_add(c, v_scale(v_add(v_scale(d, v), m.cur), kStep));
    out.c[k] = c;
    out.psi[k] = psi;
  }
}

float tracks_gap(std::span<const Vec2> hull_a, float r_a, const Track& a, std::span<const Vec2> hull_b, float r_b,
                 const Track& b, std::int32_t k0, std::int32_t k1, float cap) {
  float best = cap;
  std::vector<Vec2> pa, pb;
  for (std::int32_t k = k0; k <= k1; ++k) {
    const std::size_t s = static_cast<std::size_t>(k);
    if (s >= a.c.size() || s >= b.c.size()) break;
    const float d = v_dist(a.c[s], b.c[s]) - r_a - r_b;
    if (d >= best) continue;
    place_outline(hull_a, a.c[s], a.psi[s], pa);
    place_outline(hull_b, b.c[s], b.psi[s], pb);
    const float g = convex_gap_capped(pa, pb, best);
    if (g < best) best = g;
    if (best <= 0.0f) return 0.0f;
  }
  return best;
}

}  // namespace wm::ai_detail
