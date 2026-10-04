// Sea surface, quality tier H (water_render.md §7): 4 detail normal layers, the per-pixel slope of faded waves.
shader_type spatial;
#define TIER 3
#define WM_DETAIL_LAYERS 4
#define WM_FADED_SLOPE
#define WM_CAPS_N 6
#include "res://shaders/water_body.gdshaderinc"
