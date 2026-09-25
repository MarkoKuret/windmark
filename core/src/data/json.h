// A small strict JSON reader (RFC 8259) for the data files (data_format.md §1). Numbers keep their source text
// and are converted on request: to binary32 with correct rounding (conventions.md §5 rule 13) or to an integer.
// Object members keep document order; duplicate keys are an error.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace wm::json {

enum class Kind : std::uint8_t { null, boolean, number, string, array, object };

struct Value {
  Kind kind = Kind::null;
  bool boolean = false;
  std::string text;  // string contents (unescaped), or the number's source text
  std::vector<Value> items;
  std::vector<std::pair<std::string, Value>> members;

  bool is_null() const { return kind == Kind::null; }
  bool is_bool() const { return kind == Kind::boolean; }
  bool is_number() const { return kind == Kind::number; }
  bool is_string() const { return kind == Kind::string; }
  bool is_array() const { return kind == Kind::array; }
  bool is_object() const { return kind == Kind::object; }

  const Value* find(std::string_view key) const;  // objects only; nullptr if absent
};

std::string_view kind_name(Kind k);

// Number conversions. to_float: correctly rounded binary32; false if the value overflows binary32 (a finite
// decimal can never be NaN). to_int64: false unless the text is an integer (no fraction or exponent) in range.
bool to_float(const Value& v, float& out);
bool to_int64(const Value& v, std::int64_t& out);

// Correctly rounded decimal -> binary32 of a JSON number's text. Exposed for tests.
bool parse_float(std::string_view text, float& out);

struct ParseResult {
  bool ok = false;
  Value value;
  std::string error;  // "line L, column C: reason"
};

ParseResult parse(std::string_view text);

}  // namespace wm::json
