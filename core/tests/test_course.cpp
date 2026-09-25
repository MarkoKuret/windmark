// Course files (courses.md): the shipped example course, expansion and laps, laying a wind-relative course,
// gate sides and line orientation, the scale factor, the canonical hash, and the refusals of §7.
#include <cmath>
#include <string>
#include <vector>

#include "boat_harness.h"
#include "course/course.h"
#include "course/geometry.h"
#include "data/venue.h"
#include "doctest.h"

namespace {

const std::string kData = WINDMARK_DATA_DIR;
const std::string kCourses = WINDMARK_COURSES_DIR;

const wm::VenueData& bay() {
  static wm::VenueData v;
  static bool loaded = false;
  if (!loaded) {
    wm::LoadError err;
    REQUIRE_MESSAGE(wm::load_venue(kData + "/venues/example_bay.venue.json", v, err), err.message());
    loaded = true;
  }
  return v;
}

// A small world-frame course; the refusal cases replace one piece of it.
struct Parts {
  std::string header = R"("schema": "windmark.course/1", "id": "t", "name": "T", "venue": "example_bay",
                          "frame": "world")";
  std::string marks = R"([
    {"id": "rc", "type": "committee_boat", "at": {"x": 100, "y": 0}, "heading": 0},
    {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}},
    {"id": "w", "type": "buoy", "style": "large", "at": {"x": 0, "y": 500}},
    {"id": "g1", "type": "buoy", "at": {"x": 30, "y": -150}},
    {"id": "g2", "type": "buoy", "at": {"x": -30, "y": -150}}])";
  std::string start = R"({"ends": ["pin", "rc"]})";
  std::string finish = R"("start")";
  std::string sequence = R"([{"mark": "w", "round": "port"}, {"gate": ["g1", "g2"]}, {"mark": "w", "round": "port"},
                             {"gate": ["g1", "g2"]}])";
  std::string extra;

  std::string text() const {
    return "{" + header + ", \"marks\": " + marks + ", \"start\": " + start + ", \"finish\": " + finish +
           ", \"sequence\": " + sequence + extra + "}";
  }
};

void refuse(const std::string& name, const std::string& text, const std::string& path) {
  CAPTURE(name);
  wm::CourseData c;
  wm::LoadError err;
  CHECK(!wm::parse_course(text, "t.course.json", c, err));
  CHECK(!err.reason.empty());
  CHECK_MESSAGE(err.path.rfind(path, 0) == 0, err.message());
  CHECK(c.marks.empty());
  CHECK(c.id.empty());
}

bool geometry_fails(const std::string& name, const std::string& text, const std::string& why_part,
                    float L = 7.2f) {
  CAPTURE(name);
  wm::CourseData c;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_course(text, "t.course.json", c, err), err.message());
  std::vector<std::string> warnings;
  const bool ok = wm::validate_course(c, bay(), {L, 8}, warnings, err);
  CHECK_MESSAGE(err.reason.find(why_part) != std::string::npos, err.message());
  return !ok;
}

}  // namespace

TEST_CASE("course: the example course loads and validates for every wind direction") {
  wm::CourseData c;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_course(kCourses + "/example_bay/example_wl.course.json", c, err), err.message());
  CHECK(c.id == "example_wl");
  CHECK(c.venue == "example_bay");
  CHECK(c.frame == wm::CourseFrame::wind);
  CHECK(c.marks.size() == 10);
  CHECK(c.file_sha256.size() == 64);
  std::vector<std::string> warnings;
  CHECK_MESSAGE(wm::validate_course(c, bay(), {12.0f, 12}, warnings, err), err.message());
  for (const std::string& w : warnings) MESSAGE("warning: ", w);

  // Expansion (courses.md §4.4): start, w, off, gate, "lap", w, off, finish.
  REQUIRE(c.expanded.size() == 7);
  const wm::StepKind kinds[] = {wm::StepKind::start, wm::StepKind::mark, wm::StepKind::mark, wm::StepKind::gate,
                                wm::StepKind::mark, wm::StepKind::mark, wm::StepKind::finish};
  const int laps[] = {1, 1, 1, 1, 2, 2, 2};
  const int legs[] = {0, 1, 2, 3, 1, 2, 3};
  for (std::size_t i = 0; i < 7; ++i) {
    CAPTURE(i);
    CHECK(c.expanded[i].kind == kinds[i]);
    CHECK(c.expanded[i].lap == laps[i]);
    CHECK(c.expanded[i].leg_in_lap == legs[i]);
  }
}

TEST_CASE("course: laying the example course to the wind") {
  wm::CourseData c;
  wm::LoadError err;
  REQUIRE(wm::load_course(kCourses + "/example_bay/example_wl.course.json", c, err));
  wm::ResolvedCourse rc;
  wm::resolve_course(c, 0.0f, 1.0f, rc);
  auto at = [&](const char* id) { return rc.marks[static_cast<std::size_t>(c.find_mark(id))].pos; };
  // Wind from the north: the line is square to it at y = -300, the windward mark 700 m above the midpoint.
  CHECK(at("rc").x == doctest::Approx(125.0f).epsilon(1e-5));
  CHECK(at("rc").y == doctest::Approx(-300.0f).epsilon(1e-5));
  CHECK(at("pin").x == doctest::Approx(-125.0f).epsilon(1e-5));
  CHECK(at("w").x == doctest::Approx(0.0f).scale(1000.0f).epsilon(1e-5));
  CHECK(at("w").y == doctest::Approx(400.0f).epsilon(1e-5));
  CHECK(at("off").x == doctest::Approx(-60.0f).epsilon(1e-4));
  CHECK(at("g1").x == doctest::Approx(40.0f).epsilon(1e-4));
  CHECK(at("g1").y == doctest::Approx(-150.0f).epsilon(1e-4));
  CHECK(rc.laps == 2);
  REQUIRE(rc.legs_per_lap.size() == 2);
  CHECK(rc.legs_per_lap[0] == 3);
  CHECK(rc.legs_per_lap[1] == 3);

  // Line orientation (race.md §3.3, §6.1): the course side on the left of A→B.
  const wm::CourseStep& s = rc.start();
  CHECK(rc.mark_ids[static_cast<std::size_t>(s.marks[0])] == "pin");
  CHECK(rc.mark_ids[static_cast<std::size_t>(s.marks[1])] == "rc");
  CHECK(wm::side_left(rc.steps[1].ref, rc.end_a(s), rc.end_b(s)) > 0.0f);
  const wm::CourseStep& f = rc.finish();
  CHECK(rc.mark_ids[static_cast<std::size_t>(f.marks[0])] == "fp");
  CHECK(wm::side_left(rc.steps[5].ref, rc.end_a(f), rc.end_b(f)) > 0.0f);

  // courses.md §10 gate sides: coming down from off, g1 (right looking upwind) is rounded to port.
  const wm::CourseStep& g = rc.steps[3];
  CHECK(rc.mark_ids[static_cast<std::size_t>(g.marks[0])] == "g1");
  CHECK(g.sides[0] == wm::Side::port);
  CHECK(g.sides[1] == wm::Side::starboard);

  // Head-to-wind committee and mark boats face the axis; their outlines are collision objects.
  CHECK(rc.marks[0].heading == 0.0f);
  std::size_t boats = 0, circles = 0;
  for (const wm::CourseObject& o : rc.objects) {
    if (o.is_boat) {
      ++boats;
      CHECK(o.polygon.size() == 17);
    } else {
      ++circles;
    }
  }
  CHECK(boats == 2);
  CHECK(circles == 6);  // two virtual points are not objects

  // Wind from the east: everything turns a quarter.
  wm::ResolvedCourse re;
  wm::resolve_course(c, wm::HALF_PI, 1.0f, re);
  const wm::Vec2 w = re.marks[static_cast<std::size_t>(c.find_mark("w"))].pos;
  CHECK(w.x == doctest::Approx(700.0f).epsilon(1e-5));
  CHECK(w.y == doctest::Approx(-300.0f).epsilon(1e-5));
  CHECK(re.marks[0].heading == wm::HALF_PI);

  // Scaling multiplies only non-fixed distances.
  wm::ResolvedCourse r2;
  wm::resolve_course(c, 0.0f, 2.0f, r2);
  CHECK(r2.marks[static_cast<std::size_t>(c.find_mark("w"))].pos.y == doctest::Approx(1100.0f).epsilon(1e-5));
  CHECK(r2.marks[static_cast<std::size_t>(c.find_mark("rc"))].pos.x == doctest::Approx(125.0f).epsilon(1e-5));
}

TEST_CASE("course: axis, scale and hash") {
  CHECK(wm::course_axis(0.123f) == doctest::Approx(0.12f));
  CHECK(wm::course_axis(-0.004f) == 0.0f);
  CHECK(wm::course_axis(6.2799f) < wm::TWO_PI);

  wm::CourseData c;
  wm::LoadError err;
  REQUIRE(wm::load_course(kCourses + "/example_bay/example_wl.course.json", c, err));
  const float k = wm::course_scale(c, 0.0f, wm_test::perf("wm7"), wm_test::kn(12.0f));
  MESSAGE("wm7 scale for 600 s at 12 kn: ", k);
  CHECK(k >= 0.5f);
  CHECK(k <= 2.0f);
  const wm::PolarVmg v = wm::polar_vmg(wm_test::perf("wm7"), wm_test::kn(12.0f));
  CHECK(v.up_twa > wm_test::deg(30.0f));
  CHECK(v.up_twa < wm_test::deg(55.0f));
  CHECK(v.down_twa > wm_test::deg(120.0f));
  CHECK(v.up_speed > 1.0f);

  wm::ResolvedCourse a, b, d;
  wm::resolve_course(c, 0.3f, k, a);
  wm::resolve_course(c, 0.3f, k, b);
  wm::resolve_course(c, 0.31f, k, d);
  CHECK(a.hash() == b.hash());
  CHECK(a.hash() != d.hash());
  CHECK(a.hash().size() == 64);
  const std::string j = a.canonical_json();
  CHECK(j.find(' ') == std::string::npos);
  CHECK(j.rfind("{\"area\":", 0) == 0);
}

TEST_CASE("course: laps from repeat blocks") {
  Parts p;
  p.sequence = R"([{"mark": "w", "round": "port"},
                   {"repeat": 3, "steps": [{"gate": ["g1", "g2"]}, {"mark": "w", "round": "port"}]},
                   {"gate": ["g1", "g2"]}])";
  p.finish = R"({"ends": ["pin", "rc"]})";
  wm::CourseData c;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_course(p.text(), "t.course.json", c, err), err.message());
  // start, w, (g, w) x3, g, finish
  REQUIRE(c.expanded.size() == 10);
  const int laps[] = {1, 1, 1, 1, 2, 2, 3, 3, 3, 3};
  for (std::size_t i = 0; i < 10; ++i) {
    CAPTURE(i);
    CHECK(c.expanded[i].lap == laps[i]);
  }
  CHECK(c.expanded[3].leg_in_lap == 3);
  CHECK(c.expanded[4].leg_in_lap == 1);
}

TEST_CASE("course: the test course is valid") {
  Parts p;
  wm::CourseData c;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_course(p.text(), "t.course.json", c, err), err.message());
  CHECK(c.finish_is_start);
  std::vector<std::string> warnings;
  CHECK_MESSAGE(wm::validate_course(c, bay(), {7.2f, 8}, warnings, err), err.message());
  for (const std::string& w : warnings) MESSAGE("warning: ", w);
  wm::ResolvedCourse rc;
  wm::resolve_course(c, 0.0f, 1.0f, rc);
  // Finishing on the start line upwards from the gate: the finish's course side is below the line.
  CHECK(wm::side_left(rc.steps[rc.steps.size() - 2].ref, rc.end_a(rc.finish()), rc.end_b(rc.finish())) > 0.0f);
  CHECK(wm::side_left(rc.steps[1].ref, rc.end_a(rc.start()), rc.end_b(rc.start())) > 0.0f);
}

TEST_CASE("course: file refusals") {
  {
    Parts p;
    p.header = R"("schema": "windmark.course/2", "id": "t", "name": "T", "venue": "example_bay", "frame": "world")";
    refuse("major version", p.text(), "$.schema");
  }
  {
    Parts p;
    p.header = R"("schema": "windmark.course/1", "id": "t", "name": "Bay )" "\xE2\x80\x94" R"( 2 laps",
                  "venue": "example_bay", "frame": "world")";
    refuse("em dash", p.text(), "$.name");
  }
  {
    Parts p;
    p.marks = R"([{"id": "rc", "type": "buoy", "at": {"x": 0, "y": 0}}, {"id": "rc", "type": "buoy", "at": {"x": 1, "y": 0}}])";
    refuse("duplicate id", p.text(), "$.marks[1].id");
  }
  {
    Parts p;
    p.marks = R"([{"id": "a_mid", "type": "buoy", "at": {"x": 0, "y": 0}}])";
    refuse("reserved id", p.text(), "$.marks[0].id");
  }
  {
    Parts p;
    p.marks = R"([{"id": "rc", "type": "buoy", "radius": 0.5, "at": {"x": 0, "y": 0}}])";
    refuse("radius", p.text(), "$.marks[0].radius");
  }
  {
    Parts p;
    p.marks = R"([{"id": "rc", "type": "buoy", "at": {"bearing": 0, "dist": 10}}])";
    refuse("offset in a world course", p.text(), "$.marks[0].at");
  }
  {
    Parts p;
    p.header = R"("schema": "windmark.course/1", "id": "t", "name": "T", "venue": "example_bay", "frame": "wind",
                  "reference": {"x": 0, "y": 0})";
    p.marks = R"([{"id": "a", "type": "buoy", "at": {"bearing": 0, "dist": 10, "from": "b"}},
                  {"id": "b", "type": "buoy", "at": {"x": 0, "y": 0}}])";
    refuse("forward reference", p.text(), "$.marks[0].at.from");
  }
  {
    Parts p;
    p.header = R"("schema": "windmark.course/1", "id": "t", "name": "T", "venue": "example_bay", "frame": "wind")";
    refuse("wind frame without reference", p.text(), "$.reference");
  }
  {
    Parts p;
    p.sequence = R"([{"mark": "x", "round": "port"}])";
    refuse("unknown mark", p.text(), "$.sequence[0].mark");
  }
  {
    Parts p;
    p.sequence = R"([{"mark": "w", "round": "left"}])";
    refuse("bad side", p.text(), "$.sequence[0].round");
  }
  {
    Parts p;
    p.sequence = R"(["lap"])";
    refuse("empty expansion", p.text(), "$.sequence");
  }
  {
    Parts p;
    p.sequence = R"([{"gate": ["g1", "rc"]}])";
    refuse("gate of a committee boat", p.text(), "$.sequence[0].gate[1]");
  }
  {
    Parts p;
    p.sequence = R"([{"repeat": 2, "steps": [{"repeat": 2, "steps": [{"repeat": 2, "steps": []}]}]}])";
    refuse("nesting", p.text(), "$.sequence[0].steps[0].steps[0]");
  }
  {
    Parts p;
    p.start = R"({"ends": ["pin", "pin"]})";
    refuse("line of one mark", p.text(), "$.start.ends");
  }
  {
    Parts p;
    p.start = R"({"ends": ["pin", "rc"], "bias": 0.1})";
    refuse("bias on a world course", p.text(), "$.start.bias");
  }
  {
    Parts p;
    p.extra = R"(, "race": {"prep_flag": "Q"})";
    refuse("prep flag", p.text(), "$.race.prep_flag");
  }
  {
    Parts p;
    p.extra = R"(, "display": {"labels": {"nope": "X"}})";
    refuse("label of an unknown mark", p.text(), "$.display.labels.nope");
  }
}

TEST_CASE("course: geometry refusals") {
  {
    Parts p;
    p.marks = R"([
      {"id": "rc", "type": "committee_boat", "at": {"x": 100, "y": 0}, "heading": 0},
      {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}},
      {"id": "w", "type": "buoy", "at": {"x": 0, "y": 60}},
      {"id": "g1", "type": "buoy", "at": {"x": 30, "y": 100}},
      {"id": "g2", "type": "buoy", "at": {"x": -30, "y": 100}}])";
    CHECK(geometry_fails("first step near the line", p.text(), "100 m"));
  }
  {
    Parts p;
    p.sequence = R"([{"mark": "w", "round": "port"}, {"mark": "w", "round": "starboard"}, {"gate": ["g1", "g2"]}])";
    CHECK(geometry_fails("consecutive steps at one point", p.text(), "closer than 20 m"));
  }
  {
    Parts p;
    p.marks = R"([
      {"id": "rc", "type": "committee_boat", "at": {"x": 100, "y": 0}, "heading": 0},
      {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}},
      {"id": "w", "type": "buoy", "at": {"x": 0, "y": 500}},
      {"id": "g1", "type": "buoy", "at": {"x": 5, "y": 100}},
      {"id": "g2", "type": "buoy", "at": {"x": -5, "y": 100}}])";
    CHECK(geometry_fails("narrow gate", p.text(), "below 2 hull lengths"));
  }
  {
    Parts p;
    p.sequence = R"([{"mark": "w", "round": "port"}])";
    CHECK(geometry_fails("finish on the start line from above", p.text(), "pre-start side"));
  }
  {
    Parts p;
    p.marks = R"([
      {"id": "rc", "type": "committee_boat", "at": {"x": 100, "y": 0}, "heading": 0},
      {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}},
      {"id": "w", "type": "buoy", "at": {"x": 0, "y": 2400}},
      {"id": "g1", "type": "buoy", "at": {"x": 30, "y": 100}},
      {"id": "g2", "type": "buoy", "at": {"x": -30, "y": 100}}])";
    CHECK(geometry_fails("mark on the island", p.text(), "outside the venue bounds"));
  }
  {
    Parts p;
    p.marks = R"([
      {"id": "rc", "type": "committee_boat", "at": {"x": 100, "y": 0}, "heading": 0},
      {"id": "pin", "type": "buoy", "at": {"x": -100, "y": 0}},
      {"id": "w", "type": "buoy", "at": {"x": 0, "y": 1995}},
      {"id": "g1", "type": "buoy", "at": {"x": 30, "y": 100}},
      {"id": "g2", "type": "buoy", "at": {"x": -30, "y": 100}}])";
    CHECK(geometry_fails("mark near land", p.text(), "within 2 hull lengths", 30.0f));
  }
  {
    Parts p;
    p.extra = R"(, "area": {"boundary": [{"x": -300, "y": -300}, {"x": 300, "y": -300}, {"x": 300, "y": 300},
                                         {"x": -300, "y": 300}]})";
    CHECK(geometry_fails("mark outside the boundary", p.text(), "boundary"));
  }
  {
    // A wind-frame course that reaches the island for a wind from the north.
    Parts p;
    p.header = R"("schema": "windmark.course/1", "id": "t", "name": "T", "venue": "example_bay", "frame": "wind",
                  "reference": {"x": 0, "y": 900})";
    p.marks = R"([
      {"id": "rc", "type": "committee_boat", "at": {"bearing": 1.5708, "dist": 100}},
      {"id": "pin", "type": "buoy", "at": {"bearing": 4.7124, "dist": 100}},
      {"id": "w", "type": "buoy", "at": {"bearing": 0, "dist": 1100}},
      {"id": "g1", "type": "buoy", "at": {"bearing": 0.3, "dist": 100}},
      {"id": "g2", "type": "buoy", "at": {"bearing": -0.3, "dist": 100}}])";
    CHECK(geometry_fails("some wind lays a mark on land", p.text(), "with the wind from"));
  }
}
