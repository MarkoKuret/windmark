// The per-frame work of the wakes, bow waves and mist of docs/specs/water_render.md §5, natively:
//   SeaSampler     the sea height of SeaModel.height (sea.md §7.2, double precision) from the wave components and
//                  the exposure grid, handed over once when they change
//   WakeRibbon     one wake ribbon: rows, spray, and its mesh written in place into a fixed-size surface
//   BowWaveSheets  the two bow wave sheets of a boat, written in place into a fixed-size surface
//   MistCloud      the mist sprites, moved and written into their MultiMesh with one buffer call
// Presentation only: nothing here touches the core. The GDScript references with the same maths are
// game/scenes/sea/wake_ribbon_ref.gd (WakeRibbonRef), bow_wave.gd (BowWave.build_arrays, mist_step, mist_look)
// and sea_model.gd (SeaModel.height); SeaWakes uses them when the extension is missing, and
// game/tests/wakes_native_test.gd compares the two. Keep them in step.
#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <deque>
#include <vector>

namespace windmark_godot {

class SeaSampler : public godot::RefCounted {
  GDCLASS(SeaSampler, godot::RefCounted)

 public:
  // [a (m), kx, ky (cycles per metre), c (cycles), T (ms)] each, as SeaModel.components
  void set_components(const godot::Array& list);
  // SeaModel.exposure: {x0, y0, dx, dy, nx, ny, default, e: PackedFloat32Array}; empty = none
  void set_exposure(const godot::Dictionary& grid);
  double exposure_at(double x, double y) const;
  double height(double x, double y, double t_ms) const;
  int64_t component_count() const { return static_cast<int64_t>(comp_.size()); }

 protected:
  static void _bind_methods();

 private:
  struct Comp {
    double a, kx, ky, c, T;
  };
  std::vector<Comp> comp_;
  bool has_expo_ = false;
  double x0_ = 0, y0_ = 0, dx_ = 1, dy_ = 1, def_ = 1;
  int nx_ = 0, ny_ = 0;
  std::vector<float> e_;
};

// Fixed-size mesh surface written in place: position (float3) in the vertex stream; colour (RGBA8), UV and UV2
// (float2) in the attribute stream; 16-bit indices. Unused index slots are 0 (degenerate triangles).
struct FixedSurface {
  godot::RID mesh;
  int64_t n_vert = 0, n_index = 0;
  int64_t col_off = 0, uv_off = 0, uv2_off = 0, attr_stride = 0;
  godot::PackedByteArray vbytes, abytes, ibytes;
  std::vector<uint16_t> last_idx;  // the indices last uploaded

  // The arrays of an empty surface of n_vert vertices and n_index indices (every index 0).
  static godot::Array blank(int64_t n_vert, int64_t n_index);
  bool attach(const godot::RID& rid, int64_t verts, int64_t indices);
  // Encodes the first n vertices; indices beyond idx.size() are 0. Uploads what changed.
  void write(const std::vector<godot::Vector3>& pos, const std::vector<godot::Vector2>& uv,
             const std::vector<godot::Vector2>& uv2, const std::vector<godot::Color>& col,
             const std::vector<uint16_t>& idx, bool upload_indices);
};

class WakeRibbon : public godot::RefCounted {
  GDCLASS(WakeRibbon, godot::RefCounted)

 public:
  static constexpr int N_ROWS = 180;
  static constexpr int ACROSS = 15;
  static constexpr int MAX_INDEX = (N_ROWS - 1) * (ACROSS - 1) * 6;

  void emit(double t_s, const godot::Vector2& p, double heading, double v, double w0, double ratio, bool visible,
            double dist);
  // edges of the last row at t_s: [port, starboard] (world x, y)
  godot::PackedVector2Array last_edges(double t_s) const;
  // the two spray particles of the last row (WakeRibbonRef.launch_spray)
  void launch_last_spray(double speed, double heel, double z_port, double z_stbd);
  // drops old rows, drifts them with the current (Callable(x, y) -> Vector2, or null) and moves the spray; the
  // spray lands on sea.height(x, y, t_ms)
  void step(double t_s, double dt, const godot::Ref<SeaSampler>& sea, double t_ms, const godot::Variant& current);
  int64_t row_count() const { return static_cast<int64_t>(rows_.size()); }
  // row k (oldest first) as WakeRibbonRef keeps it: {t, p, fwd, v, w0, ratio, visible, dist, spray}
  godot::Dictionary row(int64_t k) const;
  // the reference's compact arrays (WakeRibbonRef.build_arrays)
  godot::Array build_arrays(double t_s);
  godot::Array blank_arrays() const { return FixedSurface::blank(N_ROWS * ACROSS, MAX_INDEX); }
  bool attach_mesh(const godot::RID& mesh);
  // builds at t_s and writes the attached surface in place (and its bounds); false when nothing is drawn
  bool write_mesh(double t_s);
  godot::PackedByteArray vertex_bytes() const { return surf_.vbytes; }
  godot::PackedByteArray attribute_bytes() const { return surf_.abytes; }
  godot::PackedByteArray index_bytes() const { return surf_.ibytes; }

 protected:
  static void _bind_methods();

 private:
  struct Spray {
    godot::Vector3 pos, vel;
    bool landed = false;
  };
  struct Row {
    double t, v, w0, ratio, dist;
    godot::Vector2 p, fwd;
    bool visible;
    int ns = 0;
    Spray spray[2];
  };
  static godot::Vector2 port(const Row& r) { return godot::Vector2(-r.fwd.y, r.fwd.x); }
  static double half_width(const Row& r, double t_s);
  static double alpha(const Row& r, double t_s);
  static godot::Vector2 spray_excess(const Row& r, double t_s);
  void build(double t_s);

  std::deque<Row> rows_;
  std::vector<godot::Vector3> pos_;
  std::vector<godot::Vector2> uv_, uv2_;
  std::vector<godot::Color> col_;
  std::vector<uint16_t> idx_;
  std::vector<godot::Vector2> excess_;
  FixedSurface surf_;
};

class BowWaveSheets : public godot::RefCounted {
  GDCLASS(BowWaveSheets, godot::RefCounted)

 public:
  static constexpr int NS = 14;
  static constexpr int NT = 7;
  static constexpr int N_VERT = 2 * NS * NT;
  static constexpr int N_INDEX = 2 * (NS - 1) * (NT - 1) * 6;

  // BowWave.build_arrays for a boat state (SeaWakes.update_boat keys) and the drivers v, ratio, plunge
  godot::Array build_arrays(const godot::Dictionary& st, double v, double ratio, double plunge);
  godot::Array blank_arrays() const;
  bool attach_mesh(const godot::RID& mesh);
  // false (nothing written) when the wave is not visible
  bool write_mesh(const godot::Dictionary& st, double v, double ratio, double plunge);
  godot::PackedByteArray vertex_bytes() const { return surf_.vbytes; }
  godot::PackedByteArray attribute_bytes() const { return surf_.abytes; }

 protected:
  static void _bind_methods();

 private:
  bool build(const godot::Dictionary& st, double v, double ratio, double plunge);
  std::vector<godot::Vector3> pos_;
  std::vector<godot::Vector2> uv_, uv2_;
  std::vector<godot::Color> col_;
  std::vector<uint16_t> idx_;
  FixedSurface surf_;
};

class MistCloud : public godot::RefCounted {
  GDCLASS(MistCloud, godot::RefCounted)

 public:
  static constexpr int MAX = 256;
  static constexpr int STRIDE = 16;  // 3x4 transform and custom data

  // a sprite as BowWave.mist_sprite makes it: {pos, vel (ENU), age, life, s0, s1, seed, a}
  void add(const godot::Dictionary& m);
  int64_t count() const { return static_cast<int64_t>(m_.size()); }
  // BowWave.mist_step on every sprite, dropping the lived-out ones
  void step(double dt);
  // the sprites as dictionaries (tests, previews)
  godot::Array sprites() const;
  // the MultiMesh buffer (MAX instances, 3D transforms with custom data), the live ones first
  godot::PackedFloat32Array buffer();
  // writes the buffer into a MultiMesh of MAX instances and sets its visible instance count
  void write_multimesh(const godot::RID& mm);

 protected:
  static void _bind_methods();

 private:
  struct Sprite {
    godot::Vector3 pos, vel;
    double age, life, s0, s1, seed;
    double a, g, drag, k;  // a burst's droplet sheet: alpha scale, gravity, drag, look (1); mist: 1, MIST_*, 0
  };
  std::vector<Sprite> m_;
  godot::PackedFloat32Array buf_;
  size_t last_n_ = 0;
};

}  // namespace windmark_godot
