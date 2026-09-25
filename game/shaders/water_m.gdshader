// Sea surface, quality tier M (water_render.md §7): 3 detail normal layers.
shader_type spatial;
#define TIER 2
#define WM_DETAIL_LAYERS 3
#include "res://shaders/water_body.gdshaderinc"
