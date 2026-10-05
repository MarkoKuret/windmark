// Diagnostic, skipped by default (run with -tc="probe*" --no-skip): how far the cockpit floor and the deck edge at
// the transom stand above the sea, by class, wind and heading, with and without the heel. The numbers behind
// water_render.md §4.8; the geometry is the generator's (tools/boatgen deck.py) for the shipped classes.
#include <cmath>
#include <cstdio>

#include "boat_harness.h"
#include "sea/sea.h"

using namespace wm_test;

namespace {

// transom x, cockpit floor height and half width there, sheer height and half breadth there (body frame, m)
struct Geo { float tx, floor, halfw, sheer, sheer_y; };

float point_z(const wm::BoatState& s, float x, float y, float z) {
  // conventions.md §3: R = Rz Ry(-theta) Rx(phi); only the vertical component matters
  const float z1 = y * std::sin(s.phi) + z * std::cos(s.phi);
  return s.z + x * std::sin(s.theta) + z1 * std::cos(s.theta);
}

void run(const char* cls, Geo g, float tws_kn, float twa_deg, bool kite) {
  const wm::PerfData& p = perf(cls);
  wm::SeaSettings ss;
  ss.wind_sea = wm::wind_sea_from_wind(static_cast<double>(kn(tws_kn)), 10000.0, 0.0f);
  wm::SeaField sea(42, ss);
  wm::Boat b;
  b.init(&p, 42, 0);
  wm::BoatEnv e;
  e.wind_speed = kn(tws_kn);
  e.wind_from = 0.0f;
  e.wind_speed_clean = e.wind_speed;
  wm::SeaTick st = sea.at(0);
  e.sea = &st;
  const float twa = deg(twa_deg);
  b.reset(0, 0, wm::wrap_2pi(-twa), 3.0f, p.start_front_sail, true, e);
  if (kite) (void)b.hoist(static_cast<std::int32_t>(p.sails.size()) - 1);
  int n = 0, wet_sh = 0, wet = 0, wet_c = 0, wet_nh = 0;
  double heel = 0, pitch = 0, cmid = 0;
  float worst = 1e9f;
  double sum = 0;
  for (std::uint32_t i = 0; i < 12000; ++i) {
    st = sea.at(i * wm::DT_MS);
    e.sea = &st;
    const float err = wm::wrap_pi(b.state().twa - twa);
    b.set_helm(wm::clamp(3.0f * err, -0.3f, 0.3f));
    b.step(e);
    if (i < 1200) continue;
    const wm::BoatState& s = b.state();
    const wm::SinCos sc = wm::wm_sincos(s.psi);
    float c = 1e9f, cnh = 1e9f, cc = 0;
    wm::BoatState s0 = s;
    s0.phi = 0;
    for (float y : {-g.halfw, 0.0f, g.halfw}) {
      const float wx = (s.pos_x + g.tx * sc.s) - y * sc.c;
      const float wy = (s.pos_y + g.tx * sc.c) + y * sc.s;
      const float d = point_z(s, g.tx, y, g.floor) - st.sea_height(wx, wy);
      c = std::fmin(c, d);
      cnh = std::fmin(cnh, point_z(s0, g.tx, y, g.floor) - st.sea_height(wx, wy));
      if (y == 0.0f) cc = d;
    }
    float sh = 1e9f;
    for (float y : {-g.sheer_y, g.sheer_y}) {
      const float wx = (s.pos_x + g.tx * sc.s) - y * sc.c;
      const float wy = (s.pos_y + g.tx * sc.c) + y * sc.s;
      sh = std::fmin(sh, point_z(s, g.tx, y, g.sheer) - st.sea_height(wx, wy));
    }
    if (sh < 0) ++wet_sh;
    heel += static_cast<double>(std::fabs(s.phi));
    pitch += static_cast<double>(s.theta);
    cmid += static_cast<double>(cc);
    if (cc < 0) ++wet_c;
    if (cnh < 0) ++wet_nh;
    ++n;
    sum += static_cast<double>(c);
    if (c < 0) ++wet;
    worst = std::fmin(worst, c);
  }
  std::printf("%-5s %3.0fkn %3.0f%s Hs %.2f | corner mean %5.2f min %5.2f wet %4.1f%% | centre mean %.2f wet %4.1f%% | "
              "no-heel wet %4.1f%% | deck edge wet %4.1f%% | heel %4.1f pitch %4.1f\n", cls, (double)tws_kn, (double)twa_deg, kite ? "k" : " ",
              (double)ss.wind_sea.hs, sum / n, (double)worst, 100.0 * wet / n, cmid / n, 100.0 * wet_c / n,
              100.0 * wet_nh / n, 100.0 * wet_sh / n, (double)to_deg((float)(heel / n)), (double)to_deg((float)(pitch / n)));
}

}  // namespace

TEST_CASE("probe: stern clearance" * doctest::skip()) {
  const Geo g7{-3.745f, 0.346f, 0.756f, 0.60f, 1.05f}, g12{-6.15f, 0.507f, 1.006f, 0.90f, 1.40f};
  for (float tws : {10.0f, 15.0f, 20.0f, 25.0f}) {
    run("wm7", g7, tws, 42, false);
    run("wm7", g7, tws, 90, false);
    run("wm7", g7, tws, 140, true);
    run("wm12", g12, tws, 42, false);
    run("wm12", g12, tws, 90, false);
    run("wm12", g12, tws, 140, true);
  }
}
