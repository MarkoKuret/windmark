#include "data/vmg_table.h"

#include <algorithm>
#include <array>
#include <bit>
#include <span>

#include "data/perf.h"
#include "math/wm_math.h"

namespace wm {

namespace {

constexpr std::size_t N_ANGLES = 361;
constexpr float NEAR_TIE = 1e-5f;  // relative VMG gap of the candidates kept beside a segment's winner
// Below this the polar speeds are subnormal floats, whose rounding is not monotone in the wind speed: the lookup
// runs the scan there (in practice only for a calm, TWS = 0).
constexpr float TINY = 1e-20f;  // m/s

// The 361 true wind angles of the search, 0 to pi in half degrees, and their cosines.
struct VmgGrid {
  std::array<float, N_ANGLES> twa;
  std::array<float, N_ANGLES> cos;
  VmgGrid() {
    for (std::int32_t i = 0; i <= 360; ++i) {
      twa[static_cast<std::size_t>(i)] = static_cast<float>(i) * (PI / 360.0f);
      cos[static_cast<std::size_t>(i)] = wm_cos(twa[static_cast<std::size_t>(i)]);
    }
  }
};

const VmgGrid& vmg_grid() {
  static const VmgGrid g;
  return g;
}

// The search over the 361 angles for one configuration's speeds.
void vmg_scan(const VmgGrid& g, const std::array<float, N_ANGLES>& speed, PolarVmg& r) {
  for (std::size_t i = 0; i < N_ANGLES; ++i) {
    const float twa = g.twa[i];
    const float v = speed[i];
    const float c = g.cos[i];
    const float up = v * c, down = -(v * c);
    if (up > r.up_speed) {
      r.up_speed = up;
      r.up_twa = twa;
    }
    if (down > r.down_speed) {
      r.down_speed = down;
      r.down_twa = twa;
    }
  }
}

// One side's VMG of a config and angle, as the scan computes it.
float side_vmg(float v, float c, bool up) { return up ? v * c : -(v * c); }

// The scan with the polar rows along the grid interpolated once (Table::at_each_rows gives the bits of at_each):
// every candidate's VMG at a wind speed, and the scan's winner (index cfg * 361 + k, -1: none).
class Scanner {
 public:
  explicit Scanner(const PerfData& perf) : perf_(perf), rows_(perf.configs.size()) {
    for (std::size_t c = 0; c < perf.configs.size(); ++c) perf.configs[c].polar.rows_at_each(vmg_grid().twa, rows_[c]);
  }
  std::size_t size() const { return perf_.configs.size() * N_ANGLES; }
  void values(float tws, bool up, std::vector<float>& out) const {
    const VmgGrid& g = vmg_grid();
    out.resize(size());
    std::array<float, N_ANGLES> speed;
    for (std::size_t c = 0; c < perf_.configs.size(); ++c) {
      perf_.configs[c].polar.at_each_rows(tws, rows_[c], speed);
      for (std::size_t i = 0; i < N_ANGLES; ++i) out[c * N_ANGLES + i] = side_vmg(speed[i], g.cos[i], up);
    }
  }
  std::int32_t winner(float tws, bool up) const {
    values(tws, up, buf_);
    float best = 0.0f;
    std::int32_t w = -1;
    for (std::size_t j = 0; j < buf_.size(); ++j) {
      if (buf_[j] > best) {
        best = buf_[j];
        w = static_cast<std::int32_t>(j);
      }
    }
    return w;
  }

 private:
  const PerfData& perf_;
  std::vector<std::vector<float>> rows_;
  mutable std::vector<float> buf_;
};

float from_bits(std::uint32_t b) { return std::bit_cast<float>(b); }
std::uint32_t bits(float x) { return std::bit_cast<std::uint32_t>(x); }

// One side. Between two probes (grid points and polar wind breakpoints) every polar is linear in the wind speed, so
// each candidate wins over one stretch at most: walking forward, each change of winner is found by bisection over
// the float bits (non-negative floats order like their bits) for the first speed the scan picks another. Then each
// segment's near ties: the gap between a candidate and the winner is linear between breakpoints, so its smallest
// value over the segment is at an end or at a breakpoint inside, and those are the points checked.
void build_side(const Scanner& sc, const std::vector<float>& probes, const std::vector<float>& breaks, bool up,
                std::size_t n_cells, VmgTable::Side& out) {
  struct Start {
    float from;
    std::int32_t w;
  };
  std::vector<Start> st;
  std::int32_t cur = sc.winner(probes.front(), up);
  st.push_back({probes.front(), cur});
  for (std::size_t j = 0; j + 1 < probes.size(); ++j) {
    std::uint32_t a = bits(probes[j]);
    const std::uint32_t hm = bits(probes[j + 1]) - 1;  // the last float before the next probe
    while (sc.winner(from_bits(hm), up) != cur) {
      std::uint32_t lo = a, hi = hm;  // cur wins at lo, not at hi
      while (hi - lo > 1) {
        const std::uint32_t mid = lo + (hi - lo) / 2;
        if (sc.winner(from_bits(mid), up) == cur) lo = mid;
        else hi = mid;
      }
      cur = sc.winner(from_bits(hi), up);
      st.push_back({from_bits(hi), cur});
      a = hi;
    }
    const std::int32_t next = sc.winner(probes[j + 1], up);  // a step in a polar's wind axis may change it right here
    if (next != cur) {
      cur = next;
      st.push_back({probes[j + 1], cur});
    }
  }

  out = VmgTable::Side{};
  std::vector<float> v;
  std::vector<std::int32_t> keep;
  for (std::size_t s = 0; s < st.size(); ++s) {
    VmgTable::Seg seg;
    seg.from = st[s].from;
    seg.first = static_cast<std::uint16_t>(out.cands.size());
    if (st[s].w >= 0) {
      const float end = s + 1 < st.size() ? from_bits(bits(st[s + 1].from) - 1) : probes.back();
      std::vector<float> pts{seg.from, end};
      for (const float b : breaks) {
        if (b > seg.from && b < end) pts.push_back(b);
      }
      keep.assign(sc.size(), 0);
      for (const float x : pts) {
        sc.values(x, up, v);
        float best = 0.0f;
        for (const float y : v) best = max(best, y);
        const float floor = best - NEAR_TIE * best;
        for (std::size_t j = 0; j < v.size(); ++j) {
          if (v[j] > 0.0f && v[j] >= floor) keep[j] = 1;
        }
      }
      keep[static_cast<std::size_t>(st[s].w)] = 1;
      for (std::size_t j = 0; j < keep.size(); ++j) {
        if (keep[j]) {
          out.cands.push_back({static_cast<std::int16_t>(j / N_ANGLES), static_cast<std::int16_t>(j % N_ANGLES)});
        }
      }
    }
    seg.count = static_cast<std::uint16_t>(out.cands.size() - seg.first);
    out.segs.push_back(seg);
  }
  out.cell.assign(n_cells, 0);
  std::size_t i = 0;
  for (std::size_t c = 0; c < n_cells; ++c) {
    const float x = static_cast<float>(c) * VmgTable::STEP;
    while (i + 1 < out.segs.size() && out.segs[i + 1].from <= x) ++i;
    out.cell[c] = static_cast<std::uint16_t>(i);
  }
}

const VmgTable::Seg& find(const VmgTable::Side& t, float x) {
  const float f = x * (1.0f / VmgTable::STEP);
  const std::size_t last = t.cell.size() - 1;
  std::size_t i = t.cell[f < static_cast<float>(last) ? static_cast<std::size_t>(f) : last];
  while (i > 0 && t.segs[i].from > x) --i;
  while (i + 1 < t.segs.size() && t.segs[i + 1].from <= x) ++i;
  return t.segs[i];
}

// The scan restricted to the segment's candidates (in the scan's order, first strict maximum).
void lookup(const PerfData& perf, const VmgTable::Side& t, float tws, bool up, float& speed, float& twa) {
  const VmgGrid& g = vmg_grid();
  const VmgTable::Seg& s = find(t, tws);
  for (std::size_t j = s.first; j < static_cast<std::size_t>(s.first) + s.count; ++j) {
    const VmgTable::Cand c = t.cands[j];
    const std::size_t k = static_cast<std::size_t>(c.k);
    const float vmg = side_vmg(perf.configs[static_cast<std::size_t>(c.cfg)].polar.at(tws, g.twa[k]), g.cos[k], up);
    if (vmg > speed) {
      speed = vmg;
      twa = g.twa[k];
    }
  }
}

}  // namespace

std::size_t VmgTable::bytes() const {
  std::size_t n = 0;
  for (const Side* s : {&up, &down}) {
    n += s->segs.size() * sizeof(Seg) + s->cands.size() * sizeof(Cand) + s->cell.size() * sizeof(std::uint16_t);
  }
  return n;
}

PolarVmg polar_vmg_scan(const PerfData& perf, float tws) {
  const VmgGrid& g = vmg_grid();
  std::array<float, N_ANGLES> speed;
  PolarVmg r;
  for (const ConfigPerf& cfg : perf.configs) {
    cfg.polar.at_each(tws, g.twa, speed);
    vmg_scan(g, speed, r);
  }
  return r;
}

void build_vmg_table(const PerfData& perf, VmgTable& out) {
  out = VmgTable{};
  if (perf.configs.empty()) return;
  // Probes: TINY, every STEP below the polars' top wind, every polar wind breakpoint and the top (constant above it:
  // tables never extrapolate).
  float top = 0.0f;
  std::vector<float> breaks;
  for (const ConfigPerf& c : perf.configs) {
    for (const float p : c.polar.axis(0).points) {
      if (p > 0.0f) breaks.push_back(p);
      top = max(top, p);
    }
  }
  std::sort(breaks.begin(), breaks.end());
  breaks.erase(std::unique(breaks.begin(), breaks.end()), breaks.end());
  const std::size_t n_cells = static_cast<std::size_t>(top * (1.0f / VmgTable::STEP)) + 2;
  std::vector<float> probes = breaks;
  probes.push_back(TINY);
  for (std::size_t c = 1; c < n_cells; ++c) {
    const float x = static_cast<float>(c) * VmgTable::STEP;
    if (x < top) probes.push_back(x);
  }
  std::sort(probes.begin(), probes.end());
  probes.erase(std::unique(probes.begin(), probes.end()), probes.end());
  const Scanner sc(perf);
  build_side(sc, probes, breaks, true, n_cells, out.up);
  build_side(sc, probes, breaks, false, n_cells, out.down);
}

PolarVmg polar_vmg(const PerfData& perf, float tws) {
  if (perf.vmg.empty()) return polar_vmg_scan(perf, tws);
  if (!(tws >= TINY)) return polar_vmg_scan(perf, tws);  // calm, below 0, NaN
  PolarVmg r;
  lookup(perf, perf.vmg.up, tws, true, r.up_speed, r.up_twa);
  lookup(perf, perf.vmg.down, tws, false, r.down_speed, r.down_twa);
  return r;
}

}  // namespace wm
