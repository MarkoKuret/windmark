// wind_shadow.md §8: zones and profile, a boat sailing in another's blanket, independence of boat order; plus
// the tactical positions of §6 and the header sign of §5.
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

#include "data/perf.h"
#include "doctest.h"
#include "env_scenarios.h"
#include "shadow/shadow.h"
#include "test_util.h"

using wm_env::make_source;
using wm_test::bits;

namespace {

constexpr float kTws = 7.0f;
constexpr float kTwd = 0.0f;  // from north

// Starboard tack close-hauled: heading 315°, wind 45° on the starboard bow.
float upwind_psi() { return wm::wrap_2pi(-45.0f * wm::DEG); }

wm::Vec2 add(wm::Vec2 a, wm::Vec2 b, float s) { return {a.x + s * b.x, a.y + s * b.y}; }

struct Frame {
  wm::Vec2 ce, a, n;  // centre of effort, downwind axis, across
};

Frame blanket_frame(const wm::ShadowSource& B) {
  const wm::WindShadowParams& p = B.cls->p;
  const wm::Vec2 f = wm::dir(B.psi);
  const wm::Vec2 aw = wm::dir(B.awd_from);
  const wm::Vec2 a{-aw.x, -aw.y};
  return {{B.pos_x + p.ce_x * f.x, B.pos_y + p.ce_x * f.y}, a, {a.y, -a.x}};
}

}  // namespace

TEST_CASE("§8.1 zero upwind and beyond 1.25 Lb, blanket_depth at the peak") {
  const wm::ShadowClass cls = wm::make_shadow_class(wm_env::shadow_params_s());
  for (const bool spin : {false, true}) {
    const float psi = spin ? wm::PI : upwind_psi();
    const wm::ShadowSource B = make_source(&cls, 50.0f, -30.0f, psi, 3.0f, kTws, kTwd, spin);
    const Frame fr = blanket_frame(B);
    const float Lb = wm::shadow_blanket_length(cls, B.aws);
    CAPTURE(spin);
    REQUIRE(Lb > 1.0f);
    // Upwind of the sails: nothing, on the axis and off it.
    for (float d : {0.06f, 0.2f, 0.5f, 1.0f})
      for (float e : {-3.0f, 0.0f, 3.0f}) {
        const wm::Vec2 q = add(add(fr.ce, fr.a, -d * Lb), fr.n, e);
        CHECK(wm::shadow(B, q.x, q.y).l == 0.0f);
      }
    // Beyond 1.25 Lb in any direction: nothing.
    for (int k = 0; k < 16; ++k) {
      const wm::Vec2 u = wm::dir(static_cast<float>(k) * (wm::TWO_PI / 16.0f));
      const wm::Vec2 q = add(fr.ce, u, 1.25f * Lb + cls.p.width_spinnaker + 0.5f);
      CHECK(wm::shadow(B, q.x, q.y).l == 0.0f);
    }
    // Past the end of the blanket on the axis: nothing.
    const wm::Vec2 end = add(fr.ce, fr.a, 1.001f * Lb);
    CHECK(wm::shadow(B, end.x, end.y).l == 0.0f);
    // Peak on the axis.
    const float depth = spin ? cls.p.blanket_depth_spinnaker : cls.p.blanket_depth;
    const wm::Vec2 pk = add(fr.ce, fr.a, cls.p.blanket_peak * Lb);
    const wm::ShadowLoss l = wm::shadow(B, pk.x, pk.y);
    CHECK(l.l == doctest::Approx(depth).epsilon(1e-4));
    CHECK(l.delta == doctest::Approx(std::min(cls.p.header_coef * depth, cls.p.header_max)));
    CHECK(wm::shadow_p_long(cls.p, cls.p.blanket_peak) == 1.0f);
    CHECK(wm::shadow_p_lat(0.0f) == 1.0f);
    // Nothing on the axis beats the peak.
    for (float s = -0.05f; s < 1.0f; s += 0.01f) {
      const wm::Vec2 q = add(fr.ce, fr.a, s * Lb);
      CHECK(wm::shadow(B, q.x, q.y).l <= depth * 1.0001f);
    }
  }
}

TEST_CASE("§8.1 symmetric in eta (the blanket; the backwind band is one-sided by design)") {
  wm::WindShadowParams p = wm_env::shadow_params_s();
  p.turb_depth = 0.0f;
  const wm::ShadowClass cls = wm::make_shadow_class(p);
  const wm::ShadowSource B = make_source(&cls, 0.0f, 0.0f, upwind_psi(), 3.0f, kTws, kTwd);
  const Frame fr = blanket_frame(B);
  const float Lb = wm::shadow_blanket_length(cls, B.aws);
  for (float s : {-0.03f, 0.1f, 0.25f, 0.5f, 0.8f})
    for (float e : {0.5f, 1.5f, 3.0f, 6.0f}) {
      const wm::Vec2 base = add(fr.ce, fr.a, s * Lb);
      const wm::Vec2 qa = add(base, fr.n, e), qb = add(base, fr.n, -e);
      CAPTURE(s);
      CAPTURE(e);
      CHECK(wm::shadow(B, qa.x, qa.y).l == doctest::Approx(wm::shadow(B, qb.x, qb.y).l).epsilon(1e-4).scale(1e-5));
    }
}

TEST_CASE("§4 sizes: the S blanket at 8 m/s apparent is about 31 m, half in light air, a quarter more in 20 m/s") {
  const wm::ShadowClass cls = wm::make_shadow_class(wm_env::shadow_params_s());
  const float L8 = wm::shadow_blanket_length(cls, 8.0f);
  CHECK(L8 == doctest::Approx(31.2).epsilon(0.01));
  CHECK(wm::shadow_blanket_length(cls, 2.0f) / L8 == doctest::Approx(0.5).epsilon(0.07));
  CHECK(wm::shadow_blanket_length(cls, 20.0f) / L8 == doctest::Approx(1.25).epsilon(0.03));
  CHECK(wm::shadow_blanket_length(cls, 0.05f) < 1.0f);
  const wm::ShadowSource calm = make_source(&cls, 0.0f, 0.0f, 0.0f, 0.0f, 0.05f, kTwd);
  CHECK(wm::shadow(calm, 0.0f, -2.0f).l == 0.0f);  // Lb < 1: no shadow
}

TEST_CASE("§6 tactical positions on the same tack upwind") {
  const wm::ShadowClass cls = wm::make_shadow_class(wm_env::shadow_params_s());
  const float psi = upwind_psi();
  const wm::Vec2 f = wm::dir(psi);
  const wm::Vec2 port{-f.y, f.x}, stbd{f.y, -f.x};  // starboard is windward on starboard tack
  const wm::ShadowSource B = make_source(&cls, 0.0f, 0.0f, psi, 3.0f, kTws, kTwd);
  const float h = cls.p.height;

  SUBCASE("in the blanket, two mast heights down the apparent wind: less wind and a header") {
    const Frame fr = blanket_frame(B);
    const wm::Vec2 q = add(fr.ce, fr.a, 2.0f * h * 0.5f);  // inside the long blanket (Lb about 3 h)
    const wm::ShadowLoss l = wm::shadow(B, q.x, q.y);
    CHECK(l.l > 0.1f);
    CHECK(l.l <= 0.22f);
    const wm::ShadowSource snap[] = {B};
    const wm::ShadowedWind w = wm::shadowed_wind(snap, -1, q.x, q.y, kTws, kTwd + 0.3f);
    CHECK(w.source == 0);
    CHECK(w.speed == doctest::Approx(kTws * (1.0f - l.l)));
    // Starboard-tack source: the wind backs, which heads a starboard-tack receiver.
    CHECK(wm::angle_diff(w.from, kTwd + 0.3f) == doctest::Approx(-l.delta));
    CHECK(w.header > 0.0f);
    CHECK(w.header <= cls.p.header_max);
  }

  SUBCASE("safe leeward: the boat ahead and to leeward is clear, the one astern and to windward is slowed") {
    // A: 8 m ahead of B's reference point and 3 m to leeward (port on starboard tack).
    const wm::Vec2 pa = add(add({0.0f, 0.0f}, f, 8.0f), port, 3.0f);
    const wm::ShadowSource A = make_source(&cls, pa.x, pa.y, psi, 3.0f, kTws, kTwd);
    const wm::ShadowSource snap[] = {A, B};
    const wm::ShadowedWind wa = wm::shadowed_wind(snap, 0, A.pos_x, A.pos_y, kTws, kTwd);
    const wm::ShadowedWind wb = wm::shadowed_wind(snap, 1, B.pos_x, B.pos_y, kTws, kTwd);
    MESSAGE("safe leeward: A loss " << wa.loss << ", B loss " << wb.loss);
    CHECK(wa.source == -1);
    CHECK(wa.speed == kTws);
    CHECK(wb.source == 0);
    CHECK(wb.loss > 0.02f);
    CHECK(wb.loss <= cls.p.turb_depth);
  }

  SUBCASE("backwind: astern and to windward within about 1.5 boat lengths") {
    const wm::Vec2 stern = add({0.0f, 0.0f}, f, cls.p.stern_x);
    const wm::Vec2 wdir = add(wm::Vec2{-f.x * cls.turb_ca, -f.y * cls.turb_ca}, stbd, cls.turb_sa);
    const wm::Vec2 q = add(stern, wdir, 3.0f);
    const wm::ShadowLoss l = wm::shadow(B, q.x, q.y);
    CHECK(l.l > 0.1f);
    CHECK(l.l <= cls.p.turb_depth);
    // Further to windward, outside the band: nothing. (To leeward the blanket takes over.)
    const wm::Vec2 q2 = add(q, stbd, 8.0f);
    CHECK(wm::shadow(B, q2.x, q2.y).l == 0.0f);
    // Far astern (beyond Lt, outside the blanket): nothing.
    const wm::Vec2 q3 = add(stern, wdir, 0.45f * wm::shadow_blanket_length(cls, B.aws));
    CHECK(wm::shadow(B, q3.x, q3.y).l == 0.0f);
  }

  SUBCASE("to windward and abeam or ahead: clear air") {
    for (float ahead : {-2.0f, 0.0f, 5.0f, 15.0f})
      for (float side : {8.0f, 15.0f, 25.0f}) {
        const wm::Vec2 q = add(add({0.0f, 0.0f}, f, ahead), stbd, side);
        CAPTURE(ahead);
        CAPTURE(side);
        CHECK(wm::shadow(B, q.x, q.y).l == 0.0f);
      }
  }

  SUBCASE("no backwind off the wind") {
    const wm::ShadowSource R = make_source(&cls, 0.0f, 0.0f, wm::wrap_2pi(-120.0f * wm::DEG), 4.0f, kTws, kTwd);
    REQUIRE(std::fabs(R.awa) > cls.p.turb_awa_max);
    const wm::Vec2 fr = wm::dir(R.psi);
    const wm::Vec2 q = add({0.0f, 0.0f}, fr, cls.p.stern_x - 3.0f);  // right astern, outside the blanket
    CHECK(wm::shadow(R, q.x, q.y).l == 0.0f);
  }
}

TEST_CASE("§6 downwind: the boat behind blankets the boat ahead") {
  const wm::ShadowClass cls = wm::make_shadow_class(wm_env::shadow_params_s());
  // Running dead downwind (heading south in a northerly) with a spinnaker.
  const wm::ShadowSource behind = make_source(&cls, 0.0f, 0.0f, wm::PI, 3.0f, kTws, kTwd, true);
  const wm::ShadowSource ahead = make_source(&cls, 0.0f, -12.0f, wm::PI, 3.0f, kTws, kTwd, true);
  const wm::ShadowSource snap[] = {behind, ahead};
  const wm::ShadowedWind wa = wm::shadowed_wind(snap, 1, ahead.pos_x, ahead.pos_y, kTws, kTwd);
  const wm::ShadowedWind wb = wm::shadowed_wind(snap, 0, behind.pos_x, behind.pos_y, kTws, kTwd);
  MESSAGE("running: ahead loses " << wa.loss << ", behind " << wb.loss);
  CHECK(wa.source == 0);
  CHECK(wa.loss > 0.15f);
  CHECK(wb.loss == 0.0f);
}

TEST_CASE("§8.2 two boats on the same tack, the second two mast heights down the first's apparent wind") {
  wm::PerfData perf;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_perf(std::string(WINDMARK_DATA_DIR) + "/perf/wm7.perf.json", perf, err), err.message());
  const wm::ShadowClass cls = wm::make_shadow_class(perf.dynamics.wind_shadow);
  const float psi = upwind_psi();
  const wm::ShadowSource A = make_source(&cls, 0.0f, 0.0f, psi, 3.0f, kTws, kTwd);
  const Frame fr = blanket_frame(A);
  const wm::Vec2 q = add(fr.ce, fr.a, 2.0f * cls.p.height);
  const wm::ShadowSource Bb = make_source(&cls, q.x, q.y, psi, 3.0f, kTws, kTwd);
  const wm::ShadowSource snap[] = {A, Bb};
  const wm::ShadowedWind wa = wm::shadowed_wind(snap, 0, A.pos_x, A.pos_y, kTws, kTwd);
  const wm::ShadowedWind wb = wm::shadowed_wind(snap, 1, Bb.pos_x, Bb.pos_y, kTws, kTwd);
  CHECK(wa.loss == 0.0f);
  REQUIRE(wb.loss > 0.05f);
  // Speed target: the polar at the reduced true wind (the boat step then settles on it, boat.md).
  const wm::ConfigPerf* cfg = perf.config_for(perf.start_front_sail);
  REQUIRE(cfg != nullptr);
  const float twa = 45.0f * wm::DEG;
  const float v_clear = cfg->polar.at(wa.speed, twa);
  const float v_shadow = cfg->polar.at(wb.speed, twa);
  MESSAGE("loss " << wb.loss << ", header " << wb.header / wm::DEG << " deg, polar " << v_clear << " -> " << v_shadow);
  CHECK(v_shadow < v_clear);
  // Heading at a fixed TWA turns lower (away from the clean wind) by the header.
  const float psi_clear = wm::wrap_2pi(wa.from - twa);
  const float psi_shadow = wm::wrap_2pi(wb.from - twa);
  CHECK(wm::angle_diff(psi_shadow, psi_clear) == doctest::Approx(-wb.header));
}

TEST_CASE("§8.3 boat order: permuting the snapshot permutes the winds and nothing else") {
  const wm::ShadowClass cls = wm::make_shadow_class(wm_env::shadow_params_s());
  std::vector<wm::ShadowSource> boats;
  for (int i = 0; i < 16; ++i) {
    const float x = wm_env::in_range(-25.0f, 25.0f, 1200000 + 4 * i);
    const float y = wm_env::in_range(-25.0f, 25.0f, 1200001 + 4 * i);
    const float psi = wm_env::in_range(0.0f, wm::TWO_PI, 1200002 + 4 * i);
    boats.push_back(make_source(&cls, x, y, psi, 3.0f, kTws, kTwd, i % 4 == 0));
  }
  boats[5].casts = false;
  auto winds = [](const std::vector<wm::ShadowSource>& b) {
    std::vector<wm::ShadowedWind> out;
    for (std::size_t i = 0; i < b.size(); ++i)
      out.push_back(wm::shadowed_wind(b, static_cast<std::int32_t>(i), b[i].pos_x, b[i].pos_y, kTws, kTwd));
    return out;
  };
  const std::vector<wm::ShadowedWind> w0 = winds(boats);
  int shadowed = 0;
  for (const wm::ShadowedWind& w : w0) shadowed += w.source >= 0;
  MESSAGE(shadowed << " of 16 boats in another's shadow");
  CHECK(shadowed >= 3);
  std::vector<int> perm(boats.size());
  for (std::size_t i = 0; i < perm.size(); ++i) perm[i] = static_cast<int>(i);
  for (int round = 0; round < 20; ++round) {
    // Fisher-Yates with the test RNG.
    for (std::size_t k = perm.size() - 1; k > 0; --k) {
      const auto j = static_cast<std::size_t>(wm_env::in_range(0.0f, 1.0f, 1300000 + 100 * round + k) * static_cast<float>(k + 1));
      std::swap(perm[k], perm[std::min(j, k)]);
    }
    std::vector<wm::ShadowSource> pb;
    for (int p : perm) pb.push_back(boats[static_cast<std::size_t>(p)]);
    const std::vector<wm::ShadowedWind> w1 = winds(pb);
    for (std::size_t i = 0; i < perm.size(); ++i) {
      const wm::ShadowedWind& a = w1[i];
      const wm::ShadowedWind& b = w0[static_cast<std::size_t>(perm[i])];
      REQUIRE(bits(a.speed) == bits(b.speed));
      REQUIRE(bits(a.from) == bits(b.from));
      REQUIRE((a.source < 0) == (b.source < 0));
      if (a.source >= 0) REQUIRE(perm[static_cast<std::size_t>(a.source)] == b.source);
    }
  }
}

TEST_CASE("§3 casts = false and §7 zone outlines") {
  const wm::ShadowClass cls = wm::make_shadow_class(wm_env::shadow_params_s());
  wm::ShadowSource B = make_source(&cls, 0.0f, 0.0f, upwind_psi(), 3.0f, kTws, kTwd);
  const Frame fr = blanket_frame(B);
  const float Lb = wm::shadow_blanket_length(cls, B.aws);
  const wm::Vec2 pk = add(fr.ce, fr.a, 0.25f * Lb);
  const wm::ShadowZones z = wm::shadow_zones(B, 16);
  CHECK(z.Lb == Lb);
  CHECK(z.blanket_left.size() == 16);
  CHECK(z.backwind_left.size() == 16);
  CHECK(z.Lt == doctest::Approx(cls.p.turb_length * Lb));
  // Points just inside the blanket outline are shadowed, just outside are not.
  for (std::size_t k = 1; k + 1 < 16; ++k) {
    const wm::Vec2 l = z.blanket_left[k], r = z.blanket_right[k];
    const wm::Vec2 mid{0.5f * (l.x + r.x), 0.5f * (l.y + r.y)};
    const wm::Vec2 in{mid.x + 0.9f * (l.x - mid.x), mid.y + 0.9f * (l.y - mid.y)};
    const wm::Vec2 out{mid.x + 1.1f * (l.x - mid.x), mid.y + 1.1f * (l.y - mid.y)};
    CAPTURE(k);
    CHECK(wm::shadow(B, in.x, in.y).l > 0.0f);
    // Outside the blanket edge only the backwind band may still reach.
    const wm::ShadowLoss lo = wm::shadow(B, out.x, out.y);
    if (lo.l > 0.0f) CHECK(lo.l < wm::shadow(B, in.x, in.y).l + cls.p.turb_depth);
  }
  B.casts = false;
  CHECK(wm::shadow(B, pk.x, pk.y).l == 0.0f);
  CHECK(wm::shadow_zones(B).blanket_left.empty());
}

TEST_CASE("tick step 5: env_at_boat combines the clean wind, the shadows and the current") {
  const wm::ShadowClass cls = wm::make_shadow_class(wm_env::shadow_params_s());
  wm::WindSettings s;
  s.current_speed = 0.3f;
  s.current_to = 1.0f;
  wm::WindField w(8, s);
  const wm::WindTick& tick = w.advance(120000);
  const float psi = upwind_psi();
  const wm::ShadowSource A = make_source(&cls, 0.0f, 0.0f, psi, 3.0f, s.base_speed, tick.global_from);
  const Frame fr = blanket_frame(A);
  const wm::Vec2 q = add(fr.ce, fr.a, 0.3f * wm::shadow_blanket_length(cls, A.aws));
  const wm::ShadowSource Bq = make_source(&cls, q.x, q.y, psi, 3.0f, s.base_speed, tick.global_from);
  const wm::ShadowSource snap[] = {A, Bq};
  const wm::EnvAtBoat e = wm::env_at_boat(w, tick, snap, 1, q.x, q.y);
  const wm::WindSample clean = w.wind_clean(tick, q.x, q.y);
  CHECK(bits(e.wind_speed_clean) == bits(clean.speed));
  CHECK(bits(e.wind_from_clean) == bits(clean.from));
  CHECK(e.shadow_source == 0);
  CHECK(bits(e.wind_speed) == bits(clean.speed * (1.0f - e.shadow_loss)));
  const wm::Vec2 c = w.current(q.x, q.y, 120000);
  CHECK(bits(e.current_x) == bits(c.x));
  CHECK(bits(e.current_y) == bits(c.y));
  const wm::EnvAtBoat ea = wm::env_at_boat(w, tick, snap, 0, 0.0f, 0.0f);
  CHECK(ea.shadow_source == -1);
  CHECK(bits(ea.wind_speed) == bits(ea.wind_speed_clean));
}
