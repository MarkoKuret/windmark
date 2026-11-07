// SailShape: docs/specs/sail_visuals.md §3 to §9. See sail_shape.h.
#include "sail_shape.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

namespace windmark_godot {

namespace {

constexpr float PI_F = 3.14159265358979f;
constexpr float TAU_F = 6.28318530717959f;
constexpr float KNOT = 1852.0f / 3600.0f;
constexpr float C_HOOK = 0.0369260386f;
// §6.2 the jib's and genoa's camber k_j, its fill scale b_j and the largest of x (1 - x) (2 - x)
constexpr float JIB_CAMBER = 0.135f;
constexpr float JIB_FILL = 0.15f;
constexpr float JIB_PROFILE_MAX = 0.3849002f;
// §7.3 the tack pin reaches this share of the luff from the tack
constexpr float TACK_PIN = 0.25f;
// §7.4 the last segment of an obstacle section runs on past its leech by this many clearances
constexpr float RUN_ON = 6.0f;
constexpr float TAU_SMOOTH = 0.25f;
constexpr float DT_MAX = 0.1f;
// §4, §7.4 clearance constants: push slope, ease threshold (in clearances), ease cap (rad)
constexpr float PUSH_SLOPE = 0.3f;
constexpr float PUSH_EASE = 2.0f;
constexpr float EASE_MAX = 0.35f;
// §7.4 a flying sail on a pole flies forward of the forestay: margin c_s and the stay's half width (of the
// foretriangle base), the top share of the height the shift fades out over, the chord share it is taken in full
// from (none at the luff) and the share it loses toward the leech
constexpr float STAY_CLEAR = 0.25f;
constexpr float STAY_WIDTH = 0.6f;
constexpr float STAY_HEAD = 0.3f;
constexpr float STAY_LUFF = 0.5f;
constexpr float STAY_LEECH = 0.3f;
// §6.4 the belly of a symmetric spinnaker's foot sags down by this share of its depth, fading out over the lower
// SYM_SAG_H of the height
constexpr float SYM_SAG = 0.35f;
constexpr float SYM_SAG_H = 0.35f;
// §7.7 the clew set: corner reach (grid steps), fade height (of Sl), bounds of the draw-in and draw-down, the
// difference step and the Newton steps of the solve
constexpr int CLEW_REACH = 2;
constexpr float CLEW_H = 0.3f;
constexpr float CLEW_KD_LO = -0.1f, CLEW_KD_HI = 0.25f;
constexpr float CLEW_KL_LO = -0.1f, CLEW_KL_HI = 0.3f;
constexpr float CLEW_STEP = 0.01f;
constexpr int CLEW_ITER = 2;
constexpr float CLEW_FADE0 = 75.0f * PI_F / 180.0f, CLEW_FADE1 = 105.0f * PI_F / 180.0f;  // round the bow
constexpr float CLEW_AWA0 = 45.0f * PI_F / 180.0f, CLEW_AWA1 = 65.0f * PI_F / 180.0f;     // the lowest AWA
// §4.1 the luff and leech curl reach this share of the chord in from the edge; `forward` holds the corners over
// this share of Sl; `tack_rise` fades out over this share of Sl from the tack
constexpr float CURL_BAND = 0.25f;
constexpr float HOLD = 0.35f;
constexpr float TACK_REACH = 0.5f;
constexpr double DEG = 3.14159265358979323846 / 180.0;
// §6.5 the lofted belly crosses to the other side as sin(beta + awa) passes +-LOFT_SIDE; the whole kite's turn off
// the main, the jib and the mast: at most LOFT_EASE_MAX (rad; LOFT_STAY_MAX for a kite on a pole, which also keeps
// off the forestay, a last resort), in at most LOFT_EASE_STEPS steps
constexpr float LOFT_SIDE = 0.1f;
constexpr float LOFT_EASE_MAX = 0.5f;
constexpr float LOFT_STAY_MAX = 1.8f;
// §6.5 the drawn whole-kite turn moves at most this fast (rad/s) from the last update's
constexpr float LOFT_EASE_RATE = 0.6f;
// §6.5 ... and its belly crosses to the other side at most this fast (per second; 2: a full crossing in 1 s)
constexpr float LOFT_SIDE_RATE = 2.0f;
// §6.5 a flogging kite: its side held to leeward forward of the beam (faded out from |AWA| LOFT_FLOG_UP0 over
// LOFT_FLOG_UP1, rad), its luff collapsing over this share of the chord
constexpr float LOFT_FLOG_UP0 = 70.0f * 3.14159265f / 180.0f;
constexpr float LOFT_FLOG_UP1 = 40.0f * 3.14159265f / 180.0f;
constexpr float LOFT_FLOG_LUFF = 0.35f;
// §6.5 a lofted kite on a pole keeps this share of the foretriangle base ahead of the forestay (the hard rule)
constexpr float LOFT_STAY_CLEAR = 0.04f;
constexpr int LOFT_EASE_STEPS = 12;
// §6.5 after its first step, the turn's solve looks only at vertices this many clearances near the worst
constexpr float LOFT_NEAR = 2.0f;
// §6.5 the turn keeps this many margins (horizontal, §7.4), so the true distance up by the head, where the sails
// lean, keeps one
constexpr float LOFT_MARGIN = 1.2f;
// §6.5 |beta| over which the trim and the turn off the obstacles fade in from the centreline, and from where and over
// how much they fade out round the bow (rad)
constexpr float LOFT_FADE0 = 0.1f, LOFT_FADE1 = 1.7453293f, LOFT_FADE2 = 1.0471976f;

inline float sgn(float x) { return x >= 0.0f ? 1.0f : -1.0f; }
inline float wrap_pi(float x) {
  float r = std::fmod(x + PI_F, TAU_F);
  if (r < 0.0f) r += TAU_F;
  return r - PI_F;
}
inline float clampf(float x, float a, float b) { return std::min(std::max(x, a), b); }
inline float smooth01(float x) {
  const float t = clampf(x, 0.0f, 1.0f);
  return t * t * (3.0f - 2.0f * t);
}

// Rotation by `angle` about the line through `p` along the unit `axis` (right-handed).
inline Transform3D about(const Vector3& p, const Vector3& axis, float angle) {
  Basis b(axis, angle);
  return Transform3D(b, p - b.xform(p));
}

float getf(const Dictionary& d, const char* key, float def) {
  return d.has(key) ? static_cast<float>(static_cast<double>(d[key])) : def;
}

double getd(const Dictionary& d, const char* key, double def) {
  return d.has(key) ? static_cast<double>(d[key]) : def;
}

Vector3 getv(const Dictionary& d, const char* key, const Vector3& def) {
  return d.has(key) ? static_cast<Vector3>(d[key]) : def;
}

// Godot's octahedral normal encoding (Vector3::octahedron_encode) as the mesh stores it: two 16-bit units.
inline void oct16(const Vector3& v, uint16_t out[2]) {
  Vector3 n = v / (std::fabs(v.x) + std::fabs(v.y) + std::fabs(v.z));
  float ox, oy;
  if (n.z >= 0.0f) {
    ox = n.x;
    oy = n.y;
  } else {
    ox = (1.0f - std::fabs(n.y)) * (n.x >= 0.0f ? 1.0f : -1.0f);
    oy = (1.0f - std::fabs(n.x)) * (n.y >= 0.0f ? 1.0f : -1.0f);
  }
  ox = ox * 0.5f + 0.5f;
  oy = oy * 0.5f + 0.5f;
  out[0] = static_cast<uint16_t>(clampf(ox * 65535.0f, 0.0f, 65535.0f));
  out[1] = static_cast<uint16_t>(clampf(oy * 65535.0f, 0.0f, 65535.0f));
}

PackedVector3Array to_packed(const std::vector<Vector3>& v) {
  PackedVector3Array out;
  out.resize(static_cast<int64_t>(v.size()));
  if (!v.empty()) std::memcpy(out.ptrw(), v.data(), v.size() * sizeof(Vector3));
  return out;
}

}  // namespace

double SailShape::fill(double v, double g, double k) {
  const double x = std::fabs(v);
  const double m = std::min(std::max(std::pow(x, 0.75 / k) * std::exp(-0.01 / (x + 1e-6)), 0.0), 1.0);
  return (v >= 0.0 ? 1.0 : -1.0) * 0.75 * g * m;
}

bool SailShape::configure(const PackedVector3Array& rest, int64_t rows, int64_t cols, const Dictionary& p) {
  if (rows < 2 || cols < 2 || rest.size() != rows * cols) return false;
  rows_ = static_cast<int>(rows);
  cols_ = static_cast<int>(cols);
  n_ = rows_ * cols_;
  kind_ = p.has("kind") ? static_cast<int>(static_cast<int64_t>(p["kind"])) : MAIN;
  mode_ = p.has("mode") ? static_cast<int>(static_cast<int64_t>(p["mode"])) : BOOM;
  furling_ = p.has("furling") ? static_cast<bool>(p["furling"]) : false;
  fill_gain_ = getf(p, "fill_gain", fill_gain_);
  fill_curve_ = getf(p, "fill_curve", fill_curve_);
  flutter_amp_ = getf(p, "flutter_amp", flutter_amp_);
  flutter_rate_ = getf(p, "flutter_rate", flutter_rate_);
  flutter_rate_max_ = getf(p, "flutter_rate_max", flutter_rate_max_);
  twist_top_ = getf(p, "twist_top", twist_top_);
  // §4 camber: flying sails always; a headsail only with the key (the code zero cap of §6.2). `depth` is ignored.
  camber_ = getf(p, "camber", 0.26f);
  cam_cap_ = (kind_ == HEADSAIL && p.has("camber")) ? camber_ : 0.0f;
  tack_line_max_ = getf(p, "tack_line_max", tack_line_max_);
  fwd_ = getv(p, "fwd", fwd_);
  port_ = getv(p, "port", port_);
  up_ = getv(p, "up", up_);
  boom_pivot_ = getv(p, "boom_pivot", boom_pivot_);
  boom_axis_ = getv(p, "boom_axis", up_).normalized();
  mast_step_ = getv(p, "mast_step", mast_step_);
  mast_axis_ = getv(p, "mast_axis", up_).normalized();
  phi_ = getf(p, "phi", 0.0f);
  clearance_ = getf(p, "clearance", 0.0f);
  has_lead_ = p.has("sheet_lead");
  sheet_lead_ = getv(p, "sheet_lead", Vector3());
  has_mast_head_ = p.has("mast_head");
  mast_head_ = getv(p, "mast_head", mast_step_ + mast_axis_);
  // §4.1 the kite set parameters: the keys given over the defaults of the kind (none on a main or headsail)
  const bool kite = kind_ == ASYM || kind_ == SYM;
  const bool asym = kind_ == ASYM;
  auto kp = [&](const char* key, double def) { return kite ? getd(p, key, def) : def; };
  const double peak = kp("depth_peak_h", asym ? 0.3 : 0.5), foot = kp("depth_foot", asym ? 0.8 : 1.0);
  const double headd = kp("depth_head", asym ? 0.45 : 0.7);
  const double dlow = kp("draft_low", asym ? std::pow(0.5, 1.0 / 0.8) : 0.5);
  const double dhead = kp("draft_head", asym ? std::pow(0.5, 1.0 / 1.4) : 0.5);
  const double dfrom = kp("draft_from_h", 0.55);
  const double lc = kp("luff_curl", 0.0), rc = kp("leech_curl", 0.0);
  const double gf = kp("girth_foot", 1.0), gm = kp("girth_mid", 1.0), gh = kp("girth_head", 1.0);
  const float clew_h = static_cast<float>(kp("clew_h", CLEW_H));
  belly_aft_ = static_cast<float>(kp("belly_aft", 0.5));
  belly_up_ = static_cast<float>(kp("belly_up", 0.5));
  twist_exp_ = static_cast<float>(kp("twist_exp", asym ? 2.5 : 1.5));
  twist_lo_ = static_cast<float>(kp("twist_awa_lo", 60.0 * DEG));
  twist_hi_ = static_cast<float>(kp("twist_awa_hi", 130.0 * DEG));
  twist_run_ = static_cast<float>(kp("twist_run", 25.0 * DEG));
  foot_sag_ = static_cast<float>(kp("foot_sag", kind_ == SYM ? SYM_SAG : 0.0));
  foot_sag_h_ = static_cast<float>(kp("foot_sag_h", SYM_SAG_H));
  head_drop_ = static_cast<float>(kp("head_drop", 0.0));
  clew_lift_ = static_cast<float>(kp("clew_lift", 0.0));
  clew_out_ = static_cast<float>(kp("clew_out", 0.0));
  forward_ = static_cast<float>(kp("forward", 0.0));
  tack_rise_ = static_cast<float>(kp("tack_rise", 0.0));
  stay_head_ = static_cast<float>(kp("stay_head", STAY_HEAD));
  stay_luff_ = static_cast<float>(kp("stay_luff", STAY_LUFF));
  stay_leech_ = static_cast<float>(kp("stay_leech", STAY_LEECH));
  loft_depth_ = static_cast<float>(kp("loft_depth", 1.0));
  loft_trim_ = static_cast<float>(kp("loft_trim", 0.0));
  // §6.5 the lofted shapes, when the set block picks the loft and the sidecar has them
  loft_ = false;
  turn_ = 0.0f;
  loft_awa_.clear();
  loft_pts_.clear();
  if (kite && p.has("model") && String(p["model"]) == String("loft") && p.has("loft_awa") && p.has("loft_shapes")) {
    const PackedFloat32Array la = p["loft_awa"];
    const PackedVector3Array ls = p["loft_shapes"];
    if (la.size() >= 1 && ls.size() == la.size() * rows * cols) {
      loft_awa_.assign(la.ptr(), la.ptr() + la.size());
      loft_pts_.assign(ls.ptr(), ls.ptr() + ls.size());
      loft_ = true;
    }
  }
  has_stay_ = mode_ == POLE && clearance_ > 0.0f && p.has("forestay_tack") && p.has("hounds");
  if (has_stay_) {
    stay0_ = getv(p, "forestay_tack", Vector3());
    stay1_ = getv(p, "hounds", Vector3());
    const Vector3 dm = stay0_ - mast_step_;
    const float jb = (dm - mast_axis_ * dm.dot(mast_axis_)).length();  // the foretriangle base
    stay_w_ = static_cast<float>(kp("stay_width", STAY_WIDTH)) * jb;
    stay_c_ = std::max(static_cast<float>(kp("stay_clear", STAY_CLEAR)) * jb, clearance_);
  }
  // §6.5 a lofted kite, on a pole or a sprit, keeps ahead of the forestay (the hard rule)
  loft_stay_ = loft_ && clearance_ > 0.0f && p.has("forestay_tack") && p.has("hounds");
  if (loft_stay_) {
    stay0_ = getv(p, "forestay_tack", Vector3());
    stay1_ = getv(p, "hounds", Vector3());
    const Vector3 dm = stay0_ - mast_step_;
    loft_stay_c_ = LOFT_STAY_CLEAR * (dm - mast_axis_ * dm.dot(mast_axis_)).length();
  }
  obs_.clear();
  ease_ = 0.0f;
  turn_set_ = false;
  turn_prev_ = 0.0f;
  side_prev_ = 1.0f;

  const Vector3* r = rest.ptr();
  tack_ = r[0];
  head_ = r[(rows_ - 1) * cols_];
  lh_ = (head_ - tack_).normalized();
  nh_ = port_.normalized();
  ah_ = lh_.cross(nh_).normalized();
  a_.assign(n_, 0.0f);
  l_.assign(n_, 0.0f);
  u_.assign(n_, 0.0f);
  h_.assign(n_, 0.0f);
  uc_.assign(n_, 0.0f);
  float amin = INFINITY, amax = -INFINITY, lmin = INFINITY, lmax = -INFINITY;
  for (int k = 0; k < n_; ++k) {
    const Vector3 d = r[k] - tack_;
    a_[k] = d.dot(ah_);
    l_[k] = d.dot(lh_);
    amin = std::min(amin, a_[k]);
    amax = std::max(amax, a_[k]);
    lmin = std::min(lmin, l_[k]);
    lmax = std::max(lmax, l_[k]);
  }
  a_min_ = amin;
  l_min_ = lmin;
  sa_ = std::max(amax - amin, 1e-3f);
  sl_ = std::max(lmax - lmin, 1e-3f);
  c_.assign(rows_, 0.0f);
  amid_.assign(rows_, 0.0f);
  hrow_.assign(rows_, 0.0f);
  u0row_.assign(rows_, 0.0f);
  ulrow_.assign(rows_, 0.0f);
  drow_.assign(rows_, 0.0f);
  srow_.assign(rows_, 1.0f);
  prow_.assign(rows_, 0.0f);
  trow_.assign(rows_, 0.0f);
  crow_.assign(rows_, 0.0f);
  d0row_.assign(rows_, 0.0f);
  kd_ = kl_ = 0.0f;
  prof_.assign(n_, 0.0f);
  grow_.assign(rows_, 1.0f);
  // §6.3, §6.4, §4.1: the camber's height profile and the draft's exponent (coefficients in double, so the
  // defaults give the constants they replace exactly)
  const float pk = static_cast<float>(peak), pk1 = static_cast<float>(1.0 - peak);
  const float cf = static_cast<float>(1.0 - foot), chd = static_cast<float>(1.0 - headd);
  const double ql = std::log(0.5) / std::log(dlow), qh = std::log(0.5) / std::log(dhead);
  const float q0 = static_cast<float>(ql), dq = static_cast<float>(qh - ql);
  const float df = static_cast<float>(dfrom), df1 = static_cast<float>(1.0 - dfrom);
  const float fgm = static_cast<float>(gm), fgf = static_cast<float>(gf - gm), fgh = static_cast<float>(gh - gm);
  const float flc = static_cast<float>(lc), frc = static_cast<float>(rc);
  for (int i = 0; i < rows_; ++i) {
    for (int j = 0; j < cols_; ++j) {
      const int k = i * cols_ + j;
      u_[k] = (a_[k] - a_min_) / sa_;
      h_[k] = (l_[k] - l_min_) / sl_;
      uc_[k] = static_cast<float>(j) / static_cast<float>(cols_ - 1);
    }
    c_[i] = r[i * cols_ + cols_ - 1].distance_to(r[i * cols_]);
    amid_[i] = 0.5f * (a_[i * cols_] + a_[i * cols_ + cols_ - 1]);
    hrow_[i] = h_[i * cols_];
    const float cr = clampf(1.0f - hrow_[i] / clew_h, 0.0f, 1.0f);
    crow_[i] = cr * cr * cr;
    u0row_[i] = u_[i * cols_];
    ulrow_[i] = u_[i * cols_ + cols_ - 1];
    // §6.3 (asymmetric: deepest at 0.3 of the height, the draft forward) and §6.4 (symmetric: full depth from the
    // foot to mid height, the draft in the middle), by the set parameters of §4.1
    const float hr = hrow_[i];
    if (kite) {
      const float lo = (pk - hr) / pk, hi = (hr - pk) / pk1;
      prow_[i] = hr < pk ? 1.0f - cf * lo * lo : 1.0f - chd * hi * hi;
      const float t = clampf((hr - df) / df1, 0.0f, 1.0f);
      const float q = q0 + dq * t * t * (3.0f - 2.0f * t);
      const float b = hr < 0.5f ? 1.0f - 2.0f * hr : 2.0f * hr - 1.0f;
      grow_[i] = fgm + (hr < 0.5f ? fgf : fgh) * b * b;
      const float fh = 4.0f * hr * (1.0f - hr);  // the edge curls, none at the corners
      for (int j = 0; j < cols_; ++j) {
        const float uc = uc_[i * cols_ + j];
        float pr;
        if (kind_ == ASYM) {
          pr = std::sin(PI_F * std::pow(uc, q));
        } else {
          const float x = q == 1.0f ? uc : std::pow(uc, q);
          pr = 4.0f * x * (1.0f - x);
        }
        if (flc != 0.0f) {
          const float bl = clampf(1.0f - uc / CURL_BAND, 0.0f, 1.0f);
          pr += flc * bl * bl * fh;
        }
        if (frc != 0.0f) {
          const float br = clampf(1.0f - (1.0f - uc) / CURL_BAND, 0.0f, 1.0f);
          pr += frc * br * br * fh;
        }
        prof_[i * cols_ + j] = pr;
      }
    }
  }
  furl_radius_ = getf(p, "furl_radius", 0.02f + 0.006f * sa_);
  tack_d_.assign(n_, 0.0f);
  for (int k = 0; k < n_; ++k) tack_d_[k] = r[k].distance_to(r[0]);
  // §4.1 the corners' hold of `forward` and the share of `tack_rise`, from the rest distances to the corners
  hold_.assign(n_, 0.0f);
  rise_.assign(n_, 0.0f);
  if (kite) {
    const float rr = HOLD * sl_;
    const Vector3 hc = r[(rows_ - 1) * cols_], cc = r[cols_ - 1];
    for (int k = 0; k < n_; ++k) {
      hold_[k] = smooth01(tack_d_[k] / rr) * smooth01(r[k].distance_to(hc) / rr) * smooth01(r[k].distance_to(cc) / rr);
      const float w = 1.0f - std::min(tack_d_[k] / (TACK_REACH * sl_), 1.0f);
      rise_[k] = w * w;
    }
  }
  fa_ = 0.0f;
  // §7.4 rest distances between grid neighbours, for the spread of the push
  ec_.assign(n_, 0.0f);
  er_.assign(n_, 0.0f);
  e1_.assign(n_, 0.0f);
  e2_.assign(n_, 0.0f);
  for (int i = 0; i < rows_; ++i) {
    for (int j = 0; j < cols_; ++j) {
      const int k = i * cols_ + j;
      if (j + 1 < cols_) ec_[k] = r[k].distance_to(r[k + 1]);
      if (i + 1 < rows_) {
        er_[k] = r[k].distance_to(r[k + cols_]);
        if (j + 1 < cols_) e1_[k] = r[k].distance_to(r[k + cols_ + 1]);
        if (j > 0) e2_[k] = r[k].distance_to(r[k + cols_ - 1]);
      }
    }
  }
  cp_.assign(n_, 0.0f);
  px_.assign(n_, 0.0f);
  pd_.assign(n_, 0.0f);
  pg_.assign(n_, Vector3());
  const Vector3 dh = tack_ - head_;
  r_h_ = std::max((dh - up_ * dh.dot(up_)).length(), 1e-3f);
  const Vector3 hz = -fwd_;
  const float den = hz.dot(ah_);
  kappa_ = std::fabs(den) > 1e-6f ? hz.dot(lh_) / den : 0.0f;

  loc_.assign(n_, Vector3());
  mid_.assign(n_, Vector3());
  pos_.assign(2 * n_, Vector3());
  nrm_.assign(2 * n_, Vector3());
  for (int k = 0; k < n_; ++k) {
    loc_[k] = Vector3(a_[k], l_[k], 0.0f);
    mid_[k] = r[k];
    pos_[k] = r[k] + nh_ * 0.001f;
    pos_[n_ + k] = r[k] - nh_ * 0.001f;
    nrm_[k] = nh_;
    nrm_[n_ + k] = -nh_;
  }
  tl_set_ = false;
  s_b_ = 1.0f;
  return true;
}

void SailShape::advance(double dt_in, double aws, double awa, bool backed) {
  const float dt = clampf(static_cast<float>(dt_in), 0.0f, DT_MAX);
  const float w = std::min(flutter_rate_ * static_cast<float>(aws), flutter_rate_max_);
  phi_ = std::fmod(phi_ + w * dt, TAU_F);
  if (phi_ < 0.0f) phi_ += TAU_F;
  const float k = 1.0f - std::exp(-dt / TAU_SMOOTH);
  s_b_ += ((backed ? -1.0f : 1.0f) - s_b_) * k;
  const float target = -sgn(static_cast<float>(awa));
  if (!tl_set_) {
    tl_ = target;
    tl_set_ = true;
  } else {
    tl_ += (target - tl_) * k;
  }
}

Vector3 SailShape::main_shape(int k, float d_cam, float amp, float shiver) const {
  const float h = h_[k], u = u_[k];
  const float f = 1.0f - std::exp(-8.0f * h);
  return Vector3(a_[k], l_[k], f * d_cam * u * (1.0f - u) + amp * shiver * h * u * std::sin(phi_ - a_[k]));
}

float SailShape::head_n(int i, float u, float a, float d_cam, float amp, float shiver, float us) const {
  const float fl = amp * shiver * u * std::sin(phi_ - a);
  if (cam_cap_ > 0.0f) {
    const float u2 = u * u;
    return 0.5f * d_cam * (u2 * u2 - C_HOOK * u) + fl;
  }
  // §6.2 the clew line plus a belly against each row's own chord
  const float u0 = us <= 0.0f ? u0row_[i] : 0.0f;
  const float ul = ulrow_[i] - us;
  const float x = clampf((u - u0) / std::max(ul - u0, 1e-3f), 0.0f, 1.0f);
  const float c = c_[i] * clampf((ul - u0) / std::max(ulrow_[i] - u0row_[i], 1e-3f), 0.0f, 1.0f);
  const float hh = 2.0f * hrow_[i] - 1.0f;
  const float g = x * (1.0f - x) * (2.0f - x) / JIB_PROFILE_MAX;
  const float ul2 = ul * ul;
  return 0.5f * d_cam * (ul2 * ul2 - C_HOOK * ul) * x - jcam_ * (1.0f - 0.15f * hh * hh) * c * g + fl;
}

Vector3 SailShape::halyard(int k, float p, float d_cam, float amp, float shiver) const {
  const float hc = 1.0f - p;
  if (h_[k] >= hc) return Vector3(a_[k], l_[k] - hc * sl_, head_n(k / cols_, u_[k], a_[k], d_cam, amp, shiver, 0.0f));
  return Vector3(a_[k], a_[k] * kappa_ + 0.03f, 0.02f * sl_ * std::sin(12.0f * h_[k]));
}

Vector3 SailShape::furl(int k, float p, float d_cam, float amp, float shiver) const {
  const float ac = (1.0f - p) * sa_;
  const float r = furl_radius_ * (0.4f + 0.6f * (1.0f - p));
  if (a_[k] - a_min_ < ac) {
    const float t = 6.0f * PI_F * uc_[k];
    return Vector3(a_min_ + r * (1.0f - std::cos(t)), l_[k], r * std::sin(t));
  }
  const float a2 = a_[k] - ac;
  return Vector3(a2, l_[k], head_n(k / cols_, (a2 - a_min_) / sa_, a2, d_cam, amp, shiver, 1.0f - p));
}

Vector3 SailShape::fly(int k, int i, const Vector3& w, float shiver) const {
  const float uc = uc_[k];
  const float s = srow_[i], a0 = a_[i * cols_], gi = grow_[i];
  const float e = drow_[i] * s * gi * c_[i] * prof_[k];
  const float i2 = 0.33f * flutter_amp_ * shiver;
  const float q = phi_ - 7.0f * uc;
  const Vector3 m(w.x + 0.1f * i2 * std::sin(q), w.y, w.z + i2 * std::cos(q));
  // §7.7 the draw-down; §4.1 the clew raised and let out, the head dropped, the girth
  Vector3 r = Vector3(a0 + (a_[k] - a0) * s * gi + clew_out_ * c_[0] * crow_[i] * uc * uc,
                      l_[k] - (kl_ - clew_lift_) * c_[0] * crow_[i] * uc * uc - head_drop_ * sl_ * h_[k], 0.0f) -
              m * e;
  if (foot_sag_ != 0.0f) {
    // §6.4, §4.1 the lower panels' belly sags, so the foot curves round and down
    const float fs = clampf(1.0f - hrow_[i] / foot_sag_h_, 0.0f, 1.0f);
    r.y -= foot_sag_ * e * fs * fs;
  }
  if (kind_ == SYM) {
    const float hh = 2.0f * h_[k] - 1.0f;
    const float g = std::max(0.0f, shiver - uc) * (1.0f - hh * hh);
    r.x += (a0 + (amid_[i] - a0) * s * gi - r.x) * 0.5f * g;
    r.z += g * flutter_amp_ * 0.1f * sa_ * std::sin(phi_ - a_[k]);
  }
  return r;
}

Vector3 SailShape::hoist(int k, float c, const Vector3& f) const {
  float hy = 1.0f, kk = 0.0f;
  if (c <= 0.9f)
    hy = c / 0.9f;
  else
    kk = (c - 0.9f) / 0.1f;
  const float h = h_[k];
  const float sn = flutter_amp_ * 0.1f * sa_ * std::sin(15.0f * h + phi_);
  const float x = (1.0f - h) * kk;
  const float g = 0.05f + 0.1f * clampf(10.0f * x * x * x * x, 0.0f, 1.0f);
  const Vector3 bundle(g * (f.x + sn), l_min_ + (l_[k] - l_min_) * hy, g * (f.z - sn));
  return bundle + (f - bundle) * (kk * kk);
}

// §8.5; slide (a lofted kite, §6.5): the cloth still up slides down the luff keeping its flying shape instead of
// relaxing to the flat sail (which, near the centreline, would cross the forestay)
Vector3 SailShape::drop(int k, float c, const Vector3& f, bool slide) const {
  const float thr = l_min_ + sl_ * c;
  const float kk = std::pow(c, 0.3f);
  const float r = 1.0f - h_[k];
  const float l = l_[k];
  Vector3 tg;
  if (l <= thr) {
    tg = Vector3(0.05f * sl_ * std::sin(4.0f * r), l_min_, 0.0f);
  } else {
    const float t2 = (l - thr) / sl_;
    const float w = flutter_amp_ * 0.1f * sa_ * 0.63f * std::atan(8.0f * r) * (1.0f - t2) * 2.0f * std::sin(l + phi_);
    if (slide)
      tg = Vector3(f.x + w, f.y - (thr - l_min_), f.z + w);
    else
      tg = Vector3(a_[k] + (f.x - a_[k]) * t2 + w, l - (thr - l_min_), t2 * f.z + w);
  }
  return f + (tg - f) * kk;
}

void SailShape::update(int64_t phase, double progress, double beta_in, double gamma_in, double luff_shiver,
                       double awa_in, double aws_in) {
  if (n_ == 0) return;
  const float beta = static_cast<float>(beta_in), gamma = static_cast<float>(gamma_in);
  const float awa = static_cast<float>(awa_in), aws = static_cast<float>(aws_in);
  if (!tl_set_) {
    tl_ = -sgn(awa);
    tl_set_ = true;
  }
  const float shiver = clampf(static_cast<float>(luff_shiver), 0.0f, 1.0f);
  if (loft_) {
    update_loft(phase, static_cast<float>(progress), beta, gamma, shiver, awa, aws);
    return;
  }
  const float amp = flutter_amp_ * sa_;

  // §7: the swing S, then the rotation about the (swung) luff or the boom axis
  Transform3D s_t;
  float ge = 0.0f;
  Vector3 piv = tack_, ax = lh_;
  if (mode_ == BOOM) {
    piv = boom_pivot_;
    ax = boom_axis_;
  } else if (mode_ == SPRIT) {
    const float lim = std::asin(std::min(1.0f, tack_line_max_ * sl_ / r_h_));
    ge = sgn(gamma) * std::min(std::fabs(gamma), lim);
    s_t = about(head_, up_, ge);
  } else if (mode_ == POLE) {
    ge = gamma;
    s_t = about(mast_step_, mast_axis_, ge);
  }
  if (mode_ == SPRIT || mode_ == POLE) {
    piv = s_t.xform(tack_);
    ax = s_t.basis.xform(lh_).normalized();
  }
  const float base = beta - ge;
  const Basis b0 = Basis(ax, base) * s_t.basis;
  const Vector3 ap = b0.xform(ah_), lp = b0.xform(lh_), np = b0.xform(nh_);

  // §5.1 drivers
  float d_cam = 0.0f;
  Vector3 w;
  if (kind_ == MAIN) {
    const float b = static_cast<float>(fill(std::sin(wrap_pi(beta + awa)), fill_gain_, fill_curve_));
    d_cam = sgn(b) * 4.0f * sa_ * b * b;
  } else if (kind_ == HEADSAIL) {
    const float b = static_cast<float>(fill(std::sin(beta), fill_gain_, fill_curve_)) * s_b_;
    d_cam = sgn(b) * 4.0f * sa_ * b * b;
    if (cam_cap_ > 0.0f) {
      const float dm = cam_cap_ * sa_ / 0.2362f;
      d_cam = dm * std::tanh(d_cam / dm);
    }
    jcam_ = sgn(b) * JIB_CAMBER * std::tanh(std::fabs(b) / JIB_FILL);
  } else {
    float f_fly;
    if (kind_ == SYM)
      f_fly = std::fabs(static_cast<float>(fill(std::sin(beta), fill_gain_, fill_curve_)));
    else
      f_fly = fill_gain_ * clampf(aws / KNOT, 3.0f, 6.0f) / 6.0f;
    const Vector3 uw = fwd_ * std::cos(awa) - port_ * std::sin(awa);
    w = Vector3(uw.dot(ap) * belly_aft_ / fill_curve_, uw.dot(lp) * belly_up_, uw.dot(np));
    w = w.length_squared() > 1e-12f ? w.normalized() : Vector3(0, 0, 1);
    const float fc = camber_ * std::min(f_fly, 1.15f);
    for (int i = 0; i < rows_; ++i) d0row_[i] = fc * prow_[i];
    clew_rows(0.0f, 0.0f);
  }
  // §7.1 to §7.3 the row twist (an asymmetric spinnaker's opens with the AWA)
  {
    float tw = twist_top_;
    if (kind_ == ASYM) {
      const float ta = clampf((std::fabs(awa) - twist_lo_) / (twist_hi_ - twist_lo_), 0.0f, 1.0f);
      const float tr = clampf((PI_F - std::fabs(awa)) / twist_run_, 0.0f, 1.0f);
      tw *= ta * ta * (3.0f - 2.0f * ta) * tr * tr * (3.0f - 2.0f * tr);
    }
    // (signed; the asymmetric spinnaker's on the side away from the wind at once: zero where awa changes sign)
    for (int i = 0; i < rows_; ++i)
      trow_[i] = kind_ == ASYM ? -sgn(awa) * tw * (1.0f - std::pow(1.0f - hrow_[i], twist_exp_))
                               : tl_ * tw * std::pow(hrow_[i], kind_ == SYM ? twist_exp_ : 1.5f);
  }

  // §8.1 which shape in which phase
  const bool up_shape = phase == 3 || phase == 4 || kind_ == MAIN;
  float p = 1.0f;
  if (!up_shape) {
    if (phase == 2)
      p = static_cast<float>(progress);
    else if (phase == 5)
      p = kind_ == HEADSAIL ? 1.0f - static_cast<float>(progress) : static_cast<float>(progress);
    else
      p = 0.0f;
    p = clampf(p, 0.0f, 1.0f);
  }
  locals(phase, up_shape, p, d_cam, amp, shiver, w);
  // §7.4 the ease of a flying sail off the other sails (the head lies on the luff axis)
  const Vector3 hd = s_t.xform(head_ - lh_ * (head_drop_ * sl_));  // §4.1 the head as dropped
  tack_at_ = s_t.xform(tack_);
  const bool clearing = clearance_ > 0.0f && (!obs_.empty() || has_mast_head_);
  ease_ = 0.0f;
  if (clearing && !obs_.empty()) {
    sections(s_t, piv, ax, base);
    ease_ = ease(beta, s_t, piv, ax, base, hd);
  } else {
    secs_.clear();  // no obstacles: none left over from the last update
  }
  const float es = sgn(beta) * ease_;
  // §7.7 the clew set by its sheet (with the sail as eased): the low rows again with the solved draw-in, draw-down
  kd_ = kl_ = 0.0f;
  const float g_c = (1.0f - smooth01((std::fabs(wrap_pi(beta)) - CLEW_FADE0) / (CLEW_FADE1 - CLEW_FADE0))) *
                    smooth01((std::fabs(awa) - CLEW_AWA0) / (CLEW_AWA1 - CLEW_AWA0));
  if (kind_ == ASYM && has_lead_ && g_c > 0.0f) {
    clew_set(beta, base + es, piv, ax, s_t, w);
    kd_ *= g_c;
    kl_ *= g_c;
    if (kd_ != 0.0f || kl_ != 0.0f) {
      clew_rows(kd_, kl_);
      // only the rows the clew set reaches change (the tack corner does not: its offset is the same)
      int r_to = 0;
      while (r_to < rows_ && crow_[r_to] > 0.0f) ++r_to;
      locals(phase, up_shape, p, d_cam, amp, shiver, w, r_to);
    }
  }
  // §7 placement, row by row with the twist toward leeward
  for (int i = 0; i < rows_; ++i) {
    const float th = base + trow_[i] + es;
    const Transform3D xr = about(piv, ax, th) * s_t;
    for (int j = 0; j < cols_; ++j) {
      const int k = i * cols_ + j;
      const Vector3& lc = loc_[k];
      mid_[k] = xr.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
    }
  }
  // §7.6 the share of the flying shape: 1 up, growing over the last tenth of the hoist, going with the drop
  fa_ = 0.0f;
  if (kind_ == ASYM || kind_ == SYM) {
    if (up_shape) {
      fa_ = 1.0f;
    } else if (phase == 2) {
      const float kh = clampf((p - 0.9f) / 0.1f, 0.0f, 1.0f);
      fa_ = kh * kh;
    } else if (phase == 5) {
      fa_ = 1.0f - std::pow(p, 0.3f);
    }
  }
  clew0_ = mid_[cols_ - 1];
  if (fa_ > 0.0f && (forward_ != 0.0f || tack_rise_ != 0.0f)) shift();
  if (has_stay_ && fa_ > 0.0f) stay();
  if (clearing) push(awa, hd);
  layers(np);
}

// §6.5 a lofted kite: the measured shapes blended by the AWA, scaled by the fill, the belly on the side the wind
// blows it to, then placed whole: turned about its luff by the core's sheet angle (and the trim), and further out
// only as far as the main, the jib and the mast need. No local bending.
void SailShape::update_loft(int64_t phase, float progress, float beta, float gamma, float shiver, float awa,
                            float aws) {
  Transform3D s_t;
  float ge = 0.0f;
  if (mode_ == SPRIT) {
    const float lim = std::asin(std::min(1.0f, tack_line_max_ * sl_ / r_h_));
    ge = sgn(gamma) * std::min(std::fabs(gamma), lim);
    s_t = about(head_, up_, ge);
  } else if (mode_ == POLE) {
    ge = gamma;
    s_t = about(mast_step_, mast_axis_, ge);
  }
  const Vector3 piv = s_t.xform(tack_);
  const Vector3 ax = s_t.basis.xform(lh_).normalized();
  // the measured shapes by the AWA (smoothstep between neighbours, held beyond the ends)
  const int m = static_cast<int>(loft_awa_.size());
  const float x = std::fabs(wrap_pi(awa));
  int i0 = 0, i1 = 0;
  float t = 0.0f;
  if (x >= loft_awa_[m - 1]) {
    i0 = i1 = m - 1;
  } else if (x > loft_awa_[0]) {
    while (i0 + 2 < m && x >= loft_awa_[i0 + 1]) ++i0;
    i1 = i0 + 1;
    t = smooth01((x - loft_awa_[i0]) / (loft_awa_[i1] - loft_awa_[i0]));
  }
  const float dep = std::min(fill_gain_ * clampf(aws / KNOT, 3.0f, 6.0f) / 6.0f, 1.0f) * loft_depth_;
  const float sd = clampf(std::sin(wrap_pi(beta + awa)) / LOFT_SIDE, -1.0f, 1.0f);
  // a flogging kite (the shiver: on the wind line, or flown beyond its usable angle) keeps its belly to leeward
  // forward of the beam, its fill breathing and its luff collapsing and refilling, the flutter three times as hard
  const float w_up = 1.0f - smooth01((std::fabs(wrap_pi(awa)) - LOFT_FLOG_UP0) / LOFT_FLOG_UP1);
  const float kf = shiver * w_up;  // forward of the beam: abaft it a luffing kite (a gybe) only shivers
  const float side = sd * (3.0f - sd * sd) / 2.0f;
  float side_f = side + (sgn(awa) - side) * std::min(1.0f, 2.0f * kf);
  // the belly crosses over at most at LOFT_SIDE_RATE per second (a gybe turns it inside out over a visible time)
  if (turn_set_ && turn_step_ > 0.0f) {
    const float lim = LOFT_SIDE_RATE * turn_step_;
    side_f = side_prev_ + clampf(side_f - side_prev_, -lim, lim);
  }
  side_prev_ = side_f;
  const float breath = 1.0f - kf * (0.3f + 0.2f * std::sin(phi_) + 0.15f * std::sin(2.3f * phi_ + 1.0f));
  const float luff_c = kf * (0.5f + 0.5f * std::sin(1.7f * phi_ + 0.5f));
  const float i2 = 0.33f * flutter_amp_ * shiver * (1.0f + 2.0f * kf);
  fly_.resize(n_);
  const Vector3* l0 = loft_pts_.data() + static_cast<size_t>(i0) * n_;
  const Vector3* l1 = loft_pts_.data() + static_cast<size_t>(i1) * n_;
  for (int k = 0; k < n_; ++k) {
    const Vector3 lf = l0[k] + (l1[k] - l0[k]) * t;
    Vector3 fl(a_[k], l_[k], 0.0f);
    fl += (lf - fl) * (dep * breath);
    fl.z *= side_f;
    if (luff_c > 0.0f && uc_[k] < LOFT_FLOG_LUFF) {
      const float r = 1.0f - uc_[k] / LOFT_FLOG_LUFF;
      fl.z *= 1.0f - luff_c * r * r;
    }
    if (i2 > 0.0f) {  // luffing: the belly breathes, strongest where it is deep, travelling aft
      const float q = phi_ - 7.0f * uc_[k];
      fl += Vector3(0.1f * i2 * std::sin(q) * std::fabs(fl.z), 0.0f, i2 * std::cos(q) * fl.z);
    }
    fly_[k] = fl;
  }
  // the turn about the luff: the core's sheet angle (as the hinge model's, §7.3), plus the trim
  // the trim and the turn off the obstacles fade out where sgn(beta) flips: on the centreline and round the bow
  const float wb = std::fabs(wrap_pi(beta));
  const float es = sgn(beta) * smooth01(wb / LOFT_FADE0) * (1.0f - smooth01((wb - LOFT_FADE1) / LOFT_FADE2));
  const float th = beta - ge + es * loft_trim_;
  turn_ = th;
  // §8.1 which shape: the hoist and drop of §8.4, §8.5 toward the flying shape, the tack on its fitting
  const bool up_shape = phase == 3 || phase == 4;
  float p = 1.0f;
  if (!up_shape) p = (phase == 2 || phase == 5) ? clampf(progress, 0.0f, 1.0f) : 0.0f;
  for (int k = 0; k < n_; ++k) {
    if (up_shape)
      loc_[k] = fly_[k];
    else if (phase == 5)
      loc_[k] = drop(k, p, fly_[k], true);
    else
      loc_[k] = hoist(k, p, fly_[k]);
  }
  if (!up_shape) {
    const Vector3 dt0 = loc_[0] - Vector3(a_[0], l_[0], 0.0f);
    if (dt0.length_squared() > 0.0f) {
      for (int k = 0; k < n_; ++k) {
        const float wt = 1.0f - clampf(tack_d_[k] / (TACK_PIN * sl_), 0.0f, 1.0f);
        if (wt > 0.0f) loc_[k] -= dt0 * (wt * wt);
      }
    }
  }
  std::fill(trow_.begin(), trow_.end(), 0.0f);
  kd_ = kl_ = 0.0f;
  const Vector3 hd = s_t.xform(head_);
  tack_at_ = piv;
  ease_ = 0.0f;
  if (clearance_ > 0.0f && (!obs_.empty() || has_mast_head_ || loft_stay_)) {
    if (!obs_.empty())
      sections(s_t, piv, ax, th);
    else
      secs_.clear();
    stay_on_ = wb <= LOFT_FADE1;  // not while an asymmetric goes round the bow in a gybe
    ease_ = loft_ease(es, awa, s_t, piv, ax, th, hd);
  } else {
    secs_.clear();
  }
  // the drawn turn moves at most LOFT_EASE_RATE from the last update's over the time since (a placement's first
  // update, or a step of 0, takes it at once)
  float turned = es * ease_;  // the turn as drawn, out to the side of sgn(beta)
  if (turn_set_ && turn_step_ > 0.0f) {
    const float lim = LOFT_EASE_RATE * turn_step_;
    turned = turn_prev_ + clampf(turned - turn_prev_, -lim, lim);
  }
  turn_prev_ = turned;
  turn_set_ = true;
  const Transform3D xr = about(piv, ax, th + turned) * s_t;
  for (int k = 0; k < n_; ++k) {
    const Vector3& lc = loc_[k];
    mid_[k] = xr.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
  }
  fa_ = 0.0f;
  if (up_shape) {
    fa_ = 1.0f;
  } else if (phase == 2) {
    const float kh = clampf((p - 0.9f) / 0.1f, 0.0f, 1.0f);
    fa_ = kh * kh;
  } else if (phase == 5) {
    fa_ = 1.0f - std::pow(p, 0.3f);
  }
  clew0_ = mid_[cols_ - 1];
  layers(xr.basis.xform(nh_));
}

void SailShape::loft_clear(const std::vector<Vector3>& pts, const Vector3& hd, const Vector3& lee,
                           const std::vector<int>& idx, std::vector<float>& out) const {
  out.resize(idx.size());
  Vector3 g;
  for (size_t q = 0; q < idx.size(); ++q) {
    const Vector3& pt = pts[idx[q]];
    const float cp = LOFT_MARGIN * margin_at(pt, hd);
    float x = has_mast_head_ ? mast_x(pt, lee, g) - cp : INFINITY;
    for (const Section& o : secs_) x = std::min(x, clear_x(o, pt, cp, g) - cp);
    if (loft_stay_ && stay_on_) x = std::min(x, stay_x(pt) - loft_stay_c_);
    out[q] = x;
  }
}

// §6.5 how far a point lies ahead of the forestay, a wall LOFT_NEAR clearances either side of the stay between its
// tack fitting and the hounds (INFINITY beside or above it)
float SailShape::stay_x(const Vector3& pt) const {
  const float z0 = stay0_.dot(up_), z1 = stay1_.dot(up_), pz = pt.dot(up_);
  if (pz < z0 || pz > z1) return INFINITY;
  const Vector3 q = stay0_ + (stay1_ - stay0_) * ((pz - z0) / (z1 - z0));
  if (std::fabs((pt - q).dot(port_)) > LOFT_NEAR * clearance_) return INFINITY;
  return (pt - q).dot(fwd_);
}

float SailShape::loft_ease(float beta, float awa, const Transform3D& s_t, const Vector3& piv, const Vector3& ax,
                           float th, const Vector3& hd) {
  lq_.resize(n_);
  lp_.resize(n_);
  for (int k = 0; k < n_; ++k) {
    const Vector3& lc = loc_[k];
    lq_[k] = s_t.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
  }
  float left = 0.0f;
  return loft_turn(1.0f, beta, awa, piv, ax, th, hd, left);
}

// §6.5 the turn's solve one way (dir +1 out, -1 in): the turn (rad, >= 0) and, in `left`, the worst clearance over
// its margin there (>= 0 when clear). After the first step only the vertices then within LOFT_NEAR clearances of the
// worst are looked at again, but with the forestay every vertex (the whole kite may come round it).
float SailShape::loft_turn(float dir, float es_f, float awa, const Vector3& piv, const Vector3& ax, float th,
                           const Vector3& hd, float& left) {
  // the turn as it is drawn: es_f, the out side times the fade where sgn(beta) flips (update_loft)
  const float es = es_f * dir;
  left = 0.0f;
  if (std::fabs(es_f) < 0.05f) return 0.0f;
  const Vector3 lee = port_ * sgn(awa);
  const float cap = loft_stay_ ? LOFT_STAY_MAX : LOFT_EASE_MAX;
  float delta = 0.0f;
  lidx_.resize(n_);
  for (int k = 0; k < n_; ++k) lidx_[k] = k;
  left = INFINITY;
  for (int it = 0; it <= LOFT_EASE_STEPS; ++it) {
    const Transform3D xr = about(piv, ax, th + es * delta);
    for (int k : lidx_) lp_[k] = xr.xform(lq_[k]);
    loft_clear(lp_, hd, lee, lidx_, lx_);
    float worst = INFINITY;
    int at = -1;
    for (size_t m = 0; m < lx_.size(); ++m) {
      if (lx_[m] < worst) {
        worst = lx_[m];
        at = lidx_[m];
      }
    }
    left = worst;
    if (!(worst < 0.0f) || it == LOFT_EASE_STEPS || delta >= cap) break;
    if (it == 0 && !loft_stay_) {
      size_t w = 0;
      for (size_t m = 0; m < lx_.size(); ++m)
        if (lx_[m] < worst + LOFT_NEAR * clearance_) lidx_[w++] = lidx_[m];
      lidx_.resize(w);
    }
    const Vector3 d = lp_[at] - piv;
    const float rr = (d - ax * d.dot(ax)).length();
    delta = std::min(delta + (-worst) / (std::max(rr, 0.5f) * std::fabs(es)), cap);
  }
  return delta;
}

// §7.4 a flying sail on a pole flies forward of the forestay: per row the shift forward that brings its cloth
// within the stay's half width at least c_s ahead of the stay, the largest of its own and the rows' above (so it
// grows down to the foot), faded out over the top STAY_HEAD of the height, taken in full at the middle of the
// chord, none at the luff and 1 - STAY_LEECH of it at the leech; times the flying shape's share.
void SailShape::stay() {
  const float z0 = stay0_.dot(up_), z1 = stay1_.dot(up_);
  std::vector<float> sw(cols_), d_row(rows_, 0.0f);
  for (int j = 0; j < cols_; ++j) {
    const float uc = uc_[j];
    sw[j] = smooth01(uc / stay_luff_) * (1.0f - stay_leech_ * smooth01((uc - stay_luff_) / (1.0f - stay_luff_)));
  }
  for (int i = 0; i + 1 < rows_; ++i) {
    for (int j = 0; j < cols_; ++j) {
      const Vector3& pt = mid_[i * cols_ + j];
      const float pz = pt.dot(up_);
      if (pz < z0 || pz > z1 || sw[j] < 0.25f) continue;
      const Vector3 q = stay0_ + (stay1_ - stay0_) * ((pz - z0) / (z1 - z0));
      const float dy = std::fabs((pt - q).dot(port_));
      const float k = 1.0f - smooth01((dy - stay_w_) / stay_c_);
      const float d = (stay_c_ - (pt - q).dot(fwd_)) * k;
      if (d > 0.0f) d_row[i] = std::max(d_row[i], d / std::max(sw[j], 0.5f));
    }
  }
  for (int i = rows_ - 2; i >= 0; --i) d_row[i] = std::max(d_row[i], d_row[i + 1]);  // never less than above
  for (int i = 0; i < rows_; ++i) {
    const float s = d_row[i] * smooth01((1.0f - hrow_[i]) / stay_head_) * fa_;
    if (s <= 0.0f) continue;
    for (int j = 0; j < cols_; ++j) mid_[i * cols_ + j] += fwd_ * (s * sw[j]);
  }
}

// §4.1 the cloth projected forward (the corners held) and the tack raised, times the flying shape's share
void SailShape::shift() {
  const float f = forward_ * sl_ * fa_, t = tack_rise_ * sl_ * fa_;
  for (int k = 0; k < n_; ++k) mid_[k] += fwd_ * (f * hold_[k]) + up_ * (t * rise_[k]);
  tack_at_ += up_ * t;
}

// §6, §8 the local shape of every vertex, with the tack pin of §7.5
void SailShape::locals(int64_t phase, bool up_shape, float p, float d_cam, float amp, float shiver,
                       const Vector3& w, int rows_to) {
  const int r_to = rows_to < 0 ? rows_ : std::min(rows_to, rows_);
  for (int i = 0; i < r_to; ++i) {
    for (int j = 0; j < cols_; ++j) {
      const int k = i * cols_ + j;
      Vector3 lc;
      if (kind_ == MAIN) {
        lc = main_shape(k, d_cam, amp, shiver);
      } else if (kind_ == HEADSAIL) {
        if (up_shape)
          lc = Vector3(a_[k], l_[k], head_n(i, u_[k], a_[k], d_cam, amp, shiver, 0.0f));
        else if (furling_)
          lc = furl(k, p, d_cam, amp, shiver);
        else
          lc = halyard(k, p, d_cam, amp, shiver);
      } else {
        const Vector3 f = fly(k, i, w, shiver);
        if (up_shape)
          lc = f;
        else if (phase == 5)
          lc = drop(k, p, f);
        else
          lc = hoist(k, p, f);
      }
      loc_[k] = lc;
    }
  }
  // §7.3 the tack stays on its fitting: the hoist and drop shapes' offset of the tack corner is taken out of the
  // cloth round it
  if (kind_ == ASYM || kind_ == SYM) {
    const Vector3 dt0 = loc_[0] - Vector3(a_[0], l_[0], 0.0f);
    if (dt0.length_squared() > 0.0f) {
      for (int k = 0; k < r_to * cols_; ++k) {
        const float wt = 1.0f - clampf(tack_d_[k] / (TACK_PIN * sl_), 0.0f, 1.0f);
        if (wt > 0.0f) loc_[k] -= dt0 * (wt * wt);
      }
    }
  }
}

// §7.7 the rows' chord over flat chord and camber with the draw-in kd (the low rows drawn in, the cloth's length
// kept as camber), and the draw-down kl
void SailShape::clew_rows(float kd, float kl) {
  for (int i = 0; i < rows_; ++i) {
    float s = 1.0f / (1.0f + 8.0f / 3.0f * d0row_[i] * d0row_[i]);
    if (kd != 0.0f && crow_[i] > 0.0f) {
      s = std::min(s * (1.0f - kd * crow_[i]), 1.0f);
      drow_[i] = std::sqrt(std::max(1.0f / s - 1.0f, 0.0f) * 3.0f / 8.0f);
    } else {
      drow_[i] = d0row_[i];
    }
    srow_[i] = s;
  }
  kl_ = kl;
}

// §7.7 the flying shape (up, no flutter) of vertex k with the draw-in kd and draw-down kl
Vector3 SailShape::fly_at(int k, const Vector3& w, float kd, float kl) const {
  const int i = k / cols_;
  float s = 1.0f / (1.0f + 8.0f / 3.0f * d0row_[i] * d0row_[i]);
  float d = d0row_[i];
  if (kd != 0.0f && crow_[i] > 0.0f) {
    s = std::min(s * (1.0f - kd * crow_[i]), 1.0f);
    d = std::sqrt(std::max(1.0f / s - 1.0f, 0.0f) * 3.0f / 8.0f);
  }
  const float a0 = a_[i * cols_], uc = uc_[k], gi = grow_[i];
  const float e = d * s * gi * c_[i] * prof_[k];
  Vector3 r(a0 + (a_[k] - a0) * s * gi + clew_out_ * c_[0] * crow_[i] * uc * uc,
            l_[k] - (kl - clew_lift_) * c_[0] * crow_[i] * uc * uc - head_drop_ * sl_ * h_[k], 0.0f);
  if (foot_sag_ != 0.0f) {
    const float fs = clampf(1.0f - hrow_[i] / foot_sag_h_, 0.0f, 1.0f);
    r.y -= foot_sag_ * e * fs * fs;
  }
  return r - w * e;
}

// §7.7 the corner's bisector b and the sheet's direction s with (kd, kl)
void SailShape::clew_corner(float kd, float kl, float beta, float base, const Vector3& piv, const Vector3& ax,
                            const Transform3D& s_t, const Vector3& w, Vector3& b, Vector3& s) const {
  const Transform3D x0 = about(piv, ax, base + trow_[0]) * s_t;
  const Transform3D x2 = about(piv, ax, base + trow_[CLEW_REACH]) * s_t;
  Vector3 lc = fly_at(cols_ - 1, w, kd, kl);
  const Vector3 cl = x0.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
  lc = fly_at(cols_ - 1 - CLEW_REACH, w, kd, kl);
  const Vector3 ft = x0.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
  lc = fly_at(CLEW_REACH * cols_ + cols_ - 1, w, kd, kl);
  const Vector3 et = x2.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
  b = ((ft - cl).normalized() + (et - cl).normalized()).normalized();
  s = (cl - working_lead(beta)).normalized();
}

// §7.7 the draw-in and draw-down that lay the clew's bisector on the sheet: two Newton steps from (0, 0) with
// difference derivatives, each clamped to its bounds; into kd_, kl_
void SailShape::clew_set(float beta, float base, const Vector3& piv, const Vector3& ax, const Transform3D& s_t,
                         const Vector3& w) {
  Vector3 b, s0;
  clew_corner(0.0f, 0.0f, beta, base, piv, ax, s_t, w, b, s0);
  Vector3 u1 = s0.cross(up_);
  if (u1.length_squared() < 1e-12f) u1 = s0.cross(fwd_);
  u1 = u1.normalized();
  const Vector3 u2 = u1.cross(s0);
  auto res = [&](float kd, float kl, float& r0, float& r1) {
    Vector3 bb, ss;
    clew_corner(kd, kl, beta, base, piv, ax, s_t, w, bb, ss);
    const Vector3 d = bb - ss;
    r0 = d.dot(u1);
    r1 = d.dot(u2);
  };
  float kd = 0.0f, kl = 0.0f;
  for (int it = 0; it < CLEW_ITER; ++it) {
    float r0, r1, a0, a1, c0, c1;
    res(kd, kl, r0, r1);
    res(kd + CLEW_STEP, kl, a0, a1);
    res(kd, kl + CLEW_STEP, c0, c1);
    const float j00 = (a0 - r0) / CLEW_STEP, j10 = (a1 - r1) / CLEW_STEP;  // d r / d kd
    const float j01 = (c0 - r0) / CLEW_STEP, j11 = (c1 - r1) / CLEW_STEP;  // d r / d kl
    const float det = j00 * j11 - j01 * j10;
    if (std::fabs(det) < 1e-9f) break;
    kd = clampf(kd - (j11 * r0 - j01 * r1) / det, CLEW_KD_LO, CLEW_KD_HI);
    kl = clampf(kl - (-j10 * r0 + j00 * r1) / det, CLEW_KL_LO, CLEW_KL_HI);
  }
  kd_ = kd;
  kl_ = kl;
}

Vector3 SailShape::working_lead(double beta) const {
  const float y = sheet_lead_.dot(port_);
  return sheet_lead_ + port_ * (-sgn(static_cast<float>(beta)) * std::fabs(y) - y);
}


void SailShape::set_obstacles(const Array& obstacles) {
  obs_.clear();
  for (int64_t i = 0; i < obstacles.size(); ++i) {
    SailShape* s = Object::cast_to<SailShape>(static_cast<Object*>(obstacles[i]));
    if (s != nullptr && s != this && s->n_ > 0) obs_.push_back(Ref<SailShape>(s));
  }
}

// §7.4: mean row heights and the bow-facing foot normal of each obstacle, the side from this sail's clew before
// the ease.
void SailShape::sections(const Transform3D& s_t, const Vector3& piv, const Vector3& ax, float base) {
  const Vector3& lc = loc_[cols_ - 1];
  const Transform3D xr = about(piv, ax, base + trow_[0]) * s_t;
  const Vector3 cl = xr.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
  const float sk = sgn((cl - mast_step_).dot(port_));
  const Vector3 bow = fwd_ + port_ * (0.3f * sk);
  secs_.resize(obs_.size());
  for (size_t o = 0; o < obs_.size(); ++o) {
    const SailShape* s = obs_[o].ptr();
    Section& sc = secs_[o];
    sc.s = s;
    sc.z.assign(s->rows_, 0.0f);
    sc.box.assign(4 * s->rows_, 0.0f);
    for (int i = 0; i < s->rows_; ++i) {
      float z = 0.0f, x0 = INFINITY, x1 = -INFINITY, y0 = INFINITY, y1 = -INFINITY;
      for (int j = 0; j < s->cols_; ++j) {
        const Vector3& m = s->mid_[i * s->cols_ + j];
        z += m.dot(up_);
        const float x = m.dot(fwd_), y = m.dot(port_);
        x0 = std::min(x0, x);
        x1 = std::max(x1, x);
        y0 = std::min(y0, y);
        y1 = std::max(y1, y);
      }
      sc.z[i] = z / static_cast<float>(s->cols_);
      float* bx = sc.box.data() + 4 * i;
      bx[0] = x0;
      bx[1] = x1;
      bx[2] = y0;
      bx[3] = y1;
    }
    for (int i = 0; i + 1 < s->rows_; ++i) {  // row i's box covers rows i and i + 1
      float* bx = sc.box.data() + 4 * i;
      const float* nx = bx + 4;
      bx[0] = std::min(bx[0], nx[0]);
      bx[1] = std::max(bx[1], nx[1]);
      bx[2] = std::min(bx[2], nx[2]);
      bx[3] = std::max(bx[3], nx[3]);
    }
    const Vector3 ch = s->mid_[s->cols_ - 1] - s->mid_[0];
    Vector3 f = up_.cross(ch - up_ * ch.dot(up_));
    f = f.length_squared() > 1e-12f ? f.normalized() : port_;
    sc.f = f.dot(bow) >= 0.0f ? f : -f;
  }
}

// §7.4: clearance of p from an obstacle's section at p's height (horizontal), and the push direction g.
float SailShape::clear_x(const Section& o, const Vector3& p, float reach, Vector3& g) const {
  const SailShape& s = *o.s;
  const int r_n = s.rows_, c_n = s.cols_;
  const float z = p.dot(up_);
  if (z < o.z[0] - clearance_ || z > o.z[r_n - 1]) return INFINITY;
  const int r = std::max(0, std::min(r_n - 2, static_cast<int>(std::upper_bound(o.z.begin(), o.z.end(), z) -
                                                                 o.z.begin()) - 1));
  const float* bx = o.box.data() + 4 * r;
  const float px = p.dot(fwd_), py = p.dot(port_);
  reach += RUN_ON * clearance_;  // the bounds cover the leech's run-on
  if (px < bx[0] - reach || px > bx[1] + reach || py < bx[2] - reach || py > bx[3] + reach) return INFINITY;
  const float den = o.z[r + 1] - o.z[r];
  const float t = den > 1e-6f ? clampf((z - o.z[r]) / den, 0.0f, 1.0f) : 0.0f;
  const Vector3 ph = p - up_ * z;
  const Vector3* m0 = s.mid_.data() + r * c_n;
  const Vector3* m1 = m0 + c_n;
  auto sec = [&](int j) {
    const Vector3 q = m0[j] + (m1[j] - m0[j]) * t;
    return q - up_ * q.dot(up_);
  };
  float best = INFINITY, bs = 0.0f, bh = 1.0f;
  int bj = 0;
  Vector3 bq, bd;
  Vector3 q0 = sec(0);
  for (int j = 0; j + 1 < c_n; ++j) {
    const Vector3 q1 = sec(j + 1);
    const Vector3 d = q1 - q0;
    const float l2 = d.length_squared();
    // the last segment runs on past the leech by RUN_ON clearances (§7.4)
    const float hi = (j == c_n - 2 && l2 > 1e-12f) ? 1.0f + RUN_ON * clearance_ / std::sqrt(l2) : 1.0f;
    const float sp = l2 > 1e-12f ? clampf((ph - q0).dot(d) / l2, 0.0f, hi) : 0.0f;
    const Vector3 q = q0 + d * sp;
    const float d2 = (ph - q).length_squared();
    if (d2 < best) {
      best = d2;
      bj = j;
      bs = sp;
      bq = q;
      bd = d;
      bh = hi;
    }
    q0 = q1;
  }
  if ((bj == 0 && bs <= 0.0f) || (bj == c_n - 2 && bs >= bh) || bd.length_squared() < 1e-12f) {
    const Vector3 v = ph - bq;
    const float len = v.length();
    g = len > 1e-6f ? v / len : o.f;
    return len;
  }
  g = up_.cross(bd).normalized();
  if (g.dot(o.f) < 0.0f) g = -g;
  return (ph - bq).dot(g);
}

float SailShape::mast_x(const Vector3& p, const Vector3& lee, Vector3& g) const {
  const Vector3 d = p - mast_step_;
  const Vector3 ax = mast_head_ - mast_step_;
  const float len = ax.length();
  if (len < 1e-6f) return INFINITY;
  const Vector3 au = ax / len;
  const float tz = d.dot(au);
  if (tz < 0.0f || tz > len) return INFINITY;
  const Vector3 rad = d - au * tz;
  const float x = rad.length();
  g = x > 1e-6f ? rad / x : lee;
  return x;
}

float SailShape::margin_at(const Vector3& p, const Vector3& hd) const {
  const float x = clampf(p.distance_to(hd) / (5.0f * clearance_), 0.0f, 1.0f);
  const float y = clampf(p.distance_to(tack_at_) / (5.0f * clearance_), 0.0f, 1.0f);
  return clearance_ * x * x * (3.0f - 2.0f * x) * y * y * (3.0f - 2.0f * y);
}

// §7.4 the ease: the extra turn about the luff that brings the leech samples clear of the obstacles.
float SailShape::ease(float beta, const Transform3D& s_t, const Vector3& piv, const Vector3& ax, float base,
                      const Vector3& hd) const {
  float delta = 0.0f;
  const float es = sgn(beta);
  for (int it = 0; it < 4; ++it) {
    float worst = INFINITY, rr = 1.0f;
    for (int i = 0;; i = std::min(i + 3, rows_ - 2)) {  // rows 0, 3, 6, ... and the one below the head
      const int k = i * cols_ + cols_ - 1;
      const Vector3& lc = loc_[k];
      const float th = base + trow_[i] + es * delta;
      const Vector3 pt = (about(piv, ax, th) * s_t).xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
      const float cp = margin_at(pt, hd);
      for (const Section& o : secs_) {
        Vector3 g;
        const float x = clear_x(o, pt, cp, g) - cp;
        if (x < worst) {
          worst = x;
          const Vector3 d = pt - piv;
          rr = (d - ax * d.dot(ax)).length();
        }
      }
      if (i == rows_ - 2) break;
    }
    worst += PUSH_EASE * clearance_;  // the push takes up to P_e; the ease only the rest
    if (worst >= 0.0f) break;
    delta = std::min(delta + (-worst) / std::max(rr, 0.5f), EASE_MAX);
  }
  return delta;
}

// §7.4 the spread of the push depths: d_k = max over k' of d_k' - k_p * (rest distance over the cloth), by two
// chamfer passes over the grid (row, column and diagonal neighbours).
void SailShape::spread(std::vector<float>& d) const {
  const int rn = rows_, cn = cols_;
  const float s = PUSH_SLOPE;
  for (int i = 0; i < rn; ++i) {
    for (int j = 0; j < cn; ++j) {
      const int k = i * cn + j;
      float v = d[k];
      if (j > 0) v = std::max(v, d[k - 1] - s * ec_[k - 1]);
      if (i > 0) {
        v = std::max(v, d[k - cn] - s * er_[k - cn]);
        if (j > 0) v = std::max(v, d[k - cn - 1] - s * e1_[k - cn - 1]);
        if (j + 1 < cn) v = std::max(v, d[k - cn + 1] - s * e2_[k - cn + 1]);
      }
      d[k] = v;
    }
  }
  for (int i = rn - 1; i >= 0; --i) {
    for (int j = cn - 1; j >= 0; --j) {
      const int k = i * cn + j;
      float v = d[k];
      if (j + 1 < cn) v = std::max(v, d[k + 1] - s * ec_[k]);
      if (i + 1 < rn) {
        v = std::max(v, d[k + cn] - s * er_[k]);
        if (j + 1 < cn) v = std::max(v, d[k + cn + 1] - s * e1_[k]);
        if (j > 0) v = std::max(v, d[k + cn - 1] - s * e2_[k]);
      }
      d[k] = v;
    }
  }
}

// §7.4 the push: per obstacle the local push (a smooth bump along the obstacle's bow-facing normal) and the margin
// push, then every vertex off the mast.
void SailShape::push(float awa, const Vector3& hd) {
  const float b = clearance_;
  auto smax = [b](float x) { return x >= b ? x : (x <= -b ? 0.0f : (x + b) * (x + b) / (4.0f * b)); };
  const Vector3 lee = port_ * sgn(awa);
  for (int k = 0; k < n_; ++k) cp_[k] = margin_at(mid_[k], hd);
  for (const Section& o : secs_) {
    bool any = false;
    for (int k = 0; k < n_; ++k) {
      const float x = clear_x(o, mid_[k], cp_[k] + b, pg_[k]);
      px_[k] = x;
      pd_[k] = x < cp_[k] + b ? cp_[k] - x : -INFINITY;
      any = any || x < cp_[k] + b;
    }
    if (any) {
      spread(pd_);
      for (int k = 0; k < n_; ++k) {
        const float v = smax(pd_[k]) * cp_[k] / b;
        if (v > 0.0f) {
          mid_[k] += o.f * v;
          px_[k] = clear_x(o, mid_[k], cp_[k] + b, pg_[k]);
        }
      }
    }
    for (int k = 0; k < n_; ++k) {
      const float x = px_[k];
      if (x < cp_[k] + b) mid_[k] += pg_[k] * (cp_[k] + smax(x - cp_[k]) - x);
    }
  }
  if (has_mast_head_) {
    for (int k = 0; k < n_; ++k) {
      Vector3 g;
      const float x = mast_x(mid_[k], lee, g);
      if (x < cp_[k] + b) mid_[k] += g * (cp_[k] + smax(x - cp_[k]) - x);
    }
  }
}

void SailShape::layers(const Vector3& np) {
  for (int i = 0; i < rows_; ++i) {
    const int i0 = std::max(i - 1, 0), i1 = std::min(i + 1, rows_ - 1);
    for (int j = 0; j < cols_; ++j) {
      const int k = i * cols_ + j;
      const Vector3 tu = mid_[i * cols_ + std::min(j + 1, cols_ - 1)] - mid_[i * cols_ + std::max(j - 1, 0)];
      const Vector3 tv = mid_[i1 * cols_ + j] - mid_[i0 * cols_ + j];
      Vector3 nn = tu.cross(tv);
      if (nn.length_squared() < 1e-12f) nn = i > 0 ? nrm_[k - cols_] : np;
      nn.normalize();
      nrm_[k] = nn;
      nrm_[n_ + k] = -nn;
      pos_[k] = mid_[k] + nn * 0.001f;
      pos_[n_ + k] = mid_[k] - nn * 0.001f;
    }
  }
}

Dictionary SailShape::frame() const {
  Dictionary d;
  d["tack"] = tack_;
  d["head"] = head_;
  d["lh"] = lh_;
  d["ah"] = ah_;
  d["nh"] = nh_;
  d["sa"] = sa_;
  d["sl"] = sl_;
  d["a_min"] = a_min_;
  d["l_min"] = l_min_;
  d["kappa"] = kappa_;
  d["r_h"] = r_h_;
  d["furl_radius"] = furl_radius_;
  return d;
}

PackedVector3Array SailShape::local_shape() const { return to_packed(loc_); }
PackedVector3Array SailShape::mid() const { return to_packed(mid_); }

PackedVector3Array SailShape::mid_points(const PackedInt32Array& idx) const {
  PackedVector3Array out;
  out.resize(idx.size());
  for (int64_t k = 0; k < idx.size(); ++k) {
    int32_t i = idx[k];
    out.set(k, i >= 0 && static_cast<size_t>(i) < mid_.size() ? mid_[i] : Vector3());
  }
  return out;
}
PackedVector3Array SailShape::positions() const { return to_packed(pos_); }
PackedVector3Array SailShape::normals() const { return to_packed(nrm_); }

bool SailShape::attach_mesh(const RID& mesh) {
  RenderingServer* rs = RenderingServer::get_singleton();
  const Dictionary sd = rs->mesh_get_surface(mesh, 0);
  const int64_t count = sd.has("vertex_count") ? static_cast<int64_t>(sd["vertex_count"]) : 0;
  if (count != 2 * n_) return false;
  const uint64_t fmt = static_cast<uint64_t>(static_cast<int64_t>(sd["format"]));
  if (fmt & Mesh::ARRAY_FLAG_COMPRESS_ATTRIBUTES) return false;
  const auto f = static_cast<BitField<RenderingServer::ArrayFormat>>(fmt);
  if (rs->mesh_surface_get_format_vertex_stride(f, count) != 12) return false;
  mesh_ = mesh;
  bytes_ = sd["vertex_data"];
  noff_ = rs->mesh_surface_get_format_offset(f, count, RenderingServer::ARRAY_NORMAL);
  nstride_ = rs->mesh_surface_get_format_normal_tangent_stride(f, count);
  return noff_ >= 12 * count && nstride_ >= 4 && bytes_.size() >= noff_ + nstride_ * count;
}

void SailShape::encode() {
  if (bytes_.size() < 12 * 2 * n_) return;
  uint8_t* b = bytes_.ptrw();
  std::memcpy(b, pos_.data(), sizeof(float) * 3 * 2 * n_);
  static_assert(sizeof(Vector3) == 12, "Vector3 must be three floats");
  if (nstride_ < 4) return;
  for (int k = 0; k < 2 * n_; ++k) {
    uint16_t o[2];
    oct16(nrm_[k], o);
    std::memcpy(b + noff_ + nstride_ * k, o, 4);
  }
}

PackedByteArray SailShape::vertex_bytes() {
  encode();
  return bytes_;
}

void SailShape::write_mesh() {
  if (!mesh_.is_valid()) return;
  encode();
  RenderingServer::get_singleton()->mesh_surface_update_vertex_region(mesh_, 0, 0, bytes_);
}

void SailShape::_bind_methods() {
  ClassDB::bind_method(D_METHOD("configure", "rest_mid", "rows", "cols", "params"), &SailShape::configure);
  ClassDB::bind_method(D_METHOD("advance", "dt", "aws", "awa", "backed"), &SailShape::advance);
  ClassDB::bind_method(D_METHOD("set_obstacles", "obstacles"), &SailShape::set_obstacles);
  ClassDB::bind_method(D_METHOD("get_ease"), &SailShape::get_ease);
  ClassDB::bind_method(D_METHOD("working_lead", "beta"), &SailShape::working_lead);
  ClassDB::bind_method(D_METHOD("sheet_weight"), &SailShape::sheet_weight);
  ClassDB::bind_method(D_METHOD("sheet_clew"), &SailShape::sheet_clew);
  ClassDB::bind_method(D_METHOD("update", "phase", "progress", "beta", "gamma", "luff_shiver", "awa", "aws"),
                       &SailShape::update);
  ClassDB::bind_method(D_METHOD("get_phase"), &SailShape::get_phase);
  ClassDB::bind_method(D_METHOD("set_phase", "phi"), &SailShape::set_phase);
  ClassDB::bind_method(D_METHOD("get_backed_factor"), &SailShape::get_backed_factor);
  ClassDB::bind_method(D_METHOD("set_backed_factor", "s_b"), &SailShape::set_backed_factor);
  ClassDB::bind_method(D_METHOD("get_twist_side"), &SailShape::get_twist_side);
  ClassDB::bind_method(D_METHOD("get_turn"), &SailShape::get_turn);
  ClassDB::bind_method(D_METHOD("set_turn_step", "dt"), &SailShape::set_turn_step);
  ClassDB::bind_method(D_METHOD("is_loft"), &SailShape::is_loft);
  ClassDB::bind_method(D_METHOD("set_twist_side", "tl"), &SailShape::set_twist_side);
  ClassDB::bind_method(D_METHOD("frame"), &SailShape::frame);
  ClassDB::bind_method(D_METHOD("local_shape"), &SailShape::local_shape);
  ClassDB::bind_method(D_METHOD("mid"), &SailShape::mid);
  ClassDB::bind_method(D_METHOD("mid_points", "indices"), &SailShape::mid_points);
  ClassDB::bind_method(D_METHOD("positions"), &SailShape::positions);
  ClassDB::bind_method(D_METHOD("normals"), &SailShape::normals);
  ClassDB::bind_method(D_METHOD("attach_mesh", "mesh"), &SailShape::attach_mesh);
  ClassDB::bind_method(D_METHOD("vertex_bytes"), &SailShape::vertex_bytes);
  ClassDB::bind_method(D_METHOD("write_mesh"), &SailShape::write_mesh);
  ClassDB::bind_static_method("SailShape", D_METHOD("fill", "v", "g", "k"), &SailShape::fill);
}

}  // namespace windmark_godot
