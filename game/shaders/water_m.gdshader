// Sea surface, quality tier M (water_render.md §7): 3 detail normal layers, no per-pixel slope of faded waves, no shadows on the sea (the boats'
// shadows on the water are drawn instead, §4.7).
shader_type spatial;
#define TIER 2
#define WM_DETAIL_LAYERS 3
#define WM_NO_SHADOWS
#include "res://shaders/water_body.gdshaderinc"
