// The skippers' memory block (ai.md §16): every value an AI carries from one tick to the next, written by one field
// visitor so save and load cannot drift apart. Polar tables and shadow classes are caches rebuilt from the world's
// performance data; the per tick context is rebuilt every step.
#include <type_traits>

#include "ai/ai.h"
#include "ai/ai_internal.h"

namespace wm {

namespace {

constexpr std::uint32_t kAiMagic = 0x49414D57u;  // "WMAI"
constexpr std::uint32_t kAiVersion = 3;
constexpr std::uint32_t kMaxBadAir = 100000;

struct Put {
  SnapshotWriter& w;
  void operator()(float& x) { w.put_f32(x); }
  void operator()(bool& x) { w.put_bool(x); }
  void operator()(std::int8_t& x) { w.put_i8(x); }
  void operator()(std::int32_t& x) { w.put_i32(x); }
  void operator()(std::uint32_t& x) { w.put_u32(x); }
  void operator()(std::uint64_t& x) { w.put_u64(x); }
  template <class E>
    requires std::is_enum_v<E>
  void operator()(E& x) {
    w.put_u8(static_cast<std::uint8_t>(x));
  }
  void operator()(Vec2& x) {
    w.put_f32(x.x);
    w.put_f32(x.y);
  }
  void count(std::size_t n) { w.put_u32(static_cast<std::uint32_t>(n)); }
};

struct Get {
  SnapshotReader& r;
  void operator()(float& x) { x = r.get_f32(); }
  void operator()(bool& x) {
    const std::uint8_t v = r.get_u8();
    if (v > 1) r.fail();
    x = v != 0;
  }
  void operator()(std::int8_t& x) { x = r.get_i8(); }
  void operator()(std::int32_t& x) { x = r.get_i32(); }
  void operator()(std::uint32_t& x) { x = r.get_u32(); }
  void operator()(std::uint64_t& x) { x = r.get_u64(); }
  template <class E>
    requires std::is_enum_v<E>
  void operator()(E& x) {
    x = static_cast<E>(r.get_u8());
  }
  void operator()(Vec2& x) {
    x.x = r.get_f32();
    x.y = r.get_f32();
  }
};

template <class V>
void visit_telemetry(V& v, AiTelemetry& t) {
  v(t.tacks); v(t.gybes); v(t.penalties); v(t.ocs);
  for (std::int32_t& k : t.activations) v(k);
  v(t.stuck_s); v(t.min_gap); v(t.sail_changes); v(t.start_delay);
}

template <class V>
void visit_bad_air(V& v, AiBadAirRecord& r) {
  v(r.tick); v(r.d_at); v(r.d_after);
}

template <class V>
void visit_debug(V& v, AiDebug& d) {
  v(d.tactic); v(d.psi_target); v(d.d); v(d.twd_ref); v(d.twd_f); v(d.tws_f); v(d.leg); v(d.manoeuvre);
  v(d.aim); v(d.spot);
}

// Every carried field of one AI, in declaration order (ai_internal.h). The level, `speed_only` and `autopilot_only`
// come first: the level parameters are rebuilt from them.
template <class V>
void visit_boat(V& v, AiSkippers::Boat& a) {
  v(a.level); v(a.speed_only); v(a.autopilot_only); v(a.active);
  v(a.k16); v(a.k17);
  v(a.init); v(a.fx); v(a.fy); v(a.rx); v(a.ry); v(a.sx); v(a.sy); v(a.tws_f); v(a.tws_felt); v(a.d_f);
  v(a.twd_f); v(a.twd_ref); v(a.twd_5); v(a.shift);
  v(a.man); v(a.man_t0); v(a.man_from); v(a.man_to); v(a.man_passed); v(a.man_forced); v(a.irons_t);
  v(a.irons_until); v(a.last_man); v(a.low_until); v(a.pend_tack); v(a.pend_reason); v(a.turn_dir);
  v(a.leg); v(a.leg_step); v(a.speed_build); v(a.headed_t); v(a.pressure_t); v(a.route_t); v(a.route_gain); v(a.route_stay); v(a.gate_step); v(a.gate_buoy);
  v(a.rounding); v(a.round_mark);
  v(a.phase); v(a.spot_fixed); v(a.spot_u); v(a.spot_beta); v(a.spot_rank); v(a.drawn); v(a.spread_r); v(a.e_start); v(a.go);
  v(a.loop); v(a.hover_fly); v(a.ret_stage); v(a.match_stage);
  v(a.avoid_until); v(a.avoid_hold); v(a.avoid_psi); v(a.avoid_slow); v(a.avoid_other); v(a.avoid_kind);
  v(a.pin_t); v(a.pin_until); v(a.pin_seen); v(a.pin_n); v(a.pin_mode); v(a.pin_check_t); v(a.pin_c); v(a.pin_psi);
  v(a.bad_t); v(a.foot_until); v(a.foot_delta); v(a.bad_src); v(a.bad_last);
  v(a.opp_other_t); v(a.cover_opp); v(a.opp_tack_prev); v(a.opp_tacked_at);
  v(a.pen_on); v(a.pen_t0); v(a.pen_dir); v(a.pen_seen_turning); v(a.pen_stall_t); v(a.pen_prepare); v(a.pen_block); v(a.pen_served0);
  v(a.change_t); v(a.change_want);
  v(a.psi_target); v(a.let_fly); v(a.helm_fixed); v(a.forced); v(a.r_limit); v(a.h_int); v(a.tactic);
  v(a.prev_tactic); v(a.decided);
  visit_telemetry(v, a.tel);
  visit_debug(v, a.dbg);
  v(a.slow_t); v(a.pen_seen); v(a.ocs_counted); v(a.tack_prev);
}

}  // namespace

void AiSkippers::save(SnapshotWriter& w, const World& world) const {
  w.put_u32(kAiMagic);
  w.put_u32(kAiVersion);
  w.put_u32(world.tick());
  w.put_u64(world.setup().race_seed);
  w.put_u32(static_cast<std::uint32_t>(world.boat_count()));
  w.put_u32(static_cast<std::uint32_t>(boats_.size()));
  Put put{w};
  for (const auto& bp : boats_) {
    Boat a = *bp;  // the visitor takes references; the copy keeps save const
    w.put_i32(a.i);
    visit_boat(put, a);
    put.count(a.tel.bad_air.size());
    for (AiBadAirRecord& r : a.tel.bad_air) visit_bad_air(put, r);
  }
}

bool AiSkippers::load(std::span<const std::uint8_t> bytes, const World& world, std::string& error) {
  SnapshotReader r(bytes);
  if (r.get_u32() != kAiMagic || r.get_u32() != kAiVersion) {
    error = "not an AI block of this version";
    return false;
  }
  const std::uint32_t tick = r.get_u32();
  const std::uint64_t seed = r.get_u64();
  const std::uint32_t nb = r.get_u32();
  const std::uint32_t n = r.get_u32();
  if (r.failed()) {
    error = "AI block truncated";
    return false;
  }
  if (tick != world.tick() || seed != world.setup().race_seed || nb != world.boat_count()) {
    error = "the AI block is of another tick, seed or fleet than the world";
    return false;
  }
  if (n > nb) {
    error = "AI block out of range";
    return false;
  }
  std::vector<std::unique_ptr<Boat>> boats;
  Get get{r};
  for (std::uint32_t k = 0; k < n && !r.failed(); ++k) {
    auto a = std::make_unique<Boat>();
    a->i = r.get_i32();
    visit_boat(get, *a);
    const std::uint32_t nr = r.get_u32();
    if (a->i < 0 || static_cast<std::uint32_t>(a->i) >= nb || nr > kMaxBadAir ||
        static_cast<std::uint8_t>(a->level) > 3 || static_cast<std::uint8_t>(a->man) > 4 ||
        static_cast<std::uint8_t>(a->leg) > 2 || static_cast<std::uint8_t>(a->phase) > 3 || a->pin_mode < 0 ||
        a->pin_mode > 2 ||
        static_cast<std::size_t>(a->tactic) >= kAiTacticCount ||
        static_cast<std::size_t>(a->prev_tactic) >= kAiTacticCount ||
        static_cast<std::size_t>(a->pend_reason) >= kAiTacticCount ||
        static_cast<std::size_t>(a->avoid_kind) >= kAiTacticCount ||
        static_cast<std::size_t>(a->dbg.tactic) >= kAiTacticCount) {
      r.fail();
      break;
    }
    for (const auto& o : boats) {
      if (o->i == a->i) r.fail();
    }
    a->tel.bad_air.resize(nr);
    for (AiBadAirRecord& rec : a->tel.bad_air) visit_bad_air(get, rec);
    a->P = a->autopilot_only ? ai_level_params(AiLevel::intermediate) : ai_level_params(a->level, a->speed_only);
    boats.push_back(std::move(a));
  }
  if (r.failed() || !r.at_end()) {
    error = r.failed() ? "AI block truncated or damaged" : "bytes left over after the AI block";
    return false;
  }
  boats_ = std::move(boats);
  return true;
}

}  // namespace wm
