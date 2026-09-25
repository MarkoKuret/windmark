// wind.md §10: shift statistics, continuity, puffs, the per-tick cache; plus the venue field, the grid sampler
// and the current.
#include <cmath>
#include <vector>

#include "doctest.h"
#include "env_scenarios.h"
#include "math/rng.h"
#include "test_util.h"
#include "wind/grid.h"
#include "wind/wind.h"

using wm_test::bits;

namespace {

wm::WindSettings shifty() {
  wm::WindSettings s;
  wm::apply_shift_preset(s, wm::ShiftPreset::shifty);
  return s;
}

}  // namespace

TEST_CASE("§1 presets and §4.1 reference ramp rates") {
  wm::WindSettings s;
  CHECK(s.shift_amplitude == 15.0f * wm::DEG);  // default is shifty
  CHECK(s.shift_hold_max_ms == 60000);
  CHECK(s.shift_hold_min_ms == 12000);
  wm::apply_shift_preset(s, wm::ShiftPreset::stable);
  CHECK(wm::WindField(1, s).shift_ramp_rate() == doctest::Approx(0.02).epsilon(0.02));
  CHECK(s.shift_hold_max_ms == 120000);
  CHECK(s.shift_hold_min_ms == 24000);
  wm::apply_shift_preset(s, wm::ShiftPreset::shifty);
  CHECK(wm::WindField(1, s).shift_ramp_rate() == doctest::Approx(0.055).epsilon(0.02));
  wm::apply_shift_preset(s, wm::ShiftPreset::unstable);
  CHECK(wm::WindField(1, s).shift_ramp_rate() == doctest::Approx(0.13).epsilon(0.02));
  wm::apply_shift_preset(s, wm::ShiftPreset::steady);
  const wm::WindField steady(1, s);
  for (std::uint32_t t = 0; t < 3600000; t += 60050) CHECK(steady.shift(t) == 0.0f);
}

TEST_CASE("§10.2 shift statistics over 1e5 segments (shifty)") {
  const wm::WindField w(0xC0FFEE, shifty());
  const float A = w.shift_amp(), B = w.shift_bound();
  const std::uint32_t hmin = w.hold_min(), hmax = w.hold_max();
  constexpr int kN = 100000, kBins = 10;
  int bins[kBins] = {};
  double sum = 0.0;
  float lo = 0.0f, hi = 0.0f;
  int small_steps = 0, big_steps = 0, toward = 0, away = 0;
  wm::ShiftSegment seg = w.segment(0);
  CHECK(seg.start == 0);
  CHECK(seg.o_prev == 0.0f);
  for (int k = 0; k < kN; ++k) {
    REQUIRE(seg.k == static_cast<std::uint32_t>(k));
    REQUIRE(seg.o >= -B);
    REQUIRE(seg.o <= B);
    REQUIRE(seg.hold >= hmin);
    REQUIRE(seg.hold <= hmax);
    sum += static_cast<double>(seg.o);
    lo = std::fmin(lo, seg.o);
    hi = std::fmax(hi, seg.o);
    ++bins[std::min<std::uint32_t>((seg.hold - hmin) * kBins / (hmax - hmin + 1), kBins - 1)];
    // Steps lie between 0.2 A and A unless the bound cut them.
    const float step = std::fabs(seg.o - seg.o_prev);
    const bool clipped = seg.o == B || seg.o == -B;
    if (!clipped) {
      if (step < 0.2f * A * 0.9999f) ++small_steps;
      if (step > A * 1.0001f) ++big_steps;
    }
    if (std::fabs(seg.o_prev) > A) (std::fabs(seg.o) < std::fabs(seg.o_prev) ? toward : away)++;
    // The ramp takes |step| / C.
    CHECK(seg.ramp == static_cast<std::uint32_t>((step / w.shift_ramp_rate()) * 1000.0f + 0.5f));
    const wm::ShiftSegment next = w.next_segment(seg);
    REQUIRE(next.start == seg.start + seg.ramp + seg.hold);
    seg = next;
  }
  const double mean = sum / kN;
  MESSAGE("mean " << mean / static_cast<double>(A) << " A, range [" << lo / A << ", " << hi / A << "] A");
  CHECK(std::fabs(mean) < 0.05 * static_cast<double>(A));
  CHECK(small_steps == 0);
  CHECK(big_steps == 0);
  CHECK(toward > 2 * away);  // mean reversion beyond one amplitude
  CHECK(hi > A);             // the walk does run to the side
  CHECK(lo < -A);
  // Uniform hold times: each bin within 4 % of kN / kBins (sd about 1 %).
  for (int i = 0; i < kBins; ++i) {
    CAPTURE(i);
    CHECK(std::abs(bins[i] - kN / kBins) < kN / kBins / 25);
  }
}

TEST_CASE("§4.3 shift evaluation: ramps then plateaus, segment boundaries") {
  const wm::WindField w(5, shifty());
  wm::ShiftSegment seg = w.segment(0);
  for (int k = 0; k < 50; ++k) {
    const auto t0 = static_cast<std::uint32_t>(seg.start);
    CHECK(w.shift(t0) == seg.o_prev);  // ramp starts at the previous plateau
    const auto th = static_cast<std::uint32_t>(seg.start + seg.ramp);
    CHECK(w.shift(th) == seg.o);  // plateau from the end of the ramp
    CHECK(w.shift(static_cast<std::uint32_t>(seg.end() - 1)) == seg.o);
    if (seg.ramp > 2) {
      const float mid = w.shift(t0 + seg.ramp / 2);
      CHECK(mid == doctest::Approx(0.5f * (seg.o_prev + seg.o)).epsilon(0.01).scale(0.001));
    }
    seg = w.next_segment(seg);
  }
}

TEST_CASE("§10.3 continuity: global_from moves at most C·DT per tick with the oscillation off") {
  for (const wm::ShiftPreset p : {wm::ShiftPreset::stable, wm::ShiftPreset::shifty, wm::ShiftPreset::unstable}) {
    wm::WindSettings s;
    wm::apply_shift_preset(s, p);
    s.base_from = 6.2f;  // near the wrap
    wm::WindField w(77, s);
    const float lim = w.shift_ramp_rate() * wm::DT;
    float prev = w.advance(0).global_from;
    float worst = 0.0f;
    for (std::uint32_t t = 50; t <= 7200000; t += 50) {
      const float g = w.advance(t).global_from;
      worst = std::fmax(worst, std::fabs(wm::angle_diff(g, prev)));
      prev = g;
    }
    MESSAGE("largest step " << worst << " rad, C*DT = " << lim);
    // Ramps last a whole number of ms (§4.2 rounds |step| / C), so the rate can exceed C by half a millisecond's
    // worth: the bound is C·(DT + 0.5 ms), plus float rounding.
    CHECK(worst <= w.shift_ramp_rate() * (wm::DT + 0.0005f) + 1e-6f);
  }
}

TEST_CASE("§3 trend and §5 oscillation") {
  wm::WindSettings s = shifty();
  s.shift_trend_rate = 0.001f;
  s.shift_trend_max = 0.35f;
  s.osc_enabled = true;
  const wm::WindField w(3, s);
  CHECK(w.trend(0) == 0.0f);
  CHECK(w.trend(100000) == doctest::Approx(0.1));
  CHECK(w.trend(1000000) == 0.35f);  // clamped
  float amax = 0.0f;
  for (std::uint32_t t = 0; t < 3600000; t += 250) amax = std::fmax(amax, std::fabs(w.osc(t)));
  MESSAGE("largest oscillation " << amax / s.osc_amplitude << " amplitudes");
  CHECK(amax <= 1.8f * s.osc_amplitude);
  CHECK(amax > 0.8f * s.osc_amplitude);
  CHECK(w.dir_offset(123450) == (w.shift(123450) + w.trend(123450)) + w.osc(123450));
  CHECK(w.global_from(123450) == wm::wrap_2pi(s.base_from + w.dir_offset(123450)));
  s.osc_enabled = false;
  CHECK(wm::WindField(3, s).osc(123450) == 0.0f);
}

TEST_CASE("§10.4 puffs: caps, drift of sb·DT per tick, envelope 0 at birth and death") {
  wm::WindSettings s;
  s.base_from = 1.1f;
  wm::WindField w(0xBADA55, s);
  const wm::PuffParams& p = s.puffs;
  float fmin = 2.0f, fmax = 0.0f;
  std::uint64_t n = 0;
  int births = 0;
  std::vector<wm::PuffPatch> prev = w.advance(0).slots;
  for (std::uint32_t t = 50; t <= 1800000; t += 50) {
    const wm::WindTick& tick = w.advance(t);
    REQUIRE(tick.slots.size() == p.puff_count + p.lull_count);
    for (int i = 0; i < 4; ++i, n += 2) {
      const float f = w.puff_factor(tick, wm_env::in_range(-3000.0f, 3000.0f, n), wm_env::in_range(-3000.0f, 3000.0f, n + 1));
      fmin = std::fmin(fmin, f);
      fmax = std::fmax(fmax, f);
      REQUIRE(f >= 1.0f - p.cap_down);
      REQUIRE(f <= 1.0f + p.cap_up);
    }
    for (std::size_t j = 0; j < tick.slots.size(); ++j) {
      const wm::PuffPatch& a = prev[j];
      const wm::PuffPatch& b = tick.slots[j];
      REQUIRE(b.e >= 0.0f);
      REQUIRE(b.e <= 1.0f);
      REQUIRE(b.life_ms >= p.life_min_ms);
      REQUIRE(b.life_ms <= p.life_max_ms);
      if (b.generation == a.generation) {
        REQUIRE(b.age_ms == a.age_ms + 50);
        // Drift: sb·DT along the birth wind, sb = base (1 + s).
        const float sb = s.base_speed * (1.0f + b.s);
        const float moved = std::hypot(b.px - a.px, b.py - a.py);
        REQUIRE(moved == doctest::Approx(sb * wm::DT).epsilon(3e-3));
        CHECK(b.R == a.R);
        CHECK(b.s == a.s);
      } else {
        ++births;
        REQUIRE(b.generation == a.generation + 1);
        REQUIRE(a.age_ms + 50 >= a.life_ms);  // the old one reached its end
        CHECK(a.e < 50.0f / (0.1f * static_cast<float>(a.life_ms)) + 1e-6f);  // envelope near 0 at death
        CHECK(b.age_ms < 50);
        if (b.age_ms == 0) CHECK(b.e == 0.0f);  // 0 at birth
      }
      if (j < p.puff_count) CHECK(b.s > 0.0f);
      else CHECK(b.s < 0.0f);
    }
    prev = tick.slots;
  }
  MESSAGE("factor range [" << fmin << ", " << fmax << "], " << births << " births in 30 min");
  CHECK(births > 100);
  CHECK(fmin < 0.8f);
  CHECK(fmax > 1.1f);
}

TEST_CASE("§6.3 a patch drifts downwind with the wind of its birth") {
  wm::WindSettings s;
  s.base_from = 0.0f;  // from north: patches move south
  wm::apply_shift_preset(s, wm::ShiftPreset::steady);
  wm::WindField w(9, s);
  const wm::WindTick a = w.at(10000);
  const wm::WindTick b = w.at(10050);
  for (std::size_t j = 0; j < a.slots.size(); ++j) {
    if (a.slots[j].generation != b.slots[j].generation) continue;
    CHECK(b.slots[j].py < a.slots[j].py);
    CHECK(std::fabs(b.slots[j].px - a.slots[j].px) < 1e-3f);
  }
}

TEST_CASE("§6.4 puff factor: paraboloid, tile repeat, disabled") {
  wm::WindSettings s;
  wm::WindField w(21, s);
  const wm::WindTick tick = w.at(400000);
  for (const wm::PuffPatch& pp : w.puff_patches(tick)) {
    CHECK(pp.e >= 1e-4f);
    // Tile repeat: the same factor one tile away in x and y.
    const float f0 = w.puff_factor(tick, pp.px, pp.py);
    CHECK(w.puff_factor(tick, pp.px + 1000.0f, pp.py - 2000.0f) == doctest::Approx(f0).epsilon(1e-4));
  }
  // A single patch on its own: factor 1 + e·s at the centre (where no other patch overlaps).
  wm::WindSettings one;
  one.puffs.puff_count = 1;
  one.puffs.lull_count = 0;
  one.puffs.cap_up = 1.0f;
  wm::WindField w1(22, one);
  const wm::WindTick t1 = w1.at(300000);
  const wm::PuffPatch& pp = t1.slots[0];
  CHECK(w1.puff_factor(t1, pp.px, pp.py) == doctest::Approx(1.0f + pp.e * pp.s));
  CHECK(w1.puff_factor(t1, pp.px + pp.R * 1.001f, pp.py) == 1.0f);
  const float half = w1.puff_factor(t1, pp.px + 0.5f * pp.R, pp.py);
  CHECK(half == doctest::Approx(1.0f + pp.e * pp.s * 0.75f));
  one.puffs_enabled = false;
  wm::WindField w0(22, one);
  const wm::WindTick t0 = w0.at(300000);
  CHECK(t0.slots.empty());
  CHECK(w0.puff_factor(t0, 1.0f, 2.0f) == 1.0f);
  CHECK(w0.wind_clean(t0, 1.0f, 2.0f).speed == one.base_speed);
}

TEST_CASE("§10.5 cache: tick by tick equals from scratch at random times, bit for bit") {
  wm_env::Venue venue;
  for (const wm_env::WindScenario& sc : wm_env::wind_scenarios(venue)) {
    CAPTURE(sc.name);
    wm::WindField cached(sc.seed, sc.s);
    const wm::WindField scratch(sc.seed, sc.s);
    std::uint64_t n = 0;
    auto same = [&](std::uint32_t t) {
      const wm::WindTick& a = cached.advance(t);
      const wm::WindTick b = scratch.at(t);
      REQUIRE(bits(a.global_from) == bits(b.global_from));
      REQUIRE(bits(a.shift) == bits(scratch.shift(t)));
      REQUIRE(bits(a.global_from) == bits(scratch.global_from(t)));
      REQUIRE(a.slots.size() == b.slots.size());
      for (std::size_t j = 0; j < a.slots.size(); ++j) {
        REQUIRE(bits(a.slots[j].px) == bits(b.slots[j].px));
        REQUIRE(bits(a.slots[j].py) == bits(b.slots[j].py));
        REQUIRE(bits(a.slots[j].e) == bits(b.slots[j].e));
      }
      for (int i = 0; i < 5; ++i, n += 2) {
        const float x = wm_env::in_range(-2500.0f, 2500.0f, 900000 + n);
        const float y = wm_env::in_range(-2500.0f, 2500.0f, 900001 + n);
        const wm::WindSample wa = cached.wind_clean(a, x, y);
        const wm::WindSample wb = scratch.wind_clean(b, x, y);
        REQUIRE(bits(wa.speed) == bits(wb.speed));
        REQUIRE(bits(wa.from) == bits(wb.from));
      }
    };
    for (std::uint32_t t = 0; t <= 3600000; t += 50)
      if (t % 1000 == 0 || t < 5000) same(t);
      else cached.advance(t);
    // Random times, also going back: the cache restarts and gives the same bits.
    for (int i = 0; i < 300; ++i) same(static_cast<std::uint32_t>(wm_env::in_range(0.0f, 1.0f, 950000 + i) * 7.2e6f) / 50u * 50u);
  }
}

TEST_CASE("§2 wind at a point: no venue gives the base speed times the puff factor") {
  wm::WindSettings s;
  s.base_from = 2.0f;
  const wm::WindField w(4, s);
  const wm::WindTick tick = w.at(250000);
  for (int i = 0; i < 100; ++i) {
    const float x = wm_env::in_range(-4000.0f, 4000.0f, 960000 + 2 * i);
    const float y = wm_env::in_range(-4000.0f, 4000.0f, 960001 + 2 * i);
    const wm::WindSample ws = w.wind_clean(tick, x, y);
    CHECK(bits(ws.speed) == bits((s.base_speed * 1.0f) * w.puff_factor(tick, x, y)));
    CHECK(bits(ws.from) == bits(tick.global_from));
  }
}

TEST_CASE("§8.1 grid sampler: nodes, bilinear, outside, NaN") {
  wm::Grid g{10.0f, 20.0f, 5.0f, 10.0f, 3, 2};
  const std::vector<float> v = {0.0f, 1.0f, 2.0f, 10.0f, 11.0f, 12.0f};  // j major
  CHECK(wm::check_grid(g, v) == nullptr);
  CHECK(wm::grid_sample(g, v, 10.0f, 20.0f, -1.0f) == 0.0f);
  CHECK(wm::grid_sample(g, v, 20.0f, 30.0f, -1.0f) == 12.0f);  // far corner: last cell, t = 1
  CHECK(wm::grid_sample(g, v, 15.0f, 20.0f, -1.0f) == 1.0f);
  CHECK(wm::grid_sample(g, v, 12.5f, 25.0f, -1.0f) == doctest::Approx(5.5));
  CHECK(wm::grid_sample(g, v, 9.99f, 25.0f, -1.0f) == -1.0f);
  CHECK(wm::grid_sample(g, v, 15.0f, 30.01f, -1.0f) == -1.0f);
  CHECK(wm::grid_sample(g, v, NAN, 25.0f, -1.0f) == -1.0f);
  wm::Grid bad = g;
  bad.nx = 1;
  CHECK(wm::check_grid(bad, v) != nullptr);
  CHECK(wm::check_grid(g, {1.0f}) != nullptr);
}

TEST_CASE("§8 venue field: sector blend, seamless border") {
  wm_env::Venue venue;
  wm::WindSettings s;
  wm::apply_shift_preset(s, wm::ShiftPreset::steady);
  s.puffs_enabled = false;
  s.venue_wind_field = venue.wind.get();
  REQUIRE(wm::check_wind_settings(s) == nullptr);
  const wm::VenueWindField& v = *venue.wind;
  // Exactly on a base direction the field is that sector's.
  for (int k = 0; k < 8; ++k) {
    s.base_from = static_cast<float>(k) * wm::QUARTER_PI;
    const wm::WindField w(1, s);
    const wm::WindTick tick = w.at(0);
    if (!(tick.global_from / wm::QUARTER_PI == static_cast<float>(k))) continue;
    const float x = -1500.0f + 100.0f * 7.0f, y = -1000.0f + 125.0f * 5.0f;  // node (7, 5)
    const wm::WindSample ws = w.wind_clean(tick, x, y);
    CAPTURE(k);
    CHECK(ws.speed == doctest::Approx(s.base_speed * v.f[k][5 * 31 + 7]));
    CHECK(wm::angle_diff(ws.from, s.base_from) == doctest::Approx(v.d[k][5 * 31 + 7]).scale(1.0));
  }
  // Halfway between N and NE: the average of the two sectors.
  s.base_from = 0.5f * wm::QUARTER_PI;
  const wm::WindField w(1, s);
  const wm::WindTick tick = w.at(0);
  const float x = -1500.0f + 100.0f * 3.0f, y = -1000.0f + 125.0f * 9.0f;
  const std::uint32_t r = 9 * 31 + 3;
  CHECK(w.wind_clean(tick, x, y).speed == doctest::Approx(s.base_speed * 0.5f * (v.f[0][r] + v.f[1][r])));
  // Border nodes are (1, 0): stepping out of the box is seamless.
  const wm::WindSample in = w.wind_clean(tick, -1500.0f, 0.0f);
  const wm::WindSample out = w.wind_clean(tick, -1500.01f, 0.0f);
  CHECK(in.speed == out.speed);
  CHECK(in.from == out.from);
}

TEST_CASE("§7 current: uniform plus tide times the venue field") {
  wm_env::Venue venue;
  wm::WindSettings s;
  s.current_speed = 0.5f;
  s.current_to = wm::HALF_PI;  // flowing east
  wm::WindField w(1, s);
  const wm::Vec2 c = w.current(0.0f, 0.0f, 1000);
  CHECK(c.x == doctest::Approx(0.5));
  CHECK(std::fabs(c.y) < 1e-6f);
  s.current_speed = 0.0f;
  s.venue_current_field = venue.current.get();
  s.tide_scale = 1.0f;
  s.tide_period_ms = 40000;
  s.tide_phase_ms = 0;
  wm::WindField wt(1, s);
  const float fx = wm::grid_sample(venue.current->grid, venue.current->vx, 100.0f, 50.0f, 0.0f);
  CHECK(wt.current(100.0f, 50.0f, 0).x == doctest::Approx(fx));          // tide(0) = 1
  CHECK(wt.current(100.0f, 50.0f, 20000).x == doctest::Approx(-fx));     // half a period
  CHECK(std::fabs(wt.current(100.0f, 50.0f, 10000).x) < 1e-6f);          // slack water
  CHECK(wt.current(100.0f, 50.0f, 40000).x == wt.current(100.0f, 50.0f, 0).x);  // periodic, exact
  CHECK(wt.current(5000.0f, 0.0f, 0).x == 0.0f);                          // outside the field
}

TEST_CASE("settings checks") {
  wm::WindSettings s;
  CHECK(wm::check_wind_settings(s) == nullptr);
  s.puffs.life_min_ms = 0;
  CHECK(wm::check_wind_settings(s) != nullptr);
  s = wm::WindSettings{};
  s.base_speed = NAN;
  CHECK(wm::check_wind_settings(s) != nullptr);
  s = wm::WindSettings{};
  s.tide_period_ms = 0;
  CHECK(wm::check_wind_settings(s) != nullptr);
}
