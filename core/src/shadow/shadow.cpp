// wind_shadow.md, formulas evaluated as written: one rounding per operation, in the written order; products of
// three factors associate left to right.
#include "shadow/shadow.h"

#include <cmath>

namespace wm {

ShadowClass make_shadow_class(const WindShadowParams& p) {
  const SinCos sc = wm_sincos(p.turb_angle);
  return {p, sc.c, sc.s};
}

float shadow_blanket_length(const ShadowClass& c, float aws) {
  return ((c.p.height * c.p.length_coef) * (aws / (aws + c.p.length_knee)));
}

float shadow_p_long(const WindShadowParams& p, float s) {
  if (s <= -p.blanket_reach_up || s >= 1.0f) return 0.0f;
  if (s < 0.0f) return p.blanket_near * (1.0f + s / p.blanket_reach_up);
  if (s < p.blanket_peak) {
    const float r = s / p.blanket_peak;
    return p.blanket_near + (1.0f - p.blanket_near) * (r * (2.0f - r));
  }
  const float u = (s - p.blanket_peak) / (1.0f - p.blanket_peak);
  return (1.0f - u * u) * (1.0f - u * u);
}

float shadow_p_lat(float q) {
  if (q >= 1.0f) return 0.0f;
  return (1.0f - q * q) * (1.0f - q * q);
}

ShadowLoss shadow(const ShadowSource& B, float px, float py) {
  if (!B.casts || !B.cls) return {0.0f, 0.0f};
  const WindShadowParams& p = B.cls->p;
  const SinCos aw = wm_sincos(B.awd_from);
  const float ax = -aw.s, ay = -aw.c;  // toward where the apparent wind blows
  const float nx = ay, ny = -ax;
  const SinCos hd = wm_sincos(B.psi);
  const float fx = hd.s, fy = hd.c;
  const float aws = B.aws;
  const float Lb = shadow_blanket_length(*B.cls, aws);
  if (Lb < 1.0f) return {0.0f, 0.0f};
  const float cx = B.pos_x + p.ce_x * fx, cy = B.pos_y + p.ce_x * fy;
  const float dx = px - cx, dy = py - cy;
  const float far = 1.25f * Lb + p.width_spinnaker;
  if (dx * dx + dy * dy > far * far) return {0.0f, 0.0f};

  // blanket
  const float xi = dx * ax + dy * ay;
  const float eta = dx * nx + dy * ny;
  const float wsrc = max(p.chord * std::fabs(wm_sin(B.awa)), B.spinnaker ? p.width_spinnaker : p.width_min);
  const float W = 0.5f * wsrc + max(xi, 0.0f) * p.blanket_spread;
  const float s = xi / Lb;
  const float lb = ((B.spinnaker ? p.blanket_depth_spinnaker : p.blanket_depth) * shadow_p_long(p, s)) *
                   shadow_p_lat(std::fabs(eta) / W);

  // backwind
  float lt = 0.0f;
  const float aa = std::fabs(B.awa);
  if (aa < p.turb_awa_max) {
    const float fade = aa <= p.turb_awa_fade ? 1.0f : (p.turb_awa_max - aa) / (p.turb_awa_max - p.turb_awa_fade);
    const float tk = sgn(B.twa);
    const float ca = B.cls->turb_ca, sa = B.cls->turb_sa;
    const float wx = (-ca * fx) + (tk * sa) * fy;
    const float wy = (-ca * fy) - (tk * sa) * fx;
    const float tx = px - (B.pos_x + p.stern_x * fx);
    const float ty = py - (B.pos_y + p.stern_x * fy);
    const float xt = tx * wx + ty * wy;
    const float et = tx * wy - ty * wx;
    const float Lt = p.turb_length * Lb;
    if (xt > 0.0f && xt < Lt) {
      const float st = xt / Lt;
      const float q = 1.0f - st * st;
      lt = ((p.turb_depth * fade) * (q * q)) * shadow_p_lat(std::fabs(et) / (p.turb_width + xt * p.turb_spread));
    }
  }

  const float l = max(lb, lt);
  const float delta = min(p.header_coef * l, p.header_max);
  return {l, delta};
}

ShadowedWind shadowed_wind(std::span<const ShadowSource> snapshot, std::int32_t self, float x, float y, float U,
                           float from) {
  float best_l = 0.0f, best_d = 0.0f, best_tack = 1.0f;
  std::int32_t best = -1;
  for (std::size_t j = 0; j < snapshot.size(); ++j) {
    if (static_cast<std::int32_t>(j) == self) continue;
    const ShadowLoss s = shadow(snapshot[j], x, y);
    if (s.l > best_l) {
      best_l = s.l;
      best_d = s.delta;
      best_tack = sgn(snapshot[j].twa);
      best = static_cast<std::int32_t>(j);
    }
  }
  return {U * (1.0f - best_l), wrap_2pi(from - best_tack * best_d), best_l, best_d, best};
}

ShadowZones shadow_zones(const ShadowSource& B, std::uint32_t samples) {
  ShadowZones z;
  if (!B.cls || samples < 2) return z;
  const WindShadowParams& p = B.cls->p;
  const SinCos aw = wm_sincos(B.awd_from);
  const float ax = -aw.s, ay = -aw.c;
  const float nx = ay, ny = -ax;
  const SinCos hd = wm_sincos(B.psi);
  const float fx = hd.s, fy = hd.c;
  z.Lb = shadow_blanket_length(*B.cls, B.aws);
  if (!B.casts || z.Lb < 1.0f) {
    z.Lb = 0.0f;
    return z;
  }
  const float cx = B.pos_x + p.ce_x * fx, cy = B.pos_y + p.ce_x * fy;
  const float wsrc = max(p.chord * std::fabs(wm_sin(B.awa)), B.spinnaker ? p.width_spinnaker : p.width_min);
  const float x0 = -p.blanket_reach_up * z.Lb;
  for (std::uint32_t k = 0; k < samples; ++k) {
    const float xi = x0 + (z.Lb - x0) * (static_cast<float>(k) / static_cast<float>(samples - 1));
    const float W = 0.5f * wsrc + max(xi, 0.0f) * p.blanket_spread;
    const float bx = cx + xi * ax, by = cy + xi * ay;
    z.blanket_left.push_back({bx + W * nx, by + W * ny});
    z.blanket_right.push_back({bx - W * nx, by - W * ny});
  }
  if (std::fabs(B.awa) < p.turb_awa_max) {
    const float tk = sgn(B.twa);
    const float ca = B.cls->turb_ca, sa = B.cls->turb_sa;
    const float wx = (-ca * fx) + (tk * sa) * fy;
    const float wy = (-ca * fy) - (tk * sa) * fx;
    const float sx = B.pos_x + p.stern_x * fx, sy = B.pos_y + p.stern_x * fy;
    z.Lt = p.turb_length * z.Lb;
    // Across-band unit vector of §4's et = tx*wy - ty*wx: (wy, -wx).
    for (std::uint32_t k = 0; k < samples; ++k) {
      const float xt = z.Lt * (static_cast<float>(k) / static_cast<float>(samples - 1));
      const float w = p.turb_width + xt * p.turb_spread;
      const float bx = sx + xt * wx, by = sy + xt * wy;
      z.backwind_left.push_back({bx + w * wy, by - w * wx});
      z.backwind_right.push_back({bx - w * wy, by + w * wx});
    }
  }
  return z;
}

}  // namespace wm
