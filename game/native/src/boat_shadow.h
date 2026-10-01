// The per-frame geometry of a drawn boat shadow on the water (docs/specs/water_render.md §4.7), natively:
//   BoatShadowShape  a boat's hull, mast and sails projected along the sun onto the plane at its heave, as convex
//                    polygons (edge lines for the shader), the hull footprint, and the rectangle of the grid
// Presentation only: nothing here touches the core. The GDScript reference with the same maths is
// game/scenes/sea/boat_shadows.gd (BoatShadows.build); BoatShadows uses it when the extension is missing, and
// game/tests/boat_shadow_test.gd compares the two. Keep them in step.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace windmark_godot {

class BoatShadowShape : public godot::RefCounted {
  GDCLASS(BoatShadowShape, godot::RefCounted)

 public:
  static constexpr int MAX_POLYS = 8;
  static constexpr int MAX_PLANES = 96;
  static constexpr int MAX_EXCL = 40;

  // the caster of BoatShadows.caster_from_physics: {hull: PackedVector3Array (body), mast_step, mast_head: Vector3,
  // mast_r: float}
  void configure(const godot::Dictionary& caster);
  // BoatShadows.build without the caster (configured): xform body frame to scene, sun toward the sun (unit), the
  // sails' outline points (scene) and the points per sail. {} when the sun is too low or nothing is configured.
  godot::Dictionary build(const godot::Transform3D& xform, const godot::Vector3& sun,
                          const godot::PackedVector3Array& sails, const godot::PackedInt32Array& sail_counts);

 protected:
  static void _bind_methods();

 private:
  std::vector<godot::Vector3> hull_;
  godot::Vector3 mast_step_, mast_head_;
  double mast_r_ = 0.0;
  bool ok_ = false;
  // scratch
  std::vector<godot::Vector2> p2_, ring_, work_;
};

}  // namespace windmark_godot
