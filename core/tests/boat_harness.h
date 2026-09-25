// Shared set-up for the boat and sail tests: the shipped performance files, a boat in a uniform wind, and a
// simple heading autopilot.
#pragma once

#include <cmath>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "boat/boat.h"
#include "data/perf.h"
#include "doctest.h"
#include "math/wm_math.h"

namespace wm_test {

inline const wm::PerfData& perf(const std::string& cls) {
  static std::map<std::string, std::unique_ptr<wm::PerfData>> cache;
  auto it = cache.find(cls);
  if (it == cache.end()) {
    auto p = std::make_unique<wm::PerfData>();
    wm::LoadError err;
    const std::string file = std::string(WINDMARK_DATA_DIR) + "/perf/" + cls + ".perf.json";
    REQUIRE_MESSAGE(wm::load_perf(file, *p, err), err.message());
    it = cache.emplace(cls, std::move(p)).first;
  }
  return *it->second;
}

inline float kn(float knots) { return knots * wm::KNOT; }
inline float deg(float d) { return d * wm::DEG; }
inline float to_deg(float r) { return r / wm::DEG; }
inline float to_kn(float v) { return v / wm::KNOT; }

// The class with feel multipliers applied the way the VPP applies a class file's `handling` block
// (data_format.md §3.7.1): accel tables times `accel`, decel_linear and decel_const times `decel`, both turn radii
// divided by `turn_rate`. Used where the shipped tables miss a spec's handling target, to show the core meets it
// once the data does.
inline const wm::PerfData& tuned(const std::string& cls, float accel, float decel, float turn_rate) {
  static std::map<std::string, std::unique_ptr<wm::PerfData>> cache;
  const std::string key = cls + "/" + std::to_string(accel) + "/" + std::to_string(decel) + "/" +
                          std::to_string(turn_rate);
  auto it = cache.find(key);
  if (it == cache.end()) {
    auto p = std::make_unique<wm::PerfData>(perf(cls));
    wm::Dynamics& d = p->dynamics;
    d.decel_linear = d.decel_linear * decel;
    d.decel_const = d.decel_const * decel;
    d.turn_radius_full = d.turn_radius_full / turn_rate;
    d.turn_radius_offset = d.turn_radius_offset / turn_rate;
    d.derived.turn_c = d.turn_radius_full + d.turn_radius_offset;
    for (wm::ConfigPerf& c : p->configs) {
      std::vector<float> v = c.accel.values();
      for (float& x : v) x = x * accel;
      c.accel = wm::Table(c.accel.axes(), c.accel.unit(), std::move(v));
    }
    it = cache.emplace(key, std::move(p)).first;
  }
  return *it->second;
}

// A boat in a steady uniform wind from `wind_from` with no current and flat water unless `sea` is set.
struct Sim {
  wm::Boat boat;
  wm::BoatEnv env;
  std::uint32_t tick = 0;

  Sim(const std::string& cls, float tws_kn, float wind_from, std::uint64_t seed = 1, std::uint32_t index = 0)
      : Sim(perf(cls), tws_kn, wind_from, seed, index) {}
  Sim(const wm::PerfData& p, float tws_kn, float wind_from, std::uint64_t seed = 1, std::uint32_t index = 0) {
    boat.init(&p, seed, index);
    env.wind_speed = kn(tws_kn);
    env.wind_speed_clean = env.wind_speed;
    env.wind_from = wind_from;
  }
  // Heading so that the true wind angle is `twa` (wind from starboard for twa > 0).
  void place(float twa, float v, std::int32_t front_sail, bool auto_trim = true) {
    boat.reset(0.0f, 0.0f, wm::wrap_2pi(env.wind_from - twa), v, front_sail, auto_trim, env);
  }
  void step() {
    boat.step(env);
    ++tick;
  }
  void run(float seconds) {
    const int n = static_cast<int>(std::lround(seconds / wm::DT));
    for (int i = 0; i < n; ++i) step();
  }
  // Proportional heading hold on a true wind angle, helm limited to +-limit.
  void steer_twa(float twa_target, float limit = 0.5f, float gain = 4.0f) {
    const float e = wm::wrap_pi(boat.state().twa - twa_target);  // > 0: bow is too far from the wind on stbd
    float h = gain * e * (boat.state().v >= 0.0f ? 1.0f : -1.0f);
    boat.set_helm(wm::clamp(h, -limit, limit));
  }
  const wm::BoatState& s() const { return boat.state(); }
};

}  // namespace wm_test
