// SailShape: the per-vertex sail shapes of docs/specs/sail_visuals.md (§3 to §9) for one sail: fill, camber,
// twist, flutter, backing, hoist and drop, the flying spinnaker shapes, the placement about the boom, the luff, the
// sprit or the pole, and both cloth layers with their normals, written straight into the sail's grid-order mesh.
// Presentation only: nothing here touches the core. game/scripts/sail_shape_ref.gd is the GDScript reference with
// the same calls (tests compare the two); keep them in step.
#pragma once

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace windmark_godot {

class SailShape : public godot::RefCounted {
  GDCLASS(SailShape, godot::RefCounted)

 public:
  enum Kind { MAIN = 0, HEADSAIL = 1, ASYM = 2, SYM = 3 };
  enum Mode { BOOM = 0, LUFF = 1, SPRIT = 2, POLE = 3 };

  bool configure(const godot::PackedVector3Array& rest_mid, int64_t rows, int64_t cols,
                 const godot::Dictionary& params);
  void advance(double dt, double aws, double awa, bool backed);
  // §7.4: the other sails this (flying) sail keeps clear of, as last placed; set before each update
  void set_obstacles(const godot::Array& obstacles);
  double get_ease() const { return ease_; }
  // §7.6: the working lead block on the side of beta, the flying shape's share of the last update, and the clew
  // the sheet leaves from (as placed, before the clearance push)
  godot::Vector3 working_lead(double beta) const;
  double sheet_weight() const { return fa_; }
  godot::Vector3 sheet_clew() const { return clew0_; }
  void update(int64_t phase, double progress, double beta, double gamma, double luff_shiver, double awa,
              double aws);

  double get_phase() const { return phi_; }
  void set_phase(double v) { phi_ = static_cast<float>(v); }
  double get_backed_factor() const { return s_b_; }
  void set_backed_factor(double v) { s_b_ = static_cast<float>(v); }
  double get_twist_side() const { return tl_; }
  // §6.5 a lofted kite: the turn about the luff of the last update (before the ease)
  double get_turn() const { return turn_; }
  double get_tack_rise() const { return tack_up_; }
  bool is_loft() const { return loft_; }
  void set_twist_side(double v) {
    tl_ = static_cast<float>(v);
    tl_set_ = true;
  }

  godot::Dictionary frame() const;
  godot::PackedVector3Array local_shape() const;
  godot::PackedVector3Array mid() const;
  // the placed mid-surface at the given grid indices (the drawn shadow's outline, BoatShadows.sail_indices)
  godot::PackedVector3Array mid_points(const godot::PackedInt32Array& idx) const;
  godot::PackedVector3Array positions() const;
  godot::PackedVector3Array normals() const;

  bool attach_mesh(const godot::RID& mesh);
  godot::PackedByteArray vertex_bytes();
  void write_mesh();

  static double fill(double v, double g, double k);

 protected:
  static void _bind_methods();

 private:
  godot::Vector3 main_shape(int k, float d_cam, float amp, float shiver) const;
  float head_n(int i, float u, float a, float d_cam, float amp, float shiver, float us) const;
  godot::Vector3 halyard(int k, float p, float d_cam, float amp, float shiver) const;
  godot::Vector3 furl(int k, float p, float d_cam, float amp, float shiver) const;
  godot::Vector3 fly(int k, int i, const godot::Vector3& w, float shiver) const;
  godot::Vector3 hoist(int k, float c, const godot::Vector3& f) const;
  godot::Vector3 drop(int k, float c, const godot::Vector3& f) const;
  // rows 0 .. rows_to - 1 (all with -1)
  void locals(int64_t phase, bool up_shape, float p, float d_cam, float amp, float shiver, const godot::Vector3& w,
              int rows_to = -1);
  // §7.7 the clew set by its sheet
  void clew_rows(float kd, float kl);
  godot::Vector3 fly_at(int k, const godot::Vector3& w, float kd, float kl) const;
  void clew_corner(float kd, float kl, float beta, float base, const godot::Vector3& piv, const godot::Vector3& ax,
                   const godot::Transform3D& s_t, const godot::Vector3& w, godot::Vector3& b,
                   godot::Vector3& s) const;
  void clew_set(float beta, float base, const godot::Vector3& piv, const godot::Vector3& ax,
                const godot::Transform3D& s_t, const godot::Vector3& w);
  void layers(const godot::Vector3& np);
  // §6.5 the lofted kite's update, its clearance over the margin (and the vertex it is at) and its turn off the
  // obstacles
  void update_loft(int64_t phase, float progress, float beta, float gamma, float shiver, float awa, float aws);
  void loft_clear(const std::vector<godot::Vector3>& pts, const godot::Vector3& hd, const godot::Vector3& lee,
                  const std::vector<int>& idx, std::vector<float>& out) const;
  float stay_x(const godot::Vector3& pt) const;
  float loft_ease(float beta, float awa, const godot::Transform3D& s_t, const godot::Vector3& piv,
                  const godot::Vector3& ax, float th, const godot::Vector3& hd);
  // §7.4 clearance
  struct Section {
    const SailShape* s = nullptr;
    std::vector<float> z;  // mean row heights
    godot::Vector3 f;      // foot normal on the bow-facing side
    std::vector<float> box;  // per row pair: horizontal bounds (fwd min, max, port min, max)
  };
  // INFINITY when p is more than `reach` from the section's bounds
  float clear_x(const Section& o, const godot::Vector3& p, float reach, godot::Vector3& g) const;
  float mast_x(const godot::Vector3& p, const godot::Vector3& lee, godot::Vector3& g) const;
  float margin_at(const godot::Vector3& p, const godot::Vector3& hd) const;
  void sections(const godot::Transform3D& s_t, const godot::Vector3& piv, const godot::Vector3& ax, float base);
  float ease(float beta, const godot::Transform3D& s_t, const godot::Vector3& piv, const godot::Vector3& ax,
             float base, const godot::Vector3& hd) const;
  void spread(std::vector<float>& d) const;
  void push(float awa, const godot::Vector3& hd);
  void stay();
  void shift();
  void encode();

  int rows_ = 0, cols_ = 0, n_ = 0;
  int kind_ = MAIN, mode_ = BOOM;
  bool furling_ = false;
  float fill_gain_ = 0.6f, fill_curve_ = 4.0f, flutter_amp_ = 0.15f, flutter_rate_ = 0.6f;
  float flutter_rate_max_ = 10.0f, twist_top_ = 0.0f, camber_ = 0.26f, cam_cap_ = 0.0f, tack_line_max_ = 0.0f;
  float furl_radius_ = 0.05f;
  float clearance_ = 0.0f, ease_ = 0.0f;
  bool has_mast_head_ = false;
  bool has_stay_ = false;  // §7.4 a flying sail on a pole: the forestay (tack fitting, hounds), half width, margin
  godot::Vector3 stay0_, stay1_;
  float stay_w_ = 0.0f, stay_c_ = 0.0f;
  // §4.1 the kite set parameters (defaults by kind in configure); the ones read per update
  float belly_aft_ = 0.5f, belly_up_ = 0.5f, twist_exp_ = 1.5f, twist_lo_ = 0.0f, twist_hi_ = 0.0f, twist_run_ = 0.0f;
  float foot_sag_ = 0.0f, foot_sag_h_ = 0.35f, head_drop_ = 0.0f, clew_lift_ = 0.0f, clew_out_ = 0.0f;
  float forward_ = 0.0f, tack_rise_ = 0.0f, stay_head_ = 0.3f, stay_luff_ = 0.5f, stay_leech_ = 0.3f;
  // §6.5 a lofted kite: its measured AWAs (rising), the shapes (n_ per AWA, grid order), depth scale and trim
  bool loft_ = false;
  std::vector<float> loft_awa_;
  std::vector<godot::Vector3> loft_pts_, fly_, lq_, lp_;
  std::vector<int> lidx_;
  std::vector<float> lx_;
  float loft_depth_ = 1.0f, loft_trim_ = 0.0f, turn_ = 0.0f, tack_up_ = 0.0f;
  std::vector<float> grow_;                // per row: the girth scale
  std::vector<float> hold_, rise_;         // per vertex: the corners' hold of `forward`, the share of `tack_rise`
  godot::Vector3 mast_head_;
  std::vector<godot::Ref<SailShape>> obs_;
  std::vector<Section> secs_;
  godot::Vector3 fwd_{0, 0, 1}, port_{1, 0, 0}, up_{0, 1, 0};
  godot::Vector3 boom_pivot_, boom_axis_{0, 1, 0}, mast_step_, mast_axis_{0, 1, 0};

  godot::Vector3 tack_, head_, lh_{0, 1, 0}, ah_{0, 0, -1}, nh_{1, 0, 0};
  float sa_ = 1.0f, sl_ = 1.0f, a_min_ = 0.0f, l_min_ = 0.0f, r_h_ = 1.0f, kappa_ = 0.0f;

  std::vector<float> a_, l_, u_, h_, uc_;  // per vertex
  std::vector<float> c_, amid_, hrow_;     // per row
  std::vector<float> u0row_, ulrow_;       // per row: u of the luff and leech vertex (§6.2)
  float jcam_ = 0.0f;
  bool has_lead_ = false;                  // §7.6 the working lead block (starboard, model axes)
  godot::Vector3 sheet_lead_;
  std::vector<float> tack_d_;              // §7.3 rest distance of each vertex from the tack (the tack pin)
  godot::Vector3 tack_at_;                 // §7.4 the placed tack, where the margin fades out as at the head
  float fa_ = 0.0f;
  godot::Vector3 clew0_;                   // §7.6 the clew as placed, before the clearance push                      // §6.2 the jib's signed camber over chord, per update
  std::vector<float> drow_, srow_;         // per row, per update: camber over chord and chord shortening
  std::vector<float> prow_, trow_;         // per row: the camber's height profile (§6.3, §6.4), the twist (§7, per update)
  std::vector<float> crow_, d0row_;        // per row: §7.7 the clew set's share; the camber before it (per update)
  float kd_ = 0.0f, kl_ = 0.0f;            // §7.7 the draw-in and draw-down of the last update
  std::vector<float> prof_;                // per vertex: the chordwise camber profile (§6.3, §6.4)
  // §7.4 rest distances from vertex k to its neighbour along the row (k + 1), up the column (k + cols), and the
  // two diagonals up (k + cols + 1, k + cols - 1); scratch per vertex for the push
  std::vector<float> ec_, er_, e1_, e2_;
  std::vector<float> cp_, px_, pd_;
  std::vector<godot::Vector3> pg_;

  float phi_ = 0.0f, s_b_ = 1.0f, tl_ = 0.0f;
  bool tl_set_ = false;

  std::vector<godot::Vector3> loc_, mid_, pos_, nrm_;

  godot::RID mesh_;
  godot::PackedByteArray bytes_;
  int64_t noff_ = 0, nstride_ = 0;
};

}  // namespace windmark_godot
