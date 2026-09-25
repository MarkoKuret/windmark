// Counter-based random numbers (conventions.md §7): every draw is a pure function of (seed, stream, index), so
// any client evaluates any draw at any time without replaying a sequence.
#pragma once

#include <cstdint>

namespace wm {

// The only allowed stream numbers (conventions.md §7). A new use gets a new number there first.
enum class RngStream : std::uint64_t {
  wind_shift = 1,        // wind.md §4
  wind_oscillation = 2,  // wind.md §5
  puff_slots = 3,        // wind.md §6
  puff_generations = 4,  // wind.md §6
  wave_phases = 5,       // sea.md §3
  attitude_wobble = 6,   // boat.md §6.5
  spawn_shuffle = 7,     // race.md
  ai_first = 16,         // ai.md: 16..31
  ai_last = 31,
};

std::uint64_t mix64(std::uint64_t z);
std::uint64_t rng_u64(std::uint64_t seed, std::uint64_t stream, std::uint64_t index);
std::uint32_t rng_u32(std::uint64_t seed, std::uint64_t stream, std::uint64_t index);
float rng_unit(std::uint64_t seed, std::uint64_t stream, std::uint64_t index);  // [0, 1), exact
float rng_range(float lo, float hi, std::uint64_t seed, std::uint64_t stream, std::uint64_t index);

inline std::uint64_t rng_u64(std::uint64_t seed, RngStream stream, std::uint64_t index) {
  return rng_u64(seed, static_cast<std::uint64_t>(stream), index);
}
inline float rng_unit(std::uint64_t seed, RngStream stream, std::uint64_t index) {
  return rng_unit(seed, static_cast<std::uint64_t>(stream), index);
}
inline float rng_range(float lo, float hi, std::uint64_t seed, RngStream stream, std::uint64_t index) {
  return rng_range(lo, hi, seed, static_cast<std::uint64_t>(stream), index);
}

}  // namespace wm
