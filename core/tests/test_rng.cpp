// conventions.md §7 check values and properties.
#include "doctest.h"
#include "math/rng.h"
#include "test_util.h"

TEST_CASE("§7 check values") {
  struct Row {
    std::uint64_t seed, stream, index, u64;
    float unit;
  };
  const Row rows[] = {
      {0, 0, 0, 0x2FF145472E2746D6ull, 0.187275231f},
      {0, 0, 1, 0x7B575A03C5870447ull, 0.481801629f},
      {1, 1, 0, 0xBB1D2681F3984480ull, 0.730913520f},
      {12345, 2, 7, 0xF90F0DD20CC249EBull, 0.972885907f},
      {3735928559ull, 3, 1000, 0x32CD075B64360FC1ull, 0.198440969f},
  };
  for (const Row& r : rows) {
    CAPTURE(r.seed);
    CAPTURE(r.index);
    CHECK(wm::rng_u64(r.seed, r.stream, r.index) == r.u64);
    CHECK(wm::rng_u32(r.seed, r.stream, r.index) == static_cast<std::uint32_t>(r.u64 >> 32));
    CHECK(wm::rng_unit(r.seed, r.stream, r.index) == r.unit);
  }
}

TEST_CASE("rng_unit is in [0, 1) and exact; rng_range maps it") {
  for (std::uint64_t i = 0; i < 100000; ++i) {
    const float u = wm::rng_unit(42, wm::RngStream::wind_shift, i);
    REQUIRE(u >= 0.0f);
    REQUIRE(u < 1.0f);
    // 24-bit grid: u * 2^24 is an integer.
    const float scaled = u * 16777216.0f;
    REQUIRE(scaled == static_cast<float>(static_cast<std::uint32_t>(scaled)));
  }
  const float r = wm::rng_range(2.0f, 4.0f, 7, wm::RngStream::puff_slots, 3);
  CHECK(r >= 2.0f);
  CHECK(r < 4.0f);
  CHECK(r == 2.0f + 2.0f * wm::rng_unit(7, wm::RngStream::puff_slots, 3));
}

TEST_CASE("streams and indices give independent draws") {
  CHECK(wm::rng_u64(1, 1, 0) != wm::rng_u64(1, 2, 0));
  CHECK(wm::rng_u64(1, 1, 0) != wm::rng_u64(1, 1, 1));
  CHECK(wm::rng_u64(1, 1, 0) != wm::rng_u64(2, 1, 0));
}
