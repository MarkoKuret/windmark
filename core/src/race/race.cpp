#include "race/race.h"

#include <algorithm>
#include <cmath>

#include "course/geometry.h"
#include "math/rng.h"

namespace wm {

std::string_view score_code_name(ScoreCode c) {
  switch (c) {
    case ScoreCode::none: return "";
    case ScoreCode::ZFP: return "ZFP";
    case ScoreCode::DNC: return "DNC";
    case ScoreCode::DNS: return "DNS";
    case ScoreCode::OCS: return "OCS";
    case ScoreCode::UFD: return "UFD";
    case ScoreCode::BFD: return "BFD";
    case ScoreCode::DNF: return "DNF";
    case ScoreCode::RET: return "RET";
    case ScoreCode::DSQ: return "DSQ";
  }
  return "?";
}

namespace {

constexpr std::int64_t kTicksPerSecond = 20;

std::int64_t ticks_ceil(float seconds) { return static_cast<std::int64_t>(std::ceil(seconds / DT)); }

// race.md §3.2: signal offsets from the gun in seconds: warning, prep up, prep down, start.
void signal_offsets(SequenceKind k, std::int64_t out[4]) {
  const std::int64_t w = k == SequenceKind::s3210 ? 180 : 300;
  out[0] = -w;
  out[1] = -(w - 60);
  out[2] = -60;
  out[3] = 0;
}

std::int32_t bow_index(const std::vector<Vec2>& outline) {
  std::int32_t best = 0;
  for (std::size_t k = 1; k < outline.size(); ++k) {
    if (outline[k].x > outline[static_cast<std::size_t>(best)].x) best = static_cast<std::int32_t>(k);
  }
  return best;
}

// Distance from p to a course object's surface.
float object_gap(const CourseObject& o, Vec2 p) {
  if (!o.is_boat) return v_dist(p, o.c) - o.r;
  if (point_in_polygon(p, o.polygon)) return 0.0f;
  return point_polygon_edge_dist(p, o.polygon);
}

// race.md §5.1 winding set-up for mark M, side, previous and next references.
struct Winding {
  float phi0, done;
};

Winding winding_init(Vec2 M, Side side, Vec2 P, Vec2 N, Vec2 N2, Vec2 c) {
  const float sigma = side == Side::port ? 1.0f : -1.0f;
  Vec2 n = N;
  if (v_dist(n, M) < 1.0f) n = N2;
  const float a_out = compass(v_sub(n, M));
  const float a_in = v_dist(P, M) < 1.0f ? wrap_2pi(a_out + sigma * PI) : compass(v_sub(P, M));
  float sweep = wrap_2pi(sigma * (a_in - a_out));
  // race.md §5.1: a course that turns away from the mark by more than 150° is a turn around it (leeward gates).
  if (sweep < 0.523598776f) sweep = sweep + TWO_PI;
  const float done = max(HALF_PI, sweep - HALF_PI);
  const float phi0 = sigma * wrap_pi(a_in - compass(v_sub(c, M)));
  return {phi0, done};
}

}  // namespace

// ---- Lines ----

float Race::Line::s(Vec2 p) const { return side_left(p, a, b) / len; }
float Race::Line::u(Vec2 p) const { return v_dot(v_sub(p, a), d) / (len * len); }

float Race::start_s(Vec2 p) const { return start_.s(p); }
float Race::start_u(Vec2 p) const { return start_.u(p); }
float Race::finish_s(Vec2 p) const { return finish_.s(p); }
float Race::finish_u(Vec2 p) const { return 1.0f - finish_.u(p); }

Vec2 Race::bow(std::size_t i) const {
  const RaceBoat& b = boats_[i];
  const std::vector<Vec2>& o = b.perf->dynamics.collision.outline;
  return place_point(o[static_cast<std::size_t>(bow_index(o))], b.c, b.psi);
}

Race::Crossing Race::hull_cross(const std::vector<Vec2>& p0, const std::vector<Vec2>& p1, const Line& line) const {
  Crossing r;
  for (std::size_t k = 0; k < p1.size(); ++k) {
    const float s0 = line.s(p0[k]), s1 = line.s(p1[k]);
    if (!(s0 <= 0.0f && 0.0f < s1)) continue;
    const float f = s0 / (s0 - s1);
    const Vec2 q{p0[k].x + f * (p1[k].x - p0[k].x), p0[k].y + f * (p1[k].y - p0[k].y)};
    const float u = line.u(q);
    if (u >= 0.0f && u <= 1.0f && (!r.crossed || f < r.f)) {
      r.crossed = true;
      r.f = f;
    }
  }
  return r;
}

bool Race::all_pre_start(const std::vector<Vec2>& hull) const {
  for (const Vec2 p : hull) {
    if (start_.s(p) > 0.0f) return false;
  }
  return true;
}

bool Race::point_in_start_triangle(Vec2 p) const {
  const Vec2 A = start_.a, B = start_.b, C = first_ref_;
  const float d1 = side_left(p, A, B), d2 = side_left(p, B, C), d3 = side_left(p, C, A);
  const bool neg = d1 < 0.0f || d2 < 0.0f || d3 < 0.0f;
  const bool pos = d1 > 0.0f || d2 > 0.0f || d3 > 0.0f;
  return !(neg && pos);
}

// ---- Spawning (race.md §3.5) ----

std::vector<Vec2> spawn_slots(const ResolvedCourse& course, const VenueData* venue, float L, std::size_t n) {
  const Vec2 A = course.end_a(course.start()), B = course.end_b(course.start());
  const float len = v_dist(A, B);
  const Vec2 d = v_unit(v_sub(B, A), {1.0f, 0.0f});
  const Vec2 pre{d.y, -d.x};  // right of A→B: the pre-start side
  const Vec2 mid = v_mid(A, B);
  const float step = 3.0f * L;
  const std::int32_t J = static_cast<std::int32_t>(std::floor(len / step));
  std::vector<Vec2> out;
  for (std::int32_t k = 0; k < 200 && out.size() < n; ++k) {
    const float dk = (4.0f + 3.0f * static_cast<float>(k)) * L;
    const Vec2 rc{mid.x + pre.x * dk, mid.y + pre.y * dk};
    for (std::int32_t j = -J; j <= J; ++j) {
      const float o = static_cast<float>(j) * step;
      const Vec2 p{rc.x + d.x * o, rc.y + d.y * o};
      bool ok = true;
      for (const CourseObject& obj : course.objects) {
        if (object_gap(obj, p) < 2.0f * L) ok = false;
      }
      if (venue != nullptr) {
        for (const VenueObstacle& ob : venue->obstacles) {
          const float g = ob.is_circle ? v_dist(p, ob.c) - ob.r
                                       : (point_in_polygon(p, ob.polygon) ? 0.0f : point_polygon_edge_dist(p, ob.polygon));
          if (g < 2.0f * L) ok = false;
        }
        for (const VenueLand& l : venue->land) {
          if (point_in_polygon(p, l.points) || point_polygon_edge_dist(p, l.points) < 2.0f * L) ok = false;
        }
      }
      if (course.has_spawn && !point_in_polygon(p, course.spawn)) ok = false;
      if (ok) out.push_back(p);
    }
  }
  return out;
}

std::vector<std::int32_t> spawn_order(std::uint64_t race_seed, std::int32_t n) {
  std::vector<std::int32_t> v(static_cast<std::size_t>(n));
  for (std::int32_t i = 0; i < n; ++i) v[static_cast<std::size_t>(i)] = i;
  for (std::int32_t k = n - 1; k >= 1; --k) {
    const float r = rng_unit(race_seed, RngStream::spawn_shuffle, static_cast<std::uint64_t>(k));
    std::uint32_t j = static_cast<std::uint32_t>(r * static_cast<float>(k + 1));
    if (j > static_cast<std::uint32_t>(k)) j = static_cast<std::uint32_t>(k);
    std::swap(v[static_cast<std::size_t>(k)], v[j]);
  }
  return v;
}

// ---- Set-up ----

std::int32_t Race::add_boat(const PerfData* perf, bool human) {
  // race.md §3.5: joining is allowed until the preparatory signal.
  if (state_ != RaceState::created && (signals_done_ >= 2 || state_ == RaceState::closed ||
                                       state_ == RaceState::abandoned || race_type_ == RaceType::match)) {
    return -1;
  }
  RaceBoat b;
  b.perf = perf;
  b.human = human;
  b.L = perf->dynamics.loa;
  b.B = perf->dynamics.bwl;
  boats_.push_back(std::move(b));
  const std::int32_t i = static_cast<std::int32_t>(boats_.size() - 1);
  if (state_ != RaceState::created) {
    boats_.back().joined_tick = 0;
    L_max_ = max(L_max_, boats_.back().L);
    RaceEvent e;
    e.kind = RaceEventKind::joined;
    e.boat = i;
    emit(e);
  }
  return i;
}

std::int64_t Race::gun_after_creation(const RaceSettings& s, const CourseRaceDefaults& course) {
  const RaceType type = s.race_type ? *s.race_type : (course.has_type ? course.type : RaceType::fleet);
  SequenceKind seq;
  if (s.sequence) seq = *s.sequence;
  else if (course.has_sequence) seq = course.sequence;
  else seq = type == RaceType::match ? SequenceKind::match : SequenceKind::s5410;
  std::int64_t off[4];
  signal_offsets(seq, off);
  return ticks_ceil(s.free_sailing_s + static_cast<float>(-off[0]));
}

bool Race::create(const ResolvedCourse& course, const RaceSettings& s, std::uint32_t n_created, float twd_mean,
                  std::string& error) {
  if (course.steps.size() < 3) {
    error = "the course has no step between start and finish";
    return false;
  }
  settings_ = s;
  course_ = course;
  race_type_ = s.race_type ? *s.race_type : (course.race.has_type ? course.race.type : RaceType::fleet);
  if (s.sequence) sequence_ = *s.sequence;
  else if (course.race.has_sequence) sequence_ = course.race.sequence;
  else sequence_ = race_type_ == RaceType::match ? SequenceKind::match : SequenceKind::s5410;
  if (s.prep_flag) prep_flag_ = *s.prep_flag;
  else if (course.race.has_prep_flag) prep_flag_ = course.race.prep_flag;
  else prep_flag_ = race_type_ == RaceType::match ? PrepFlag::P : PrepFlag::I;
  if (race_type_ == RaceType::match && boats_.size() != 2) {
    error = "a match race has two boats";
    return false;
  }
  if (boats_.empty()) {
    error = "no boats";
    return false;
  }
  L_max_ = 0.0f;
  for (const RaceBoat& b : boats_) L_max_ = max(L_max_, b.L);

  n_created_ = n_created;
  std::int64_t off[4];
  signal_offsets(sequence_, off);
  n_gun_ = static_cast<std::int64_t>(n_created) + gun_after_creation(s, course.race);
  n_warning_ = n_gun_ + off[0] * kTicksPerSecond;
  float limit = s.time_limit_s;
  if (!(limit > 0.0f)) limit = course.race.time_limit;
  if (!(limit > 0.0f) && course.race.target_duration > 0.0f) limit = 2.5f * course.race.target_duration;
  if (!(limit > 0.0f)) limit = 1800.0f;
  n_time_limit_ = n_gun_ + ticks_ceil(limit);

  start_.a = course.end_a(course.start());
  start_.b = course.end_b(course.start());
  start_.d = v_sub(start_.b, start_.a);
  start_.len = v_len(start_.d);
  // The finish line oriented with the side beyond the finish on the left, so the §4.1 crossing test applies.
  finish_.a = course.end_b(course.finish());
  finish_.b = course.end_a(course.finish());
  finish_.d = v_sub(finish_.b, finish_.a);
  finish_.len = v_len(finish_.d);
  first_ref_ = course.steps[1].ref;

  state_ = RaceState::free_sailing;
  twd_mean_ = twd_mean;
  update_legs();
  return true;
}

void Race::emit(RaceEvent e) { events_.push_back(e); }

void Race::signal(std::uint32_t n, SignalKind k) {
  RaceEvent e;
  e.kind = RaceEventKind::signal;
  e.tick = n;
  e.signal = k;
  e.flag = prep_flag_;
  emit(e);
}

void Race::make_ghost(std::uint32_t n, std::size_t i, GhostReason r) {
  RaceBoat& b = boats_[i];
  if (b.ghost) return;
  b.ghost = true;
  b.ghost_reason = r;
  RaceEvent e;
  e.kind = RaceEventKind::ghosted;
  e.tick = n;
  e.boat = static_cast<std::int32_t>(i);
  e.ghost = r;
  emit(e);
}

void Race::place_hulls(std::span<const RaceBoatInput> in) {
  for (std::size_t i = 0; i < boats_.size() && i < in.size(); ++i) {
    RaceBoat& b = boats_[i];
    std::swap(b.hull_prev, b.hull);
    b.c_prev = b.c;
    b.psi_prev = b.psi;
    b.c = in[i].pos;
    b.psi = in[i].psi;
    place_outline(b.perf->dynamics.collision.outline, b.c, b.psi, b.hull);
    if (!b.has_prev) {
      b.hull_prev = b.hull;
      b.c_prev = b.c;
      b.psi_prev = b.psi;
      b.has_prev = true;
    }
  }
}

bool Race::returning(std::size_t i) const {
  const RaceBoat& b = boats_[i];
  if (b.ghost || b.started || b.ocs_scored) return false;
  if (!(state_ == RaceState::racing || state_ == RaceState::closing)) return false;
  return !all_pre_start(b.hull);
}

// ---- Tick ----

void Race::signals(std::uint32_t n) {
  std::int64_t off[4];
  signal_offsets(sequence_, off);
  const std::int64_t nn = static_cast<std::int64_t>(n);
  while (signals_done_ < 4 && nn >= n_gun_ + off[signals_done_] * kTicksPerSecond) {
    const std::int32_t k = signals_done_++;
    switch (k) {
      case 0:
        state_ = RaceState::sequence;
        signal(n, SignalKind::warning);
        break;
      case 1:
        rules_live_ = true;
        signal(n, SignalKind::prep_up);
        if (race_type_ == RaceType::match) {
          // race.md §3.4.1: outside the line band beyond the assigned end (boat 0 end B, boat 1 end A).
          for (std::size_t i = 0; i < boats_.size() && i < 2; ++i) {
            bool outside = true;
            for (const Vec2 p : boats_[i].hull) {
              const float u = start_.u(p);
              if (i == 0 ? !(u > 1.0f) : !(u < 0.0f)) outside = false;
            }
            if (!outside) penalty_requests_.push_back({static_cast<std::int32_t>(i), RacePenaltyRule::c_prep});
          }
        }
        break;
      case 2:
        signal(n, SignalKind::prep_down);
        break;
      default:
        state_ = RaceState::racing;
        signal(n, SignalKind::start);
        at_gun(n);
        break;
    }
  }
}

void Race::at_gun(std::uint32_t n) {
  std::int32_t over = 0, racing_boats = 0;
  for (std::size_t i = 0; i < boats_.size(); ++i) {
    RaceBoat& b = boats_[i];
    if (b.ghost) continue;
    ++racing_boats;
    if (prep_flag_ == PrepFlag::P) {
      for (const Vec2 p : b.hull) {
        const float u = start_.u(p);
        if (start_.s(p) > 0.0f && u >= 0.0f && u <= 1.0f) {
          b.ocs = true;
          break;
        }
      }
      if (b.ocs) {
        RaceEvent e;
        e.kind = RaceEventKind::boat_ocs;
        e.tick = n;
        e.boat = static_cast<std::int32_t>(i);
        e.flag = PrepFlag::P;
        emit(e);
      }
    }
    if (b.ocs || b.ocs_i) ++over;
  }
  if (settings_.general_recall && recalls_ < 2 &&
      static_cast<float>(over) >= max(3.0f, 0.3f * static_cast<float>(racing_boats))) {
    general_recall(n);
    return;
  }
  for (std::size_t i = 0; i < boats_.size(); ++i) {
    RaceBoat& b = boats_[i];
    if (b.ghost) continue;
    if (b.black_flag) {
      b.code = ScoreCode::BFD;
      make_ghost(n, i, GhostReason::bfd);
    } else if (b.u_flag) {
      b.code = ScoreCode::UFD;
      make_ghost(n, i, GhostReason::ufd);
    }
  }
  bool any = false;
  for (const RaceBoat& b : boats_) any = any || (!b.ghost && (b.ocs || b.ocs_i));
  if (any) {
    x_flag_ = true;
    signal(n, SignalKind::x_up);
  }
}

void Race::general_recall(std::uint32_t n) {
  signal(n, SignalKind::general_recall);
  ++recalls_;
  switch (prep_flag_) {
    case PrepFlag::P: prep_flag_ = PrepFlag::I; break;
    case PrepFlag::I: prep_flag_ = PrepFlag::U; break;
    case PrepFlag::Z: prep_flag_ = PrepFlag::U; break;
    case PrepFlag::U: prep_flag_ = PrepFlag::black; break;
    case PrepFlag::black: break;
  }
  if (recalls_ >= 2) prep_flag_ = PrepFlag::black;
  for (std::size_t i = 0; i < boats_.size(); ++i) {
    RaceBoat& b = boats_[i];
    if (b.ghost) continue;
    if (b.black_flag) {
      b.code = ScoreCode::BFD;
      make_ghost(n, i, GhostReason::bfd);
      continue;
    }
    b.ocs = b.ocs_i = b.i_around_end = false;
    b.z_flag = b.u_flag = false;
    b.pre_seen = false;
  }
  std::int64_t off[4];
  signal_offsets(sequence_, off);
  n_gun_ = static_cast<std::int64_t>(n) + (60 - off[0]) * kTicksPerSecond;
  n_warning_ = n_gun_ + off[0] * kTicksPerSecond;
  const std::int64_t limit = n_time_limit_ - static_cast<std::int64_t>(n);
  n_time_limit_ = n_gun_ + limit;
  signals_done_ = 0;
  rules_live_ = false;
  state_ = RaceState::sequence;
}

void Race::pre_start(std::uint32_t n, std::size_t i, float /*t*/) {
  RaceBoat& b = boats_[i];
  const std::int64_t nn = static_cast<std::int64_t>(n);
  const bool last_minute = nn >= n_gun_ - 60 * kTicksPerSecond && nn < n_gun_;
  if (last_minute) {
    if (prep_flag_ == PrepFlag::I && !b.ocs_i) {
      for (const Vec2 p : b.hull) {
        if (start_.s(p) > 0.0f) {
          b.ocs_i = true;
          b.i_around_end = false;
          RaceEvent e;
          e.kind = RaceEventKind::boat_ocs;
          e.tick = n;
          e.boat = static_cast<std::int32_t>(i);
          e.flag = PrepFlag::I;
          emit(e);
          break;
        }
      }
    }
    const bool tri_flag = prep_flag_ == PrepFlag::Z || prep_flag_ == PrepFlag::U || prep_flag_ == PrepFlag::black;
    const bool already = b.z_flag || b.u_flag || b.black_flag;
    if (tri_flag && !already) {
      for (const Vec2 p : b.hull) {
        if (point_in_start_triangle(p)) {
          if (prep_flag_ == PrepFlag::Z) b.z_flag = true;
          else if (prep_flag_ == PrepFlag::U) b.u_flag = true;
          else b.black_flag = true;
          RaceEvent e;
          e.kind = RaceEventKind::boat_ocs;
          e.tick = n;
          e.boat = static_cast<std::int32_t>(i);
          e.flag = prep_flag_;
          emit(e);
          break;
        }
      }
    }
  }
  // race.md §3.4.2 match entry: a hull point crosses from the course side to the pre-start side through the band,
  // then the hull is completely on the pre-start side.
  if (race_type_ == RaceType::match && signals_done_ >= 2 && !b.entered) {
    Line rev;
    rev.a = start_.b;
    rev.b = start_.a;
    rev.d = v_sub(rev.b, rev.a);
    rev.len = start_.len;
    if (hull_cross(b.hull_prev, b.hull, rev).crossed) b.entry_crossed = true;
    if (b.entry_crossed && all_pre_start(b.hull)) b.entered = true;
  }
  if (race_type_ == RaceType::match && i < 2 && nn == n_gun_ - 120 * kTicksPerSecond && !b.entered) {
    penalty_requests_.push_back({static_cast<std::int32_t>(i), RacePenaltyRule::c_entry});
  }
}

void Race::begin_step(std::size_t i, std::int32_t k) {
  RaceBoat& b = boats_[i];
  b.next = k;
  b.n_cross = 0;
  b.phi[0] = b.phi[1] = 0.0f;
  const CourseStep& s = course_.steps[static_cast<std::size_t>(k)];
  if (s.kind != StepKind::mark && s.kind != StepKind::gate) {
    b.finish_armed = true;
    return;
  }
  const std::size_t last = course_.steps.size() - 1;
  const Vec2 P = course_.steps[static_cast<std::size_t>(k - 1)].ref;
  const Vec2 N = course_.steps[static_cast<std::size_t>(k + 1)].ref;
  const Vec2 N2 = course_.steps[std::min(static_cast<std::size_t>(k + 2), last)].ref;
  const std::int32_t nb = s.kind == StepKind::gate ? 2 : 1;
  for (std::int32_t m = 0; m < nb; ++m) {
    const Vec2 M = course_.marks[static_cast<std::size_t>(s.marks[m])].pos;
    const Winding w = winding_init(M, s.sides[m], P, N, N2, b.c);
    b.phi[m] = w.phi0;
    b.phi_done[m] = w.done;
  }
}

void Race::complete_step(std::uint32_t n, std::size_t i, std::int32_t buoy) {
  RaceBoat& b = boats_[i];
  const std::int32_t k = b.next;
  if (b.splits.size() < course_.steps.size()) b.splits.assign(course_.steps.size(), -1.0f);
  b.splits[static_cast<std::size_t>(k)] = race_time(n);
  b.rounded_this_tick = true;
  b.last_rounded = k;
  RaceEvent e;
  e.kind = RaceEventKind::rounded;
  e.tick = n;
  e.boat = static_cast<std::int32_t>(i);
  e.step = k;
  e.buoy = buoy;
  e.t = race_time(n);
  emit(e);
  begin_step(i, k + 1);
}

void Race::starting(std::uint32_t n, std::size_t i, std::span<const std::uint8_t> /*pending*/) {
  RaceBoat& b = boats_[i];
  const bool all_pre = all_pre_start(b.hull);
  // race.md §4.3 OCS-I: the reference point's crossings from the course side back to the pre-start side.
  if (b.ocs_i) {
    const float s0 = start_.s(b.c_prev), s1 = start_.s(b.c);
    if (s0 > 0.0f && s1 <= 0.0f) {
      const float f = s0 / (s0 - s1);
      const Vec2 q{b.c_prev.x + f * (b.c.x - b.c_prev.x), b.c_prev.y + f * (b.c.y - b.c_prev.y)};
      const float u = start_.u(q);
      b.i_around_end = !(u >= 0.0f && u <= 1.0f);
    }
  }
  const std::int64_t nn = static_cast<std::int64_t>(n);
  if (nn > n_gun_ && b.pre_seen && !b.ocs && !b.ocs_i) {
    const Crossing c = hull_cross(b.hull_prev, b.hull, start_);
    if (c.crossed) {
      b.started = true;
      b.t_start = static_cast<float>(nn - 1 - n_gun_) * DT + c.f * DT;
      if (b.splits.size() < course_.steps.size()) b.splits.assign(course_.steps.size(), -1.0f);
      b.splits[0] = b.t_start;
      RaceEvent e;
      e.kind = RaceEventKind::started;
      e.tick = n;
      e.boat = static_cast<std::int32_t>(i);
      e.t = b.t_start;
      emit(e);
      begin_step(i, 1);
      return;
    }
  }
  if (all_pre) {
    b.pre_seen = true;
    auto returned = [&](PrepFlag f) {
      RaceEvent e;
      e.kind = RaceEventKind::boat_returned;
      e.tick = n;
      e.boat = static_cast<std::int32_t>(i);
      e.flag = f;
      emit(e);
    };
    if (b.ocs && nn > n_gun_) {
      b.ocs = false;
      returned(PrepFlag::P);
    }
    if (b.ocs_i && b.i_around_end) {
      b.ocs_i = false;
      returned(PrepFlag::I);
    }
  }
}

void Race::sail_course(std::uint32_t n, std::size_t i, std::span<const std::uint8_t> pending) {
  RaceBoat& b = boats_[i];
  const std::int32_t k = b.next;
  const CourseStep& s = course_.steps[static_cast<std::size_t>(k)];
  if (s.kind == StepKind::mark || s.kind == StepKind::gate) {
    const std::int32_t nb = s.kind == StepKind::gate ? 2 : 1;
    for (std::int32_t m = 0; m < nb; ++m) {
      const Vec2 M = course_.marks[static_cast<std::size_t>(s.marks[m])].pos;
      const float sigma = s.sides[m] == Side::port ? 1.0f : -1.0f;
      b.phi[m] = b.phi[m] + sigma * signed_angle(v_sub(b.c_prev, M), v_sub(b.c, M));
    }
    if (s.kind == StepKind::mark) {
      if (b.phi[0] >= b.phi_done[0]) complete_step(n, i, s.marks[0]);
      return;
    }
    // race.md §5.2 gate crossings of the reference point, entry side = the side of P.
    const Vec2 G0 = course_.marks[static_cast<std::size_t>(s.marks[0])].pos;
    const Vec2 G1 = course_.marks[static_cast<std::size_t>(s.marks[1])].pos;
    const Vec2 P = course_.steps[static_cast<std::size_t>(k - 1)].ref;
    Line g;
    const bool p_left = side_left(P, G0, G1) > 0.0f;
    g.a = p_left ? G1 : G0;  // exit side on the left of a→b
    g.b = p_left ? G0 : G1;
    g.d = v_sub(g.b, g.a);
    g.len = v_len(g.d);
    const float s0 = g.s(b.c_prev), s1 = g.s(b.c);
    auto in_band = [&](float f) {
      const Vec2 q{b.c_prev.x + f * (b.c.x - b.c_prev.x), b.c_prev.y + f * (b.c.y - b.c_prev.y)};
      const float u = g.u(q);
      return u >= 0.0f && u <= 1.0f;
    };
    if (s0 <= 0.0f && 0.0f < s1 && in_band(s0 / (s0 - s1))) ++b.n_cross;
    else if (s0 > 0.0f && s1 <= 0.0f && in_band(s0 / (s0 - s1))) --b.n_cross;
    if (b.n_cross >= 1) {
      if (s.gate_mode == GateMode::cross) {
        complete_step(n, i, -1);
      } else if (b.phi[0] >= b.phi_done[0]) {
        complete_step(n, i, s.marks[0]);
      } else if (b.phi[1] >= b.phi_done[1]) {
        complete_step(n, i, s.marks[1]);
      }
    }
    return;
  }
  // race.md §6.1 finish.
  bool all_course = true;
  for (const Vec2 p : b.hull) {
    if (finish_.s(p) > 0.0f) all_course = false;
  }
  const Crossing c = hull_cross(b.hull_prev, b.hull, finish_);
  if (c.crossed && b.finish_armed) {
    const bool blocked = i < pending.size() && pending[i] != 0;
    if (blocked) {
      b.finish_armed = false;
      RaceEvent e;
      e.kind = RaceEventKind::finish_blocked;
      e.tick = n;
      e.boat = static_cast<std::int32_t>(i);
      e.block = FinishBlock::penalty;
      emit(e);
    } else {
      const std::int64_t nn = static_cast<std::int64_t>(n);
      b.finished = true;
      b.finish_tick = n;
      b.t_finish_us = (nn - 1 - n_gun_) * 50000 + static_cast<std::int64_t>(std::nearbyint(c.f * 50000.0f));
      if (b.splits.size() < course_.steps.size()) b.splits.assign(course_.steps.size(), -1.0f);
      b.splits[static_cast<std::size_t>(k)] = static_cast<float>(nn - 1 - n_gun_) * DT + c.f * DT;
      finished_this_tick_.push_back(static_cast<std::int32_t>(i));
    }
  } else if (!b.finish_armed && all_course) {
    b.finish_armed = true;
  }
}

void Race::after_finish(std::uint32_t n, std::size_t i) {
  RaceBoat& b = boats_[i];
  if (b.cleared) return;
  bool beyond = true;
  for (const Vec2 p : b.hull) {
    if (!(finish_.s(p) > 2.0f * b.L)) beyond = false;
  }
  const std::int64_t t_now_us = (static_cast<std::int64_t>(n) - n_gun_) * 50000;
  if (beyond || t_now_us - b.t_finish_us >= 10000000) {
    b.cleared = true;
    make_ghost(n, i, GhostReason::finished);
  }
}

void Race::progress(std::uint32_t n, std::span<const RaceBoatInput> in, std::span<const std::uint8_t> pending,
                    float twd_mean) {
  penalty_requests_.clear();
  finished_this_tick_.clear();
  if (state_ == RaceState::created || state_ == RaceState::closed || state_ == RaceState::abandoned) return;
  for (RaceBoat& b : boats_) b.rounded_this_tick = false;
  if (n % 200u == 0u && twd_mean != twd_mean_) {
    twd_mean_ = twd_mean;
    update_legs();
  }
  place_hulls(in);
  signals(n);
  if (state_ == RaceState::closed) return;

  const std::int64_t nn = static_cast<std::int64_t>(n);
  const float t = race_time(n);
  for (std::size_t i = 0; i < boats_.size(); ++i) {
    RaceBoat& b = boats_[i];
    if (b.ghost) continue;
    if (!b.came_near && nn >= n_warning_ && signals_done_ >= 1 &&
        point_segment_dist(b.c, start_.a, start_.b) <= 10.0f * b.L) {
      b.came_near = true;
    }
    if (nn < n_gun_ || signals_done_ < 4) {
      pre_start(n, i, t);
      if (b.ocs_i) {
        // Track returns around an end before the gun too (race.md §4.3).
        const float s0 = start_.s(b.c_prev), s1 = start_.s(b.c);
        if (s0 > 0.0f && s1 <= 0.0f) {
          const float f = s0 / (s0 - s1);
          const Vec2 q{b.c_prev.x + f * (b.c.x - b.c_prev.x), b.c_prev.y + f * (b.c.y - b.c_prev.y)};
          const float u = start_.u(q);
          b.i_around_end = !(u >= 0.0f && u <= 1.0f);
        }
      }
    } else if (!b.started && !b.ocs_scored) {
      starting(n, i, pending);
    } else if (!b.finished) {
      sail_course(n, i, pending);
    } else {
      after_finish(n, i);
    }
  }

  // Places for this tick's finishers, in crossing order (race.md §6.1).
  std::sort(finished_this_tick_.begin(), finished_this_tick_.end(), [&](std::int32_t a, std::int32_t c) {
    const RaceBoat& A = boats_[static_cast<std::size_t>(a)];
    const RaceBoat& C = boats_[static_cast<std::size_t>(c)];
    if (A.t_finish_us != C.t_finish_us) return A.t_finish_us < C.t_finish_us;
    return a < c;
  });
  for (const std::int32_t i : finished_this_tick_) {
    RaceBoat& b = boats_[static_cast<std::size_t>(i)];
    if (!b.ocs_scored) {
      std::int32_t place = 1;
      for (std::size_t j = 0; j < boats_.size(); ++j) {
        const RaceBoat& o = boats_[j];
        if (static_cast<std::int32_t>(j) == i || !o.finished || o.ocs_scored || o.place == 0) continue;
        if (o.t_finish_us < b.t_finish_us) ++place;
      }
      b.place = place;
      if (b.z_flag) b.code = ScoreCode::ZFP;
    } else {
      b.code = ScoreCode::OCS;
    }
    RaceEvent e;
    e.kind = RaceEventKind::finished;
    e.tick = n;
    e.boat = i;
    e.t_us = b.t_finish_us;
    e.place = b.place;
    emit(e);
    if (!any_finished_) {
      any_finished_ = true;
      if (settings_.finish_window && state_ == RaceState::racing) {
        const float t_win = clamp(0.5f * (static_cast<float>(b.t_finish_us) * 1e-6f), 120.0f, 600.0f);
        n_window_end_ = nn + ticks_ceil(t_win);
        state_ = RaceState::closing;
        RaceEvent c;
        c.kind = RaceEventKind::race_closing;
        c.tick = n;
        c.value = t_win;
        emit(c);
      }
    }
  }

  // race.md §4.4 start limit and the X flag.
  if (signals_done_ >= 4) {
    if (nn == n_gun_ + ticks_ceil(settings_.start_limit_s)) {
      for (std::size_t i = 0; i < boats_.size(); ++i) {
        RaceBoat& b = boats_[i];
        if (b.ghost || b.started || b.ocs_scored) continue;
        if (b.ocs || b.ocs_i) {
          b.ocs_scored = true;
          begin_step(i, 1);
        } else {
          b.code = b.came_near ? ScoreCode::DNS : ScoreCode::DNC;
          make_ghost(n, i, GhostReason::dns);
        }
      }
    }
    if (x_flag_) {
      bool pending_ocs = false;
      for (const RaceBoat& b : boats_) pending_ocs = pending_ocs || (!b.ghost && !b.ocs_scored && (b.ocs || b.ocs_i));
      if (!pending_ocs || nn >= n_gun_ + ticks_ceil(settings_.start_limit_s)) {
        x_flag_ = false;
        signal(n, SignalKind::x_down);
      }
    }
  }
}

// ---- Ranking (race.md §8) and closing (§7) ----

void Race::update_legs() {
  legs_twd_ = twd_mean_;
  legs_.assign(course_.steps.size(), LegAxis{});
  const Vec2 w = dir(twd_mean_);
  for (std::size_t j = 1; j < course_.steps.size(); ++j) {
    const Vec2 d = v_sub(course_.steps[j].ref, course_.steps[j - 1].ref);
    const float len = v_len(d);
    const float along = v_dot(d, w);
    LegAxis& a = legs_[j];
    if (std::fabs(along) >= 0.707106781f * len) {
      a.wind_axis = true;
      a.e = along >= 0.0f ? w : Vec2{-w.x, -w.y};
    } else {
      a.wind_axis = false;
      a.e = v_unit(d, w);
    }
    a.length = max(0.0f, v_dot(d, a.e));
  }
}

float Race::remaining(std::size_t i) const {
  const RaceBoat& b = boats_[i];
  if (b.finished) return 0.0f;
  const std::size_t last = course_.steps.size() - 1;
  const std::size_t k = static_cast<std::size_t>(b.next);
  const Vec2 bw = bow(i);
  float D;
  if (k == last && !legs_[k].wind_axis) {
    D = point_segment_dist(bw, finish_.a, finish_.b);
  } else {
    D = max(0.0f, v_dot(v_sub(course_.steps[k].ref, bw), legs_[k].e));
  }
  for (std::size_t j = k + 1; j <= last; ++j) D = D + legs_[j].length;
  return D;
}

// Seconds to sail the remaining course at 0.9 of the polar (race.md §7.2).
float Race::v_ref_time(std::size_t i, float tws) const {
  const RaceBoat& b = boats_[i];
  const PolarVmg vmg = polar_vmg(*b.perf, tws);
  const std::size_t last = course_.steps.size() - 1;
  const std::size_t k = static_cast<std::size_t>(b.next);
  const Vec2 w = dir(twd_mean_);
  float t = 0.0f;
  for (std::size_t j = k; j <= last; ++j) {
    const LegAxis& a = legs_[j];
    float d = a.length;
    if (j == k) d = max(0.0f, v_dot(v_sub(course_.steps[k].ref, bow(i)), a.e));
    float V;
    if (a.wind_axis) {
      V = v_dot(a.e, w) > 0.0f ? vmg.up_speed : vmg.down_speed;
    } else {
      V = polar_best(*b.perf, tws, std::fabs(wrap_pi(twd_mean_ - compass(a.e))));
    }
    V = 0.9f * V;
    if (V > 0.01f) t = t + d / V;
  }
  return t;
}

bool Race::any_human_racing() const {
  for (const RaceBoat& b : boats_) {
    if (b.human && !b.ghost && !b.finished) return true;
  }
  return false;
}

bool Race::any_racing() const {
  for (const RaceBoat& b : boats_) {
    if (!b.ghost && !b.finished) return true;
  }
  return false;
}

void Race::rank(std::uint32_t n, std::span<const RaceBoatInput> in) {
  if (state_ == RaceState::created || state_ == RaceState::closed || state_ == RaceState::abandoned) return;
  const std::size_t nb = boats_.size();
  std::vector<float> key(nb, 0.0f);
  for (std::size_t i = 0; i < nb; ++i) {
    RaceBoat& b = boats_[i];
    if (b.finished) b.D = 0.0f;
    else if (!b.ghost && (b.started || b.ocs_scored)) b.D = remaining(i);
    else b.D = point_segment_dist(b.c, start_.a, start_.b);
  }
  auto group = [&](const RaceBoat& b) {
    if (b.finished) return 0;
    if (b.ghost) return 3;
    if (b.started || b.ocs_scored) return 1;
    return 2;
  };
  order_.resize(nb);
  for (std::size_t i = 0; i < nb; ++i) order_[i] = static_cast<std::int32_t>(i);
  std::sort(order_.begin(), order_.end(), [&](std::int32_t a, std::int32_t c) {
    const RaceBoat& A = boats_[static_cast<std::size_t>(a)];
    const RaceBoat& C = boats_[static_cast<std::size_t>(c)];
    const int ga = group(A), gc = group(C);
    if (ga != gc) return ga < gc;
    if (ga == 0 && A.t_finish_us != C.t_finish_us) return A.t_finish_us < C.t_finish_us;
    if (ga == 1 && A.next != C.next) return A.next > C.next;
    if ((ga == 1 || ga == 2) && A.D != C.D) return A.D < C.D;
    return a < c;
  });
  for (std::size_t r = 0; r < nb; ++r) {
    RaceBoat& b = boats_[static_cast<std::size_t>(order_[r])];
    b.rank = static_cast<std::int32_t>(r + 1);
    if (r > 0) {
      const RaceBoat& p = boats_[static_cast<std::size_t>(order_[r - 1])];
      if (b.finished && p.finished && b.t_finish_us == p.t_finish_us) b.rank = p.rank;
    }
  }

  // Closing (race.md §7).
  const std::int64_t nn = static_cast<std::int64_t>(n);
  bool has_human = false;
  for (const RaceBoat& b : boats_) has_human = has_human || b.human;
  if (state_ == RaceState::closing && n_window_end_ >= 0) {
    for (const std::int64_t warn : {std::int64_t{60}, std::int64_t{10}}) {
      if (nn == n_window_end_ - warn * kTicksPerSecond && any_human_racing()) {
        RaceEvent e;
        e.kind = RaceEventKind::window_warning;
        e.tick = n;
        e.value = static_cast<float>(warn);
        emit(e);
      }
    }
    if (nn >= n_window_end_) {
      close(n);
      return;
    }
  }
  if (!any_finished_ && signals_done_ >= 4 && nn >= n_time_limit_) {
    close(n);
    return;
  }
  if (has_human && !any_human_racing()) {
    // race.md §7.2 projected finishes for the computer boats still racing.
    const float t_now = race_time(n);
    for (std::size_t i = 0; i < nb; ++i) {
      RaceBoat& b = boats_[i];
      if (b.human || b.ghost || b.finished || !(b.started || b.ocs_scored) || b.ocs_scored) continue;
      const float tws = i < in.size() ? in[i].tws : 0.0f;
      b.projected = true;
      b.t_proj = max(t_now, t_now + v_ref_time(i, tws));
    }
    close(n);
    return;
  }
  if (!any_racing()) close(n);
}

void Race::close(std::uint32_t n) {
  for (std::size_t i = 0; i < boats_.size(); ++i) {
    RaceBoat& b = boats_[i];
    if (b.finished || b.projected) continue;
    if (b.code != ScoreCode::none) continue;  // already scored (RET, DSQ, UFD, ...)
    if (b.ocs_scored || (!b.started && (b.ocs || b.ocs_i))) b.code = ScoreCode::OCS;
    else if (b.started) b.code = ScoreCode::DNF;
    else b.code = b.came_near ? ScoreCode::DNS : ScoreCode::DNC;
  }
  state_ = RaceState::closed;

  // Results (race.md §9).
  results_.clear();
  const float entries = static_cast<float>(boats_.size());
  const float dnf_points = entries + 1.0f;
  std::vector<std::int32_t> fin, proj, rest;
  for (std::size_t i = 0; i < boats_.size(); ++i) {
    const RaceBoat& b = boats_[i];
    const std::int32_t ii = static_cast<std::int32_t>(i);
    if (b.finished && (b.code == ScoreCode::none || b.code == ScoreCode::ZFP)) fin.push_back(ii);
    else if (b.projected) proj.push_back(ii);
    else rest.push_back(ii);
  }
  std::sort(fin.begin(), fin.end(), [&](std::int32_t a, std::int32_t c) {
    const RaceBoat& A = boats_[static_cast<std::size_t>(a)];
    const RaceBoat& C = boats_[static_cast<std::size_t>(c)];
    return A.t_finish_us != C.t_finish_us ? A.t_finish_us < C.t_finish_us : a < c;
  });
  std::sort(proj.begin(), proj.end(), [&](std::int32_t a, std::int32_t c) {
    const RaceBoat& A = boats_[static_cast<std::size_t>(a)];
    const RaceBoat& C = boats_[static_cast<std::size_t>(c)];
    return A.t_proj != C.t_proj ? A.t_proj < C.t_proj : a < c;
  });
  auto code_rank = [](ScoreCode c) { return static_cast<int>(c); };
  std::sort(rest.begin(), rest.end(), [&](std::int32_t a, std::int32_t c) {
    const RaceBoat& A = boats_[static_cast<std::size_t>(a)];
    const RaceBoat& C = boats_[static_cast<std::size_t>(c)];
    const int ra = code_rank(A.code), rc = code_rank(C.code);
    return ra != rc ? ra < rc : a < c;
  });
  const float zfp_add = max(1.0f, round_half_even(0.2f * entries));
  std::size_t i = 0;
  while (i < fin.size()) {
    std::size_t j = i;
    while (j + 1 < fin.size() && boats_[static_cast<std::size_t>(fin[j + 1])].t_finish_us ==
                                     boats_[static_cast<std::size_t>(fin[i])].t_finish_us) {
      ++j;
    }
    const float first = static_cast<float>(i + 1), lastp = static_cast<float>(j + 1);
    const float pts = (first + lastp) * 0.5f;
    for (std::size_t k = i; k <= j; ++k) {
      RaceBoat& b = boats_[static_cast<std::size_t>(fin[k])];
      b.place = static_cast<std::int32_t>(i + 1);
      ResultRow r;
      r.boat = fin[k];
      r.place = b.place;
      r.code = b.code;
      r.points = b.code == ScoreCode::ZFP ? min(pts + zfp_add, dnf_points) : pts;
      r.t_finish_us = b.t_finish_us;
      results_.push_back(r);
    }
    i = j + 1;
  }
  std::int32_t place = static_cast<std::int32_t>(fin.size());
  for (const std::int32_t p : proj) {
    RaceBoat& b = boats_[static_cast<std::size_t>(p)];
    b.place = ++place;
    ResultRow r;
    r.boat = p;
    r.place = b.place;
    r.points = static_cast<float>(b.place);
    r.projected = true;
    r.t_finish_us = static_cast<std::int64_t>(std::nearbyint(b.t_proj * 1e6f));
    results_.push_back(r);
  }
  for (const std::int32_t p : rest) {
    const RaceBoat& b = boats_[static_cast<std::size_t>(p)];
    ResultRow r;
    r.boat = p;
    r.code = b.code;
    r.points = dnf_points;
    r.t_finish_us = b.finished ? b.t_finish_us : 0;
    results_.push_back(r);
  }
  RaceEvent e;
  e.kind = RaceEventKind::race_closed;
  e.tick = n;
  emit(e);
}

// ---- Actions ----

void Race::retire(std::int32_t boat, std::uint32_t n) {
  RaceBoat& b = boats_[static_cast<std::size_t>(boat)];
  if (b.ghost || b.finished) return;
  b.retired = true;
  b.code = b.started ? ScoreCode::RET : ScoreCode::DNS;
  RaceEvent e;
  e.kind = RaceEventKind::retired;
  e.tick = n;
  e.boat = boat;
  emit(e);
  make_ghost(n, static_cast<std::size_t>(boat), GhostReason::retired);
}

void Race::disqualify(std::int32_t boat, std::uint32_t n) {
  RaceBoat& b = boats_[static_cast<std::size_t>(boat)];
  if (b.ghost && b.dsq) return;
  b.dsq = true;
  b.code = ScoreCode::DSQ;
  b.finished = false;
  make_ghost(n, static_cast<std::size_t>(boat), GhostReason::dsq);
}

void Race::leave(std::int32_t boat, std::uint32_t n) {
  RaceBoat& b = boats_[static_cast<std::size_t>(boat)];
  RaceEvent e;
  e.kind = RaceEventKind::left;
  e.tick = n;
  e.boat = boat;
  emit(e);
  if (b.ghost || b.finished) return;
  b.code = b.started ? ScoreCode::DNF : ScoreCode::DNS;
  make_ghost(n, static_cast<std::size_t>(boat), GhostReason::left);
}

void Race::abandon(std::uint32_t n) {
  state_ = RaceState::abandoned;
  results_.clear();
  RaceEvent e;
  e.kind = RaceEventKind::abandoned;
  e.tick = n;
  emit(e);
}

}  // namespace wm
