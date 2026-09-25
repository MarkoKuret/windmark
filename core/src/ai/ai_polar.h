// The AI's polar tables (ai.md §3.1): per class, built once from the performance file's polar of every config, on a
// true wind speed grid of 0.25 m/s from 0 to 20 m/s. Lookups interpolate linearly in TWS.
#pragma once

#include <cstdint>
#include <vector>

#include "data/perf.h"

namespace wm {

class AiPolar {
 public:
  static constexpr float kTwsStep = 0.25f;
  static constexpr std::int32_t kTwsN = 81;  // 0 .. 20 m/s

  explicit AiPolar(const PerfData& perf);

  const PerfData& perf() const { return *perf_; }

  // Upwind optimum over 25°..90° and downwind optimum over 90°..180° (0.25° steps), best config.
  float theta_up(float tws) const { return lookup(theta_up_, tws); }
  float v_up(float tws) const { return lookup(v_up_, tws); }
  float theta_dn(float tws) const { return lookup(theta_dn_, tws); }
  float v_dn(float tws) const { return lookup(v_dn_, tws); }
  float vmg_up(float tws) const { return lookup(vmg_up_, tws); }
  float vmg_dn(float tws) const { return lookup(vmg_dn_, tws); }

  // Speed of the best config at (tws, |twa|) and its front sail (-1 = main only).
  float speed(float tws, float twa_abs) const;
  std::int32_t best_sail(float tws, float twa_abs) const;
  // The speed of the config driven by `front_sail`.
  float speed_with(float tws, float twa_abs, std::int32_t front_sail) const;

 private:
  float lookup(const std::vector<float>& t, float tws) const;

  const PerfData* perf_;
  std::vector<float> theta_up_, v_up_, theta_dn_, v_dn_, vmg_up_, vmg_dn_;
};

}  // namespace wm
