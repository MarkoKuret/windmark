// Sea surface, quality tier L (water_render.md §7): 2 detail normal layers.
shader_type spatial;
#define TIER 1
#define WM_DETAIL_LAYERS 2
#include "res://shaders/water_body.gdshaderinc"
