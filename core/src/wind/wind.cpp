// wind.md, formulas evaluated as written: one rounding per operation, in the written order.
#include "wind/wind.h"

#include <cmath>

#include "math/rng.h"

namespace wm {

namespace {

constexpr std::uint64_t kShift = static_cast<std::uint64_t>(RngStream::wind_shift);
constexpr std::uint64_t kOsc = static_cast<std::uint64_t>(RngStream::wind_oscillation);
constexpr std::uint64_t kSlots = static_cast<std::uint64_t>(RngStream::puff_slots);
constexpr std::uint64_t kGens = static_cast<std::uint64_t>(RngStream::puff_generations);

bool finite(float f) { return std::isfinite(f); }

}  // namespace

void apply_shift_preset(WindSettings& s, ShiftPreset p) {
  float amp_deg = 0.0f;
  std::uint32_t hold_max = 0;
  switch (p) {
    case ShiftPreset::steady: amp_deg = 0.0f; hold_max = 0; break;
    case ShiftPreset::stable: amp_deg = 3.0f; hold_max = 120000; break;
    case ShiftPreset::oscillating: amp_deg = 8.0f; hold_max = 90000; break;
    case ShiftPreset::shifty: amp_deg = 15.0f; hold_max = 60000; break;
    case ShiftPreset::unstable: amp_deg = 25.0f; hold_max = 45000; break;
  }
  s.shift_amplitude = amp_deg * DEG;
  s.shift_hold_max_ms = hold_max;
  s.shift_hold_min_ms = hold_max / 5;
}

const char* check_wind_settings(const WindSettings& s) {
  const float fs[] = {s.base_speed, s.base_from, s.shift_amplitude, s.shift_trend_rate, s.shift_trend_max,
                      s.osc_amplitude, s.osc_time_scale, s.current_speed, s.current_to, s.tide_scale};
  for (float f : fs)
    if (!finite(f)) return "wind setting not finite";
  if (s.base_speed < 0.0f) return "base_speed must be >= 0";
  if (s.osc_enabled && !(s.osc_time_scale > 0.0f)) return "osc_time_scale must be > 0";
  if (s.tide_period_ms == 0) return "tide_period_ms must be > 0";
  const PuffParams& p = s.puffs;
  if (s.puffs_enabled) {
    const float pf[] = {p.tile, p.diameter_min, p.diameter_max, p.puff_strength_min, p.puff_strength_max,
                        p.lull_strength_min, p.lull_strength_max, p.cap_up, p.cap_down};
    for (float f : pf)
      if (!finite(f)) return "puff parameter not finite";
    if (!(p.tile > 0.0f)) return "puff_tile must be > 0";
    if (p.life_min_ms == 0 || p.life_max_ms < p.life_min_ms) return "puff lifetimes need 0 < min <= max";
    if (p.diameter_min <= 0.0f || p.diameter_max < p.diameter_min) return "puff diameters need 0 < min <= max";
    if (p.lull_strength_max >= 1.0f) return "lull strength must stay below 1";
    if (p.cap_down < 0.0f || p.cap_down >= 1.0f || p.cap_up < 0.0f) return "puff caps out of range";
  }
  if (const VenueWindField* v = s.venue_wind_field) {
    for (int k = 0; k < 8; ++k) {
      if (const char* r = check_grid(v->grid, v->f[k])) return r;
      if (const char* r = check_grid(v->grid, v->d[k])) return r;
      for (float f : v->f[k])
        if (f < 0.0f) return "venue wind speed factor must be >= 0";
    }
  }
  if (const VenueCurrentField* c = s.venue_current_field) {
    if (const char* r = check_grid(c->grid, c->vx)) return r;
    if (const char* r = check_grid(c->grid, c->vy)) return r;
  }
  return nullptr;
}

WindField::WindField(std::uint64_t race_seed, const WindSettings& s) : seed_(race_seed), s_(s) {
  // §4.1
  shift_enabled_ = s_.shift_amplitude >= 1e-5f && s_.shift_hold_max_ms > 0;
  A_ = clamp(s_.shift_amplitude, DEG, PI);
  B_ = min(1.4f * A_, PI);
  C_ = clamp(0.08f * A_ + 0.5f * (A_ * A_), 0.02f, 0.2f);
  hmax_ = s_.shift_hold_max_ms;
  hmin_ = s_.shift_hold_min_ms < hmax_ ? s_.shift_hold_min_ms : hmax_;
  // §5
  osc_t0_ = 1000.0f * rng_unit(seed_, kOsc, 0);
  // §6.2
  const PuffParams& p = s_.puffs;
  inv_tile_ = 1.0f / p.tile;
  const std::uint32_t n = p.puff_count + p.lull_count;
  life_.resize(n);
  off_.resize(n);
  for (std::uint32_t j = 0; j < n; ++j) {
    const std::uint32_t span = p.life_max_ms - p.life_min_ms;
    const std::uint32_t lr = static_cast<std::uint32_t>(rng_unit(seed_, kSlots, 2ull * j) * static_cast<float>(span + 1ull));
    life_[j] = p.life_min_ms + (lr < span ? lr : span);
    const std::uint32_t orr = static_cast<std::uint32_t>(rng_unit(seed_, kSlots, 2ull * j + 1) * static_cast<float>(life_[j]));
    off_[j] = orr < life_[j] - 1 ? orr : life_[j] - 1;
  }
  slot_cache_.resize(n);
}

// §4.2
ShiftSegment WindField::make_segment(std::uint32_t k, float o_prev, std::int64_t start) const {
  const float u_dir = rng_unit(seed_, kShift, 3ull * k);
  const float u_mag = rng_unit(seed_, kShift, 3ull * k + 1);
  const float u_hold = rng_unit(seed_, kShift, 3ull * k + 2);
  const float p_pos = 1.0f / (1.0f + wm_pow10(o_prev / (2.0f * A_)));
  const float sg = u_dir < p_pos ? 1.0f : -1.0f;
  const float m = clamp(0.45f - 0.35f * (sg * (o_prev / A_)), 0.0f, 0.8f);
  const float step = (sg * A_) * (0.2f + m * u_mag);
  ShiftSegment seg;
  seg.k = k;
  seg.start = start;
  seg.o_prev = o_prev;
  seg.o = clamp(o_prev + step, -B_, B_);
  seg.ramp = static_cast<std::uint32_t>((std::fabs(seg.o - o_prev) / C_) * 1000.0f + 0.5f);
  const std::uint32_t span = hmax_ - hmin_;
  const std::uint32_t hr = static_cast<std::uint32_t>(u_hold * static_cast<float>(span + 1ull));
  seg.hold = hmin_ + (hr < span ? hr : span);
  return seg;
}

ShiftSegment WindField::next_segment(const ShiftSegment& prev) const {
  return make_segment(prev.k + 1, prev.o, prev.end());
}

ShiftSegment WindField::segment(std::uint32_t k) const {
  ShiftSegment s = first_segment();
  while (s.k < k) s = next_segment(s);
  return s;
}

// §4.3: advance the cursor to the segment holding t (restart from k = 0 for an earlier t), then evaluate.
float WindField::shift_on(Cursor& c, std::uint32_t t) const {
  if (!shift_enabled_) return 0.0f;
  const std::int64_t tt = t;
  if (!c.valid || tt < c.seg.start) {
    c.seg = first_segment();
    c.valid = true;
  }
  while (tt >= c.seg.end()) c.seg = next_segment(c.seg);
  const ShiftSegment& g = c.seg;
  const std::int64_t tau = tt - g.start;
  if (tau < static_cast<std::int64_t>(g.ramp))
    return g.o_prev + (g.o - g.o_prev) * (static_cast<float>(tau) / static_cast<float>(g.ramp));
  return g.o;
}

float WindField::shift(std::uint32_t t) const {
  Cursor c;
  return shift_on(c, t);
}

// §3
float WindField::trend(std::uint32_t t) const {
  const float t_s = static_cast<float>(t) * 0.001f;
  return clamp(s_.shift_trend_rate * t_s, -s_.shift_trend_max, s_.shift_trend_max);
}

// §5
float WindField::osc(std::uint32_t t) const {
  if (!s_.osc_enabled) return 0.0f;
  const float t_o = static_cast<float>(t) * 0.001f + osc_t0_;
  const float tau = t_o / s_.osc_time_scale;
  const float a = wm_sin(((6.0f * tau) + wm_sin(0.8f * tau)) + wm_sin(8.47f * tau));
  const float b = wm_sin(wm_sin(tau) * wm_sin(3.0f * (tau + 7.0f)));
  const float c = wm_sin(2.0f * tau);
  return s_.osc_amplitude * (((0.5f * a) + b) + (0.3f * c));
}

float WindField::global_from_on(Cursor& c, std::uint32_t t) const {
  const float off = (shift_on(c, t) + trend(t)) + osc(t);
  return wrap_2pi(s_.base_from + off);
}

float WindField::dir_offset(std::uint32_t t) const { return (shift(t) + trend(t)) + osc(t); }

float WindField::global_from(std::uint32_t t) const {
  Cursor c;
  return global_from_on(c, t);
}

// §2 per-tick parts and §6.2, §6.3 for every slot.
void WindField::fill_tick(WindTick& out, std::uint32_t t, Cursor& walk, Cursor& birth_walk, SlotCache* cache) const {
  out.t = t;
  out.shift = shift_on(walk, t);
  out.trend = trend(t);
  out.osc = osc(t);
  out.dir_offset = (out.shift + out.trend) + out.osc;
  out.global_from = wrap_2pi(s_.base_from + out.dir_offset);
  const PuffParams& p = s_.puffs;
  const std::uint32_t n = static_cast<std::uint32_t>(life_.size());
  out.slots.resize(s_.puffs_enabled ? n : 0);
  if (!s_.puffs_enabled) return;
  for (std::uint32_t j = 0; j < n; ++j) {
    const std::uint64_t life = life_[j];
    const std::uint64_t q = static_cast<std::uint64_t>(t) + off_[j];
    const std::uint64_t g = q / life;
    const std::uint64_t a = q % life;
    const std::int64_t birth = static_cast<std::int64_t>(t) - static_cast<std::int64_t>(a);
    SlotCache fresh;
    SlotCache& sc = cache ? cache[j] : fresh;
    if (!sc.valid || sc.generation != g) {
      const std::uint64_t idx = (static_cast<std::uint64_t>(j) << 32) | g;
      const float u0 = rng_unit(seed_, kGens, 4 * idx + 0);
      const float u1 = rng_unit(seed_, kGens, 4 * idx + 1);
      const float u2 = rng_unit(seed_, kGens, 4 * idx + 2);
      const float u3 = rng_unit(seed_, kGens, 4 * idx + 3);
      sc.cx = u0 * p.tile;
      sc.cy = u1 * p.tile;
      sc.R = 0.5f * (p.diameter_min + u2 * (p.diameter_max - p.diameter_min));
      sc.s = j < p.puff_count ? p.puff_strength_min + u3 * (p.puff_strength_max - p.puff_strength_min)
                              : -(p.lull_strength_min + u3 * (p.lull_strength_max - p.lull_strength_min));
      const std::uint32_t tb = birth > 0 ? static_cast<std::uint32_t>(birth) : 0u;
      sc.fb = global_from_on(birth_walk, tb);
      sc.sb = s_.base_speed * (1.0f + sc.s);
      sc.generation = g;
      sc.valid = true;
    }
    const SinCos fsc = wm_sincos(sc.fb);
    const float age_s = static_cast<float>(a) * 0.001f;
    PuffPatch& pp = out.slots[j];
    pp.slot = j;
    pp.generation = g;
    pp.px = sc.cx + (-sc.sb * fsc.s) * age_s;
    pp.py = sc.cy + (-sc.sb * fsc.c) * age_s;
    pp.R = sc.R;
    pp.s = sc.s;
    const float fl = static_cast<float>(life);
    const float fa = static_cast<float>(a);
    pp.e = fa < 0.1f * fl ? fa / (0.1f * fl) : (fa < 0.9f * fl ? 1.0f : (fl - fa) / (0.1f * fl));
    pp.age_ms = static_cast<std::uint32_t>(a);
    pp.life_ms = static_cast<std::uint32_t>(life);
  }
}

WindTick WindField::at(std::uint32_t t) const {
  WindTick out;
  Cursor walk, birth_walk;
  fill_tick(out, t, walk, birth_walk, nullptr);
  return out;
}

const WindTick& WindField::advance(std::uint32_t t) {
  fill_tick(tick_, t, walk_, birth_walk_, slot_cache_.data());
  return tick_;
}

// §6.4
float WindField::puff_factor(const WindTick& tick, float x, float y) const {
  if (!s_.puffs_enabled) return 1.0f;
  const float tile = s_.puffs.tile;
  float m = 1.0f;
  for (const PuffPatch& pp : tick.slots) {
    if (pp.e < 1e-4f) continue;
    const float ux = x - pp.px;
    const float uy = y - pp.py;
    const float dx = ux - tile * std::floor(ux * inv_tile_ + 0.5f);
    const float dy = uy - tile * std::floor(uy * inv_tile_ + 0.5f);
    const float r2 = dx * dx + dy * dy;
    const float R2 = pp.R * pp.R;
    if (r2 <= R2) m = m * (1.0f + (pp.e * pp.s) * (1.0f - r2 / R2));
  }
  return clamp(m, 1.0f - s_.puffs.cap_down, 1.0f + s_.puffs.cap_up);
}

std::vector<PuffPatch> WindField::puff_patches(const WindTick& tick) const {
  std::vector<PuffPatch> out;
  for (const PuffPatch& pp : tick.slots)
    if (!(pp.e < 1e-4f)) out.push_back(pp);
  return out;
}

// §8: speed factor, and the direction offset in `d`. Outside the grid both sectors give (1, 0), so the blend is
// exactly (1, 0) and is returned directly.
float WindField::venue_lookup(float x, float y, float from, float& d) const {
  const VenueWindField* v = s_.venue_wind_field;
  d = 0.0f;
  if (!v) return 1.0f;
  const GridCell c = grid_locate(v->grid, x, y);
  if (!c.inside) return 1.0f;
  const float w = from / QUARTER_PI;
  const float fw = std::floor(w);
  const std::uint32_t k0 = static_cast<std::uint32_t>(static_cast<std::int32_t>(fw)) & 7u;
  const std::uint32_t k1 = (k0 + 1) & 7u;
  const float tw = w - fw;
  const float f0 = grid_lerp(v->grid, v->f[k0], c), d0 = grid_lerp(v->grid, v->d[k0], c);
  const float f1 = grid_lerp(v->grid, v->f[k1], c), d1 = grid_lerp(v->grid, v->d[k1], c);
  d = lerp(d0, d1, tw);
  return lerp(f0, f1, tw);
}

// §2
WindSample WindField::wind_clean(const WindTick& tick, float x, float y) const {
  float d;
  const float f = venue_lookup(x, y, tick.global_from, d);
  const float m = s_.puffs_enabled ? puff_factor(tick, x, y) : 1.0f;
  return {(s_.base_speed * f) * m, wrap_2pi(tick.global_from + d)};
}

// §7
Vec2 WindField::current(float x, float y, std::uint32_t t) const {
  const SinCos sc = wm_sincos(s_.current_to);
  const float ux = s_.current_speed * sc.s;
  const float uy = s_.current_speed * sc.c;
  float fx = 0.0f, fy = 0.0f;
  if (const VenueCurrentField* v = s_.venue_current_field) {
    const GridCell c = grid_locate(v->grid, x, y);
    if (c.inside) {
      fx = grid_lerp(v->grid, v->vx, c);
      fy = grid_lerp(v->grid, v->vy, c);
    }
  }
  // (t + tide_phase_ms) in 64 bits so it never wraps before the modulo.
  const std::uint64_t ph = (static_cast<std::uint64_t>(t) + s_.tide_phase_ms) % s_.tide_period_ms;
  const float tide =
      s_.tide_scale * wm_cos(TWO_PI * (static_cast<float>(ph) / static_cast<float>(s_.tide_period_ms)));
  return {ux + tide * fx, uy + tide * fy};
}

}  // namespace wm
