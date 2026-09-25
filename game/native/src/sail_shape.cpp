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
constexpr float TAU_SMOOTH = 0.25f;
constexpr float DT_MAX = 0.1f;

inline float sgn(float x) { return x >= 0.0f ? 1.0f : -1.0f; }
inline float wrap_pi(float x) {
  float r = std::fmod(x + PI_F, TAU_F);
  if (r < 0.0f) r += TAU_F;
  return r - PI_F;
}
inline float clampf(float x, float a, float b) { return std::min(std::max(x, a), b); }

// Rotation by `angle` about the line through `p` along the unit `axis` (right-handed).
inline Transform3D about(const Vector3& p, const Vector3& axis, float angle) {
  Basis b(axis, angle);
  return Transform3D(b, p - b.xform(p));
}

float getf(const Dictionary& d, const char* key, float def) {
  return d.has(key) ? static_cast<float>(static_cast<double>(d[key])) : def;
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
  depth_ = getf(p, "depth", depth_);
  tack_line_max_ = getf(p, "tack_line_max", tack_line_max_);
  fwd_ = getv(p, "fwd", fwd_);
  port_ = getv(p, "port", port_);
  up_ = getv(p, "up", up_);
  boom_pivot_ = getv(p, "boom_pivot", boom_pivot_);
  boom_axis_ = getv(p, "boom_axis", up_).normalized();
  mast_step_ = getv(p, "mast_step", mast_step_);
  mast_axis_ = getv(p, "mast_axis", up_).normalized();
  phi_ = getf(p, "phi", 0.0f);

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
  }
  furl_radius_ = getf(p, "furl_radius", 0.02f + 0.006f * sa_);
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

float SailShape::head_n(float u, float a, float d_cam, float amp, float shiver) const {
  const float u2 = u * u;
  return 0.5f * d_cam * (u2 * u2 - C_HOOK * u) + amp * shiver * u * std::sin(phi_ - a);
}

Vector3 SailShape::halyard(int k, float p, float d_cam, float amp, float shiver) const {
  const float hc = 1.0f - p;
  if (h_[k] >= hc) return Vector3(a_[k], l_[k] - hc * sl_, head_n(u_[k], a_[k], d_cam, amp, shiver));
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
  return Vector3(a2, l_[k], head_n((a2 - a_min_) / sa_, a2, d_cam, amp, shiver));
}

Vector3 SailShape::fly(int k, int i, const Vector3& w, float shiver) const {
  const float uc = uc_[k];
  const float e = depth_ * c_[i] * 4.0f * uc * (1.0f - uc);
  const float i2 = 0.33f * flutter_amp_ * shiver;
  const float q = phi_ - 7.0f * uc;
  const Vector3 m(w.x + 0.1f * i2 * std::sin(q), w.y, w.z + i2 * std::cos(q));
  Vector3 r = Vector3(a_[k], l_[k], 0.0f) - m * e;
  if (kind_ == SYM) {
    const float hh = 2.0f * h_[k] - 1.0f;
    const float g = std::max(0.0f, shiver - uc) * (1.0f - hh * hh);
    r.x += (amid_[i] - r.x) * 0.5f * g;
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

Vector3 SailShape::drop(int k, float c, const Vector3& f) const {
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
  } else {
    float f_fly;
    if (kind_ == SYM)
      f_fly = std::fabs(static_cast<float>(fill(std::sin(beta), fill_gain_, fill_curve_)));
    else
      f_fly = fill_gain_ * clampf(aws / KNOT, 3.0f, 6.0f) / 6.0f;
    const Vector3 uw = fwd_ * std::cos(awa) - port_ * std::sin(awa);
    w = Vector3(uw.dot(ap) * 0.5f / fill_curve_, uw.dot(lp) * 0.5f, uw.dot(np));
    w = w.length_squared() > 1e-12f ? w.normalized() * f_fly : Vector3(0, 0, f_fly);
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
  for (int i = 0; i < rows_; ++i) {
    for (int j = 0; j < cols_; ++j) {
      const int k = i * cols_ + j;
      Vector3 lc;
      if (kind_ == MAIN) {
        lc = main_shape(k, d_cam, amp, shiver);
      } else if (kind_ == HEADSAIL) {
        if (up_shape)
          lc = Vector3(a_[k], l_[k], head_n(u_[k], a_[k], d_cam, amp, shiver));
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
  // §7 placement, row by row with the twist toward leeward
  for (int i = 0; i < rows_; ++i) {
    const float th = base + tl_ * twist_top_ * std::pow(hrow_[i], 1.5f);
    const Transform3D xr = about(piv, ax, th) * s_t;
    for (int j = 0; j < cols_; ++j) {
      const int k = i * cols_ + j;
      const Vector3& lc = loc_[k];
      mid_[k] = xr.xform(tack_ + ah_ * lc.x + lh_ * lc.y + nh_ * lc.z);
    }
  }
  layers(np);
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
  ClassDB::bind_method(D_METHOD("update", "phase", "progress", "beta", "gamma", "luff_shiver", "awa", "aws"),
                       &SailShape::update);
  ClassDB::bind_method(D_METHOD("get_phase"), &SailShape::get_phase);
  ClassDB::bind_method(D_METHOD("set_phase", "phi"), &SailShape::set_phase);
  ClassDB::bind_method(D_METHOD("get_backed_factor"), &SailShape::get_backed_factor);
  ClassDB::bind_method(D_METHOD("set_backed_factor", "s_b"), &SailShape::set_backed_factor);
  ClassDB::bind_method(D_METHOD("get_twist_side"), &SailShape::get_twist_side);
  ClassDB::bind_method(D_METHOD("set_twist_side", "tl"), &SailShape::set_twist_side);
  ClassDB::bind_method(D_METHOD("frame"), &SailShape::frame);
  ClassDB::bind_method(D_METHOD("local_shape"), &SailShape::local_shape);
  ClassDB::bind_method(D_METHOD("mid"), &SailShape::mid);
  ClassDB::bind_method(D_METHOD("positions"), &SailShape::positions);
  ClassDB::bind_method(D_METHOD("normals"), &SailShape::normals);
  ClassDB::bind_method(D_METHOD("attach_mesh", "mesh"), &SailShape::attach_mesh);
  ClassDB::bind_method(D_METHOD("vertex_bytes"), &SailShape::vertex_bytes);
  ClassDB::bind_method(D_METHOD("write_mesh"), &SailShape::write_mesh);
  ClassDB::bind_static_method("SailShape", D_METHOD("fill", "v", "g", "k"), &SailShape::fill);
}

}  // namespace windmark_godot
