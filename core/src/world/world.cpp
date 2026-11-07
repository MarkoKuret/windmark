#include "world/world.h"

#include <algorithm>
#include <cmath>

#include "course/geometry.h"
#include "state/checksum.h"

namespace wm {

World::World(const WorldSetup& setup) : setup_(setup) {
  setup_.race.race_seed = setup.race_seed;
  wind_settings_ = setup.wind;
  sea_settings_ = setup.sea_settings;
  if (setup.venue != nullptr) apply_venue(*setup.venue, wind_settings_, sea_settings_);
  if (setup.sea && !(sea_settings_.wind_sea.hs > 0.0f)) {
    const double fetch = setup.venue != nullptr ? static_cast<double>(setup.venue->fetch) : 10000.0;
    sea_settings_.wind_sea =
        wind_sea_from_wind(static_cast<double>(wind_settings_.base_speed), fetch, wind_settings_.base_from);
  }
  wind_ = std::make_unique<WindField>(setup.race_seed, wind_settings_);
  if (setup.sea) sea_ = std::make_unique<SeaField>(setup.race_seed, sea_settings_);
  if (setup.venue != nullptr) scene_.set_venue(*setup.venue);
}

BoatEnv World::env_at(Vec2 p) const {
  const WindTick& wt = wind_->current_tick();
  const WindSample w = wind_->wind_clean(wt, p.x, p.y);
  const Vec2 c = wind_->current(p.x, p.y, t_ms());
  BoatEnv e;
  e.wind_speed = w.speed;
  e.wind_from = w.from;
  e.wind_speed_clean = w.speed;
  e.current_x = c.x;
  e.current_y = c.y;
  e.sea = sea_ ? &sea_tick_ : nullptr;
  return e;
}

// race.md §3.5 placement: port tack at twa = −60° (a close reach towards the line and its starboard end B), 60 % of
// the polar speed.
void World::spawn(std::size_t i, Vec2 p, float psi_hint, bool use_hint) {
  (void)wind_->advance(t_ms());
  if (sea_) sea_tick_ = sea_->at(t_ms());
  const BoatEnv e = env_at(p);
  const BoatEntry& en = entries_[i];
  const float twa = -60.0f * DEG;  // port: psi = TWD + 60°
  const float psi = use_hint ? psi_hint : wrap_2pi(e.wind_from - twa);
  const std::int32_t front = en.front_sail == -2 ? en.perf->start_front_sail : en.front_sail;
  Boat& b = boats_[i];
  const float v = 0.6f * b.polar_at(e.wind_speed, wrap_pi(e.wind_from - psi), front);
  b.reset(p.x, p.y, psi, v, front, en.auto_trim, e);
  b.set_performance_scale(en.performance_scale);
}

void World::place_boat(std::int32_t boat, float x, float y, float psi, float v, std::int32_t front_sail) {
  if (boat < 0 || static_cast<std::size_t>(boat) >= boats_.size()) return;
  (void)wind_->advance(t_ms());
  if (sea_) sea_tick_ = sea_->at(t_ms());
  const BoatEnv e = env_at({x, y});
  Boat& b = boats_[static_cast<std::size_t>(boat)];
  const Sails& sl = b.sails();
  b.reset(x, y, wrap_2pi(psi), v, front_sail == -2 ? sl.front() : front_sail, b.controls().auto_trim, e);
  b.set_performance_scale(entries_[static_cast<std::size_t>(boat)].performance_scale);
}

std::int32_t World::add_boat(const BoatEntry& e) {
  if (e.perf == nullptr) return -1;
  if (created_) {
    const std::int32_t r = race_.add_boat(e.perf, e.human, e.performance_scale);
    if (r < 0) return -1;
  }
  const std::uint32_t index = static_cast<std::uint32_t>(boats_.size());
  boats_.emplace_back();
  boats_.back().init(e.perf, setup_.race_seed, index);
  boats_.back().set_weather_helm(setup_.weather_helm);
  entries_.push_back(e);
  shadow_classes_.push_back(make_shadow_class(e.perf->dynamics.wind_shadow));
  env_.emplace_back();
  collide_in_.emplace_back();
  if (created_) {
    rules_.sync_boats(race_);
    // The first free slot whose disc of 3 L_max holds no other boat.
    const float L = race_.L_max();
    for (const Vec2 s : slots_) {
      bool free = true;
      for (std::size_t j = 0; j + 1 < boats_.size(); ++j) {
        const BoatState& o = boats_[j].state();
        if (v_dist(s, {o.pos_x, o.pos_y}) < 3.0f * L) free = false;
      }
      if (free) {
        spawn(boats_.size() - 1, s, 0.0f, false);
        break;
      }
    }
  }
  return static_cast<std::int32_t>(index);
}

bool World::create_race(const CourseData& course, std::string& error) {
  if (created_) {
    error = "the race exists already";
    return false;
  }
  if (boats_.empty()) {
    error = "no boats";
    return false;
  }
  if (setup_.venue == nullptr) {
    error = "no venue";
    return false;
  }
  const VenueData& venue = *setup_.venue;
  // courses.md §6.1: the course axis from the median wind at the gun.
  const std::int64_t gun = static_cast<std::int64_t>(tick_) + Race::gun_after_creation(setup_.race, course.race);
  const std::uint32_t t_gun = static_cast<std::uint32_t>(gun) * DT_MS;
  float L_max = 0.0f;
  if (!resolve_and_build(course, course_axis(wind_settings_.base_from + wind_->trend(t_gun)), L_max, error)) {
    return false;
  }
  laid_ = false;

  for (const BoatEntry& e : entries_) race_.add_boat(e.perf, e.human, e.performance_scale);
  const WindTick& wt = wind_->advance(t_ms());
  if (!race_.create(course_, setup_.race, tick_, wt.global_from, error)) return false;
  rules_.init(race_, &venue, setup_.rules);
  collisions_.reset();
  contacts_.clear();

  const std::size_t n = boats_.size();
  if (race_.race_type() == RaceType::match) {
    // race.md §3.5: boat 0 beyond end B, boat 1 beyond end A, on the pre-start side, sailing outwards.
    const Vec2 A = course_.end_a(course_.start()), B = course_.end_b(course_.start());
    const Vec2 u = v_unit(v_sub(B, A), {1.0f, 0.0f});
    const Vec2 pre{u.y, -u.x};
    for (std::size_t i = 0; i < 2; ++i) {
      const float L = entries_[i].perf->dynamics.loa;
      const Vec2 out = i == 0 ? u : Vec2{-u.x, -u.y};
      const Vec2 end = i == 0 ? B : A;
      const Vec2 p = v_add(v_add(end, v_scale(out, 6.0f * L)), v_scale(pre, 2.0f * L));
      (void)wind_->advance(t_ms());
      const float from = wind_->wind_clean(wind_->current_tick(), p.x, p.y).from;
      const float h1 = wrap_2pi(from - 100.0f * DEG), h2 = wrap_2pi(from + 100.0f * DEG);
      spawn(i, p, v_dot(dir(h1), out) >= v_dot(dir(h2), out) ? h1 : h2, true);
    }
  } else {
    slots_ = spawn_slots(course_, &venue, L_max, n);
    if (slots_.size() < n) {
      error = "course " + course.id + ": not enough spawn slots for " + std::to_string(n) + " boats";
      return false;
    }
    const std::vector<std::int32_t> order = spawn_order(setup_.race_seed, static_cast<std::int32_t>(n));
    for (std::size_t k = 0; k < n; ++k) spawn(static_cast<std::size_t>(order[k]), slots_[k], 0.0f, false);
  }
  created_ = true;
  entries_at_create_ = static_cast<std::uint32_t>(n);
  return true;
}

bool World::resolve_and_build(const CourseData& course, float twd_c, float& L_max, std::string& error) {
  const VenueData& venue = *setup_.venue;
  L_max = 0.0f;
  const PerfData* longest = entries_.front().perf;
  for (const BoatEntry& e : entries_) {
    if (e.perf->dynamics.loa > L_max) {
      L_max = e.perf->dynamics.loa;
      longest = e.perf;
    }
  }
  const float scale = course_scale(course, twd_c, *longest, wind_settings_.base_speed);
  resolve_course(course, twd_c, scale, course_);
  std::vector<std::string> warnings;
  std::string why;
  if (!check_resolved_course(course_, venue, {L_max, static_cast<std::int32_t>(boats_.size())}, warnings, why)) {
    error = "course " + course.id + ": " + why;
    return false;
  }

  // The collision scene: course entries in course order (courses.md §2), then the venue.
  scene_.clear();
  for (std::size_t m = 0; m < course_.marks.size(); ++m) {
    const ResolvedMark& rm = course_.marks[m];
    std::int32_t idx = -1;
    if (rm.type == MarkType::buoy) {
      idx = scene_.add_mark(rm.pos, rm.radius);
    } else if (rm.type == MarkType::virtual_point) {
      idx = scene_.add_virtual();
    } else {
      for (const CourseObject& o : course_.objects) {
        if (o.mark == static_cast<std::int32_t>(m)) idx = scene_.add_course_polygon(o.c, o.heading, o.outline);
      }
    }
    if (idx != static_cast<std::int32_t>(m)) {
      error = "course " + course.id + ": mark \"" + course_.mark_ids[m] + "\" is not a valid collision shape";
      return false;
    }
  }
  scene_.set_venue(venue);
  return true;
}

bool World::lay_course(const CourseData& course, std::string& error) {
  if (created_ || laid_) {
    error = created_ ? "the race exists already" : "the course is laid already";
    return false;
  }
  if (boats_.empty()) {
    error = "no boats";
    return false;
  }
  if (setup_.venue == nullptr) {
    error = "no venue";
    return false;
  }
  // courses.md §6.4: the axis on the median wind now (no gun), scaled and checked as for a race.
  float L_max = 0.0f;
  if (!resolve_and_build(course, course_axis(wind_settings_.base_from + wind_->trend(t_ms())), L_max, error)) {
    course_ = ResolvedCourse{};
    scene_.clear();
    scene_.set_venue(*setup_.venue);
    return false;
  }
  collisions_.reset();
  contacts_.clear();
  // race.md §3.5 slots, the nearest to the start line's middle first, in the race's spawn order.
  const std::size_t n = boats_.size();
  std::vector<Vec2> slots = spawn_slots(course_, setup_.venue, L_max, n + 64);
  if (slots.size() < n) {
    error = "course " + course.id + ": not enough spawn slots for " + std::to_string(n) + " boats";
    course_ = ResolvedCourse{};
    scene_.clear();
    scene_.set_venue(*setup_.venue);
    return false;
  }
  const Vec2 mid = v_mid(course_.end_a(course_.start()), course_.end_b(course_.start()));
  std::stable_sort(slots.begin(), slots.end(),
                   [&](Vec2 a, Vec2 b) { return v_dist(a, mid) < v_dist(b, mid); });
  const std::vector<std::int32_t> order = spawn_order(setup_.race_seed, static_cast<std::int32_t>(n));
  for (std::size_t k = 0; k < n; ++k) spawn(static_cast<std::size_t>(order[k]), slots[k], 0.0f, false);
  laid_ = true;
  return true;
}

bool World::place_boat(std::int32_t boat, Vec2 p, float psi) {
  if (created_ || boat < 0 || static_cast<std::size_t>(boat) >= boats_.size()) return false;
  spawn(static_cast<std::size_t>(boat), p, wrap_2pi(psi), true);
  return true;
}

void World::set_helm(std::int32_t b, float h) { queue({Command::Kind::helm, b, h, 0}); }
void World::set_sheet(std::int32_t b, float s) { queue({Command::Kind::sheet, b, s, 0}); }
void World::set_auto_trim(std::int32_t b, bool on) { queue({Command::Kind::auto_trim, b, on ? 1.0f : 0.0f, 0}); }
void World::set_let_fly(std::int32_t b, bool on) { queue({Command::Kind::let_fly, b, on ? 1.0f : 0.0f, 0}); }
void World::hoist(std::int32_t b, std::int32_t sail) { queue({Command::Kind::hoist, b, 0.0f, sail}); }
void World::drop_front(std::int32_t b) { queue({Command::Kind::drop, b, 0.0f, 0}); }
void World::retire(std::int32_t b) { queue({Command::Kind::retire, b, 0.0f, 0}); }
void World::protest(std::int32_t b) { queue({Command::Kind::protest, b, 0.0f, 0}); }

// conventions.md §9: FNV-1a 64 over the tick index, then the snapshot body hashed as it is written.
std::uint64_t World::checksum() const {
  Fnv1a64 h;
  h.update_u32(tick_);
  SnapshotWriter w(h);
  save_body(w);
  return h.value();
}

void World::step() {
  const std::uint32_t n = tick_;
  const std::uint32_t t = t_ms();
  const std::size_t nb = boats_.size();
  events_ = WorldEvents{};
  const WindTick& wt = wind_->advance(t);  // the environment at t_n (step 3 uses the same tick)
  if (sea_) sea_tick_ = sea_->at(t);

  // Step 1: race and rules on the state at t_n and the previous tick's contacts (race.md §1).
  if (created_) {
    race_in_.resize(nb);
    rules_in_.resize(nb);
    for (std::size_t i = 0; i < nb; ++i) {
      const Boat& b = boats_[i];
      const BoatState& s = b.state();
      const Vec2 p{s.pos_x, s.pos_y};
      const WindSample w = wind_->wind_clean(wt, p.x, p.y);
      const float beta = b.sails().sail(static_cast<std::size_t>(b.perf().main_sail)).beta;
      race_in_[i] = {p, s.psi, s.v, w.speed, w.from, beta};
      const Vec2 cur = wind_->current(p.x, p.y, t);
      RulesBoatInput& r = rules_in_[i];
      r.pos = p;
      r.psi = s.psi;
      r.v = s.v;
      r.turn_rate = b.outputs().turn_rate;
      r.current = v_add(cur, b.drift_velocity());  // the drift: current plus sideways drift (rules.md §3.1)
      r.cog = b.outputs().cog;
      r.sog = b.outputs().sog;
      r.tws = w.speed;
      r.twd = w.from;
      r.main_beta = beta;
      r.helm = s.h;
      r.let_fly_drive = b.let_fly_drive();
      r.sprit = 0.0f;  // the bowsprit is in normal position while the sail tacked to it is set (rules.md §3.2)
      if (const std::int32_t f = b.sails().front(); f >= 0) {
        const SailType t = b.perf().sails[static_cast<std::size_t>(f)].type;
        const SailPhase ph = b.sails().sail(static_cast<std::size_t>(f)).phase;
        if ((t == SailType::spinnaker_asym || t == SailType::code_zero) &&
            (ph == SailPhase::up || ph == SailPhase::prepare_drop)) {
          r.sprit = b.perf().dynamics.collision.sprit;
        }
      }
      r.ai = entries_[i].ai;
    }
    rules_.pending_flags(pending_);
    race_.progress(n, race_in_, pending_, wt.global_from);
    rules_.update(n, race_, rules_in_, contacts_);
    for (const auto& [boat, why] : rules_.dsq()) {
      (void)why;
      race_.disqualify(boat, n);
    }
    race_.rank(n, race_in_);
    for (std::size_t i = 0; i < nb; ++i) collide_in_[i].collides = race_.collides(i);
  }

  // Step 2: controls.
  if (controller_) controller_(*this);
  for (const Command& c : commands_) {
    if (c.boat < 0 || static_cast<std::size_t>(c.boat) >= nb) continue;
    Boat& b = boats_[static_cast<std::size_t>(c.boat)];
    switch (c.kind) {
      case Command::Kind::helm: b.set_helm(c.value); break;
      case Command::Kind::sheet: b.set_sheet(c.value); break;
      case Command::Kind::auto_trim: b.set_auto_trim(c.value != 0.0f); break;
      case Command::Kind::let_fly: b.set_let_fly(c.value != 0.0f); break;
      case Command::Kind::hoist: (void)b.hoist(c.sail); break;
      case Command::Kind::drop: (void)b.drop_front(); break;
      case Command::Kind::retire:
        if (created_) race_.retire(c.boat, n);
        break;
      case Command::Kind::protest:
        if (created_) rules_.protest(c.boat, n);
        break;
    }
  }
  commands_.clear();

  // Step 4: the shadow snapshot at t_n.
  snapshot_.resize(nb);
  for (std::size_t i = 0; i < nb; ++i) {
    const Boat& b = boats_[i];
    const BoatState& s = b.state();
    ShadowSource& src = snapshot_[i];
    src.cls = &shadow_classes_[i];
    src.pos_x = s.pos_x;
    src.pos_y = s.pos_y;
    src.psi = s.psi;
    src.aws = s.aws;
    src.awd_from = s.awd_from;
    src.awa = s.awa;
    src.twa = s.twa;
    src.spinnaker = b.sails().spinnaker_flying();
    src.casts = setup_.shadows && (!created_ || race_.casts(i));
  }

  // Step 5: the wind at each boat, then the boat step.
  for (std::size_t i = 0; i < nb; ++i) {
    Boat& b = boats_[i];
    env_[i] = env_at_boat(*wind_, wt, snapshot_, static_cast<std::int32_t>(i), b.state().pos_x, b.state().pos_y);
    BoatEnv be;
    be.wind_speed = env_[i].wind_speed;
    be.wind_from = env_[i].wind_from;
    be.wind_speed_clean = env_[i].wind_speed_clean;
    be.current_x = env_[i].current_x;
    be.current_y = env_[i].current_y;
    be.sea = sea_ ? &sea_tick_ : nullptr;
    b.step(be);
    collide_in_[i].current = {env_[i].current_x, env_[i].current_y};
  }

  // Step 6: collisions on the new positions.
  contacts_.clear();
  collisions_.step(n, boats_, collide_in_, scene_, contacts_);

  // Step 7: publish.
  if (created_) {
    events_.race = race_.events();
    events_.rules = rules_.events();
    race_.clear_events();
    rules_.clear_events();
  }
  events_.contacts = contacts_;
  ++tick_;
}

}  // namespace wm
