// Writes the sea and puff samples the front end checks its water renderer against (water_render.md §9): for fixed
// sea states, the core's wave components, exposure grid, and sea heights and slopes at points up to 8 km from the
// origin and tick times up to 4 hours; for the example venue, the exposure at random points and the puff patches
// with the puff factor at random points of a 2 x 2 km area at 100 times. Numbers are printed with 9 significant
// digits, so every binary32 value reads back exactly. Read-only use of the core: nothing here changes behaviour.
//   build/tests/windmark_gen_sea_render_samples <repo>/data/venues/practice_waters.venue.json > samples.json
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "data/load_error.h"
#include "data/venue.h"
#include "env_scenarios.h"
#include "math/rng.h"
#include "math/wm_math.h"
#include "sea/sea.h"
#include "wind/wind.h"

namespace {

constexpr std::uint64_t kSeed = 0x5345415245ull;  // test inputs only
constexpr std::uint64_t kStream = 2100;           // private stream, not a simulation stream

double D(float f) { return static_cast<double>(f); }

float in_range(float lo, float hi, std::uint64_t i) { return wm::rng_range(lo, hi, kSeed, kStream, i); }

std::uint32_t tick_time(std::uint64_t i) {
  return static_cast<std::uint32_t>(in_range(0.0f, 1.0f, i) * 14400000.0f) / 50u * 50u;
}

void print_components(const wm::SeaField& f) {
  std::printf("\"components\": [");
  const auto& cs = f.components();
  for (std::size_t i = 0; i < cs.size(); ++i)
    std::printf("%s[%.9g, %.9g, %.9g, %.9g, %" PRIu32 "]", i ? ", " : "", D(cs[i].a), D(cs[i].kx), D(cs[i].ky), D(cs[i].c),
                cs[i].T);
  std::printf("],\n");
}

void print_exposure(const wm::VenueExposure* e, float def) {
  if (!e) {
    std::printf("\"exposure\": null,\n");
    return;
  }
  std::printf("\"exposure\": {\"x0\": %.9g, \"y0\": %.9g, \"dx\": %.9g, \"dy\": %.9g, \"nx\": %" PRIu32
              ", \"ny\": %" PRIu32 ", \"default\": %.9g, \"e\": [",
              D(e->grid.x0), D(e->grid.y0), D(e->grid.dx), D(e->grid.dy), e->grid.nx, e->grid.ny, D(def));
  for (std::size_t i = 0; i < e->e.size(); ++i) std::printf("%s%.9g", i ? ", " : "", D(e->e[i]));
  std::printf("]},\n");
}

// Heights and slopes at points up to 8 km from the origin, tick times up to 4 h.
void print_heights(const wm::SeaField& f, std::uint64_t& n) {
  std::printf("\"heights\": [");
  for (int k = 0; k < 300; ++k, n += 3) {
    const float x = in_range(-8000.0f, 8000.0f, n);
    const float y = in_range(-8000.0f, 8000.0f, n + 1);
    const std::uint32_t t = tick_time(n + 2);
    const wm::SeaTick st = f.at(t);
    const wm::SeaSlope sl = st.sea_slope(x, y);
    std::printf("%s[%.9g, %.9g, %" PRIu32 ", %.9g, %.9g, %.9g]", k ? ", " : "", D(x), D(y), t, D(st.sea_height(x, y)),
                D(sl.dx), D(sl.dy));
  }
  std::printf("]");
}

struct Scenario {
  std::string name;
  std::uint64_t seed;
  wm::SeaSettings sea;
  bool venue = false;       // exposure and puff samples
  wm::WindSettings wind{};  // when venue
};

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s <practice_waters.venue.json>\n", argv[0]);
    return 2;
  }
  wm::VenueData venue;
  wm::LoadError err;
  if (!wm::load_venue(argv[1], venue, err)) {
    std::fprintf(stderr, "cannot load the venue %s\n", argv[1]);
    return 1;
  }

  std::vector<Scenario> sc;
  const wm_env::Venue env_venue;
  for (const wm_env::SeaScenario& s : wm_env::sea_scenarios(env_venue)) sc.push_back({s.name, s.seed, s.s});
  // The example venue at 10 and 20 kn from the south-west, wind sea from the growth law with the venue fetch.
  for (const float kn : {10.0f, 20.0f}) {
    Scenario s;
    s.name = "practice_waters_" + std::to_string(static_cast<int>(kn)) + "kn";
    s.seed = 0x42415921ull + static_cast<std::uint64_t>(kn);
    s.venue = true;
    s.wind.base_speed = kn * wm::KNOT;
    s.wind.base_from = 225.0f * wm::DEG;
    s.sea.wind_sea = wm::wind_sea_from_wind(D(s.wind.base_speed), D(venue.fetch), s.wind.base_from);
    wm::apply_venue(venue, s.wind, s.sea);
    sc.push_back(s);
  }

  std::uint64_t n = 0;
  std::printf("{\"schema\": \"windmark.sea_render_samples/1\",\n\"scenarios\": [\n");
  for (std::size_t si = 0; si < sc.size(); ++si) {
    const Scenario& s = sc[si];
    const wm::SeaField f(s.seed, s.sea);
    std::printf("%s{\"name\": \"%s\", \"seed\": %" PRIu64 ", \"hs\": %.9g, \"tp\": %.9g, \"from\": %.9g,\n",
                si ? ",\n" : "", s.name.c_str(), s.seed, D(s.sea.wind_sea.hs), D(s.sea.wind_sea.tp),
                D(s.sea.wind_sea.from));
    print_components(f);
    print_exposure(s.sea.exposure, s.sea.exposure_default);
    print_heights(f, n);
    if (s.venue) {
      // Exposure at random points over and around the grid (water_render.md §9.4).
      std::printf(",\n\"exposure_samples\": [");
      for (int k = 0; k < 10000; ++k, n += 2) {
        const float x = in_range(-3500.0f, 3500.0f, n);
        const float y = in_range(-3500.0f, 3500.0f, n + 1);
        std::printf("%s[%.9g, %.9g, %.9g]", k ? ", " : "", D(x), D(y), D(f.exposure(x, y)));
      }
      std::printf("],\n");
      // Puffs (wind.md §6, water_render.md §9.3): live patches and the factor at 100 random points in a 2 x 2 km
      // area, at 100 times.
      const wm::WindField w(s.seed, s.wind);
      const wm::PuffParams& p = s.wind.puffs;
      std::printf("\"wind\": {\"base_speed\": %.9g, \"base_from\": %.9g, \"puff_tile\": %.9g, \"cap_up\": %.9g, "
                  "\"cap_down\": %.9g},\n\"puffs\": [",
                  D(s.wind.base_speed), D(s.wind.base_from), D(p.tile), D(p.cap_up), D(p.cap_down));
      for (int k = 0; k < 100; ++k) {
        const std::uint32_t t = static_cast<std::uint32_t>(in_range(0.0f, 1.0f, n++) * 3600000.0f);
        const wm::WindTick tick = w.at(t);
        std::printf("%s\n{\"t\": %" PRIu32 ", \"global_from\": %.9g, \"patches\": [", k ? "," : "", t,
                    D(tick.global_from));
        const std::vector<wm::PuffPatch> pp = w.puff_patches(tick);
        for (std::size_t j = 0; j < pp.size(); ++j)
          std::printf("%s[%.9g, %.9g, %.9g, %.9g, %.9g]", j ? ", " : "", D(pp[j].px), D(pp[j].py), D(pp[j].R),
                      D(pp[j].s), D(pp[j].e));
        std::printf("], \"samples\": [");
        for (int q = 0; q < 100; ++q, n += 2) {
          const float x = in_range(-1000.0f, 1000.0f, n);
          const float y = in_range(-1000.0f, 1000.0f, n + 1);
          std::printf("%s[%.9g, %.9g, %.9g]", q ? ", " : "", D(x), D(y), D(w.puff_factor(tick, x, y)));
        }
        std::printf("]}");
      }
      std::printf("]");
    }
    std::printf("}");
  }
  std::printf("\n]}\n");
  return 0;
}
