// Rules geometry (rules.md §3.1, §3.5, §3.6, §7.4): the constant-turn motion model, predicted hull gaps, the turn
// test, the escape manoeuvres and the mark-room path. Pure kinematics on binary32; the physics is never run here.
#include <cmath>

#include "course/geometry.h"
#include "rules/rules.h"

namespace wm {

namespace {

constexpr float kSub = 0.1f;       // prediction sub-step, s
constexpr std::size_t kPred = 101;  // samples 0 .. 10 s

std::size_t samples(float H) { return static_cast<std::size_t>(std::lround(H / kSub)) + 1; }

float gap_capped(const Hull& a, Vec2 ca, float ra, const Hull& b, Vec2 cb, float rb, float cap) {
  const float lb = v_dist(ca, cb) - ra - rb;
  if (lb >= cap) return lb;
  return convex_gap_capped(a, b, cap);
}

}  // namespace

float Rules::margin(std::size_t a, std::size_t b) const {
  const float L = max(st_[a].L, st_[b].L);
  return max(p_.margin_min, p_.margin_coef * L);
}

// §3.1: ψ += r·0.1, c += (v·dir(ψ) + current)·0.1.
void Rules::predict(std::size_t i, const RulesBoatInput& in) {
  BoatState& s = st_[i];
  s.pred.resize(kPred);
  Pose p{in.pos, in.psi};
  s.pred[0] = p;
  for (std::size_t k = 1; k < kPred; ++k) {
    p.psi = p.psi + in.turn_rate * kSub;
    const Vec2 d = dir(p.psi);
    p.c = {p.c.x + (in.v * d.x + in.current.x) * kSub, p.c.y + (in.v * d.y + in.current.y) * kSub};
    s.pred[k] = p;
  }
  s.pred_hulls.resize(kPred);
  s.pred_placed.assign(kPred, 0);
  for (bool& v : s.man_valid) v = false;
}

// The manoeuvres of a boat do not depend on the other boat: computed once per tick over the longest horizon.
const std::vector<Rules::Pose>& Rules::manoeuvre_cached(std::size_t a, int kind) const {
  const BoatState& s = st_[a];
  if (!s.man_valid[kind]) {
    manoeuvre(a, kind, max(p_.room_horizon, p_.escape_h), s.man[kind]);
    s.man_valid[kind] = true;
  }
  return s.man[kind];
}

const Hull& Rules::pred_hull(std::size_t i, std::size_t k) const {
  const BoatState& s = st_[i];
  if (!s.pred_placed[k]) {
    place_hull(s.perf->dynamics.collision.outline, s.pred[k].c, s.pred[k].psi, s.pred_hulls[k]);
    s.pred_placed[k] = 1;
  }
  return s.pred_hulls[k];
}

// PredGap(A, B, H) (§3.1): the minimum hull gap over the samples 0, 0.1, …, H s. Values at or above `cap` are
// lower bounds only.
float Rules::pred_gap(std::size_t a, std::size_t b, float H, float cap) const {
  const std::size_t K = samples(H);
  float g = INFINITY;
  for (std::size_t k = 0; k < K && k < kPred; ++k) {
    const float x = gap_capped(pred_hull(a, k), st_[a].pred[k].c, st_[a].r_hull, pred_hull(b, k), st_[b].pred[k].c,
                               st_[b].r_hull, cap);
    g = min(g, x);
    if (g <= 0.0f) break;
  }
  return g;
}

float Rules::hull_gap(std::size_t i, std::size_t j) const { return convex_gap(st_[i].placed, st_[j].placed); }

// §3.5 turn test: B rotated by δ about her reference point then moved T_react on the rotated heading; A on her
// current motion. Hits = the hulls touch.
bool Rules::turn_test_hits(std::size_t a, std::size_t b, float delta) const {
  const RulesBoatInput& ib = in_[b];
  const std::size_t K = samples(p_.t_react);
  Hull hb;
  for (const float sgn : {1.0f, -1.0f}) {
    const float psi = ib.psi + sgn * delta;
    const Vec2 d = dir(psi);
    const Vec2 vel{ib.v * d.x + ib.current.x, ib.v * d.y + ib.current.y};
    for (std::size_t k = 0; k < K; ++k) {
      const float t = static_cast<float>(k) * kSub;
      const Vec2 c{ib.pos.x + vel.x * t, ib.pos.y + vel.y * t};
      place_hull(st_[b].perf->dynamics.collision.outline, c, psi, hb);
      const float g = gap_capped(pred_hull(a, k), st_[a].pred[k].c, st_[a].r_hull, hb, c, st_[b].r_hull, 0.5f);
      if (g <= 0.0f) return true;
    }
  }
  return false;
}

// §3.6 manoeuvres of boat a over H: 0 hold course, 1 full turn to port, 2 full turn to starboard, 3 slow down.
void Rules::manoeuvre(std::size_t a, int kind, float H, std::vector<Pose>& out) const {
  const std::size_t K = samples(H);
  out.resize(K);
  if (kind == 0) {
    for (std::size_t k = 0; k < K; ++k) out[k] = st_[a].pred[k];
    return;
  }
  const RulesBoatInput& in = in_[a];
  const Dynamics& d = st_[a].perf->dynamics;
  const float tack = st_[a].twa >= 0.0f ? 1.0f : -1.0f;
  const std::size_t react = samples(p_.escape_react) - 1;
  Pose p{in.pos, in.psi};
  float v = in.v, h = in.helm;
  const float target = kind == 1 ? -1.0f : 1.0f;
  const float v_floor = max(0.0f, in.let_fly_drive * in.v);  // what the let-fly sails still drive (§3.6)
  out[0] = p;
  for (std::size_t k = 1; k < K; ++k) {
    float rate = in.turn_rate;
    if (k > react) {
      if (kind == 3) {
        rate = 0.0f;
        if (v > v_floor) v = max(v_floor, v - (d.decel_linear * v + d.decel_const) * kSub);
      } else {
        const float step = d.helm_rate * kSub;
        h = h + clamp(target - h, -step, step);
        const float n = std::fabs(h);
        rate = 0.0f;
        if (n >= 1e-5f) {
          const float R = max(d.derived.turn_c / n - d.turn_radius_offset, 0.5f);
          rate = sgn(h) * (v / R);
        }
        const bool luff = sgn(h) == tack;
        const float drag = (luff ? d.rudder_drag_luff : d.rudder_drag_bear).at(std::fabs(v), n);
        v = max(0.0f, v - drag * kSub);
      }
    }
    p.psi = p.psi + rate * kSub;
    const Vec2 u = dir(p.psi);
    p.c = {p.c.x + (v * u.x + in.current.x) * kSub, p.c.y + (v * u.y + in.current.y) * kSub};
    out[k] = p;
  }
}

float Rules::poses_gap(std::size_t a, const std::vector<Pose>& pa, std::size_t b, const std::vector<Pose>& pb,
                       float cap) const {
  Hull ha, hb;
  float g = INFINITY;
  const std::size_t K = std::min(pa.size(), pb.size());
  for (std::size_t k = 0; k < K; ++k) {
    const float lb = v_dist(pa[k].c, pb[k].c) - st_[a].r_hull - st_[b].r_hull;
    float x = lb;
    if (lb < cap) {
      place_hull(st_[a].perf->dynamics.collision.outline, pa[k].c, pa[k].psi, ha);
      place_hull(st_[b].perf->dynamics.collision.outline, pb[k].c, pb[k].psi, hb);
      x = convex_gap_capped(ha, hb, cap);
    }
    g = min(g, x);
    if (g <= 0.0f) break;
  }
  return g;
}

// Escape(A, B, H): at least one manoeuvre of A keeps the hulls apart while B keeps her motion.
bool Rules::escape(std::size_t a, std::size_t b, float H) const {
  std::vector<Pose> pb(samples(H));
  for (std::size_t k = 0; k < pb.size(); ++k) pb[k] = st_[b].pred[k];
  for (int kind = 0; kind < 4; ++kind) {
    if (poses_gap(a, manoeuvre_cached(a, kind), b, pb, 0.5f) > 0.0f) return true;
  }
  return false;
}

// §7.4: can giver g keep the entitled boat's path free by one of her manoeuvres?
bool Rules::escape_room(std::size_t g, const std::vector<Pose>& e_path, std::size_t e, float H, float m) const {
  const std::size_t K = std::min(samples(H), e_path.size());
  const std::vector<Pose> ep(e_path.begin(), e_path.begin() + static_cast<std::ptrdiff_t>(K));
  for (int kind = 0; kind < 4; ++kind) {
    if (poses_gap(g, manoeuvre_cached(g, kind), e, ep, m + 0.5f) >= m) return true;
  }
  return false;
}

// §7.4 mark-room path: straight to the entry tangent of the rounding circle, around it in the rounding
// direction to the exit tangent towards the next reference point, then straight on.
void Rules::mark_room_path(std::size_t e, std::int32_t mark, Side side, Vec2 next_ref, std::vector<Vec2>& out) const {
  out.clear();
  const BoatState& s = st_[e];
  const Vec2 c = s.c;
  const Vec2 M = course_->marks[static_cast<std::size_t>(mark)].pos;
  float r_mark = course_->marks[static_cast<std::size_t>(mark)].radius;
  for (const CourseObject& o : course_->objects) {
    if (o.mark == mark) r_mark = o.r;
  }
  float rho = (r_mark + 0.5f * s.B) + 0.25f * s.L;
  const float d = v_dist(c, M);
  if (d < rho) rho = d;
  out.push_back(c);
  if (!(rho > 0.01f)) return;
  const float port = side == Side::port ? 1.0f : -1.0f;
  const float phi_c = wm_atan2(c.y - M.y, c.x - M.x);
  const float alpha = wm_acos(clamp(rho / d, -1.0f, 1.0f));
  const float th_in = phi_c + port * alpha;
  const float dn = v_dist(next_ref, M);
  const float phi_n = wm_atan2(next_ref.y - M.y, next_ref.x - M.x);
  const float alpha_n = dn > rho ? wm_acos(clamp(rho / dn, -1.0f, 1.0f)) : 0.0f;
  const float th_out = phi_n - port * alpha_n;
  const float sweep = port > 0.0f ? wrap_2pi(th_out - th_in) : wrap_2pi(th_in - th_out);
  const std::int32_t steps = static_cast<std::int32_t>(std::ceil(sweep / (10.0f * DEG)));
  for (std::int32_t k = 0; k <= steps; ++k) {
    const float a = th_in + port * sweep * (steps > 0 ? static_cast<float>(k) / static_cast<float>(steps) : 0.0f);
    const SinCos sc = wm_sincos(a);
    out.push_back({M.x + rho * sc.c, M.y + rho * sc.s});
  }
  const Vec2 last = out.back();
  const Vec2 u = v_unit(v_sub(next_ref, last), {0.0f, 1.0f});
  out.push_back({last.x + u.x * 60.0f, last.y + u.y * 60.0f});
}

// The entitled boat moved along a path at her current speed (at least 0.5 m/s), sampled every 0.1 s over H.
void Rules::along_path(std::size_t e, const std::vector<Vec2>& path, float H, std::vector<Pose>& out) const {
  const std::size_t K = samples(H);
  out.resize(K);
  const float v = max(in_[e].v, 0.5f);
  float psi = in_[e].psi;
  for (std::size_t k = 0; k < K; ++k) {
    float s = v * (static_cast<float>(k) * kSub);
    Vec2 p = path.empty() ? st_[e].c : path.front();
    for (std::size_t i = 1; i < path.size(); ++i) {
      const Vec2 dv = v_sub(path[i], path[i - 1]);
      const float l = v_len(dv);
      if (l > 1e-4f) psi = compass(dv);
      if (s <= l || i + 1 == path.size()) {
        const float f = l > 1e-4f ? min(s / l, 1.0f) : 0.0f;
        p = {path[i - 1].x + f * dv.x, path[i - 1].y + f * dv.y};
        break;
      }
      s = s - l;
    }
    out[k] = {p, psi};
  }
}

}  // namespace wm
