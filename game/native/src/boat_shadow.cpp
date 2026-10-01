// Drawn boat shadows on the water: docs/specs/water_render.md §4.7. See boat_shadow.h.
#include "boat_shadow.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

namespace windmark_godot {

namespace {

// BoatShadows constants
constexpr double MARGIN = 0.5;
constexpr double PENUMBRA_BASE = 0.03;
constexpr double PENUMBRA_K = 0.0047;
constexpr double SUN_MIN_Y = 0.0523;

double cross(const Vector2& o, const Vector2& a, const Vector2& b) {
  return static_cast<double>(a.x - o.x) * static_cast<double>(b.y - o.y) -
         static_cast<double>(a.y - o.y) * static_cast<double>(b.x - o.x);
}

// Geometry2D.convex_hull (Andrew's monotone chain, collinear points dropped), counter-clockwise, without the
// closing point.
void convex_ring(const std::vector<Vector2>& in, std::vector<Vector2>& work, std::vector<Vector2>& out) {
  out.clear();
  work = in;
  size_t n = work.size();
  if (n < 3) {
    out = work;
    return;
  }
  std::sort(work.begin(), work.end(),
            [](const Vector2& a, const Vector2& b) { return a.x < b.x || (a.x == b.x && a.y < b.y); });
  out.resize(2 * n);
  size_t k = 0;
  for (size_t i = 0; i < n; ++i) {
    while (k >= 2 && cross(out[k - 2], out[k - 1], work[i]) <= 0) --k;
    out[k++] = work[i];
  }
  for (size_t i = n - 1, t = k + 1; i > 0; --i) {
    while (k >= t && cross(out[k - 2], out[k - 1], work[i - 1]) <= 0) --k;
    out[k++] = work[i - 1];
  }
  out.resize(k > 0 ? k - 1 : 0);  // the last point repeats the first
}

Vector2 centre(const std::vector<Vector2>& ring) {
  double cx = 0.0, cy = 0.0;
  for (const Vector2& q : ring) {
    cx += q.x;
    cy += q.y;
  }
  double n = std::max<double>(static_cast<double>(ring.size()), 1.0);
  return Vector2(static_cast<real_t>(cx / n), static_cast<real_t>(cy / n));
}

// edge lines (outward unit normal, offset) of a counter-clockwise ring (BoatShadows._add_planes)
void add_planes(const std::vector<Vector2>& ring, PackedVector4Array& out) {
  size_t n = ring.size();
  for (size_t k = 0; k < n; ++k) {
    const Vector2& a = ring[k];
    const Vector2& b = ring[(k + 1) % n];
    Vector2 e = b - a;
    Vector2 nr(e.y, -e.x);
    double l = nr.length();
    if (l < 1e-6) {
      nr = (a - centre(ring)).normalized();
    } else {
      nr /= static_cast<real_t>(l);
    }
    out.push_back(Vector4(nr.x, nr.y, nr.dot(a), 0.0));
  }
}

}  // namespace

void BoatShadowShape::configure(const Dictionary& caster) {
  hull_.clear();
  ok_ = false;
  if (caster.is_empty()) return;
  PackedVector3Array h = caster.get("hull", PackedVector3Array());
  for (int64_t i = 0; i < h.size(); ++i) hull_.push_back(h[i]);
  mast_step_ = caster.get("mast_step", Vector3());
  mast_head_ = caster.get("mast_head", Vector3());
  mast_r_ = caster.get("mast_r", 0.0);
  ok_ = !hull_.empty();
}

Dictionary BoatShadowShape::build(const Transform3D& xform, const Vector3& sun, const PackedVector3Array& sails,
                                  const PackedInt32Array& sail_counts) {
  Dictionary out;
  if (sun.y < SUN_MIN_Y || !ok_) return out;
  const Vector3 o = xform.origin;
  const double kx = static_cast<double>(sun.x) / sun.y;
  const double kz = static_cast<double>(sun.z) / sun.y;

  PackedVector4Array planes, poly, bound, excl;
  PackedVector2Array corners;
  PackedInt32Array corner_end;
  std::vector<Vector3> hull_w(hull_.size());
  for (size_t k = 0; k < hull_.size(); ++k) hull_w[k] = xform.xform(hull_[k]);

  // groups: hull, mast, then each sail
  const int64_t n_sails = sail_counts.size();
  int64_t at = 0;
  for (int64_t g = 0; g < 2 + n_sails; ++g) {
    const Vector3* pts = nullptr;
    int64_t n = 0;
    Vector3 mast[2];
    if (g == 0) {
      pts = hull_w.data();
      n = static_cast<int64_t>(hull_w.size());
    } else if (g == 1) {
      if (mast_r_ > 0.0) {
        mast[0] = xform.xform(mast_step_);
        mast[1] = xform.xform(mast_head_);
        pts = mast;
        n = 2;
      }
    } else {
      n = sail_counts[g - 2];
      if (at + n > sails.size()) n = std::max<int64_t>(sails.size() - at, 0);
      pts = n > 0 ? sails.ptr() + at : nullptr;
      at += sail_counts[g - 2];
    }
    if (n < 2 || poly.size() >= MAX_POLYS) continue;
    p2_.resize(n);
    double h = 0.0;
    for (int64_t k = 0; k < n; ++k) {
      const Vector3& p = pts[k];
      double dy = static_cast<double>(p.y) - o.y;
      p2_[k] = Vector2(static_cast<real_t>(p.x - o.x - kx * dy), static_cast<real_t>(p.z - o.z - kz * dy));
      h += std::max(dy, 0.0);
    }
    h /= static_cast<double>(n);
    if (g == 1) {
      // the mast: a strip of its width along the projected spar
      Vector2 a = p2_[0], b = p2_[1];
      Vector2 t = a.distance_to(b) > 1e-4 ? (b - a).normalized() : Vector2(1, 0);
      Vector2 nr = Vector2(-t.y, t.x) * static_cast<real_t>(mast_r_);
      p2_ = {a + nr, a - nr, b - nr, b + nr};
    }
    convex_ring(p2_, work_, ring_);
    if (ring_.size() < 3 || planes.size() + static_cast<int64_t>(ring_.size()) > MAX_PLANES) continue;
    Vector2 c = centre(ring_);
    double rad = 0.0;
    for (const Vector2& q : ring_) rad = std::max(rad, static_cast<double>(q.distance_to(c)));
    add_planes(ring_, planes);
    for (const Vector2& q : ring_) corners.push_back(q);
    corner_end.push_back(corners.size());
    poly.push_back(Vector4(static_cast<real_t>(planes.size()), PENUMBRA_BASE + PENUMBRA_K * h / sun.y, 0.0, 0.0));
    bound.push_back(Vector4(c.x, c.y, rad, 0.0));
  }

  // the hull footprint: its points dropped straight down
  p2_.resize(hull_w.size());
  for (size_t k = 0; k < hull_w.size(); ++k) p2_[k] = Vector2(hull_w[k].x - o.x, hull_w[k].z - o.z);
  std::vector<Vector2> fring;
  convex_ring(p2_, work_, fring);
  if (fring.size() >= 3 && fring.size() <= static_cast<size_t>(MAX_EXCL)) add_planes(fring, excl);

  // the grid's rectangle: one side along the shadow
  Vector2 u(-sun.x, -sun.z);
  u = u.length() > 1e-3 ? u.normalized() : Vector2(1, 0);
  Vector2 v(-u.y, u.x);
  const real_t inf = std::numeric_limits<real_t>::infinity();
  Vector2 lo(inf, inf), hi(-inf, -inf);
  auto grow = [&](const Vector2& q) {
    Vector2 w(q.dot(u), q.dot(v));
    lo = Vector2(std::min(lo.x, w.x), std::min(lo.y, w.y));
    hi = Vector2(std::max(hi.x, w.x), std::max(hi.y, w.y));
  };
  for (int64_t k = 0; k < corners.size(); ++k) grow(corners[k]);
  for (const Vector2& q : fring) grow(q);
  double fmax = 0.0;
  for (int64_t k = 0; k < poly.size(); ++k) fmax = std::max(fmax, static_cast<double>(poly[k].y));
  real_t m = static_cast<real_t>(MARGIN + 2.0 * fmax);
  lo -= Vector2(m, m);
  hi += Vector2(m, m);

  const int64_t n_poly = poly.size();
  const int64_t n_excl = excl.size();
  planes.resize(MAX_PLANES);
  poly.resize(MAX_POLYS);
  bound.resize(MAX_POLYS);
  excl.resize(MAX_EXCL);
  for (int64_t k = n_poly; k < MAX_POLYS; ++k) {
    poly.set(k, Vector4());
    bound.set(k, Vector4());
  }
  Vector3 u3(u.x, 0, u.y), v3(v.x, 0, v.y);
  Transform3D rect(Basis(u3 * (hi.x - lo.x), Vector3(0, 1, 0), v3 * (hi.y - lo.y)),
                   o + u3 * lo.x + v3 * lo.y);
  out["origin"] = o;
  out["sun"] = sun;
  out["planes"] = planes;
  out["poly"] = poly;
  out["bound"] = bound;
  out["n_poly"] = n_poly;
  out["excl"] = excl;
  out["n_excl"] = n_excl;
  out["rect"] = rect;
  out["corners"] = corners;
  out["corner_end"] = corner_end;
  return out;
}

void BoatShadowShape::_bind_methods() {
  ClassDB::bind_method(D_METHOD("configure", "caster"), &BoatShadowShape::configure);
  ClassDB::bind_method(D_METHOD("build", "xform", "sun", "sails", "sail_counts"), &BoatShadowShape::build);
}

}  // namespace windmark_godot
