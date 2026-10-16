#!/usr/bin/env python3
"""Offline preview of the water, step 2 (no window): renders the shots dumped by tests/water_preview_dump.gd.

The water, wake and sky colours come from the same shader functions Godot runs (shaders/sea_common.gdshaderinc,
sky_common.gdshaderinc, wake_common.gdshaderinc), compiled here as GLSL 4.1 on an offscreen OpenGL context, with
the uniforms, meshes and textures Godot computed. Only the lighting model around them is a stand-in for Godot's
Forward+ (GGX sun specular, sky reflection blurred by the roughness with Godot's environment BRDF, Lambert, Godot's fog, Godot's ACES curve), so colours are
close to, not identical with, the engine's. Boats are drawn with the boat shader's textures, factors and baked AO
(on the ambient light only), without shadows.

    python3 game/tests/water_preview.py [--size 1280x720] [--no-wakes] [--publish] [--strip NAME] [shot ...]

Writes game/generated/water_preview/<shot>.png (with --publish also game/tests/previews/water_<shot>.jpg, or
<shot>.jpg for the whitecap shots, whitecaps_*). --strip NAME also puts the shots side by side, two per row, each
labelled with its time from the first (a time sequence), in generated/water_preview/NAME.png (with --publish also
in game/tests/previews/NAME.jpg). Needs numpy, Pillow and moderngl (docs/THIRD_PARTY.md).
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

import moderngl
import numpy as np
from PIL import Image

GAME = Path(__file__).resolve().parents[1]
SHADERS = GAME / "shaders"
OUT = GAME / "generated" / "water_preview"
PUBLISHED = GAME / "tests" / "previews"


def fog_uniforms(fog):
    """The fog of a dumped scene (Godot's Environment fog) as the LIGHTING uniforms."""
    return {
        "u_fog_density": float(fog["density"]),
        "u_fog_color": tuple(fog["color"][:3]),
        "u_fog_mode": int(fog.get("mode", 0)),
        "u_fog_depth": (float(fog.get("begin", 0.0)), float(fog.get("end", 1.0)), float(fog.get("curve", 1.0))),
        "u_fog_sun_scatter": float(fog.get("sun_scatter", 0.0)),
    }


def inc(name):
    return (SHADERS / name).read_text()


SAMPLERS = """
uniform sampler2D expo_tex;
uniform sampler2D land_tex;
uniform sampler2D detail_tex;
uniform sampler2D foam_tex;
uniform sampler2D wake_tex;
uniform sampler2D caps_tex;
"""

LIGHTING = """
uniform vec3 u_cam;
uniform float u_cloud_cover;
uniform vec2 u_cloud_offset;
uniform float u_fog_density;
uniform vec3 u_fog_color;
uniform int u_fog_mode;        // Godot's Environment.fog_mode: 0 exponential, 1 depth (the haze, water_render.md §4.5)
uniform vec3 u_fog_depth;      // depth fog begin (m), end (m), curve
uniform float u_fog_sun_scatter;
uniform float u_ambient;

const float WM_PI = 3.14159265;

vec3 env_sky(vec3 d) {
    return wm_sky_color(d, normalize(sun_dir), sky_horizon, sky_zenith, sun_color, u_cloud_cover, u_cloud_offset, 0.0);
}

// The sun's shadow map (water_render.md §4.6, stand-in): the boats' depth seen from the sun, filtered over about
// 5 cm like Godot's soft filter. 1 = lit.
uniform sampler2D u_shadow_map;
uniform mat4 u_light_vp;
uniform float u_use_shadow_map;
float sun_vis(vec3 wpos, vec3 N) {
    if (u_use_shadow_map < 0.5) return 1.0;
    vec4 l = u_light_vp * vec4(wpos + N * 0.02, 1.0);
    vec3 c = l.xyz / l.w * 0.5 + 0.5;
    if (c.x < 0.0 || c.y < 0.0 || c.x > 1.0 || c.y > 1.0 || c.z > 1.0) return 1.0;
    float texel = 1.0 / float(textureSize(u_shadow_map, 0).x);
    float vis = 0.0;
    for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
            float d = texture(u_shadow_map, c.xy + vec2(float(i), float(j)) * texel * 2.0).r;
            vis += c.z - 0.0004 > d ? 0.0 : 1.0;
        }
    }
    return vis / 25.0;
}

// The sky seen in a rough mirror (Godot's radiance map, blurred by roughness): the sky averaged over a GGX-sized cone
// of 13 fixed directions around R (half angle about 1.5 alpha), the sharp sky below alpha 0.01.
vec3 env_rough(vec3 R, float a) {
    if (a < 0.01) return env_sky(R);
    vec3 t = normalize(abs(R.y) < 0.99 ? cross(R, vec3(0.0, 1.0, 0.0)) : cross(R, vec3(1.0, 0.0, 0.0)));
    vec3 b = cross(R, t);
    vec3 c = env_sky(R);
    float w = 1.0;
    for (int i = 0; i < 12; i++) {
        float ang = float(i) * 2.39996;
        float r = sqrt((float(i) + 0.5) / 12.0) * 1.5 * a;
        vec3 d = normalize(R + r * (cos(ang) * t + sin(ang) * b));
        d.y = max(d.y, 0.002);
        c += env_sky(normalize(d));
        w += 1.0;
    }
    return c / w;
}

// Stand-in for Godot's PBR: F0 = 0.16 specular^2, GGX with alpha = roughness^2, Schlick sky reflection. vis: the
// sun's share that reaches the surface (its shadow).
vec3 shade_vis(vec3 albedo, float rough, float spec, vec3 N, vec3 V, float vis_sun);
vec3 shade(vec3 albedo, float rough, float spec, vec3 N, vec3 V) {
    return shade_vis(albedo, rough, spec, N, V, 1.0);
}
vec3 shade_vis(vec3 albedo, float rough, float spec, vec3 N, vec3 V, float vis_sun) {
    vec3 L = normalize(sun_dir);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 1e-4);
    vec3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float LdotH = max(dot(L, H), 0.0);
    float f0 = 0.16 * spec * spec;
    float a = max(rough * rough, 2e-3);
    float a2 = a * a;
    float dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (WM_PI * dd * dd);
    float k = a * 0.5;
    float vis = 0.25 / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k));
    float F = f0 + (1.0 - f0) * pow(1.0 - LdotH, 5.0);
    vec3 direct = vis_sun * sun_color * NdotL * (albedo * (1.0 - F) + WM_PI * D * vis * F);
    // Godot's environment BRDF approximation (scene_forward: Lazarov 2013 / Karis mobile), which dims the sky's
    // reflection of a rough surface at grazing angles
    vec4 rc = rough * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
    float a004 = min(rc.x * rc.x, exp2(-9.28 * NdotV)) * rc.x + rc.y;
    vec2 envb = vec2(-1.04, 1.04) * a004 + rc.zw;
    float Fe = envb.x * f0 + envb.y * clamp(50.0 * f0, 0.0, 1.0);
    vec3 R = reflect(-V, N);
    vec3 refl = env_rough(R, a) * Fe;
    vec3 amb = albedo * mix(sky_horizon, sky_zenith, 0.5) * u_ambient * (1.0 - Fe);
    return direct + refl + amb;
}

// Godot's fixed fog (Forward+ fog_process): exponential, or depth fog density * smoothstep(begin, end, d)^curve;
// the fog colour gains the sun's light toward the sun (sun scatter).
vec3 fogged(vec3 c, vec3 wpos) {
    float d = length(u_cam - wpos);
    float f = u_fog_mode == 1 ? pow(smoothstep(u_fog_depth.x, u_fog_depth.y, d), u_fog_depth.z) * u_fog_density
                              : 1.0 - exp(-u_fog_density * d);
    vec3 fc = u_fog_color + sun_color * pow(max(dot(normalize(wpos - u_cam), normalize(sun_dir)), 0.0), 8.0) * u_fog_sun_scatter;
    return mix(c, fc, f);
}
"""


# --no-caps: leave the whitecaps (water_render.md §4.4) out, for a before/after comparison
NO_CAPS = False

# --faded-slope: the per-pixel slope of faded waves on every tier (water_render.md §3.2; the shaders draw it on tier
# H only), to compare a tier's look with and without it
FADED_SLOPE_ALWAYS = False


def header(tier, layers):
    slope = "#define WM_FADED_SLOPE\n" if tier >= 3 or FADED_SLOPE_ALWAYS else ""
    caps = "" if NO_CAPS else "#define WM_WHITECAPS\n#define WM_CAPS_N %d\n" % (4 if tier == 1 else 6)
    return (f"#version 410\n#define TIER {tier}\n#define WM_DETAIL_LAYERS {layers}\n" + slope + caps + SAMPLERS
            + inc("sea_common.gdshaderinc"))


WATER_VS = """
uniform mat4 u_vp;
uniform vec3 u_sea_pos;
in vec3 in_pos;
in vec2 in_uv;
out vec2 v_local;
out float v_spacing;
out float v_eta;
out float v_expo;
out float v_land;
out vec3 v_normal;
out vec3 v_wpos;
void main() {
    vec2 xl = vec2(in_pos.x, -in_pos.z);
    float eta;
    vec2 grad;
    wm_sea_height(xl, in_uv.x, eta, grad);
    float expo = wm_exposure(sea_origin + xl);
    eta *= expo;
    grad *= expo;
    v_normal = normalize(vec3(-grad.x, 1.0, grad.y));
    v_local = xl;
    v_spacing = in_uv.x;
    v_eta = eta;
    v_expo = expo;
    v_land = wm_land(sea_origin + xl);
    v_wpos = vec3(in_pos.x, eta, in_pos.z) + u_sea_pos;
    gl_Position = u_vp * vec4(v_wpos, 1.0);
}
"""

WATER_FS = """
in vec2 v_local;
in float v_spacing;
in float v_eta;
in float v_expo;
in float v_land;
in vec3 v_normal;
in vec3 v_wpos;
out vec4 frag;
void main() {
    vec3 view = normalize(u_cam - v_wpos);
    float dist = length(u_cam.xz - v_wpos.xz);
    vec3 n_geo = normalize(v_normal);
    float px = max(length(fwidth(v_local)), 1e-3);
#ifdef WM_FADED_SLOPE
    vec2 g = wm_faded_slope(v_local, v_spacing, px) * v_expo;
    n_geo = normalize(n_geo + vec3(-g.x, 0.0, g.y));
#endif
    WmSurface S = wm_surface(v_local, v_eta, n_geo, view, dist, px, vec2(0.0), v_land);
#ifdef WM_WHITECAPS
    wm_apply_caps(S, v_local, px, v_expo, dist, n_geo);
#endif
    vec3 c = shade_vis(S.albedo, S.roughness, S.specular, S.normal, view, sun_vis(v_wpos, vec3(0.0, 1.0, 0.0))) + S.emission;
    frag = vec4(fogged(c, v_wpos), 1.0);
}
"""

WAKE_VS = """
uniform mat4 u_vp;
uniform vec3 u_cam;
uniform float grid_q;
uniform float grid_segments;
in vec3 in_pos;
in vec2 in_uv;
in vec4 in_color;
out vec2 v_uv;
out float v_a;
out float v_c;
out float v_line;
out float v_age;
out vec3 v_wpos;
out vec2 v_ground;
void main() {
    v_ground = in_pos.xz;
    v_wpos = wm_wake_drape(in_pos, u_cam, grid_q, grid_segments);
    v_uv = in_uv;
    v_a = in_color.a;
    v_c = in_color.r;
    v_line = in_color.b;
    v_age = in_color.g;
    gl_Position = u_vp * vec4(v_wpos, 1.0);
}
"""

WAKE_FS = """
in vec2 v_uv;
in float v_a;
in float v_c;
in float v_line;
in float v_age;
in vec3 v_wpos;
in vec2 v_ground;
out vec4 frag;
void main() {
    float a = wm_wake_alpha(v_uv, v_c, v_line, v_a, v_age, texture(foam_tex, v_ground / 3.0).r,
                            texture(foam_tex, v_uv * vec2(0.6, 0.7) + 0.37).g, texture(foam_tex, v_uv * vec2(0.15, 0.17) + 0.71).g);
    vec3 V = normalize(u_cam - v_wpos);
    vec3 c = shade(col_foam, 0.6, 0.3, vec3(0.0, 1.0, 0.0), V);
    frag = vec4(fogged(c, v_wpos), a);
}
"""

BOW_VS = """
uniform mat4 u_vp;
uniform vec3 u_cam;
uniform float grid_q;
uniform float grid_segments;
uniform float u_flow;
in vec3 in_pos;
in vec2 in_uv;
in vec2 in_uv2;
in vec4 in_color;
out vec2 v_uv;
out vec2 v_flow;
out float v_a;
out vec3 v_wpos;
void main() {
    v_wpos = wm_drape(in_pos, in_uv2.x, u_cam, grid_q, grid_segments);
    v_uv = in_uv;
    v_flow = vec2(in_uv.x * 2.0, in_uv2.y - u_flow);
    v_a = in_color.a;
    gl_Position = u_vp * vec4(v_wpos, 1.0);
}
"""

# bow_wave.gdshader's fragment()
BOW_FS = """
in vec2 v_uv;
in vec2 v_flow;
in float v_a;
in vec3 v_wpos;
out vec4 frag;
const vec3 COL_SHEET = vec3(0.10, 0.22, 0.24);
void main() {
    vec2 f = wm_bow_alpha(v_uv, v_a, texture(foam_tex, v_flow * vec2(1.6, 0.9)).g,
                          texture(foam_tex, v_flow * vec2(0.45, 0.2) + 0.61).g);
    vec3 V = normalize(u_cam - v_wpos);
    vec3 c = shade(mix(COL_SHEET, col_foam, f.x), mix(0.12, 0.6, f.x), 0.4, vec3(0.0, 1.0, 0.0), V);
    frag = vec4(fogged(c, v_wpos), f.y);
}
"""

MIST_VS = """
uniform mat4 u_vp;
in vec3 in_pos;
in vec2 in_uv;
in vec3 in_as;
out vec2 v_uv;
out vec3 v_as;
out vec3 v_wpos;
void main() {
    v_wpos = in_pos;
    v_uv = in_uv;
    v_as = in_as;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

# mist.gdshader's fragment() (the engine also fades the sprite against the scene depth)
MIST_FS = """
in vec2 v_uv;
in vec3 v_as;
in vec3 v_wpos;
out vec4 frag;
void main() {
    float c = cos(v_as.y * 6.2831);
    float sn = sin(v_as.y * 6.2831);
    vec2 ruv = mat2(vec2(c, sn), vec2(-sn, c)) * (v_uv - 0.5);
    float n = texture(foam_tex, ruv * (0.7 + 1.3 * v_as.z) + v_as.y * 3.7).r;
    float d = length(v_wpos - u_cam);
    float a = wm_mist_alpha(v_uv, n, v_as.z) * v_as.x * smoothstep(1.0, 3.0, d);
    vec3 view_dir = normalize(v_wpos - u_cam);
    float fwd = pow(max(dot(view_dir, normalize(sun_dir)), 0.0), 3.0);
    vec3 col = 0.35 * sky_horizon + 0.12 * sun_color * (1.0 + 2.0 * fwd);
    frag = vec4(fogged(col, v_wpos), clamp(a, 0.0, 1.0));
}
"""

# boat_shadow.gdshader: the drawn boat shadow (water_render.md §4.7), multiplying the colour behind it
DRAWN_VS = """
uniform mat4 u_vp;
uniform vec3 u_cam;
uniform float grid_q;
uniform float grid_segments;
in vec3 in_pos;
out vec3 v_water;
void main() {
    vec3 p = wm_drape(in_pos, 0.03, u_cam, grid_q, grid_segments);
    vec2 dc = p.xz - u_cam.xz;
    float s = length(dc) > 1e-4 ? length(in_pos.xz - u_cam.xz) / length(dc) : 1.0;
    v_water = u_cam + (p - u_cam) * s;
    gl_Position = u_vp * vec4(p, 1.0);
}
"""

DRAWN_FS = """
in vec3 v_water;
out vec4 frag;
void main() {
    float px = length(fwidth(v_water.xz));
    float s = wm_boat_shadow(v_water, px, u_row);
    vec3 V = normalize(u_cam - v_water);
    frag = vec4(mix(vec3(1.0), shadow_keep, s), 1.0);
}
"""

DEPTH_VS = """
#version 410
uniform mat4 u_vp;
in vec3 in_pos;
void main() {
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

DEPTH_FS = """
#version 410
void main() {
}
"""

BOAT_VS = """
#version 410
uniform mat4 u_vp;
uniform vec2 u_uv_scale;
in vec3 in_pos;
in vec3 in_normal;
in vec2 in_uv;
in float in_ao;
out vec3 v_n;
out vec3 v_wpos;
out vec2 v_uv;
out float v_ao;
void main() {
    v_n = in_normal;
    v_wpos = in_pos;
    v_uv = in_uv * u_uv_scale;
    v_ao = in_ao;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

# The boat shader's inputs (shaders/boat.gdshader): tiling albedo (sRGB) and metallic-roughness textures times the
# factors, albedo capped, baked AO on the ambient and reflected light only; metals reflect the sky in their
# colour. Stand-in for Godot's PBR like the water's.
BOAT_FS = """
in vec3 v_n;
in vec3 v_wpos;
in vec2 v_uv;
in float v_ao;
uniform vec3 u_albedo;
uniform float u_rough;
uniform float u_metal;
uniform float u_ao_strength;
uniform float u_albedo_max;
uniform sampler2D u_albedo_tex;
uniform sampler2D u_mr_tex;
uniform float u_shadow;  // 1: the boat takes the shadow map (sun_vis), 0: lit
out vec4 frag;
void main() {
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_wpos);
    if (dot(N, V) < 0.0) N = -N;
    vec3 tex = pow(texture(u_albedo_tex, v_uv).rgb, vec3(2.2));
    vec3 albedo = min(tex * u_albedo, vec3(u_albedo_max));
    vec4 mr = texture(u_mr_tex, v_uv);
    float rough = clamp(mr.g * u_rough, 0.04, 1.0);
    float metal = clamp(mr.b * u_metal, 0.0, 1.0);
    float ao = mix(1.0, v_ao, u_ao_strength);
    vec3 L = normalize(sun_dir);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 1e-4);
    vec3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    vec3 f0 = mix(vec3(0.04), albedo, metal);
    float a = max(rough * rough, 2e-3);
    float a2 = a * a;
    float dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (WM_PI * dd * dd);
    float k = a * 0.5;
    float vis = 0.25 / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k));
    vec3 F = f0 + (1.0 - f0) * pow(1.0 - max(dot(L, H), 0.0), 5.0);
    vec3 diff = albedo * (1.0 - metal);
    vec3 direct = mix(1.0, sun_vis(v_wpos, N), u_shadow) * sun_color * NdotL * (diff * (1.0 - F) + WM_PI * D * vis * F);
    vec3 Fe = f0 + (max(vec3(1.0 - rough), f0) - f0) * pow(1.0 - NdotV, 5.0);
    vec3 R = reflect(-V, N);
    // rough surfaces see a blurred sky: toward the average sky colour
    vec3 sky_r = mix(env_sky(R), mix(sky_horizon, sky_zenith, 0.5), clamp(rough * 1.3, 0.0, 1.0));
    vec3 amb_sky = mix(mix(sky_horizon, sky_zenith, 0.5) * 0.8, sky_horizon * 0.45, clamp(-N.y, 0.0, 1.0));
    vec3 c = direct + ao * (sky_r * Fe + diff * amb_sky * u_ambient * (1.0 - Fe));
    frag = vec4(fogged(c, v_wpos), 1.0);
}
"""

SKY_VS = """
#version 410
in vec2 in_pos;
out vec2 v_ndc;
void main() {
    v_ndc = in_pos;
    gl_Position = vec4(in_pos, 0.9999, 1.0);
}
"""

SKY_FS = """
uniform mat4 u_inv_vp;
in vec2 v_ndc;
out vec4 frag;
void main() {
    vec4 a = u_inv_vp * vec4(v_ndc, -1.0, 1.0);
    vec4 b = u_inv_vp * vec4(v_ndc, 1.0, 1.0);
    vec3 d = normalize(b.xyz / b.w - a.xyz / a.w);
    frag = vec4(wm_sky_color(d, normalize(sun_dir), sky_horizon, sky_zenith, sun_color, u_cloud_cover, u_cloud_offset, 1.0), 1.0);
}
"""

TONEMAP_FS = """
#version 410
uniform sampler2D u_hdr;
uniform float u_exposure;
uniform float u_white;
in vec2 v_ndc;
out vec4 frag;
// Godot's ACES fit (tonemap_aces in the engine's tonemap shader).
vec3 tonemap_aces(vec3 color, float white) {
    const float exposure_bias = 1.8;
    const float A = 0.0245786;
    const float B = 0.000090537;
    const float C = 0.983729;
    const float D = 0.432951;
    const float E = 0.238081;
    const mat3 rgb_to_rrt = mat3(
        vec3(0.59719 * exposure_bias, 0.35458 * exposure_bias, 0.04823 * exposure_bias),
        vec3(0.07600 * exposure_bias, 0.90834 * exposure_bias, 0.01566 * exposure_bias),
        vec3(0.02840 * exposure_bias, 0.13383 * exposure_bias, 0.83777 * exposure_bias));
    const mat3 odt_to_rgb = mat3(
        vec3(1.60475, -0.53108, -0.07367),
        vec3(-0.10208, 1.10813, -0.00605),
        vec3(-0.00327, -0.07276, 1.07602));
    color *= rgb_to_rrt;
    vec3 t = (color * (color + A) - B) / (color * (C * color + D) + E);
    t *= odt_to_rgb;
    white *= exposure_bias;
    float w = (white * (white + A) - B) / (white * (C * white + D) + E);
    return t / w;
}
vec3 to_srgb(vec3 c) {
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
uniform sampler2D u_glow;
void main() {
    vec2 uv = v_ndc * 0.5 + 0.5;
    vec3 c = (texture(u_hdr, uv).rgb + texture(u_glow, uv).rgb) * u_exposure;
    frag = vec4(to_srgb(clamp(tonemap_aces(max(c, vec3(0.0)), u_white), 0.0, 1.0)), 1.0);
}
"""


def perspective(fov_deg, aspect, near, far):
    f = 1.0 / math.tan(math.radians(fov_deg) / 2.0)
    m = np.zeros((4, 4))
    m[0, 0] = f / aspect
    m[1, 1] = f
    m[2, 2] = (far + near) / (near - far)
    m[2, 3] = 2.0 * far * near / (near - far)
    m[3, 2] = -1.0
    return m


def load_bin(d, name, dtype, cols):
    return np.fromfile(d / name, dtype=dtype).reshape(-1, cols) if cols > 1 else np.fromfile(d / name, dtype=dtype)


def set_uniforms(prog, values):
    for k, v in values.items():
        if k not in prog:
            continue
        u = prog[k]
        if isinstance(v, list) and v and isinstance(v[0], list):
            arr = np.array(v, dtype="f4")
            n = u.array_length
            if arr.shape[0] < n:
                arr = np.vstack([arr, np.zeros((n - arr.shape[0], arr.shape[1]), dtype="f4")])
            u.write(arr[:n].tobytes())
        elif isinstance(v, list) and u.array_length > 1 and u.dimension == 1:
            arr = np.zeros(u.array_length, dtype="f4")
            arr[:min(len(v), u.array_length)] = v[:u.array_length]
            u.write(arr.tobytes())
        elif isinstance(v, list):
            if u.fmt and "i" in u.fmt:
                u.value = tuple(int(x) for x in v)
            else:
                u.value = tuple(float(x) for x in v)
        elif isinstance(v, bool):
            u.value = int(v)
        elif u.fmt and "i" in u.fmt:
            u.value = int(v)
        else:
            u.value = float(v)


def set_if(prog, name, value):
    if name in prog:
        prog[name].value = value


def texture_from_png(ctx, path, components):
    img = Image.open(path)
    img = img.convert("RGBA" if components == 4 else "RGB")
    a = np.asarray(img, dtype="u1")[:, :, :components]
    t = ctx.texture(img.size, components, np.ascontiguousarray(a).tobytes())
    t.build_mipmaps()
    t.repeat_x = t.repeat_y = True
    t.filter = (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
    t.anisotropy = 8.0
    return t


def look_at(eye, target, up):
    f = target - eye
    f = f / np.linalg.norm(f)
    s = np.cross(f, up)
    s = s / np.linalg.norm(s)
    u = np.cross(s, f)
    m = np.eye(4)
    m[0, :3], m[1, :3], m[2, :3] = s, u, -f
    m[:3, 3] = -m[:3, :3] @ eye
    return m


def ortho(half, near, far):
    m = np.eye(4)
    m[0, 0] = m[1, 1] = 1.0 / half
    m[2, 2] = -2.0 / (far - near)
    m[2, 3] = -(far + near) / (far - near)
    return m


SHADOW_MAP = 4096
SHADOW_HALF = 25.0


def shadow_pass(ctx, d, sc):
    """The boats' depth seen from the sun around the boat: (depth texture, light view-projection)."""
    tris = []
    for b in sc["boat"]:
        if "indices" not in b:
            continue
        bp = load_bin(d, b["name"] + "_pos.bin", "f4", 3)
        bi = load_bin(d, b["name"] + "_idx.bin", "i4", 1)
        tris.append(bp[bi])
    if not tris:
        return None, None
    pts = np.vstack(tris)
    centre = 0.5 * (pts.min(0) + pts.max(0))
    L = np.array(sc["water"]["sun_dir"], dtype=float)
    L /= np.linalg.norm(L)
    up = np.array([0.0, 1.0, 0.0]) if abs(L[1]) < 0.99 else np.array([0.0, 0.0, -1.0])
    light_vp = ortho(SHADOW_HALF, 1.0, 160.0) @ look_at(centre + L * 80.0, centre, up)
    tex = ctx.depth_texture((SHADOW_MAP, SHADOW_MAP))
    tex.compare_func = ""
    tex.filter = (moderngl.NEAREST, moderngl.NEAREST)
    fbo = ctx.framebuffer(depth_attachment=tex)
    fbo.use()
    ctx.clear(depth=1.0)
    ctx.enable(moderngl.DEPTH_TEST)
    ctx.disable(moderngl.CULL_FACE)
    prog = ctx.program(vertex_shader=DEPTH_VS, fragment_shader=DEPTH_FS)
    prog["u_vp"].write(light_vp.T.astype("f4").tobytes())
    vbo = ctx.buffer(pts.astype("f4").tobytes())
    ctx.vertex_array(prog, [(vbo, "3f", "in_pos")]).render(moderngl.TRIANGLES)
    return tex, light_vp


def render(ctx, d, size, wakes=True, shadows="auto"):
    """shadows: `real` (the sun's shadow map on the water, tier H), `drawn` (the drawn boat shadows, tiers L and
    M), `none`, or `auto` (the tier's). The boats take the shadow map unless `none`."""
    sc = json.loads((d / "scene.json").read_text())
    if sc.get("meshes_from"):
        # a light sequence frame: its own sea uniforms, everything else the first frame's
        d = d.parent / sc["meshes_from"]
        water = sc["water"]
        sc = json.loads((d / "scene.json").read_text())
        sc["water"] = water
    w, h = size
    tier = {"L": 1, "M": 2, "H": 3}[sc["tier"]]
    if shadows == "auto":
        shadows = "real" if sc["tier"] == "H" else "drawn"
    shadow_tex, light_vp = shadow_pass(ctx, d, sc) if shadows != "none" else (None, None)
    hdr_inc = header(tier, sc["detail_layers"])
    sky_inc = inc("sky_common.gdshaderinc")
    wake_inc = inc("wake_common.gdshaderinc")

    cam = sc["camera"]
    basis = np.array(cam["basis"]).T  # columns x, y, z
    origin = np.array(cam["origin"])
    view = np.eye(4)
    view[:3, :3] = basis.T
    view[:3, 3] = -basis.T @ origin
    near = max(cam["near"], 0.3)
    proj = perspective(cam["fov"], w / h, near, cam["far"])
    vp = proj @ view
    vp_bytes = vp.T.astype("f4").tobytes()
    inv_vp = np.linalg.inv(vp).T.astype("f4").tobytes()

    common = {
        "u_cam": tuple(origin),
        "u_cloud_cover": float(sc["sky"].get("cloud_cover", 0.3)),
        "u_cloud_offset": tuple(sc["sky"].get("cloud_offset", [0.0, 0.0])),
        **fog_uniforms(sc["fog"]),
        "u_ambient": float(sc["ambient_energy"]),
    }

    water = ctx.program(vertex_shader=hdr_inc + WATER_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + WATER_FS)
    wake = ctx.program(vertex_shader=hdr_inc + wake_inc + WAKE_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + wake_inc + WAKE_FS)
    bow = ctx.program(vertex_shader=hdr_inc + wake_inc + BOW_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + wake_inc + BOW_FS)
    mist = ctx.program(vertex_shader=hdr_inc + MIST_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + wake_inc + MIST_FS)
    boat = ctx.program(vertex_shader=BOAT_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + BOAT_FS)
    drawn = ctx.program(vertex_shader=hdr_inc + wake_inc + DRAWN_VS,
                        fragment_shader=hdr_inc + sky_inc + LIGHTING + "uniform sampler2D shadow_tex;\nuniform int u_row;\n" + inc("boat_shadow_common.gdshaderinc") + DRAWN_FS)
    sky = ctx.program(vertex_shader=SKY_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + SKY_FS)
    tone = ctx.program(vertex_shader=SKY_VS, fragment_shader=TONEMAP_FS)

    # textures shared by the water and the wakes
    detail = texture_from_png(ctx, d / "detail.png", 4)
    foam = texture_from_png(ctx, d / "foam.png", 3)
    caps = texture_from_png(ctx, d / "caps.png", 4)
    if sc["exposure"]:
        e = np.fromfile(d / "expo.bin", dtype="f4")
        expo = ctx.texture((sc["exposure"]["nx"], sc["exposure"]["ny"]), 1, e.tobytes(), dtype="f4")
    else:
        expo = ctx.texture((2, 2), 1, np.ones(4, dtype="f4").tobytes(), dtype="f4")
    expo.filter = (moderngl.NEAREST, moderngl.NEAREST)
    if sc.get("land"):
        lf = np.fromfile(d / "land.bin", dtype="f4")
        land = ctx.texture((sc["land"]["nx"], sc["land"]["ny"]), 2, lf.tobytes(), dtype="f4")
    else:
        land = ctx.texture((2, 2), 2, np.ones(8, dtype="f4").tobytes(), dtype="f4")
    land.filter = (moderngl.NEAREST, moderngl.NEAREST)
    wake_tex = ctx.texture((1, 1), 4, bytes([128, 128, 128, 255]))
    units = {"expo_tex": (expo, 0), "detail_tex": (detail, 1), "foam_tex": (foam, 2), "wake_tex": (wake_tex, 3),
             "land_tex": (land, 4), "caps_tex": (caps, 9)}
    for tex, unit in units.values():
        tex.use(unit)

    if shadow_tex is not None:
        shadow_tex.use(7)
    for p in (water, wake, bow, mist, boat, sky, drawn):
        set_uniforms(p, sc["water"])
        set_if(p, "u_shadow_map", 7)
        set_if(p, "u_use_shadow_map", 1.0 if shadow_tex is not None else 0.0)
        if light_vp is not None and "u_light_vp" in p:
            p["u_light_vp"].write(light_vp.T.astype("f4").tobytes())
        for k, v in common.items():
            set_if(p, k, v)
        for name, (_, unit) in units.items():
            set_if(p, name, unit)
        if "u_vp" in p:
            p["u_vp"].write(vp_bytes)
    set_uniforms(wake, sc["wake_uniforms"])
    set_uniforms(bow, sc["wake_uniforms"])
    # the sea takes the shadow map only for real shadows (tier H); the wakes, bow waves and mist take none
    set_if(water, "u_use_shadow_map", 1.0 if shadows == "real" else 0.0)
    set_uniforms(sky, {k: v for k, v in sc["sky"].items() if k in ("sky_horizon", "sky_zenith", "sun_dir", "sun_color")})
    sky["u_inv_vp"].write(inv_vp)
    water["u_sea_pos"].value = tuple(sc["sea_position"])

    samples = 4
    color_rb = ctx.renderbuffer((w, h), 4, samples=samples, dtype="f2")
    depth_rb = ctx.depth_renderbuffer((w, h), samples=samples)
    fbo = ctx.framebuffer(color_attachments=[color_rb], depth_attachment=depth_rb)
    resolved = ctx.texture((w, h), 4, dtype="f2")
    fbo_res = ctx.framebuffer(color_attachments=[resolved])
    fbo.use()
    ctx.clear(0.0, 0.0, 0.0, 1.0, depth=1.0)

    quad = ctx.buffer(np.array([-1, -1, 3, -1, -1, 3], dtype="f4").tobytes())
    ctx.disable(moderngl.DEPTH_TEST)
    ctx.vertex_array(sky, [(quad, "2f", "in_pos")]).render(moderngl.TRIANGLES)

    ctx.enable(moderngl.DEPTH_TEST)
    ctx.enable(moderngl.CULL_FACE)
    ctx.front_face = "cw"  # Godot's front faces are clockwise
    g = sc["grid"]
    pos = load_bin(d, "grid_pos.bin", "f4", 3)
    uv = load_bin(d, "grid_uv.bin", "f4", 2)
    idx = load_bin(d, "grid_idx.bin", "i4", 1)
    vbo = ctx.buffer(np.hstack([pos, uv]).astype("f4").tobytes())
    ibo = ctx.buffer(idx.astype("i4").tobytes())
    ctx.vertex_array(water, [(vbo, "3f 2f", "in_pos", "in_uv")], ibo).render(moderngl.TRIANGLES)
    assert g["count"] == pos.shape[0]

    ctx.disable(moderngl.CULL_FACE)
    white = ctx.texture((1, 1), 4, bytes([255, 255, 255, 255]))
    tex_cache = {}

    def boat_tex(name):
        if not name:
            return white
        if name not in tex_cache:
            tex_cache[name] = texture_from_png(ctx, d / name, 4)
        return tex_cache[name]

    for b in sc["boat"]:
        if "normal" not in b or "indices" not in b:
            continue
        bp = load_bin(d, b["name"] + "_pos.bin", "f4", 3)
        bn = load_bin(d, b["name"] + "_normal.bin", "f4", 3)
        bi = load_bin(d, b["name"] + "_idx.bin", "i4", 1)
        n = bp.shape[0]
        buv = load_bin(d, b["name"] + "_uv.bin", "f4", 2) if b.get("uv") else np.zeros((n, 2), "f4")
        bao = load_bin(d, b["name"] + "_color.bin", "f4", 4)[:, :1] if b.get("color") else np.ones((n, 1), "f4")
        boat["u_albedo"].value = tuple(b["albedo"][:3])
        set_if(boat, "u_rough", float(b.get("roughness", 0.5)))
        set_if(boat, "u_metal", float(b.get("metallic", 0.0)))
        set_if(boat, "u_ao_strength", float(b.get("ao", 0.0)))
        set_if(boat, "u_albedo_max", float(b.get("albedo_max", 1.0)))
        set_if(boat, "u_uv_scale", tuple(b.get("uv_scale", [1.0, 1.0])))
        set_if(boat, "u_shadow", 1.0 if shadow_tex is not None else 0.0)
        boat_tex(b.get("albedo_tex")).use(5)
        boat_tex(b.get("mr_tex")).use(6)
        set_if(boat, "u_albedo_tex", 5)
        set_if(boat, "u_mr_tex", 6)
        bv = ctx.buffer(np.hstack([bp, bn, buv, bao]).astype("f4").tobytes())
        ctx.vertex_array(boat, [(bv, "3f 3f 2f 1f", "in_pos", "in_normal", "in_uv", "in_ao")],
                         ctx.buffer(bi.astype("i4").tobytes())).render(moderngl.TRIANGLES)

    ctx.enable(moderngl.BLEND)
    fbo.depth_mask = False  # the ribbons and the drawn shadows do not write depth (depth_draw_never)
    if shadows == "drawn":
        # the drawn boat shadows multiply the colour behind them, before the wakes (render priority -1)
        ctx.blend_func = moderngl.DST_COLOR, moderngl.ZERO
        if sc.get("drawn_shadows"):
            tw, th = sc["drawn_tex"]
            data = np.fromfile(d / "drawn_tex.bin", dtype="f4")
            dtex = ctx.texture((tw, th), 4, data.tobytes(), dtype="f4")
            dtex.filter = (moderngl.NEAREST, moderngl.NEAREST)
            dtex.use(8)
            drawn["shadow_tex"].value = 8
            set_uniforms(drawn, {k: v for k, v in sc["drawn_uniforms"].items() if k != "shadow_tex"})
        for r in sc.get("drawn_shadows", []):
            drawn["u_row"].value = int(r["row"])
            rp = load_bin(d, r["name"] + "_pos.bin", "f4", 3)
            ri = load_bin(d, r["name"] + "_idx.bin", "i4", 1)
            ctx.vertex_array(drawn, [(ctx.buffer(rp.astype("f4").tobytes()), "3f", "in_pos")],
                             ctx.buffer(ri.astype("i4").tobytes())).render(moderngl.TRIANGLES)
    ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA
    for r in sc["wakes"] if wakes else []:
        if "indices" not in r:
            continue
        rp = load_bin(d, r["name"] + "_pos.bin", "f4", 3)
        ru = load_bin(d, r["name"] + "_uv.bin", "f4", 2)
        rc = load_bin(d, r["name"] + "_color.bin", "f4", 4)
        ri = load_bin(d, r["name"] + "_idx.bin", "i4", 1)
        rv = ctx.buffer(np.hstack([rp, ru, rc]).astype("f4").tobytes())
        ctx.vertex_array(wake, [(rv, "3f 2f 4f", "in_pos", "in_uv", "in_color")],
                         ctx.buffer(ri.astype("i4").tobytes())).render(moderngl.TRIANGLES)
    for r in sc.get("bow_waves", []) if wakes else []:
        if "indices" not in r:
            continue
        rp = load_bin(d, r["name"] + "_pos.bin", "f4", 3)
        ru = load_bin(d, r["name"] + "_uv.bin", "f4", 2)
        ru2 = load_bin(d, r["name"] + "_uv2.bin", "f4", 2)
        rc = load_bin(d, r["name"] + "_color.bin", "f4", 4)
        ri = load_bin(d, r["name"] + "_idx.bin", "i4", 1)
        bow["u_flow"].value = float(r.get("flow", 0.0))
        rv = ctx.buffer(np.hstack([rp, ru, ru2, rc]).astype("f4").tobytes())
        ctx.vertex_array(bow, [(rv, "3f 2f 2f 4f", "in_pos", "in_uv", "in_uv2", "in_color")],
                         ctx.buffer(ri.astype("i4").tobytes())).render(moderngl.TRIANGLES)
    if wakes and sc.get("mist"):
        # camera-facing quads, as the mist shader's billboard
        right, up = basis[:, 0], basis[:, 1]
        verts = []
        for m in sc["mist"]:
            x, y, z, size, alpha, seed = m[:6]
            kind = m[6] if len(m) > 6 else 0.0
            ctr = np.array([x, z, -y])
            for (cu, cv) in ((0, 0), (1, 0), (1, 1), (0, 0), (1, 1), (0, 1)):
                p = ctr + right * (cu - 0.5) * size + up * (cv - 0.5) * size
                verts.append([p[0], p[1], p[2], cu, 1 - cv, alpha, seed, kind])
        mv = ctx.buffer(np.array(verts, "f4").tobytes())
        ctx.vertex_array(mist, [(mv, "3f 2f 3f", "in_pos", "in_uv", "in_as")]).render(moderngl.TRIANGLES)
    fbo.depth_mask = True
    ctx.disable(moderngl.BLEND)

    ctx.copy_framebuffer(fbo_res, fbo)
    return tonemapped(ctx, tone, resolved, quad, sc, w, h)


def _box_blur(a, r, axis):
    c = np.cumsum(np.pad(a, [(r + 1, r) if k == axis else (0, 0) for k in range(a.ndim)], mode="edge"), axis=axis)
    n = a.shape[axis]
    return (np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, np.arange(0, n), axis=axis)) / (2 * r + 1)


def _blur(a, sigma):
    r = max(1, int(round(sigma * 0.9)))
    for _ in range(3):
        a = _box_blur(_box_blur(a, r, 0), r, 1)
    return a


def glow_texture(ctx, resolved, sc, w, h):
    """Stand-in for Godot's glow (additive, normalized levels): what is brighter than the threshold (linear, before
    the exposure) bleeds out over a few coarse levels."""
    g = sc.get("glow", {})
    if not g.get("enabled"):
        return None
    hdr = np.frombuffer(resolved.read(), dtype="f2").astype("f4").reshape(h, w, 4)[:, :, :3]
    lum = hdr.max(axis=2, keepdims=True)
    bright = hdr * (np.clip(lum - float(g["threshold"]), 0.0, None) * float(g.get("scale", 2.0)) / np.maximum(lum, 1e-4))
    bright = np.minimum(bright, 12.0)
    s = w / 1280.0
    glow = (_blur(bright, 6 * s) + _blur(bright, 14 * s) + _blur(bright, 30 * s)) * (float(g["intensity"]) / 3.0)
    t = ctx.texture((w, h), 4, np.dstack([glow, np.ones((h, w, 1))]).astype("f2").tobytes(), dtype="f2")
    return t


def tonemapped(ctx, tone, resolved, quad, sc, w, h):
    """The resolved HDR frame with the glow added, exposed and tone mapped (Godot's ACES), as an RGB image."""
    glow = glow_texture(ctx, resolved, sc, w, h)
    if glow is None:
        glow = ctx.texture((1, 1), 4, np.zeros(4, "f2").tobytes(), dtype="f2")
    out_tex = ctx.texture((w, h), 4)
    out_fbo = ctx.framebuffer(color_attachments=[out_tex])
    out_fbo.use()
    ctx.disable(moderngl.DEPTH_TEST)
    resolved.use(0)
    glow.use(1)
    tone["u_hdr"].value = 0
    if "u_glow" in tone:
        tone["u_glow"].value = 1
    tone["u_exposure"].value = float(sc["tonemap"]["exposure"])
    tone["u_white"].value = float(sc["tonemap"]["white"])
    ctx.vertex_array(tone, [(quad, "2f", "in_pos")]).render(moderngl.TRIANGLES)
    img = Image.frombytes("RGBA", (w, h), out_fbo.read(components=4)).transpose(Image.FLIP_TOP_BOTTOM)
    return img.convert("RGB")


def compare_image(real, drawn):
    """Side by side: the real shadow (tier H) left, the drawn one (tiers L and M) right, labelled."""
    from PIL import ImageDraw
    w, h = real.size
    out = Image.new("RGB", (2 * w + 8, h), (255, 255, 255))
    out.paste(real, (0, 0))
    out.paste(drawn, (w + 8, 0))
    dr = ImageDraw.Draw(out)
    for x, label in ((10, "real sun shadow on the sea (tier H)"), (w + 18, "drawn boat shadow (tiers L and M)")):
        dr.rectangle([x - 4, 8, x + 7 * len(label), 28], fill=(0, 0, 0))
        dr.text((x, 12), label, fill=(255, 255, 255))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--no-wakes", action="store_true", help="leave the wake ribbons out")
    ap.add_argument("--shadows", default="auto", choices=["auto", "real", "drawn", "none"],
                    help="the boats' shadow on the water: the tier's (auto), the sun's shadow map (real, tier H), "
                         "the drawn shadow (drawn, tiers L and M) or none")
    ap.add_argument("--compare", action="store_true",
                    help="render each shot with the real and the drawn shadow: <shot>.real.png, <shot>.drawn.png "
                         "and <shot>.compare.png side by side")
    ap.add_argument("--faded-slope", action="store_true",
                    help="draw the per-pixel slope of faded waves on every tier (the shaders: tier H only)")
    ap.add_argument("--no-caps", action="store_true", help="leave the whitecaps out")
    ap.add_argument("--suffix", default="", help="added to the output names (e.g. .slope)")
    ap.add_argument("--publish", action="store_true",
                    help="also write JPEG copies to game/tests/previews (the committed previews)")
    ap.add_argument("--strip", help="also compose the shots into one labelled time sequence image NAME")
    ap.add_argument("shots", nargs="*")
    a = ap.parse_args()
    global FADED_SLOPE_ALWAYS, NO_CAPS
    FADED_SLOPE_ALWAYS = a.faded_slope
    NO_CAPS = a.no_caps
    size = tuple(int(x) for x in a.size.split("x"))
    shots = a.shots or sorted(p.name for p in OUT.iterdir() if (p / "scene.json").exists())
    if not shots:
        print("no dumped shots in %s: run tests/water_preview_dump.gd first" % OUT)
        return 1
    ctx = moderngl.create_standalone_context(require=410)
    strip = []
    for s in shots:
        if a.compare:
            imgs = {}
            for mode in ("real", "drawn"):
                imgs[mode] = render(ctx, OUT / s, size, not a.no_wakes, mode)
                path = OUT / ("%s%s.%s.png" % (s, a.suffix, mode))
                imgs[mode].save(path)
                print("wrote", path)
            path = OUT / (s + a.suffix + ".compare.png")
            compare_image(imgs["real"], imgs["drawn"]).save(path)
            print("wrote", path)
            continue
        img = render(ctx, OUT / s, size, not a.no_wakes, a.shadows)
        path = OUT / (s + a.suffix + (".nowake" if a.no_wakes else "") + ".png")
        img.save(path)
        print("wrote", path)
        if a.strip:
            strip.append((s, img))
        if a.publish and not a.strip:
            PUBLISHED.mkdir(exist_ok=True)
            jpg = PUBLISHED / (("" if s.startswith("whitecaps_") else "water_") + s + ".jpg")
            img.save(jpg, quality=88)
            print("wrote", jpg)
    if a.strip and strip:
        out = strip_image(strip)
        path = OUT / (a.strip + ".png")
        out.save(path)
        print("wrote", path)
        if a.publish:
            PUBLISHED.mkdir(exist_ok=True)
            out.save(PUBLISHED / (a.strip + ".jpg"), quality=88)
            print("wrote", PUBLISHED / (a.strip + ".jpg"))
    return 0


def strip_image(frames):
    """Frames two per row, each labelled with its render time from the first (a time sequence)."""
    from PIL import ImageDraw
    w, h = frames[0][1].size
    t0 = json.loads((OUT / frames[0][0] / "scene.json").read_text())["render_time_ms"]
    rows = (len(frames) + 1) // 2
    out = Image.new("RGB", (2 * w + 8, rows * (h + 8) - 8), (255, 255, 255))
    dr = ImageDraw.Draw(out)
    for k, (s, img) in enumerate(frames):
        x, y = (k % 2) * (w + 8), (k // 2) * (h + 8)
        out.paste(img, (x, y))
        t = json.loads((OUT / s / "scene.json").read_text())["render_time_ms"]
        label = "t = %.1f s" % ((t - t0) / 1000.0)
        dr.rectangle([x + 6, y + 6, x + 14 + 7 * len(label), y + 26], fill=(0, 0, 0))
        dr.text((x + 10, y + 10), label, fill=(255, 255, 255))
    return out


if __name__ == "__main__":
    sys.exit(main())
