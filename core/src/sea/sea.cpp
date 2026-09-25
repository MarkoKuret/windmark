// sea.md, formulas evaluated as written: one rounding per operation, in the written order.
#include "sea/sea.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include "math/rng.h"
#include "math/wm_math.h"

namespace wm {

namespace {

constexpr std::uint64_t kWaves = static_cast<std::uint64_t>(RngStream::wave_phases);

// §3.1 wind sea
constexpr float kSeaR[10] = {0.75f, 0.85f, 0.95f, 1.05f, 1.18f, 1.35f, 1.6f, 1.95f, 2.4f, 3.0f};
constexpr float kSeaW[10] = {0.1621f, 0.2738f, 0.4766f, 0.5384f, 0.3616f,
                             0.3225f, 0.2765f, 0.2051f, 0.1433f, 0.0887f};
constexpr float kSeaO[10] = {0.0f, -25.0f, 20.0f, -10.0f, 35.0f, -40.0f, 12.0f, 45.0f, -30.0f, 5.0f};
// §3.2 swell
constexpr float kSwellR[3] = {0.92f, 1.0f, 1.08f};
constexpr float kSwellW[3] = {0.5f, 0.70710678f, 0.5f};
constexpr float kSwellO[3] = {-8.0f, 0.0f, 8.0f};

// §3.3 component `i` of a train; appended unless its amplitude is 0.
void add_component(std::vector<SeaComponent>& out, std::uint64_t seed, std::uint32_t i, const WaveTrain& tr,
                   float r, float w, float o_deg, float sea_scale) {
  const std::uint32_t T = std::max<std::uint32_t>(200u, static_cast<std::uint32_t>((tr.tp * 1000.0f) / r + 0.5f));
  const float w_ang = (TWO_PI * 1000.0f) / static_cast<float>(T);
  const float kap = ((w_ang * w_ang) / G) / TWO_PI;
  const float jitter = (rng_unit(seed, kWaves, 2ull * i + 1) - 0.5f) * (10.0f * DEG);
  const float dir = wrap_2pi(((tr.from + PI) + o_deg * DEG) + jitter);
  const SinCos sc = wm_sincos(dir);
  float a = ((tr.hs * 0.353553391f) * w) * sea_scale;
  a = min(a, 0.1f / (kap * TWO_PI));
  const float c = rng_unit(seed, kWaves, 2ull * i);
  if (a == 0.0f) return;
  out.push_back({a, kap * sc.s, kap * sc.c, c, T});
}

}  // namespace

const char* check_sea_settings(const SeaSettings& s) {
  if (s.swells.size() > SeaSettings::kMaxSwells) return "at most 4 swells";
  auto bad = [](const WaveTrain& t) {
    return !std::isfinite(t.hs) || !std::isfinite(t.tp) || !std::isfinite(t.from) || t.hs < 0.0f ||
           (t.hs > 0.0f && !(t.tp > 0.0f));
  };
  if (bad(s.wind_sea)) return "wind sea needs hs >= 0 and tp > 0";
  for (const WaveTrain& t : s.swells)
    if (bad(t)) return "swell needs hs >= 0 and tp > 0";
  if (!std::isfinite(s.sea_scale) || s.sea_scale < 0.0f) return "sea_scale must be >= 0";
  if (!std::isfinite(s.exposure_default) || s.exposure_default < 0.0f || s.exposure_default > 1.0f)
    return "exposure_default must be in [0, 1]";
  if (s.exposure) {
    if (const char* r = check_grid(s.exposure->grid, s.exposure->e)) return r;
    for (float e : s.exposure->e)
      if (e < 0.0f || e > 1.0f) return "exposure values must be in [0, 1]";
  }
  return nullptr;
}

WaveTrain wind_sea_from_wind(double U, double F, float from) {
  WaveTrain t;
  t.from = from;
  if (U < 1.0) return t;
  const double g = 9.81;
  const double chi = std::min(g * F / (U * U), 2.2e4);
  t.hs = static_cast<float>(0.0016 * std::sqrt(chi) * U * U / g);
  t.tp = static_cast<float>(0.286 * std::cbrt(chi) * U / g);
  return t;
}

SeaField::SeaField(std::uint64_t race_seed, const SeaSettings& s)
    : exposure_(s.exposure), exposure_default_(s.exposure_default) {
  for (std::uint32_t i = 0; i < 10; ++i)
    add_component(comps_, race_seed, i, s.wind_sea, kSeaR[i], kSeaW[i], kSeaO[i], s.sea_scale);
  for (std::uint32_t sw = 0; sw < s.swells.size(); ++sw)
    for (std::uint32_t m = 0; m < 3; ++m)
      add_component(comps_, race_seed, 10 + 3 * sw + m, s.swells[sw], kSwellR[m], kSwellW[m], kSwellO[m],
                    s.sea_scale);
}

SeaField::SeaField(std::vector<SeaComponent> components, const VenueExposure* exposure, float exposure_default)
    : comps_(std::move(components)), exposure_(exposure), exposure_default_(exposure_default) {}

// §6
float SeaField::exposure(float x, float y) const {
  if (!exposure_) return 1.0f;
  return grid_sample(exposure_->grid, exposure_->e, x, y, exposure_default_);
}

// §4 per-tick phases
SeaTick::SeaTick(const SeaField* field, std::uint32_t t) : field_(field), t_(t) {
  const std::vector<SeaComponent>& cs = field_->components();
  d_.resize(cs.size());
  for (std::size_t i = 0; i < cs.size(); ++i)
    d_[i] = cs[i].c - static_cast<float>(t % cs[i].T) / static_cast<float>(cs[i].T);
}

float SeaTick::exposure(float x, float y) const { return field_ ? field_->exposure(x, y) : 1.0f; }

// §4
float SeaTick::sea_height(float x, float y) const {
  if (!field_) return 0.0f;
  const std::vector<SeaComponent>& cs = field_->components();
  float sum = 0.0f;
  for (std::size_t i = 0; i < cs.size(); ++i) {
    const float c = ((cs[i].kx * x) + (cs[i].ky * y)) + d_[i];
    const float f = c - round_half_even(c);
    sum = sum + cs[i].a * wm_cos(TWO_PI * f);
  }
  return field_->exposure(x, y) * sum;
}

// §4 slope: ∂η/∂x = −E·Σ a_i·2π·kx_i·sin(2π f_i), likewise y.
SeaSlope SeaTick::sea_slope(float x, float y) const {
  if (!field_) return {0.0f, 0.0f};
  const std::vector<SeaComponent>& cs = field_->components();
  float sx = 0.0f, sy = 0.0f;
  for (std::size_t i = 0; i < cs.size(); ++i) {
    const float c = ((cs[i].kx * x) + (cs[i].ky * y)) + d_[i];
    const float f = c - round_half_even(c);
    const float s = wm_sin(TWO_PI * f);
    const float ak = cs[i].a * TWO_PI;
    sx = sx + (ak * cs[i].kx) * s;
    sy = sy + (ak * cs[i].ky) * s;
  }
  const float E = field_->exposure(x, y);
  return {-(E * sx), -(E * sy)};
}

}  // namespace wm
