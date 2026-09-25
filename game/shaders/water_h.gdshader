// Sea surface, quality tier H (water_render.md §7): 4 detail normal layers.
shader_type spatial;
#define TIER 3
#define WM_DETAIL_LAYERS 4
#include "res://shaders/water_body.gdshaderinc"
