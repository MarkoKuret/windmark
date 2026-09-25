#include "data/boat_class.h"

#include <span>

#include "data/json.h"
#include "data/table_reader.h"
#include "state/sha256.h"

namespace wm {

bool parse_boat_class(std::string_view text, std::string_view file, BoatClassInfo& out, LoadError& err) {
  out = BoatClassInfo{};
  err = LoadError{};
  ErrorSink sink(err, file);
  const json::ParseResult pr = json::parse(text);
  if (!pr.ok) return sink.fail("", "JSON: " + pr.error);
  const json::Value& root = pr.value;
  if (!data::check_schema(root, "windmark.boatclass", 1, sink)) return false;
  if (!data::read_string(root, "$", "id", out.id, sink)) return false;
  if (!data::is_valid_id(out.id)) return sink.fail("$.id", "ids are lowercase [a-z0-9_]");
  if (!data::read_string(root, "$", "name", out.name, sink)) return false;
  if (!data::read_int(root, "$", "version", out.version, sink)) return false;
  if (out.version < 1) return sink.fail("$.version", "must be >= 1");

  const json::Value* sv = data::member(root, "$", "sails", true, sink);
  if (sv == nullptr) return false;
  if (!sv->is_array()) return sink.fail("$.sails", "expected an array");
  std::int32_t mains = 0;
  for (std::size_t i = 0; i < sv->items.size(); ++i) {
    const json::Value& s = sv->items[i];
    const std::string p = path_index("$.sails", i);
    if (!data::expect_object(s, p, sink)) return false;
    BoatClassSail sail;
    std::string type;
    if (!data::read_string(s, p, "id", sail.id, sink)) return false;
    if (!data::is_valid_id(sail.id)) return sink.fail(p + ".id", "ids are lowercase [a-z0-9_]");
    for (const BoatClassSail& other : out.sails) {
      if (other.id == sail.id) return sink.fail(p + ".id", "duplicate sail id \"" + sail.id + "\"");
    }
    if (!data::read_string(s, p, "type", type, sink)) return false;
    if (!sail_type_from_name(type, sail.type)) return sink.fail(p + ".type", "unknown sail type \"" + type + "\"");
    if (!data::read_float(s, p, "area", sail.area, sink)) return false;
    if (!(sail.area > 0.0f)) return sink.fail(p + ".area", "must be > 0");
    if (sail.type == SailType::main) ++mains;
    out.sails.push_back(std::move(sail));
  }
  if (mains != 1) return sink.fail("$.sails", "exactly one sail of type main");

  if (const json::Value* st = root.find("start")) {
    if (!data::expect_object(*st, "$.start", sink)) return false;
    const json::Value* fs = st->find("front_sail");
    if (fs != nullptr && !fs->is_null()) {
      if (!fs->is_string()) return sink.fail("$.start.front_sail", "expected a sail id or null");
      for (std::size_t i = 0; i < out.sails.size(); ++i) {
        if (out.sails[i].id == fs->text && out.sails[i].type != SailType::main) {
          out.start_front_sail = static_cast<std::int32_t>(i);
        }
      }
      if (out.start_front_sail < 0) return sink.fail("$.start.front_sail", "not a front sail: \"" + fs->text + "\"");
    }
  }

  const auto* bytes = reinterpret_cast<const std::uint8_t*>(text.data());
  out.sha256 = to_hex(sha256(std::span<const std::uint8_t>(bytes, text.size())));
  return true;
}

bool load_boat_class(const std::string& file, BoatClassInfo& out, LoadError& err) {
  std::string text;
  if (!data::read_file(file, text, err)) return false;
  return parse_boat_class(text, file, out, err);
}

bool perf_matches_class(const PerfData& perf, const BoatClassInfo& cls, LoadError& err) {
  err = LoadError{};
  ErrorSink sink(err, "");
  if (perf.class_id != cls.id) return sink.fail("$.class_id", "perf file is for class \"" + perf.class_id + "\"");
  if (perf.class_version != cls.version) {
    return sink.fail("$.class_version", "perf file is for version " + std::to_string(perf.class_version) +
                                            ", class file is version " + std::to_string(cls.version));
  }
  if (perf.class_sha256 != cls.sha256) return sink.fail("$.class_sha256", "class file changed since generation");
  if (perf.sails.size() != cls.sails.size()) return sink.fail("$.sails", "different number of sails");
  for (const BoatClassSail& s : cls.sails) {
    const std::int32_t i = perf.find_sail(s.id);
    if (i < 0) return sink.fail(path_key("$.sails", s.id), "sail missing from the perf file");
    if (perf.sails[static_cast<std::size_t>(i)].type != s.type) {
      return sink.fail(path_key("$.sails", s.id), "sail type differs from the class file");
    }
  }
  return true;
}

}  // namespace wm
