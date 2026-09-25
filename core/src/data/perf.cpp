#include "data/perf.h"

#include <cmath>
#include <cstring>
#include <span>

#include "data/json.h"
#include "data/table_reader.h"
#include "state/sha256.h"

namespace wm {

namespace {

using data::member;
using data::read_float;
using data::read_table;
using data::TableSpec;
using json::Value;

constexpr float kInf = INFINITY;

// data_format.md §4.3: the tws axis of every config table covers 0 to at least 40 kn.
constexpr float kTwsCoverage = 20.6f;

// Value specs of every table the performance file carries (data_format.md §4, §5; sails.md §6).
const TableSpec kPolar{{Quantity::tws, Quantity::twa_abs}, Unit::m_s, -5.0f, 40.0f};
const TableSpec kHeel{{Quantity::tws, Quantity::twa_abs}, Unit::rad, 0.0f, HALF_PI};
const TableSpec kAccel{{Quantity::tws, Quantity::twa_abs}, Unit::m_s2, 0.0f, kInf};
const TableSpec kTrim{{Quantity::tws, Quantity::awa_abs, Quantity::trim_error}, Unit::one, 0.0f, 3.0f};
const TableSpec kWeatherHelm{{Quantity::tws, Quantity::twa_abs}, Unit::rad_s, -kInf, kInf};
const TableSpec kFallOff{{Quantity::boat_speed, Quantity::twa_abs}, Unit::rad_s, 0.0f, kInf};
const TableSpec kFlogDrag{{Quantity::aws, Quantity::awa_abs}, Unit::m_s2, 0.0f, kInf};
const TableSpec kOptimalAngle{{Quantity::tws, Quantity::awa_abs}, Unit::rad, 0.0f, PI};
const TableSpec kHeelSpeedFactor{{Quantity::heel_abs}, Unit::one, 0.0f, 3.0f};
const TableSpec kRudderDrag{{Quantity::boat_speed_abs, Quantity::helm_abs}, Unit::m_s2, -kInf, kInf};
// Sail angle magnitudes: the spec gives no explicit range; a magnitude lies in [0, pi].
const TableSpec kSheetMaxByHeel{{Quantity::heel_abs}, Unit::rad, 0.0f, PI};
const TableSpec kPoleAngle{{Quantity::tws, Quantity::awa_abs}, Unit::rad, 0.0f, PI};
const TableSpec kShiverAngle{{Quantity::tws}, Unit::rad, 0.0f, PI};
const TableSpec kDuration{{Quantity::tws, Quantity::twa_abs}, Unit::s, 0.0f, kInf};

struct NamedType {
  std::string_view name;
  SailType type;
};
constexpr NamedType kSailTypes[] = {
    {"main", SailType::main},
    {"jib", SailType::jib},
    {"genoa", SailType::genoa},
    {"code_zero", SailType::code_zero},
    {"spinnaker_sym", SailType::spinnaker_sym},
    {"spinnaker_asym", SailType::spinnaker_asym},
};

class PerfReader {
 public:
  PerfReader(ErrorSink& sink, PerfData& out) : sink_(sink), out_(out) {}

  bool read(const Value& root) {
    if (!data::check_schema(root, "windmark.perf", 1, sink_)) return false;
    return header(root) && dynamics(root) && sails(root) && configs(root) && start(root);
  }

 private:
  ErrorSink& sink_;
  PerfData& out_;

  bool fail(const std::string& path, std::string_view why) { return sink_.fail(path, why); }

  bool header(const Value& root) {
    if (!data::read_string(root, "$", "class_id", out_.class_id, sink_)) return false;
    if (!data::is_valid_id(out_.class_id)) return fail("$.class_id", "ids are lowercase [a-z0-9_]");
    if (!data::read_int(root, "$", "class_version", out_.class_version, sink_)) return false;
    if (out_.class_version < 1) return fail("$.class_version", "must be >= 1");
    if (!data::read_string(root, "$", "class_sha256", out_.class_sha256, sink_)) return false;
    if (out_.class_sha256.size() != 64) return fail("$.class_sha256", "expected 64 lowercase hex digits");
    for (char c : out_.class_sha256) {
      if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
        return fail("$.class_sha256", "expected 64 lowercase hex digits");
      }
    }
    if (const Value* g = member(root, "$", "generator", false, sink_)) {
      if (!data::expect_object(*g, "$.generator", sink_)) return false;
      if (const Value* t = g->find("tool"); t && t->is_string()) out_.generator_tool = t->text;
      if (const Value* v = g->find("version"); v && v->is_string()) out_.generator_version = v->text;
    }
    return true;
  }

  // A float that must lie in [lo, hi] (inclusive).
  bool ranged(const Value& obj, const std::string& path, std::string_view key, float& out, float lo, float hi) {
    if (!read_float(obj, path, key, out, sink_)) return false;
    if (out < lo || out > hi) return fail(path_key(path, key), "value outside its allowed range");
    return true;
  }

  bool positive(const Value& obj, const std::string& path, std::string_view key, float& out) {
    if (!read_float(obj, path, key, out, sink_)) return false;
    if (!(out > 0.0f)) return fail(path_key(path, key), "must be > 0");
    return true;
  }

  bool table(const Value& obj, const std::string& path, std::string_view key, const TableSpec& spec, Table& out) {
    const Value* v = member(obj, path, key, true, sink_);
    return v != nullptr && read_table(*v, path_key(path, key), spec, out, sink_);
  }

  bool optional_table(const Value& obj, const std::string& path, std::string_view key, const TableSpec& spec,
                      OptionalTable& out) {
    const Value* v = obj.find(key);
    out.present = v != nullptr;
    return v == nullptr || read_table(*v, path_key(path, key), spec, out.table, sink_);
  }

  bool dynamics(const Value& root) {
    const std::string p = "$.dynamics";
    const Value* dv = member(root, "$", "dynamics", true, sink_);
    if (dv == nullptr || !data::expect_object(*dv, p, sink_)) return false;
    const Value& d = *dv;
    Dynamics& y = out_.dynamics;
    const bool scalars =
        positive(d, p, "helm_rate", y.helm_rate) && ranged(d, p, "rudder_max", y.rudder_max, 0.0f, HALF_PI) &&
        positive(d, p, "turn_radius_full", y.turn_radius_full) &&
        read_float(d, p, "turn_radius_offset", y.turn_radius_offset, sink_) &&
        ranged(d, p, "yaw_time", y.yaw_time, 0.0f, 2.0f) &&
        ranged(d, p, "decel_linear", y.decel_linear, 0.0f, kInf) &&
        ranged(d, p, "decel_const", y.decel_const, 0.0f, kInf) &&
        table(d, p, "heel_speed_factor", kHeelSpeedFactor, y.heel_speed_factor) &&
        table(d, p, "rudder_drag_luff", kRudderDrag, y.rudder_drag_luff) &&
        table(d, p, "rudder_drag_bear", kRudderDrag, y.rudder_drag_bear) &&
        ranged(d, p, "heel_max", y.heel_max, 0.0f, HALF_PI) && ranged(d, p, "heel_limit", y.heel_limit, 0.0f, HALF_PI) &&
        positive(d, p, "heel_freq", y.heel_freq) && ranged(d, p, "heel_damping", y.heel_damping, 0.0f, kInf) &&
        positive(d, p, "pitch_freq", y.pitch_freq) && ranged(d, p, "pitch_damping", y.pitch_damping, 0.0f, kInf) &&
        read_float(d, p, "wave_roll_gain", y.wave_roll_gain, sink_) &&
        read_float(d, p, "wave_pitch_gain", y.wave_pitch_gain, sink_) &&
        read_float(d, p, "wobble_heel", y.wobble_heel, sink_) &&
        read_float(d, p, "wobble_pitch", y.wobble_pitch, sink_) &&
        read_float(d, p, "wobble_freq", y.wobble_freq, sink_) &&
        ranged(d, p, "heave_time", y.heave_time, 0.0f, kInf) &&
        read_float(d, p, "waterline_offset", y.waterline_offset, sink_) &&
        read_float(d, p, "surf_gain", y.surf_gain, sink_) && positive(d, p, "lwl", y.lwl) &&
        positive(d, p, "bwl", y.bwl) && positive(d, p, "loa", y.loa);
    if (!scalars) return false;

    if (const Value* hp = d.find("hull_points")) {
      y.has_hull_points = true;
      if (!data::read_points(*hp, p + ".hull_points", y.hull_points, sink_)) return false;
      if (y.hull_points.empty() || y.hull_points.size() > 64)
        return fail(p + ".hull_points", "1 to 64 points");
    }
    return collision(d, p + ".collision") && wind_shadow(d, p + ".wind_shadow") && derive(p);
  }

  // boat.md §4.1: derived constants in the spec's order, then their validation.
  bool derive(const std::string& p) {
    Dynamics& y = out_.dynamics;
    DerivedDynamics& k = y.derived;
    k.heel_k1 = (y.heel_freq * y.heel_freq) * DT;
    k.heel_k2 = 1.0f - ((2.0f * y.heel_damping) * y.heel_freq) * DT;
    k.pitch_k1 = (y.pitch_freq * y.pitch_freq) * DT;
    k.pitch_k2 = 1.0f - ((2.0f * y.pitch_damping) * y.pitch_freq) * DT;
    k.heave_a = DT / (y.heave_time + DT);
    k.turn_c = y.turn_radius_full + y.turn_radius_offset;
    k.yaw_a = DT / (y.yaw_time + DT);
    // The offset may be negative (a rudder that stalls short of full helm), but the radius law needs turn_c > 0.
    if (!(k.turn_c > 0.0f)) return fail(p + ".turn_radius_offset", "turn_radius_full + turn_radius_offset <= 0");
    if (!(k.heel_k2 >= 0.0f && k.heel_k2 < 1.0f)) return fail(p + ".heel_damping", "heel_k2 outside [0, 1)");
    if (!(k.pitch_k2 >= 0.0f && k.pitch_k2 < 1.0f)) return fail(p + ".pitch_damping", "pitch_k2 outside [0, 1)");
    // boat.md §4.1 asks for heel_k1, pitch_k1 in (0, 1], but k1 = w^2 DT carries 1/s: the bound only makes sense
    // on the dimensionless per-tick gain k1*DT = (w DT)^2. With k2 in [0, 1) that bound also keeps the
    // recurrence of §5.6/§5.7 stable (it needs (w DT)^2 < 2 (1 + k2)). Read as k1*DT in (0, 1].
    const float heel_gain = k.heel_k1 * DT;
    const float pitch_gain = k.pitch_k1 * DT;
    if (!(heel_gain > 0.0f && heel_gain <= 1.0f)) return fail(p + ".heel_freq", "heel_k1*DT outside (0, 1]");
    if (!(pitch_gain > 0.0f && pitch_gain <= 1.0f)) return fail(p + ".pitch_freq", "pitch_k1*DT outside (0, 1]");
    return true;
  }

  // collisions.md §2.1: 6-32 vertices, strictly convex, counter-clockwise, containing the origin.
  bool collision(const Value& d, const std::string& p) {
    const Value* cv = member(d, "$.dynamics", "collision", true, sink_);
    if (cv == nullptr || !data::expect_object(*cv, p, sink_)) return false;
    CollisionShape& c = out_.dynamics.collision;
    const Value* ov = member(*cv, p, "outline", true, sink_);
    if (ov == nullptr || !data::read_points(*ov, p + ".outline", c.outline, sink_)) return false;
    if (!positive(*cv, p, "mass", c.mass) || !positive(*cv, p, "yaw_gyration", c.yaw_gyration)) return false;
    const std::size_t n = c.outline.size();
    if (n < 6 || n > 32) return fail(p + ".outline", "outline needs 6 to 32 vertices");
    for (std::size_t i = 0; i < n; ++i) {
      const Vec2 a = c.outline[i];
      const Vec2 b = c.outline[(i + 1) % n];
      const Vec2 e = c.outline[(i + 2) % n];
      const float turn = (b.x - a.x) * (e.y - b.y) - (b.y - a.y) * (e.x - b.x);
      if (!(turn > 0.0f)) {
        return fail(path_index(p + ".outline", (i + 1) % n), "outline not strictly convex and counter-clockwise");
      }
      // Origin strictly to the left of every edge.
      const float side = (b.x - a.x) * (0.0f - a.y) - (b.y - a.y) * (0.0f - a.x);
      if (!(side > 0.0f)) return fail(path_index(p + ".outline", i), "outline does not contain the origin");
    }
    return true;
  }

  bool wind_shadow(const Value& d, const std::string& p) {
    const Value* wv = member(d, "$.dynamics", "wind_shadow", true, sink_);
    if (wv == nullptr || !data::expect_object(*wv, p, sink_)) return false;
    const Value& w = *wv;
    WindShadowParams& s = out_.dynamics.wind_shadow;
    struct Field {
      std::string_view key;
      float* dst;
    };
    const Field fields[] = {
        {"height", &s.height},
        {"ce_x", &s.ce_x},
        {"stern_x", &s.stern_x},
        {"chord", &s.chord},
        {"width_min", &s.width_min},
        {"width_spinnaker", &s.width_spinnaker},
        {"length_coef", &s.length_coef},
        {"length_knee", &s.length_knee},
        {"blanket_depth", &s.blanket_depth},
        {"blanket_depth_spinnaker", &s.blanket_depth_spinnaker},
        {"blanket_peak", &s.blanket_peak},
        {"blanket_near", &s.blanket_near},
        {"blanket_reach_up", &s.blanket_reach_up},
        {"blanket_spread", &s.blanket_spread},
        {"turb_length", &s.turb_length},
        {"turb_depth", &s.turb_depth},
        {"turb_width", &s.turb_width},
        {"turb_spread", &s.turb_spread},
        {"turb_angle", &s.turb_angle},
        {"turb_awa_fade", &s.turb_awa_fade},
        {"turb_awa_max", &s.turb_awa_max},
        {"header_coef", &s.header_coef},
        {"header_max", &s.header_max},
    };
    for (const Field& f : fields) {
      if (!read_float(w, p, f.key, *f.dst, sink_)) return false;
    }
    if (!(s.height > 0.0f)) return fail(p + ".height", "must be > 0");
    if (!(s.length_knee > 0.0f)) return fail(p + ".length_knee", "must be > 0");
    if (!(s.turb_awa_fade <= s.turb_awa_max)) return fail(p + ".turb_awa_max", "must be >= turb_awa_fade");
    return true;
  }

  bool duration(const Value& h, const std::string& p, std::string_view key, Duration& out) {
    const Value* v = member(h, p, key, true, sink_);
    if (v == nullptr) return false;
    const std::string kp = path_key(p, key);
    if (v->is_number()) {
      out.is_table = false;
      if (!data::read_float_value(*v, kp, out.constant, sink_)) return false;
      if (!(out.constant >= 0.0f)) return fail(kp, "durations are >= 0");
      return true;
    }
    out.is_table = true;
    return read_table(*v, kp, kDuration, out.table, sink_);
  }

  bool handling(const Value& s, const std::string& p, SailPerf& sail) {
    const Value* hv = s.find("handling");
    const bool is_main = sail.type == SailType::main;
    if (is_main) {
      if (hv != nullptr) return fail(p + ".handling", "the main has no handling block");
      return true;
    }
    if (hv == nullptr) return fail(p + ".handling", "required key missing (front sails)");
    const std::string hp = p + ".handling";
    if (!data::expect_object(*hv, hp, sink_)) return false;
    SailHandling& h = sail.handling;
    sail.has_handling = true;
    return duration(*hv, hp, "prepare_hoist_time", h.prepare_hoist_time) &&
           duration(*hv, hp, "hoist_time", h.hoist_time) &&
           duration(*hv, hp, "prepare_drop_time", h.prepare_drop_time) &&
           duration(*hv, hp, "drop_time", h.drop_time) &&
           ranged(*hv, hp, "slow_prepare_hoist", h.slow_prepare_hoist, 0.0f, kInf) &&
           ranged(*hv, hp, "slow_hoist", h.slow_hoist, 0.0f, kInf) &&
           ranged(*hv, hp, "slow_prepare_drop", h.slow_prepare_drop, 0.0f, kInf) &&
           ranged(*hv, hp, "slow_drop", h.slow_drop, 0.0f, kInf);
  }

  bool sails(const Value& root) {
    const Value* sv = member(root, "$", "sails", true, sink_);
    if (sv == nullptr || !data::expect_object(*sv, "$.sails", sink_)) return false;
    if (sv->members.empty()) return fail("$.sails", "no sails");
    for (const auto& [id, s] : sv->members) {
      const std::string p = path_key("$.sails", id);
      if (!data::is_valid_id(id)) return fail(p, "ids are lowercase [a-z0-9_]");
      if (!data::expect_object(s, p, sink_)) return false;
      SailPerf sail;
      sail.id = id;
      std::string type;
      if (!data::read_string(s, p, "type", type, sink_)) return false;
      if (!sail_type_from_name(type, sail.type)) return fail(p + ".type", "unknown sail type \"" + type + "\"");
      if (!ranged(s, p, "sheet_min", sail.sheet_min, 0.0f, PI) || !ranged(s, p, "sheet_max", sail.sheet_max, 0.0f, PI)) {
        return false;
      }
      if (!(sail.sheet_min <= sail.sheet_max)) return fail(p + ".sheet_max", "sheet_max < sheet_min");
      if (!optional_table(s, p, "sheet_max_by_heel", kSheetMaxByHeel, sail.sheet_max_by_heel)) return false;
      if (!positive(s, p, "rate_in", sail.rate_in) || !positive(s, p, "rate_out", sail.rate_out)) return false;
      if (!optional_table(s, p, "pole_angle", kPoleAngle, sail.pole_angle)) return false;
      if (s.find("pole_rate") != nullptr) {
        sail.has_pole_rate = true;
        if (!positive(s, p, "pole_rate", sail.pole_rate)) return false;
      }
      if (sail.pole_angle.present && !sail.has_pole_rate) return fail(p + ".pole_rate", "required with pole_angle");
      if (!table(s, p, "shiver_angle", kShiverAngle, sail.shiver_angle)) return false;
      if (!data::read_bool(s, p, "shiver_free", sail.shiver_free, sink_)) return false;
      if (!handling(s, p, sail)) return false;
      if (sail.type == SailType::main) {
        if (out_.main_sail >= 0) return fail(p + ".type", "more than one main");
        out_.main_sail = static_cast<std::int32_t>(out_.sails.size());
      }
      out_.sails.push_back(std::move(sail));
    }
    if (out_.main_sail < 0) return fail("$.sails", "no sail of type main");
    return true;
  }

  // Coverage of the config tables (data_format.md §4.3): tws from 0 to >= 20.6 m/s, twa_abs/awa_abs 0 to pi, aws
  // from 0.
  bool coverage(const Table& t, const std::string& p) {
    for (std::uint32_t a = 0; a < t.rank(); ++a) {
      const Axis& ax = t.axis(a);
      const std::string ap = path_index(p + ".axes", a) + ".points";
      if (ax.q == Quantity::tws) {
        if (ax.points.front() != 0.0f || !(ax.points.back() >= kTwsCoverage)) {
          return fail(ap, "tws axis must run from 0 to at least 20.6 m/s");
        }
      } else if (ax.q == Quantity::aws) {
        if (ax.points.front() != 0.0f) return fail(ap, "aws axis must start at 0");
      } else if (ax.q == Quantity::twa_abs || ax.q == Quantity::awa_abs) {
        if (ax.points.front() != 0.0f || ax.points.back() != PI) {
          return fail(ap, std::string(quantity_name(ax.q)) + " axis must run from 0 to pi");
        }
      }
    }
    return true;
  }

  bool config_table(const Value& c, const std::string& p, std::string_view key, const TableSpec& spec, Table& out) {
    return table(c, p, key, spec, out) && coverage(out, path_key(p, key));
  }

  bool config_optional(const Value& c, const std::string& p, std::string_view key, const TableSpec& spec,
                       OptionalTable& out) {
    if (!optional_table(c, p, key, spec, out)) return false;
    return !out.present || coverage(out.table, path_key(p, key));
  }

  bool configs(const Value& root) {
    const Value* cv = member(root, "$", "configs", true, sink_);
    if (cv == nullptr) return false;
    if (!cv->is_array()) return fail("$.configs", "expected an array");
    std::vector<bool> seen(out_.sails.size(), false);
    bool seen_main_only = false;
    for (std::size_t i = 0; i < cv->items.size(); ++i) {
      const Value& c = cv->items[i];
      const std::string p = path_index("$.configs", i);
      if (!data::expect_object(c, p, sink_)) return false;
      ConfigPerf cfg;
      const Value* fs = member(c, p, "front_sail", true, sink_);
      if (fs == nullptr) return false;
      if (fs->is_null()) {
        if (seen_main_only) return fail(p + ".front_sail", "second main-only config");
        seen_main_only = true;
      } else if (fs->is_string()) {
        cfg.front_sail = out_.find_sail(fs->text);
        if (cfg.front_sail < 0) return fail(p + ".front_sail", "unknown sail \"" + fs->text + "\"");
        if (cfg.front_sail == out_.main_sail) return fail(p + ".front_sail", "the main is not a front sail");
        if (seen[static_cast<std::size_t>(cfg.front_sail)]) return fail(p + ".front_sail", "second config for this sail");
        seen[static_cast<std::size_t>(cfg.front_sail)] = true;
      } else {
        return fail(p + ".front_sail", "expected a sail id or null");
      }
      if (!config_table(c, p, "polar", kPolar, cfg.polar) || !config_table(c, p, "heel", kHeel, cfg.heel) ||
          !config_table(c, p, "accel", kAccel, cfg.accel) ||
          !config_optional(c, p, "accel_rest", kAccel, cfg.accel_rest) ||
          !config_optional(c, p, "trim_speed", kTrim, cfg.trim_speed) ||
          !config_optional(c, p, "trim_heel", kTrim, cfg.trim_heel) ||
          !config_optional(c, p, "weather_helm", kWeatherHelm, cfg.weather_helm) ||
          !config_optional(c, p, "fall_off", kFallOff, cfg.fall_off) ||
          !config_optional(c, p, "flog_drag", kFlogDrag, cfg.flog_drag)) {
        return false;
      }
      // optimal_angle: exactly the main and the config's front sail, keyed by sail id.
      const std::string op = p + ".optimal_angle";
      const Value* ov = member(c, p, "optimal_angle", true, sink_);
      if (ov == nullptr || !data::expect_object(*ov, op, sink_)) return false;
      const std::string& main_id = out_.sails[static_cast<std::size_t>(out_.main_sail)].id;
      if (!config_table(*ov, op, main_id, kOptimalAngle, cfg.optimal_main)) return false;
      std::size_t expected = 1;
      if (cfg.front_sail >= 0) {
        const std::string& front_id = out_.sails[static_cast<std::size_t>(cfg.front_sail)].id;
        if (!config_table(*ov, op, front_id, kOptimalAngle, cfg.optimal_front)) return false;
        expected = 2;
      }
      if (ov->members.size() != expected) {
        return fail(op, "holds only the main and the config's front sail");
      }
      out_.configs.push_back(std::move(cfg));
    }
    if (!seen_main_only) return fail("$.configs", "no main-only config");
    for (std::size_t s = 0; s < out_.sails.size(); ++s) {
      if (static_cast<std::int32_t>(s) != out_.main_sail && !seen[s]) {
        return fail("$.configs", "no config for front sail \"" + out_.sails[s].id + "\"");
      }
    }
    return true;
  }

  bool start(const Value& root) {
    // Absent start block: no front sail at the start.
    const Value* sv = root.find("start");
    if (sv == nullptr) return true;
    if (!data::expect_object(*sv, "$.start", sink_)) return false;
    const Value* fs = sv->find("front_sail");
    if (fs == nullptr || fs->is_null()) return true;
    if (!fs->is_string()) return fail("$.start.front_sail", "expected a sail id or null");
    out_.start_front_sail = out_.find_sail(fs->text);
    if (out_.start_front_sail < 0 || out_.start_front_sail == out_.main_sail) {
      return fail("$.start.front_sail", "not a front sail of this class: \"" + fs->text + "\"");
    }
    return true;
  }
};

}  // namespace

bool sail_type_from_name(std::string_view name, SailType& out) {
  for (const NamedType& t : kSailTypes) {
    if (t.name == name) {
      out = t.type;
      return true;
    }
  }
  return false;
}

std::string_view sail_type_name(SailType type) {
  for (const NamedType& t : kSailTypes) {
    if (t.type == type) return t.name;
  }
  return "?";
}

std::int32_t PerfData::find_sail(std::string_view id) const {
  for (std::size_t i = 0; i < sails.size(); ++i) {
    if (sails[i].id == id) return static_cast<std::int32_t>(i);
  }
  return -1;
}

const ConfigPerf* PerfData::config_for(std::int32_t front_sail) const {
  for (const ConfigPerf& c : configs) {
    if (c.front_sail == front_sail) return &c;
  }
  return nullptr;
}

bool parse_perf(std::string_view text, std::string_view file, PerfData& out, LoadError& err) {
  out = PerfData{};
  err = LoadError{};
  ErrorSink sink(err, file);
  const json::ParseResult pr = json::parse(text);
  if (!pr.ok) return sink.fail("", "JSON: " + pr.error);
  PerfReader reader(sink, out);
  if (!reader.read(pr.value)) {
    out = PerfData{};
    return false;
  }
  const auto* bytes = reinterpret_cast<const std::uint8_t*>(text.data());
  out.file_sha256 = to_hex(sha256(std::span<const std::uint8_t>(bytes, text.size())));
  return true;
}

bool load_perf(const std::string& file, PerfData& out, LoadError& err) {
  std::string text;
  if (!data::read_file(file, text, err)) return false;
  return parse_perf(text, file, out, err);
}

}  // namespace wm
