// Writes the math vector file the test suite checks (tests/vectors/math_vectors.txt): inputs and results of the
// core's math functions and RNG as hex bit patterns. Regenerate only on purpose, and check the result on a second
// architecture before committing it:
//   build/tests/windmark_gen_vectors > tests/vectors/math_vectors.txt
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "math/rng.h"
#include "math/wm_math.h"

namespace {

std::uint32_t b(float f) {
  std::uint32_t u;
  std::memcpy(&u, &f, sizeof u);
  return u;
}

// Deterministic inputs: the RNG itself on a private stream number (not a simulation stream).
constexpr std::uint64_t kSeed = 0x57494E444D41524Bull;
constexpr std::uint64_t kStream = 1000;

float in_range(float lo, float hi, std::uint64_t i) { return wm::rng_range(lo, hi, kSeed, kStream, i); }

}  // namespace

int main() {
  std::printf("# windmark math vectors: function, inputs, results (binary32 bit patterns, hex)\n");
  std::uint64_t n = 0;
  const float special[] = {0.0f, -0.0f, 1e-30f, 0.5f, 1.0f, -3.0f, 100.0f, wm::PI, -wm::PI, wm::HALF_PI,
                           wm::TWO_PI, 8192.0f, -8192.0f, 65535.0f, 12345.678f};
  for (float x : special) {
    const wm::SinCos sc = wm::wm_sincos(x);
    std::printf("sincos %08" PRIX32 " %08" PRIX32 " %08" PRIX32 "\n", b(x), b(sc.s), b(sc.c));
  }
  for (int i = 0; i < 600; ++i, ++n) {
    const float x = i < 400 ? in_range(-8.0f, 8.0f, n) : in_range(-8192.0f, 8192.0f, n);
    const wm::SinCos sc = wm::wm_sincos(x);
    std::printf("sincos %08" PRIX32 " %08" PRIX32 " %08" PRIX32 "\n", b(x), b(sc.s), b(sc.c));
  }
  for (int i = 0; i < 300; ++i, ++n) {
    const float x = i < 200 ? in_range(-4.0f, 4.0f, n) : in_range(-1000.0f, 1000.0f, n);
    std::printf("atan %08" PRIX32 " %08" PRIX32 "\n", b(x), b(wm::wm_atan(x)));
  }
  for (int i = 0; i < 300; ++i, n += 2) {
    const float y = in_range(-10.0f, 10.0f, n);
    const float x = i % 10 == 0 ? 0.0f : in_range(-10.0f, 10.0f, n + 1);
    std::printf("atan2 %08" PRIX32 " %08" PRIX32 " %08" PRIX32 "\n", b(y), b(x), b(wm::wm_atan2(y, x)));
  }
  for (int i = 0; i < 200; ++i, ++n) {
    const float x = i == 0 ? 1.0f : (i == 1 ? -1.0f : (i == 2 ? 0.5f : in_range(-1.0f, 1.0f, n)));
    std::printf("asin %08" PRIX32 " %08" PRIX32 "\n", b(x), b(wm::wm_asin(x)));
    std::printf("acos %08" PRIX32 " %08" PRIX32 "\n", b(x), b(wm::wm_acos(x)));
  }
  for (int i = 0; i < 200; ++i, ++n) {
    const float x = i == 0 ? -80.0f : (i == 1 ? 80.0f : in_range(-80.0f, 80.0f, n));
    std::printf("exp %08" PRIX32 " %08" PRIX32 "\n", b(x), b(wm::wm_exp(x)));
  }
  for (int i = 0; i < 100; ++i, ++n) {
    const float x = in_range(-30.0f, 30.0f, n);
    std::printf("pow10 %08" PRIX32 " %08" PRIX32 "\n", b(x), b(wm::wm_pow10(x)));
  }
  for (int i = 0; i < 300; ++i, ++n) {
    const float x = i < 100 ? in_range(-7.0f, 7.0f, n) : in_range(-5000.0f, 5000.0f, n);
    std::printf("wrap_pi %08" PRIX32 " %08" PRIX32 "\n", b(x), b(wm::wrap_pi(x)));
    std::printf("wrap_2pi %08" PRIX32 " %08" PRIX32 "\n", b(x), b(wm::wrap_2pi(x)));
  }
  for (int i = 0; i < 100; ++i, n += 3) {
    const float a = in_range(0.0f, wm::TWO_PI, n);
    const float c = in_range(0.0f, wm::TWO_PI, n + 1);
    const float t = in_range(0.0f, 1.0f, n + 2);
    std::printf("angle_lerp %08" PRIX32 " %08" PRIX32 " %08" PRIX32 " %08" PRIX32 "\n", b(a), b(c), b(t),
                b(wm::angle_lerp(a, c, t)));
  }
  for (std::uint64_t i = 0; i < 200; ++i) {
    const std::uint64_t seed = wm::rng_u64(kSeed, kStream + 1, i);
    const std::uint64_t stream = i % 32;
    const std::uint64_t index = i * 977 + (i % 3 == 0 ? 0xFFFFFFFFull : 0);
    std::printf("rng %016" PRIX64 " %" PRIX64 " %" PRIX64 " %016" PRIX64 " %08" PRIX32 "\n", seed, stream, index,
                wm::rng_u64(seed, stream, index), b(wm::rng_unit(seed, stream, index)));
  }
  return 0;
}
