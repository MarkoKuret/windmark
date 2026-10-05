// Runs a headless race and writes its per-tick checksums (conventions.md §9), one line per tick, for comparing
// runs across builds and architectures (WM-033; core/tools/cross_arch_check.sh diffs an arm64 and an x86_64 build):
//
//   windmark_race_trace ai   [--seed S] [--boats N] [--out FILE]   the AI fleet of tests/ai_fleet_race.h (10 boats)
//   windmark_race_trace full [--seed S] [--out FILE]               the scripted six-boat race of the full-race tests
//   windmark_race_trace ai --profile [--boats N]                   per-tick cost, split by how bunched the fleet is
//   windmark_race_trace ai --telemetry FILE                        a per-boat CSV of the AI fleet every 0.5 s
//
// The telemetry CSV (for finding where a boat loses time): race time, boat, class, level, next step, rank,
// position, heading, speed and polar target, true wind angle and speed at the boat, heel and its target, the
// front sail (perf sail id, "-" for none; "*" while a sail change runs), helm, let fly, the AI's tactic and
// manoeuvre, pending penalties, turning for a penalty, the deadline, the race status, and the AI's leg type
// (0 beat, 1 reach, 2 run), target heading, the reason of its last tack or gybe, why a penalty turn waits and its
// aim point. Rules events (penalties, served, late, mark touches, disqualifications) follow as "#ev" lines, and each
// boat's splits at the end as "#split" lines (with the course distance still to sail when the boat last raced, and
// the speed at the close).
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
#include <string_view>
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
  const char* telemetry = nullptr;
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
    } else if (a == "--telemetry") {
      o.telemetry = next();
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

  std::FILE* tel = nullptr;
  if (o.telemetry != nullptr) {
    if (o.mode != "ai") die("--telemetry needs the ai race");
    tel = std::fopen(o.telemetry, "w");
    if (tel == nullptr) die(std::string("cannot write ") + o.telemetry);
    std::fprintf(tel, "t,i,cls,lvl,next,rank,x,y,psi,v,vt,twa,tws,heel,heel_t,front,helm,letfly,tactic,man,pend,"
                 "pturn,deadline,status,leg,psi_t,why,pen_wait,aim_x,aim_y\n");
  }
  auto write_telemetry = [&]() {
    const float t = w->race().race_time(w->tick());
    for (std::size_t i = 0; i < w->boat_count(); ++i) {
      const wm::Boat& b = w->boat(i);
      const wm::BoatState& s = b.state();
      const wm::RaceBoat& rb = w->race().boat(i);
      const wm::BoatRules& br = w->rules().boat(i);
      const wm::AiDebug& d = ai.debug(static_cast<std::int32_t>(i));
      const std::int32_t f = b.sails().front();
      const std::string front = (f >= 0 ? b.perf().sails[static_cast<std::size_t>(f)].id : std::string("-")) +
                                (b.sails().busy() ? "*" : "");
      const char* status = rb.finished ? "fin" : (rb.dsq || br.dsq ? "dsq" : (rb.ghost ? "ghost" : "race"));
      std::fprintf(tel,
                   "%.1f,%zu,%s,%d,%d,%d,%.1f,%.1f,%.1f,%.2f,%.2f,%.1f,%.2f,%.1f,%.1f,%s,%.2f,%d,%s,%d,%zu,%d,%.0f,%s,"
                   "%d,%.1f,%s,%d,%.1f,%.1f\n",
                   static_cast<double>(t), i, b.perf().class_id.c_str(),
                   static_cast<int>(wm_test::AiFleetRace::level(static_cast<int>(i))),
                   rb.next, rb.rank, static_cast<double>(s.pos_x), static_cast<double>(s.pos_y),
                   static_cast<double>(s.psi / wm::DEG), static_cast<double>(s.v),
                   static_cast<double>(b.outputs().target_speed), static_cast<double>(s.twa / wm::DEG),
                   static_cast<double>(s.tws), static_cast<double>(s.phi / wm::DEG),
                   static_cast<double>(b.outputs().heel_target / wm::DEG), front.c_str(), static_cast<double>(s.h),
                   b.controls().let_fly ? 1 : 0, wm::ai_tactic_name(d.tactic), d.manoeuvre, br.pending.size(),
                   br.turning_for_penalty ? 1 : 0, static_cast<double>(br.deadline_s), status, d.leg,
                   static_cast<double>(d.psi_target / wm::DEG), wm::ai_tactic_name(d.man_why), d.pen_wait,
                   static_cast<double>(d.aim.x), static_cast<double>(d.aim.y));
    }
  };

  std::int32_t contacts = 0, penalties = 0;
  std::uint64_t last = 0;
  std::vector<float> last_d;  // remaining course distance while racing (race.md §8.2)
  for (std::uint32_t k = 0; k < 80000 && w->race().state() != wm::RaceState::closed; ++k) {
    if (tel != nullptr && w->race_created() && w->tick() % 10u == 0u) write_telemetry();
    if (tel != nullptr && w->race_created()) {
      last_d.resize(w->boat_count(), 0.0f);
      for (std::size_t i = 0; i < w->boat_count(); ++i) {
        if (w->race().racing(i)) last_d[i] = w->race().boat(i).D;
      }
    }
    int near = 0, pairs = 0;
    if (o.profile) bunching(*w, r_bunch, near, pairs);
    const double ai_before = ai_s;
    const auto t0 = std::chrono::steady_clock::now();
    w->step();
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
    if (out != nullptr) std::fprintf(out, "%u %016" PRIx64 "\n", w->tick(), w->checksum());
    for (const wm::ContactEvent& e : w->events().contacts) {
      if (e.begin && e.other_kind == wm::ContactKind::boat && e.boat < e.other) ++contacts;
    }
    for (const wm::RulesEvent& e : w->events().rules) {
      penalties += e.kind == wm::RulesEventKind::penalty ? 1 : 0;
      if (tel != nullptr && e.kind != wm::RulesEventKind::rule_warning && e.kind != wm::RulesEventKind::incident) {
        static const char* const kinds[] = {"warning", "incident", "penalty", "served", "cancelled", "late",
                                            "mark_touch", "protestable", "protested", "dsq"};
        const std::string_view rule = wm::rule_code_str(e.rule);
        std::fprintf(tel, "#ev,%.1f,%d,%s,%.*s,other %d,mark %d\n",
                     static_cast<double>(w->race().race_time(e.tick)), e.boat, kinds[static_cast<int>(e.kind)],
                     static_cast<int>(rule.size()), rule.data(), e.other, e.mark);
      }
    }
  }
  if (out != nullptr) std::fclose(out);
  if (tel != nullptr) {
    for (std::size_t i = 0; i < w->boat_count(); ++i) {
      std::fprintf(tel, "#split,%zu", i);
      for (const float t : w->race().boat(i).splits) std::fprintf(tel, ",%.1f", static_cast<double>(t));
      const std::string_view code = wm::score_code_name(w->race().boat(i).code);
      std::fprintf(tel, ",place %d %.*s,D %.1f m,v %.2f m/s\n", w->race().boat(i).place, static_cast<int>(code.size()),
                   code.data(), static_cast<double>(i < last_d.size() ? last_d[i] : 0.0f),
                   static_cast<double>(w->boat(i).state().v));
    }
    std::fclose(tel);
  }

  last = w->checksum();
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
