// The core's scalar math (conventions.md §5 rule 12, §6). Every transcendental function the simulation uses
// comes from here, never from the platform libm, so results are identical bits on every platform.
#pragma once

#include <cstdint>

namespace wm {

// §6 constants, exact binary32 values.
inline constexpr float PI = 3.14159274f;
inline constexpr float TWO_PI = 6.28318548f;
inline constexpr float HALF_PI = 1.57079637f;
inline constexpr float QUARTER_PI = 0.785398163f;

// §1 conversion constants (edges only: HUD, logs, tools).
inline constexpr float KNOT = 0.514444470f;  // m/s per knot
inline constexpr float DEG = 0.0174532924f;  // rad per degree
inline constexpr float G = 9.81f;            // m/s², sea.md

// §4 tick length.
inline constexpr float DT = 0.05f;
inline constexpr std::uint32_t DT_MS = 50;

// §5 rule 12. clamp keeps NaN (neither comparison holds), which is why inputs are sanitised first (rule 11).
inline float clamp(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
inline float lerp(float a, float b, float t) { return a + t * (b - a); }
inline float min(float a, float b) { return a < b ? a : b; }
inline float max(float a, float b) { return a > b ? a : b; }
// §3: +1 for x >= 0 (either zero), -1 for x < 0; never 0. NaN gives -1 (x >= 0 is false).
inline float sgn(float x) { return x >= 0.0f ? 1.0f : -1.0f; }

struct SinCos {
  float s;
  float c;
};

// §6.1: accurate to about 1e-7 for |x| <= 8192, 1e-4 up to 65536; deterministic for any finite x.
SinCos wm_sincos(float x);
float wm_sin(float x);
float wm_cos(float x);

// §6.2
float wm_atan(float x);
float wm_atan2(float y, float x);  // [-PI, PI]

// §6.3: domain [-1, 1], callers clamp.
float wm_asin(float x);
float wm_acos(float x);

// §6.4: domain [-80, 80], callers clamp.
float wm_exp(float x);
float wm_pow10(float x);

// §6.5 angle helpers.
float wrap_pi(float a);    // [-PI, PI)
float wrap_2pi(float a);   // [0, TWO_PI)
float angle_diff(float a, float b);            // wrap_pi(a - b)
float angle_lerp(float a, float b, float t);   // compass angles, shortest way

// §2 compass helpers.
struct Vec2 {
  float x;
  float y;
};
Vec2 dir(float psi);      // (sin psi, cos psi): east, north
float compass(Vec2 v);    // wrap_2pi(atan2(vx, vy)); callers handle |v| < 1e-6 themselves

// §5 rule 8: round half to even in the default rounding mode.
float round_half_even(float x);

}  // namespace wm
