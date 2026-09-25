// The water surface (sea.md): a wind sea and up to four swells as a sum of travelling cosines on the deep-water
// dispersion relation, scaled by a venue exposure grid. One height function serves the boats and the renderer.
#pragma once

#include <cstdint>
#include <vector>

#include "wind/grid.h"

#include "boat/boat_env.h"

namespace wm {

// §2 one wave train.
struct WaveTrain {
  float hs = 0.0f;    // significant height, m
  float tp = 0.0f;    // peak period, s
  float from = 0.0f;  // rad, compass: where the waves come from
};

// data_format.md §6.4
struct VenueExposure {
  Grid grid;
  std::vector<float> e;  // [0, 1]
};

// §2 sea-state settings, chosen by the race layer and sent with the seed.
struct SeaSettings {
  WaveTrain wind_sea;              // sea_hs, sea_tp, sea_from (default from: the wind's base_from)
  std::vector<WaveTrain> swells;   // at most kMaxSwells
  float sea_scale = 1.0f;          // 0 = flat water
  const VenueExposure* exposure = nullptr;  // optional, not owned; must outlive the SeaField
  float exposure_default = 1.0f;   // outside the exposure grid
  static constexpr std::uint32_t kMaxSwells = 4;
};

// nullptr when valid, else a reason.
const char* check_sea_settings(const SeaSettings& s);

// §2 fetch-limited growth law (server side, any precision): the wind sea for a base wind `U` (m/s) and a fetch
// `F` (m). Hs = 0 below 1 m/s.
WaveTrain wind_sea_from_wind(double U, double F, float from);

// §3.3, §7.1: one travelling component, as exported to renderers.
struct SeaComponent {
  float a;       // amplitude, m
  float kx, ky;  // wave vector, cycles per metre, pointing the way the wave travels
  float c;       // phase, cycles
  std::uint32_t T;  // period, ms
};

// Height and slope at a point for one time.
struct SeaSlope {
  float dx, dy;  // ∂η/∂x, ∂η/∂y (the gradient of E is ignored)
};

class SeaField;

// §4 the surface at one tick: d_i = c_i − (t mod T_i)/T_i per component. Evaluates sea_height(x, y) of that time.
class SeaTick final : public SeaSurface {
 public:
  SeaTick() = default;
  SeaTick(const SeaField* field, std::uint32_t t);

  std::uint32_t t() const { return t_; }
  float sea_height(float x, float y) const override;
  SeaSlope sea_slope(float x, float y) const;
  float exposure(float x, float y) const;

 private:
  const SeaField* field_ = nullptr;
  std::uint32_t t_ = 0;
  std::vector<float> d_;
};

class SeaField {
 public:
  // Builds the components once (§3), in construction order; `s` must pass check_sea_settings.
  SeaField(std::uint64_t race_seed, const SeaSettings& s);
  // A field from an explicit component list (tests, tools).
  SeaField(std::vector<SeaComponent> components, const VenueExposure* exposure, float exposure_default);

  const std::vector<SeaComponent>& components() const { return comps_; }
  const VenueExposure* exposure_grid() const { return exposure_; }
  float exposure_default() const { return exposure_default_; }
  // §6 E(x, y)
  float exposure(float x, float y) const;

  // Tick step 3: the surface at t.
  SeaTick at(std::uint32_t t) const { return SeaTick(this, t); }
  // Convenience: pure functions of (x, y, t).
  float sea_height(float x, float y, std::uint32_t t) const { return at(t).sea_height(x, y); }
  SeaSlope sea_slope(float x, float y, std::uint32_t t) const { return at(t).sea_slope(x, y); }

 private:
  std::vector<SeaComponent> comps_;
  const VenueExposure* exposure_ = nullptr;
  float exposure_default_ = 1.0f;
};

}  // namespace wm
