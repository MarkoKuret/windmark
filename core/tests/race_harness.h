// Scripted set-up for the race and rules tests: a course from a JSON string, a Race over boats of the shipped
// classes, and tracks (polylines sailed at a constant speed) that give each boat her pose every tick. No physics:
// the race and the rules only read poses and motion (race.md §0, rules.md §3.1).
#pragma once

#include <cmath>
#include <string>
#include <vector>

#include "boat_harness.h"
#include "course/course.h"
#include "doctest.h"
#include "race/race.h"

namespace wm_test {

inline wm::ResolvedCourse course_from(const std::string& json, float twd_c = 0.0f) {
  wm::CourseData c;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_course(json, "test.course.json", c, err), err.message());
  wm::ResolvedCourse rc;
  wm::resolve_course(c, twd_c, 1.0f, rc);
  return rc;
}

// A polyline sailed at `speed` m/s from its first point; the heading follows the segment.
struct Track {
  std::vector<wm::Vec2> pts;
  float speed = 5.0f;
  double s = 0.0;

  bool done() const { return s >= length(); }
  double length() const {
    double l = 0.0;
    for (std::size_t i = 1; i < pts.size(); ++i) l += seg(i);
    return l;
  }
  double seg(std::size_t i) const {
    const double dx = static_cast<double>(pts[i].x) - static_cast<double>(pts[i - 1].x);
    const double dy = static_cast<double>(pts[i].y) - static_cast<double>(pts[i - 1].y);
    return std::sqrt(dx * dx + dy * dy);
  }
  // Pose at the current arc length.
  void pose(wm::Vec2& p, float& psi) const {
    double rem = s;
    for (std::size_t i = 1; i < pts.size(); ++i) {
      const double l = seg(i);
      if (rem <= l || i + 1 == pts.size()) {
        const double f = l > 0.0 ? std::fmin(rem / l, 1.0) : 0.0;
        const double ax = static_cast<double>(pts[i - 1].x), ay = static_cast<double>(pts[i - 1].y);
        const double bx = static_cast<double>(pts[i].x), by = static_cast<double>(pts[i].y);
        p = {static_cast<float>(ax + f * (bx - ax)), static_cast<float>(ay + f * (by - ay))};
        if (l > 1e-9) psi = wm::compass({static_cast<float>(bx - ax), static_cast<float>(by - ay)});
        return;
      }
      rem -= l;
    }
    p = pts.back();
  }
  void advance() { s += static_cast<double>(speed) * static_cast<double>(wm::DT); }
};

// Points on a circle around m (radius r) from math angle a0 through a signed sweep d (rad, > 0 anticlockwise).
inline void arc(std::vector<wm::Vec2>& out, wm::Vec2 m, double r, double a0, double d) {
  const int n = static_cast<int>(std::ceil(std::fabs(d) / (5.0 * 3.14159265358979 / 180.0)));
  for (int k = 0; k <= n; ++k) {
    const double a = a0 + d * (n > 0 ? static_cast<double>(k) / n : 0.0);
    out.push_back({static_cast<float>(static_cast<double>(m.x) + r * std::cos(a)),
                   static_cast<float>(static_cast<double>(m.y) + r * std::sin(a))});
  }
}

struct Rig {
  wm::ResolvedCourse course;
  wm::Race race;
  std::vector<wm::RaceBoatInput> in;
  std::vector<std::uint8_t> pending;
  std::vector<wm::RaceEvent> events;
  std::uint32_t n = 0;

  Rig(const wm::ResolvedCourse& rc, const wm::RaceSettings& s, int boats, const std::string& cls = "wm7") : course(rc) {
    for (int i = 0; i < boats; ++i) race.add_boat(&perf(cls), true);
    in.resize(static_cast<std::size_t>(boats));
    pending.assign(static_cast<std::size_t>(boats), 0);
    std::string err;
    REQUIRE_MESSAGE(race.create(course, s, 0, 0.0f, err), err);
  }
  void step() {
    race.progress(n, in, pending, 0.0f);
    race.rank(n, in);
    for (const wm::RaceEvent& e : race.events()) events.push_back(e);
    race.clear_events();
    ++n;
  }
  std::uint32_t gun() const { return static_cast<std::uint32_t>(race.n_gun()); }
  void set(std::size_t i, wm::Vec2 p, float psi) {
    in[i].pos = p;
    in[i].psi = psi;
  }
  // Runs until tick `until` (exclusive) with the boats where they are.
  void run_to(std::uint32_t until) {
    while (n < until) step();
  }
  int count(wm::RaceEventKind k, std::int32_t boat = -1) const {
    int c = 0;
    for (const wm::RaceEvent& e : events) {
      if (e.kind == k && (boat < 0 || e.boat == boat)) ++c;
    }
    return c;
  }
  const wm::RaceEvent* find(wm::RaceEventKind k, std::int32_t boat = -1) const {
    for (const wm::RaceEvent& e : events) {
      if (e.kind == k && (boat < 0 || e.boat == boat)) return &e;
    }
    return nullptr;
  }
};

inline wm::RaceSettings quick_settings(wm::PrepFlag flag = wm::PrepFlag::P) {
  wm::RaceSettings s;
  s.sequence = wm::SequenceKind::s3210;
  s.prep_flag = flag;
  s.free_sailing_s = 0.0f;
  return s;
}

}  // namespace wm_test
