// The per-frame geometry of a drawn boat shadow on the water (docs/specs/water_render.md §4.7), natively:
//   BoatShadowShape  a boat's hull, mast and sails projected along the sun onto the plane at its heave, as convex
//                    polygons (edge lines for the shader), the hull footprint, and the rectangle of the grid
// Presentation only: nothing here touches the core. The GDScript reference with the same maths is
// game/scenes/sea/boat_shadows.gd (BoatShadows.build, BoatShadows.pack_row); BoatShadows uses it when the extension
// is missing, and game/tests/boat_shadow_test.gd compares the two. Keep them in step.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <cstdint>
#include <vector>

namespace windmark_godot {

class BoatShadowShape : public godot::RefCounted {
  GDCLASS(BoatShadowShape, godot::RefCounted)

 public:
  static constexpr int MAX_POLYS = 8;
  static constexpr int MAX_PLANES = 96;
  static constexpr int MAX_EXCL = 40;
  // the boat's row of the shadow data texture (boat_shadow_common.gdshaderinc), in RGBA32F texels
  static constexpr int ROW_POLY = 3;
  static constexpr int ROW_BOUND = 11;
  static constexpr int ROW_PLANE = 19;
  static constexpr int ROW_EXCL = 115;
  static constexpr int ROW_WIDTH = 160;

  // the caster of BoatShadows.caster_from_physics: {hull: PackedVector3Array (body), mast_step, mast_head: Vector3,
  // mast_r: float}
  void configure(const godot::Dictionary& caster);
  // BoatShadows.build without the caster (configured): xform body frame to scene, sun toward the sun (unit), the
  // sails' outline points (scene) and the points per sail. {} when the sun is too low or nothing is configured.
  godot::Dictionary build(const godot::Transform3D& xform, const godot::Vector3& sun,
                          const godot::PackedVector3Array& sails, const godot::PackedInt32Array& sail_counts);
  // the same polygons as the boat's row of the data texture (ROW_WIDTH texels), the fade `strength` in texel 0;
  // empty when nothing is drawn. The grid's rectangle is then last_rect().
  godot::PackedFloat32Array build_row(const godot::Transform3D& xform, const godot::Vector3& sun,
                                      const godot::PackedVector3Array& sails,
                                      const godot::PackedInt32Array& sail_counts, double strength);
  godot::Transform3D last_rect() const { return rect_; }

 protected:
  static void _bind_methods();

 private:
  bool compute(const godot::Transform3D& xform, const godot::Vector3& sun, const godot::PackedVector3Array& sails,
               const godot::PackedInt32Array& sail_counts);
  godot::PackedFloat32Array row(double strength) const;

  std::vector<godot::Vector3> hull_;
  godot::Vector3 mast_step_, mast_head_;
  double mast_r_ = 0.0;
  bool ok_ = false;
  // the last build
  godot::Vector3 origin_, sun_;
  std::vector<godot::Vector4> planes_, poly_, bound_, excl_;
  std::vector<godot::Vector2> corners_;
  std::vector<int32_t> corner_end_;
  godot::Transform3D rect_;
  // scratch
  std::vector<godot::Vector3> hull_w_;
  std::vector<godot::Vector2> p2_, ring_, work_, fring_;
};

}  // namespace windmark_godot
