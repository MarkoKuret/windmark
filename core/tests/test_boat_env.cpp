// Boats sailing in the environment modules: tick steps 3 to 5 (conventions.md §4.1) with the wind field, the sea
// and the wind shadows; the determinism tests of boat.md §10.5; the boat response of sea.md §8.4 and the
// two-boat shadow test of wind_shadow.md §8.2.
#include <cmath>
#include <memory>
#include <string>
#include <vector>

#include "boat_harness.h"
#include "sea/sea.h"
#include "shadow/shadow.h"
#include "state/checksum.h"
#include "wind/wind.h"

using namespace wm_test;
using wm::DT;

namespace {

// A minimal fleet driver: environment at t_n (step 3), shadow snapshot (step 4), wind at each boat and the boat
// step (step 5), then the tick checksum (step 7). Collisions and the race layer are not involved.
struct Fleet {
  std::uint64_t seed;
  wm::WindField wind;
  std::unique_ptr<wm::SeaField> sea;
  std::vector<std::unique_ptr<wm::Boat>> boats;
  std::vector<wm::ShadowClass> classes;  // one per boat (a boat's class never changes)
  std::vector<wm::ShadowSource> snapshot;
  std::vector<wm::EnvAtBoat> env;
  std::uint32_t tick = 0;
  bool shadows = true;

  Fleet(std::uint64_t race_seed, const wm::WindSettings& ws, const wm::SeaSettings* ss)
      : seed(race_seed), wind(race_seed, ws) {
    if (ss != nullptr) sea = std::make_unique<wm::SeaField>(race_seed, *ss);
  }

  std::uint32_t t_ms() const { return tick * wm::DT_MS; }

  wm::Boat& add(const wm::PerfData& p, float x, float y, float twa, float v, std::int32_t front) {
    boats.push_back(std::make_unique<wm::Boat>());
    wm::Boat& b = *boats.back();
    b.init(&p, seed, static_cast<std::uint32_t>(boats.size() - 1));
    classes.push_back(wm::make_shadow_class(p.dynamics.wind_shadow));
    const wm::WindTick& wt = wind.advance(t_ms());
    const wm::WindSample w = wind.wind_clean(wt, x, y);
    const wm::SeaTick st = sea ? sea->at(t_ms()) : wm::SeaTick();
    wm::BoatEnv e;
    e.wind_speed = w.speed;
    e.wind_from = w.from;
    e.wind_speed_clean = w.speed;
    const wm::Vec2 c = wind.current(x, y, t_ms());
    e.current_x = c.x;
    e.current_y = c.y;
    e.sea = sea ? &st : nullptr;
    b.reset(x, y, wm::wrap_2pi(w.from - twa), v, front, true, e);
    return b;
  }

  // One tick; returns its checksum.
  std::uint64_t step() {
    const wm::WindTick& wt = wind.advance(t_ms());                    // step 3
    const wm::SeaTick st = sea ? sea->at(t_ms()) : wm::SeaTick();
    snapshot.resize(boats.size());                                     // step 4
    for (std::size_t i = 0; i < boats.size(); ++i) {
      const wm::Boat& b = *boats[i];
      const wm::BoatState& s = b.state();
      wm::ShadowSource& src = snapshot[i];
      src.cls = &classes[i];
      src.pos_x = s.pos_x;
      src.pos_y = s.pos_y;
      src.psi = s.psi;
      src.aws = s.aws;
      src.awd_from = s.awd_from;
      src.awa = s.awa;
      src.twa = s.twa;
      src.spinnaker = b.sails().spinnaker_flying();
      src.casts = shadows;
    }
    env.resize(boats.size());
    for (std::size_t i = 0; i < boats.size(); ++i) {                  // step 5
      wm::Boat& b = *boats[i];
      const wm::EnvAtBoat e =
          wm::env_at_boat(wind, wt, snapshot, static_cast<std::int32_t>(i), b.state().pos_x, b.state().pos_y);
      env[i] = e;
      wm::BoatEnv be;
      be.wind_speed = e.wind_speed;
      be.wind_from = e.wind_from;
      be.wind_speed_clean = e.wind_speed_clean;
      be.current_x = e.current_x;
      be.current_y = e.current_y;
      be.sea = sea ? &st : nullptr;
      b.step(be);
    }
    ++tick;
    return checksum();                                                 // step 7
  }

  std::uint64_t checksum() const {
    std::vector<std::vector<std::uint8_t>> snaps;
    for (const auto& b : boats) {
      wm::SnapshotWriter w;
      b->save(w);
      snaps.push_back(w.bytes());
    }
    return wm::tick_checksum(tick, snaps);
  }
};

wm::WindSettings breeze(float kn_speed, float from) {
  wm::WindSettings s;
  s.base_speed = kn(kn_speed);
  s.base_from = from;
  return s;  // shifty preset and puffs on: the defaults
}

// Scripted skipper for the determinism runs: tacks, a spinnaker hoist and drop, let-fly, manual trim.
void script(Fleet& f) {
  const std::uint32_t t = f.tick;
  for (std::size_t i = 0; i < f.boats.size(); ++i) {
    wm::Boat& b = *f.boats[i];
    const wm::PerfData& p = b.perf();
    const std::int32_t kite = static_cast<std::int32_t>(p.sails.size()) - 1;  // the last sail is a spinnaker
    const std::uint32_t k = (t + static_cast<std::uint32_t>(i) * 37u) % 2400u;
    if (k < 400) b.set_helm(0.0f);
    else if (k < 480) b.set_helm(0.6f);
    else if (k < 900) b.set_helm(0.0f);
    else if (k == 900) (void)b.hoist(kite);
    else if (k < 1000) b.set_helm(-0.3f);
    else if (k < 1400) b.set_helm(0.0f);
    else if (k == 1400) (void)b.drop_front();
    else if (k < 1500) { b.set_let_fly(true); b.set_helm(0.2f); }
    else if (k < 1800) { b.set_let_fly(false); b.set_auto_trim(false); b.set_sheet(0.3f); }
    else { b.set_auto_trim(true); b.set_helm(0.0f); }
    if (k == 2000) (void)b.hoist(p.start_front_sail);
  }
}

Fleet make_scenario(std::uint64_t seed) {
  wm::SeaSettings ss;
  ss.wind_sea = wm::wind_sea_from_wind(static_cast<double>(kn(14.0f)), 10000.0, 0.0f);
  ss.swells.push_back({0.3f, 6.0f, 0.4f});
  Fleet f(seed, breeze(14.0f, 0.0f), &ss);
  f.add(perf("wm7"), 0.0f, 0.0f, deg(45.0f), 2.5f, perf("wm7").start_front_sail);
  f.add(perf("wm12"), 30.0f, -40.0f, deg(-45.0f), 3.0f, perf("wm12").start_front_sail);
  f.add(perf("wm7"), -25.0f, -60.0f, deg(50.0f), 2.5f, perf("wm7").start_front_sail);
  return f;
}

}  // namespace

// boat.md §10.5: two runs with the same inputs give identical checksums every tick; a run split in two through a
// snapshot save and load gives the same checksums as an unbroken run.
TEST_CASE("boat: determinism and snapshot round trip") {
  const std::uint32_t n = 6000;  // 5 minutes
  Fleet a = make_scenario(0xC0FFEE);
  Fleet b = make_scenario(0xC0FFEE);
  std::vector<std::uint64_t> sums;
  bool same = true;
  for (std::uint32_t i = 0; i < n; ++i) {
    script(a);
    script(b);
    const std::uint64_t ca = a.step();
    const std::uint64_t cb = b.step();
    if (ca != cb) same = false;
    sums.push_back(ca);
  }
  CHECK(same);

  // Split run: stop half way, save every boat, load into fresh boats, carry on.
  Fleet c = make_scenario(0xC0FFEE);
  for (std::uint32_t i = 0; i < n / 2; ++i) {
    script(c);
    c.step();
  }
  std::vector<std::vector<std::uint8_t>> saved;
  for (const auto& boat : c.boats) {
    wm::SnapshotWriter w;
    boat->save(w);
    saved.push_back(w.bytes());
  }
  for (std::size_t i = 0; i < c.boats.size(); ++i) {
    auto fresh = std::make_unique<wm::Boat>();
    fresh->init(&c.boats[i]->perf(), c.seed, static_cast<std::uint32_t>(i));
    wm::SnapshotReader r(saved[i]);
    REQUIRE(fresh->load(r));
    CHECK(r.at_end());
    c.boats[i] = std::move(fresh);
  }
  CHECK(c.checksum() == sums[n / 2 - 1]);
  bool split_same = true;
  for (std::uint32_t i = n / 2; i < n; ++i) {
    script(c);
    if (c.step() != sums[i]) split_same = false;
  }
  CHECK(split_same);

  // A different seed gives a different run (the wobble phases, the wind and the sea all move).
  Fleet d = make_scenario(0xC0FFEF);
  script(d);
  CHECK(d.step() != sums[0]);

  // The run sailed: every boat moved and none has a non-finite state.
  for (const auto& boat : a.boats) {
    const wm::BoatState& s = boat->state();
    CHECK(std::isfinite(s.pos_x));
    CHECK(std::isfinite(s.v));
    CHECK(std::hypot(s.pos_x, s.pos_y) > 50.0f);
  }
}

// A boat in the environment's wind and sea: it sails close to its polar at the wind it gets, heaves and pitches
// on the waves; sea.md §8.4: in Hs 0.4 m, Tp 2.7 s the larger boat pitches less than the smaller one.
TEST_CASE("boat: sailing in the wind field and the sea") {
  wm::SeaSettings ss;
  ss.wind_sea = {0.4f, 2.7f, 0.0f};
  wm::WindSettings ws = breeze(12.0f, 0.0f);
  ws.puffs_enabled = false;
  wm::apply_shift_preset(ws, wm::ShiftPreset::steady);
  Fleet f(42, ws, &ss);
  f.shadows = false;
  const float twa = deg(60.0f);
  wm::Boat& s = f.add(perf("wm7"), 0.0f, 0.0f, twa, 3.0f, perf("wm7").start_front_sail);
  wm::Boat& l = f.add(perf("wm12"), 0.0f, 400.0f, twa, 3.5f, perf("wm12").start_front_sail);
  const auto hold = [&](wm::Boat& b) {
    const float e = wm::wrap_pi(b.state().twa - twa);
    b.set_helm(wm::clamp(3.0f * e, -0.3f, 0.3f));
  };
  for (int i = 0; i < 1200; ++i) {
    hold(s);
    hold(l);
    f.step();
  }
  double ps = 0.0, pl = 0.0, zs = 0.0, rel_s = 0.0, rel_l = 0.0;
  const int n = 2400;
  for (int i = 0; i < n; ++i) {
    hold(s);
    hold(l);
    f.step();
    ps += static_cast<double>(s.state().theta * s.state().theta);
    pl += static_cast<double>(l.state().theta * l.state().theta);
    zs += static_cast<double>(s.state().z * s.state().z);
    rel_s += static_cast<double>(s.state().v / s.outputs().polar_speed);
    rel_l += static_cast<double>(l.state().v / l.outputs().polar_speed);
  }
  const float pitch_s = to_deg(static_cast<float>(std::sqrt(ps / n)));
  const float pitch_l = to_deg(static_cast<float>(std::sqrt(pl / n)));
  const float heave_s = static_cast<float>(std::sqrt(zs / n));
  MESSAGE("rms pitch wm7 ", pitch_s, " deg, wm12 ", pitch_l, " deg; rms heave wm7 ", heave_s,
          " m; mean speed / polar wm7 ", rel_s / n, ", wm12 ", rel_l / n);
  CHECK(pitch_l < pitch_s);
  CHECK(heave_s > 0.02f);
  CHECK(rel_s / n > 0.85);
  CHECK(rel_s / n < 1.1);
  CHECK(rel_l / n > 0.85);
  CHECK(rel_l / n < 1.1);
}

// wind_shadow.md §8.2 through the whole tick: two boats on the same tack, the second two mast heights downwind on
// the first's apparent wind axis. The second's speed settles lower, on its polar at the reduced true wind.
TEST_CASE("boat: second boat slows in the first's shadow") {
  wm::WindSettings ws = breeze(10.0f, 0.0f);
  ws.puffs_enabled = false;
  wm::apply_shift_preset(ws, wm::ShiftPreset::steady);
  Fleet f(7, ws, nullptr);
  // Without the attitude wobble, whose pitch moves the speed by a few percent (boat.md §5.8), so the two boats
  // compare at one instant.
  static wm::PerfData p = perf("wm7");
  p.dynamics.wobble_heel = 0.0f;
  p.dynamics.wobble_pitch = 0.0f;
  const float twa = deg(45.0f);
  const float v0 = p.config_for(p.start_front_sail)->polar.at(kn(10.0f), twa);
  wm::Boat& a = f.add(p, 0.0f, 0.0f, twa, v0, p.start_front_sail);
  // Two mast heights down A's apparent wind from its centre of effort.
  const wm::BoatState& sa = a.state();
  const wm::Vec2 fwd = wm::dir(sa.psi);
  const wm::Vec2 aw = wm::dir(sa.awd_from);
  const float h = p.dynamics.wind_shadow.height;
  const float ce = p.dynamics.wind_shadow.ce_x;
  const float bx = (sa.pos_x + ce * fwd.x) - (2.0f * h) * aw.x;
  const float by = (sa.pos_y + ce * fwd.y) - (2.0f * h) * aw.y;
  wm::Boat& b = f.add(p, bx, by, twa, v0, p.start_front_sail);
  // Both hold the same TWA, so B heads lower by the header; 20 s is short enough for the geometry to hold.
  const auto hold = [&](wm::Boat& bt) {
    const float e = wm::wrap_pi(bt.state().twa - twa);
    bt.set_helm(wm::clamp(3.0f * e, -0.3f, 0.3f));
  };
  for (int i = 0; i < static_cast<int>(20.0f / DT); ++i) {
    hold(a);
    hold(b);
    f.step();
  }
  const wm::EnvAtBoat& eb = f.env[1];
  const wm::EnvAtBoat& ea = f.env[0];
  const wm::ConfigPerf& c = *p.config_for(p.start_front_sail);
  const float expect_b = c.polar.at(b.state().tws, std::fabs(b.state().twa)) *
                         p.dynamics.heel_speed_factor.at(std::fabs(b.state().phi));
  MESSAGE("twa A ", to_deg(a.state().twa), " B ", to_deg(b.state().twa), "; A: loss ", ea.shadow_loss, ", v ", to_kn(a.state().v), " kn; B: loss ", eb.shadow_loss, ", header ",
          to_deg(eb.shadow_header), " deg, tws ", to_kn(b.state().tws), " kn, v ", to_kn(b.state().v),
          " kn (polar at its wind ", to_kn(expect_b), " kn)");
  CHECK(ea.shadow_source == -1);
  CHECK(eb.shadow_source == 0);
  CHECK(eb.shadow_loss > 0.05f);
  CHECK(b.state().tws < a.state().tws);
  CHECK(b.state().v < a.state().v);
  CHECK(b.state().v == doctest::Approx(expect_b).epsilon(0.05));
  // At the same TWA the header turns B's heading lower (away from the clean wind) by about the header.
  CHECK(wm::angle_diff(a.state().psi, b.state().psi) == doctest::Approx(eb.shadow_header).epsilon(0.2));
  CHECK(b.state().v == doctest::Approx(a.state().v * c.polar.at(b.state().tws, twa) / c.polar.at(a.state().tws, twa))
                           .epsilon(0.02));
}
