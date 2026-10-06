// Venue conditions (data_format.md §6.7) and their resolution into one race's settings (race.md §2.1): the shipped
// Practice Waters, a test venue with a tide and a trend, the three weather modes, the tide turn, the refusals, and
// the C API path (wm_world_settings_resolve, then wm_world_create).
#include <cmath>
#include <string>

#include "data/venue.h"
#include "doctest.h"
#include "math/rng.h"
#include "race/conditions.h"
#include "wind/wind.h"

namespace {

const std::string kData = WINDMARK_DATA_DIR;
constexpr float KN = 0.514444f;

wm::VenueData practice() {
  wm::VenueData v;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_venue(kData + "/venues/practice_waters.venue.json", v, err), err.message());
  return v;
}

// A small venue with a uniform current field (vx = 1 m/s everywhere), a tide turning to the ebb between 40 % and
// 60 % of the race, a trend that backs, an oscillation and a swell. `cond` replaces the conditions block.
std::string tidal_text(const std::string& cond = "", const std::string& briefing = "") {
  const std::string c = cond.empty() ? R"({
      "wind": {"speed": [6.0, 9.0], "from": 3.927, "from_spread": 0.2},
      "shift": {"preset": "stable", "amplitude": 0.0698, "trend_rate": -0.000145, "trend_max": 0.2618},
      "oscillation": {"amplitude": 0.0349, "time_scale": 17},
      "puffs": {"preset": "standard", "puff_cap_up": 0.3, "puff_life_min": 50},
      "current": {"speed": 0.1, "to": 1.0},
      "tide": {"scale": 0.6, "period": 44712, "turn": [0.4, 0.6], "turn_to": -1},
      "sea": {"scale": 0.8, "swells": [{"hs": 0.8, "tp": 12.0, "from": 4.19}]},
      "random": {"tide_scale": [0.5, 1.5], "swell_scale": [0.5, 1.5]}})"
                                       : cond;
  return R"({"schema": "windmark.venue/1", "id": "tidal", "name": "Tidal Test", "version": 1,
             "bounds": [-1000, -1000, 1000, 1000], "fetch": 8000,
             "current_field": {"grid": {"x0": -5000, "y0": -5000, "dx": 10000, "dy": 10000, "nx": 2, "ny": 2},
                               "vx": [1, 1, 1, 1], "vy": [0, 0, 0, 0], "ref_speed": 1.0},
             "conditions": )" +
         c + briefing + "}";
}

wm::VenueData tidal(const std::string& cond = "") {
  wm::VenueData v;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::parse_venue(tidal_text(cond), "tidal", v, err), err.message());
  return v;
}

bool refused(const std::string& text, const std::string& path) {
  wm::VenueData v;
  wm::LoadError err;
  if (wm::parse_venue(text, "t", v, err)) return false;
  return err.message().find(path) != std::string::npos;
}

struct Resolved {
  wm::WindSettings w;
  wm::SeaSettings s;
};

Resolved resolve(const wm::VenueData& v, wm::WeatherChoice c, std::uint64_t seed, wm::RaceTiming t = {}) {
  Resolved r;
  std::string error;
  REQUIRE_MESSAGE(wm::resolve_weather(v, c, seed, t, r.w, r.s, error), error);
  return r;
}

}  // namespace

TEST_CASE("conditions: Practice Waters ships its conditions and briefing") {
  const wm::VenueData v = practice();
  CHECK(v.id == "practice_waters");
  CHECK(v.name == "Practice Waters");
  REQUIRE(v.has_conditions);
  const wm::VenueConditions& c = v.conditions;
  CHECK(std::lround(c.speed_min / KN) == 10);
  CHECK(std::lround(c.speed_max / KN) == 14);
  CHECK(c.from == 0.0f);
  CHECK(c.shift_preset == wm::ShiftPreset::stable);
  CHECK(c.puff_preset == wm::PuffPreset::light);
  CHECK(c.puffs.cap_up == doctest::Approx(0.15f));
  CHECK(std::lround(c.current_speed / KN * 10.0f) == 3);
  CHECK_FALSE(c.has_tide);
  CHECK(c.r_shift.size() == 3);
  CHECK(c.r_puffs.size() == 2);
  CHECK(v.has_ref_speed);
}

TEST_CASE("conditions: random defaults widen the local values") {
  const wm::VenueData v = tidal(R"({"wind": {"speed": [3.0, 12.0], "from_spread": 0.3},
                                    "shift": {"preset": "unstable"}, "puffs": {"preset": "light"}})");
  const wm::VenueConditions& c = v.conditions;
  CHECK(c.r_speed_min == doctest::Approx(2.06f));   // clamped to 4 kn
  CHECK(c.r_speed_max == doctest::Approx(12.87f));  // clamped to 25 kn
  CHECK(c.r_from_spread == doctest::Approx(0.6f));
  REQUIRE(c.r_shift.size() == 2);
  CHECK(c.r_shift[0] == wm::ShiftPreset::shifty);
  CHECK(c.r_shift[1] == wm::ShiftPreset::unstable);
  REQUIRE(c.r_puffs.size() == 2);  // light and standard, never `none` unless local is none
  CHECK(c.r_puffs[0] == wm::PuffPreset::light);
  CHECK(c.r_puffs[1] == wm::PuffPreset::standard);
  CHECK(c.r_tide_min == 0.5f);
  CHECK(c.r_tide_max == 1.2f);
  // an explicit amplitude picks the preset whose briefing band holds it (7° is Oscillating)
  const wm::VenueData e = tidal(R"({"shift": {"amplitude": 0.122}})");
  REQUIRE(e.conditions.r_shift.size() == 3);
  CHECK(e.conditions.r_shift[1] == wm::ShiftPreset::oscillating);
}

TEST_CASE("conditions: refusals") {
  CHECK(refused(tidal_text(R"({"wind": {"speed": [9, 6]}})"), "$.conditions.wind.speed"));
  CHECK(refused(tidal_text(R"({"wind": {"speed": [1, 6]}})"), "$.conditions.wind.speed"));
  CHECK(refused(tidal_text(R"({"wind": {"from_spread": 0.5}})"), "$.conditions.wind.from_spread"));
  CHECK(refused(tidal_text(R"({"shift": {"preset": "wild"}})"), "$.conditions.shift.preset"));
  CHECK(refused(tidal_text(R"({"shift": {"trend_max": 0.5}})"), "$.conditions.shift.trend_max"));
  CHECK(refused(tidal_text(R"({"shift": {"hold_max": 10, "hold_min": 20}})"), "$.conditions.shift.hold_min"));
  CHECK(refused(tidal_text(R"({"oscillation": {"amplitude": 0.2, "time_scale": 17}})"), "$.conditions.oscillation"));
  CHECK(refused(tidal_text(R"({"puffs": {"preset": "storm"}})"), "$.conditions.puffs.preset"));
  CHECK(refused(tidal_text(R"({"puffs": {"puff_wobble": 1}})"), "$.conditions.puffs.puff_wobble"));
  CHECK(refused(tidal_text(R"({"puffs": {"lull_strength_max": 1.0}})"), "$.conditions.puffs"));
  CHECK(refused(tidal_text(R"({"tide": {"scale": 1, "period": 44712, "turn": [0.1, 0.9], "turn_to": -1}})"),
                "$.conditions.tide.turn"));
  CHECK(refused(tidal_text(R"({"tide": {"scale": 1, "period": 44712, "turn": [0.4, 0.6], "turn_to": 0}})"),
                "$.conditions.tide.turn_to"));
  CHECK(refused(tidal_text(R"({"sea": {"swells": [{"hs": 1, "tp": 0, "from": 0}]}})"), "$.conditions.sea.swells[0].tp"));
  CHECK(refused(tidal_text(R"({"random": {"shift": []}})"), "$.conditions.random.shift"));
  CHECK(refused(tidal_text(R"({"random": {"from_spread": 1.0}})"), "$.conditions.random.from_spread"));
  // a tide needs a current field
  CHECK(refused(R"({"schema": "windmark.venue/1", "id": "t", "name": "T", "version": 1, "bounds": [-1, -1, 1, 1],
                    "conditions": {"tide": {"scale": 1, "period": 44712, "turn": [0.4, 0.6], "turn_to": 1}}})",
                "$.conditions.tide"));
  // player-facing text: no em dashes
  CHECK(refused(tidal_text("{}", R"(, "briefing": {"tag": "Bora", "tip": "Gusts — tack"})"), "$.briefing.tip"));
  CHECK(refused(tidal_text("{}", ", \"briefing\": {\"tag\": \"A \xE2\x80\x94 B\"}"), "$.briefing.tag"));
  CHECK_FALSE(refused(tidal_text("{}", R"(, "briefing": {"tag": "Bora", "tip": "Tack on the headers."})"), "$"));
}

TEST_CASE("conditions: local draws stay in the venue's ranges and repeat with the seed") {
  const wm::VenueData v = practice();
  wm::WeatherChoice local;
  float lo = 1e9f, hi = 0.0f;
  for (std::uint64_t seed = 1; seed <= 300; ++seed) {
    const Resolved r = resolve(v, local, seed);
    CHECK(r.w.base_speed >= v.conditions.speed_min);
    CHECK(r.w.base_speed <= v.conditions.speed_max);
    CHECK(r.w.base_from == 0.0f);  // spread 0
    lo = std::fmin(lo, r.w.base_speed);
    hi = std::fmax(hi, r.w.base_speed);
    CHECK(r.w.shift_amplitude == doctest::Approx(3.0f * wm::DEG));
    CHECK(r.w.shift_hold_max_ms == 120000);
    CHECK(r.w.puffs_enabled);
    CHECK(r.w.puffs.cap_up == doctest::Approx(0.15f));
    CHECK(r.w.current_to == doctest::Approx(1.5708f));
    CHECK(r.w.tide_scale == 0.0f);
    CHECK(r.s.swells.empty());
  }
  CHECK(hi - lo > 1.0f);
  const Resolved a = resolve(v, local, 77), b = resolve(v, local, 77);
  CHECK(a.w.base_speed == b.w.base_speed);
  // the formula of race.md §2.1, bit for bit
  const float s0 = v.conditions.speed_min, s1 = v.conditions.speed_max;
  CHECK(a.w.base_speed == s0 + (s1 - s0) * (0.5f * (wm::rng_unit(77, 8, 0) + wm::rng_unit(77, 8, 1))));
}

TEST_CASE("conditions: random mode is wider, picks presets from the lists, custom takes the player's") {
  const wm::VenueData v = practice();
  wm::WeatherChoice random;
  random.mode = wm::WeatherMode::random;
  bool below = false, above = false, steady = false, standard = false;
  for (std::uint64_t seed = 1; seed <= 400; ++seed) {
    const Resolved r = resolve(v, random, seed);
    CHECK(r.w.base_speed >= v.conditions.r_speed_min);
    CHECK(r.w.base_speed <= v.conditions.r_speed_max);
    below = below || r.w.base_speed < v.conditions.speed_min;
    above = above || r.w.base_speed > v.conditions.speed_max;
    const float off = std::fabs(wm::wrap_pi(r.w.base_from));
    CHECK(off <= v.conditions.r_from_spread + 1e-6f);
    steady = steady || r.w.shift_amplitude == 0.0f;
    standard = standard || r.w.puffs.cap_up == 0.25f;
    CHECK(r.w.shift_amplitude <= 8.0f * wm::DEG + 1e-6f);  // steady, stable or oscillating
  }
  CHECK(below);
  CHECK(above);
  CHECK(steady);
  CHECK(standard);

  wm::WeatherChoice custom;
  custom.mode = wm::WeatherMode::custom;
  custom.speed = 18.0f * KN;
  custom.from = 270.0f * wm::DEG;
  custom.has_shift = true;
  custom.shift = wm::ShiftPreset::unstable;
  custom.has_puffs = true;
  custom.puffs = wm::PuffPreset::gusty;
  const Resolved r = resolve(v, custom, 5);
  CHECK(r.w.base_speed == custom.speed);
  CHECK(r.w.base_from == doctest::Approx(custom.from));
  CHECK(r.w.shift_amplitude == doctest::Approx(25.0f * wm::DEG));
  CHECK(r.w.puffs.cap_up == doctest::Approx(0.45f));
  CHECK(r.w.puffs.puff_count == 7);
  CHECK(r.w.current_speed == v.conditions.current_speed);  // the venue's current
  // custom without presets: the venue's
  custom.has_shift = custom.has_puffs = false;
  const Resolved d = resolve(v, custom, 5);
  CHECK(d.w.shift_amplitude == doctest::Approx(3.0f * wm::DEG));
  CHECK(d.w.puffs.cap_up == doctest::Approx(0.15f));
}

TEST_CASE("conditions: the tide turns inside the race window, trend, oscillation and swells are the venue's") {
  const wm::VenueData v = tidal();
  const wm::VenueConditions& c = v.conditions;
  CHECK(c.puffs.cap_up == doctest::Approx(0.3f));     // override over the preset
  CHECK(c.puffs.life_min_ms == 50000);                // lifetimes in s in the file
  wm::RaceTiming t;
  t.t_race_s = 1200.0f;
  t.t_gun_ms = 330000;
  for (std::uint64_t seed = 1; seed <= 40; ++seed) {
    for (wm::WeatherMode m : {wm::WeatherMode::local, wm::WeatherMode::random}) {
      wm::WeatherChoice ch;
      ch.mode = m;
      Resolved r = resolve(v, ch, seed, t);
      CHECK(r.w.shift_trend_rate == c.trend_rate);
      CHECK(r.w.shift_trend_max == c.trend_max);
      CHECK(r.w.osc_enabled);
      if (m == wm::WeatherMode::local) CHECK(r.w.shift_amplitude == doctest::Approx(0.0698f));
      REQUIRE(r.s.swells.size() == 1);
      CHECK(r.s.sea_scale == doctest::Approx(0.8f));
      // the turn: tide(t_turn) == 0 and the factor's sign changes to turn_to (-1) there
      const float a = m == wm::WeatherMode::local ? 0.4f : 0.0f, b = m == wm::WeatherMode::local ? 0.6f : 1.0f;
      const float f = a + (b - a) * wm::rng_unit(seed, 8, 3);
      const auto t_turn = static_cast<std::uint32_t>(t.t_gun_ms + static_cast<std::uint64_t>(f * t.t_race_s * 1000.0f));
      CHECK(t_turn >= t.t_gun_ms + static_cast<std::uint64_t>(a * 1200000.0f) - 1);
      CHECK(t_turn <= t.t_gun_ms + static_cast<std::uint64_t>(b * 1200000.0f) + 1);
      r.w.venue_current_field = v.current_field_ptr();
      r.w.current_speed = 0.0f;  // the tide alone
      const wm::WindField wf(seed, r.w);
      CHECK(std::fabs(wf.current(0, 0, t_turn).x) < 1e-3f);
      CHECK(wf.current(0, 0, t_turn - 600000 > t_turn ? 0 : t_turn - 600000).x > 0.0f);
      CHECK(wf.current(0, 0, t_turn + 600000).x < 0.0f);
      if (m == wm::WeatherMode::local) {
        CHECK(r.w.tide_scale == doctest::Approx(0.6f));
      } else {
        CHECK(r.w.tide_scale >= 0.6f * 0.5f - 1e-6f);
        CHECK(r.w.tide_scale <= 0.6f * 1.5f + 1e-6f);
        CHECK(r.s.swells[0].hs >= 0.4f - 1e-6f);
        CHECK(r.s.swells[0].hs <= 1.2f + 1e-6f);
      }
    }
  }
}

TEST_CASE("conditions: a venue without conditions offers custom only, on the defaults") {
  wm::VenueData v = practice();
  v.has_conditions = false;
  v.conditions = wm::VenueConditions{};
  wm::WindSettings w;
  wm::SeaSettings s;
  std::string error;
  wm::WeatherChoice local;
  CHECK_FALSE(wm::resolve_weather(v, local, 1, {}, w, s, error));
  CHECK(error.find("custom") != std::string::npos);
  wm::WeatherChoice custom;
  custom.mode = wm::WeatherMode::custom;
  custom.speed = 6.0f;
  const Resolved r = resolve(v, custom, 1);
  const wm::WindSettings d;
  CHECK(r.w.base_speed == 6.0f);
  CHECK(r.w.shift_amplitude == d.shift_amplitude);  // shifty
  CHECK(r.w.puffs.cap_up == d.puffs.cap_up);        // standard
  CHECK(r.w.current_speed == 0.0f);
  CHECK(r.w.tide_scale == 0.0f);
  CHECK(r.s.sea_scale == 1.0f);
}

TEST_CASE("conditions: race timing from the course and the sequence") {
  wm::CourseData c;
  wm::RaceSettings s;
  wm::RaceTiming t = wm::race_timing(s, nullptr);
  CHECK(t.t_gun_ms == 0);
  CHECK(t.t_race_s == 900.0f);
  t = wm::race_timing(s, &c);
  CHECK(t.t_gun_ms == (30u + 300u) * 1000u);  // free sailing, then 5-4-1-0
  CHECK(t.t_race_s == 900.0f);
  c.race.target_duration = 1500.0f;
  s.sequence = wm::SequenceKind::s3210;
  t = wm::race_timing(s, &c);
  CHECK(t.t_gun_ms == (30u + 180u) * 1000u);
  CHECK(t.t_race_s == 1500.0f);
}
