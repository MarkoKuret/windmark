// Best VMG up and down a class's polar (rules.md §3.7, race.md §7.2, courses.md §6.3): the scan over every sail
// config at 361 true wind angles, and the per-class table built from it at load that the core asks every tick.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace wm {

struct PerfData;

// Best VMG up and down over every sail config. Angles in rad.
struct PolarVmg {
  float up_speed = 0.0f, up_twa = 0.0f;      // vmg > 0
  float down_speed = 0.0f, down_twa = 0.0f;  // vmg toward downwind, > 0
};

// rules.md §3.7: the scan's answer as a staircase in the true wind speed. For each side, segments start at `from`
// (ascending; the first at 1e-20 m/s, below which, in a calm, the lookup runs the scan): the first binary32 wind
// speed where the scan's winner (a config and one of the 361 angles) changes, found by bisection over the float bits
// when the table is built. Each segment keeps its winner and every other config and angle whose VMG comes within
// 1e-5 of it anywhere in the segment (a near tie, where rounding may pick either): a lookup takes the best of those
// few in the scan's order, so it returns the scan's answer bit for bit. `cell` indexes the segments every STEP m/s
// so a lookup is a few steps, not a search.
struct VmgTable {
  static constexpr float STEP = 0.05f;  // m/s
  struct Cand {
    std::int16_t cfg = 0;  // index into PerfData::configs
    std::int16_t k = 0;    // angle k * pi / 360
  };
  struct Seg {
    float from = 0.0f;         // m/s
    std::uint16_t first = 0;   // into cands
    std::uint16_t count = 0;   // 0: no positive VMG
  };
  struct Side {
    std::vector<Seg> segs;
    std::vector<Cand> cands;           // in the scan's order within a segment
    std::vector<std::uint16_t> cell;   // last segment with from <= c * STEP
  };
  Side up, down;
  bool empty() const { return up.segs.empty(); }
  std::size_t bytes() const;
};

// The full scan (every config, 361 angles 0 to pi in half degrees, the first strict maximum in config order then
// angle order): the reference the table is built from.
PolarVmg polar_vmg_scan(const PerfData& perf, float tws);
// Builds `out` from the configs' polars (parse_perf calls it once the file is valid).
void build_vmg_table(const PerfData& perf, VmgTable& out);
// The table lookup, equal to polar_vmg_scan bit for bit; falls back to the scan for a PerfData without a table.
PolarVmg polar_vmg(const PerfData& perf, float tws);

}  // namespace wm
