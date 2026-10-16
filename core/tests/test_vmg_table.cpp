// The per-class VMG table (rules.md §3.7): equal to the full polar scan bit for bit over a fine wind sweep and
// on both sides of every change of winner, in particular where the best sail config switches.
#include <bit>
#include <cmath>
#include <cstdint>
#include <string>

#include "boat_harness.h"
#include "data/perf.h"
#include "data/vmg_table.h"
#include "doctest.h"

namespace {

bool same(const wm::PolarVmg& a, const wm::PolarVmg& b) {
  return std::bit_cast<std::uint32_t>(a.up_speed) == std::bit_cast<std::uint32_t>(b.up_speed) &&
         std::bit_cast<std::uint32_t>(a.up_twa) == std::bit_cast<std::uint32_t>(b.up_twa) &&
         std::bit_cast<std::uint32_t>(a.down_speed) == std::bit_cast<std::uint32_t>(b.down_speed) &&
         std::bit_cast<std::uint32_t>(a.down_twa) == std::bit_cast<std::uint32_t>(b.down_twa);
}

float prev_float(float x) { return std::bit_cast<float>(std::bit_cast<std::uint32_t>(x) - 1); }

}  // namespace

TEST_CASE("vmg table: equal to the full scan over a fine wind sweep") {
  for (const std::string cls : {"wm7", "wm12"}) {
    const wm::PerfData& p = wm_test::perf(cls);
    REQUIRE(!p.vmg.empty());
    MESSAGE(cls, ": ", p.vmg.up.segs.size(), " up and ", p.vmg.down.segs.size(), " down segments, ", p.vmg.up.cands.size() + p.vmg.down.cands.size(), " candidates, ", p.vmg.bytes(), " bytes");
    float max_d_angle = 0.0f, max_d_speed = 0.0f;
    std::int32_t mismatches = 0;
    for (std::int32_t i = -100; i <= 24000; ++i) {  // -0.1 to 24 m/s every 1 mm/s, past the polars' top wind
      const float tws = static_cast<float>(i) * 0.001f;
      const wm::PolarVmg t = wm::polar_vmg(p, tws), s = wm::polar_vmg_scan(p, tws);
      if (!same(t, s)) ++mismatches;
      max_d_angle = wm::max(max_d_angle, wm::max(std::fabs(t.up_twa - s.up_twa), std::fabs(t.down_twa - s.down_twa)));
      max_d_speed =
          wm::max(max_d_speed, wm::max(std::fabs(t.up_speed - s.up_speed), std::fabs(t.down_speed - s.down_speed)));
    }
    // Odd floats too: every 1021st binary32 from 0.5 to 21 m/s.
    for (std::uint32_t b = std::bit_cast<std::uint32_t>(0.5f); b < std::bit_cast<std::uint32_t>(21.0f); b += 1021) {
      const float tws = std::bit_cast<float>(b);
      if (!same(wm::polar_vmg(p, tws), wm::polar_vmg_scan(p, tws))) ++mismatches;
    }
    MESSAGE(cls, ": max |angle difference| ", max_d_angle, " rad, max |speed difference| ", max_d_speed, " m/s");
    CHECK(mismatches == 0);
    CHECK(same(wm::polar_vmg(p, 1000.0f), wm::polar_vmg_scan(p, 1000.0f)));
    CHECK(same(wm::polar_vmg(p, std::nanf("")), wm::polar_vmg_scan(p, std::nanf(""))));
    // No wind, no VMG: the rules fall back to their fixed angles.
    CHECK(wm::polar_vmg(p, 0.0f).up_twa == 0.0f);
  }
}

TEST_CASE("vmg table: exact on both sides of every switch, including the best config's") {
  for (const std::string cls : {"wm7", "wm12"}) {
    const wm::PerfData& p = wm_test::perf(cls);
    std::int32_t jumps = 0;
    for (const wm::VmgTable::Side* side : {&p.vmg.up, &p.vmg.down}) {
      const bool up = side == &p.vmg.up;
      for (std::size_t i = 1; i < side->segs.size(); ++i) {
        const float x = side->segs[i].from, xm = prev_float(x);
        CHECK(side->segs[i - 1].from < x);
        const wm::PolarVmg lo = wm::polar_vmg(p, xm), hi = wm::polar_vmg(p, x);
        CHECK(same(lo, wm::polar_vmg_scan(p, xm)));
        CHECK(same(hi, wm::polar_vmg_scan(p, x)));
        const float a_lo = up ? lo.up_twa : lo.down_twa, a_hi = up ? hi.up_twa : hi.down_twa;
        if (std::fabs(a_hi - a_lo) > wm_test::deg(1.0f)) {
          // A jump of more than one grid step: the best config switches (or the best angle of one config jumps
          // across a dip in its polar). One float below it the lookup has the old angle, at it the new one, never
          // a blend of the two; halfway across the table cells on either side it is still the scan's answer.
          ++jumps;
          MESSAGE(cls, (up ? " up" : " down"), ": angle ", a_lo * (180.0f / wm::PI), " -> ", a_hi * (180.0f / wm::PI),
                  " deg at ", x, " m/s");
          for (const float d : {-0.5f, 0.5f}) {
            const float y = x + d * wm::VmgTable::STEP;
            CHECK(same(wm::polar_vmg(p, y), wm::polar_vmg_scan(p, y)));
          }
        }
      }
    }
    MESSAGE(cls, ": ", jumps, " angle jumps");
    CHECK(jumps > 0);
  }
}
