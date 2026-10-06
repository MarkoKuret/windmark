// The true wind over the race area and the water current (wind.md): base wind, persistent shifts, a small
// oscillation, drifting puffs and lulls, an optional venue field, and the current. Everything is a pure function
// of (race_seed, t_env_ms, position); the per-tick cache (WindField::advance) only saves work and gives the same
// bits as evaluating from scratch (WindField::at).
#pragma once

#include <cstdint>
#include <vector>

#include "math/wm_math.h"
#include "wind/grid.h"

namespace wm {

// §1 shift presets (shift_amplitude, shift_hold_max_ms).
enum class ShiftPreset : std::uint8_t { steady, stable, oscillating, shifty, unstable };

// §6.1
struct PuffParams {
  float tile = 1000.0f;  // m
  std::uint32_t puff_count = 5, lull_count = 5;
  float diameter_min = 200.0f, diameter_max = 300.0f;  // m
  float puff_strength_min = 0.3f, puff_strength_max = 0.5f;
  float lull_strength_min = 0.5f, lull_strength_max = 0.7f;
  std::uint32_t life_min_ms = 60000, life_max_ms = 120000;  // life_min_ms > 0
  float cap_up = 0.25f, cap_down = 0.4f;
};

// §8, data_format.md §6.2: per base direction (from N, NE, E, SE, S, SW, W, NW) a speed factor f >= 0 and a
// direction offset d (rad, + = veer) on one grid.
struct VenueWindField {
  Grid grid;
  std::vector<float> f[8];
  std::vector<float> d[8];
};

// §7, data_format.md §6.3: current at tide factor 1, m/s east/north; zero outside the grid.
struct VenueCurrentField {
  Grid grid;
  std::vector<float> vx, vy;
};

// §1. Defaults as in the spec; the shift block defaults to the `shifty` preset.
struct WindSettings {
  float base_speed = 7.2f;  // m/s at 10 m
  float base_from = 0.0f;   // rad, compass
  float shift_amplitude = 15.0f * DEG;
  std::uint32_t shift_hold_max_ms = 60000;
  std::uint32_t shift_hold_min_ms = 12000;
  float shift_trend_rate = 0.0f;  // rad/s
  float shift_trend_max = 0.35f;  // rad
  bool osc_enabled = false;
  float osc_amplitude = 0.0349f;  // rad
  float osc_time_scale = 17.0f;   // s
  bool puffs_enabled = true;
  PuffParams puffs;
  const VenueWindField* venue_wind_field = nullptr;  // optional, not owned; must outlive the WindField
  float current_speed = 0.0f;  // m/s
  float current_to = 0.0f;     // rad, compass
  const VenueCurrentField* venue_current_field = nullptr;  // optional, not owned
  float tide_scale = 0.0f;
  std::uint32_t tide_period_ms = 44712000;  // > 0
  std::uint32_t tide_phase_ms = 0;
};

// Sets shift_amplitude, shift_hold_max_ms and shift_hold_min_ms = max / 5 from a §1 preset.
void apply_shift_preset(WindSettings& s, ShiftPreset p);

// §6.1 puff presets; `none` switches puffs off and leaves the parameters.
enum class PuffPreset : std::uint8_t { none, light, standard, gusty };

// Sets puffs_enabled and the §6.1 parameters of a preset (keys a preset does not list keep the defaults).
void apply_puff_preset(WindSettings& s, PuffPreset p);

// Checks the settings the formulas divide by or index with. nullptr when valid, else a reason.
const char* check_wind_settings(const WindSettings& s);

// §4.2 one segment of the shift walk: a ramp from o_prev to o, then a hold.
struct ShiftSegment {
  std::uint32_t k = 0;
  std::int64_t start = 0;  // ms; int64 so a walk far past the uint32 clock never wraps
  std::uint32_t ramp = 0, hold = 0;  // ms
  float o_prev = 0.0f, o = 0.0f;     // rad
  std::int64_t end() const { return start + ramp + hold; }
};

// §6.2, §6.3: one live puff or lull at a time. Centres are not wrapped: the pattern repeats every `tile` in x
// and y, so a renderer draws the patch at (px + m·tile, py + n·tile) for the tiles it shows.
struct PuffPatch {
  std::uint32_t slot;  // j
  std::uint64_t generation;
  float px, py;  // m
  float R;       // radius, m
  float s;       // peak strength: + puff, - lull
  float e;       // envelope [0, 1]
  std::uint32_t age_ms, life_ms;
};

// The environment at one time: everything a per-point query needs (§2 "per-tick parts").
struct WindTick {
  std::uint32_t t = 0;
  float shift = 0.0f, trend = 0.0f, osc = 0.0f;  // §3 terms
  float dir_offset = 0.0f;                       // shift + trend + osc
  float global_from = 0.0f;                      // wrap_2pi(base_from + dir_offset)
  std::vector<PuffPatch> slots;                  // every slot in slot order (e may be 0)
};

struct WindSample {
  float speed;  // m/s
  float from;   // rad, compass
};

class WindField {
 public:
  // `s` must pass check_wind_settings.
  WindField(std::uint64_t race_seed, const WindSettings& s);

  const WindSettings& settings() const { return s_; }
  std::uint64_t seed() const { return seed_; }

  // Pure, from scratch (the shift walk restarts at k = 0).
  float shift(std::uint32_t t) const;
  float trend(std::uint32_t t) const;
  float osc(std::uint32_t t) const;
  float dir_offset(std::uint32_t t) const;
  float global_from(std::uint32_t t) const;
  WindTick at(std::uint32_t t) const;

  // Tick step 3: the same WindTick as at(t), using the cached shift segments and per-slot birth directions.
  // Cheapest when t grows; an earlier t restarts the walk and gives the same bits.
  const WindTick& advance(std::uint32_t t);
  const WindTick& current_tick() const { return tick_; }

  // §2 clean wind at a point for a tick (no shadows).
  WindSample wind_clean(const WindTick& tick, float x, float y) const;
  // §6.4 puff/lull factor at a point for a tick (1 when puffs are off).
  float puff_factor(const WindTick& tick, float x, float y) const;
  // §9 live patches (e >= 1e-4) of a tick, in slot order.
  std::vector<PuffPatch> puff_patches(const WindTick& tick) const;
  // §7 current at a point and time (m/s, east/north).
  Vec2 current(float x, float y, std::uint32_t t) const;

  // Walk access for tests and debug views: segment k of the shift walk, and the tick-cached one.
  ShiftSegment segment(std::uint32_t k) const;
  ShiftSegment next_segment(const ShiftSegment& prev) const;
  float shift_ramp_rate() const { return C_; }  // §4.1 C, rad/s
  float shift_bound() const { return B_; }       // §4.1 B, rad
  float shift_amp() const { return A_; }         // §4.1 A, rad
  std::uint32_t hold_min() const { return hmin_; }
  std::uint32_t hold_max() const { return hmax_; }

 private:
  struct Cursor {
    ShiftSegment seg;
    bool valid = false;
  };
  struct SlotCache {
    bool valid = false;
    std::uint64_t generation = 0;
    float cx, cy, R, s, fb, sb;  // spawn point, radius, strength, birth direction and drift speed
  };

  ShiftSegment make_segment(std::uint32_t k, float o_prev, std::int64_t start) const;
  ShiftSegment first_segment() const { return make_segment(0, 0.0f, 0); }
  float shift_on(Cursor& c, std::uint32_t t) const;
  float global_from_on(Cursor& c, std::uint32_t t) const;
  void fill_tick(WindTick& out, std::uint32_t t, Cursor& walk, Cursor& birth_walk, SlotCache* cache) const;
  float venue_lookup(float x, float y, float from, float& d) const;

  std::uint64_t seed_;
  WindSettings s_;
  bool shift_enabled_;
  float A_, B_, C_;
  std::uint32_t hmin_, hmax_;
  float osc_t0_;     // s, §5 random start
  float inv_tile_;   // 1 / puff_tile
  std::vector<std::uint32_t> life_, off_;  // §6.2 per slot

  Cursor walk_, birth_walk_;
  std::vector<SlotCache> slot_cache_;
  WindTick tick_;
};

}  // namespace wm
