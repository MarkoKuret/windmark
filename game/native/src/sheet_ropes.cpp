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
constexpr float WHIP_WAVE = 1.5f;  // m, the shortest wavelength of the whip along a flogging sheet
constexpr float WHIP_RINGS = 8.0f;  // ring spacings in the whip's wavelength at least (no zig-zag between rings)
constexpr float WHIP_STEEP = 0.4f;  // the whip's amplitude at most this share of its wavelength times the whip
// §11.3 "Rope": the free run moves as a damped string about its hanging shape
constexpr float ROPE_STEP = 1.0f / 120.0f;  // s, the longest sub-step
constexpr float ROPE_OMEGA = 8.0f;   // rad/s, the pull back to the hanging shape
constexpr float ROPE_ZETA = 0.5f;    // its damping ratio
constexpr float ROPE_SMOOTH = 0.25f; // the deviation's smoothing per sub-step
constexpr float ROPE_VMAX = 4.0f;    // the fastest ring, in follow speeds
constexpr float ROPE_WRAP_LO = 0.2f;  // rad, the turn at a waypoint from which the rope is wrapped round it ..
constexpr float ROPE_WRAP_HI = 0.6f;  // .. fully from this
constexpr float ROPE_SNAP = 0.3f;    // a start jumping more than this share of the run in one update relays the line
constexpr int ROPE_ITER = 4;         // length passes
constexpr double DECK_FALL = 4.0;    // m down per m out over the deck field's fall (build_deck)
constexpr float DECK_SLOPE = 1.0f;   // a ring lifted onto the deck lifts its neighbours by as much less this per m
constexpr float DRAPE_STEEP = 0.5f;  // a rise of the field from a fixed end steeper than this (m per m) bends the tube
constexpr float DRAPE_STEP = 0.025f;  // m, the drape's sample step along a tube (under the field's widening)
constexpr double PI_D = 3.14159265358979;
constexpr double ROUTE_FADE = 0.1;  // rad, the angle over which an obstacle point fades in at an end of a route
constexpr double ROUTE_UNDER = 0.1;  // m above the straight line from which an obstacle point lets the line under
constexpr double ROUTE_UNDER_FADE = 0.2;  // m over which it fades out
constexpr double ROUTE_OPEN = 0.05;  // rad short of PI between the ends' angles from which a route runs straight
constexpr double ROUTE_OPEN_FADE = 0.3;  // rad before that over which its waypoints ease onto the straight line
constexpr double ROUTE_ASTERN_FADE = 0.8;  // rad before that, for the start dead astern of the pivot
constexpr double ROUTE_NEAR = 0.2;  // m in plan from the pivot (and its offset) within which a route runs straight

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
  follow_ = std::max(getf(params, "follow", 2.0f), 1e-3f);
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
    l.x.assign(l.free_rings, Vector3());
    l.v.assign(l.free_rings, Vector3());
    l.tp.assign(l.free_rings, Vector3());
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
                        const PackedFloat32Array& drive, const Vector3& gravity, double dt) {
  const Vector3 g = gravity.length_squared() > 1e-12f ? gravity.normalized() : Vector3(0, -1, 0);
  const int per = sides_ + 1;
  const int64_t nlines = static_cast<int64_t>(lines_.size());
  const int64_t slots = nlines > 0 ? std::min<int64_t>(ways.size() / nlines, MAX_WAYS) : 0;
  for (size_t i = 0; i < lines_.size(); ++i) {
    Line& l = lines_[i];
    const int64_t ii = static_cast<int64_t>(i);
    const Vector3 s0 = ii < starts.size() ? starts[ii] : l.anchor;
    const float* dv = drive.size() >= (ii + 1) * DRIVE ? drive.ptr() + ii * DRIVE : nullptr;
    const bool shown = dv != nullptr && dv[0] > 0.5f;
    Vector3* r = ring_.data() + l.first_ring;
    if (!shown) {
      for (int k = 0; k < l.rings; ++k) r[k] = s0;
      l.live = false;
    } else {
      const float sag_f = dv[1], sag_l = dv[2], psi = dv[3], whip = dv[4], phi = dv[5];
      // the free run: start (on the deck at least: a sail coming down into the boat), its waypoints (the unused
      // slots NaN), anchor
      pts_.clear();
      pts_.push_back(Vector3(s0.x, std::max(s0.y, deck_at(s0.x, s0.z) + l.radius), s0.z));
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
      const float hs = len / static_cast<float>(nf - 1);  // the ring spacing
      // the hanging shape (§11.3 "Shape"): the whip's wavelength at least WHIP_RINGS ring spacings
      const float lam = std::max(WHIP_WAVE, WHIP_RINGS * hs);
      const float amp = whip * std::min(len, WHIP_STEEP * lam);
      tgt_.resize(nf);
      bear_.resize(nf);
      for (int k = 0; k < nf; ++k) {
        const float t = static_cast<float>(k) / static_cast<float>(nf - 1);
        const float s = t * len;
        const float b = 4.0f * t * (1.0f - t);
        tgt_[k] = along(p, c, n, s) + sag * b + side * (b * amp * std::sin(phi - TAU_F * s / lam));
        // wrapped round an obstacle: within two ring spacings of a waypoint along the run (fading out over two
        // more) where the run turns by ROPE_WRAP_LO .. ROPE_WRAP_HI or more
        float wrap = 0.0f;
        for (int j = 1; j + 1 < n; ++j) {
          const float u = std::min(std::max((std::fabs(s - c[j]) - 2.0f * hs) / (2.0f * hs), 0.0f), 1.0f);
          const Vector3 da = p[j] - p[j - 1], db = p[j + 1] - p[j];
          // (a turn between two legs either side of it, not within a cluster of waypoints closer than a quarter
          // spacing: those are points eased onto an end, not a wrap)
          const float q2 = 0.0625f * hs * hs;
          const float tn = da.length_squared() > q2 && db.length_squared() > q2 ? da.angle_to(db) : 0.0f;
          const float v = std::min(std::max((tn - ROPE_WRAP_LO) / (ROPE_WRAP_HI - ROPE_WRAP_LO), 0.0f), 1.0f);
          wrap = std::max(wrap, (1.0f - u * u * (3.0f - 2.0f * u)) * v * v * (3.0f - 2.0f * v));
        }
        bear_[k] = wrap;
      }
      lay_on_deck(tgt_.data(), nf, l.radius);
      // §11.3 "Rope": the rings move as a rope toward it, or are laid on it
      const Vector3 start = tgt_[0];
      if (dt > 0.0 && l.live && (start - l.x[0]).length() <= ROPE_SNAP * len) {
        rope_step(l, tgt_.data(), bear_.data(), static_cast<float>(dt));
      } else {
        for (int k = 0; k < nf; ++k) {
          l.x[k] = tgt_[k];
          l.v[k] = tgt_[k];
        }
      }
      for (int k = 0; k < nf; ++k) l.tp[k] = tgt_[k];
      l.live = true;
      for (int k = 0; k < nf; ++k) r[k] = l.x[k];
      lay_on_deck(r, nf, l.radius);
      drape(r, nf, l.radius);
      if (l.lead_rings > 0) {
        const Vector3 a = l.anchor, e = l.fixed[0];
        const float len2 = (e - a).length();
        const Vector3 sag2 = g * (len2 * sag_l);
        for (int k = 1; k <= l.lead_rings; ++k) {
          const float t = static_cast<float>(k) / static_cast<float>(l.lead_rings);
          Vector3 q = a + (e - a) * t + sag2 * (4.0f * t * (1.0f - t));
          r[nf - 1 + k] = q;
        }
        lay_on_deck(r + nf - 1, l.lead_rings + 1, l.radius);
        bridge(r + nf - 1, l.lead_rings + 1);
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

// §11.3 "Rope": the free run's rings `l.x` (ends on the start and the anchor) as a damped Verlet rope guided by the
// hanging shape `target`: they move with the shape up to the follow speed; what it moved faster (the sail jumping, a
// route changing) is left as a deviation that a spring pulls back, the rings' neighbours smooth and the rope's length
// carries along it (a start moving away drags the rings after it), so it dies away as a damped wave.
void SheetRopes::rope_step(Line& l, const Vector3* target, const float* bear, float dt) {
  const int n = l.free_rings;
  Vector3* x = l.x.data();
  Vector3* xp = l.v.data();  // the rings' positions a sub-step earlier (Verlet)
  const Vector3* tp = l.tp.data();
  // how far a ring moves with the shape at once: the follow speed, more near the start (it drags the rope after it:
  // the start's move times (1 - k / (n - 1))^2) and all of it where the ring is wrapped round an obstacle (it is
  // carried round it)
  const float reach = follow_ * dt;
  const float drag = (target[0] - tp[0]).length();
  for (int k = 1; k < n - 1; ++k) {
    Vector3 d = target[k] - tp[k];
    const float dl = d.length();
    const float u = 1.0f - static_cast<float>(k) / static_cast<float>(n - 1);
    const float r = reach + drag * u * u;
    if (dl > r) d *= (r + (dl - r) * bear[k]) / dl;
    x[k] += d;
    xp[k] += d;
  }
  x[0] = xp[0] = target[0];
  x[n - 1] = xp[n - 1] = target[n - 1];
  const int steps = std::max(1, static_cast<int>(std::ceil(dt / ROPE_STEP - 1e-4f)));
  const float h = dt / static_cast<float>(steps);
  const float pull = (ROPE_OMEGA * h) * (ROPE_OMEGA * h);
  const float keep = std::exp(-2.0f * ROPE_ZETA * ROPE_OMEGA * h);
  const float vmax = ROPE_VMAX * follow_ * h;
  dev_.resize(n);
  Vector3* d = dev_.data();
  for (int st = 0; st < steps; ++st) {
    for (int k = 1; k < n - 1; ++k) {
      Vector3 vel = (x[k] - xp[k]) * keep;
      const float sp = vel.length();
      if (sp > vmax) vel *= vmax / sp;
      xp[k] = x[k];
      x[k] += vel + (target[k] - x[k]) * pull;
    }
    // the deviation smoothed along the rope (its shortest waves die at once: no zig-zag between rings)
    for (int k = 0; k < n; ++k) d[k] = x[k] - target[k];
    d[0] = d[n - 1] = Vector3();
    for (int k = 1; k < n - 1; ++k) x[k] += (d[k - 1] - d[k] * 2.0f + d[k + 1]) * ROPE_SMOOTH;
    // a ring wrapped round an obstacle lies on it
    for (int k = 1; k < n - 1; ++k) {
      x[k] += (target[k] - x[k]) * bear[k];
      xp[k] += (target[k] - xp[k]) * bear[k];
    }
    // the rope's length: no segment longer than the hanging shape's (the ends stay)
    for (int it = 0; it < ROPE_ITER; ++it) {
      for (int k = 0; k + 1 < n; ++k) {
        const Vector3 e = x[k + 1] - x[k];
        const float el = e.length();
        if (el < 1e-9f) continue;
        const float w0 = k == 0 ? 0.0f : 1.0f, w1 = k + 1 == n - 1 ? 0.0f : 1.0f;
        if (w0 + w1 <= 0.0f) continue;
        const float rest = (target[k + 1] - target[k]).length();
        if (el <= rest) continue;  // a rope stretches no further, but goes slack
        const Vector3 c = e * ((el - rest) / el / (w0 + w1));
        x[k] += c * w0;
        x[k + 1] -= c * w1;
      }
    }
  }
}

// §11.3 "Deck": every inner ring of a run at least the rope's radius over the field, and a ring lifted lifts its
// neighbours by as much less DECK_SLOPE times the distance to them (the rope lies over a rail or a cabin edge and
// falls away from it, it does not dive between rings on and off the deck).
void SheetRopes::lay_on_deck(Vector3* r, int n, float radius) {
  if (deck_.empty() || n < 3) return;
  lift_.assign(n, 0.0f);
  bool any = false;
  for (int k = 1; k < n - 1; ++k) {
    const float h = deck_at(r[k].x, r[k].z);
    if (h > NO_DECK) lift_[k] = std::max(h + radius - r[k].y, 0.0f);
    any = any || lift_[k] > 0.0f;
  }
  if (!any) return;
  for (int k = 2; k < n - 1; ++k) lift_[k] = std::max(lift_[k], lift_[k - 1] - DECK_SLOPE * (r[k] - r[k - 1]).length());
  for (int k = n - 3; k >= 1; --k) lift_[k] = std::max(lift_[k], lift_[k + 1] - DECK_SLOPE * (r[k + 1] - r[k]).length());
  for (int k = 1; k < n - 1; ++k) r[k].y += lift_[k];
}

// §11.3 "Deck": a lead run under its load bridges over what it was lifted onto (a coaming, a winch base) as a taut
// string: every ring up to the upper hull of the rings over the run's plan length (no dip between two lifts).
void SheetRopes::bridge(Vector3* r, int n) {
  if (n < 3) return;
  cum_.assign(n, 0.0f);
  for (int k = 1; k < n; ++k) cum_[k] = cum_[k - 1] + Vector2(r[k].x - r[k - 1].x, r[k].z - r[k - 1].z).length();
  hull_.clear();
  for (int k = 0; k < n; ++k) {
    while (hull_.size() >= 2) {
      const int a = hull_[hull_.size() - 2], b = hull_.back();
      // b under the line from a to k: not on the upper hull
      const float cr = (cum_[b] - cum_[a]) * (r[k].y - r[a].y) - (r[b].y - r[a].y) * (cum_[k] - cum_[a]);
      if (cr < 0.0f) break;
      hull_.pop_back();
    }
    hull_.push_back(k);
  }
  for (size_t j = 0; j + 1 < hull_.size(); ++j) {
    const int a = hull_[j], b = hull_[j + 1];
    for (int k = a + 1; k < b; ++k) {
      const float f = cum_[b] > cum_[a] ? (cum_[k] - cum_[a]) / (cum_[b] - cum_[a]) : 0.0f;
      r[k].y = std::max(r[k].y, r[a].y + (r[b].y - r[a].y) * f);
    }
  }
}

// The field's height at an end of the tube p0-p1 sampled in m steps: at the end, or off the field at the first sample
// from that end that is on it (NO_DECK when none is).
float SheetRopes::end_field(const Vector3& p0, const Vector3& p1, int m, bool far) const {
  const Vector3 e = far ? p1 : p0;
  float h = deck_at(e.x, e.z);
  for (int j = 1; j < m && h <= NO_DECK; ++j) {
    const float f = static_cast<float>(far ? m - j : j) / static_cast<float>(m);
    h = deck_at(p0.x + (p1.x - p0.x) * f, p0.z + (p1.z - p0.z) * f);
  }
  return h;
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
      // a fixed end below the field (a block on the deck, a clew coming down outside the rail) lets its tube in by
      // its own depth under the field (there, or where the tube first meets it), fading along it
      const float e0 = k == 0 ? std::max(end_field(p0, p1, m, false) + radius - p0.y, 0.0f) : 0.0f;
      const float e1 = k + 1 == n - 1 ? std::max(end_field(p0, p1, m, true) + radius - p1.y, 0.0f) : 0.0f;
      // next to a fixed end under the field or below a steep rise of it (a clew down the hull side), the free ring goes
      // no higher than the rope's radius over the highest field under the tube (the rise bends the tube there, it
      // does not throw the ring up)
      const float y0 = p0.y, y1 = p1.y;
      float top = NO_DECK;
      for (int j = 1; j < m; ++j) {
        const float f = static_cast<float>(j) / static_cast<float>(m);
        const float h = deck_at(p0.x + dx * f, p0.z + dz * f);
        if (h <= NO_DECK) continue;
        top = std::max(top, h + radius);
        const float d = h + radius - (p0.y + (p1.y - p0.y) * f) - e0 * (1.0f - f) - e1 * f;
        if (d <= 0.0f) continue;
        const float w0 = w0f * (1.0f - f), w1 = w1f * f;
        const float den = w0 * w0 + w1 * w1;
        if (den < 1e-9f) continue;
        p0.y += d * w0 / den;
        p1.y += d * w1 / den;
      }
      const float run = std::sqrt(dx * dx + dz * dz) * DRAPE_STEEP;
      if (k + 1 == n - 1 && (e1 > 0.0f || top - y1 > run)) p0.y = std::min(p0.y, std::max(y0, top));
      if (k == 0 && (e0 > 0.0f || top - y0 > run)) p1.y = std::min(p1.y, std::max(y1, top));
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
  // a route runs straight from ROUTE_OPEN short of PI between the ends' angles, or with the start that close to dead
  // astern of the pivot (a pole's end by the mast: its angle flips from PI to -PI there); toward either the waypoints
  // ease onto the straight line (no pop between a route and none)
  const double wide = std::max(std::fabs(tb - ta), std::fabs(ta));
  if (wide >= PI_D - ROUTE_OPEN || std::fabs(tb - ta) < 1e-9) return out;
  const double ow = std::min(std::max((std::fabs(tb - ta) - (PI_D - ROUTE_OPEN - ROUTE_OPEN_FADE)) / ROUTE_OPEN_FADE,
                                      0.0), 1.0);
  const double oa = std::min(std::max((std::fabs(ta) - (PI_D - ROUTE_OPEN - ROUTE_ASTERN_FADE)) / ROUTE_ASTERN_FADE,
                                      0.0), 1.0);
  const double ov = std::max(ow, oa);
  // nor with the start by the pivot, where its angle is no guide (a pole's end at the mast): straight within
  // ROUTE_NEAR and the pivot's offset from the centreline of it in plan, easing in over as much again
  const double near = std::hypot(double(a.x) - ox, double(a.z) - oz);
  const double rn = ROUTE_NEAR + std::fabs(ox);  // the pivot's own offset from the centreline more
  if (near <= rn) return out;
  const double nv = std::min(std::max((2.0 * rn - near) / rn, 0.0), 1.0);
  const double open = std::max(ov * ov * (3.0 - 2.0 * ov), nv * nv * (3.0 - 2.0 * nv));
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
  // eased toward the chord by `open`, then the heights along the chain as it ends up
  if (open > 0.0) {
    for (size_t i = 1; i + 1 < ch.size(); ++i) {
      const double g = std::min(
          std::max(((wx[i] - a.x) * cx + (wz[i] - a.z) * cz) / std::max(cx * cx + cz * cz, 1e-12), 0.0), 1.0);
      wx[i] += (a.x + cx * g - wx[i]) * open;
      wz[i] += (a.z + cz * g - wz[i]) * open;
    }
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

Dictionary SheetRopes::build_deck(const Array& surfaces, double cell, int64_t skirt, int64_t dilate,
                                  int64_t fall) const {
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
  const int pad =
      static_cast<int>(std::max<int64_t>(skirt, 0) + std::max<int64_t>(dilate, 0) + std::max<int64_t>(fall, 0)) + 2;
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
  // the fall: `fall` more cells out, each DECK_FALL * cell below its highest neighbour (the hull side, steep but not a
  // cliff, so a rope swinging out over the rail falls away from it instead of popping off the field)
  for (int64_t step = 0; step < fall; ++step) {
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
        if (best > NO_DECK) h[k * nx + i] = best - DECK_FALL * cell;
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

PackedVector3Array SheetRopes::hanging(int64_t line) const {
  PackedVector3Array out;
  if (line < 0 || line >= static_cast<int64_t>(lines_.size())) return out;
  const Line& l = lines_[line];
  out.resize(static_cast<int64_t>(l.tp.size()));
  for (size_t k = 0; k < l.tp.size(); ++k) out.set(static_cast<int64_t>(k), l.tp[k]);
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
  ClassDB::bind_method(D_METHOD("update", "starts", "ways", "drive", "gravity", "dt"), &SheetRopes::update,
                       DEFVAL(0.0));
  ClassDB::bind_method(D_METHOD("get_line_count"), &SheetRopes::get_line_count);
  ClassDB::bind_method(D_METHOD("get_vertex_count"), &SheetRopes::get_vertex_count);
  ClassDB::bind_method(D_METHOD("indices"), &SheetRopes::indices);
  ClassDB::bind_method(D_METHOD("positions"), &SheetRopes::positions);
  ClassDB::bind_method(D_METHOD("normals"), &SheetRopes::normals);
  ClassDB::bind_method(D_METHOD("tangents"), &SheetRopes::tangents);
  ClassDB::bind_method(D_METHOD("uvs"), &SheetRopes::uvs);
  ClassDB::bind_method(D_METHOD("centre", "line"), &SheetRopes::centre);
  ClassDB::bind_method(D_METHOD("hanging", "line"), &SheetRopes::hanging);
  ClassDB::bind_method(D_METHOD("deck_height", "x", "z"), &SheetRopes::deck_height);
  ClassDB::bind_method(D_METHOD("route", "a", "b", "pivot", "side", "obstacles", "spacing", "max_ways"),
                       &SheetRopes::route);
  ClassDB::bind_method(D_METHOD("build_deck", "surfaces", "cell", "skirt", "dilate", "fall"), &SheetRopes::build_deck,
                       DEFVAL(0));
  ClassDB::bind_method(D_METHOD("attach_mesh", "mesh", "surface"), &SheetRopes::attach_mesh);
  ClassDB::bind_method(D_METHOD("vertex_bytes"), &SheetRopes::vertex_bytes);
  ClassDB::bind_method(D_METHOD("attribute_bytes"), &SheetRopes::attribute_bytes);
  ClassDB::bind_method(D_METHOD("write_mesh"), &SheetRopes::write_mesh);
}

}  // namespace windmark_godot
