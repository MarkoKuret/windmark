// Collisions (collisions.md): tick step 6 (conventions.md §4.1). 2-D detection on the water plane between boat
// hulls, course marks and objects, venue obstacles and land; the impulse response that writes the boats' pos, v
// and contact_* (boat.md §3); the contact events (§5) and the in-contact pair set that is state (§6).
#pragma once

#include <cstdint>
#include <span>
#include <vector>

#include "math/wm_math.h"
#include "state/checksum.h"

namespace wm {

class Boat;
struct VenueData;

// §4 constants.
struct CollideConst {
  static constexpr float SLOP = 0.02f;
  static constexpr float PUSH = 0.8f;
  static constexpr float PUSH_MAX = 0.5f;
  static constexpr float REST_BOAT = 0.2f;
  static constexpr float REST_MARK = 0.3f;   // marks and course objects
  static constexpr float REST_FIXED = 0.1f;  // obstacles and land
  static constexpr float FRICTION_BOAT = 0.3f;
  static constexpr float FRICTION_FIXED = 0.5f;  // every static shape
  static constexpr float YAW_KICK_MAX = 1.0f;
  static constexpr std::uint8_t CONTACT_GAP = 30;  // ticks (1.5 s) without contact before a new `begin`
};

// §5. The numeric values are part of the pair key (§6), so they never change.
enum class ContactKind : std::uint8_t { boat = 0, mark = 1, course_object = 2, obstacle = 3, land = 4 };

// §5: one per resolved contact, in list order (§3.1).
struct ContactEvent {
  std::uint64_t tick;
  std::int32_t boat;         // boat A (the lower index of a boat pair)
  ContactKind other_kind;
  std::int32_t other;        // boat index, course index, venue obstacle index or venue land index
  Vec2 point;                // as detected
  Vec2 normal;               // unit, from the other shape toward boat A
  float depth;               // m, as detected
  float closing_speed;       // max(0, -vn) before the impulse, m/s
  float impulse;             // j, N·s (0 when not closing)
  bool begin;                // the pair had no contact in the previous CONTACT_GAP ticks
};

// §6: one entry of the pair set. `age` = ticks since the pair's last contact (0: in contact in the last step).
struct ContactPair {
  std::uint64_t key;  // Collisions::pair_key
  std::uint8_t age;   // 0 .. CONTACT_GAP - 1
  bool operator==(const ContactPair&) const = default;
};

// ---------------------------------------------------------------------------------------------------------------
// Detection primitives (§3). Polygons are convex and counter-clockwise unless named land. `normal` points from B
// (the second shape) toward A.

struct Hit {
  Vec2 point{0.0f, 0.0f};
  Vec2 normal{0.0f, 0.0f};
  float depth = 0.0f;
};

// §3.2 separating axes. `ca`, `cb`: the centres used to orient the normal.
bool collide_polygons(std::span<const Vec2> a, Vec2 ca, std::span<const Vec2> b, Vec2 cb, Hit& out);
// §3.3: circle (c, r) is B, polygon is A.
bool collide_circle_polygon(Vec2 c, float r, std::span<const Vec2> a, Hit& out);

// A land polygon (counter-clockwise, interior = land) with the band index of §3.4 built once.
struct LandShape {
  std::vector<Vec2> points;
  float xmin = 0.0f, ymin = 0.0f, xmax = 0.0f, ymax = 0.0f;
  std::int32_t bands = 1;
  float band_h = 0.0f;
  std::vector<std::uint32_t> edge_start, edge_ids;  // per band, ascending edge index (edge k: points k -> k+1)
  std::vector<std::uint32_t> vert_start, vert_ids;  // per band, ascending vertex index
  void build(std::span<const Vec2> pts);
  std::int32_t band_of(float y) const;
};
// §3.4 boat (convex A with reference point `pos`, bounding radius `r_hull`) vs land. `use_index = false` tests every
// edge and vertex (the reference the index must match).
bool collide_boat_land(std::span<const Vec2> a, Vec2 pos, float r_hull, const LandShape& land, bool use_index,
                       Hit& out);
// Crossing number (§3.4) and the nearest land edge (squared distance to the clamped segment, lowest index on ties).
bool land_contains(const LandShape& land, Vec2 p, bool use_index);
float land_nearest_edge(const LandShape& land, Vec2 p, bool use_index, std::uint32_t& edge);

// §2.1 world vertices of a body-frame outline at (pos, psi).
void outline_to_world(std::span<const Vec2> body, Vec2 pos, float psi, std::vector<Vec2>& world);

// ---------------------------------------------------------------------------------------------------------------
// The static scene: plain data the race layer builds once per race (course in course order, then the venue).

struct CourseShape {
  ContactKind kind = ContactKind::mark;  // mark or course_object
  bool solid = true;                     // false: a virtual mark, keeps its index, never collides
  bool is_circle = true;
  Vec2 pos{0.0f, 0.0f};                  // circle centre, or the polygon's reference point (its centre)
  float radius = 0.0f;                   // circle radius; for a polygon: the largest vertex distance from pos
  float heading = 0.0f;                  // polygon only, compass
  std::vector<Vec2> world;               // polygon only: world vertices, counter-clockwise
};

struct ObstacleShape {
  bool is_circle = false;
  Vec2 centre{0.0f, 0.0f};  // circle centre, or the vertex mean of the polygon (§3.2)
  float radius = 0.0f;      // circle radius, or the polygon's bounding radius about `centre`
  std::vector<Vec2> polygon;
};

class CollisionScene {
 public:
  void clear();

  // Course entries in course order; each returns its index (the `other` of contact events), or -1 if the shape
  // is invalid (radius < 0.8 m, outline not 3..64 vertices strictly convex counter-clockwise around the origin).
  std::int32_t add_mark(Vec2 centre, float radius);                          // buoy: kind mark, circle
  std::int32_t add_course_circle(Vec2 centre, float radius);                 // course_object, circle
  std::int32_t add_course_polygon(Vec2 pos, float heading, std::span<const Vec2> outline_body);  // course_object
  std::int32_t add_virtual();                                                // no shape

  // Copies the venue's obstacles and land in file order and builds the land index. Replaces any earlier venue.
  void set_venue(const VenueData& venue);

  const std::vector<CourseShape>& course() const { return course_; }
  const std::vector<ObstacleShape>& obstacles() const { return obstacles_; }
  const std::vector<LandShape>& land() const { return land_; }

 private:
  std::vector<CourseShape> course_;
  std::vector<ObstacleShape> obstacles_;
  std::vector<LandShape> land_;
};

// Per-boat input of the step, written by the race layer (race.md §1) and the environment.
struct CollideBoatInput {
  bool collides = true;             // §6
  Vec2 current{0.0f, 0.0f};         // the current at the boat this tick (the BoatEnv current of step 5), m/s
};

// The pair set of §6 and the step. One instance per race.
class Collisions {
 public:
  void reset() { pairs_.clear(); }  // a new race: no pair has touched

  // Tick step 6 on the positions after every boat step of tick `tick`. `boats[i]` and `input[i]` are boat i
  // (same length). Detects in the order of §3.1, resolves each contact in list order (§4), appends one event per
  // contact to `events` (not cleared here) and updates the pair set.
  void step(std::uint64_t tick, std::span<Boat> boats, std::span<const CollideBoatInput> input,
            const CollisionScene& scene, std::vector<ContactEvent>& events);

  // Pairs with a contact in the last CONTACT_GAP steps, ascending key (§6).
  const std::vector<ContactPair>& pairs() const { return pairs_; }
  // boat << 36 | kind << 32 | other (boat A, the other's kind and index as in the event).
  static std::uint64_t pair_key(std::int32_t boat, ContactKind kind, std::int32_t other);

  // §6: uint32 count, then per pair its key (uint64) and age (uint8), ascending key. Serialised after the boats.
  void save(SnapshotWriter& w) const;
  bool load(SnapshotReader& r);

 private:
  std::vector<ContactPair> pairs_;
  // Scratch, reused between ticks (never part of the state).
  std::vector<std::vector<Vec2>> world_;
};

}  // namespace wm
