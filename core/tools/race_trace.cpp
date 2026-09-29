// Runs a headless race and writes its per-tick checksums (conventions.md §9), one line per tick, for comparing
// runs across builds and architectures (WM-033; core/tools/cross_arch_check.sh diffs an arm64 and an x86_64 build):
//
//   windmark_race_trace ai   [--seed S] [--boats N] [--out FILE]   the AI fleet of tests/ai_fleet_race.h (10 boats)
//   windmark_race_trace full [--seed S] [--out FILE]               the scripted six-boat race of the full-race tests
//   windmark_race_trace ai --profile [--boats N]                   per-tick cost, split by how bunched the fleet is
//
// Lines: "<tick> <checksum hex>" for the tick the step made (world.tick() after the step). A summary goes to stderr.
// The profile uses the wall clock of the tool only; nothing in the core reads it.
#include <algorithm>
#include <chrono>
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "ai/ai.h"
#include "ai_fleet_race.h"
#include "course/course.h"
#include "data/perf.h"
#include "data/venue.h"
#include "full_race_course.h"
#include "pilot.h"
#include "world/world.h"

namespace {

[[noreturn]] void die(const std::string& why) {
  std::fprintf(stderr, "windmark_race_trace: %s\n", why.c_str());
  std::exit(2);
}

struct Options {
  std::string mode;
  std::uint64_t seed = 0;
  int boats = 10;
  const char* out = nullptr;
  bool profile = false;
};

std::unique_ptr<wm::World> full_world(const Options& o, const wm_test::AiFleetRace& data) {
  wm::WorldSetup s;
  s.venue = &data.venue;
  s.race_seed = o.seed;
  s.wind.base_speed = 11.0f * wm::KNOT;
  s.wind.base_from = 0.2f;
  wm::apply_shift_preset(s.wind, wm::ShiftPreset::stable);
  s.race.free_sailing_s = 10.0f;
  auto w = std::make_unique<wm::World>(s);
  for (int i = 0; i < 6; ++i) {
    wm::BoatEntry e;
    e.perf = i == 5 ? &data.wm12 : &data.wm7;
    if (w->add_boat(e) != i) die("add_boat failed");
  }
  wm::CourseData course;
  wm::LoadError err;
  if (!wm::parse_course(wm_test::kFullRaceCourse, "test_wl_1.course.json", course, err)) die(err.message());
  std::string why;
  if (!w->create_race(course, why)) die(why);
  return w;
}

// Boats within `r` of the nearest course mark, and boat pairs closer than `r` to each other.
void bunching(const wm::World& w, float r, int& near_mark, int& close_pairs) {
  near_mark = 0;
  close_pairs = 0;
  const std::size_t n = w.boat_count();
  for (std::size_t i = 0; i < n; ++i) {
    const wm::BoatState& a = w.boat(i).state();
    for (const wm::ResolvedMark& m : w.course().marks) {
      if (m.type == wm::MarkType::buoy && wm::v_dist({a.pos_x, a.pos_y}, m.pos) < r) {
        ++near_mark;
        break;
      }
    }
    for (std::size_t j = i + 1; j < n; ++j) {
      const wm::BoatState& b = w.boat(j).state();
      if (wm::v_dist({a.pos_x, a.pos_y}, {b.pos_x, b.pos_y}) < r) ++close_pairs;
    }
  }
}

}  // namespace

int main(int argc, char** argv) {
  Options o;
  for (int k = 1; k < argc; ++k) {
    const std::string a = argv[k];
    auto next = [&]() -> const char* {
      if (k + 1 >= argc) die("missing value after " + a);
      return argv[++k];
    };
    if (a == "ai" || a == "full") {
      o.mode = a;
    } else if (a == "--seed") {
      o.seed = std::strtoull(next(), nullptr, 10);
    } else if (a == "--boats") {
      o.boats = std::atoi(next());
    } else if (a == "--out") {
      o.out = next();
    } else if (a == "--profile") {
      o.profile = true;
    } else {
      die("unknown argument " + a);
    }
  }
  if (o.mode.empty()) die("usage: windmark_race_trace ai|full [--seed S] [--boats N] [--out FILE] [--profile]");
  if (o.seed == 0) o.seed = o.mode == "ai" ? 33 : 20260925;
  if (o.boats < 1 || o.boats > 40) die("--boats must be 1 to 40");

  wm_test::AiFleetRace data;
  std::string why;
  if (!data.load(why)) die(why);
  wm::AiSkippers ai;
  wm_test::Pilot pilot(6);
  pilot.boat(1).early = true;
  pilot.boat(2).rogue_port = true;
  pilot.boat(3).leave_bounds_at = 20.0f;
  pilot.boat(3).exclusion = {245.0f, -250.0f};
  std::unique_ptr<wm::World> w = o.mode == "ai" ? data.world(o.seed, o.boats, ai, why) : full_world(o, data);
  if (w == nullptr) die(why);
  // The controller is timed on its own in a profile run.
  double ai_s = 0.0;
  if (o.mode == "ai") {
    w->set_controller([&ai, &ai_s, &o](wm::World& world) {
      if (!o.profile) return ai.step(world);
      const auto t0 = std::chrono::steady_clock::now();
      ai.step(world);
      ai_s += std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    });
  } else {
    w->set_controller([&pilot](wm::World& world) { pilot(world); });
  }

  std::FILE* out = nullptr;
  if (o.out != nullptr) {
    out = std::fopen(o.out, "w");
    if (out == nullptr) die(std::string("cannot write ") + o.out);
    std::fprintf(out, "# windmark per-tick checksums: %s race, seed %" PRIu64 ", %zu boats\n", o.mode.c_str(), o.seed,
                 w->boat_count());
  }

  // Profile buckets by the number of boats within 4 L_max of a mark.
  struct Bucket {
    double step_s = 0.0, ai_s = 0.0;
    long ticks = 0;
    long pairs = 0;
  };
  std::map<int, Bucket> buckets;
  double worst_s = 0.0;
  std::uint32_t worst_tick = 0;
  int worst_near = 0, worst_pairs = 0;
  const float r_bunch = 4.0f * w->race().L_max();

  std::int32_t contacts = 0, penalties = 0;
  std::uint64_t last = 0;
  for (std::uint32_t k = 0; k < 80000 && w->race().state() != wm::RaceState::closed; ++k) {
    int near = 0, pairs = 0;
    if (o.profile) bunching(*w, r_bunch, near, pairs);
    const double ai_before = ai_s;
    const auto t0 = std::chrono::steady_clock::now();
    last = w->step();
    const double dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    if (o.profile) {
      Bucket& b = buckets[near >= 15 ? 15 : (near >= 10 ? 10 : (near >= 5 ? 5 : 0))];
      b.step_s += dt;
      b.ai_s += ai_s - ai_before;
      ++b.ticks;
      b.pairs += pairs;
      if (dt > worst_s) {
        worst_s = dt;
        worst_tick = w->tick();
        worst_near = near;
        worst_pairs = pairs;
      }
    }
    if (out != nullptr) std::fprintf(out, "%u %016" PRIx64 "\n", w->tick(), last);
    for (const wm::ContactEvent& e : w->events().contacts) {
      if (e.begin && e.other_kind == wm::ContactKind::boat && e.boat < e.other) ++contacts;
    }
    for (const wm::RulesEvent& e : w->events().rules) penalties += e.kind == wm::RulesEventKind::penalty ? 1 : 0;
  }
  if (out != nullptr) std::fclose(out);

  int finished = 0;
  for (const wm::ResultRow& r : w->race().results()) finished += r.place > 0 ? 1 : 0;
  std::fprintf(stderr, "%s race seed %" PRIu64 ": %s after %u ticks, %d of %zu finished, %d boat contacts, %d penalties, "
               "final checksum %016" PRIx64 "\n",
               o.mode.c_str(), o.seed, w->race().state() == wm::RaceState::closed ? "closed" : "NOT closed", w->tick(),
               finished, w->boat_count(), contacts, penalties, last);
  if (o.profile) {
    std::fprintf(stderr, "per-tick cost by boats within 4 L_max (%.1f m) of a mark:\n", static_cast<double>(r_bunch));
    for (const auto& [near, b] : buckets) {
      if (b.ticks == 0) continue;
      std::fprintf(stderr, "  %2d+ boats: %6ld ticks, step %.3f ms (of which AI %.3f ms), %.1f close pairs\n", near,
                   b.ticks, 1e3 * b.step_s / static_cast<double>(b.ticks), 1e3 * b.ai_s / static_cast<double>(b.ticks),
                   static_cast<double>(b.pairs) / static_cast<double>(b.ticks));
    }
    std::fprintf(stderr, "  worst tick %u: %.3f ms, %d boats near a mark, %d close pairs\n", worst_tick, 1e3 * worst_s,
                 worst_near, worst_pairs);
  }
  return w->race().state() == wm::RaceState::closed ? 0 : 1;
}
