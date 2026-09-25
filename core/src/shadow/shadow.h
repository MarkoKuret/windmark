// Wind shadow (wind_shadow.md): each boat casts a blanket along its apparent wind and, upwind, a backwind band
// astern. A receiving boat takes the strongest single loss and its header. All shadows of a tick are computed
// from a snapshot of the boats at t_n, so boat order does not matter.
#pragma once

#include <cstdint>
#include <span>
#include <vector>

#include "data/perf.h"
#include "math/wm_math.h"
#include "wind/wind.h"

namespace wm {

// §2 per class, with the constants of §4 computed once.
struct ShadowClass {
  WindShadowParams p;
  float turb_ca, turb_sa;  // cos, sin of turb_angle
};

ShadowClass make_shadow_class(const WindShadowParams& p);

// §3 one boat of the tick-4 snapshot.
struct ShadowSource {
  const ShadowClass* cls = nullptr;  // not owned
  float pos_x = 0.0f, pos_y = 0.0f;  // hull reference point, m
  float psi = 0.0f;                  // heading
  float aws = 0.0f, awd_from = 0.0f, awa = 0.0f;
  float twa = 0.0f;
  bool spinnaker = false;  // front sail is a spinnaker, `up` or `prepare_drop`
  bool casts = true;       // race layer: false for boats that cast no shadow
};

struct ShadowLoss {
  float l;      // fraction of the wind speed lost
  float delta;  // header, rad, >= 0
};

// §4 loss from one source at a receiving point.
ShadowLoss shadow(const ShadowSource& B, float px, float py);

// §5 the wind at receiving boat `self` (or any point: pass self = -1 to count every boat) from the clean wind
// (U, from) and every other boat of the snapshot.
struct ShadowedWind {
  float speed, from;    // m/s, compass
  float loss, header;   // of the strongest source
  std::int32_t source;  // its index, -1 = clear air
};

ShadowedWind shadowed_wind(std::span<const ShadowSource> snapshot, std::int32_t self, float x, float y, float U,
                           float from);

// Tick step 5 for receiving boat `self` at its hull reference point (x, y): the clean wind of the tick, the other
// boats' shadows from the snapshot, and the current. The fields map one to one onto the boat's environment
// input (boat.md §2).
struct EnvAtBoat {
  float wind_speed, wind_from;              // shadowed
  float wind_speed_clean, wind_from_clean;  // wind.md §2, for the HUD, AI and the race layer
  float current_x, current_y;               // m/s, east/north
  float shadow_loss, shadow_header;
  std::int32_t shadow_source;               // -1 = clear air
};

EnvAtBoat env_at_boat(const WindField& wind, const WindTick& tick, std::span<const ShadowSource> snapshot,
                      std::int32_t self, float x, float y);

// §7 outlines for drawing, world metres: the blanket's two edges |η| = W(ξ) for ξ in [−reach_up·Lb, Lb] and
// the backwind's two edges |η_t| = turb_width + ξ_t·turb_spread for ξ_t in [0, Lt] (empty when the source has
// no backwind). Each edge has `samples` points; left edge first, then the right edge.
struct ShadowZones {
  std::vector<Vec2> blanket_left, blanket_right;
  std::vector<Vec2> backwind_left, backwind_right;
  float Lb = 0.0f, Lt = 0.0f;
};

ShadowZones shadow_zones(const ShadowSource& B, std::uint32_t samples = 16);

// §4 building blocks, exposed for tests and tools.
float shadow_blanket_length(const ShadowClass& c, float aws);  // Lb
float shadow_p_long(const WindShadowParams& p, float s);
float shadow_p_lat(float q);

}  // namespace wm
