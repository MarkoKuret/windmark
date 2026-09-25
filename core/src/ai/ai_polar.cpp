#include "ai/ai_polar.h"

#include <cmath>

namespace wm {

AiPolar::AiPolar(const PerfData& perf) : perf_(&perf) {
  const std::size_t n = static_cast<std::size_t>(kTwsN);
  theta_up_.assign(n, 0.7f);
  v_up_.assign(n, 0.0f);
  theta_dn_.assign(n, 2.6f);
  v_dn_.assign(n, 0.0f);
  vmg_up_.assign(n, 0.0f);
  vmg_dn_.assign(n, 0.0f);
  for (std::size_t k = 0; k < n; ++k) {
    const float tws = static_cast<float>(k) * kTwsStep;
    float best_up = 0.0f, best_dn = 0.0f;
    // 25° .. 90° in 0.25° steps (260 steps), then 90° .. 180° (360 steps).
    for (std::int32_t s = 0; s <= 260; ++s) {
      const float twa = (25.0f + static_cast<float>(s) * 0.25f) * DEG;
      const float v = speed(tws, twa);
      const float vmg = v * wm_cos(twa);
      if (vmg > best_up) {
        best_up = vmg;
        theta_up_[k] = twa;
        v_up_[k] = v;
      }
    }
    for (std::int32_t s = 0; s <= 360; ++s) {
      const float twa = (90.0f + static_cast<float>(s) * 0.25f) * DEG;
      const float v = speed(tws, twa);
      const float vmg = -(v * wm_cos(twa));
      if (vmg > best_dn) {
        best_dn = vmg;
        theta_dn_[k] = twa;
        v_dn_[k] = v;
      }
    }
    vmg_up_[k] = best_up;
    vmg_dn_[k] = best_dn;
  }
  // Below the first row with any speed the angles are those of the first row that has one (a calm has no optimum).
  std::size_t first = 0;
  while (first < n && !(v_up_[first] > 0.0f)) ++first;
  if (first < n) {
    for (std::size_t k = 0; k < first; ++k) {
      theta_up_[k] = theta_up_[first];
      theta_dn_[k] = theta_dn_[first];
    }
  }
}

float AiPolar::lookup(const std::vector<float>& t, float tws) const {
  if (!(tws > 0.0f)) return t[0];
  const float x = tws / kTwsStep;
  const float fl = std::floor(x);
  const std::int32_t i = static_cast<std::int32_t>(fl);
  if (i >= kTwsN - 1) return t[static_cast<std::size_t>(kTwsN - 1)];
  const std::size_t k = static_cast<std::size_t>(i);
  return lerp(t[k], t[k + 1], x - fl);
}

float AiPolar::speed(float tws, float twa_abs) const {
  float best = 0.0f;
  for (const ConfigPerf& c : perf_->configs) best = max(best, c.polar.at(tws, twa_abs));
  return best;
}

std::int32_t AiPolar::best_sail(float tws, float twa_abs) const {
  float best = -1.0f;
  std::int32_t s = -1;
  for (const ConfigPerf& c : perf_->configs) {
    const float v = c.polar.at(tws, twa_abs);
    if (v > best) {
      best = v;
      s = c.front_sail;
    }
  }
  return s;
}

float AiPolar::speed_with(float tws, float twa_abs, std::int32_t front_sail) const {
  return perf_->config_for(front_sail)->polar.at(tws, twa_abs);
}

}  // namespace wm
