// Fixed environment scenarios shared by the environment tests and the env vector file writer
// (tools/gen_env_vectors.cpp): wind settings with and without a venue field, sea states, shadow sources.
// Inputs come from the RNG on private stream numbers (not simulation streams), so they are the same everywhere.
#pragma once

#include <cinttypes>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "math/rng.h"
#include "math/wm_math.h"
#include "sea/sea.h"
#include "shadow/shadow.h"
#include "state/checksum.h"
#include "wind/wind.h"

namespace wm_env {

constexpr std::uint64_t kSeed = 0x57494E444D41524Bull;
constexpr std::uint64_t kStream = 2000;  // test inputs only

inline std::uint32_t b(float f) {
  std::uint32_t u;
  std::memcpy(&u, &f, sizeof u);
  return u;
}

inline float in_range(float lo, float hi, std::uint64_t i) { return wm::rng_range(lo, hi, kSeed, kStream, i); }

// A synthetic venue: speed factors 0.6..1.2 and offsets ±10° inside, (1, 0) on the border nodes.
inline std::unique_ptr<wm::VenueWindField> make_venue_wind() {
  auto v = std::make_unique<wm::VenueWindField>();
  v->grid = {-1500.0f, -1000.0f, 100.0f, 125.0f, 31, 17};
  const std::uint32_t n = v->grid.node_count();
  for (int k = 0; k < 8; ++k) {
    v->f[k].resize(n);
    v->d[k].resize(n);
    for (std::uint32_t j = 0; j < v->grid.ny; ++j)
      for (std::uint32_t i = 0; i < v->grid.nx; ++i) {
        const std::uint32_t r = j * v->grid.nx + i;
        const bool border = i == 0 || j == 0 || i == v->grid.nx - 1 || j == v->grid.ny - 1;
        const std::uint64_t q = 100000ull * static_cast<std::uint64_t>(k) + 2ull * r;
        v->f[k][r] = border ? 1.0f : in_range(0.6f, 1.2f, q);
        v->d[k][r] = border ? 0.0f : in_range(-10.0f * wm::DEG, 10.0f * wm::DEG, q + 1);
      }
  }
  return v;
}

inline std::unique_ptr<wm::VenueCurrentField> make_venue_current() {
  auto c = std::make_unique<wm::VenueCurrentField>();
  c->grid = {-800.0f, -800.0f, 200.0f, 200.0f, 9, 9};
  const std::uint32_t n = c->grid.node_count();
  c->vx.resize(n);
  c->vy.resize(n);
  for (std::uint32_t r = 0; r < n; ++r) {
    c->vx[r] = in_range(-0.8f, 0.8f, 500000ull + 2ull * r);
    c->vy[r] = in_range(-0.8f, 0.8f, 500001ull + 2ull * r);
  }
  return c;
}

inline std::unique_ptr<wm::VenueExposure> make_exposure() {
  auto e = std::make_unique<wm::VenueExposure>();
  e->grid = {-3000.0f, -2000.0f, 250.0f, 250.0f, 13, 11};
  e->e.resize(e->grid.node_count());
  for (std::uint32_t r = 0; r < e->e.size(); ++r) e->e[r] = in_range(0.0f, 1.0f, 600000ull + r);
  return e;
}

// Owns the venue data a scenario points to.
struct Venue {
  std::unique_ptr<wm::VenueWindField> wind = make_venue_wind();
  std::unique_ptr<wm::VenueCurrentField> current = make_venue_current();
  std::unique_ptr<wm::VenueExposure> exposure = make_exposure();
};

struct WindScenario {
  const char* name;
  std::uint64_t seed;
  wm::WindSettings s;
};

inline std::vector<WindScenario> wind_scenarios(const Venue& v) {
  std::vector<WindScenario> out;
  {
    wm::WindSettings s;  // defaults: shifty, puffs
    s.base_from = 0.7f;
    out.push_back({"shifty", 1, s});
  }
  {
    wm::WindSettings s;
    wm::apply_shift_preset(s, wm::ShiftPreset::unstable);
    s.base_speed = 4.1f;
    s.base_from = 5.9f;
    s.osc_enabled = true;
    s.shift_trend_rate = 0.0002f;
    s.venue_wind_field = v.wind.get();
    s.current_speed = 0.4f;
    s.current_to = 2.0f;
    s.venue_current_field = v.current.get();
    s.tide_scale = 0.7f;
    s.tide_phase_ms = 3600000;
    out.push_back({"venue", 0xDEADBEEFCAFEull, s});
  }
  {
    wm::WindSettings s;
    wm::apply_shift_preset(s, wm::ShiftPreset::stable);
    s.base_speed = 11.0f;
    s.base_from = 3.1f;
    s.osc_enabled = true;
    s.shift_trend_rate = -0.0003f;
    s.puffs.tile = 700.0f;
    s.puffs.puff_count = 3;
    s.puffs.lull_count = 7;
    out.push_back({"stable", 0x0123456789ABCDEFull, s});
  }
  return out;
}

struct SeaScenario {
  const char* name;
  std::uint64_t seed;
  wm::SeaSettings s;
};

inline std::vector<SeaScenario> sea_scenarios(const Venue& v) {
  std::vector<SeaScenario> out;
  {
    wm::SeaSettings s;
    s.wind_sea = {0.4f, 2.7f, 0.3f};
    out.push_back({"chop", 7, s});
  }
  {
    wm::SeaSettings s;
    s.wind_sea = {0.68f, 3.8f, 4.0f};
    s.swells.push_back({1.2f, 9.0f, 2.0f});
    s.exposure = v.exposure.get();
    s.exposure_default = 0.9f;
    out.push_back({"open", 0xFEEDFACEull, s});
  }
  {
    wm::SeaSettings s;
    s.wind_sea = {0.26f, 2.3f, 1.0f};
    s.swells.push_back({0.5f, 6.0f, 5.5f});
    s.swells.push_back({0.3f, 11.0f, 0.2f});
    s.sea_scale = 0.5f;
    out.push_back({"mixed", 99, s});
  }
  return out;
}

inline wm::WindShadowParams shadow_params_s() {
  wm::WindShadowParams p{};
  p.height = 10.5f; p.ce_x = 0.1f; p.stern_x = -3.6f; p.chord = 6.5f;
  p.width_min = 4.0f; p.width_spinnaker = 7.0f;
  p.length_coef = 4.5f; p.length_knee = 4.12f;
  p.blanket_depth = 0.22f; p.blanket_depth_spinnaker = 0.25f; p.blanket_peak = 0.25f; p.blanket_near = 0.7f;
  p.blanket_reach_up = 0.05f; p.blanket_spread = 0.10f;
  p.turb_length = 0.4f; p.turb_depth = 0.15f; p.turb_width = 2.5f; p.turb_spread = 0.3f;
  p.turb_angle = 10.0f * wm::DEG; p.turb_awa_fade = 70.0f * wm::DEG; p.turb_awa_max = 75.0f * wm::DEG;
  p.header_coef = 0.4f; p.header_max = 3.0f * wm::DEG;
  return p;
}

// A snapshot source sailing at heading psi and speed v in a true wind (tws, twd_from), with its apparent wind
// from the wind triangle (flat water, no current).
inline wm::ShadowSource make_source(const wm::ShadowClass* cls, float x, float y, float psi, float v, float tws,
                                    float twd_from, bool spinnaker = false) {
  wm::ShadowSource s;
  s.cls = cls;
  s.pos_x = x;
  s.pos_y = y;
  s.psi = psi;
  const wm::Vec2 wd = wm::dir(twd_from);
  const wm::Vec2 hd = wm::dir(psi);
  const float ax = -tws * wd.x - v * hd.x;  // air relative to the boat, the way it blows
  const float ay = -tws * wd.y - v * hd.y;
  s.aws = std::sqrt(ax * ax + ay * ay);
  s.awd_from = wm::compass({-ax, -ay});
  s.awa = wm::wrap_pi(s.awd_from - psi);
  s.twa = wm::wrap_pi(twd_from - psi);
  s.spinnaker = spinnaker;
  return s;
}

// The env vector file lines (tests/vectors/env_vectors.txt).
inline std::vector<std::string> env_vector_lines() {
  std::vector<std::string> out;
  char buf[256];
  Venue venue;
  for (const WindScenario& sc : wind_scenarios(venue)) {
    wm::WindField w(sc.seed, sc.s);
    for (std::uint32_t k = 0; k < 100; ++k) {
      const std::uint32_t t = k * 36011u + (k % 7u) * 13u;
      const wm::WindTick& tick = w.advance(t);
      wm::Fnv1a64 h;
      for (int j = 0; j < 50; ++j)
        for (int i = 0; i < 50; ++i) {
          const float x = -2000.0f + 81.0f * static_cast<float>(i);
          const float y = -2000.0f + 81.0f * static_cast<float>(j);
          const wm::WindSample ws = w.wind_clean(tick, x, y);
          h.update_u32(b(ws.speed));
          h.update_u32(b(ws.from));
        }
      const wm::WindSample w0 = w.wind_clean(tick, 123.5f, -456.25f);
      const wm::Vec2 cu = w.current(123.5f, -456.25f, t);
      std::snprintf(buf, sizeof buf,
                    "wind %s %" PRIu32 " %08" PRIX32 " %016" PRIX64 " %08" PRIX32 " %08" PRIX32 " %08" PRIX32
                    " %08" PRIX32,
                    sc.name, t, b(tick.global_from), h.value(), b(w0.speed), b(w0.from), b(cu.x), b(cu.y));
      out.emplace_back(buf);
    }
  }
  std::uint64_t n = 0;
  for (const SeaScenario& sc : sea_scenarios(venue)) {
    wm::SeaField f(sc.seed, sc.s);
    for (int k = 0; k < 200; ++k, n += 3) {
      const float x = in_range(-8000.0f, 8000.0f, 700000 + n);
      const float y = in_range(-8000.0f, 8000.0f, 700001 + n);
      const std::uint32_t t = static_cast<std::uint32_t>(in_range(0.0f, 1.0f, 700002 + n) * 14400000.0f) / 50u * 50u;
      const wm::SeaTick st = f.at(t);
      const wm::SeaSlope sl = st.sea_slope(x, y);
      std::snprintf(buf, sizeof buf, "sea %s %08" PRIX32 " %08" PRIX32 " %" PRIu32 " %08" PRIX32 " %08" PRIX32 " %08" PRIX32,
                    sc.name, b(x), b(y), t, b(st.sea_height(x, y)), b(sl.dx), b(sl.dy));
      out.emplace_back(buf);
    }
  }
  const wm::ShadowClass cls = wm::make_shadow_class(shadow_params_s());
  for (int k = 0; k < 300; ++k, n += 7) {
    const float psi = in_range(0.0f, wm::TWO_PI, 800000 + n);
    const float tws = in_range(1.0f, 12.0f, 800001 + n);
    const float v = in_range(0.0f, 5.0f, 800002 + n);
    const bool spin = k % 3 == 0;
    const wm::ShadowSource s = make_source(&cls, 10.0f, -20.0f, psi, v, tws, 0.4f, spin);
    // Points concentrated near the source so most land in a zone.
    const float px = 10.0f + in_range(-40.0f, 40.0f, 800003 + n);
    const float py = -20.0f + in_range(-40.0f, 40.0f, 800004 + n);
    const wm::ShadowLoss l = wm::shadow(s, px, py);
    std::snprintf(buf, sizeof buf,
                  "shadow %08" PRIX32 " %08" PRIX32 " %08" PRIX32 " %08" PRIX32 " %08" PRIX32 " %08" PRIX32 " %08" PRIX32,
                  b(psi), b(tws), b(v), b(px), b(py), b(l.l), b(l.delta));
    out.emplace_back(buf);
  }
  return out;
}

}  // namespace wm_env
