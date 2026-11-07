// The C API's free sail course (courses.md §6.4): wm_world_lay_course lays the course without a race, the course
// readers answer, the boat is placed on the pre-start side, and wm_world_place_boat still works.
#include <string>

#include "doctest.h"
#include "windmark.h"

namespace {
const std::string kData = WINDMARK_DATA_DIR;
const std::string kCourses = WINDMARK_COURSES_DIR;
}  // namespace

TEST_CASE("capi: free sail lays a course without a race") {
  CHECK(wm_api_version() == 8);
  wm_venue* venue = nullptr;
  REQUIRE(wm_venue_load((kData + "/venues/practice_waters.venue.json").c_str(), &venue) == WM_OK);
  wm_perf* perf = nullptr;
  REQUIRE(wm_perf_load((kData + "/perf/wm7.perf.json").c_str(), &perf) == WM_OK);
  wm_course* course = nullptr;
  REQUIRE(wm_course_load((kCourses + "/practice_waters/example_wl.course.json").c_str(), &course) == WM_OK);
  wm_world_settings s;
  wm_world_settings_init(&s);
  s.race_seed = 9;
  wm_world* w = nullptr;
  REQUIRE(wm_world_create(&s, venue, &w) == WM_OK);
  wm_boat_entry e;
  wm_boat_entry_init(&e, perf);
  int32_t b = -1;
  REQUIRE(wm_world_add_boat(w, &e, &b) == WM_OK);
  wm_course_info ci{};
  CHECK(wm_world_course(w, &ci) == WM_ERR_STATE);
  CHECK(wm_world_has_course(w) == 0);

  REQUIRE(wm_world_lay_course(w, course) == WM_OK);
  CHECK(wm_world_has_course(w) == 1);
  CHECK(wm_world_has_race(w) == 0);
  REQUIRE(wm_world_course(w, &ci) == WM_OK);
  CHECK(ci.step_count >= 3);
  CHECK(ci.zone_lengths == doctest::Approx(3.0f));
  wm_step st{};
  REQUIRE(wm_world_course_step(w, 0, &st) == WM_OK);
  CHECK(st.kind == WM_STEP_START);
  wm_mark m{};
  REQUIRE(wm_world_course_mark(w, st.marks[0], &m) == WM_OK);
  CHECK(wm_world_lay_course(w, course) == WM_ERR_STATE);
  CHECK(wm_world_place_boat(w, b, m.x, m.y - 100.0f, 0.0f) == WM_OK);
  for (int k = 0; k < 20; ++k) wm_world_step(w);
  wm_race_info ri{};
  CHECK(wm_world_race(w, &ri) == WM_ERR_STATE);

  wm_world_free(w);
  wm_course_free(course);
  wm_perf_free(perf);
  wm_venue_free(venue);
}
