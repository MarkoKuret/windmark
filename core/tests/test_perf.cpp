// Performance file loader and validator (data_format.md §4, §5) on the shipped classes, and its refusals.
#include <string>
#include <utility>
#include <vector>

#include "data/json.h"

#include "data/boat_class.h"
#include "data/perf.h"
#include "data/table_reader.h"
#include "doctest.h"

namespace {

const std::string kData = WINDMARK_DATA_DIR;

std::string read(const std::string& file) {
  std::string text;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::data::read_file(file, text, err), err.message());
  return text;
}

// Test-only JSON writer, so the refusal tests edit the parsed tree and do not depend on the file's formatting.
void dump(const wm::json::Value& v, std::string& out) {
  using wm::json::Kind;
  switch (v.kind) {
    case Kind::null: out += "null"; break;
    case Kind::boolean: out += v.boolean ? "true" : "false"; break;
    case Kind::number: out += v.text; break;
    case Kind::string: out += '"' + v.text + '"'; break;  // ids and plain text only
    case Kind::array:
      out += '[';
      for (std::size_t i = 0; i < v.items.size(); ++i) {
        if (i) out += ',';
        dump(v.items[i], out);
      }
      out += ']';
      break;
    case Kind::object:
      out += '{';
      for (std::size_t i = 0; i < v.members.size(); ++i) {
        if (i) out += ',';
        out += '"' + v.members[i].first + "\":";
        dump(v.members[i].second, out);
      }
      out += '}';
      break;
  }
}

std::string dump(const wm::json::Value& v) {
  std::string s;
  dump(v, s);
  return s;
}

wm::json::Value parse_ok(const std::string& text) {
  wm::json::ParseResult r = wm::json::parse(text);
  REQUIRE(r.ok);
  return std::move(r.value);
}

// Member by key (must exist).
wm::json::Value& key(wm::json::Value& v, const std::string& k) {
  for (auto& m : v.members) {
    if (m.first == k) return m.second;
  }
  FAIL("no key " << k);
  return v;
}

wm::json::Value num(const std::string& text) {
  wm::json::Value v;
  v.kind = wm::json::Kind::number;
  v.text = text;
  return v;
}

wm::json::Value str(const std::string& text) {
  wm::json::Value v;
  v.kind = wm::json::Kind::string;
  v.text = text;
  return v;
}

struct Refusal {
  std::string name;
  std::string text;
  std::string path;  // expected JSON path (prefix)
};

void expect_refusals(const std::string& file, const std::vector<Refusal>& cases) {
  for (const Refusal& c : cases) {
    CAPTURE(c.name);
    wm::PerfData perf;
    wm::LoadError err;
    CHECK(!wm::parse_perf(c.text, file, perf, err));
    CHECK(err.file == file);
    CHECK(!err.reason.empty());
    CHECK_MESSAGE(err.path.rfind(c.path, 0) == 0, err.message());
    CHECK(perf.sails.empty());  // nothing partly loaded
  }
}

void check_class(const std::string& id, std::size_t n_sails) {
  const std::string perf_file = kData + "/perf/" + id + ".perf.json";
  const std::string class_file = kData + "/classes/" + id + ".boat.json";
  wm::PerfData perf;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_perf(perf_file, perf, err), err.message());
  CHECK(perf.class_id == id);
  CHECK(perf.sails.size() == n_sails);
  CHECK(perf.configs.size() == n_sails);  // main only + one per front sail
  REQUIRE(perf.main_sail >= 0);
  CHECK(perf.sails[static_cast<std::size_t>(perf.main_sail)].type == wm::SailType::main);
  CHECK(perf.file_sha256.size() == 64);
  CHECK(perf.dynamics.collision.outline.size() >= 6);

  // Every config: lookups give finite values across and beyond the table range.
  for (const wm::ConfigPerf& c : perf.configs) {
    REQUIRE(perf.config_for(c.front_sail) == &c);
    for (float tws = -1.0f; tws < 25.0f; tws += 0.7f) {
      for (float twa = -0.1f; twa < 3.3f; twa += 0.05f) {
        const float v = c.polar.at(tws, twa);
        const float h = c.heel.at(tws, twa);
        REQUIRE(std::isfinite(v));
        REQUIRE(h >= 0.0f);
        if (c.trim_speed.present) REQUIRE(std::isfinite(c.trim_speed.table.at(tws, twa, 0.0f)));
      }
    }
    // The 0 tws row holds 0 (sails.md §6).
    CHECK(c.polar.at(0.0f, 1.5f) == 0.0f);
    // At a stored grid point the lookup returns the stored value exactly.
    const wm::Axis& ax = c.polar.axis(0);
    const wm::Axis& ay = c.polar.axis(1);
    const std::size_t i = ax.points.size() / 2;
    const std::size_t j = ay.points.size() - 3;
    CHECK(c.polar.at(ax.points[i], ay.points[j]) == c.polar.values()[i * ay.points.size() + j]);
  }

  // Generated from the class file in the repository.
  wm::BoatClassInfo cls;
  REQUIRE_MESSAGE(wm::load_boat_class(class_file, cls, err), err.message());
  CHECK(cls.id == id);
  CHECK_MESSAGE(wm::perf_matches_class(perf, cls, err), err.message());
  CHECK(cls.start_front_sail >= 0);
  CHECK(perf.sails[static_cast<std::size_t>(perf.start_front_sail)].id ==
        cls.sails[static_cast<std::size_t>(cls.start_front_sail)].id);
}

}  // namespace

TEST_CASE("wm7 perf file loads and validates") { check_class("wm7", 3); }
TEST_CASE("wm12 perf file loads and validates") { check_class("wm12", 4); }

TEST_CASE("wm7 values read as binary32 of the file's decimals") {
  wm::PerfData perf;
  wm::LoadError err;
  REQUIRE_MESSAGE(wm::load_perf(kData + "/perf/wm7.perf.json", perf, err), err.message());
  const wm::Dynamics& d = perf.dynamics;
  CHECK(d.rudder_max == 0.61f);
  CHECK(d.heel_limit == 1.4f);
  CHECK(d.derived.turn_c == d.turn_radius_full + d.turn_radius_offset);
  CHECK(d.derived.heel_k1 == (d.heel_freq * d.heel_freq) * wm::DT);
  CHECK(perf.find_sail("main") == perf.main_sail);
  const wm::SailPerf& jib = perf.sails[static_cast<std::size_t>(perf.find_sail("jib"))];
  CHECK(jib.has_handling);
  CHECK(!jib.handling.hoist_time.is_table);
  // The no-go edge is a step (two equal breakpoints) on the polar's twa axis.
  const wm::ConfigPerf* cfg = perf.config_for(perf.find_sail("jib"));
  REQUIRE(cfg != nullptr);
  const std::vector<float>& twa = cfg->polar.axis(1).points;
  bool step = false;
  for (std::size_t k = 1; k < twa.size(); ++k) step = step || twa[k] == twa[k - 1];
  CHECK(step);
}

TEST_CASE("the test JSON writer round-trips the shipped file") {
  const std::string file = kData + "/perf/wm7.perf.json";
  wm::PerfData perf;
  wm::LoadError err;
  CHECK_MESSAGE(wm::parse_perf(dump(parse_ok(read(file))), file, perf, err), err.message());
}

TEST_CASE("validator refuses broken performance files with file, path and reason") {
  const std::string file = kData + "/perf/wm7.perf.json";
  const wm::json::Value good = parse_ok(read(file));
  std::vector<Refusal> cases;
  auto add = [&](const std::string& name, const std::string& path, auto edit) {
    wm::json::Value v = good;
    edit(v);
    cases.push_back({name, dump(v), path});
  };
  add("other major version", "$.schema", [](wm::json::Value& v) { key(v, "schema") = str("windmark.perf/2"); });
  add("other schema", "$.schema", [](wm::json::Value& v) { key(v, "schema") = str("windmark.venue/1"); });
  add("missing dynamics key", "$.dynamics.helm_rate", [](wm::json::Value& v) {
    auto& m = key(v, "dynamics").members;
    for (auto it = m.begin(); it != m.end(); ++it) {
      if (it->first == "helm_rate") {
        m.erase(it);
        break;
      }
    }
  });
  add("number as string", "$.dynamics.rudder_max",
      [](wm::json::Value& v) { key(key(v, "dynamics"), "rudder_max") = str("0.61"); });
  add("overflowing number", "$.dynamics.heel_limit",
      [](wm::json::Value& v) { key(key(v, "dynamics"), "heel_limit") = num("1e40"); });
  add("heel limit beyond pi/2", "$.dynamics.heel_limit",
      [](wm::json::Value& v) { key(key(v, "dynamics"), "heel_limit") = num("2.0"); });
  add("heel_k2 < 0", "$.dynamics.heel_damping",
      [](wm::json::Value& v) { key(key(v, "dynamics"), "heel_damping") = num("40"); });
  add("decreasing axis", "$.configs[0].polar.axes[0].points", [](wm::json::Value& v) {
    auto& pts = key(key(v, "configs").items[0], "polar");
    key(pts, "axes").items[0].members[1].second.items[2] = num("1.0");  // 0, 2, 1, ...
  });
  add("three equal points", "$.configs[0].polar.axes[1].points", [](wm::json::Value& v) {
    auto& pts = key(key(key(v, "configs").items[0], "polar"), "axes").items[1];
    auto& p = key(pts, "points").items;
    p[1] = p[2];  // makes a triple with the step at 2, 3
  });
  add("axis beyond pi", "$.configs[0].polar.axes[1].points", [](wm::json::Value& v) {
    auto& p = key(key(key(key(v, "configs").items[0], "polar"), "axes").items[1], "points").items;
    p.back() = num("3.2");
  });
  add("tws axis short of 40 kn", "$.configs[0].heel.axes[0].points", [](wm::json::Value& v) {
    auto& p = key(key(key(key(v, "configs").items[0], "heel"), "axes").items[0], "points").items;
    p.back() = num("18.0");
  });
  add("wrong quantity", "$.configs[0].polar.axes[1].q", [](wm::json::Value& v) {
    key(key(key(key(v, "configs").items[0], "polar"), "axes").items[1], "q") = str("awa_abs");
  });
  add("wrong unit", "$.configs[0].polar.unit",
      [](wm::json::Value& v) { key(key(key(v, "configs").items[0], "polar"), "unit") = str("kn"); });
  add("unknown key in a table", "$.configs[0].polar.extra", [](wm::json::Value& v) {
    key(key(v, "configs").items[0], "polar").members.emplace_back("extra", num("1"));
  });
  add("value count", "$.configs[0].polar.values", [](wm::json::Value& v) {
    key(key(key(v, "configs").items[0], "polar"), "values").items.pop_back();
  });
  add("polar value out of range", "$.configs[1].polar.values[3]", [](wm::json::Value& v) {
    key(key(key(v, "configs").items[1], "polar"), "values").items[3] = num("41");
  });
  add("trim factor out of range", "$.configs[0].trim_speed.values[0]", [](wm::json::Value& v) {
    key(key(key(v, "configs").items[0], "trim_speed"), "values").items[0] = num("-0.1");
  });
  add("unknown sail type", "$.sails.jib.type",
      [](wm::json::Value& v) { key(key(key(v, "sails"), "jib"), "type") = str("staysail"); });
  add("front sail without handling", "$.sails.jib.handling", [](wm::json::Value& v) {
    auto& m = key(key(v, "sails"), "jib").members;
    for (auto it = m.begin(); it != m.end(); ++it) {
      if (it->first == "handling") {
        m.erase(it);
        break;
      }
    }
  });
  add("negative duration", "$.sails.jib.handling.hoist_time", [](wm::json::Value& v) {
    key(key(key(key(v, "sails"), "jib"), "handling"), "hoist_time") = num("-1");
  });
  add("second config for a sail", "$.configs[2].front_sail",
      [](wm::json::Value& v) { key(key(v, "configs").items[2], "front_sail") = str("jib"); });
  add("missing config", "$.configs", [](wm::json::Value& v) { key(v, "configs").items.pop_back(); });
  add("extra optimal angle", "$.configs[0].optimal_angle", [](wm::json::Value& v) {
    auto& oa = key(key(v, "configs").items[0], "optimal_angle");
    oa.members.emplace_back("jib", oa.members[0].second);
  });
  add("bad class hash", "$.class_sha256", [](wm::json::Value& v) { key(v, "class_sha256") = str("xyz"); });
  add("clockwise outline", "$.dynamics.collision.outline", [](wm::json::Value& v) {
    auto& o = key(key(key(v, "dynamics"), "collision"), "outline").items;
    std::vector<wm::json::Value> rev(o.rbegin(), o.rend());
    o = rev;
  });
  add("outline off the origin", "$.dynamics.collision.outline", [](wm::json::Value& v) {
    for (auto& p : key(key(key(v, "dynamics"), "collision"), "outline").items) {
      float x = 0;
      REQUIRE(wm::json::to_float(p.items[0], x));
      p.items[0] = num(std::to_string(x + 100.0f));
    }
  });
  add("missing wind shadow key", "$.dynamics.wind_shadow.header_max", [](wm::json::Value& v) {
    auto& m = key(key(v, "dynamics"), "wind_shadow").members;
    m.pop_back();
  });
  add("turn radius law without a positive turn_c", "$.dynamics.turn_radius_offset", [](wm::json::Value& v) {
    float r = 0;
    REQUIRE(wm::json::to_float(key(key(v, "dynamics"), "turn_radius_full"), r));
    key(key(v, "dynamics"), "turn_radius_offset") = num(std::to_string(-r));
  });
  add("more than 64 hull points", "$.dynamics.hull_points", [](wm::json::Value& v) {
    auto& hp = key(key(v, "dynamics"), "hull_points").items;
    const wm::json::Value first = hp[0];
    while (hp.size() <= 64) hp.push_back(first);
  });
  add("start sail unknown", "$.start.front_sail",
      [](wm::json::Value& v) { key(key(v, "start"), "front_sail") = str("genoa"); });
  cases.push_back({"not JSON", "{\"schema\":", ""});
  expect_refusals(file, cases);
}

TEST_CASE("class check reports a changed class file") {
  const std::string file = kData + "/perf/wm12.perf.json";
  wm::PerfData perf;
  wm::LoadError err;
  REQUIRE(wm::load_perf(file, perf, err));
  wm::BoatClassInfo cls;
  REQUIRE(wm::load_boat_class(kData + "/classes/wm12.boat.json", cls, err));
  cls.sha256[0] = cls.sha256[0] == '0' ? '1' : '0';
  CHECK(!wm::perf_matches_class(perf, cls, err));
  CHECK(err.path == "$.class_sha256");
  cls.version = 2;
  CHECK(!wm::perf_matches_class(perf, cls, err));
  CHECK(err.path == "$.class_version");
}
