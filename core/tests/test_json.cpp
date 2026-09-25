// JSON reader: strict grammar, document order, numbers correctly rounded to binary32 (conventions.md §5 rule 13).
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "data/json.h"
#include "doctest.h"
#include "math/rng.h"
#include "test_util.h"

using wm_test::bits;

TEST_CASE("parses values in document order") {
  const auto r = wm::json::parse(R"( {"b": [1, -2.5e3, true, null], "a": {"s": "x\u00e9\n\ud83d\ude00"}} )");
  REQUIRE(r.ok);
  REQUIRE(r.value.is_object());
  CHECK(r.value.members[0].first == "b");
  CHECK(r.value.members[1].first == "a");
  const auto* b = r.value.find("b");
  REQUIRE(b != nullptr);
  REQUIRE(b->items.size() == 4);
  float f = 0;
  CHECK(wm::json::to_float(b->items[1], f));
  CHECK(f == -2500.0f);
  std::int64_t i = 0;
  CHECK(wm::json::to_int64(b->items[0], i));
  CHECK(i == 1);
  CHECK(!wm::json::to_int64(b->items[1], i));
  CHECK(b->items[2].boolean);
  CHECK(b->items[3].is_null());
  CHECK(r.value.find("a")->find("s")->text == "x\xC3\xA9\n\xF0\x9F\x98\x80");
}

TEST_CASE("rejects invalid JSON with a position") {
  const char* bad[] = {
      "",          "{",          "[1,]",      "{\"a\":1,}", "{\"a\" 1}", "01",       "1.",     ".5",
      "+1",        "NaN",        "Infinity",  "[1] 2",      "\"a",       "\"\\x\"",  "{\"a\":1,\"a\":2}",
      "\"\t\"",    "[tru]",      "\"\\ud800\"",
  };
  for (const char* s : bad) {
    CAPTURE(s);
    const auto r = wm::json::parse(s);
    CHECK(!r.ok);
    CHECK(r.error.find("line ") == 0);
  }
}

TEST_CASE("numbers round correctly to binary32") {
  float f = 0;
  CHECK(wm::json::parse_float("0.1", f));
  CHECK(bits(f) == 0x3DCCCCCDu);
  CHECK(wm::json::parse_float("3.14159265", f));
  CHECK(bits(f) == 0x40490FDBu);
  CHECK(wm::json::parse_float("-0", f));
  CHECK((f == 0.0f && std::signbit(f)));
  CHECK(wm::json::parse_float("1e-50", f));  // underflow rounds to zero
  CHECK(f == 0.0f);
  CHECK(wm::json::parse_float("1.4e-45", f));  // smallest denormal
  CHECK(bits(f) == 0x00000001u);
  CHECK(!wm::json::parse_float("1e39", f));  // overflow
  // Halfway between 1 and the next float (1 + 2^-24): ties to even -> 1; just above -> next float.
  CHECK(wm::json::parse_float("1.000000059604644775390625", f));
  CHECK(bits(f) == 0x3F800000u);
  CHECK(wm::json::parse_float("1.000000059604644775390626", f));
  CHECK(bits(f) == 0x3F800001u);
  // Agrees with the C library's correctly rounded strtof on many 9-digit decimals.
  int mismatches = 0;
  for (std::uint64_t i = 0; i < 20000; ++i) {
    char buf[64];
    const float mant = wm::rng_unit(99, 40, i);
    const int exp10 = static_cast<int>(wm::rng_u32(99, 41, i) % 20) - 10;
    std::snprintf(buf, sizeof buf, "%.8e", static_cast<double>(mant) * std::pow(10.0, exp10) * 7.3);
    float a = 0;
    REQUIRE(wm::json::parse_float(buf, a));
    const float b = std::strtof(buf, nullptr);
    if (bits(a) != bits(b)) ++mismatches;
  }
  CHECK(mismatches == 0);
}
