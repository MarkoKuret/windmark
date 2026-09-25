#include "wind/grid.h"

#include <cmath>

#include "math/wm_math.h"

namespace wm {

GridCell grid_locate(const Grid& g, float x, float y) {
  const float x1 = g.x0 + static_cast<float>(g.nx - 1) * g.dx;
  const float y1 = g.y0 + static_cast<float>(g.ny - 1) * g.dy;
  if (x < g.x0 || y < g.y0 || x > x1 || y > y1) return {false, 0, 0, 0.0f, 0.0f};
  // NaN positions fail none of the comparisons above; they are refused here so the index stays in range.
  if (!(x >= g.x0) || !(y >= g.y0)) return {false, 0, 0, 0.0f, 0.0f};
  const float u = (x - g.x0) / g.dx;
  const float w = (y - g.y0) / g.dy;
  std::uint32_t i = static_cast<std::uint32_t>(static_cast<std::int32_t>(u));
  std::uint32_t j = static_cast<std::uint32_t>(static_cast<std::int32_t>(w));
  if (i > g.nx - 2) i = g.nx - 2;
  if (j > g.ny - 2) j = g.ny - 2;
  return {true, i, j, u - static_cast<float>(i), w - static_cast<float>(j)};
}

float grid_lerp(const Grid& g, const std::vector<float>& v, const GridCell& c) {
  const std::uint32_t r = c.j * g.nx + c.i;
  const float r0 = lerp(v[r], v[r + 1], c.tx);
  const float r1 = lerp(v[r + g.nx], v[r + g.nx + 1], c.tx);
  return lerp(r0, r1, c.ty);
}

float grid_sample(const Grid& g, const std::vector<float>& v, float x, float y, float outside) {
  const GridCell c = grid_locate(g, x, y);
  return c.inside ? grid_lerp(g, v, c) : outside;
}

const char* check_grid(const Grid& g, const std::vector<float>& v) {
  if (g.nx < 2 || g.ny < 2) return "grid needs at least 2 x 2 nodes";
  if (!(g.dx > 0.0f) || !(g.dy > 0.0f) || !std::isfinite(g.dx) || !std::isfinite(g.dy)) return "grid spacing must be > 0";
  if (!std::isfinite(g.x0) || !std::isfinite(g.y0)) return "grid origin must be finite";
  if (v.size() != static_cast<std::size_t>(g.nx) * g.ny) return "grid value count is not nx*ny";
  for (float f : v)
    if (!std::isfinite(f)) return "grid value not finite";
  return nullptr;
}

}  // namespace wm
