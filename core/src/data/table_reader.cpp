#include "data/table_reader.h"

#include <cmath>
#include <fstream>
#include <sstream>

namespace wm::data {

namespace {

// Allowed axis ranges per quantity (data_format.md §5).
struct QuantityRange {
  float lo;
  float hi;
};

QuantityRange quantity_range(Quantity q) {
  constexpr float inf = INFINITY;
  switch (q) {
    case Quantity::tws: return {0.0f, inf};
    case Quantity::twa_abs:
    case Quantity::awa_abs: return {0.0f, PI};
    case Quantity::trim_error:
    case Quantity::boat_speed: return {-inf, inf};
    case Quantity::boat_speed_abs: return {0.0f, inf};
    case Quantity::helm_abs: return {0.0f, 1.0f};
    case Quantity::heel_abs: return {0.0f, HALF_PI};
  }
  return {-inf, inf};
}

std::string fmt_float(float f) {
  std::ostringstream os;
  os.precision(9);
  os << f;
  return os.str();
}

}  // namespace

bool expect_object(const json::Value& v, const std::string& path, ErrorSink& sink) {
  if (!v.is_object()) return sink.fail(path, "expected an object, found " + std::string(json::kind_name(v.kind)));
  return true;
}

const json::Value* member(const json::Value& obj, const std::string& path, std::string_view key, bool required,
                          ErrorSink& sink) {
  const json::Value* v = obj.find(key);
  if (v == nullptr && required) sink.fail(path_key(path, key), "required key missing");
  return v;
}

bool read_float_value(const json::Value& v, const std::string& path, float& out, ErrorSink& sink) {
  if (!v.is_number()) return sink.fail(path, "expected a number, found " + std::string(json::kind_name(v.kind)));
  if (!json::to_float(v, out)) return sink.fail(path, "number does not fit binary32: " + v.text);
  return true;
}

bool read_float(const json::Value& obj, const std::string& path, std::string_view key, float& out, ErrorSink& sink) {
  const json::Value* v = member(obj, path, key, true, sink);
  if (v == nullptr) return false;
  return read_float_value(*v, path_key(path, key), out, sink);
}

bool read_bool(const json::Value& obj, const std::string& path, std::string_view key, bool& out, ErrorSink& sink) {
  const json::Value* v = member(obj, path, key, true, sink);
  if (v == nullptr) return false;
  if (!v->is_bool()) return sink.fail(path_key(path, key), "expected a boolean");
  out = v->boolean;
  return true;
}

bool read_string(const json::Value& obj, const std::string& path, std::string_view key, std::string& out,
                 ErrorSink& sink) {
  const json::Value* v = member(obj, path, key, true, sink);
  if (v == nullptr) return false;
  if (!v->is_string()) return sink.fail(path_key(path, key), "expected a string");
  out = v->text;
  return true;
}

bool read_int(const json::Value& obj, const std::string& path, std::string_view key, std::int64_t& out,
              ErrorSink& sink) {
  const json::Value* v = member(obj, path, key, true, sink);
  if (v == nullptr) return false;
  if (!json::to_int64(*v, out)) return sink.fail(path_key(path, key), "expected an integer");
  return true;
}

bool read_points(const json::Value& v, const std::string& path, std::vector<Vec2>& out, ErrorSink& sink) {
  if (!v.is_array()) return sink.fail(path, "expected an array of [x, y] points");
  out.clear();
  out.reserve(v.items.size());
  for (std::size_t i = 0; i < v.items.size(); ++i) {
    const json::Value& p = v.items[i];
    const std::string pp = path_index(path, i);
    if (!p.is_array() || p.items.size() != 2) return sink.fail(pp, "expected an [x, y] pair");
    Vec2 q{};
    if (!read_float_value(p.items[0], path_index(pp, 0), q.x, sink)) return false;
    if (!read_float_value(p.items[1], path_index(pp, 1), q.y, sink)) return false;
    out.push_back(q);
  }
  return true;
}

bool is_valid_id(std::string_view id) {
  if (id.empty()) return false;
  for (char c : id) {
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) return false;
  }
  return true;
}

bool read_file(const std::string& file, std::string& out, LoadError& err) {
  std::ifstream in(file, std::ios::binary);
  if (!in) {
    err = {file, "", "cannot open file"};
    return false;
  }
  std::ostringstream ss;
  ss << in.rdbuf();
  if (in.bad()) {
    err = {file, "", "read error"};
    return false;
  }
  out = ss.str();
  return true;
}

bool check_schema(const json::Value& root, std::string_view name, int major, ErrorSink& sink) {
  if (!expect_object(root, "$", sink)) return false;
  std::string schema;
  if (!read_string(root, "$", "schema", schema, sink)) return false;
  const std::string prefix = std::string(name) + "/";
  if (schema.compare(0, prefix.size(), prefix) != 0) {
    return sink.fail("$.schema", "expected schema " + prefix + std::to_string(major) + ", found \"" + schema + "\"");
  }
  const std::string ver = schema.substr(prefix.size());
  if (ver != std::to_string(major)) {
    return sink.fail("$.schema", "unsupported major version \"" + schema + "\" (this reader reads " + prefix +
                                     std::to_string(major) + ")");
  }
  return true;
}

bool read_table(const json::Value& v, const std::string& path, const TableSpec& spec, Table& out, ErrorSink& sink) {
  if (!expect_object(v, path, sink)) return false;
  // Unknown keys are refused inside tables (data_format.md §1).
  for (const auto& m : v.members) {
    if (m.first != "axes" && m.first != "unit" && m.first != "values") {
      return sink.fail(path_key(path, m.first), "unknown key in a table");
    }
  }
  const json::Value* axes_v = member(v, path, "axes", true, sink);
  const json::Value* unit_v = member(v, path, "unit", true, sink);
  const json::Value* values_v = member(v, path, "values", true, sink);
  if (axes_v == nullptr || unit_v == nullptr || values_v == nullptr) return false;

  const std::string axes_path = path_key(path, "axes");
  if (!axes_v->is_array()) return sink.fail(axes_path, "expected an array");
  if (axes_v->items.empty() || axes_v->items.size() > 3) return sink.fail(axes_path, "a table has 1 to 3 axes");
  if (axes_v->items.size() != spec.axes.size()) {
    return sink.fail(axes_path, "expected " + std::to_string(spec.axes.size()) + " axes, found " +
                                    std::to_string(axes_v->items.size()));
  }
  std::vector<Axis> axes;
  std::size_t count = 1;
  for (std::size_t a = 0; a < axes_v->items.size(); ++a) {
    const json::Value& av = axes_v->items[a];
    const std::string ap = path_index(axes_path, a);
    if (!expect_object(av, ap, sink)) return false;
    for (const auto& m : av.members) {
      if (m.first != "q" && m.first != "points") return sink.fail(path_key(ap, m.first), "unknown key in an axis");
    }
    std::string qname;
    if (!read_string(av, ap, "q", qname, sink)) return false;
    Axis axis;
    if (!quantity_from_name(qname, axis.q)) return sink.fail(path_key(ap, "q"), "unknown quantity \"" + qname + "\"");
    if (axis.q != spec.axes[a]) {
      return sink.fail(path_key(ap, "q"), "expected quantity " + std::string(quantity_name(spec.axes[a])) +
                                              ", found " + qname);
    }
    const json::Value* pts = member(av, ap, "points", true, sink);
    if (pts == nullptr) return false;
    const std::string pp = path_key(ap, "points");
    if (!pts->is_array()) return sink.fail(pp, "expected an array");
    axis.points.reserve(pts->items.size());
    for (std::size_t i = 0; i < pts->items.size(); ++i) {
      float f = 0.0f;
      if (!read_float_value(pts->items[i], path_index(pp, i), f, sink)) return false;
      axis.points.push_back(f);
    }
    if (const char* why = check_axis_points(axis.points)) return sink.fail(pp, why);
    const QuantityRange r = quantity_range(axis.q);
    for (std::size_t i = 0; i < axis.points.size(); ++i) {
      if (axis.points[i] < r.lo || axis.points[i] > r.hi) {
        return sink.fail(path_index(pp, i), "point " + fmt_float(axis.points[i]) + " outside the range of " + qname);
      }
    }
    count *= axis.points.size();
    axes.push_back(std::move(axis));
  }

  const std::string up = path_key(path, "unit");
  if (!unit_v->is_string()) return sink.fail(up, "expected a string");
  Unit unit;
  if (!unit_from_name(unit_v->text, unit)) return sink.fail(up, "unknown unit \"" + unit_v->text + "\"");
  if (unit != spec.unit) {
    return sink.fail(up, "expected unit " + std::string(unit_name(spec.unit)) + ", found " + unit_v->text);
  }

  const std::string vp = path_key(path, "values");
  if (!values_v->is_array()) return sink.fail(vp, "expected an array");
  if (values_v->items.size() != count) {
    return sink.fail(vp, "expected " + std::to_string(count) + " values (product of the axis lengths), found " +
                             std::to_string(values_v->items.size()));
  }
  std::vector<float> values;
  values.reserve(count);
  for (std::size_t i = 0; i < count; ++i) {
    float f = 0.0f;
    if (!read_float_value(values_v->items[i], path_index(vp, i), f, sink)) return false;
    if (f < spec.lo || f > spec.hi) {
      return sink.fail(path_index(vp, i), "value " + fmt_float(f) + " outside [" + fmt_float(spec.lo) + ", " +
                                              fmt_float(spec.hi) + "]");
    }
    values.push_back(f);
  }
  out = Table(std::move(axes), unit, std::move(values));
  return true;
}

}  // namespace wm::data
