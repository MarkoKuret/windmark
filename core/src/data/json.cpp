#include "data/json.h"

#include <charconv>
#include <cstdlib>
#include <cmath>
#include <system_error>

namespace wm::json {

const Value* Value::find(std::string_view key) const {
  for (const auto& m : members) {
    if (m.first == key) return &m.second;
  }
  return nullptr;
}

std::string_view kind_name(Kind k) {
  switch (k) {
    case Kind::null: return "null";
    case Kind::boolean: return "a boolean";
    case Kind::number: return "a number";
    case Kind::string: return "a string";
    case Kind::array: return "an array";
    case Kind::object: return "an object";
  }
  return "?";
}

bool parse_float(std::string_view text, float& out) {
  // std::from_chars is locale independent and correctly rounded (round to nearest even).
  const char* first = text.data();
  const char* last = first + text.size();
  float v = 0.0f;
  const std::from_chars_result r = std::from_chars(first, last, v, std::chars_format::general);
  if (r.ptr != last) return false;
  if (r.ec == std::errc::result_out_of_range) {
    // Overflow is an error. Underflow is not: a tiny decimal rounds to a denormal or to zero, and some
    // libraries report that as out of range without storing the value. strtof rounds correctly on the
    // supported platforms; it is only reached for magnitudes below 2^-126, which real data never has.
    const std::string s(text);
    const float f = std::strtof(s.c_str(), nullptr);
    if (!(std::fabs(f) < 1.0f)) return false;
    out = f;
    return true;
  }
  if (r.ec != std::errc()) return false;
  if (!std::isfinite(v)) return false;
  out = v;
  return true;
}

bool to_float(const Value& v, float& out) { return v.is_number() && parse_float(v.text, out); }

bool to_int64(const Value& v, std::int64_t& out) {
  if (!v.is_number()) return false;
  for (char c : v.text) {
    if (c == '.' || c == 'e' || c == 'E') return false;
  }
  const char* first = v.text.data();
  const char* last = first + v.text.size();
  std::int64_t i = 0;
  const std::from_chars_result r = std::from_chars(first, last, i);
  if (r.ec != std::errc() || r.ptr != last) return false;
  out = i;
  return true;
}

namespace {

constexpr int kMaxDepth = 64;

class Parser {
 public:
  explicit Parser(std::string_view text) : s_(text) {}

  ParseResult run() {
    ParseResult res;
    // A UTF-8 byte order mark is tolerated.
    if (s_.size() >= 3 && static_cast<unsigned char>(s_[0]) == 0xEF && static_cast<unsigned char>(s_[1]) == 0xBB &&
        static_cast<unsigned char>(s_[2]) == 0xBF) {
      pos_ = 3;
    }
    skip_ws();
    if (!value(res.value, 0)) {
      res.error = error_;
      return res;
    }
    skip_ws();
    if (pos_ != s_.size()) {
      fail("unexpected text after the top-level value");
      res.error = error_;
      return res;
    }
    res.ok = true;
    return res;
  }

 private:
  std::string_view s_;
  std::size_t pos_ = 0;
  std::string error_;

  bool fail(std::string_view reason) {
    if (!error_.empty()) return false;
    std::size_t line = 1;
    std::size_t col = 1;
    for (std::size_t i = 0; i < pos_ && i < s_.size(); ++i) {
      if (s_[i] == '\n') {
        ++line;
        col = 1;
      } else {
        ++col;
      }
    }
    error_ = "line " + std::to_string(line) + ", column " + std::to_string(col) + ": " + std::string(reason);
    return false;
  }

  bool at_end() const { return pos_ >= s_.size(); }
  char peek() const { return at_end() ? '\0' : s_[pos_]; }

  void skip_ws() {
    while (!at_end()) {
      const char c = s_[pos_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        ++pos_;
      } else {
        break;
      }
    }
  }

  bool literal(std::string_view word) {
    if (s_.substr(pos_, word.size()) != word) return fail("invalid literal");
    pos_ += word.size();
    return true;
  }

  bool value(Value& out, int depth) {
    if (depth > kMaxDepth) return fail("nesting too deep");
    if (at_end()) return fail("unexpected end of input");
    const char c = peek();
    switch (c) {
      case '{': return object(out, depth);
      case '[': return array(out, depth);
      case '"':
        out.kind = Kind::string;
        return string(out.text);
      case 't':
        out.kind = Kind::boolean;
        out.boolean = true;
        return literal("true");
      case 'f':
        out.kind = Kind::boolean;
        out.boolean = false;
        return literal("false");
      case 'n':
        out.kind = Kind::null;
        return literal("null");
      default:
        if (c == '-' || (c >= '0' && c <= '9')) return number(out);
        return fail("unexpected character");
    }
  }

  static bool is_digit(char c) { return c >= '0' && c <= '9'; }

  bool number(Value& out) {
    const std::size_t start = pos_;
    if (peek() == '-') ++pos_;
    if (peek() == '0') {
      ++pos_;
    } else if (is_digit(peek())) {
      while (is_digit(peek())) ++pos_;
    } else {
      return fail("invalid number");
    }
    if (peek() == '.') {
      ++pos_;
      if (!is_digit(peek())) return fail("invalid number: digit expected after '.'");
      while (is_digit(peek())) ++pos_;
    }
    if (peek() == 'e' || peek() == 'E') {
      ++pos_;
      if (peek() == '+' || peek() == '-') ++pos_;
      if (!is_digit(peek())) return fail("invalid number: digit expected in exponent");
      while (is_digit(peek())) ++pos_;
    }
    out.kind = Kind::number;
    out.text.assign(s_.substr(start, pos_ - start));
    return true;
  }

  bool hex4(std::uint32_t& cp) {
    if (pos_ + 4 > s_.size()) return fail("truncated \\u escape");
    cp = 0;
    for (int i = 0; i < 4; ++i) {
      const char c = s_[pos_++];
      cp <<= 4;
      if (c >= '0' && c <= '9') {
        cp |= static_cast<std::uint32_t>(c - '0');
      } else if (c >= 'a' && c <= 'f') {
        cp |= static_cast<std::uint32_t>(c - 'a' + 10);
      } else if (c >= 'A' && c <= 'F') {
        cp |= static_cast<std::uint32_t>(c - 'A' + 10);
      } else {
        return fail("invalid \\u escape");
      }
    }
    return true;
  }

  static void put_utf8(std::string& out, std::uint32_t cp) {
    if (cp < 0x80) {
      out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
      out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
      out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
      out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
  }

  bool string(std::string& out) {
    ++pos_;  // opening quote
    out.clear();
    while (true) {
      if (at_end()) return fail("unterminated string");
      const char c = s_[pos_];
      if (c == '"') {
        ++pos_;
        return true;
      }
      if (static_cast<unsigned char>(c) < 0x20) return fail("control character in string");
      if (c != '\\') {
        out.push_back(c);
        ++pos_;
        continue;
      }
      ++pos_;
      if (at_end()) return fail("unterminated escape");
      const char e = s_[pos_++];
      switch (e) {
        case '"': out.push_back('"'); break;
        case '\\': out.push_back('\\'); break;
        case '/': out.push_back('/'); break;
        case 'b': out.push_back('\b'); break;
        case 'f': out.push_back('\f'); break;
        case 'n': out.push_back('\n'); break;
        case 'r': out.push_back('\r'); break;
        case 't': out.push_back('\t'); break;
        case 'u': {
          std::uint32_t cp = 0;
          if (!hex4(cp)) return false;
          if (cp >= 0xD800 && cp <= 0xDBFF) {
            if (s_.substr(pos_, 2) != "\\u") return fail("unpaired surrogate");
            pos_ += 2;
            std::uint32_t lo = 0;
            if (!hex4(lo)) return false;
            if (lo < 0xDC00 || lo > 0xDFFF) return fail("unpaired surrogate");
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
            return fail("unpaired surrogate");
          }
          put_utf8(out, cp);
          break;
        }
        default: return fail("invalid escape");
      }
    }
  }

  bool array(Value& out, int depth) {
    ++pos_;
    out.kind = Kind::array;
    skip_ws();
    if (peek() == ']') {
      ++pos_;
      return true;
    }
    while (true) {
      skip_ws();
      out.items.emplace_back();
      if (!value(out.items.back(), depth + 1)) return false;
      skip_ws();
      if (peek() == ',') {
        ++pos_;
        continue;
      }
      if (peek() == ']') {
        ++pos_;
        return true;
      }
      return fail("',' or ']' expected");
    }
  }

  bool object(Value& out, int depth) {
    ++pos_;
    out.kind = Kind::object;
    skip_ws();
    if (peek() == '}') {
      ++pos_;
      return true;
    }
    while (true) {
      skip_ws();
      if (peek() != '"') return fail("object key expected");
      std::string key;
      if (!string(key)) return false;
      if (out.find(key) != nullptr) return fail("duplicate key \"" + key + "\"");
      skip_ws();
      if (peek() != ':') return fail("':' expected");
      ++pos_;
      skip_ws();
      out.members.emplace_back(std::move(key), Value{});
      if (!value(out.members.back().second, depth + 1)) return false;
      skip_ws();
      if (peek() == ',') {
        ++pos_;
        continue;
      }
      if (peek() == '}') {
        ++pos_;
        return true;
      }
      return fail("',' or '}' expected");
    }
  }
};

}  // namespace

ParseResult parse(std::string_view text) { return Parser(text).run(); }

}  // namespace wm::json
