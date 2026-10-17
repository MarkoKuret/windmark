// Course files `windmark.course/1` (courses.md): marks, start and finish lines, the sequence of marks, gates and
// laps, the race area and the race defaults. `load_course` reads and checks the file on its own (schema, ids,
// references, radii); `validate_course` checks its geometry against a venue and a class length (courses.md §7);
// `resolve_course` lays it for one race (wind-relative courses to the course axis, courses.md §6) into the world
// positions the race, the rules, the collisions and the network use (courses.md §9).
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "data/load_error.h"
#include "data/perf.h"
#include "data/venue.h"
#include "math/wm_math.h"

namespace wm {

enum class MarkType : std::uint8_t { buoy, committee_boat, mark_boat, virtual_point };
enum class Side : std::uint8_t { port, starboard };
enum class CourseFrame : std::uint8_t { world, wind };
enum class GateMode : std::uint8_t { round, cross };
enum class RaceType : std::uint8_t { fleet, match };
enum class SequenceKind : std::uint8_t { s5410, s3210, match };  // "5-4-1-0", "3-2-1-0", "match"
enum class PrepFlag : std::uint8_t { P, I, Z, U, black };

std::string_view mark_type_name(MarkType t);
std::string_view side_name(Side s);
std::string_view prep_flag_name(PrepFlag f);

// courses.md §3: a world point, or an offset from a base (wind frame).
struct CoursePos {
  bool offset = false;
  Vec2 world{0.0f, 0.0f};     // !offset
  float bearing = 0.0f;       // rad, relative to the wind axis
  float dist = 0.0f;          // m
  std::string from;           // base: mark id, "<a>_<b>_mid", or empty = reference
  std::int32_t base_a = -1, base_b = -1;  // resolved `from`: none = reference, a only = mark, both = midpoint
  bool fixed = false;         // not scaled (§6.3)
};

// courses.md §2
struct CourseMark {
  std::string id;
  MarkType type = MarkType::buoy;
  std::string style;           // buoys: inflatable, large, tetra
  float radius = 0.8f;         // m (style or override)
  CoursePos at;
  bool head_to_wind = true;    // committee / mark boats with "heading": null (or absent)
  float heading = 0.0f;        // rad, compass, when !head_to_wind
  float length = 0.0f, beam = 0.0f;  // committee / mark boat footprint
  std::vector<Vec2> outline;         // committee / mark boat: explicit body outline, empty = the default (§2)
};

// courses.md §4.4, as written in the file.
struct SequenceItem {
  enum class Kind : std::uint8_t { mark, gate, repeat, lap };
  Kind kind = Kind::mark;
  std::int32_t marks[2] = {-1, -1};  // mark indices
  bool has_sides = false;            // gates: sides given
  Side sides[2] = {Side::port, Side::port};
  GateMode gate_mode = GateMode::round;
  std::int32_t repeat = 1;
  std::vector<SequenceItem> steps;   // repeat blocks
  std::int32_t source_index = 0;     // index in the top-level sequence
};

struct CourseExclusion {
  std::string id;
  std::vector<CoursePos> polygon;
};

// courses.md §5.2: defaults for the race settings; `has_*` false = not given.
struct CourseRaceDefaults {
  bool has_type = false;
  RaceType type = RaceType::fleet;
  bool has_sequence = false;
  SequenceKind sequence = SequenceKind::s5410;
  bool has_prep_flag = false;
  PrepFlag prep_flag = PrepFlag::I;
  float time_limit = 0.0f;       // s, 0 = none
  float target_duration = 0.0f;  // s, 0 = none
  float zone_lengths = 3.0f;
};

struct CourseLabel {
  std::string mark, text;
};

enum class StepKind : std::uint8_t { start, mark, gate, finish };

// One expanded step (courses.md §4.4, race.md §5).
struct CourseStep {
  StepKind kind = StepKind::mark;
  std::int32_t marks[2] = {-1, -1};  // mark: marks[0]; gate: both buoys; lines: the ends A, B (oriented)
  Side sides[2] = {Side::port, Side::port};
  GateMode gate_mode = GateMode::round;
  bool sides_given = false;     // gates: sides from the file, else the courses.md §4.3 default
  std::int32_t lap = 1;         // 1-based
  std::int32_t leg_in_lap = 1;  // 1-based
  std::int32_t source_index = -1;
  Vec2 ref{0.0f, 0.0f};         // reference point R_k
};

struct CourseData {
  std::string id, name, venue;
  std::vector<std::string> classes;
  CourseFrame frame = CourseFrame::world;
  Vec2 reference{0.0f, 0.0f};
  std::vector<CourseMark> marks;
  std::int32_t start_ends[2] = {-1, -1};
  float start_bias = 0.0f;
  bool finish_is_start = false;
  std::int32_t finish_ends[2] = {-1, -1};
  std::vector<SequenceItem> sequence;
  bool has_boundary = false;
  std::vector<CoursePos> boundary;
  std::vector<CourseExclusion> exclusions;
  bool has_spawn = false;
  std::vector<CoursePos> spawn;
  CourseRaceDefaults race;
  std::vector<CourseLabel> labels;  // display.labels, file order
  std::vector<CourseStep> expanded; // the sequence expanded (courses.md §4.4) with lap numbers; refs unset
  std::string file_sha256;

  std::int32_t find_mark(std::string_view id) const;  // -1 if absent
};

// Parses and checks the file on its own (courses.md §1–§5, §8 and the schema rows of §7). On failure `out` is
// left empty.
bool parse_course(std::string_view text, std::string_view file, CourseData& out, LoadError& err);
bool load_course(const std::string& file, CourseData& out, LoadError& err);

// ---- Resolution (courses.md §3, §4, §6, §9) ----

struct ResolvedMark {
  MarkType type = MarkType::buoy;
  Vec2 pos{0.0f, 0.0f};
  float radius = 0.8f;
  float heading = 0.0f;
  float length = 0.0f, beam = 0.0f;
};

// A static collision object of the course (courses.md §2, collisions.md §2.2), numbered by its mark index.
struct CourseObject {
  std::int32_t mark = -1;
  bool is_boat = false;  // committee / mark boat: other_kind course_object, convex polygon; else a mark circle
  Vec2 c{0.0f, 0.0f};
  float r = 0.0f;
  float heading = 0.0f;
  std::vector<Vec2> outline;  // body frame, counter-clockwise (boats only)
  std::vector<Vec2> polygon;  // world, counter-clockwise (boats only)
};

struct ResolvedCourse {
  std::string id, venue;
  CourseFrame frame = CourseFrame::world;
  float twd_c = 0.0f;  // course axis, rad (courses.md §6.1)
  float k = 1.0f;      // scale (courses.md §6.3)
  std::vector<std::string> mark_ids;
  std::vector<ResolvedMark> marks;  // file order
  std::vector<CourseStep> steps;    // step 0 = start line, last = finish line
  std::int32_t laps = 1;
  std::vector<std::int32_t> legs_per_lap;  // index lap-1
  bool has_boundary = false;
  std::vector<Vec2> boundary;
  std::vector<std::vector<Vec2>> exclusions;
  bool has_spawn = false;
  std::vector<Vec2> spawn;
  CourseRaceDefaults race;
  std::vector<CourseObject> objects;  // every non-virtual mark, in mark order

  const CourseStep& start() const { return steps.front(); }
  const CourseStep& finish() const { return steps.back(); }
  // Line end positions of a start or finish step: A, B with the course side on the left of A→B.
  Vec2 end_a(const CourseStep& s) const { return marks[static_cast<std::size_t>(s.marks[0])].pos; }
  Vec2 end_b(const CourseStep& s) const { return marks[static_cast<std::size_t>(s.marks[1])].pos; }

  // courses.md §9: canonical JSON (keys sorted, floats with 9 significant digits, no whitespace) and its SHA-256.
  std::string canonical_json() const;
  std::string hash() const;
};

// courses.md §2: the default committee / mark boat outline (body frame, counter-clockwise, 17 vertices).
std::vector<Vec2> default_boat_outline(float L, float B);

// courses.md §6.1: the course axis from the wind's median direction, rounded to 0.01 rad.
float course_axis(float median_from);

// courses.md §3, §4, §6.2: lays the course with axis `twd_c` and scale `k` (world-frame courses ignore both for
// positions but keep `twd_c` for head-to-wind boats). Never fails on a course that passed load_course.
void resolve_course(const CourseData& c, float twd_c, float k, ResolvedCourse& out);

// courses.md §6.3: the scale factor for a target duration with the class's polar at `tws` (1 without a target or
// for world-frame courses).
float course_scale(const CourseData& c, float twd_c, const PerfData& perf, float tws);

// Polar helpers shared with the race (race.md §7.2): best VMG up and down over every sail config (PolarVmg,
// polar_vmg in data/vmg_table.h, from the class's table), and the best speed at a true wind angle. Angles in rad.
float polar_best(const PerfData& perf, float tws, float twa_abs);

// courses.md §7 geometry checks of a resolved course.
struct CourseCheck {
  float L = 8.0f;              // longest class hull, m
  std::int32_t max_boats = 12;
};
bool check_resolved_course(const ResolvedCourse& rc, const VenueData& venue, const CourseCheck& chk,
                           std::vector<std::string>& warnings, std::string& error);

// courses.md §7: the file against its venue. Wind-frame courses are checked for every axis in steps of π/18 at
// scale 1. `warnings` receives each distinct warning once. The error names the axis for wind-frame courses.
bool validate_course(const CourseData& c, const VenueData& venue, const CourseCheck& chk,
                     std::vector<std::string>& warnings, LoadError& err);

}  // namespace wm
