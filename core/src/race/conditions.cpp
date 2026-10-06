#include "race/conditions.h"

#include <algorithm>
#include <vector>

#include "math/rng.h"

namespace wm {

namespace {

constexpr std::uint64_t kStream = 8;  // race.md §10: venue conditions draw

float u(std::uint64_t seed, std::uint64_t i) { return rng_unit(seed, kStream, i); }

template <typename T>
T pick(const std::vector<T>& list, std::uint64_t seed, std::uint64_t i) {
  const auto n = static_cast<std::uint32_t>(list.size());
  const auto k = static_cast<std::uint32_t>(u(seed, i) * static_cast<float>(n));
  return list[k < n - 1 ? k : n - 1];
}

}  // namespace

RaceTiming race_timing(const RaceSettings& s, const CourseData* course) {
  RaceTiming t;
  if (course == nullptr) return t;
  if (course->race.target_duration > 0.0f) t.t_race_s = course->race.target_duration;
  t.t_gun_ms = static_cast<std::uint64_t>(Race::gun_after_creation(s, course->race)) * DT_MS;
  return t;
}

bool resolve_weather(const VenueData& v, const WeatherChoice& c, std::uint64_t seed, const RaceTiming& timing,
                     WindSettings& wind, SeaSettings& sea, std::string& error) {
  if (!v.has_conditions && c.mode != WeatherMode::custom) {
    error = "venue " + v.id + " has no conditions: custom weather only";
    return false;
  }
  const VenueConditions d;  // a venue without conditions: the defaults (wind.md §1, sea.md §2)
  const VenueConditions& k = v.has_conditions ? v.conditions : d;
  WindSettings w;
  SeaSettings s;

  // wind speed and direction
  switch (c.mode) {
    case WeatherMode::local: {
      const float s0 = k.speed_min, s1 = k.speed_max;
      w.base_speed = s0 + (s1 - s0) * (0.5f * (u(seed, 0) + u(seed, 1)));
      w.base_from = wrap_2pi(k.from + k.from_spread * (2.0f * u(seed, 2) - 1.0f));
      break;
    }
    case WeatherMode::random: {
      const float r0 = k.r_speed_min, r1 = k.r_speed_max;
      w.base_speed = r0 + (r1 - r0) * u(seed, 4);
      w.base_from = wrap_2pi(k.from + k.r_from_spread * (2.0f * u(seed, 5) - 1.0f));
      break;
    }
    case WeatherMode::custom:
      w.base_speed = c.speed;
      w.base_from = wrap_2pi(c.from);
      break;
  }

  // shifts: size and pace from the mode; trend and oscillation the venue's in every mode
  if (c.mode == WeatherMode::random) apply_shift_preset(w, pick(k.r_shift, seed, 6));
  else if (c.mode == WeatherMode::custom && c.has_shift) apply_shift_preset(w, c.shift);
  else if (v.has_conditions) k.local_shift(w);
  else apply_shift_preset(w, ShiftPreset::shifty);
  w.shift_trend_rate = k.trend_rate;
  w.shift_trend_max = k.trend_max;
  w.osc_enabled = k.has_oscillation;
  if (k.has_oscillation) {
    w.osc_amplitude = k.osc_amplitude;
    w.osc_time_scale = k.osc_time_scale;
  }

  // puffs: a picked or chosen preset takes no venue overrides
  if (c.mode == WeatherMode::random) apply_puff_preset(w, pick(k.r_puffs, seed, 7));
  else if (c.mode == WeatherMode::custom && c.has_puffs) apply_puff_preset(w, c.puffs);
  else {
    w.puffs_enabled = k.puffs_enabled;
    w.puffs = k.puffs;
  }

  // current and tide
  w.current_speed = k.current_speed;
  w.current_to = k.current_to;
  if (k.has_tide) {
    // the race starts at a drawn point of the whole cycle, in every mode
    const std::uint64_t P = static_cast<std::uint64_t>(k.tide_period_s) * 1000u;
    const std::uint64_t phi = std::min(static_cast<std::uint64_t>(u(seed, 3) * static_cast<float>(P)), P - 1);
    w.tide_phase_ms = static_cast<std::uint32_t>((phi + P - (timing.t_gun_ms % P)) % P);
    w.tide_period_ms = static_cast<std::uint32_t>(P);
    w.tide_scale = k.tide_scale;
    if (c.mode == WeatherMode::random) {
      w.tide_scale = k.tide_scale * (k.r_tide_min + (k.r_tide_max - k.r_tide_min) * u(seed, 8));
    }
  }

  // sea: the wind sea grows from base_speed and the fetch in the world; swells and sea_scale the venue's
  s.swells = k.swells;
  if (c.mode == WeatherMode::random && !s.swells.empty()) {
    const float m = k.r_swell_min + (k.r_swell_max - k.r_swell_min) * u(seed, 9);
    for (WaveTrain& t : s.swells) t.hs = t.hs * m;
  }
  s.sea_scale = k.sea_scale;

  if (const char* why = check_wind_settings(w)) {
    error = std::string("wind: ") + why;
    return false;
  }
  if (const char* why = check_sea_settings(s)) {
    error = std::string("sea: ") + why;
    return false;
  }
  // keep what the caller set that the conditions do not decide (the venue fields, the exposure)
  w.venue_wind_field = wind.venue_wind_field;
  w.venue_current_field = wind.venue_current_field;
  s.exposure = sea.exposure;
  s.exposure_default = sea.exposure_default;
  s.wind_sea = WaveTrain{};
  wind = w;
  sea = s;
  return true;
}

}  // namespace wm
