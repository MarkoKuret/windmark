// The world snapshot (conventions.md §9.1): save, load, and the body the tick checksum covers.
#include <string_view>

#include "state/snapshot_util.h"
#include "world/world.h"

namespace wm {

using namespace snap;

namespace {

constexpr std::uint32_t kMagic = 0x57574D57u;
constexpr std::uint32_t kVersion = 3;

std::uint64_t text_id(std::string_view s) {
  return fnv1a64({reinterpret_cast<const std::uint8_t*>(s.data()), s.size()});
}

void put_outputs(SnapshotWriter& w, const BoatOutputs& o) {
  for (const float x : {o.target_speed, o.polar_speed, o.heel_target, o.turn_rate, o.vmg, o.sog, o.cog, o.man_coef,
                        o.trim_speed, o.trim_heel, o.heel_coef, o.surf_coef, o.wind_speed_clean}) {
    w.put_f32(x);
  }
}

BoatOutputs get_outputs(SnapshotReader& r) {
  BoatOutputs o;
  for (float* x : {&o.target_speed, &o.polar_speed, &o.heel_target, &o.turn_rate, &o.vmg, &o.sog, &o.cog,
                   &o.man_coef, &o.trim_speed, &o.trim_heel, &o.heel_coef, &o.surf_coef, &o.wind_speed_clean}) {
    *x = r.get_f32();
  }
  return o;
}

void put_env(SnapshotWriter& w, const EnvAtBoat& e) {
  for (const float x : {e.wind_speed, e.wind_from, e.wind_speed_clean, e.wind_from_clean, e.current_x, e.current_y,
                        e.shadow_loss, e.shadow_header}) {
    w.put_f32(x);
  }
  w.put_i32(e.shadow_source);
}

EnvAtBoat get_env(SnapshotReader& r) {
  EnvAtBoat e{};
  for (float* x : {&e.wind_speed, &e.wind_from, &e.wind_speed_clean, &e.wind_from_clean, &e.current_x, &e.current_y,
                   &e.shadow_loss, &e.shadow_header}) {
    *x = r.get_f32();
  }
  e.shadow_source = r.get_i32();
  return e;
}

void put_sail_outputs(SnapshotWriter& w, const Sails& sails) {
  for (std::size_t k = 0; k < sails.sail_count(); ++k) {
    const SailOutput& o = sails.output(k);
    for (const float x : {o.k_h, o.m_opt, o.beta_opt, o.beta_t, o.trim_error, o.luff_shiver}) w.put_f32(x);
    put_enum(w, o.motion);
    w.put_bool(o.backed);
  }
}

std::vector<SailOutput> get_sail_outputs(SnapshotReader& r, std::size_t n) {
  std::vector<SailOutput> v(n);
  for (SailOutput& o : v) {
    for (float* x : {&o.k_h, &o.m_opt, &o.beta_opt, &o.beta_t, &o.trim_error, &o.luff_shiver}) *x = r.get_f32();
    o.motion = get_enum(r, SailMotion::easing);
    o.backed = r.get_bool();
  }
  return v;
}

}  // namespace

void World::save_body(SnapshotWriter& w) const {
  for (const Boat& b : boats_) b.save(w);
  collisions_.save(w);  // collisions.md §6: after the boats
  if (created_) {
    race_.save(w);
    rules_.save(w);
  }
  for (std::size_t i = 0; i < boats_.size(); ++i) {
    put_outputs(w, boats_[i].outputs());
    put_env(w, env_[i]);
    put_sail_outputs(w, boats_[i].sails());
  }
  put_count(w, contacts_.size());
  for (const ContactEvent& c : contacts_) {
    w.put_u64(c.tick);
    w.put_i32(c.boat);
    put_enum(w, c.other_kind);
    w.put_i32(c.other);
    put_vec2(w, c.point);
    put_vec2(w, c.normal);
    w.put_f32(c.depth);
    w.put_f32(c.closing_speed);
    w.put_f32(c.impulse);
    w.put_bool(c.begin);
  }
  put_count(w, commands_.size());
  for (const Command& c : commands_) {
    put_enum(w, c.kind);
    w.put_i32(c.boat);
    w.put_f32(c.value);
    w.put_i32(c.sail);
  }
}

void World::save(SnapshotWriter& w) const {
  w.put_u32(kMagic);
  w.put_u32(kVersion);
  w.put_u32(tick_);
  w.put_u64(setup_.race_seed);
  w.put_bool(created_);
  w.put_u32(created_ ? race_.n_created() : 0u);
  w.put_u32(created_ ? entries_at_create_ : 0u);
  w.put_u64(setup_.venue != nullptr ? text_id(setup_.venue->file_sha256) : 0u);
  w.put_u64(created_ ? text_id(course_.hash()) : 0u);
  put_count(w, entries_.size());
  for (const BoatEntry& e : entries_) {
    w.put_u64(text_id(e.perf->file_sha256));
    w.put_bool(e.human);
    w.put_bool(e.ai);
    w.put_f32(e.performance_scale);
    w.put_bool(e.auto_trim);
    w.put_i32(e.front_sail);
  }
  save_body(w);
}

bool World::load(std::span<const std::uint8_t> bytes, const CourseData* course, std::string& error) {
  // A scratch world built as this one was takes the snapshot first, so one that fails leaves this world as it was;
  // then this world is reset and takes it the same way, which cannot fail.
  {
    World probe(setup_);
    for (const BoatEntry& e : entries_) (void)probe.add_boat(e);
    if (!probe.load_new(bytes, course, error)) return false;
  }
  reset();
  return load_new(bytes, course, error);
}

void World::reset() {
  std::vector<BoatEntry> entries = std::move(entries_);
  Controller controller = std::move(controller_);
  *this = World(setup_);
  controller_ = std::move(controller);
  for (const BoatEntry& e : entries) (void)add_boat(e);
}

bool World::load_new(std::span<const std::uint8_t> bytes, const CourseData* course, std::string& error) {
  SnapshotReader r(bytes);
  if (r.get_u32() != kMagic || r.get_u32() != kVersion) {
    error = "not a world snapshot of this version";
    return false;
  }
  const std::uint32_t tick = r.get_u32();
  const std::uint64_t seed = r.get_u64();
  const bool created = r.get_bool();
  const std::uint32_t n_created = r.get_u32();
  const std::uint32_t at_create = r.get_u32();
  const std::uint64_t venue_id = r.get_u64();
  const std::uint64_t course_id = r.get_u64();
  const std::uint32_t nb = get_count(r, 19);
  if (r.failed()) {
    error = "snapshot truncated";
    return false;
  }
  if (seed != setup_.race_seed) {
    error = "the snapshot is of another race seed";
    return false;
  }
  if (nb != entries_.size()) {
    error = "snapshot has " + std::to_string(nb) + " boats, the world " + std::to_string(entries_.size());
    return false;
  }
  for (std::uint32_t i = 0; i < nb; ++i) {
    const BoatEntry& e = entries_[i];
    const std::uint64_t perf_id = r.get_u64();
    const bool human = r.get_bool(), ai = r.get_bool();
    const float scale = r.get_f32();
    const bool auto_trim = r.get_bool();
    const std::int32_t front = r.get_i32();
    if (perf_id != text_id(e.perf->file_sha256) || human != e.human || ai != e.ai ||
        !(scale == e.performance_scale) || auto_trim != e.auto_trim || front != e.front_sail) {
      error = "boat " + std::to_string(i) + " does not match the snapshot's entry";
      return false;
    }
  }
  const std::uint64_t my_venue = setup_.venue != nullptr ? text_id(setup_.venue->file_sha256) : 0u;
  if (r.failed() || venue_id != my_venue) {
    error = r.failed() ? "snapshot truncated" : "the snapshot is of another venue";
    return false;
  }

  if (created) {
    if (course == nullptr) {
      error = "the snapshot has a race: its course is needed";
      return false;
    }
    if (at_create == 0 || at_create > nb || n_created > tick) {
      error = "snapshot header out of range";
      return false;
    }
    // Rebuild the world as it was built: the race at n_created with the entries of then, later ones joining.
    const std::vector<BoatEntry> later(entries_.begin() + at_create, entries_.end());
    boats_.resize(at_create);
    entries_.resize(at_create);
    shadow_classes_.resize(at_create);
    env_.resize(at_create);
    collide_in_.resize(at_create);
    tick_ = n_created;
    if (!create_race(*course, error)) return false;
    for (const BoatEntry& e : later) {
      if (add_boat(e) < 0) {
        error = "a joined boat could not be added again";
        return false;
      }
    }
    if (text_id(course_.hash()) != course_id) {
      error = "the snapshot is of another course";
      return false;
    }
  }
  tick_ = tick;

  for (Boat& b : boats_) {
    if (!b.load(r)) {
      error = "boat state damaged";
      return false;
    }
  }
  if (!collisions_.load(r)) {
    error = "collision state damaged";
    return false;
  }
  if (created && !race_.load(r)) {
    error = "race state damaged";
    return false;
  }
  if (created && !rules_.load(r)) {
    error = "rules state damaged";
    return false;
  }
  std::vector<BoatOutputs> outs(nb);
  std::vector<std::vector<SailOutput>> sail_outs(nb);
  for (std::uint32_t i = 0; i < nb; ++i) {
    outs[i] = get_outputs(r);
    env_[i] = get_env(r);
    sail_outs[i] = get_sail_outputs(r, boats_[i].sails().sail_count());
  }
  const std::uint32_t nc = get_count(r, 46);
  std::vector<ContactEvent> contacts(nc);
  for (ContactEvent& c : contacts) {
    c.tick = r.get_u64();
    c.boat = r.get_i32();
    c.other_kind = get_enum(r, ContactKind::land);
    c.other = r.get_i32();
    c.point = get_vec2(r);
    c.normal = get_vec2(r);
    c.depth = r.get_f32();
    c.closing_speed = r.get_f32();
    c.impulse = r.get_f32();
    c.begin = r.get_bool();
    if (c.boat < 0 || static_cast<std::uint32_t>(c.boat) >= nb) r.fail();
  }
  const std::uint32_t nq = get_count(r, 13);
  std::vector<Command> commands(nq);
  for (Command& c : commands) {
    c.kind = get_enum(r, Command::Kind::protest);
    c.boat = r.get_i32();
    c.value = r.get_f32();
    c.sail = r.get_i32();
  }
  if (r.failed() || !r.at_end()) {
    error = r.failed() ? "snapshot truncated or damaged" : "bytes left over after the snapshot";
    return false;
  }
  for (std::uint32_t i = 0; i < nb; ++i) boats_[i].restore_outputs(outs[i], sail_outs[i]);
  contacts_ = std::move(contacts);
  commands_ = std::move(commands);
  if (created) {
    race_.clear_events();
    rules_.clear_events();
  }
  events_ = WorldEvents{};
  return true;
}

}  // namespace wm
