// Venue conditions and weather modes (race.md §2.1): the venue's typical weather (data_format.md §6.7), the race
// seed and the lobby's weather mode resolved once, when the race is created, into the wind, current and sea
// settings of wind.md §1 and sea.md §2. Nothing here runs per tick.
#pragma once

#include <cstdint>
#include <string>

#include "course/course.h"
#include "data/venue.h"
#include "race/race.h"
#include "sea/sea.h"
#include "wind/wind.h"

namespace wm {

enum class WeatherMode : std::uint8_t { local, random, custom };

// The lobby's or menu's choice. Custom reads speed, from, shift and puffs; a missing choice takes the venue's.
struct WeatherChoice {
  WeatherMode mode = WeatherMode::local;
  float speed = 7.2f;  // m/s
  float from = 0.0f;   // rad
  bool has_shift = false;
  ShiftPreset shift = ShiftPreset::shifty;
  bool has_puffs = false;
  PuffPreset puffs = PuffPreset::standard;
};

// The race's timing for the tide turn: T_race (the course's target duration, else 900 s) and t_gun (ms of
// environment time at the start signal). Free sailing: t_gun = 0, T_race = 900 s.
struct RaceTiming {
  float t_race_s = 900.0f;
  std::uint64_t t_gun_ms = 0;
};

// The timing of a race on `course` with settings `s` (course may be null: free sailing).
RaceTiming race_timing(const RaceSettings& s, const CourseData* course);

// race.md §2.1. Writes every wind and sea setting the conditions decide (the venue fields themselves are applied
// by apply_venue); the wind sea is left at 0 so the world grows it from base_speed and the venue fetch. A venue
// without conditions offers custom only (on the wind.md §1 and sea.md §2 defaults): local or random there is an
// error. Returns false with a reason.
bool resolve_weather(const VenueData& v, const WeatherChoice& c, std::uint64_t race_seed, const RaceTiming& timing,
                     WindSettings& wind, SeaSettings& sea, std::string& error);

}  // namespace wm
