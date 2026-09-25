#include "base/fp_env.h"

#include <cfenv>
#include <cstdint>
#include <cstring>

namespace wm {

namespace {

std::uint32_t bits_of(float f) {
  std::uint32_t u;
  std::memcpy(&u, &f, sizeof u);
  return u;
}

float float_of(std::uint32_t u) {
  float f;
  std::memcpy(&f, &u, sizeof f);
  return f;
}

}  // namespace

bool fp_env_ok() {
  if (std::fegetround() != FE_TONEAREST) return false;
  // volatile keeps the arithmetic at run time, in the current environment.
  volatile float smallest_normal = float_of(0x00800000u);  // 2^-126
  volatile float half = 0.5f;
  float denormal_out = smallest_normal * half;             // 2^-127, a denormal: FTZ would give 0
  if (bits_of(denormal_out) != 0x00400000u) return false;
  volatile float denormal_in = float_of(0x00000001u);      // 2^-149
  volatile float two = 2.0f;
  float doubled = denormal_in * two;                       // DAZ would read the input as 0
  if (bits_of(doubled) != 0x00000002u) return false;
  return true;
}

float fp_probe_mul_add(float a, float b, float c) { return a * b + c; }

}  // namespace wm
