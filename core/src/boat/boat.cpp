#include "boat/boat.h"

#include <cmath>

#include "math/rng.h"
#include "math/wm_math.h"

namespace wm {

namespace {

constexpr float V_MAX = 40.0f;        // m/s, a data-error guard (boat.md §5.8)
constexpr float ACCEL_BLEND = 0.5f;   // share of the target speed where accel_rest has blended into accel (§5.8)
constexpr float CONTACT_KEEP = 0.9f;  // per tick (collisions.md §6)
constexpr float DRIFT_GRIP_MAX = 2.0f;  // m/s, the grip speed never exceeds it (boat.md §5.9, §6.4)

}  // namespace

void Boat::init(const PerfData* perf, std::uint64_t race_seed, std::uint32_t index) {
  perf_ = perf;
  seed_ = race_seed;
  index_ = index;
  hull_ = make_hull_points(perf->dynamics);
  sails_.init(perf);
  s_ = BoatState{};
  ctl_ = BoatControls{};
  out_ = BoatOutputs{};
}

void Boat::set_helm(float h_cmd) { ctl_.h_cmd = std::isnan(h_cmd) ? 0.0f : clamp(h_cmd, -1.0f, 1.0f); }

void Boat::set_sheet(float sheet_cmd) {
  if (!std::isnan(sheet_cmd)) ctl_.sheet_cmd = clamp(sheet_cmd, 0.0f, 1.0f);
}

void Boat::set_performance_scale(float scale) {
  // boat.md §2: (0, 2]. NaN is the neutral 1; zero and below are held at a small positive value.
  ctl_.performance_scale = std::isnan(scale) ? 1.0f : clamp(scale, 0.01f, 2.0f);
}

// boat.md §5.1
void Boat::wind_triangle(const BoatEnv& env) {
  const SinCos wf = wm_sincos(env.wind_from);
  const float wx = -env.wind_speed * wf.s;
  const float wy = -env.wind_speed * wf.c;
  const float tx = wx - env.current_x;
  const float ty = wy - env.current_y;
  s_.tws = std::sqrt(tx * tx + ty * ty);
  if (s_.tws >= 1e-4f) s_.twd_from = compass({-tx, -ty});
  const SinCos hs = wm_sincos(s_.psi);
  const float bx = s_.v * hs.s + s_.sway * hs.c;
  const float by = s_.v * hs.c - s_.sway * hs.s;
  const float ax = tx - bx;
  const float ay = ty - by;
  s_.aws = std::sqrt(ax * ax + ay * ay);
  if (s_.aws >= 1e-4f) s_.awd_from = compass({-ax, -ay});
  s_.twa = wrap_pi(s_.twd_from - s_.psi);
  s_.awa = wrap_pi(s_.awd_from - s_.psi);
  out_.wind_speed_clean = env.wind_speed_clean;
}

// boat.md §6.6
void Boat::reset(float pos_x, float pos_y, float psi, float v, std::int32_t front_sail, bool auto_trim,
                 const BoatEnv& env) {
  s_ = BoatState{};
  s_.pos_x = pos_x;
  s_.pos_y = pos_y;
  s_.psi = wrap_2pi(psi);
  s_.v = clamp(v, -V_MAX, V_MAX);
  s_.wobble_phase = TWO_PI * rng_unit(seed_, RngStream::attitude_wobble, index_);
  ctl_.h_cmd = 0.0f;
  ctl_.auto_trim = auto_trim;
  ctl_.let_fly = false;
  const HullSample hs = sample_hull(hull_, env.sea, s_.pos_x, s_.pos_y, s_.psi);
  s_.z = hs.hm + perf_->dynamics.waterline_offset;

  sails_.reset(front_sail);
  // A calm placement has no wind direction yet; start both directions from the given wind_from.
  s_.twd_from = wrap_2pi(env.wind_from);
  s_.awd_from = s_.twd_from;
  wind_triangle(env);
  TrimInput ti{s_.awa, s_.tws, s_.phi, ctl_.sheet_cmd, ctl_.auto_trim, ctl_.let_fly};
  sails_.trim(ti, /*place=*/true);

  const SinCos sc = wm_sincos(s_.psi);
  s_.v_filt = s_.v;
  s_.sog_filt_x = s_.v * sc.s + env.current_x;
  s_.sog_filt_y = s_.v * sc.c + env.current_y;
  out_ = BoatOutputs{};
  out_.sog = std::sqrt(s_.sog_filt_x * s_.sog_filt_x + s_.sog_filt_y * s_.sog_filt_y);
  out_.cog = out_.sog >= 1e-4f ? compass({s_.sog_filt_x, s_.sog_filt_y}) : s_.psi;
  out_.wind_speed_clean = env.wind_speed_clean;
}

void Boat::step(const BoatEnv& env) {
  const Dynamics& d = perf_->dynamics;
  const DerivedDynamics& k = d.derived;

  // 5.1 wind triangle
  wind_triangle(env);
  const float tack = sgn(s_.twa);
  const bool upwind = std::fabs(s_.twa) < HALF_PI;

  // 5.2 helm
  const float dh = clamp(ctl_.h_cmd - s_.h, -d.helm_rate * DT, d.helm_rate * DT);
  s_.h = s_.h + dh;

  // 5.3 sail changes, 5.4 trim
  sails_.advance(s_.tws, std::fabs(s_.twa));
  const TrimInput ti{s_.awa, s_.tws, s_.phi, ctl_.sheet_cmd, ctl_.auto_trim, ctl_.let_fly};
  sails_.trim(ti);
  const float eps = sails_.driving_trim_error();

  // 5.5 performance lookups
  const ConfigPerf& c = sails_.config();
  const float ta = std::fabs(s_.twa);
  const float aa = std::fabs(s_.awa);
  const float polar_speed = c.polar.at(s_.tws, ta);
  const float heel_mag = c.heel.at(s_.tws, ta);
  const float accel = c.accel.at(s_.tws, ta);
  const float accel_rest = c.accel_rest.present ? c.accel_rest.table.at(s_.tws, ta) : accel;
  const float trim_speed = c.trim_speed.present ? c.trim_speed.table.at(s_.tws, aa, eps) : 1.0f;
  // The trimmed boat's apparent wind (at the polar speed): the heel table's state. Over-sheeted, trim_heel is
  // looked up there (the stall's heel over the trimmed heel at that state); the sail heel then follows the
  // boat's own apparent wind speed (boat.md §5.5, §5.7).
  float aws_p = s_.aws, aa_p = aa;
  if (polar_speed > 0.0f) {
    const float wx = s_.tws * wm_cos(ta) + polar_speed, wy = s_.tws * wm_sin(ta);
    aws_p = std::sqrt(wx * wx + wy * wy);
    aa_p = wm_atan2(wy, wx);
  }
  const float heel_wind = aws_p > 0.01f ? (s_.aws * s_.aws) / (aws_p * aws_p) : 1.0f;
  const float trim_heel = c.trim_heel.present ? c.trim_heel.table.at(s_.tws, eps < 0.0f ? aa_p : aa, eps) : 1.0f;
  // sails.md §6: the weather-helm rate is scaled by trim_heel.
  const float helm_luff = c.weather_helm.present ? c.weather_helm.table.at(s_.tws, ta) * trim_heel : 0.0f;
  const float helm_fall = c.fall_off.present ? c.fall_off.table.at(s_.v, ta) : 0.0f;
  // §5.8: the sails eased toward the wind line flog on their free sheets and brake the boat.
  const float flog = c.flog_drag.present ? c.flog_drag.table.at(s_.aws, aa) : 0.0f;

  // 5.6 waves: heave and pitch; wobble (§6.5)
  const HullSample hs = sample_hull(hull_, env.sea, s_.pos_x, s_.pos_y, s_.psi);
  // how the heeled hull floats: it rises and trims (the previous tick's heel); absent tables add an exact 0
  const float heel_abs = std::fabs(s_.phi);
  const float heel_rise = d.heel_rise.present ? d.heel_rise.table.at(heel_abs) : 0.0f;
  const float heel_trim = d.heel_trim.present ? d.heel_trim.table.at(heel_abs) : 0.0f;
  s_.z = s_.z + k.heave_a * (((hs.hm + d.waterline_offset) + heel_rise) - s_.z);
  const float wk = 0.4f + s_.tws * 0.0388769f;
  s_.wobble_phase = wrap_2pi(s_.wobble_phase + (d.wobble_freq * wk) * DT);
  const float theta_target =
      (d.wave_pitch_gain * hs.wave_pitch + (d.wobble_pitch * wk) * wm_sin(s_.wobble_phase)) + heel_trim;
  s_.theta_rate = k.pitch_k2 * s_.theta_rate + k.pitch_k1 * (theta_target - s_.theta);
  s_.theta = s_.theta + s_.theta_rate * DT;

  // 5.7 heel
  const float heel_sail = clamp(((-tack * heel_mag) * trim_heel) * heel_wind, -d.heel_max, d.heel_max);
  const float heel_target = clamp(heel_sail + d.wave_roll_gain * hs.wave_roll, -d.heel_max, d.heel_max) +
                            (d.wobble_heel * wk) * wm_sin(s_.wobble_phase + 1.7f);
  s_.phi_rate = k.heel_k2 * s_.phi_rate + k.heel_k1 * (heel_target - s_.phi);
  s_.phi = s_.phi + s_.phi_rate * DT;
  if (std::fabs(s_.phi) > d.heel_limit) {
    s_.phi = sgn(s_.phi) * d.heel_limit;
    s_.phi_rate = 0.0f;
  }

  // 5.8 speed
  const float man_coef = sails_.man_coef(s_.twa);
  const float heel_coef = d.heel_speed_factor.at(std::fabs(s_.phi));
  // Surfing follows the wave part of the pitch target only; the wobble moves the hull but not the speed.
  const float theta_w = d.wave_pitch_gain * hs.wave_pitch;
  float surf_coef = 1.0f;
  if (upwind) {
    if (theta_w > 0.0f) surf_coef = max(0.0f, 1.0f - d.surf_gain * theta_w);
  } else {
    if (theta_w < 0.0f) surf_coef = 1.0f + (0.5f * d.surf_gain) * (-theta_w);
  }
  // Trim scales the drive only. Inside the no-go zone the (negative) polar is the windage drift of the rig, which
  // flogging sails do not remove; scaling it by trim_speed (0 with the sails on the wind line) would stop the boat
  // dead head to wind instead of letting it gather sternway (boat.md §7.4, §10.4).
  const float trim_drive = polar_speed > 0.0f ? trim_speed : 1.0f;
  const float target_speed =
      ((((polar_speed * trim_drive) * man_coef) * heel_coef) * surf_coef) * ctl_.performance_scale;
  const float err = target_speed - s_.v;
  float a = accel;
  if (err > 0.0f && target_speed > 0.0f) {
    // From rest the drive meets no hull resistance: the rate falls from accel_rest at rest (and in sternway) to
    // accel at half the target speed (boat.md §5.8).
    const float v_b = ACCEL_BLEND * target_speed;
    if (s_.v < v_b) a = accel_rest + (accel - accel_rest) * (max(s_.v, 0.0f) / v_b);
  }
  if (!(err > 0.0f)) {
    // Coast before drifting: a boat still making way loses it toward 0 first; only a stopped or backing boat is
    // pulled toward the negative drift of the no-go zone (boat.md §5.8, §7.4).
    const float err_d = (s_.v > 0.0f ? max(target_speed, 0.0f) : target_speed) - s_.v;
    // Windage of hull, rig and luffing sails at this tick's apparent wind, 0 abaft the beam (boat.md §5.8).
    a = (d.decel_linear * err_d - d.decel_const) - decel_wind();
    // Flogging drag: with the sheets free (let fly, or the manual sheet eased) the share of the drive the sails
    // have lost is sails flogging on the wind line (let fly: all of it); over-sheeted, stalled sails do not flog,
    // and the auto-trim crew never lets them. Only while the boat makes way ahead.
    const bool free_sheets = ctl_.let_fly || !ctl_.auto_trim;
    if (free_sheets && s_.v > 0.0f && eps > 0.0f) a = a - (1.0f - trim_speed) * flog;
    if (std::fabs(err_d) < DT * std::fabs(a)) a = err_d / DT;
  } else if (err < DT * a) {
    a = err / DT;
  }
  s_.v = s_.v + DT * a;
  const bool turning_up = (s_.h * tack) > 0.0f;
  const Table& drag_t = turning_up ? d.rudder_drag_luff : d.rudder_drag_bear;
  const float drag = drag_t.at(std::fabs(s_.v), std::fabs(s_.h));
  s_.v = s_.v - sgn(s_.v) * min(DT * drag, std::fabs(s_.v));
  s_.v = clamp(s_.v, -V_MAX, V_MAX);

  // 5.9 sideways drift (boat.md §6.4): a boat with next to no way on is pushed to leeward by its windage until the
  // keel grips; the target follows from the drift tables, the speed and the sheets, the sway from its inertia.
  if (d.has_drift) {
    const bool free_sheets = ctl_.let_fly || !ctl_.auto_trim;
    const float s_l = c.drift.present ? c.drift.table.at(s_.tws, ta) : 0.0f;
    float s_d = s_l;
    if (free_sheets && eps > 0.0f && c.drift_flog.present) {
      // The push goes with the square of the drift: the flogging share of it is the drive the trim has lost.
      const float s_f = c.drift_flog.table.at(s_.tws, ta);
      s_d = std::sqrt(s_l * s_l + (1.0f - trim_speed) * (s_f * s_f - s_l * s_l));
    }
    const float v_g = min(d.drift_grip * s_d, DRIFT_GRIP_MAX);
    const float u = v_g > 0.0f ? max(1.0f - std::fabs(s_.v) / v_g, 0.0f) : 0.0f;
    const float g = u * u;
    float sway_t = -tack * (g * s_d);
    if (d.full_leeway && c.leeway.present) {
      const float lw = c.leeway.table.at(s_.tws, ta) * trim_heel;
      sway_t = sway_t + (1.0f - g) * (-tack * (max(s_.v, 0.0f) * (wm_sin(lw) / wm_cos(lw))));
    }
    const float lam = ((2.0f * max(std::fabs(sway_t), std::fabs(s_.sway)) + k.drift_lift * std::fabs(s_.v)) /
                       d.drift_length) * DT;
    s_.sway = s_.sway + min(lam, 1.0f) * (sway_t - s_.sway);
    if (sway_t == 0.0f && std::fabs(s_.sway) < 1e-4f) s_.sway = 0.0f;
  }

  // 5.9 turning and translation
  const float n = std::fabs(s_.h);
  float turn_arc = 0.0f;
  if (n >= 1e-5f) {
    const float r = max(k.turn_c / n - d.turn_radius_offset, 0.5f);
    turn_arc = (s_.v / r) * sgn(s_.h);
  }
  // Yaw inertia: the hull's yaw rate follows the steady rate of helm, helm balance and fall-off over yaw_time,
  // building and dying away alike; collisions add theirs without the lag (boat.md §5.9).
  const float turn_hull = (turn_arc + tack * helm_luff) - tack * helm_fall;
  s_.yaw_rate = s_.yaw_rate + k.yaw_a * (turn_hull - s_.yaw_rate);
  const float turn_rate = s_.yaw_rate + s_.contact_yaw_rate;
  const float dpsi = turn_rate * DT;
  const float mid = s_.psi + 0.5f * dpsi;
  const SinCos ms = wm_sincos(mid);
  s_.pos_x = s_.pos_x + (((s_.v * ms.s + s_.sway * ms.c) + env.current_x) + s_.contact_vx) * DT;
  s_.pos_y = s_.pos_y + (((s_.v * ms.c - s_.sway * ms.s) + env.current_y) + s_.contact_vy) * DT;
  s_.psi = wrap_2pi(s_.psi + dpsi);

  // 5.10 contacts and outputs
  s_.contact_vx = s_.contact_vx * CONTACT_KEEP;
  s_.contact_vy = s_.contact_vy * CONTACT_KEEP;
  s_.contact_yaw_rate = s_.contact_yaw_rate * CONTACT_KEEP;
  const SinCos ps = wm_sincos(s_.psi);
  const float gx = ((s_.v * ps.s + s_.sway * ps.c) + env.current_x) + s_.contact_vx;
  const float gy = ((s_.v * ps.c - s_.sway * ps.s) + env.current_y) + s_.contact_vy;
  out_.sog = std::sqrt(gx * gx + gy * gy);
  out_.vmg = s_.v * wm_cos(s_.twa);
  s_.v_filt = s_.v_filt + DerivedDynamics::FILT_A * (s_.v - s_.v_filt);
  s_.sog_filt_x = s_.sog_filt_x + DerivedDynamics::FILT_A * (gx - s_.sog_filt_x);
  s_.sog_filt_y = s_.sog_filt_y + DerivedDynamics::FILT_A * (gy - s_.sog_filt_y);
  // cog from the filtered ground velocity, so a loaded snapshot rebuilds it from the state (boat.md §5.10).
  const float sf = std::sqrt(s_.sog_filt_x * s_.sog_filt_x + s_.sog_filt_y * s_.sog_filt_y);
  if (sf >= 1e-4f) out_.cog = compass({s_.sog_filt_x, s_.sog_filt_y});

  out_.target_speed = target_speed;
  out_.polar_speed = polar_speed;
  out_.heel_target = heel_target;
  out_.turn_rate = turn_rate;
  out_.man_coef = man_coef;
  out_.trim_speed = trim_speed;
  out_.trim_heel = trim_heel;
  out_.heel_coef = heel_coef;
  out_.surf_coef = surf_coef;
}

float Boat::polar_at(float tws, float twa, std::int32_t front_sail) const {
  const ConfigPerf* c = perf_->config_for(front_sail);
  return c != nullptr ? c->polar.at(tws, std::fabs(twa)) : 0.0f;
}

float Boat::accel_at(float tws, float twa, std::int32_t front_sail) const {
  const ConfigPerf* c = perf_->config_for(front_sail);
  return c != nullptr ? c->accel.at(tws, std::fabs(twa)) : 0.0f;
}

float Boat::decel_wind() const {
  const Dynamics& d = perf_->dynamics;
  return (d.decel_windage * s_.aws) * max(wm_cos(s_.awa), 0.0f);
}

Vec2 Boat::drift_velocity() const {
  const SinCos hs = wm_sincos(s_.psi);
  return {s_.sway * hs.c, -(s_.sway * hs.s)};
}

float Boat::let_fly_drive() const {
  const ConfigPerf& c = sails_.config();
  if (!c.trim_speed.present) return 1.0f;
  const std::size_t d = static_cast<std::size_t>(sails_.driving_sail());
  const SailPerf& sp = perf_->sails[d];
  const float lim = sp.sheet_max_by_heel.present
                        ? min(sp.sheet_max, sp.sheet_max_by_heel.table.at(std::fabs(s_.phi)))
                        : sp.sheet_max;
  const float aa = std::fabs(s_.awa);
  const float m = min(clamp(sp.sheet_max, sp.sheet_min, lim), aa);
  return c.trim_speed.table.at(s_.tws, aa, m - sails_.output(d).m_opt);
}

float Boat::turn_radius(float helm) const {
  const float n = std::fabs(helm);
  if (!(n >= 1e-5f)) return 1e9f;
  return max(perf_->dynamics.derived.turn_c / n - perf_->dynamics.turn_radius_offset, 0.5f);
}

void Boat::save(SnapshotWriter& w) const {
  const float f[] = {s_.pos_x,      s_.pos_y,      s_.z,          s_.psi,        s_.v,         s_.sway,
                     s_.h,          s_.yaw_rate,   s_.phi,        s_.phi_rate,   s_.theta,      s_.theta_rate,
                     s_.wobble_phase, s_.contact_vx, s_.contact_vy, s_.contact_yaw_rate,
                     s_.twd_from,   s_.awd_from,   s_.tws,        s_.twa,        s_.aws,
                     s_.awa,        s_.v_filt,     s_.sog_filt_x, s_.sog_filt_y};
  for (float x : f) w.put_f32(x);
  w.put_f32(ctl_.h_cmd);
  w.put_f32(ctl_.sheet_cmd);
  w.put_bool(ctl_.auto_trim);
  w.put_bool(ctl_.let_fly);
  w.put_f32(ctl_.performance_scale);
  sails_.save(w);
}

bool Boat::load(SnapshotReader& r) {
  float* f[] = {&s_.pos_x,      &s_.pos_y,      &s_.z,          &s_.psi,        &s_.v,         &s_.sway,
                &s_.h,          &s_.yaw_rate,   &s_.phi,        &s_.phi_rate,   &s_.theta,      &s_.theta_rate,
                &s_.wobble_phase, &s_.contact_vx, &s_.contact_vy, &s_.contact_yaw_rate,
                &s_.twd_from,   &s_.awd_from,   &s_.tws,        &s_.twa,        &s_.aws,
                &s_.awa,        &s_.v_filt,     &s_.sog_filt_x, &s_.sog_filt_y};
  for (float* x : f) *x = r.get_f32();
  ctl_.h_cmd = r.get_f32();
  ctl_.sheet_cmd = r.get_f32();
  ctl_.auto_trim = r.get_bool();
  ctl_.let_fly = r.get_bool();
  ctl_.performance_scale = r.get_f32();
  if (!sails_.load(r) || r.failed()) return false;
  // Derived outputs that carry a previous value (cog when stopped) are rebuilt from the state.
  const float gx = s_.sog_filt_x, gy = s_.sog_filt_y;
  out_.sog = std::sqrt(gx * gx + gy * gy);
  out_.cog = out_.sog >= 1e-4f ? compass({gx, gy}) : s_.psi;
  return true;
}

}  // namespace wm
