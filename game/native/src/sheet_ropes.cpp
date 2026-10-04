// SheetRopes: docs/specs/sail_visuals.md §11.3. See sheet_ropes.h.
#include "sheet_ropes.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

namespace windmark_godot {

namespace {

constexpr float TAU_F = 6.28318530717959f;
constexpr float NO_DECK = -1.0e9f;
constexpr float WHIP_WAVE = 1.5f;  // m, wavelength of the whip along a flogging sheet

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
  ox = std::min(std::max(ox * 0.5f + 0.5f, 0.0f), 1.0f);
  oy = std::min(std::max(oy * 0.5f + 0.5f, 0.0f), 1.0f);
  out[0] = static_cast<uint16_t>(ox * 65535.0f);
  out[1] = static_cast<uint16_t>(oy * 65535.0f);
}

// Godot's tangent encoding (Vector3::octahedron_tangent_encode with the binormal sign in y), as the mesh stores it.
inline void oct16_tangent(const Vector3& v, float sign, uint16_t out[2]) {
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
  oy = std::max(oy, 1.0f / 32767.0f);
  oy = oy * 0.5f + 0.5f;
  oy = sign >= 0.0f ? oy : 1.0f - oy;
  out[0] = static_cast<uint16_t>(std::min(std::max(ox * 65535.0f, 0.0f), 65535.0f));
  out[1] = static_cast<uint16_t>(std::min(std::max(oy * 65535.0f, 0.0f), 65535.0f));
  if (out[0] == 0 && out[1] == 65535) out[0] = 65535;
}

// the binormal sign of the tube: cross(normal, along) points against the way round (+v)
constexpr float TANGENT_SIGN = -1.0f;

float getf(const Dictionary& d, const char* key, float def) {
  return d.has(key) ? static_cast<float>(static_cast<double>(d[key])) : def;
}

int geti(const Dictionary& d, const char* key, int def) {
  return d.has(key) ? static_cast<int>(static_cast<int64_t>(d[key])) : def;
}

// The point at arc length `s` along the polyline p[0..n-1] with cumulative lengths c.
Vector3 along(const Vector3* p, const float* c, int n, float s) {
  for (int k = 1; k < n; ++k) {
    if (s <= c[k] || k == n - 1) {
      const float seg = c[k] - c[k - 1];
      const float t = seg > 1e-9f ? std::min(std::max((s - c[k - 1]) / seg, 0.0f), 1.0f) : 0.0f;
      return p[k - 1] + (p[k] - p[k - 1]) * t;
    }
  }
  return p[0];
}

// A unit vector square to `a` and to `g` (the sideways direction of a hanging span).
Vector3 side_of(const Vector3& a, const Vector3& g) {
  Vector3 s = a.cross(g);
  if (s.length_squared() < 1e-12f) s = Vector3(1, 0, 0).cross(g);
  if (s.length_squared() < 1e-12f) s = Vector3(0, 0, 1).cross(g);
  return s.normalized();
}

}  // namespace

bool SheetRopes::configure(const Dictionary& params) {
  sides_ = std::max(3, geti(params, "sides", 6));
  tile_ = getf(params, "tile", 0.05f);
  lines_.clear();
  const Array lines = params.get("lines", Array());
  int ring = 0;
  for (int64_t i = 0; i < lines.size(); ++i) {
    const Dictionary d = lines[i];
    Line l;
    l.radius = getf(d, "radius", 0.005f);
    l.free_rings = std::max(2, geti(d, "free_rings", 16));
    l.lead_rings = std::max(0, geti(d, "lead_rings", 0));
    l.anchor = d.get("anchor", Vector3());
    const PackedVector3Array fx = d.get("fixed", PackedVector3Array());
    for (int64_t k = 0; k < fx.size(); ++k) l.fixed.push_back(fx[k]);
    if (l.lead_rings > 0 && l.fixed.empty()) return false;  // a lead run needs its drum entry
    if (l.lead_rings == 0) l.fixed.clear();
    l.first_ring = ring;
    l.rings = l.free_rings + (l.lead_rings > 0 ? l.lead_rings + static_cast<int>(l.fixed.size()) - 1 : 0);
    ring += l.rings;
    lines_.push_back(l);
  }
  nr_ = ring;
  const int per = sides_ + 1;
  nv_ = nr_ * per;
  ring_.assign(nr_, Vector3());
  ring_len_.assign(nr_, 0.0f);
  pos_.assign(nv_, Vector3());
  nrm_.assign(nv_, Vector3(0, 1, 0));
  tan_.assign(nv_, Vector3(0, 0, 1));
  uv_.assign(2 * nv_, 0.0f);
  idx_.clear();
  for (const Line& l : lines_) {
    for (int k = 0; k + 1 < l.rings; ++k) {
      const int a = (l.first_ring + k) * per;
      const int b = a + per;
      for (int j = 0; j < sides_; ++j) {
        // clockwise seen from outside: Godot's front faces
        idx_.push_back(a + j);
        idx_.push_back(b + j);
        idx_.push_back(b + j + 1);
        idx_.push_back(a + j);
        idx_.push_back(b + j + 1);
        idx_.push_back(a + j + 1);
      }
    }
  }
  deck_.clear();
  dnx_ = dnz_ = 0;
  if (params.has("deck")) {
    const Dictionary dk = params["deck"];
    const PackedFloat32Array h = dk.get("heights", PackedFloat32Array());
    dnx_ = geti(dk, "nx", 0);
    dnz_ = geti(dk, "nz", 0);
    dcell_ = getf(dk, "cell", 0.05f);
    const Vector2 o = dk.get("origin", Vector2());
    dx0_ = o.x;
    dz0_ = o.y;
    if (h.size() == static_cast<int64_t>(dnx_) * dnz_ && dnx_ > 1 && dnz_ > 1) {
      deck_.resize(h.size());
      std::memcpy(deck_.data(), h.ptr(), sizeof(float) * h.size());
    } else {
      dnx_ = dnz_ = 0;
    }
  }
  return nr_ > 0;
}

float SheetRopes::deck_at(float x, float z) const {
  if (deck_.empty()) return NO_DECK;
  const float fx = (x - dx0_) / dcell_;
  const float fz = (z - dz0_) / dcell_;
  if (fx < 0.0f || fz < 0.0f || fx > dnx_ - 1 || fz > dnz_ - 1) return NO_DECK;
  const int ix = std::min(static_cast<int>(fx), dnx_ - 2);
  const int iz = std::min(static_cast<int>(fz), dnz_ - 2);
  const float tx = fx - ix, tz = fz - iz;
  const float h00 = deck_[iz * dnx_ + ix], h10 = deck_[iz * dnx_ + ix + 1];
  const float h01 = deck_[(iz + 1) * dnx_ + ix], h11 = deck_[(iz + 1) * dnx_ + ix + 1];
  if (h00 <= NO_DECK || h10 <= NO_DECK || h01 <= NO_DECK || h11 <= NO_DECK) {
    return std::max(std::max(h00, h10), std::max(h01, h11));  // at the deck's edge: the highest neighbour
  }
  return (h00 * (1 - tx) + h10 * tx) * (1 - tz) + (h01 * (1 - tx) + h11 * tx) * tz;
}

double SheetRopes::deck_height(double x, double z) const { return deck_at(static_cast<float>(x), static_cast<float>(z)); }

void SheetRopes::update(const PackedVector3Array& starts, const PackedVector3Array& ways,
                        const PackedFloat32Array& drive, const Vector3& gravity) {
  const Vector3 g = gravity.length_squared() > 1e-12f ? gravity.normalized() : Vector3(0, -1, 0);
  const int per = sides_ + 1;
  for (size_t i = 0; i < lines_.size(); ++i) {
    const Line& l = lines_[i];
    const int64_t ii = static_cast<int64_t>(i);
    const Vector3 s0 = ii < starts.size() ? starts[ii] : l.anchor;
    const float* dv = drive.size() >= (ii + 1) * DRIVE ? drive.ptr() + ii * DRIVE : nullptr;
    const bool shown = dv != nullptr && dv[0] > 0.5f;
    Vector3* r = ring_.data() + l.first_ring;
    if (!shown) {
      for (int k = 0; k < l.rings; ++k) r[k] = s0;
    } else {
      const float sag_f = dv[1], sag_l = dv[2], psi = dv[3], whip = dv[4], phi = dv[5];
      // the free run: start, waypoint (when given), anchor
      Vector3 p[3];
      float c[3];
      int n = 0;
      p[n++] = s0;
      if (ii < ways.size()) {
        const Vector3 w = ways[ii];
        if (!std::isnan(w.x)) p[n++] = w;
      }
      p[n++] = l.anchor;
      c[0] = 0.0f;
      for (int k = 1; k < n; ++k) c[k] = c[k - 1] + (p[k] - p[k - 1]).length();
      const float len = c[n - 1];
      const Vector3 side = side_of(l.anchor - s0, g);
      const Vector3 sag = (g * std::cos(psi) + side * std::sin(psi)) * (len * sag_f);
      const int nf = l.free_rings;
      for (int k = 0; k < nf; ++k) {
        const float t = static_cast<float>(k) / static_cast<float>(nf - 1);
        const float s = t * len;
        const float b = 4.0f * t * (1.0f - t);
        Vector3 q = along(p, c, n, s) + sag * b + side * (b * whip * len * std::sin(phi - TAU_F * s / WHIP_WAVE));
        if (k > 0 && k < nf - 1) q.y = std::max(q.y, deck_at(q.x, q.z) + l.radius);
        r[k] = q;
      }
      if (l.lead_rings > 0) {
        const Vector3 a = l.anchor, e = l.fixed[0];
        const float len2 = (e - a).length();
        const Vector3 sag2 = g * (len2 * sag_l);
        for (int k = 1; k <= l.lead_rings; ++k) {
          const float t = static_cast<float>(k) / static_cast<float>(l.lead_rings);
          Vector3 q = a + (e - a) * t + sag2 * (4.0f * t * (1.0f - t));
          if (k < l.lead_rings) q.y = std::max(q.y, deck_at(q.x, q.z) + l.radius);
          r[nf - 1 + k] = q;
        }
        for (size_t k = 1; k < l.fixed.size(); ++k) r[nf - 1 + l.lead_rings + static_cast<int>(k)] = l.fixed[k];
      }
    }
    // frames (parallel transport) and the tube
    float acc = 0.0f;
    Vector3 nprev;
    for (int k = 0; k < l.rings; ++k) {
      const int a = std::max(k - 1, 0), b = std::min(k + 1, l.rings - 1);
      Vector3 t = r[b] - r[a];
      if (k > 0) acc += (r[k] - r[k - 1]).length();
      ring_len_[l.first_ring + k] = acc;
      if (t.length_squared() < 1e-14f) t = k > 0 ? Vector3() : Vector3(0, 0, 1);
      t = t.length_squared() > 1e-14f ? t.normalized() : Vector3(0, 0, 1);
      Vector3 nn;
      if (k == 0) {
        const Vector3 ref = std::fabs(t.y) < 0.9f ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
        nn = t.cross(ref);
      } else {
        nn = nprev - t * nprev.dot(t);
        if (nn.length_squared() < 1e-10f) {
          const Vector3 ref = std::fabs(t.y) < 0.9f ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
          nn = t.cross(ref);
        }
      }
      nn = nn.normalized();
      nprev = nn;
      const Vector3 bb = t.cross(nn);
      const int base = (l.first_ring + k) * per;
      for (int j = 0; j <= sides_; ++j) {
        const float th = TAU_F * static_cast<float>(j) / static_cast<float>(sides_);
        const Vector3 d = nn * std::cos(th) + bb * std::sin(th);
        pos_[base + j] = r[k] + d * l.radius;
        nrm_[base + j] = d;
        tan_[base + j] = t;
        uv_[2 * (base + j)] = acc;
        uv_[2 * (base + j) + 1] = tile_ * static_cast<float>(j) / static_cast<float>(sides_);
      }
    }
  }
}

PackedInt32Array SheetRopes::indices() const {
  PackedInt32Array out;
  out.resize(static_cast<int64_t>(idx_.size()));
  if (!idx_.empty()) std::memcpy(out.ptrw(), idx_.data(), idx_.size() * sizeof(int32_t));
  return out;
}

PackedVector3Array SheetRopes::positions() const {
  PackedVector3Array out;
  out.resize(nv_);
  if (nv_ > 0) std::memcpy(out.ptrw(), pos_.data(), sizeof(Vector3) * nv_);
  return out;
}

PackedFloat32Array SheetRopes::tangents() const {
  PackedFloat32Array out;
  out.resize(4 * nv_);
  float* w = out.ptrw();
  for (int k = 0; k < nv_; ++k) {
    w[4 * k] = tan_[k].x;
    w[4 * k + 1] = tan_[k].y;
    w[4 * k + 2] = tan_[k].z;
    w[4 * k + 3] = TANGENT_SIGN;
  }
  return out;
}

PackedVector3Array SheetRopes::normals() const {
  PackedVector3Array out;
  out.resize(nv_);
  if (nv_ > 0) std::memcpy(out.ptrw(), nrm_.data(), sizeof(Vector3) * nv_);
  return out;
}

PackedVector2Array SheetRopes::uvs() const {
  PackedVector2Array out;
  out.resize(nv_);
  for (int k = 0; k < nv_; ++k) out.set(k, Vector2(uv_[2 * k], uv_[2 * k + 1]));
  return out;
}

PackedVector3Array SheetRopes::centre(int64_t line) const {
  PackedVector3Array out;
  if (line < 0 || line >= static_cast<int64_t>(lines_.size())) return out;
  const Line& l = lines_[line];
  out.resize(l.rings);
  for (int k = 0; k < l.rings; ++k) out.set(k, ring_[l.first_ring + k]);
  return out;
}

bool SheetRopes::attach_mesh(const RID& mesh, int64_t surface) {
  RenderingServer* rs = RenderingServer::get_singleton();
  const Dictionary sd = rs->mesh_get_surface(mesh, surface);
  const int64_t count = sd.has("vertex_count") ? static_cast<int64_t>(sd["vertex_count"]) : 0;
  if (count != nv_) return false;
  const uint64_t fmt = static_cast<uint64_t>(static_cast<int64_t>(sd["format"]));
  if (fmt & Mesh::ARRAY_FLAG_COMPRESS_ATTRIBUTES) return false;
  if (!(fmt & Mesh::ARRAY_FORMAT_TEX_UV)) return false;
  const auto f = static_cast<BitField<RenderingServer::ArrayFormat>>(fmt);
  if (rs->mesh_surface_get_format_vertex_stride(f, count) != 12) return false;
  mesh_ = mesh;
  surface_ = surface;
  vbytes_ = sd["vertex_data"];
  abytes_ = sd["attribute_data"];
  noff_ = rs->mesh_surface_get_format_offset(f, count, RenderingServer::ARRAY_NORMAL);
  nstride_ = rs->mesh_surface_get_format_normal_tangent_stride(f, count);
  astride_ = rs->mesh_surface_get_format_attribute_stride(f, count);
  uvoff_ = rs->mesh_surface_get_format_offset(f, count, RenderingServer::ARRAY_TEX_UV);
  return noff_ >= 12 * count && nstride_ >= 4 && vbytes_.size() >= noff_ + nstride_ * count && astride_ >= 8 &&
         uvoff_ + 8 <= astride_ && abytes_.size() >= astride_ * count;
}

void SheetRopes::encode() {
  if (vbytes_.size() < 12 * nv_) return;
  uint8_t* b = vbytes_.ptrw();
  static_assert(sizeof(Vector3) == 12, "Vector3 must be three floats");
  std::memcpy(b, pos_.data(), sizeof(float) * 3 * nv_);
  if (nstride_ >= 4) {
    for (int k = 0; k < nv_; ++k) {
      uint16_t o[2];
      oct16(nrm_[k], o);
      std::memcpy(b + noff_ + nstride_ * k, o, 4);
      if (nstride_ >= 8) {
        oct16_tangent(tan_[k], TANGENT_SIGN, o);
        std::memcpy(b + noff_ + nstride_ * k + 4, o, 4);
      }
    }
  }
  if (astride_ >= 8 && abytes_.size() >= astride_ * nv_) {
    uint8_t* a = abytes_.ptrw();
    for (int k = 0; k < nv_; ++k) std::memcpy(a + astride_ * k + uvoff_, &uv_[2 * k], 8);
  }
}

PackedByteArray SheetRopes::vertex_bytes() {
  encode();
  return vbytes_;
}

PackedByteArray SheetRopes::attribute_bytes() {
  encode();
  return abytes_;
}

void SheetRopes::write_mesh() {
  if (!mesh_.is_valid()) return;
  encode();
  RenderingServer* rs = RenderingServer::get_singleton();
  rs->mesh_surface_update_vertex_region(mesh_, surface_, 0, vbytes_);
  rs->mesh_surface_update_attribute_region(mesh_, surface_, 0, abytes_);
}

void SheetRopes::_bind_methods() {
  ClassDB::bind_method(D_METHOD("configure", "params"), &SheetRopes::configure);
  ClassDB::bind_method(D_METHOD("update", "starts", "ways", "drive", "gravity"), &SheetRopes::update);
  ClassDB::bind_method(D_METHOD("get_line_count"), &SheetRopes::get_line_count);
  ClassDB::bind_method(D_METHOD("get_vertex_count"), &SheetRopes::get_vertex_count);
  ClassDB::bind_method(D_METHOD("indices"), &SheetRopes::indices);
  ClassDB::bind_method(D_METHOD("positions"), &SheetRopes::positions);
  ClassDB::bind_method(D_METHOD("normals"), &SheetRopes::normals);
  ClassDB::bind_method(D_METHOD("tangents"), &SheetRopes::tangents);
  ClassDB::bind_method(D_METHOD("uvs"), &SheetRopes::uvs);
  ClassDB::bind_method(D_METHOD("centre", "line"), &SheetRopes::centre);
  ClassDB::bind_method(D_METHOD("deck_height", "x", "z"), &SheetRopes::deck_height);
  ClassDB::bind_method(D_METHOD("attach_mesh", "mesh", "surface"), &SheetRopes::attach_mesh);
  ClassDB::bind_method(D_METHOD("vertex_bytes"), &SheetRopes::vertex_bytes);
  ClassDB::bind_method(D_METHOD("attribute_bytes"), &SheetRopes::attribute_bytes);
  ClassDB::bind_method(D_METHOD("write_mesh"), &SheetRopes::write_mesh);
}

}  // namespace windmark_godot
