// What the boat step reads from the environment (boat.md §2), kept as a small interface so the boat does not
// depend on how the wind field, the wind shadows and the sea are computed (wind.md, wind_shadow.md, sea.md).
#pragma once

namespace wm {

// The sea surface height at time t_n (sea.md §4): eta at a world point (x east, y north, m).
class SeaSurface {
 public:
  virtual ~SeaSurface() = default;
  virtual float sea_height(float x, float y) const = 0;
};

// Environment at the boat for one tick (boat.md §2, tick step 5).
struct BoatEnv {
  float wind_speed = 0.0f;        // m/s over the ground, after puffs and the other boats' shadows
  float wind_from = 0.0f;         // compass rad, direction the wind comes from
  float wind_speed_clean = 0.0f;  // the same before shadows (HUD and AI only)
  float current_x = 0.0f;         // water velocity over the ground, m/s east
  float current_y = 0.0f;         // m/s north
  const SeaSurface* sea = nullptr;  // nullptr = flat water
};

}  // namespace wm
