// The C API render queries at a fractional render time (wind.md §9 render time, sea.md §7.2): between two whole
// milliseconds they lie between the two whole-millisecond values, and at a whole millisecond they are those values.
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

#include "doctest.h"
#include "math/wm_math.h"
#include "windmark.h"

namespace {
const std::string kData = WINDMARK_DATA_DIR;

// m lies strictly between a and b (which differ).
template <class T>
bool strictly_between(T a, T m, T b) {
  return a != b && std::min(a, b) < m && m < std::max(a, b);
}
}  // namespace

TEST_CASE("render time: wind, current and sea queries resolve fractions of a millisecond") {
  wm_venue* venue = nullptr;
  REQUIRE(wm_venue_load((kData + "/venues/practice_waters.venue.json").c_str(), &venue) == WM_OK);
  wm_world_settings s;
  wm_world_settings_init(&s);
  s.race_seed = 77;
  s.shift_trend_rate = 0.01f;  // rad/s: the direction moves every millisecond
  s.shift_trend_max = 3.0f;  // not reached by n
  s.puffs = 1;
  s.tide_scale = 1.0f;
  s.tide_period_ms = 10000;  // a fast tide so the current moves every millisecond
  s.sea = 1;
  s.swell_count = 1;
  s.swells[0] = {1.0f, 6.0f, 1.0f};
  wm_world* w = nullptr;
  REQUIRE(wm_world_create(&s, venue, &w) == WM_OK);

  const std::uint32_t n = 123457;
  const double tn = n, tm = n + 0.5, t1 = n + 1.0;

  SUBCASE("sea height") {
    int checked = 0;
    for (float x = -400.0f; x <= 400.0f; x += 100.0f) {
      const float h0 = wm_world_sea_height_at(w, x, 50.0f, tn);
      const float h1 = wm_world_sea_height_at(w, x, 50.0f, t1);
      const float hm = wm_world_sea_height_at(w, x, 50.0f, tm);
      if (std::fabs(h1 - h0) < 1e-5f) continue;  // near a crest or trough the 1 ms step is below float rounding
      CHECK(strictly_between(h0, hm, h1));
      CHECK(std::fabs(hm - 0.5f * (h0 + h1)) <= 0.05f * std::fabs(h1 - h0) + 1e-6f);  // smooth over 1 ms
      ++checked;
    }
    CHECK(checked >= 5);
    // a quarter and three quarters keep their order
    const float q1 = wm_world_sea_height_at(w, 0.0f, 50.0f, n + 0.25);
    const float q3 = wm_world_sea_height_at(w, 0.0f, 50.0f, n + 0.75);
    const float h0 = wm_world_sea_height_at(w, 0.0f, 50.0f, tn);
    const float h1 = wm_world_sea_height_at(w, 0.0f, 50.0f, t1);
    CHECK((h1 - h0) * (q3 - q1) > 0.0f);
  }

  SUBCASE("current") {
    float c0x, c0y, cmx, cmy, c1x, c1y;
    REQUIRE(wm_world_current_at(w, 0.0f, 0.0f, tn, &c0x, &c0y) == WM_OK);
    REQUIRE(wm_world_current_at(w, 0.0f, 0.0f, tm, &cmx, &cmy) == WM_OK);
    REQUIRE(wm_world_current_at(w, 0.0f, 0.0f, t1, &c1x, &c1y) == WM_OK);
    CHECK(strictly_between(c0x, cmx, c1x));
  }

  SUBCASE("wind direction and puff patches") {
    wm_wind_state a, m, b;
    REQUIRE(wm_world_wind_state(w, tn, &a) == WM_OK);
    REQUIRE(wm_world_wind_state(w, tm, &m) == WM_OK);
    REQUIRE(wm_world_wind_state(w, t1, &b) == WM_OK);
    CHECK(strictly_between(0.0f, wm::angle_diff(m.global_from, a.global_from),
                           wm::angle_diff(b.global_from, a.global_from)));
    std::vector<wm_puff> p0(64), pm(64), p1(64);
    const int32_t k0 = wm_world_puffs_at(w, tn, p0.data(), 64);
    const int32_t km = wm_world_puffs_at(w, tm, pm.data(), 64);
    const int32_t k1 = wm_world_puffs_at(w, t1, p1.data(), 64);
    REQUIRE(k0 > 0);
    REQUIRE(k0 == km);
    REQUIRE(k0 == k1);
    int between = 0;  // a patch reborn in that millisecond keeps its earlier place
    for (int32_t i = 0; i < k0; ++i) {
      CHECK(pm[i].R == p0[i].R);
      if (strictly_between(p0[i].px, pm[i].px, p1[i].px) && strictly_between(p0[i].py, pm[i].py, p1[i].py))
        ++between;
    }
    CHECK(between >= k0 - 1);
  }

  SUBCASE("a whole millisecond is the tick value, NaN and negative times are 0") {
    for (int i = 0; i < 3; ++i) wm_world_step(w);
    const double t = wm_world_time_ms(w);
    CHECK(wm_world_sea_height_at(w, 30.0f, 40.0f, t) == wm_world_sea_height(w, 30.0f, 40.0f));
    float cx, cy, nx, ny;
    wm_world_current(w, 30.0f, 40.0f, &cx, &cy);
    wm_world_current_at(w, 30.0f, 40.0f, t, &nx, &ny);
    CHECK(cx == nx);
    CHECK(cy == ny);
    wm_wind_state z, q;
    wm_world_wind_state(w, 0.0, &z);
    wm_world_wind_state(w, -5.0, &q);
    CHECK(z.global_from == q.global_from);
    wm_world_wind_state(w, std::nan(""), &q);
    CHECK(z.global_from == q.global_from);
    CHECK(wm_world_sea_height_at(w, 30.0f, 40.0f, -1.0) == wm_world_sea_height_at(w, 30.0f, 40.0f, 0.0));
  }

  wm_world_free(w);
  wm_venue_free(venue);
}
