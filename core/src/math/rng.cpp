#include "math/rng.h"

namespace wm {

// All arithmetic mod 2^64 (unsigned wrap-around).
std::uint64_t mix64(std::uint64_t z) {
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
  return z ^ (z >> 31);
}

std::uint64_t rng_u64(std::uint64_t seed, std::uint64_t stream, std::uint64_t index) {
  const std::uint64_t key = mix64(seed + 0x9E3779B97F4A7C15ull * (stream + 1));
  return mix64(key + 0xD1B54A32D192ED03ull * (index + 1));
}

std::uint32_t rng_u32(std::uint64_t seed, std::uint64_t stream, std::uint64_t index) {
  return static_cast<std::uint32_t>(rng_u64(seed, stream, index) >> 32);
}

float rng_unit(std::uint64_t seed, std::uint64_t stream, std::uint64_t index) {
  // 24 bits times 2^-24: exact in binary32.
  return static_cast<float>(rng_u32(seed, stream, index) >> 8) * 5.96046448e-8f;
}

float rng_range(float lo, float hi, std::uint64_t seed, std::uint64_t stream, std::uint64_t index) {
  return lo + (hi - lo) * rng_unit(seed, stream, index);
}

}  // namespace wm
