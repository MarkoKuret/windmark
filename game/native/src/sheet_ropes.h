// SheetRopes: the running sheets of docs/specs/sail_visuals.md §11.3 for one mesh surface (a boat's headsail lines or
// its flying-sail lines): each line a rope tube from a moving start (the placed clew or tack) through an optional
// waypoint to a fixed anchor (the lead block or the sprit end), then the lead run to the winch and the fixed turns on
// the drum and the tail; every run hangs as a parabola along gravity with a sag from its tension, swings and whips as
// the sail flogs, and never dips below the class's deck height field. Written straight into the mesh surface.
// Presentation only. game/scripts/sheet_ropes_ref.gd is the GDScript reference with the same calls (tests compare
// the two); keep them in step. `route` lays a flying sail's line outside the sails, the boom and the rail (the taut
// string of §11.3 "Outside route"); `build_deck` builds the class's deck height field from its meshes (§11.3 "Deck").
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace windmark_godot {

class SheetRopes : public godot::RefCounted {
  GDCLASS(SheetRopes, godot::RefCounted)

 public:
  // per line, in `drive` (update): shown, free-run sag, lead-run sag (depth over span), swing angle (rad), whip (of
  // the span), phase (rad)
  static constexpr int DRIVE = 6;
  // the most waypoints a line's free run takes (`ways` in update: ways.size() / line count slots per line, NaN unused)
  static constexpr int MAX_WAYS = 16;

  bool configure(const godot::Dictionary& params);
  void update(const godot::PackedVector3Array& starts, const godot::PackedVector3Array& ways,
              const godot::PackedFloat32Array& drive, const godot::Vector3& gravity);

  int64_t get_line_count() const { return static_cast<int64_t>(lines_.size()); }
  int64_t get_vertex_count() const { return nv_; }
  godot::PackedInt32Array indices() const;
  godot::PackedVector3Array positions() const;
  godot::PackedVector3Array normals() const;
  // per vertex x, y, z, sign (Mesh.ARRAY_TANGENT): along the rope, binormal = sign * cross(normal, tangent)
  godot::PackedFloat32Array tangents() const;
  godot::PackedVector2Array uvs() const;
  // the centreline of a line (its rings), for the tests
  godot::PackedVector3Array centre(int64_t line) const;
  // the deck height (model up) at (x, z), -1e9 off the deck
  double deck_height(double x, double z) const;
  // §11.3 "Outside route": the waypoints of the taut string from `a` to `b` round the obstacles on side `side`
  // (sgn x of the side), about the pivot `pivot`; `obstacles` = [PackedVector3Array points, float margin, ...];
  // `spacing` the ring spacing of the run (the corner allowance); at most `max_ways` waypoints
  godot::PackedVector3Array route(const godot::Vector3& a, const godot::Vector3& b, const godot::Vector3& pivot,
                                  double side, const godot::Array& obstacles, double spacing, int64_t max_ways) const;
  // §11.3 "Deck": the deck height field from `surfaces` = [{positions, indices, cap}] in model axes (cap < 0: deck,
  // else a fitting counted where it stands at most `cap` above the deck), on a grid of `cell`, the skirt `skirt`
  // cells out over the hull side, widened by `dilate` cells. {heights, origin, cell, nx, nz, max, edge_lo, edge_hi}
  godot::Dictionary build_deck(const godot::Array& surfaces, double cell, int64_t skirt, int64_t dilate) const;

  bool attach_mesh(const godot::RID& mesh, int64_t surface);
  godot::PackedByteArray vertex_bytes();
  godot::PackedByteArray attribute_bytes();
  void write_mesh();

 protected:
  static void _bind_methods();

 private:
  struct Line {
    float radius = 0.005f;
    int free_rings = 16, lead_rings = 0;
    godot::Vector3 anchor;
    std::vector<godot::Vector3> fixed;  // the drum entry first, then the turns and the tail
    int first_ring = 0, rings = 0;      // into the ring arrays
  };
  float deck_at(float x, float z) const;
  void drape(godot::Vector3* r, int n, float radius) const;
  void encode();

  int sides_ = 6;
  float tile_ = 0.05f;
  std::vector<Line> lines_;
  int nr_ = 0, nv_ = 0;
  std::vector<godot::Vector3> ring_;  // centreline per ring
  std::vector<float> ring_len_;       // length along the line per ring
  std::vector<godot::Vector3> pos_, nrm_, tan_;  // tangent along the rope (+u); the binormal (+v) round it
  std::vector<float> uv_;  // u, v per vertex
  std::vector<int32_t> idx_;

  std::vector<float> deck_;
  float dx0_ = 0.0f, dz0_ = 0.0f, dcell_ = 0.05f;
  int dnx_ = 0, dnz_ = 0;
  float dmax_ = -1.0e9f;  // the field's highest point (a span above it needs no drape)
  std::vector<godot::Vector3> pts_;  // the free run's polyline (scratch)
  std::vector<float> cum_;

  godot::RID mesh_;
  int64_t surface_ = 0;
  godot::PackedByteArray vbytes_, abytes_;
  int64_t noff_ = 0, nstride_ = 0, astride_ = 0, uvoff_ = 0;
};

}  // namespace windmark_godot
