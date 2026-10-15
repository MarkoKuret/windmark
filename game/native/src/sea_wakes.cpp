// Wakes, bow waves and mist: docs/specs/water_render.md §5. See sea_wakes.h.
#include "sea_wakes.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

namespace windmark_godot {

namespace {

constexpr double TAU_D = 6.283185307179586;
constexpr double LIFE_S = 9.0;
constexpr double SPREAD_S = 4.0;  // the edges stop opening (the diverging waves have broken)
constexpr double KELVIN = 0.354;
constexpr double GRAVITY = 9.81;
constexpr double U_OUTER = 0.0;
constexpr double U_EDGE = 0.2;
constexpr int REACH_SMOOTH = 4;
constexpr double TAU_CREST = 0.45;
constexpr double MIST_GRAVITY = 2.0;
constexpr double MIST_DRAG = 2.5;
constexpr double MIST_ALPHA = 0.16;

inline double clampd(double x, double a, double b) { return std::min(std::max(x, a), b); }
// GDScript's smoothstep and lerpf (Math::smoothstep, Math::lerp in double)
inline double smooth(double from, double to, double s) { return Math::smoothstep(from, to, s); }
inline double lerpd(double a, double b, double w) { return a + (b - a) * w; }

double getd(const Dictionary& d, const char* key, double def) {
  return d.has(key) ? static_cast<double>(d[key]) : def;
}

// Godot's ARRAY_COLOR encoding (RenderingServer::_surface_set_data): RGBA8, truncated
inline uint8_t unorm8(float c) { return static_cast<uint8_t>(clampd(static_cast<double>(c) * 255.0, 0.0, 255.0)); }

}  // namespace

// ---------------------------------------------------------------------------------------------------------------
// SeaSampler

void SeaSampler::set_components(const Array& list) {
  comp_.clear();
  for (int64_t i = 0; i < list.size(); ++i) {
    const Array c = list[i];
    // SeaModel keeps T as an int (ms)
    comp_.push_back({static_cast<double>(c[0]), static_cast<double>(c[1]), static_cast<double>(c[2]),
                     static_cast<double>(c[3]), static_cast<double>(static_cast<int64_t>(c[4]))});
  }
}

void SeaSampler::set_exposure(const Dictionary& g) {
  has_expo_ = !g.is_empty() && g.has("e");
  e_.clear();
  if (!has_expo_) return;
  x0_ = g["x0"];
  y0_ = g["y0"];
  dx_ = g["dx"];
  dy_ = g["dy"];
  nx_ = static_cast<int>(static_cast<int64_t>(g["nx"]));
  ny_ = static_cast<int>(static_cast<int64_t>(g["ny"]));
  def_ = getd(g, "default", 1.0);
  const PackedFloat32Array e = g["e"];
  e_.assign(e.ptr(), e.ptr() + e.size());
  has_expo_ = nx_ >= 2 && ny_ >= 2 && static_cast<int64_t>(e_.size()) >= static_cast<int64_t>(nx_) * ny_;
}

double SeaSampler::exposure_at(double x, double y) const {
  if (!has_expo_) return 1.0;
  if (x < x0_ || y < y0_ || x > x0_ + (nx_ - 1) * dx_ || y > y0_ + (ny_ - 1) * dy_) return def_;
  const double u = (x - x0_) / dx_;
  const double v = (y - y0_) / dy_;
  const int i = std::min(static_cast<int>(u), nx_ - 2);
  const int j = std::min(static_cast<int>(v), ny_ - 2);
  const double tx = u - i;
  const double ty = v - j;
  const double r0 = lerpd(e_[j * nx_ + i], e_[j * nx_ + i + 1], tx);
  const double r1 = lerpd(e_[(j + 1) * nx_ + i], e_[(j + 1) * nx_ + i + 1], tx);
  return lerpd(r0, r1, ty);
}

double SeaSampler::height(double x, double y, double t_ms) const {
  double eta = 0.0;
  for (const Comp& c : comp_) {
    const double f = c.kx * x + c.ky * y + c.c - std::fmod(t_ms, c.T) / c.T;
    eta += c.a * std::cos(TAU_D * (f - std::floor(f)));
  }
  return exposure_at(x, y) * eta;
}

void SeaSampler::_bind_methods() {
  ClassDB::bind_method(D_METHOD("set_components", "list"), &SeaSampler::set_components);
  ClassDB::bind_method(D_METHOD("set_exposure", "grid"), &SeaSampler::set_exposure);
  ClassDB::bind_method(D_METHOD("exposure_at", "x", "y"), &SeaSampler::exposure_at);
  ClassDB::bind_method(D_METHOD("height", "x", "y", "t_ms"), &SeaSampler::height);
  ClassDB::bind_method(D_METHOD("component_count"), &SeaSampler::component_count);
}

// ---------------------------------------------------------------------------------------------------------------
// FixedSurface

Array FixedSurface::blank(int64_t n_vert, int64_t n_index) {
  PackedVector3Array v;
  v.resize(n_vert);
  v.fill(Vector3());
  PackedVector2Array uv;
  uv.resize(n_vert);
  uv.fill(Vector2());
  PackedColorArray col;
  col.resize(n_vert);
  col.fill(Color(0, 0, 0, 0));
  PackedInt32Array idx;
  idx.resize(n_index);
  idx.fill(0);
  Array a;
  a.resize(Mesh::ARRAY_MAX);
  a[Mesh::ARRAY_VERTEX] = v;
  a[Mesh::ARRAY_TEX_UV] = uv;
  a[Mesh::ARRAY_TEX_UV2] = uv;
  a[Mesh::ARRAY_COLOR] = col;
  a[Mesh::ARRAY_INDEX] = idx;
  return a;
}

bool FixedSurface::attach(const RID& rid, int64_t verts, int64_t indices) {
  RenderingServer* rs = RenderingServer::get_singleton();
  if (rs->mesh_get_surface_count(rid) < 1) return false;
  const Dictionary sd = rs->mesh_get_surface(rid, 0);
  if (!sd.has("vertex_count") || static_cast<int64_t>(sd["vertex_count"]) != verts) return false;
  if (!sd.has("index_count") || static_cast<int64_t>(sd["index_count"]) != indices) return false;
  const uint64_t fmt = static_cast<int64_t>(sd["format"]);
  const auto f = static_cast<BitField<RenderingServer::ArrayFormat>>(fmt);
  const uint64_t want = RenderingServer::ARRAY_FORMAT_VERTEX | RenderingServer::ARRAY_FORMAT_COLOR |
                        RenderingServer::ARRAY_FORMAT_TEX_UV | RenderingServer::ARRAY_FORMAT_TEX_UV2 |
                        RenderingServer::ARRAY_FORMAT_INDEX;
  if ((fmt & ((uint64_t(1) << RenderingServer::ARRAY_MAX) - 1)) != want) return false;
  if (fmt & RenderingServer::ARRAY_FLAG_COMPRESS_ATTRIBUTES) return false;
  if (rs->mesh_surface_get_format_vertex_stride(f, verts) != 12) return false;
  if (rs->mesh_surface_get_format_index_stride(f, verts) != 2) return false;
  attr_stride = rs->mesh_surface_get_format_attribute_stride(f, verts);
  col_off = rs->mesh_surface_get_format_offset(f, verts, RenderingServer::ARRAY_COLOR);
  uv_off = rs->mesh_surface_get_format_offset(f, verts, RenderingServer::ARRAY_TEX_UV);
  uv2_off = rs->mesh_surface_get_format_offset(f, verts, RenderingServer::ARRAY_TEX_UV2);
  vbytes = sd["vertex_data"];
  abytes = sd["attribute_data"];
  ibytes = sd["index_data"];
  if (vbytes.size() != 12 * verts || abytes.size() != attr_stride * verts || ibytes.size() != 2 * indices)
    return false;
  if (col_off + 4 > attr_stride || uv_off + 8 > attr_stride || uv2_off + 8 > attr_stride) return false;
  mesh = rid;
  n_vert = verts;
  n_index = indices;
  last_idx.assign(indices, 0);
  std::memcpy(last_idx.data(), ibytes.ptr(), 2 * indices);
  return true;
}

void FixedSurface::write(const std::vector<Vector3>& pos, const std::vector<Vector2>& uv,
                         const std::vector<Vector2>& uv2, const std::vector<Color>& col,
                         const std::vector<uint16_t>& idx, bool upload_indices) {
  const int64_t n = std::min<int64_t>(static_cast<int64_t>(pos.size()), n_vert);
  RenderingServer* rs = RenderingServer::get_singleton();
  if (n > 0) {
    uint8_t* v = vbytes.ptrw();
    static_assert(sizeof(Vector3) == 12, "float Vector3");
    std::memcpy(v, pos.data(), 12 * n);
    uint8_t* a = abytes.ptrw();
    for (int64_t k = 0; k < n; ++k) {
      uint8_t* p = a + k * attr_stride;
      const Color& c = col[k];
      const uint8_t c8[4] = {unorm8(c.r), unorm8(c.g), unorm8(c.b), unorm8(c.a)};
      std::memcpy(p + col_off, c8, 4);
      std::memcpy(p + uv_off, &uv[k], 8);
      std::memcpy(p + uv2_off, &uv2[k], 8);
    }
    if (mesh.is_valid()) {
      rs->mesh_surface_update_vertex_region(mesh, 0, 0, n == n_vert ? vbytes : vbytes.slice(0, 12 * n));
      rs->mesh_surface_update_attribute_region(mesh, 0, 0,
                                               n == n_vert ? abytes : abytes.slice(0, attr_stride * n));
    }
  }
  if (!upload_indices) return;
  // indices: only the range that changed since the last upload
  const int64_t m = std::min<int64_t>(static_cast<int64_t>(idx.size()), n_index);
  int64_t lo = -1, hi = -1;
  for (int64_t k = 0; k < n_index; ++k) {
    const uint16_t want = k < m ? idx[k] : 0;
    if (last_idx[k] != want) {
      if (lo < 0) lo = k;
      hi = k;
      last_idx[k] = want;
    }
  }
  if (lo < 0) return;
  std::memcpy(ibytes.ptrw(), last_idx.data(), 2 * n_index);
  // regions are aligned to 4 bytes
  lo &= ~int64_t(1);
  hi = std::min<int64_t>(n_index - 1, hi | 1);
  if (mesh.is_valid()) rs->mesh_surface_update_index_region(mesh, 0, 2 * lo, ibytes.slice(2 * lo, 2 * (hi + 1)));
}

// ---------------------------------------------------------------------------------------------------------------
// WakeRibbon

double WakeRibbon::half_width(const Row& r, double t_s) { return r.w0 + KELVIN * r.v * std::min(t_s - r.t, SPREAD_S); }

double WakeRibbon::alpha(const Row& r, double t_s) {
  if (!r.visible) return 0.0;
  return clampd(1.0 - (t_s - r.t) / LIFE_S, 0.0, 1.0) * std::min(1.0, r.ratio * 2.0);
}

void WakeRibbon::emit(double t_s, const Vector2& p, double heading, double v, double w0, double ratio, bool visible,
                      double dist) {
  Row r;
  r.t = t_s;
  r.p = p;
  r.fwd = Vector2(std::sin(heading), std::cos(heading));
  r.v = v;
  r.w0 = w0;
  r.ratio = ratio;
  r.visible = visible;
  r.dist = dist;
  rows_.push_back(r);
  while (static_cast<int>(rows_.size()) > N_ROWS) rows_.pop_front();
}

PackedVector2Array WakeRibbon::last_edges(double t_s) const {
  PackedVector2Array out;
  if (rows_.empty()) return out;
  const Row& r = rows_.back();
  const Vector2 l = port(r) * half_width(r, t_s);
  out.push_back(r.p + l);
  out.push_back(r.p - l);
  return out;
}

void WakeRibbon::launch_last_spray(double speed, double heel, double z_port, double z_stbd) {
  if (rows_.empty()) return;
  Row& r = rows_.back();
  const Vector2 lp = port(r);
  const Vector2 l = lp * half_width(r, r.t);
  const Vector2 e[2] = {r.p + l, r.p - l};
  const double z[2] = {z_port, z_stbd};
  const double tilt = clampd(heel, Math::deg_to_rad(-10.0), Math::deg_to_rad(10.0));
  for (int side = 0; side < 2 && r.ns < 2; ++side) {
    const Vector2 out = side == 0 ? lp : -lp;
    const Vector3 up(lp.x * std::sin(tilt), lp.y * std::sin(tilt), std::cos(tilt));
    const Vector3 d = Vector3(out.x, out.y, 0.0f) * 0.6 + up * 0.8;
    Spray& s = r.spray[r.ns++];
    s.pos = Vector3(e[side].x, e[side].y, z[side]);
    s.vel = d.normalized() * speed;
    s.landed = false;
  }
}

void WakeRibbon::step(double t_s, double dt, const Ref<SeaSampler>& sea, double t_ms, const Variant& current) {
  while (!rows_.empty() && t_s - rows_.front().t > LIFE_S) rows_.pop_front();
  const bool has_current = current.get_type() == Variant::CALLABLE;
  const Callable cur = has_current ? static_cast<Callable>(current) : Callable();
  for (Row& r : rows_) {
    if (has_current) {
      const Vector2 c = cur.call(r.p.x, r.p.y);
      r.p += c * dt;
      for (int k = 0; k < r.ns; ++k)
        if (r.spray[k].landed) r.spray[k].pos += Vector3(c.x, c.y, 0.0f) * dt;
    }
    for (int k = 0; k < r.ns; ++k) {
      Spray& s = r.spray[k];
      if (s.landed) continue;
      s.vel.z = static_cast<real_t>(static_cast<double>(s.vel.z) - GRAVITY * dt);
      s.pos += s.vel * dt;
      const double h = sea.is_valid() ? sea->height(s.pos.x, s.pos.y, t_ms) : 0.0;
      if (s.pos.z <= h && s.vel.z < 0.0f) {
        s.pos.z = static_cast<real_t>(h);
        s.landed = true;
      }
    }
  }
}

Dictionary WakeRibbon::row(int64_t k) const {
  Dictionary d;
  if (k < 0 || k >= static_cast<int64_t>(rows_.size())) return d;
  const Row& r = rows_[k];
  d["t"] = r.t;
  d["p"] = r.p;
  d["fwd"] = r.fwd;
  d["v"] = r.v;
  d["w0"] = r.w0;
  d["ratio"] = r.ratio;
  d["visible"] = r.visible;
  d["dist"] = r.dist;
  Array sp;
  for (int i = 0; i < r.ns; ++i) {
    Dictionary s;
    s["pos"] = r.spray[i].pos;
    s["vel"] = r.spray[i].vel;
    s["landed"] = r.spray[i].landed;
    sp.push_back(s);
  }
  d["spray"] = sp;
  return d;
}

Vector2 WakeRibbon::spray_excess(const Row& r, double t_s) {
  const double hw = half_width(r, t_s);
  const double base = hw + 0.3 + 0.25 * hw;
  const Vector2 lp = port(r);
  Vector2 out;
  for (int side = 0; side < std::min(r.ns, 2); ++side) {
    const Vector2 q(r.spray[side].pos.x, r.spray[side].pos.y);
    const double d = (q - r.p).dot(side == 0 ? lp : -lp);
    out[side] = static_cast<real_t>(std::max(0.0, d - base));
  }
  return out;
}

void WakeRibbon::build(double t_s) {
  pos_.clear();
  uv_.clear();
  uv2_.clear();
  col_.clear();
  idx_.clear();
  const int n = static_cast<int>(rows_.size());
  excess_.resize(n);
  for (int k = 0; k < n; ++k) excess_[k] = spray_excess(rows_[k], t_s);
  int prev = -1;
  for (int k = n - 1; k >= 0; --k) {
    const Row& r = rows_[k];
    const double a = alpha(r, t_s);
    if (a <= 0.0) {
      prev = -1;
      continue;
    }
    const double hw = half_width(r, t_s);
    const Vector2 lp = port(r);
    const double feather = 0.3 + 0.25 * hw;
    Vector2 ex;
    double wsum = 0.0;
    for (int o = -REACH_SMOOTH; o <= REACH_SMOOTH; ++o) {
      const int kk = k + o;
      if (kk < 0 || kk >= n) continue;
      const double w = static_cast<double>(REACH_SMOOTH + 1 - std::abs(o));
      ex += excess_[kk] * w;
      wsum += w;
    }
    ex /= wsum;
    const double reach[2] = {hw + feather + ex.x, hw + feather + ex.y};
    const int base = static_cast<int>(pos_.size());
    const double centre = clampd(r.w0 / std::max(hw + feather, 1e-3), 0.0, 1.0);
    const float vv = static_cast<float>(r.dist / 10.0);
    const double age = clampd((t_s - r.t) / LIFE_S, 0.0, 1.0);
    for (int i = 0; i < ACROSS; ++i) {
      const double u = i == 0 ? U_OUTER
                              : (i == ACROSS - 1 ? 1.0 - U_OUTER
                                                 : U_EDGE + (1.0 - 2.0 * U_EDGE) * double(i - 1) / double(ACROSS - 3));
      double off;
      if (i == 0)
        off = reach[0];
      else if (i == ACROSS - 1)
        off = -reach[1];
      else
        off = hw * (1.0 - 2.0 * double(i - 1) / double(ACROSS - 3));
      const Vector2 q = r.p + lp * off;
      pos_.emplace_back(q.x, 0.0f, -q.y);
      uv_.emplace_back(static_cast<real_t>(u), vv);
      uv2_.push_back(lp);
      col_.emplace_back(static_cast<float>(centre), static_cast<float>(age), 1.0f,
                        (i == 0 || i == ACROSS - 1) ? 0.0f : static_cast<float>(a));
    }
    if (prev >= 0) {
      for (int i = 0; i < ACROSS - 1; ++i) {
        const uint16_t t[6] = {uint16_t(prev + i), uint16_t(base + i), uint16_t(base + i + 1),
                               uint16_t(prev + i), uint16_t(base + i + 1), uint16_t(prev + i + 1)};
        idx_.insert(idx_.end(), t, t + 6);
      }
    }
    prev = base;
  }
}

Array WakeRibbon::build_arrays(double t_s) {
  build(t_s);
  PackedVector3Array v;
  PackedVector2Array uv, uv2;
  PackedColorArray col;
  PackedInt32Array idx;
  for (size_t k = 0; k < pos_.size(); ++k) {
    v.push_back(pos_[k]);
    uv.push_back(uv_[k]);
    uv2.push_back(uv2_[k]);
    col.push_back(col_[k]);
  }
  for (uint16_t i : idx_) idx.push_back(i);
  Array a;
  a.resize(Mesh::ARRAY_MAX);
  a[Mesh::ARRAY_VERTEX] = v;
  a[Mesh::ARRAY_TEX_UV] = uv;
  a[Mesh::ARRAY_TEX_UV2] = uv2;
  a[Mesh::ARRAY_COLOR] = col;
  a[Mesh::ARRAY_INDEX] = idx;
  return a;
}

bool WakeRibbon::attach_mesh(const RID& mesh) { return surf_.attach(mesh, N_ROWS * ACROSS, MAX_INDEX); }

bool WakeRibbon::write_mesh(double t_s) {
  build(t_s);
  surf_.write(pos_, uv_, uv2_, col_, idx_, true);
  if (pos_.empty() || idx_.empty()) return false;
  if (surf_.mesh.is_valid()) {
    // the bounds of the laid rows, with room for the drape on the sea and the pull toward the camera
    Vector3 lo = pos_[0], hi = pos_[0];
    for (const Vector3& p : pos_) {
      lo = lo.min(p);
      hi = hi.max(p);
    }
    lo -= Vector3(1.0f, 10.0f, 1.0f);
    hi += Vector3(1.0f, 10.0f, 1.0f);
    RenderingServer::get_singleton()->mesh_set_custom_aabb(surf_.mesh, AABB(lo, hi - lo));
  }
  return true;
}

void WakeRibbon::_bind_methods() {
  ClassDB::bind_method(D_METHOD("emit", "t_s", "p", "heading", "v", "w0", "ratio", "visible", "dist"),
                       &WakeRibbon::emit);
  ClassDB::bind_method(D_METHOD("last_edges", "t_s"), &WakeRibbon::last_edges);
  ClassDB::bind_method(D_METHOD("launch_last_spray", "speed", "heel", "z_port", "z_stbd"),
                       &WakeRibbon::launch_last_spray);
  ClassDB::bind_method(D_METHOD("step", "t_s", "dt", "sea", "t_ms", "current"), &WakeRibbon::step);
  ClassDB::bind_method(D_METHOD("row_count"), &WakeRibbon::row_count);
  ClassDB::bind_method(D_METHOD("row", "k"), &WakeRibbon::row);
  ClassDB::bind_method(D_METHOD("build_arrays", "t_s"), &WakeRibbon::build_arrays);
  ClassDB::bind_method(D_METHOD("blank_arrays"), &WakeRibbon::blank_arrays);
  ClassDB::bind_method(D_METHOD("attach_mesh", "mesh"), &WakeRibbon::attach_mesh);
  ClassDB::bind_method(D_METHOD("write_mesh", "t_s"), &WakeRibbon::write_mesh);
  ClassDB::bind_method(D_METHOD("vertex_bytes"), &WakeRibbon::vertex_bytes);
  ClassDB::bind_method(D_METHOD("attribute_bytes"), &WakeRibbon::attribute_bytes);
  ClassDB::bind_method(D_METHOD("index_bytes"), &WakeRibbon::index_bytes);
}

// ---------------------------------------------------------------------------------------------------------------
// BowWaveSheets

bool BowWaveSheets::build(const Dictionary& st, double v, double ratio, double plunge) {
  pos_.clear();
  uv_.clear();
  uv2_.clear();
  col_.clear();
  const double k = smooth(0.25, 0.6, ratio);
  if (k <= 0.0) return false;
  const double lwl = getd(st, "lwl", 6.0);
  const double bwl = getd(st, "bwl", 2.0);
  const double psi = getd(st, "psi", 0.0);
  const double heel = getd(st, "heel", 0.0);
  const Vector2 fwd(std::sin(psi), std::cos(psi));
  const Vector2 port(-fwd.y, fwd.x);
  const Vector2 pos(getd(st, "x", 0.0), getd(st, "y", 0.0));
  const Vector2 stem = pos + fwd * getd(st, "bow_x", 0.5 * lwl);
  // BowWave.size, kept as a (float) Vector2 like the reference
  const double pl = std::min(plunge, 1.5);
  const Vector2 hl(std::min(0.08 * lwl, 0.55 * v * v / (2.0 * GRAVITY)) * (1.0 + 0.6 * pl),
                   lwl * (0.18 + 0.22 * std::min(ratio, 1.3)) * (1.0 + 0.3 * pl));
  const double sh = std::fabs(std::sin(heel));
  for (int side = 0; side < 2; ++side) {
    const double sgn = side == 0 ? 1.0 : -1.0;
    const double lee = (heel > 0.0 ? -1.0 : 1.0) * sgn;
    const double hs = 1.0 + 0.6 * lee * sh;
    for (int i = 0; i < NS; ++i) {
      const double sg = double(i) / double(NS - 1);
      const double along = sg * hl.y;
      const double yh = 0.5 * bwl * std::pow(std::min(1.0, along / (0.5 * lwl)), 0.7) * (1.0 + 0.5 * lee * sh);
      const double width = (0.12 + 0.5 * along) * (1.0 + 0.3 * ratio);
      const double li = hl.x * hs * std::pow(1.0 - sg, 1.6);
      const double lc = 0.75 * hl.x * hs * std::pow(1.0 - sg, 0.7);
      const double a = k * smooth(0.0, 0.08, sg) * (1.0 - smooth(0.7, 1.0, sg));
      const Vector2 row = stem - fwd * along;
      const Vector2 ps = port * sgn;
      for (int j = 0; j < NT; ++j) {
        const double tau = double(j) / double(NT - 1);
        const double lift = tau <= TAU_CREST ? lerpd(li, lc, smooth(0.0, TAU_CREST, tau))
                                             : lc * (1.0 - smooth(TAU_CREST, 1.0, tau));
        const Vector2 q = row + ps * (yh - 0.02 + tau * width);
        pos_.emplace_back(q.x, 0.0f, -q.y);
        uv_.emplace_back(static_cast<real_t>(tau), static_cast<real_t>(sg));
        uv2_.emplace_back(static_cast<real_t>(lift + 0.1), static_cast<real_t>(along));
        col_.emplace_back(0.0f, 0.0f, 0.0f, static_cast<float>(a));
      }
    }
  }
  return true;
}

Array BowWaveSheets::build_arrays(const Dictionary& st, double v, double ratio, double plunge) {
  Array a;
  a.resize(Mesh::ARRAY_MAX);
  if (!build(st, v, ratio, plunge)) return a;
  PackedVector3Array pv;
  PackedVector2Array uv, uv2;
  PackedColorArray col;
  for (size_t k = 0; k < pos_.size(); ++k) {
    pv.push_back(pos_[k]);
    uv.push_back(uv_[k]);
    uv2.push_back(uv2_[k]);
    col.push_back(col_[k]);
  }
  const Array blank = blank_arrays();
  a[Mesh::ARRAY_VERTEX] = pv;
  a[Mesh::ARRAY_TEX_UV] = uv;
  a[Mesh::ARRAY_TEX_UV2] = uv2;
  a[Mesh::ARRAY_COLOR] = col;
  a[Mesh::ARRAY_INDEX] = blank[Mesh::ARRAY_INDEX];
  return a;
}

Array BowWaveSheets::blank_arrays() const {
  Array a = FixedSurface::blank(N_VERT, N_INDEX);
  PackedInt32Array idx;
  for (int side = 0; side < 2; ++side) {
    const int base = side * NS * NT;
    for (int i = 0; i < NS - 1; ++i)
      for (int j = 0; j < NT - 1; ++j) {
        const int v0 = base + i * NT + j;
        const int t[6] = {v0, v0 + NT, v0 + 1, v0 + 1, v0 + NT, v0 + NT + 1};
        for (int x : t) idx.push_back(x);
      }
  }
  a[Mesh::ARRAY_INDEX] = idx;
  return a;
}

bool BowWaveSheets::attach_mesh(const RID& mesh) { return surf_.attach(mesh, N_VERT, N_INDEX); }

bool BowWaveSheets::write_mesh(const Dictionary& st, double v, double ratio, double plunge) {
  if (!build(st, v, ratio, plunge)) return false;
  surf_.write(pos_, uv_, uv2_, col_, idx_, false);
  if (surf_.mesh.is_valid()) {
    // every frame the sheet moves with the boat: keep it from being culled on stale bounds
    RenderingServer::get_singleton()->mesh_set_custom_aabb(
        surf_.mesh, AABB(pos_[0] - Vector3(20.0f, 10.0f, 20.0f), Vector3(40.0f, 20.0f, 40.0f)));
  }
  return true;
}

void BowWaveSheets::_bind_methods() {
  ClassDB::bind_method(D_METHOD("build_arrays", "state", "v", "ratio", "plunge"), &BowWaveSheets::build_arrays);
  ClassDB::bind_method(D_METHOD("blank_arrays"), &BowWaveSheets::blank_arrays);
  ClassDB::bind_method(D_METHOD("attach_mesh", "mesh"), &BowWaveSheets::attach_mesh);
  ClassDB::bind_method(D_METHOD("write_mesh", "state", "v", "ratio", "plunge"), &BowWaveSheets::write_mesh);
  ClassDB::bind_method(D_METHOD("vertex_bytes"), &BowWaveSheets::vertex_bytes);
  ClassDB::bind_method(D_METHOD("attribute_bytes"), &BowWaveSheets::attribute_bytes);
}

// ---------------------------------------------------------------------------------------------------------------
// MistCloud

void MistCloud::add(const Dictionary& m) {
  if (static_cast<int>(m_.size()) >= MAX) return;
  Sprite s;
  s.pos = m["pos"];
  s.vel = m["vel"];
  s.age = getd(m, "age", 0.0);
  s.life = getd(m, "life", 1.0);
  s.s0 = getd(m, "s0", 0.5);
  s.s1 = getd(m, "s1", 1.2);
  s.seed = getd(m, "seed", 0.0);
  s.a = getd(m, "a", 1.0);
  m_.push_back(s);
}

void MistCloud::step(double dt) {
  size_t w = 0;
  const double drag = std::exp(-MIST_DRAG * dt);
  for (size_t k = 0; k < m_.size(); ++k) {
    Sprite s = m_[k];
    s.age += dt;
    if (s.age >= s.life) continue;
    Vector3 v = s.vel * drag;
    v.z = static_cast<real_t>(static_cast<double>(v.z) - MIST_GRAVITY * dt);
    s.vel = v;
    s.pos += v * dt;
    m_[w++] = s;
  }
  m_.resize(w);
}

Array MistCloud::sprites() const {
  Array out;
  for (const Sprite& s : m_) {
    Dictionary d;
    d["pos"] = s.pos;
    d["vel"] = s.vel;
    d["age"] = s.age;
    d["life"] = s.life;
    d["s0"] = s.s0;
    d["s1"] = s.s1;
    d["seed"] = s.seed;
    d["a"] = s.a;
    out.push_back(d);
  }
  return out;
}

PackedFloat32Array MistCloud::buffer() {
  if (buf_.size() != MAX * STRIDE) {
    buf_.resize(MAX * STRIDE);
    buf_.fill(0.0f);
  }
  float* b = buf_.ptrw();
  for (size_t i = 0; i < m_.size(); ++i) {
    const Sprite& s = m_[i];
    // BowWave.mist_look: size and alpha, kept as a (float) Vector2 like the reference
    const double f = s.age / s.life;
    const float size = static_cast<float>(lerpd(s.s0, s.s1, std::sqrt(f)));
    const float a = static_cast<float>(MIST_ALPHA * s.a * clampd(s.age / 0.12, 0.0, 1.0) * (1.0 - f) * (1.0 - f));
    float* o = b + i * STRIDE;
    const float t[STRIDE] = {size, 0, 0, s.pos.x, 0, size, 0, s.pos.z, 0, 0, size, -s.pos.y,
                             a,    static_cast<float>(s.seed), 0, 0};
    std::memcpy(o, t, sizeof(t));
  }
  // the instances that lived out since the last buffer: zero, as a fresh buffer
  for (size_t i = m_.size(); i < last_n_; ++i) std::memset(b + i * STRIDE, 0, sizeof(float) * STRIDE);
  last_n_ = m_.size();
  return buf_;
}

void MistCloud::write_multimesh(const RID& mm) {
  RenderingServer* rs = RenderingServer::get_singleton();
  rs->multimesh_set_buffer(mm, buffer());
  rs->multimesh_set_visible_instances(mm, static_cast<int32_t>(m_.size()));
}

void MistCloud::_bind_methods() {
  ClassDB::bind_method(D_METHOD("add", "sprite"), &MistCloud::add);
  ClassDB::bind_method(D_METHOD("count"), &MistCloud::count);
  ClassDB::bind_method(D_METHOD("step", "dt"), &MistCloud::step);
  ClassDB::bind_method(D_METHOD("sprites"), &MistCloud::sprites);
  ClassDB::bind_method(D_METHOD("buffer"), &MistCloud::buffer);
  ClassDB::bind_method(D_METHOD("write_multimesh", "multimesh"), &MistCloud::write_multimesh);
}

}  // namespace windmark_godot
