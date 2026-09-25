#pragma once

#include <cstdint>
#include <cstring>

namespace wm_test {

inline std::uint32_t bits(float f) {
  std::uint32_t u;
  std::memcpy(&u, &f, sizeof u);
  return u;
}

inline float from_bits(std::uint32_t u) {
  float f;
  std::memcpy(&f, &u, sizeof f);
  return f;
}

}  // namespace wm_test
