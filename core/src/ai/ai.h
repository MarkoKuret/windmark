// Computer skippers (ai.md): perception, strategy, tactics, manoeuvres and the helm of every AI boat, run in tick
// step 2 through the same controls a human uses (World::set_helm, set_let_fly, hoist, ...). One `AiSkippers`
// object sails every AI boat of a world; install it as the world's controller:
//
//   wm::AiSkippers ai;
//   std::int32_t i = world.add_boat(wm::ai_entry(&perf, wm::AiLevel::expert));
//   ai.add(i, wm::AiLevel::expert);
//   world.set_controller([&ai](wm::World& w) { ai.step(w); });
//
// Deterministic: the skippers read only the world state and draw random choices from the AI RNG streams of
// conventions.md §7 with the race seed.
#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <memory>
#include <span>
#include <string>
#include <vector>

#include "ai/ai_polar.h"
#include "shadow/shadow.h"
#include "world/world.h"

namespace wm {

enum class AiLevel : std::uint8_t { easy = 0, intermediate = 1, expert = 2, pro = 3 };

// ai.md §15 tactic reasons, in the spec's order.
enum class AiTactic : std::uint8_t {
  None, Start, Rounding, KeepClear, Emergency, BadAir, Cover, Shift, Pressure, Layline, Corridor, PenaltyTurn, Land,
};
inline constexpr std::size_t kAiTacticCount = 13;
const char* ai_tactic_name(AiTactic t);

enum class AiCover : std::uint8_t { none, match_only, all };

// ai.md §13, one column.
struct AiLevelParams {
  float performance_scale = 1.0f;
  float e_start_lo = 0.0f, e_start_hi = 2.5f;  // s
  float spread = 0.6f;
  float t_final = 30.0f;                       // s
  float m_lay = 2.0f;                          // hull lengths
  bool shifts = true;
  float h_up = 10.0f * DEG, h_dn = 15.0f * DEG;
  float r_read = 0.0f;                         // m
  float t_cool = 20.0f;                        // s
  float h_avoid = 5.0f;                        // s
  float c_lvl = 1.0f;                          // beams
  float badair_react = 3.0f;                   // s
  bool anticipate = false;
  AiCover cover = AiCover::match_only;
  float drop_lead = 4.0f;                      // s, §6.2 drop timing
  float route_margin = 0.04f;                  // §4.7 stream and trend routing: share of the leg time, 0 = off
  bool trend = true;                           // §4.7 plays the briefed trend of the wind
};

// `speed_only`: the decision rows of Intermediate with the level's performance_scale (§13).
AiLevelParams ai_level_params(AiLevel level, bool speed_only = false);

// A world entry for an AI boat of this level: not human, protests on its own, the level's performance_scale.
BoatEntry ai_entry(const PerfData* perf, AiLevel level);

// ai.md §15 per boat and race.
struct AiBadAirRecord {
  std::uint32_t tick = 0;
  float d_at = 0.0f;       // smoothed deficit at the trigger
  float d_after = -1.0f;   // 20 s later (< 0: not yet known)
};

struct AiTelemetry {
  std::int32_t tacks = 0, gybes = 0;
  std::int32_t penalties = 0;
  std::int32_t ocs = 0;
  std::array<std::int32_t, kAiTacticCount> activations{};
  float stuck_s = 0.0f;        // time below 0.3 m/s in spells longer than 5 s after the start
  float min_gap = 1e9f;        // smallest hull gap to any racing boat within 20 L, m (after the warning)
  std::int32_t sail_changes = 0;
  std::vector<AiBadAirRecord> bad_air;
  float start_delay = -1.0f;   // start time after the gun, s (< 0: not started)
};

// What an AI decided this tick, for tests and the debug overlay.
struct AiDebug {
  AiTactic tactic = AiTactic::None;
  float psi_target = 0.0f;
  float d = 0.0f;           // smoothed wind deficit
  float twd_ref = 0.0f, twd_f = 0.0f, tws_f = 0.0f;
  std::int32_t leg = 0;     // 0 beat, 1 reach, 2 run
  std::int32_t manoeuvre = 0;
  AiTactic man_why = AiTactic::None;  // the reason of the last tack or gybe started (not in the memory block)
  std::int32_t pen_wait = 0;  // why a pending penalty turn waits: 0 not waiting, 1 manoeuvre, 2 zone, 3 slow, 4 boat
                              // (urgent), 5 low, 6 slow, 7 next zone, 8 boat (not in the memory block)
  Vec2 aim{0.0f, 0.0f};
  Vec2 spot{0.0f, 0.0f};
};

class AiSkippers {
 public:
  AiSkippers();
  ~AiSkippers();
  AiSkippers(const AiSkippers&) = delete;
  AiSkippers& operator=(const AiSkippers&) = delete;

  // Boat `boat` is sailed by an AI of this level from the next step on.
  void add(std::int32_t boat, AiLevel level, bool speed_only = false);
  // ai.md §14: an AI at Intermediate decisions takes over a boat as it is (a disconnected human); `release`
  // hands it back.
  void take_over(std::int32_t boat);
  void release(std::int32_t boat);
  // race.md §6.2: only the finished-boat autopilot (offline human boats).
  void add_autopilot(std::int32_t boat);
  // ai.md §3.1: builds the class tables of a boat's performance file now (at load) rather than on the first step.
  void prepare(const PerfData& perf);

  // Tick step 2: every AI boat decides and writes its controls (World::Controller).
  void step(World& w);

  // ai.md §16: the skippers' memory, a block of its own next to the world snapshot (conventions.md §9.1 leaves
  // controller memory out of the world snapshot and the tick checksum). Save between ticks, together with
  // World::save; load into new skippers after World::load of the same snapshot, before the next step. `load`
  // checks the tick, the race seed and the boats against the world and rejects a damaged block.
  void save(SnapshotWriter& w, const World& world) const;
  bool load(std::span<const std::uint8_t> bytes, const World& world, std::string& error);

  bool has(std::int32_t boat) const;
  const AiTelemetry& telemetry(std::int32_t boat) const;
  const AiDebug& debug(std::int32_t boat) const;

  struct Boat;  // per boat state (ai.cpp)
  struct Ctx;   // per tick context (ai.cpp)

 private:
  Boat& get(std::int32_t boat);
  const AiPolar& polar(const PerfData* perf);
  const ShadowClass& shadow_class(const PerfData* perf);

  std::vector<std::unique_ptr<Boat>> boats_;           // by insertion
  std::map<const PerfData*, std::unique_ptr<AiPolar>> polars_;  // looked up by key only, never iterated
  std::map<const PerfData*, ShadowClass> shadow_classes_;
};

}  // namespace wm
