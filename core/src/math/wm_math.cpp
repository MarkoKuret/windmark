// Operations exactly as written in conventions.md §6, one rounding per operation, in the written order.
// This file must be built with the float rules (no contraction): every a*b+c below is two roundings.
#include "math/wm_math.h"

#include <cmath>
#include <cstdint>

namespace wm {

float round_half_even(float x) { return std::nearbyint(x); }

SinCos wm_sincos(float x) {
  const float k = round_half_even(x * 0.636619772f);  // 2/pi
  const std::int32_t q = static_cast<std::int32_t>(k);
  // Three-part pi/2; the three products by k are separate roundings.
  const float r = ((x - k * 1.5703125f) - k * 4.83751297e-4f) - k * 7.54978995e-8f;
  const float z = r * r;
  const float sr = ((-1.9515295891e-4f * z + 8.3321608736e-3f) * z - 1.6666654611e-1f) * z * r + r;
  const float cr =
      ((2.443315711809948e-5f * z - 1.388731625493765e-3f) * z + 4.166664568298827e-2f) * z * z - 0.5f * z + 1.0f;
  switch (q & 3) {
    case 0: return {sr, cr};
    case 1: return {cr, -sr};
    case 2: return {-sr, -cr};
    default: return {-cr, sr};
  }
}

float wm_sin(float x) { return wm_sincos(x).s; }
float wm_cos(float x) { return wm_sincos(x).c; }

float wm_atan(float x) {
  const float sign = x < 0.0f ? -1.0f : 1.0f;
  x = std::fabs(x);
  float y = 0.0f;
  if (x > 2.41421356f) {
    y = HALF_PI;
    x = -1.0f / x;
  } else if (x > 0.414213562f) {
    y = QUARTER_PI;
    x = (x - 1.0f) / (x + 1.0f);
  }
  const float z = x * x;
  y = y + ((((8.05374449538e-2f * z - 1.38776856032e-1f) * z + 1.99777106478e-1f) * z - 3.33329491539e-1f) * z * x + x);
  return sign * y;
}

float wm_atan2(float y, float x) {
  if (x == 0.0f) return y > 0.0f ? HALF_PI : (y < 0.0f ? -HALF_PI : 0.0f);
  float a = wm_atan(y / x);
  if (x < 0.0f) a = y >= 0.0f ? a + PI : a - PI;
  return a;
}

float wm_asin(float x) {
  const float a = std::fabs(x);
  float z;
  float r;
  bool big;
  if (a > 0.5f) {
    z = 0.5f * (1.0f - a);
    r = std::sqrt(z);
    big = true;
  } else {
    z = a * a;
    r = a;
    big = false;
  }
  float p = ((((4.2163199048e-2f * z + 2.4181311049e-2f) * z + 4.5470025998e-2f) * z + 7.4953002686e-2f) * z +
             1.6666752422e-1f) * z * r + r;
  if (big) p = HALF_PI - (p + p);
  return x < 0.0f ? -p : p;
}

float wm_acos(float x) { return HALF_PI - wm_asin(x); }

float wm_exp(float x) {
  const float n = std::floor(x * 1.44269504f + 0.5f);
  const float r = (x - n * 0.693359375f) - n * (-2.12194440e-4f);
  const float z = r * r;
  const float y = (((((1.9875691500e-4f * r + 1.3981999507e-3f) * r + 8.3334519073e-3f) * r + 4.1665795894e-2f) * r +
                    1.6666665459e-1f) * r + 5.0000001201e-1f) * z + r + 1.0f;
  return std::ldexp(y, static_cast<int>(static_cast<std::int32_t>(n)));  // exact scaling by 2^n
}

float wm_pow10(float x) { return wm_exp(x * 2.30258512f); }

float wrap_pi(float a) {
  if (-PI <= a && a < PI) return a;
  const float k = std::floor((a + PI) * 0.159154937f);  // 1/(2 pi)
  float r = (a - k * 6.28125f) - k * 1.93530717e-3f;    // two-part 2 pi
  if (r < -PI) r = r + TWO_PI;
  if (r >= PI) r = r - TWO_PI;
  return r;
}

float wrap_2pi(float a) {
  if (0.0f <= a && a < TWO_PI) return a;
  const float k = std::floor(a * 0.159154937f);
  float r = (a - k * 6.28125f) - k * 1.93530717e-3f;
  if (r < 0.0f) r = r + TWO_PI;
  if (r >= TWO_PI) r = r - TWO_PI;
  return r;
}

float angle_diff(float a, float b) { return wrap_pi(a - b); }

float angle_lerp(float a, float b, float t) { return wrap_2pi(a + t * angle_diff(b, a)); }

Vec2 dir(float psi) {
  const SinCos sc = wm_sincos(psi);
  return {sc.s, sc.c};
}

float compass(Vec2 v) { return wrap_2pi(wm_atan2(v.x, v.y)); }

}  // namespace wm
