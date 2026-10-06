// The C API path of the venue conditions (race.md §2.1): wm_world_settings_resolve, then wm_world_create on the
// resolved settings; wm_world_settings_init keeps the old defaults.
#include <string>

#include "doctest.h"
#include "math/wm_math.h"
#include "wind/wind.h"
#include "windmark.h"

namespace {
const std::string kData = WINDMARK_DATA_DIR;
constexpr float KN = 0.514444f;
}  // namespace

TEST_CASE("conditions: the C API resolves once and the world runs on the resolved settings") {
  wm_venue* venue = nullptr;
  REQUIRE(wm_venue_load((kData + "/venues/practice_waters.venue.json").c_str(), &venue) == WM_OK);
  wm_course* course = nullptr;
  REQUIRE(wm_course_load((std::string(WINDMARK_COURSES_DIR) + "/practice_waters/example_wl.course.json").c_str(),
                         &course) == WM_OK);
  // init keeps the old defaults: shifty, standard puffs, no tide, no swells
  wm_world_settings d;
  wm_world_settings_init(&d);
  const wm::WindSettings wd;
  CHECK(d.shift_amplitude == wd.shift_amplitude);
  CHECK(d.puff.cap_up == wd.puffs.cap_up);
  CHECK(d.tide_scale == 0.0f);
  CHECK(d.swell_count == 0);
  CHECK(d.weather == WM_WEATHER_LOCAL);

  wm_world_settings s;
  wm_world_settings_init(&s);
  s.race_seed = 1234;
  REQUIRE(wm_world_settings_resolve(&s, venue, course) == WM_OK);
  CHECK(s.wind_speed >= 10.0f * KN - 0.01f);
  CHECK(s.wind_speed <= 14.0f * KN + 0.01f);
  CHECK(s.shift_preset == WM_SHIFT_DEFAULT);
  CHECK(s.puff_preset == WM_PUFFS_DEFAULT);
  CHECK(s.shift_amplitude == doctest::Approx(3.0f * wm::DEG));
  CHECK(s.puff.cap_up == doctest::Approx(0.15f));
  wm_world* w = nullptr;
  REQUIRE(wm_world_create(&s, venue, &w) == WM_OK);
  wm_wind_state ws;
  REQUIRE(wm_world_wind_state(w, 0, &ws) == WM_OK);
  CHECK(ws.base_speed == s.wind_speed);
  wm_world_free(w);

  // custom: the player's wind and presets
  wm_world_settings_init(&s);
  s.weather = WM_WEATHER_CUSTOM;
  s.wind_speed = 9.0f;
  s.wind_from = 1.0f;
  s.shift_preset = WM_SHIFT_OSCILLATING;
  s.puff_preset = WM_PUFFS_NONE;
  REQUIRE(wm_world_settings_resolve(&s, venue, nullptr) == WM_OK);
  CHECK(s.wind_speed == 9.0f);
  CHECK(s.shift_amplitude == doctest::Approx(8.0f * wm::DEG));
  CHECK(s.puffs == 0);
  // a bad mode is refused
  s.weather = 7;
  CHECK(wm_world_settings_resolve(&s, venue, nullptr) == WM_ERR_ARG);
  wm_course_free(course);
  wm_venue_free(venue);
}

