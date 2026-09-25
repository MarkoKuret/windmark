// Field and table readers shared by the data loaders: typed access with a JSON path in every error, and the
// table encoding of data_format.md §5.
#pragma once

#include <cstdint>
#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

#include "data/json.h"
#include "data/load_error.h"
#include "math/wm_math.h"
#include "table/table.h"

namespace wm::data {

// What a table must look like: its axis quantities in order, its value unit and the allowed value range.
struct TableSpec {
  std::vector<Quantity> axes;
  Unit unit;
  float lo;  // inclusive; -INFINITY for none
  float hi;  // inclusive; +INFINITY for none
};

// Every table in the files is 1..3 axes with the §5 rules; this reads and validates one against its spec.
bool read_table(const json::Value& v, const std::string& path, const TableSpec& spec, Table& out, ErrorSink& sink);

// Object member access. `required` false: absent is fine (returns false, no error); present but wrong is an error.
const json::Value* member(const json::Value& obj, const std::string& path, std::string_view key, bool required,
                          ErrorSink& sink);
bool read_float(const json::Value& obj, const std::string& path, std::string_view key, float& out, ErrorSink& sink);
bool read_float_value(const json::Value& v, const std::string& path, float& out, ErrorSink& sink);
bool read_bool(const json::Value& obj, const std::string& path, std::string_view key, bool& out, ErrorSink& sink);
bool read_string(const json::Value& obj, const std::string& path, std::string_view key, std::string& out,
                 ErrorSink& sink);
bool read_int(const json::Value& obj, const std::string& path, std::string_view key, std::int64_t& out,
              ErrorSink& sink);
bool expect_object(const json::Value& v, const std::string& path, ErrorSink& sink);
// A list of [x, y] pairs.
bool read_points(const json::Value& v, const std::string& path, std::vector<Vec2>& out, ErrorSink& sink);

// data_format.md §1: ids are lowercase ASCII [a-z0-9_], non-empty.
bool is_valid_id(std::string_view id);

// Reads the whole file; false with a LoadError on failure.
bool read_file(const std::string& file, std::string& out, LoadError& err);

// Checks the "schema" string: "<name>/<major>", refusing a different major version (data_format.md §1).
bool check_schema(const json::Value& root, std::string_view name, int major, ErrorSink& sink);

}  // namespace wm::data
