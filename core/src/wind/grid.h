// Venue grids (wind.md §8.1): nx × ny nodes at (x0 + i·dx, y0 + j·dy), values row by row (j major, i fastest),
// bilinear inside the box and a caller-given default outside. One sampler serves the venue wind field, the
// current field and the sea exposure grid.
#pragma once

#include <cstdint>
#include <vector>

namespace wm {

struct Grid {
  float x0 = 0.0f, y0 = 0.0f;  // m, world ENU
  float dx = 1.0f, dy = 1.0f;  // m, > 0
  std::uint32_t nx = 2, ny = 2;  // >= 2 each

  std::uint32_t node_count() const { return nx * ny; }
};

// §8.1 location of a point: node (i, j) and the weights (tx, ty) toward i+1, j+1. `inside` is false outside
// the box (the caller then uses its default).
struct GridCell {
  bool inside;
  std::uint32_t i, j;
  float tx, ty;
};

GridCell grid_locate(const Grid& g, float x, float y);

// Bilinear value of one channel (`v` holds nx*ny values) in a located cell; `c.inside` must be true.
float grid_lerp(const Grid& g, const std::vector<float>& v, const GridCell& c);

// §8.1 in one call: bilinear inside the box, `outside` elsewhere.
float grid_sample(const Grid& g, const std::vector<float>& v, float x, float y, float outside);

// Checks nx, ny >= 2, dx, dy > 0 and finite, and that `v` has nx*ny finite values. nullptr when valid, else a
// reason.
const char* check_grid(const Grid& g, const std::vector<float>& v);

}  // namespace wm
