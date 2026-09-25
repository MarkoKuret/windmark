// sea.md §8: statistics, dispersion, boat response, renderer parity; plus components, exposure and the growth law.
#include <cmath>
#include <string>
#include <vector>

#include "data/perf.h"
#include "doctest.h"
#include "env_scenarios.h"
#include "math/wm_math.h"
#include "sea/sea.h"
#include "test_util.h"

using wm_test::bits;

namespace {

// §5.2 as the boat step does it (boat.md §5.6): least-squares plane through the hull points.
struct HullResponse {
  float hm, pitch, roll;
};

HullResponse sample_hull(const wm::SeaTick& sea, const std::vector<wm::Vec2>& pts, float pos_x, float pos_y,
                         float psi) {
  const float n = static_cast<float>(pts.size());
  float mx = 0.0f, my = 0.0f;
  for (const wm::Vec2& p : pts) {
    mx = mx + p.x;
    my = my + p.y;
  }
  mx = mx / n;
  my = my / n;
  float sxx = 0.0f, syy = 0.0f;
  for (const wm::Vec2& p : pts) {
    sxx = sxx + (p.x - mx) * (p.x - mx);
    syy = syy + (p.y - my) * (p.y - my);
  }
  const wm::SinCos sc = wm::wm_sincos(psi);
  const float fx = sc.s, fy = sc.c, lx = -fy, ly = fx;
  std::vector<float> h;
  float sum = 0.0f;
  for (const wm::Vec2& p : pts) {
    const float wx = (pos_x + p.x * fx) + p.y * lx;
    const float wy = (pos_y + p.x * fy) + p.y * ly;
    h.push_back(sea.sea_height(wx, wy));
    sum = sum + h.back();
  }
  const float hm = sum / n;
  float gx = 0.0f, gy = 0.0f;
  for (std::size_t k = 0; k < pts.size(); ++k) {
    gx = gx + (h[k] - hm) * (pts[k].x - mx);
    gy = gy + (h[k] - hm) * (pts[k].y - my);
  }
  return {hm, sxx > 1e-6f ? wm::wm_atan(gx / sxx) : 0.0f, syy > 1e-6f ? wm::wm_atan(gy / syy) : 0.0f};
}

double frac(double x) { return x - std::floor(x); }
double D(float f) { return static_cast<double>(f); }

}  // namespace

TEST_CASE("§2 growth law reference values") {
  struct Row {
    double kn, fetch, hs, tp;
  };
  const Row rows[] = {{10, 10000, 0.26, 2.3}, {15, 10000, 0.39, 2.7}, {20, 10000, 0.53, 2.9},
                      {25, 10000, 0.66, 3.2}, {15, 30000, 0.68, 3.8}};
  for (const Row& r : rows) {
    CAPTURE(r.kn);
    const wm::WaveTrain t = wm::wind_sea_from_wind(r.kn * 1852.0 / 3600.0, r.fetch, 1.0f);
    CHECK(t.hs == doctest::Approx(r.hs).epsilon(0.03));
    CHECK(t.tp == doctest::Approx(r.tp).epsilon(0.05));
    CHECK(t.from == 1.0f);
  }
  CHECK(wm::wind_sea_from_wind(0.9, 10000, 0.0f).hs == 0.0f);
}

TEST_CASE("§3 components: order, periods, dispersion, steepness cap, zero trains dropped") {
  wm::SeaSettings s;
  s.wind_sea = {0.4f, 2.7f, 0.0f};  // from north: travels south
  s.swells.push_back({1.0f, 8.0f, wm::HALF_PI});
  const wm::SeaField f(3, s);
  REQUIRE(f.components().size() == 13);
  const float r[10] = {0.75f, 0.85f, 0.95f, 1.05f, 1.18f, 1.35f, 1.6f, 1.95f, 2.4f, 3.0f};
  double var = 0.0;
  for (int i = 0; i < 10; ++i) {
    const wm::SeaComponent& c = f.components()[static_cast<std::size_t>(i)];
    CHECK(c.T == static_cast<std::uint32_t>(2700.0f / r[i] + 0.5f));
    // Travelling roughly south (within the ±45° spread plus 5° jitter).
    CHECK(c.ky < 0.0f);
    CHECK(std::fabs(std::atan2(c.kx, -c.ky)) < 50.0 * 3.14159265 / 180.0);
    // Deep-water dispersion: k = ω²/g.
    const double w = 2.0 * 3.14159265358979 / (c.T * 0.001);
    CHECK(std::hypot(D(c.kx), D(c.ky)) * 2.0 * 3.14159265358979 == doctest::Approx(w * w / 9.81).epsilon(1e-5));
    CHECK(D(c.a) * std::hypot(D(c.kx), D(c.ky)) * 2.0 * 3.14159265358979 <= 0.1 + 1e-6);
    CHECK(c.c >= 0.0f);
    CHECK(c.c < 1.0f);
    var += 0.5 * D(c.a) * D(c.a);
  }
  CHECK(4.0 * std::sqrt(var) == doctest::Approx(0.4).epsilon(0.002));  // uncapped: Hs exactly
  for (int m = 0; m < 3; ++m) CHECK(f.components()[static_cast<std::size_t>(10 + m)].kx < 0.0f);  // from the east: travels west
  s.wind_sea.hs = 0.0f;
  CHECK(wm::SeaField(3, s).components().size() == 3);
  // The swell keeps its own component indices (10..12) for its random draws.
  for (int m = 0; m < 3; ++m)
    CHECK(bits(wm::SeaField(3, s).components()[static_cast<std::size_t>(m)].c) ==
          bits(f.components()[static_cast<std::size_t>(10 + m)].c));
  s.sea_scale = 0.0f;
  CHECK(wm::SeaField(3, s).components().empty());
  CHECK(wm::SeaField(3, s).sea_height(10.0f, 20.0f, 5000) == 0.0f);
  // A steep short train is capped.
  wm::SeaSettings steep;
  steep.wind_sea = {3.0f, 2.0f, 0.0f};
  for (const wm::SeaComponent& c : wm::SeaField(1, steep).components())
    CHECK(D(c.a) * std::hypot(D(c.kx), D(c.ky)) * 2.0 * 3.14159265358979 <= 0.1 + 1e-5);
}

TEST_CASE("§8.2 statistics: Hs within 5 % and mean within 1 cm over 1 km x 1 km and 10 minutes") {
  wm::SeaSettings s;
  s.wind_sea = {0.4f, 2.7f, 0.9f};
  const wm::SeaField f(11, s);
  for (const wm::SeaComponent& c : f.components())
    REQUIRE(D(c.a) * std::hypot(D(c.kx), D(c.ky)) * 2.0 * 3.14159265358979 < 0.1);  // uncapped train
  double sum = 0.0, sum2 = 0.0;
  long n = 0;
  for (std::uint32_t t = 0; t < 600000; t += 10050) {
    const wm::SeaTick st = f.at(t);
    for (int j = 0; j < 100; ++j)
      for (int i = 0; i < 100; ++i) {
        const double h = D(st.sea_height(10.03f * static_cast<float>(i), 10.07f * static_cast<float>(j)));
        sum += h;
        sum2 += h * h;
        ++n;
      }
  }
  const double mean = sum / n;
  const double hs = 4.0 * std::sqrt(sum2 / n - mean * mean);
  MESSAGE("Hs " << hs << " m, mean " << mean << " m over " << n << " samples");
  CHECK(hs == doctest::Approx(0.4).epsilon(0.05));
  CHECK(std::fabs(mean) < 0.01);
}

TEST_CASE("§8.3 dispersion: each crest moves G·T/(2π) m/s along its direction") {
  wm::SeaSettings s;
  s.wind_sea = {0.5f, 3.0f, 2.2f};
  s.swells.push_back({1.0f, 10.0f, 4.0f});
  const wm::SeaField all(5, s);
  for (const wm::SeaComponent& c : all.components()) {
    const wm::SeaField one({c}, nullptr, 1.0f);
    const double k = std::hypot(D(c.kx), D(c.ky));
    const double speed = 9.81 * (c.T * 0.001) / (2.0 * 3.14159265358979);  // m/s
    const double ux = D(c.kx) / k, uy = D(c.ky) / k;
    for (std::uint32_t dt : {1000u, 3000u}) {
      const double d = speed * dt * 0.001;
      const float h0 = one.sea_height(100.0f, -50.0f, 20000);
      const float h1 = one.sea_height(static_cast<float>(100.0 + ux * d), static_cast<float>(-50.0 + uy * d), 20000 + dt);
      CAPTURE(c.T);
      CHECK(h1 == doctest::Approx(h0).scale(c.a).epsilon(2e-3));
    }
  }
}

TEST_CASE("§8.4 boat response: an L-class boat pitches less than an S-class boat in a short chop") {
  wm::PerfData small, large;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_perf(std::string(WINDMARK_DATA_DIR) + "/perf/wm7.perf.json", small, err), err.message());
  REQUIRE_MESSAGE(wm::load_perf(std::string(WINDMARK_DATA_DIR) + "/perf/wm12.perf.json", large, err), err.message());
  REQUIRE(small.dynamics.lwl < large.dynamics.lwl);
  wm::SeaSettings s;
  s.wind_sea = {0.4f, 2.7f, 0.0f};
  const wm::SeaField f(13, s);
  double ps = 0.0, pl = 0.0, rs = 0.0, rl = 0.0;
  for (std::uint32_t t = 0; t < 120000; t += 50) {
    const wm::SeaTick st = f.at(t);
    const HullResponse a = sample_hull(st, small.dynamics.hull_points, 10.0f, 20.0f, 0.3f);
    const HullResponse b = sample_hull(st, large.dynamics.hull_points, 10.0f, 20.0f, 0.3f);
    ps += D(a.pitch) * D(a.pitch);
    pl += D(b.pitch) * D(b.pitch);
    rs += D(a.roll) * D(a.roll);
    rl += D(b.roll) * D(b.roll);
  }
  MESSAGE("rms pitch S " << std::sqrt(ps / 2400) << " rad, L " << std::sqrt(pl / 2400) << " rad");
  CHECK(pl < ps);
  CHECK(rl < rs);
}

TEST_CASE("§8.5 renderer parity: the double-precision §7.2 evaluation matches sea_height within 1 mm") {
  wm_env::Venue venue;
  for (const wm_env::SeaScenario& sc : wm_env::sea_scenarios(venue)) {
    CAPTURE(sc.name);
    const wm::SeaField f(sc.seed, sc.s);
    std::uint64_t n = 0;
    double worst = 0.0;
    for (int k = 0; k < 400; ++k, n += 4) {
      const float x = wm_env::in_range(-8000.0f, 8000.0f, 1000000 + n);
      const float y = wm_env::in_range(-8000.0f, 8000.0f, 1000001 + n);
      const std::uint32_t t = static_cast<std::uint32_t>(wm_env::in_range(0.0f, 1.0f, 1000002 + n) * 14400000.0f) / 50u * 50u;
      // Camera-relative origin near the point, as a renderer would use.
      const double ox = std::floor(D(x) / 64.0) * 64.0, oy = std::floor(D(y) / 64.0) * 64.0;
      const double t_r = t;
      double sum = 0.0;
      for (const wm::SeaComponent& c : f.components()) {
        const double dp = frac(D(c.c) - std::fmod(t_r, c.T) / c.T + D(c.kx) * ox + D(c.ky) * oy);
        const double xl = D(x) - ox, yl = D(y) - oy;
        sum += D(c.a) * std::cos(2.0 * 3.14159265358979323846 * frac(D(c.kx) * xl + D(c.ky) * yl + dp));
      }
      const double eta = D(f.exposure(x, y)) * sum;
      worst = std::fmax(worst, std::fabs(eta - D(f.sea_height(x, y, t))));
    }
    MESSAGE("largest renderer difference " << worst * 1000.0 << " mm");
    CHECK(worst < 0.001);
  }
}

TEST_CASE("§4 slope matches the height's finite difference") {
  wm::SeaSettings s;
  s.wind_sea = {0.6f, 3.5f, 1.3f};
  const wm::SeaField f(17, s);
  const wm::SeaTick st = f.at(123450);
  for (int i = 0; i < 50; ++i) {
    const float x = wm_env::in_range(-500.0f, 500.0f, 1100000 + 2 * i);
    const float y = wm_env::in_range(-500.0f, 500.0f, 1100001 + 2 * i);
    const wm::SeaSlope sl = st.sea_slope(x, y);
    const float e = 0.01f;
    const float gx = (st.sea_height(x + e, y) - st.sea_height(x - e, y)) / (2.0f * e);
    const float gy = (st.sea_height(x, y + e) - st.sea_height(x, y - e)) / (2.0f * e);
    CHECK(sl.dx == doctest::Approx(gx).scale(0.1).epsilon(0.02));
    CHECK(sl.dy == doctest::Approx(gy).scale(0.1).epsilon(0.02));
  }
}

TEST_CASE("§6 exposure scales the height; outside the grid the default; none is 1") {
  wm_env::Venue venue;
  wm::SeaSettings s;
  s.wind_sea = {0.5f, 3.0f, 0.0f};
  const wm::SeaField open(21, s);
  s.exposure = venue.exposure.get();
  s.exposure_default = 0.9f;
  REQUIRE(wm::check_sea_settings(s) == nullptr);
  const wm::SeaField sheltered(21, s);
  CHECK(open.exposure(0.0f, 0.0f) == 1.0f);
  CHECK(sheltered.exposure(-3000.0f, -2000.0f) == venue.exposure->e[0]);
  CHECK(sheltered.exposure(5000.0f, 0.0f) == 0.9f);
  const float x = -1234.0f, y = 567.0f;
  const std::uint32_t t = 60000;
  CHECK(bits(sheltered.sea_height(x, y, t)) == bits(sheltered.exposure(x, y) * (open.sea_height(x, y, t) / 1.0f)));
}

TEST_CASE("§4 the time phase is exact: whole periods later the surface repeats bit for bit") {
  wm::SeaSettings s;
  s.wind_sea = {0.4f, 2.7f, 0.5f};
  const wm::SeaField f(23, s);
  REQUIRE(f.components().size() == 10);
  // One component on its own repeats after its period, at any time.
  const wm::SeaComponent c = f.components()[3];
  const wm::SeaField one({c}, nullptr, 1.0f);
  for (std::uint32_t t : {0u, 1234550u, 14000000u})
    CHECK(bits(one.sea_height(700.0f, -300.0f, t)) == bits(one.sea_height(700.0f, -300.0f, t + 5 * c.T)));
}

TEST_CASE("sea settings checks") {
  wm::SeaSettings s;
  CHECK(wm::check_sea_settings(s) == nullptr);
  s.wind_sea = {0.5f, 0.0f, 0.0f};
  CHECK(wm::check_sea_settings(s) != nullptr);
  s = wm::SeaSettings{};
  for (int i = 0; i < 5; ++i) s.swells.push_back({0.2f, 5.0f, 0.0f});
  CHECK(wm::check_sea_settings(s) != nullptr);
}
