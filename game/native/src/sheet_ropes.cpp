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
constexpr float DRAPE_STEP = 0.025f;  // m, the drape's sample step along a tube (under the field's widening)
constexpr double PI_D = 3.14159265358979;
constexpr double ROUTE_FADE = 0.1;  // rad, the angle over which an obstacle point fades in at an end of a route
constexpr double ROUTE_UNDER = 0.1;  // m above the straight line from which an obstacle point lets the line under
constexpr double ROUTE_UNDER_FADE = 0.2;  // m over which it fades out

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
      dmax_ = NO_DECK;
      for (float v : deck_) dmax_ = std::max(dmax_, v);
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
  const int64_t nlines = static_cast<int64_t>(lines_.size());
  const int64_t slots = nlines > 0 ? std::min<int64_t>(ways.size() / nlines, MAX_WAYS) : 0;
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
      // the free run: start, its waypoints (the unused slots NaN), anchor
      pts_.clear();
      pts_.push_back(s0);
      for (int64_t j = 0; j < slots; ++j) {
        const Vector3 w = ways[ii * slots + j];
        if (!std::isnan(w.x)) pts_.push_back(w);
      }
      pts_.push_back(l.anchor);
      const int n = static_cast<int>(pts_.size());
      const Vector3* p = pts_.data();
      cum_.assign(n, 0.0f);
      float* c = cum_.data();
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
      drape(r, nf, l.radius);
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
        drape(r + nf - 1, l.lead_rings + 1, l.radius);
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

// §11.3 "Deck": lifts the rings of a run (its ends fixed) so the straight tube between each pair clears the field at
// every DRAPE_STEP, by the least lift of the pair. One pass: a lift only raises the tubes either side of a ring, so a
// point already clear stays clear.
void SheetRopes::drape(Vector3* r, int n, float radius) const {
  if (deck_.empty() || n < 3) return;
  {
    for (int k = 0; k + 1 < n; ++k) {
      Vector3& p0 = r[k];
      Vector3& p1 = r[k + 1];
      if (std::min(p0.y, p1.y) > dmax_ + radius) continue;
      const float dx = p1.x - p0.x, dz = p1.z - p0.z;
      const int m = std::min(std::max(static_cast<int>(std::ceil(std::sqrt(dx * dx + dz * dz) / DRAPE_STEP)), 1), 64);
      const float w0f = k == 0 ? 0.0f : 1.0f, w1f = k + 1 == n - 1 ? 0.0f : 1.0f;
      // a fixed end inside the field (a block on the deck) lets its tube in by its own depth, fading along it
      const float e0 = k == 0 ? std::max(deck_at(p0.x, p0.z) + radius - p0.y, 0.0f) : 0.0f;
      const float e1 = k + 1 == n - 1 ? std::max(deck_at(p1.x, p1.z) + radius - p1.y, 0.0f) : 0.0f;
      for (int j = 1; j < m; ++j) {
        const float f = static_cast<float>(j) / static_cast<float>(m);
        const float h = deck_at(p0.x + dx * f, p0.z + dz * f);
        if (h <= NO_DECK) continue;
        const float d = h + radius - (p0.y + (p1.y - p0.y) * f) - e0 * (1.0f - f) - e1 * f;
        if (d <= 0.0f) continue;
        const float w0 = w0f * (1.0f - f), w1 = w1f * f;
        const float den = w0 * w0 + w1 * w1;
        if (den < 1e-9f) continue;
        p0.y += d * w0 / den;
        p1.y += d * w1 / den;
      }
    }
  }
}

namespace {

struct Cand {
  double th;
  double x, z;
  double m;
};

inline double cross2(double ax, double az, double bx, double bz) { return ax * bz - az * bx; }

}  // namespace

PackedVector3Array SheetRopes::route(const Vector3& a, const Vector3& b, const Vector3& pivot, double side,
                                     const Array& obstacles, double spacing, int64_t max_ways) const {
  PackedVector3Array out;
  const double sg = side >= 0.0 ? 1.0 : -1.0;
  const double ox = pivot.x, oz = pivot.z;
  auto theta = [&](double x, double z) { return std::atan2(sg * (x - ox), z - oz); };
  const double ta = theta(a.x, a.z), tb = theta(b.x, b.z);
  if (std::fabs(tb - ta) >= PI_D - 0.05 || std::fabs(tb - ta) < 1e-9) return out;
  const double tlo = std::min(ta, tb), thi = std::max(ta, tb);
  const double cx = double(b.x) - a.x, cz = double(b.z) - a.z;
  const double so = cross2(cx, cz, ox - a.x, oz - a.z) >= 0.0 ? 1.0 : -1.0;  // the pivot's side of the chord
  std::vector<Cand> k;
  for (int64_t gi = 0; gi + 1 < obstacles.size(); gi += 2) {
    const PackedVector3Array pts = obstacles[gi];
    const double m = static_cast<double>(obstacles[gi + 1]);
    const Vector3* pp = pts.ptr();
    const int64_t np = pts.size();
    for (int64_t j = 0; j < np; ++j) {
      const double px = pp[j].x, pz = pp[j].z;
      if (cross2(cx, cz, px - a.x, pz - a.z) * so >= 0.0) continue;  // on the pivot's side of the chord
      const double th = theta(px, pz);
      if (th <= tlo || th >= thi) continue;
      // a point well above the straight line there (the boom over the cockpit, the main above it) lets the line
      // pass under: it moves onto the chord as it rises from ROUTE_UNDER to ROUTE_UNDER + ROUTE_UNDER_FADE above
      const double f = std::min(std::max(((px - a.x) * cx + (pz - a.z) * cz) / std::max(cx * cx + cz * cz, 1e-12), 0.0),
                                1.0);
      const double gap = pp[j].y - (a.y + (double(b.y) - a.y) * f);
      const double v = std::min(std::max((gap - ROUTE_UNDER) / ROUTE_UNDER_FADE, 0.0), 1.0);
      const double hv = 1.0 - v * v * (3.0 - 2.0 * v);
      if (hv <= 0.0) continue;
      const double fx = a.x + cx * f, fz = a.z + cz * f;
      double qx = fx + (px - fx) * hv, qz = fz + (pz - fz) * hv;
      // a point coming into the wedge past an end starts at that end and moves out to its place over ROUTE_FADE
      // of angle, so the line bends away from it smoothly instead of jumping round it
      const bool near_a = std::fabs(th - ta) <= std::fabs(th - tb);
      const double u = std::min(std::fabs(th - (near_a ? ta : tb)) / ROUTE_FADE, 1.0);
      const double sf = u * u * (3.0 - 2.0 * u);
      const double ex = near_a ? a.x : b.x, ez = near_a ? a.z : b.z;
      qx = ex + (qx - ex) * sf;
      qz = ez + (qz - ez) * sf;
      if (sf * hv >= 1.0) {
        k.push_back({th, px, pz, m});
      } else {
        k.push_back({theta(qx, qz), qx, qz, m * sf * hv});
      }
    }
  }
  if (k.empty()) return out;
  const bool up = tb > ta;
  std::sort(k.begin(), k.end(), [up](const Cand& p, const Cand& q) { return up ? p.th < q.th : p.th > q.th; });
  // the convex chain from a to b round k (a Graham scan about the pivot)
  std::vector<Cand> ch;
  ch.push_back({ta, a.x, a.z, 0.0});
  k.push_back({tb, b.x, b.z, 0.0});
  for (const Cand& p : k) {
    while (ch.size() >= 2) {
      const Cand& c0 = ch[ch.size() - 2];
      const Cand& c1 = ch[ch.size() - 1];
      if (cross2(c1.x - c0.x, c1.z - c0.z, p.x - c1.x, p.z - c1.z) * so > 0.0) break;
      ch.pop_back();
    }
    ch.push_back(p);
  }
  auto turn = [&](size_t i) {
    const double ax = ch[i].x - ch[i - 1].x, az = ch[i].z - ch[i - 1].z;
    const double bx = ch[i + 1].x - ch[i].x, bz = ch[i + 1].z - ch[i].z;
    const double la = std::sqrt(ax * ax + az * az), lb = std::sqrt(bx * bx + bz * bz);
    if (la < 1e-9 || lb < 1e-9) return 0.0;
    return std::acos(std::min(std::max((ax * bx + az * bz) / (la * lb), -1.0), 1.0));
  };
  while (static_cast<int64_t>(ch.size()) - 2 > std::max<int64_t>(max_ways, 0)) {
    size_t best = 1;
    double bt = 1e9;
    for (size_t i = 1; i + 1 < ch.size(); ++i) {
      const double t = turn(i);
      if (t < bt) {
        bt = t;
        best = i;
      }
    }
    // its depth outside the new edge goes to the margins of its neighbours, so the edge still clears it
    {
      const Cand& p = ch[best - 1];
      const Cand& v = ch[best];
      const Cand& q = ch[best + 1];
      const double ex = q.x - p.x, ez = q.z - p.z, el = std::max(std::hypot(ex, ez), 1e-9);
      const double extra = v.m + std::max(-so * cross2(ex, ez, v.x - p.x, v.z - p.z) / el, 0.0);
      if (best - 1 > 0) ch[best - 1].m = std::max(ch[best - 1].m, extra);
      if (best + 2 < ch.size()) ch[best + 1].m = std::max(ch[best + 1].m, extra);
    }
    ch.erase(ch.begin() + static_cast<std::ptrdiff_t>(best));
  }
  if (ch.size() < 3) return out;
  // out along the outward bisector by the margin and the corner allowance of the ring spacing
  std::vector<double> wx(ch.size()), wz(ch.size());
  for (size_t i = 0; i < ch.size(); ++i) {
    wx[i] = ch[i].x;
    wz[i] = ch[i].z;
  }
  // the turns and their plan positions along the chain: a chord between two rings cuts every corner within a ring
  // spacing of it, so each corner's allowance takes the turns near it, weighted down linearly over the spacing
  std::vector<double> tn(ch.size(), 0.0), c0(ch.size(), 0.0);
  for (size_t i = 1; i < ch.size(); ++i) c0[i] = c0[i - 1] + std::hypot(ch[i].x - ch[i - 1].x, ch[i].z - ch[i - 1].z);
  for (size_t i = 1; i + 1 < ch.size(); ++i) tn[i] = turn(i);
  const double hs = std::max(spacing, 1e-6);
  for (size_t i = 1; i + 1 < ch.size(); ++i) {
    double ae = 0.0;
    for (size_t j = 1; j + 1 < ch.size(); ++j) ae += tn[j] * std::max(0.0, 1.0 - std::fabs(c0[j] - c0[i]) / hs);
    ae = std::min(ae, 2.5);
    double ax = ch[i].x - ch[i - 1].x, az = ch[i].z - ch[i - 1].z;
    double bx = ch[i + 1].x - ch[i].x, bz = ch[i + 1].z - ch[i].z;
    const double la = std::max(std::sqrt(ax * ax + az * az), 1e-9), lb = std::max(std::sqrt(bx * bx + bz * bz), 1e-9);
    ax /= la;
    az /= la;
    bx /= lb;
    bz /= lb;
    // outward: away from the pivot's side of the travel (so > 0: the pivot on the left, out to the right)
    double nx = so * (az + bz), nz = -so * (ax + bx);
    double nl = std::sqrt(nx * nx + nz * nz);
    if (nl < 1e-9) {
      nx = so * az;
      nz = -so * ax;
      nl = 1.0;
    }
    nx /= nl;
    nz /= nl;
    const double al = std::acos(std::min(std::max(ax * bx + az * bz, -1.0), 1.0));
    // a chord cuts a corner by at most half a ring spacing times sin(turn / 2), and no chord starts before the
    // route's first ring or ends after its last (the ends are rings)
    const double reach = std::min(0.5 * spacing, std::min(c0[i], c0.back() - c0[i]));
    const double push = (ch[i].m + reach * std::sin(0.5 * ae)) / std::max(std::cos(0.5 * al), 0.3);
    wx[i] += nx * push;
    wz[i] += nz * push;
  }
  std::vector<double> cl(ch.size(), 0.0);
  for (size_t i = 1; i < ch.size(); ++i) cl[i] = cl[i - 1] + std::hypot(wx[i] - wx[i - 1], wz[i] - wz[i - 1]);
  const double tot = std::max(cl.back(), 1e-9);
  out.resize(static_cast<int64_t>(ch.size()) - 2);
  for (size_t i = 1; i + 1 < ch.size(); ++i) {
    const double f = cl[i] / tot;
    out.set(static_cast<int64_t>(i) - 1, Vector3(static_cast<float>(wx[i]), static_cast<float>(a.y + (b.y - a.y) * f),
                                                 static_cast<float>(wz[i])));
  }
  return out;
}

namespace {

// Rasterises the top of a triangle mesh (model axes) at the grid nodes: `put(index, y)` per covered node.
template <typename F>
void raster(const PackedVector3Array& pos, const PackedInt32Array& idx, double x0, double z0, double cell, int nx,
            int nz, F put) {
  const Vector3* p = pos.ptr();
  const int32_t* ix = idx.ptr();
  const int64_t ni = idx.size(), np = pos.size();
  for (int64_t t = 0; t + 2 < ni; t += 3) {
    if (ix[t] < 0 || ix[t + 1] < 0 || ix[t + 2] < 0 || ix[t] >= np || ix[t + 1] >= np || ix[t + 2] >= np) continue;
    const Vector3 a = p[ix[t]], b = p[ix[t + 1]], c = p[ix[t + 2]];
    const double den = (double(b.z) - c.z) * (double(a.x) - c.x) + (double(c.x) - b.x) * (double(a.z) - c.z);
    if (std::fabs(den) < 1e-9) continue;
    const int i0 = std::max(0, static_cast<int>(std::ceil((std::min({a.x, b.x, c.x}) - x0) / cell)));
    const int i1 = std::min(nx - 1, static_cast<int>(std::floor((std::max({a.x, b.x, c.x}) - x0) / cell)));
    const int k0 = std::max(0, static_cast<int>(std::ceil((std::min({a.z, b.z, c.z}) - z0) / cell)));
    const int k1 = std::min(nz - 1, static_cast<int>(std::floor((std::max({a.z, b.z, c.z}) - z0) / cell)));
    for (int k = k0; k <= k1; ++k) {
      const double pz = z0 + k * cell;
      for (int i = i0; i <= i1; ++i) {
        const double px = x0 + i * cell;
        const double w0 = ((double(b.z) - c.z) * (px - c.x) + (double(c.x) - b.x) * (pz - c.z)) / den;
        const double w1 = ((double(c.z) - a.z) * (px - c.x) + (double(a.x) - c.x) * (pz - c.z)) / den;
        const double w2 = 1.0 - w0 - w1;
        if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) continue;
        put(k * nx + i, w0 * a.y + w1 * b.y + w2 * c.y);
      }
    }
  }
}

}  // namespace

Dictionary SheetRopes::build_deck(const Array& surfaces, double cell, int64_t skirt, int64_t dilate) const {
  Dictionary out;
  cell = std::max(cell, 1e-3);
  double xmin = 1e30, xmax = -1e30, zmin = 1e30, zmax = -1e30;
  for (int64_t s = 0; s < surfaces.size(); ++s) {
    const Dictionary d = surfaces[s];
    if (getf(d, "cap", -1.0f) >= 0.0f) continue;
    const PackedVector3Array p = d.get("positions", PackedVector3Array());
    for (int64_t v = 0; v < p.size(); ++v) {
      xmin = std::min(xmin, double(p[v].x));
      xmax = std::max(xmax, double(p[v].x));
      zmin = std::min(zmin, double(p[v].z));
      zmax = std::max(zmax, double(p[v].z));
    }
  }
  if (xmax < xmin) return out;
  const int pad = static_cast<int>(std::max<int64_t>(skirt, 0) + std::max<int64_t>(dilate, 0)) + 2;
  const double x0 = xmin - pad * cell, z0 = zmin - pad * cell;
  const int nx = static_cast<int>(std::ceil((xmax - xmin) / cell)) + 2 * pad + 1;
  const int nz = static_cast<int>(std::ceil((zmax - zmin) / cell)) + 2 * pad + 1;
  std::vector<double> h(static_cast<size_t>(nx) * nz, NO_DECK);
  for (int64_t s = 0; s < surfaces.size(); ++s) {
    const Dictionary d = surfaces[s];
    if (getf(d, "cap", -1.0f) >= 0.0f) continue;
    raster(d.get("positions", PackedVector3Array()), d.get("indices", PackedInt32Array()), x0, z0, cell, nx, nz,
           [&](int i, double y) { h[i] = std::max(h[i], y); });
  }
  // the deck's outer edge per station (the rail of the outside route), before the fittings, skirt and widening
  PackedFloat32Array lo, hi;
  lo.resize(nz);
  hi.resize(nz);
  for (int k = 0; k < nz; ++k) {
    float l = NAN, r = NAN;
    for (int i = 0; i < nx; ++i) {
      if (h[k * nx + i] <= NO_DECK) continue;
      const float x = static_cast<float>(x0 + i * cell);
      if (std::isnan(l)) l = x;
      r = x;
    }
    lo.set(k, l);
    hi.set(k, r);
  }
  const std::vector<double> deck = h;
  for (int64_t s = 0; s < surfaces.size(); ++s) {
    const Dictionary d = surfaces[s];
    const double cap = getf(d, "cap", -1.0f);
    if (cap < 0.0) continue;
    raster(d.get("positions", PackedVector3Array()), d.get("indices", PackedInt32Array()), x0, z0, cell, nx, nz,
           [&](int i, double y) {
             if (deck[i] > NO_DECK && y > h[i] && y <= deck[i] + cap) h[i] = y;
           });
  }
  for (int64_t step = 0; step < skirt; ++step) {
    const std::vector<double> src = h;
    for (int k = 0; k < nz; ++k) {
      for (int i = 0; i < nx; ++i) {
        if (src[k * nx + i] > NO_DECK) continue;
        double best = NO_DECK;
        for (int dk = -1; dk <= 1; ++dk) {
          for (int di = -1; di <= 1; ++di) {
            const int kk = k + dk, ii = i + di;
            if (kk >= 0 && kk < nz && ii >= 0 && ii < nx) best = std::max(best, src[kk * nx + ii]);
          }
        }
        h[k * nx + i] = best;
      }
    }
  }
  const int rd = static_cast<int>(std::max<int64_t>(dilate, 0));
  if (rd > 0) {
    std::vector<double> tmp = h;
    for (int k = 0; k < nz; ++k) {
      for (int i = 0; i < nx; ++i) {
        double best = NO_DECK;
        for (int di = std::max(0, i - rd); di <= std::min(nx - 1, i + rd); ++di) best = std::max(best, h[k * nx + di]);
        tmp[k * nx + i] = best;
      }
    }
    for (int k = 0; k < nz; ++k) {
      for (int i = 0; i < nx; ++i) {
        double best = NO_DECK;
        for (int dk = std::max(0, k - rd); dk <= std::min(nz - 1, k + rd); ++dk) best = std::max(best, tmp[dk * nx + i]);
        h[k * nx + i] = best;
      }
    }
  }
  PackedFloat32Array hf;
  hf.resize(static_cast<int64_t>(h.size()));
  float mx = NO_DECK;
  float* hw = hf.ptrw();
  for (size_t i = 0; i < h.size(); ++i) {
    hw[i] = static_cast<float>(h[i]);
    mx = std::max(mx, hw[i]);
  }
  out["heights"] = hf;
  out["origin"] = Vector2(static_cast<float>(x0), static_cast<float>(z0));
  out["cell"] = cell;
  out["nx"] = nx;
  out["nz"] = nz;
  out["max"] = mx;
  out["edge_lo"] = lo;
  out["edge_hi"] = hi;
  return out;
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
  ClassDB::bind_method(D_METHOD("route", "a", "b", "pivot", "side", "obstacles", "spacing", "max_ways"),
                       &SheetRopes::route);
  ClassDB::bind_method(D_METHOD("build_deck", "surfaces", "cell", "skirt", "dilate"), &SheetRopes::build_deck);
  ClassDB::bind_method(D_METHOD("attach_mesh", "mesh", "surface"), &SheetRopes::attach_mesh);
  ClassDB::bind_method(D_METHOD("vertex_bytes"), &SheetRopes::vertex_bytes);
  ClassDB::bind_method(D_METHOD("attribute_bytes"), &SheetRopes::attribute_bytes);
  ClassDB::bind_method(D_METHOD("write_mesh"), &SheetRopes::write_mesh);
}

}  // namespace windmark_godot
