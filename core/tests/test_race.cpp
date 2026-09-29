// Race flow (race.md §12): starts under P and I, rounding marks in every leg geometry, gates, finishing with an
// unserved penalty and sub-tick finish order, the ranking distance on a beat, spawning, closing and the results.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "course/geometry.h"
#include "race_harness.h"

using namespace wm_test;
using wm::RaceEventKind;
using wm::Vec2;

namespace {

std::string num(double v) {
  char b[32];
  std::snprintf(b, sizeof b, "%.4f", v);
  return b;
}

std::string pt(Vec2 p) {
  return "{\"x\": " + num(static_cast<double>(p.x)) + ", \"y\": " + num(static_cast<double>(p.y)) + "}";
}

// Start line y = 0 from x = -100 to 100 (course side north), marks, a finish line and a sequence.
std::string course_json(const std::string& marks, const std::string& finish, const std::string& seq) {
  return R"({"schema": "windmark.course/1", "id": "t", "name": "T", "venue": "v", "frame": "world",
    "marks": [{"id": "rc", "type": "buoy", "at": {"x": 100, "y": 0}},
              {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}})" +
         marks + R"(], "start": {"ends": ["pin", "rc"]}, "finish": )" + finish + R"(, "sequence": )" + seq + "}";
}

// One mark m at (0, 300) to be left to `side`, then a finish line square to the exit leg through N.
std::string rounding_course(Vec2 N, const char* side) {
  const Vec2 M{0.0f, 300.0f};
  const Vec2 d = wm::v_unit(wm::v_sub(N, M), {0.0f, 1.0f});
  const Vec2 perp{-d.y, d.x};
  const Vec2 f1{N.x + perp.x * 40.0f, N.y + perp.y * 40.0f}, f2{N.x - perp.x * 40.0f, N.y - perp.y * 40.0f};
  return course_json(R"(, {"id": "m", "type": "buoy", "at": )" + pt(M) + R"(}, {"id": "f1", "type": "buoy", "at": )" +
                         pt(f1) + R"(}, {"id": "f2", "type": "buoy", "at": )" + pt(f2) + "}",
                     R"({"ends": ["f1", "f2"]})", std::string(R"([{"mark": "m", "round": ")") + side + "\"}]");
}

// A track that rounds M between the legs P→M and M→N: approach 40 m before M offset by r to one side, an arc
// around M, then out along the exit leg. `left_of_boat` = the mark on the boat's port side (anticlockwise).
std::vector<Vec2> rounding_path(Vec2 Pf, Vec2 Mf, Vec2 Nf, bool mark_to_port, double r = 12.0) {
  struct D2 {
    double x, y;
  };
  const D2 P{static_cast<double>(Pf.x), static_cast<double>(Pf.y)}, M{static_cast<double>(Mf.x), static_cast<double>(Mf.y)},
      N{static_cast<double>(Nf.x), static_cast<double>(Nf.y)};
  const double inx = M.x - P.x, iny = M.y - P.y, il = std::sqrt(inx * inx + iny * iny);
  const double ox = N.x - M.x, oy = N.y - M.y, ol = std::sqrt(ox * ox + oy * oy);
  const double dix = inx / il, diy = iny / il, dox = ox / ol, doy = oy / ol;
  // The boat's side of the mark: right of the leg for a port rounding, left for starboard.
  const double sgn = mark_to_port ? 1.0 : -1.0;
  const double oinx = sgn * diy, oiny = sgn * -dix, ooutx = sgn * doy, oouty = sgn * -dox;
  std::vector<Vec2> p;
  p.push_back({static_cast<float>(M.x - dix * 40.0 + oinx * r), static_cast<float>(M.y - diy * 40.0 + oiny * r)});
  const double a0 = std::atan2(oiny, oinx), a1 = std::atan2(oouty, ooutx);
  const double two_pi = 2.0 * 3.14159265358979;
  double d;
  if (mark_to_port) d = std::fmod(a1 - a0 + 2.0 * two_pi, two_pi);  // anticlockwise
  else d = -std::fmod(a0 - a1 + 2.0 * two_pi, two_pi);             // clockwise
  arc(p, Mf, r, a0, d);
  p.push_back({static_cast<float>(M.x + ooutx * r + dox * 60.0), static_cast<float>(M.y + oouty * r + doy * 60.0)});
  return p;
}

// Starts boat 0 from (0, -5) at the gun, then sails `path` (after a leg from the start). Returns the rig.
struct OneBoat {
  Rig rig;
  Track track;
  explicit OneBoat(const std::string& json, wm::PrepFlag flag = wm::PrepFlag::P)
      : rig(course_from(json), quick_settings(flag), 1) {
    rig.set(0, {0.0f, -5.0f}, 0.0f);
    rig.run_to(rig.gun() + 1);
    track.pts.push_back({0.0f, -5.0f});
  }
  void add(const std::vector<Vec2>& p) { track.pts.insert(track.pts.end(), p.begin(), p.end()); }
  void sail() {
    while (!track.done()) {
      Vec2 p;
      float psi = 0.0f;
      track.pose(p, psi);
      rig.set(0, p, psi);
      rig.step();
      track.advance();
    }
    rig.step();
  }
};

}  // namespace

TEST_CASE("race: start under P, 0.1 m over is OCS and on the line is not") {
  const std::string json = course_json(R"(, {"id": "w", "type": "buoy", "at": {"x": 0, "y": 300}},
      {"id": "f1", "type": "buoy", "at": {"x": -50, "y": 150}}, {"id": "f2", "type": "buoy", "at": {"x": 50, "y": 150}})",
                                       R"({"ends": ["f1", "f2"]})", R"([{"mark": "w", "round": "port"}])");
  Rig rig(course_from(json), quick_settings(wm::PrepFlag::P), 3);
  const float bow = perf("wm7").dynamics.collision.outline[8].x;  // stem point
  REQUIRE(bow == 3.455f);
  for (std::size_t i = 0; i < 3; ++i) rig.set(i, {-40.0f + 40.0f * static_cast<float>(i), -30.0f}, 0.0f);
  rig.run_to(rig.gun());
  CHECK(rig.race.state() == wm::RaceState::sequence);
  CHECK(rig.race.rules_live());
  rig.set(0, {-40.0f, -bow + 0.1f}, 0.0f);  // bow 0.1 m over
  rig.set(1, {0.0f, -bow}, 0.0f);           // bow exactly on the line (s = 0)
  rig.step();                               // the gun tick
  CHECK(rig.race.state() == wm::RaceState::racing);
  CHECK(rig.race.boat(0).ocs);
  CHECK(!rig.race.boat(1).ocs);
  CHECK(!rig.race.boat(2).ocs);
  CHECK(rig.race.x_flag());
  CHECK(rig.count(RaceEventKind::boat_ocs, 0) == 1);

  // Boat 1 sails off and starts; boat 0 crossing now is no start.
  for (int k = 1; k <= 20; ++k) {
    rig.set(0, {-40.0f, -bow + 0.1f + 0.25f * static_cast<float>(k)}, 0.0f);
    rig.set(1, {0.0f, -bow + 0.25f * static_cast<float>(k)}, 0.0f);
    rig.step();
  }
  CHECK(rig.race.boat(1).started);
  CHECK(rig.race.boat(1).t_start == doctest::Approx(0.0f).scale(1.0f).epsilon(0.01));
  CHECK(!rig.race.boat(0).started);
  CHECK(rig.race.returning(0));
  // Boat 0 returns completely behind the line, then starts.
  rig.set(0, {-40.0f, -10.0f}, wm::PI);
  rig.step();
  CHECK(!rig.race.boat(0).ocs);
  CHECK(rig.count(RaceEventKind::boat_returned, 0) == 1);
  CHECK(!rig.race.x_flag());
  for (int k = 1; k <= 60; ++k) {
    rig.set(0, {-40.0f, -10.0f + 0.25f * static_cast<float>(k)}, 0.0f);
    rig.step();
  }
  CHECK(rig.race.boat(0).started);
  CHECK(rig.race.boat(0).t_start > 0.5f);
}

TEST_CASE("race: start under I, back at the gun is OCS-I, released only around an end") {
  const std::string json = course_json(R"(, {"id": "w", "type": "buoy", "at": {"x": 0, "y": 300}},
      {"id": "f1", "type": "buoy", "at": {"x": -50, "y": 150}}, {"id": "f2", "type": "buoy", "at": {"x": 50, "y": 150}})",
                                       R"({"ends": ["f1", "f2"]})", R"([{"mark": "w", "round": "port"}])");
  Rig rig(course_from(json), quick_settings(wm::PrepFlag::I), 1);
  rig.set(0, {0.0f, -20.0f}, 0.0f);
  rig.run_to(rig.gun() - 600);  // -0:30
  rig.set(0, {0.0f, 2.0f}, 0.0f);  // over
  rig.step();
  CHECK(rig.race.boat(0).ocs_i);
  CHECK(rig.count(RaceEventKind::boat_ocs, 0) == 1);
  rig.set(0, {0.0f, -20.0f}, wm::PI);  // back behind well before the gun
  rig.run_to(rig.gun() + 1);
  CHECK(rig.race.boat(0).ocs_i);  // back through the line, not around an end
  CHECK(!rig.race.boat(0).started);

  Track t;
  t.pts = {{0.0f, -20.0f}, {0.0f, 20.0f}, {0.0f, -20.0f}, {0.0f, 20.0f}};  // dips through the band twice
  while (!t.done()) {
    Vec2 p;
    float psi = 0.0f;
    t.pose(p, psi);
    rig.set(0, p, psi);
    rig.step();
    t.advance();
  }
  CHECK(rig.race.boat(0).ocs_i);
  CHECK(!rig.race.boat(0).started);
  // Around the rc end (x = 100): east beyond the end, south across the extension, back west, then start.
  Track r;
  r.pts = {{0.0f, 20.0f}, {150.0f, 20.0f}, {150.0f, -20.0f}, {0.0f, -20.0f}, {0.0f, 30.0f}};
  bool released_behind = false;
  while (!r.done()) {
    Vec2 p;
    float psi = 0.0f;
    r.pose(p, psi);
    rig.set(0, p, psi);
    rig.step();
    if (!rig.race.boat(0).ocs_i && !rig.race.boat(0).started) released_behind = true;
    r.advance();
  }
  CHECK(released_behind);
  CHECK(rig.count(RaceEventKind::boat_returned, 0) == 1);
  CHECK(rig.race.boat(0).started);
}

TEST_CASE("race: rounding a mark in every leg geometry") {
  const Vec2 P{0.0f, 0.0f}, M{0.0f, 300.0f};
  struct Geo {
    const char* name;
    Vec2 N;
  };
  const Geo geos[] = {
      {"straight pass", {0.0f, 600.0f}},
      {"90 deg, mark inside the turn", {-300.0f, 300.0f}},
      {"90 deg, mark outside the turn", {300.0f, 300.0f}},
      {"180 deg U-turn", {40.0f, 20.0f}},
      {"30 deg hairpin", {-150.0f, 40.0f}},
  };
  for (const Geo& g : geos) {
    for (const char* side : {"port", "starboard"}) {
      const bool port = std::string(side) == "port";
      CAPTURE(g.name);
      CAPTURE(side);
      const std::string json = rounding_course(g.N, side);
      {
        OneBoat b(json);
        b.add(rounding_path(P, M, g.N, port));
        b.sail();
        CHECK(b.rig.count(RaceEventKind::started, 0) == 1);
        CHECK_MESSAGE(b.rig.count(RaceEventKind::rounded, 0) == 1, "correct track");
      }
      {
        OneBoat b(json);
        b.add(rounding_path(P, M, g.N, !port));
        b.sail();
        CHECK_MESSAGE(b.rig.count(RaceEventKind::rounded, 0) == 0, "mirror track on the wrong side");
      }
      {
        OneBoat b(json);
        std::vector<Vec2> wrong = rounding_path(P, M, g.N, !port);
        std::vector<Vec2> path(wrong.begin(), wrong.end() - 1);  // up to the end of the arc
        std::vector<Vec2> back(wrong.begin(), wrong.end() - 1);
        std::reverse(back.begin(), back.end());
        path.insert(path.end(), back.begin() + 1, back.end());  // unwind to the approach point
        const std::vector<Vec2> right = rounding_path(P, M, g.N, port);
        path.insert(path.end(), right.begin(), right.end());
        b.add(path);
        b.sail();
        CHECK_MESSAGE(b.rig.count(RaceEventKind::rounded, 0) == 1, "wrong side, unwound, then correct");
      }
    }
  }
}

namespace {

// A leeward gate as the second step: start, windward mark w (port), gate g1 (40, 100) / g2 (-40, 100), finish
// line at y = 250 crossed upwards.
std::string gate_course() {
  return course_json(R"(, {"id": "w", "type": "buoy", "at": {"x": 0, "y": 500}},
      {"id": "g1", "type": "buoy", "at": {"x": 40, "y": 100}}, {"id": "g2", "type": "buoy", "at": {"x": -40, "y": 100}},
      {"id": "f1", "type": "buoy", "at": {"x": -60, "y": 250}}, {"id": "f2", "type": "buoy", "at": {"x": 60, "y": 250}})",
                     R"({"ends": ["f1", "f2"]})", R"([{"mark": "w", "round": "port"}, {"gate": ["g1", "g2"]}])");
}

// Start, round w to port, then come down to (0, 200) above the gate.
std::vector<Vec2> to_gate() {
  std::vector<Vec2> p = rounding_path({0.0f, 0.0f}, {0.0f, 500.0f}, {0.0f, 100.0f}, true);
  p.push_back({0.0f, 200.0f});
  return p;
}

}  // namespace

TEST_CASE("race: gates") {
  const wm::ResolvedCourse rc = course_from(gate_course());
  REQUIRE(rc.steps[2].kind == wm::StepKind::gate);
  // Coming down from w, g1 (east) is on the boat's left: rounded to port.
  CHECK(rc.steps[2].sides[0] == wm::Side::port);
  CHECK(rc.steps[2].sides[1] == wm::Side::starboard);
  const Vec2 W{0.0f, 500.0f}, G1{40.0f, 100.0f}, G2{-40.0f, 100.0f}, F{0.0f, 250.0f};

  SUBCASE("between, then round g1") {
    OneBoat b(gate_course());
    b.add(to_gate());
    b.add(rounding_path(W, G1, F, true));
    b.add({{60.0f, 300.0f}});
    b.sail();
    CHECK(b.rig.count(RaceEventKind::rounded, 0) == 2);
    const wm::RaceEvent* e = nullptr;
    for (const wm::RaceEvent& x : b.rig.events) {
      if (x.kind == RaceEventKind::rounded && x.step == 2) e = &x;
    }
    REQUIRE(e != nullptr);
    CHECK(e->buoy == 3);  // mark index of g1
    CHECK(b.rig.race.boat(0).finished);
  }
  SUBCASE("between, then round g2") {
    OneBoat b(gate_course());
    b.add(to_gate());
    b.add(rounding_path(W, G2, F, false));
    b.add({{-60.0f, 300.0f}});
    b.sail();
    CHECK(b.rig.count(RaceEventKind::rounded, 0) == 2);
    CHECK(b.rig.race.boat(0).finished);
  }
  SUBCASE("between, no turn: not complete right after passing") {
    OneBoat b(gate_course());
    b.add(to_gate());
    b.add({{0.0f, 60.0f}});
    b.sail();
    CHECK(b.rig.count(RaceEventKind::rounded, 0) == 1);
  }
  SUBCASE("round g1 from outside without passing between") {
    OneBoat b(gate_course());
    b.add(to_gate());
    b.add({{70.0f, 160.0f}, {70.0f, 60.0f}, {90.0f, 40.0f}, {90.0f, 300.0f}});  // down outside g1 and back up
    b.sail();
    CHECK(b.rig.count(RaceEventKind::rounded, 0) == 1);
    CHECK(b.rig.race.boat(0).n_cross == 0);
  }
  SUBCASE("between, back through, then round: only after passing between again") {
    OneBoat b(gate_course());
    b.add(to_gate());
    b.add({{0.0f, 80.0f}, {0.0f, 130.0f}});  // down through and back up through
    b.sail();
    CHECK(b.rig.count(RaceEventKind::rounded, 0) == 1);
    CHECK(b.rig.race.boat(0).n_cross == 0);
    auto sail = [&](std::vector<Vec2> pts) {
      Track t;
      t.pts = std::move(pts);
      while (!t.done()) {
        Vec2 p;
        float psi = 0.0f;
        t.pose(p, psi);
        b.rig.set(0, p, psi);
        b.rig.step();
        t.advance();
      }
    };
    sail({{0.0f, 130.0f}, {20.0f, 130.0f}, {20.0f, 110.0f}});
    CHECK(b.rig.race.boat(0).n_cross == 0);
    sail({{20.0f, 110.0f}, {20.0f, 80.0f}});  // between again, southwards
    CHECK(b.rig.race.boat(0).n_cross == 1);
    CHECK(b.rig.count(RaceEventKind::rounded, 0) == 1);
    std::vector<Vec2> loop;
    arc(loop, G1, 28.28, std::atan2(-20.0, -20.0), 3.14159265358979 * 1.2);  // under g1 and up its east side
    loop.push_back({70.0f, 160.0f});
    sail(loop);
    CHECK(b.rig.count(RaceEventKind::rounded, 0) == 2);
  }
}

TEST_CASE("race: finishing with an unserved penalty, and sub-tick finish order") {
  const std::string json = gate_course();
  SUBCASE("penalty blocks the finish") {
    OneBoat b(json);
    b.add(to_gate());
    b.add(rounding_path({0.0f, 500.0f}, {40.0f, 100.0f}, {0.0f, 250.0f}, true));
    // Stop short of the line with a pending penalty, cross, come back and cross again.
    b.add({{55.0f, 245.0f}});
    b.sail();
    REQUIRE(b.rig.race.boat(0).next == 3);
    b.rig.pending[0] = 1;
    Track t;
    t.pts = {{55.0f, 245.0f}, {55.0f, 265.0f}};
    while (!t.done()) {
      Vec2 p;
      float psi = 0.0f;
      t.pose(p, psi);
      b.rig.set(0, p, psi);
      b.rig.step();
      t.advance();
    }
    CHECK(!b.rig.race.boat(0).finished);
    CHECK(b.rig.count(RaceEventKind::finish_blocked, 0) == 1);
    b.rig.pending[0] = 0;  // penalty taken beyond the line
    // Still beyond: crossing again needs a return to the course side first.
    t.pts = {{55.0f, 265.0f}, {55.0f, 262.0f}, {55.0f, 275.0f}};
    t.s = 0.0;
    while (!t.done()) {
      Vec2 p;
      float psi = 0.0f;
      t.pose(p, psi);
      b.rig.set(0, p, psi);
      b.rig.step();
      t.advance();
    }
    CHECK(!b.rig.race.boat(0).finished);
    t.pts = {{55.0f, 275.0f}, {55.0f, 240.0f}, {55.0f, 262.0f}};
    t.s = 0.0;
    while (!t.done()) {
      Vec2 p;
      float psi = 0.0f;
      t.pose(p, psi);
      b.rig.set(0, p, psi);
      b.rig.step();
      t.advance();
    }
    CHECK(b.rig.race.boat(0).finished);
    CHECK(b.rig.race.boat(0).place == 1);
  }
  SUBCASE("two boats in one tick are ordered by the crossing fraction") {
    Rig rig(course_from(json), quick_settings(), 2);
    rig.set(0, {-10.0f, -5.0f}, 0.0f);
    rig.set(1, {10.0f, -5.0f}, 0.0f);
    rig.run_to(rig.gun() + 1);
    Track tr[2];
    const std::vector<Vec2> p = to_gate();
    const std::vector<Vec2> r = rounding_path({0.0f, 500.0f}, {40.0f, 100.0f}, {0.0f, 250.0f}, true);
    for (std::size_t i = 0; i < 2; ++i) {
      tr[i].pts = {{i == 0 ? -10.0f : 10.0f, -5.0f}};
      tr[i].pts.insert(tr[i].pts.end(), p.begin(), p.end());
      tr[i].pts.insert(tr[i].pts.end(), r.begin(), r.end());
      tr[i].pts.push_back({i == 0 ? 30.0f : 50.0f, 240.0f});
    }
    while (!tr[0].done() || !tr[1].done()) {
      for (std::size_t i = 0; i < 2; ++i) {
        Vec2 q;
        float psi = 0.0f;
        tr[i].pose(q, psi);
        rig.set(i, q, psi);
        tr[i].advance();
      }
      rig.step();
    }
    REQUIRE(rig.race.boat(0).next == 3);
    REQUIRE(rig.race.boat(1).next == 3);
    // Both sail north at 5 m/s, boat 1 0.08 m behind: bows at 243.455 + 0.25 k and 0.08 less.
    std::uint32_t t0 = 0, t1 = 0;
    for (int k = 0; k <= 40; ++k) {
      const float y = 240.0f + 0.25f * static_cast<float>(k);
      rig.set(0, {30.0f, y}, 0.0f);
      rig.set(1, {50.0f, y - 0.08f}, 0.0f);
      rig.step();
      if (rig.race.boat(0).finished && t0 == 0) t0 = rig.n;
      if (rig.race.boat(1).finished && t1 == 0) t1 = rig.n;
    }
    REQUIRE(rig.race.boat(0).finished);
    REQUIRE(rig.race.boat(1).finished);
    CHECK(t0 == t1);
    CHECK(rig.race.boat(0).t_finish_us < rig.race.boat(1).t_finish_us);
    CHECK(rig.race.boat(1).t_finish_us - rig.race.boat(0).t_finish_us == 16000);  // 0.08 m at 5 m/s
    CHECK(rig.race.boat(0).place == 1);
    CHECK(rig.race.boat(1).place == 2);
  }
}

TEST_CASE("race: ranking distance on a beat is measured along the wind axis") {
  const std::string json = course_json(R"(, {"id": "w", "type": "buoy", "at": {"x": 0, "y": 800}},
      {"id": "f1", "type": "buoy", "at": {"x": -50, "y": 150}}, {"id": "f2", "type": "buoy", "at": {"x": 50, "y": 150}})",
                                       R"({"ends": ["f1", "f2"]})", R"([{"mark": "w", "round": "port"}])");
  Rig rig(course_from(json), quick_settings(), 3);
  rig.set(0, {-60.0f, -5.0f}, 0.0f);
  rig.set(1, {60.0f, -5.0f}, 0.0f);
  rig.set(2, {0.0f, -40.0f}, 0.0f);
  rig.run_to(rig.gun() + 1);
  Track a, b;
  a.pts = {{-60.0f, -5.0f}, {-150.0f, 300.0f}};
  b.pts = {{60.0f, -5.0f}, {150.0f, 300.0f}};
  a.speed = b.speed = 6.0f;
  while (!a.done()) {
    Vec2 q;
    float psi = 0.0f;
    a.pose(q, psi);
    rig.set(0, q, psi);
    b.pose(q, psi);
    rig.set(1, q, psi);
    rig.step();
    a.advance();
    b.advance();
  }
  rig.set(0, {-150.0f, 300.0f}, 0.0f);
  rig.set(1, {150.0f, 300.0f}, 0.0f);
  rig.step();
  REQUIRE(rig.race.boat(0).started);
  REQUIRE(rig.race.boat(1).started);
  CHECK(std::fabs(rig.race.boat(0).D - rig.race.boat(1).D) <= 1.0f);
  // Leg 1 is on the wind axis; the remaining distance is the rest of the beat plus the run to the finish.
  CHECK(rig.race.legs()[1].wind_axis);
  CHECK(rig.race.boat(0).D == doctest::Approx(800.0f - 300.0f - 3.455f + 650.0f).epsilon(0.002));
  // The boat that has not started ranks behind the two that have.
  CHECK(rig.race.boat(2).rank == 3);
}

TEST_CASE("race: spawn grid and order") {
  const std::string json = course_json(R"(, {"id": "w", "type": "buoy", "at": {"x": 0, "y": 800}},
      {"id": "f1", "type": "buoy", "at": {"x": -50, "y": 150}}, {"id": "f2", "type": "buoy", "at": {"x": 50, "y": 150}})",
                                       R"({"ends": ["f1", "f2"]})", R"([{"mark": "w", "round": "port"}])");
  const wm::ResolvedCourse rc = course_from(json);
  const float L = 7.2f;
  const std::vector<Vec2> s = wm::spawn_slots(rc, nullptr, L, 20);
  REQUIRE(s.size() >= 20);
  // First row 4 L behind the line, slots 3 L apart, ordered along the line; next row 3 L further back.
  CHECK(s[0].y == doctest::Approx(-4.0f * L));
  CHECK(s[1].x - s[0].x == doctest::Approx(3.0f * L));
  for (const Vec2 p : s) {
    CHECK(p.y < 0.0f);
    CHECK(std::fabs(p.x) <= 200.0f + 0.01f);
    // No slot within 2 L of the line-end buoys.
    CHECK(wm::v_dist(p, {100.0f, 0.0f}) - 0.8f >= 2.0f * L);
  }
  const std::vector<std::int32_t> o1 = wm::spawn_order(42, 10), o2 = wm::spawn_order(42, 10), o3 = wm::spawn_order(43, 10);
  CHECK(o1 == o2);
  CHECK(o1 != o3);
  std::vector<std::int32_t> sorted = o1;
  std::sort(sorted.begin(), sorted.end());
  for (std::int32_t i = 0; i < 10; ++i) CHECK(sorted[static_cast<std::size_t>(i)] == i);
}

TEST_CASE("race: closing and results") {
  const std::string json = gate_course();
  wm::RaceSettings s = quick_settings(wm::PrepFlag::Z);
  s.finish_window = true;
  Rig rig(course_from(json), s, 6);
  // 0, 1 finish (1 was in the start triangle under Z), 2 retires, 3 is disqualified, 4 never comes near, 5 sails
  // but never starts.
  for (std::size_t i = 0; i < 6; ++i) rig.set(i, {-50.0f + 20.0f * static_cast<float>(i), -20.0f}, 0.0f);
  rig.set(4, {0.0f, -1500.0f}, 0.0f);
  rig.run_to(rig.gun() - 400);
  rig.set(1, {0.0f, 20.0f}, 0.0f);  // inside the start triangle in the last minute
  rig.step();
  CHECK(rig.race.boat(1).z_flag);
  rig.set(1, {0.0f, -20.0f}, 0.0f);
  rig.run_to(rig.gun() + 1);
  for (int k = 1; k <= 120; ++k) {
    rig.set(2, {10.0f, -20.0f + 0.25f * static_cast<float>(k)}, 0.0f);
    rig.step();
  }
  REQUIRE(rig.race.boat(2).started);
  rig.race.retire(2, rig.n);
  rig.race.disqualify(3, rig.n);
  Track a, c;
  a.pts = {{-50.0f, -20.0f}};
  const std::vector<Vec2> p = to_gate();
  a.pts.insert(a.pts.end(), p.begin(), p.end());
  const std::vector<Vec2> r = rounding_path({0.0f, 500.0f}, {40.0f, 100.0f}, {0.0f, 250.0f}, true);
  a.pts.insert(a.pts.end(), r.begin(), r.end());
  a.pts.push_back({55.0f, 300.0f});
  c = a;
  c.pts[0] = {-30.0f, -20.0f};
  c.speed = 4.5f;
  for (int k = 0; k < 40000 && rig.race.state() != wm::RaceState::closed; ++k) {
    Vec2 q;
    float psi = 0.0f;
    a.pose(q, psi);
    rig.set(0, q, psi);
    c.pose(q, psi);
    rig.set(1, q, psi);
    rig.step();
    a.advance();
    c.advance();
  }
  REQUIRE(rig.race.state() == wm::RaceState::closed);
  CHECK(rig.count(RaceEventKind::race_closing) == 1);
  const std::vector<wm::ResultRow>& res = rig.race.results();
  REQUIRE(res.size() == 6);
  CHECK(res[0].boat == 0);
  CHECK(res[0].points == 1.0f);
  CHECK(res[1].boat == 1);
  CHECK(res[1].code == wm::ScoreCode::ZFP);
  CHECK(res[1].points == 2.0f + 1.0f);  // place 2 + 20 % of 6 entries rounded (1)
  CHECK(res[2].code == wm::ScoreCode::DNC);
  CHECK(res[2].boat == 4);
  CHECK(res[3].code == wm::ScoreCode::DNS);
  CHECK(res[3].boat == 5);
  CHECK(res[4].boat == 2);
  CHECK(res[4].code == wm::ScoreCode::RET);
  CHECK(res[5].code == wm::ScoreCode::DSQ);
  for (std::size_t i = 2; i < 6; ++i) CHECK(res[i].points == 7.0f);
  // Boats 4 and 5 were ghosted at the start limit; the finishers when they cleared the line.
  CHECK(rig.race.boat(4).ghost);
  CHECK(rig.race.boat(0).ghost_reason == wm::GhostReason::finished);
}

TEST_CASE("race: projected finishes are scaled by performance_scale (race.md §7.2)") {
  // Boat 0 is human; 1 and 2 are AI boats at the same distance to go, 2 with an Easy performance_scale of 0.9.
  // When the human retires the race closes and both AI boats are projected; 2 sails the rest 1/0.9 as long.
  const wm::ResolvedCourse course = course_from(rounding_course({0.0f, 600.0f}, "port"));
  wm::Race race;
  race.add_boat(&perf("wm7"), true);
  race.add_boat(&perf("wm7"), false, 1.0f);
  race.add_boat(&perf("wm7"), false, 0.9f);
  CHECK(race.boat(2).performance_scale == 0.9f);
  std::string err;
  REQUIRE_MESSAGE(race.create(course, quick_settings(), 0, 0.0f, err), err);
  std::vector<wm::RaceBoatInput> in(3);
  const std::vector<std::uint8_t> pending(3, 0);
  for (std::size_t i = 0; i < 3; ++i) {
    in[i].pos = {-20.0f + 20.0f * static_cast<float>(i), -5.0f};
    in[i].tws = 6.0f;
  }
  std::uint32_t n = 0;
  auto step = [&] {
    race.progress(n, in, pending, 0.0f);
    race.rank(n, in);
    race.clear_events();
    ++n;
  };
  while (n <= static_cast<std::uint32_t>(race.n_gun())) step();
  in[1].pos = {0.0f, 50.0f};
  in[2].pos = {20.0f, 50.0f};
  step();
  REQUIRE(race.boat(1).started);
  REQUIRE(race.boat(2).started);
  race.retire(0, n);
  const std::uint32_t n_close = n;
  step();
  REQUIRE(race.state() == wm::RaceState::closed);
  const float t_now = race.race_time(n_close);
  REQUIRE(race.boat(1).projected);
  REQUIRE(race.boat(2).projected);
  const float d1 = race.boat(1).t_proj - t_now, d2 = race.boat(2).t_proj - t_now;
  REQUIRE(d1 > 10.0f);
  CHECK(d2 == doctest::Approx(d1 / 0.9f).epsilon(1e-4));
  const std::vector<wm::ResultRow>& res = race.results();
  REQUIRE(res.size() == 3);
  CHECK(res[0].boat == 1);
  CHECK(res[0].projected);
  CHECK(res[1].boat == 2);
  CHECK(res[1].projected);
  CHECK(res[1].t_finish_us > res[0].t_finish_us);
}

TEST_CASE("race: general recall escalates the flag and moves the gun") {
  const std::string json = gate_course();
  wm::RaceSettings s = quick_settings(wm::PrepFlag::P);
  s.general_recall = true;
  Rig rig(course_from(json), s, 5);
  for (std::size_t i = 0; i < 5; ++i) rig.set(i, {-60.0f + 30.0f * static_cast<float>(i), -20.0f}, 0.0f);
  rig.run_to(rig.gun());
  const std::int64_t gun0 = rig.race.n_gun();
  for (std::size_t i = 0; i < 3; ++i) rig.set(i, {-60.0f + 30.0f * static_cast<float>(i), 1.0f}, 0.0f);
  rig.step();
  CHECK(rig.race.general_recalls() == 1);
  CHECK(rig.race.prep_flag() == wm::PrepFlag::I);
  CHECK(rig.race.n_gun() == gun0 + (60 + 180) * 20);
  CHECK(rig.race.state() == wm::RaceState::sequence);
  CHECK(!rig.race.boat(0).ocs);
  CHECK(!rig.race.rules_live());
  for (std::size_t i = 0; i < 5; ++i) rig.set(i, {-60.0f + 30.0f * static_cast<float>(i), -20.0f}, 0.0f);
  rig.run_to(static_cast<std::uint32_t>(rig.race.n_gun()) + 1);
  CHECK(rig.race.state() == wm::RaceState::racing);
  CHECK(rig.count(RaceEventKind::signal) >= 9);
}
