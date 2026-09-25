// One race world: the boats, the wind, the sea, the wind shadows, the collisions, the race and the rules, advanced
// one 50 ms tick at a time in the order of conventions.md §4.1. This is what the C API and the front end wrap:
// create the world, add boats, create the race, set controls, step, read state and events.
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <span>
#include <string>
#include <vector>

#include "boat/boat.h"
#include "collide/collide.h"
#include "course/course.h"
#include "data/venue.h"
#include "race/race.h"
#include "rules/rules.h"
#include "sea/sea.h"
#include "shadow/shadow.h"
#include "state/checksum.h"
#include "wind/wind.h"

namespace wm {

struct WorldSetup {
  const VenueData* venue = nullptr;  // required; must outlive the world (its grids are referenced)
  std::uint64_t race_seed = 1;       // conventions.md §7; also RaceSettings::race_seed
  WindSettings wind;                 // the venue's wind and current fields are applied on top
  bool sea = true;
  SeaSettings sea_settings;          // wind_sea left at 0: grown from the base wind and the venue fetch
  bool shadows = true;
  RaceSettings race;
  RulesParams rules;
};

struct BoatEntry {
  const PerfData* perf = nullptr;  // must outlive the world
  bool human = true;
  bool ai = false;                  // protest mode: protests on its own (rules.md §10)
  float performance_scale = 1.0f;   // boat.md §2; 1 for humans (race.md §3.5)
  bool auto_trim = true;
  std::int32_t front_sail = -2;     // -2: the class's start front sail (data_format.md §3.7)
};

// Events of one tick, published in step 7.
struct WorldEvents {
  std::vector<RaceEvent> race;
  std::vector<RulesEvent> rules;
  std::vector<ContactEvent> contacts;
};

class World {
 public:
  explicit World(const WorldSetup& setup);

  // Boats before create_race() are the entries; later ones join (race.md §3.5) and are placed at once. Returns the
  // boat index, or -1 if the race takes no more boats.
  std::int32_t add_boat(const BoatEntry& e);

  // race.md §3.1 Created: lays the course for the wind at the gun (courses.md §6), checks it against the venue
  // (courses.md §7), builds the collision scene, creates the race and the rules, and spawns the boats.
  bool create_race(const CourseData& course, std::string& error);

  // Free sailing (no race): places boat `boat` at `p` on heading `psi` with the spawn speed of race.md §3.5 (60 %
  // of the polar speed), sails up and trimmed. Only before create_race(), which places every boat itself; returns
  // false after it or for a bad index. A world that never creates a race steps without race, rules or course.
  bool place_boat(std::int32_t boat, Vec2 p, float psi);

  // Controls, applied in step 2 of the next tick (boat.md §2, sails.md §4.2).
  void set_helm(std::int32_t boat, float h);
  void set_sheet(std::int32_t boat, float s);
  void set_auto_trim(std::int32_t boat, bool on);
  void set_let_fly(std::int32_t boat, bool on);
  void hoist(std::int32_t boat, std::int32_t sail);
  void drop_front(std::int32_t boat);
  void retire(std::int32_t boat);   // race.md §6.4
  // Scenario set-up (tests, tools; not a control): puts a boat at a pose with speed `v` as a spawn does (boat.md
  // §6.6, sails up and trimmed), between ticks. The race sees the move as the boat's track in the next step.
  void place_boat(std::int32_t boat, float x, float y, float psi, float v);
  void protest(std::int32_t boat);  // rules.md §10

  // Called in step 2 before the queued controls are applied: computer skippers and scripts decide here from the
  // state and the race and rules results of step 1 (ai.md).
  using Controller = std::function<void(World&)>;
  void set_controller(Controller c) { controller_ = std::move(c); }

  // One tick (conventions.md §4.1). Returns the tick checksum (conventions.md §9).
  std::uint64_t step();

  // State
  std::uint32_t tick() const { return tick_; }  // the next tick to run
  std::uint32_t t_ms() const { return tick_ * DT_MS; }
  std::size_t boat_count() const { return boats_.size(); }
  const Boat& boat(std::size_t i) const { return boats_[i]; }
  const EnvAtBoat& env(std::size_t i) const { return env_[i]; }
  const Race& race() const { return race_; }
  const Rules& rules() const { return rules_; }
  const ResolvedCourse& course() const { return course_; }
  const WindField& wind() const { return *wind_; }
  const SeaField* sea() const { return sea_.get(); }
  const CollisionScene& scene() const { return scene_; }
  const WorldEvents& events() const { return events_; }  // of the last step
  std::uint64_t checksum() const;  // conventions.md §9: tick index, then the snapshot body
  bool race_created() const { return created_; }
  const WorldSetup& setup() const { return setup_; }  // as given (the venue's fields are applied inside)

  // conventions.md §9.1 world snapshot, taken between ticks: everything the world carries to the next tick.
  void save(SnapshotWriter& w) const;
  // Resumes a saved world. This must be a new world (no race, no step) built with the same WorldSetup and the same
  // boats added in the same order; `course` is the course the race was created with (unused when the snapshot has
  // no race). Returns false with a reason if the snapshot does not match or is damaged; the world is then unusable.
  // Controllers are not state: set them again after loading.
  bool load(std::span<const std::uint8_t> bytes, const CourseData* course, std::string& error);

 private:
  struct Command {
    enum class Kind : std::uint8_t { helm, sheet, auto_trim, let_fly, hoist, drop, retire, protest } kind;
    std::int32_t boat;
    float value;
    std::int32_t sail;
  };
  void spawn(std::size_t i, Vec2 p, float psi_hint, bool use_hint);
  BoatEnv env_at(Vec2 p) const;
  void queue(Command c) { commands_.push_back(c); }
  void save_body(SnapshotWriter& w) const;

  WorldSetup setup_;
  WindSettings wind_settings_;
  SeaSettings sea_settings_;
  std::unique_ptr<WindField> wind_;
  std::unique_ptr<SeaField> sea_;
  SeaTick sea_tick_;
  std::vector<Boat> boats_;
  std::vector<BoatEntry> entries_;
  std::vector<ShadowClass> shadow_classes_;
  std::vector<ShadowSource> snapshot_;
  std::vector<EnvAtBoat> env_;
  std::vector<CollideBoatInput> collide_in_;
  CollisionScene scene_;
  Collisions collisions_;
  std::vector<ContactEvent> contacts_;  // of the last collision step, read by the rules in the next tick
  ResolvedCourse course_;
  Race race_;
  Rules rules_;
  bool created_ = false;
  std::uint32_t entries_at_create_ = 0;
  std::vector<Vec2> slots_;
  std::vector<Command> commands_;
  Controller controller_;
  WorldEvents events_;
  std::vector<RaceBoatInput> race_in_;
  std::vector<RulesBoatInput> rules_in_;
  std::vector<std::uint8_t> pending_;
  std::uint32_t tick_ = 0;
};

}  // namespace wm
