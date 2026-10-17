#!/usr/bin/env python3
"""Offline preview of the liveries, step 2 (no window): renders the shots dumped by tests/livery_preview_dump.gd.

The boats are drawn as the sail scene paints them: the topsides with shaders/hull_livery.gdshaderinc (colour,
graphic, name and number), the sails with sail_cloth.gdshaderinc and sail_livery.gdshaderinc (cloth, panel colours,
sail numbers on both sides and through the cloth), each boat's text texture, and the other slots in their
(livery) colours; the same files Godot compiles. Lighting, sea and sky are the stand-in of tests/sail_preview.py
(a low sun, a sky ambient, a flat sea, no shadows): for judging the liveries, not the engine's exact colours.

    python3 game/tests/livery_preview.py [--size 1600x900] [--publish] [--dir DIR] [shot ...]

Writes game/generated/livery_preview/<shot>.png and contact.png (with --publish also game/tests/previews/livery_contact.png and
game/tests/previews/livery_*.jpg). Needs numpy, Pillow and moderngl (docs/THIRD_PARTY.md).
"""
import argparse
import json
import re
from pathlib import Path

import moderngl
import numpy as np
from PIL import Image, ImageDraw

import sail_preview as spv

GAME = Path(__file__).resolve().parents[1]
OUT = GAME / "generated" / "livery_preview"
PUBLISHED = GAME / "tests" / "previews"


def inc(name):
    """A shader include with its #include lines resolved (res:// paths)."""
    text = (GAME / "shaders" / name).read_text()
    return re.sub(r'#include "res://shaders/([^"]+)"', lambda m: inc(m.group(1)), text)


VS = """
#version 410
uniform mat4 u_vp;
in vec3 in_pos;
in vec3 in_normal;
in vec4 in_uv;
in float in_port;
in vec4 in_extra;
out vec4 v_extra;
out vec3 v_n;
out vec3 v_w;
out vec4 v_uv;
out float v_port;
flat out float v_side;
uniform int sl_layer_n;
void main() {
    v_n = in_normal;
    v_w = in_pos;
    v_uv = in_uv;
    v_port = in_port;
    v_extra = in_extra;
    v_side = gl_VertexID >= sl_layer_n ? 1.0 : 0.0;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

# the sail preview's daytime light (sun, sky ramp, ambient; sail_preview.LIGHT) and the camera
LIGHT = spv.LIGHT + """
uniform vec3 u_cam;
uniform vec3 u_sun;
vec3 lit(vec3 albedo, vec3 N, vec3 V, float rough, float metal) {
    vec3 L = normalize(u_sun);
    float ndl = max(dot(N, L), 0.0);
    vec3 amb = sky_ambient(N);
    vec3 H = normalize(L + V);
    float shin = 2.0 / max(pow(rough, 4.0), 1e-3) - 2.0;
    float spec = pow(max(dot(N, H), 0.0), shin) * (shin + 8.0) / (8.0 * PI);
    vec3 diff = albedo * (1.0 - metal);
    return diff * (amb + SUN * ndl / PI) + mix(0.04, 0.6, metal) * spec * ndl * SUN * 0.25;
}
"""

BOAT_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
in float v_port;
flat in float v_side;
uniform vec3 u_albedo;
uniform float u_rough;
uniform float u_metal;
out vec4 frag;
void main() {
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_w);
    if (dot(N, V) < 0.0) N = -N;
    vec3 a = u_albedo;
    if (hl_on != 0) a = min(wm_hull_livery(v_uv.zw, step(0.5, v_port)), vec3(0.8));
    frag = vec4(lit(a, N, V, u_rough, u_metal), 1.0);
}
"""

SAIL_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
in float v_port;
flat in float v_side;
uniform vec4 albedo_color;
uniform sampler2D albedo_tex;
uniform vec2 uv_scale;
uniform float weave;
uniform float roughness;
uniform float backlight;
uniform vec4 fibre_color;
uniform float fibre_amount;
uniform vec4 telltale_color;
out vec4 frag;
void main() {
    vec2 UV = v_uv.xy;
    float px = max(fwidth(UV.x), fwidth(UV.y));
    float layers; float stitch; float panel; float fibre; float mark; float pid;
    wm_cloth(UV, v_uv.w, px, layers, stitch, panel, fibre, mark, pid);
    vec3 base = albedo_color.rgb;
    float t_near = 0.0;
    float t_far = 0.0;
    if (sl_on != 0) {
        vec2 pl = wm_cloth_plan(UV);
        base = wm_sail_design(base, pl, pid, px);
        t_near = wm_sail_text(pl, v_side);
        t_far = wm_sail_text(pl, 1.0 - v_side);
    }
    vec3 tex = texture(albedo_tex, UV * uv_scale).rgb;
    vec3 a = min(base * mix(vec3(1.0), tex, weave), vec3(0.8));
    a *= (1.0 - 0.045 * min(layers, 4.0)) * (1.0 - 0.45 * stitch) * (1.0 + 0.06 * (panel - 0.5));
    a = mix(a, fibre_color.rgb, fibre * fibre_amount);
    a = mix(a, sl_text_color, t_near);
    a = mix(a, telltale_color.rgb, mark);
    float rough = clamp(roughness + 0.1 * (panel - 0.5), 0.05, 1.0);
    float trans = backlight * exp(-0.8 * layers) * (1.0 - 0.6 * fibre * fibre_amount) * (1.0 - 0.6 * mark)
        * (1.0 - 0.85 * t_near) * (1.0 - 0.85 * t_far);
    vec3 V = normalize(u_cam - v_w);
    vec3 L = normalize(u_sun);
    vec3 N = normalize(v_n);
    float ndl = dot(N, L);
    float fwd = pow(max(dot(-V, L), 0.0), 4.0);
    vec3 diff = SUN * (max(ndl, 0.0) + max(-ndl, 0.0) * trans * (0.75 + 0.75 * fwd)) / PI;
    vec3 amb = sky_ambient(N);
    vec3 H = normalize(V + L);
    float nh = dot(N, H);
    float nl = max(ndl, 0.0);
    float nv = max(dot(N, V), 1e-4);
    float ia = 1.0 / max(rough, 0.05);
    float shd = (2.0 + ia) * pow(max(1.0 - nh * nh, 0.0), 0.5 * ia) / (2.0 * PI);
    vec3 spec = (0.03 + 0.35 * a) * shd / (4.0 * max(nl + nv - nl * nv, 1e-3)) * nl * SUN;
    frag = vec4(a * (amb + diff) + spec, 1.0);
}
"""


# The baked path (shaders/boat_baked.gdshader, sail_baked.gdshader): the same samples and includes, with a GGX
# stand-in for Godot's PBR and a sky gradient for the reflections, so gloss, scuffs and vinyl edges show.
PBR = """
vec3 srgb(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 sky_dir(vec3 d) {
    float t = clamp(d.y, 0.0, 1.0);
    vec3 c = mix(u_hor, u_zen, pow(t, 0.5));
    return d.y < 0.0 ? u_hor * 0.3 : c;
}
vec3 lit_pbr(vec3 albedo, vec3 N, vec3 V, float rough, float ao) {
    vec3 L = normalize(u_sun);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 1e-4);
    vec3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float a = max(rough * rough, 2e-3);
    float a2 = a * a;
    float dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * dd * dd);
    float k = a * 0.5;
    float vis = 0.25 / ((NdotL * (1.0 - k) + k) * (NdotV * (1.0 - k) + k));
    float F = 0.04 + 0.96 * pow(1.0 - max(dot(L, H), 0.0), 5.0);
    vec3 direct = SUN * NdotL * (albedo / PI * (1.0 - F) + D * vis * F);
    float Fe = 0.04 + (max(1.0 - rough, 0.04) - 0.04) * pow(1.0 - NdotV, 5.0);
    vec3 R = reflect(-V, N);
    vec3 sky_r = mix(sky_dir(R), mix(u_hor, u_zen, 0.5), clamp(rough * 1.3, 0.0, 1.0));
    vec3 amb = sky_ambient(N);
    return direct + ao * (sky_r * Fe * 0.9 + albedo * amb * (1.0 - Fe));
}
"""

BOAT_BAKED_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
in float v_port;
flat in float v_side;
uniform sampler2D albedo_tex;
uniform sampler2D mr_tex;
uniform sampler2D bk_albedo;
uniform sampler2D bk_normal;
uniform sampler2D bk_orm;
uniform vec2 uv_scale;
uniform float roughness;
uniform float bk_detail_mean;
uniform float bk_rough_mean;
uniform int bk_proj;
uniform int bk_maps;
uniform int bk_mask;
uniform sampler2D ns_albedo_tex;
uniform sampler2D ns_mr_tex;
uniform vec2 ns_uv_scale;
uniform float ns_detail_mean;
uniform float ns_rough_mean;
out vec4 frag;
void main() {
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_w);
    if (dot(N, V) < 0.0) N = -N;
    vec2 UV = v_uv.xy * uv_scale;
    vec2 t = v_uv.zw;
    vec3 det = srgb(texture(albedo_tex, UV).rgb) / bk_detail_mean;
    vec4 mr = texture(mr_tex, UV);
    float rough = clamp(mr.g * roughness, 0.0, 1.0);
    float rdet = mr.g / bk_rough_mean;
    float occ = 1.0;
    float flat_k = 1.0;
    vec3 orm = vec3(1.0);
    if (bk_maps != 0) orm = texture(bk_orm, t).rgb;
    if (bk_mask != 0) {
        flat_k = smoothstep(0.35, 0.7, abs(normalize(v_n).y));
        float ns = orm.b * flat_k;
        vec2 uvn = v_uv.xy * ns_uv_scale;
        det = mix(det, srgb(texture(ns_albedo_tex, uvn).rgb) / ns_detail_mean, ns);
        rdet = mix(rdet, texture(ns_mr_tex, uvn).g / ns_rough_mean, ns);
    }
    vec3 a = srgb(texture(bk_albedo, t).rgb) * det;
    if (bk_maps != 0) {
        rough = orm.g * rdet;
        occ = orm.r;
        vec3 nb = texture(bk_normal, t).rgb * 2.0 - 1.0;
        nb = mix(vec3(0.0, 0.0, 1.0), nb, flat_k);
        N = wm_perturb(N, v_w, t, nb, -1.0);
    }
    if (ov_on != 0) {
        vec2 c = wm_ov_hull(v_uv.zw);
        a = mix(a, ov_color * det, c.x);
        a *= 1.0 - 0.12 * c.y;
        rough = mix(rough, 0.24, c.x);
    }
    frag = vec4(lit_pbr(min(a, vec3(0.8)), N, V, clamp(rough, 0.03, 1.0), occ), 1.0);
}
"""

# The boat material (shaders/boat_atlas.gdshader, sail_visuals.md §11.4): the same slot table, tiling atlas, livery
# atlas regions, painted fittings and text, with the GGX stand-in above.
BOAT_ATLAS_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
in float v_port;
flat in float v_side;
in vec4 v_extra;
uniform vec4 slot_color[32];
uniform vec4 slot_pbr[32];
uniform vec4 slot_map[32];
uniform sampler2D tile_color;
uniform sampler2D tile_mr;
uniform sampler2D tile_normal;
uniform vec2 tile_grid;
uniform float tile_inset;
uniform float detail_mean;
uniform float rough_mean;
uniform vec4 deck_tiles;
uniform int bk_on;
uniform sampler2D bk_albedo;
uniform sampler2D bk_normal;
uniform sampler2D bk_orm;
uniform vec4 bk_rect[5];
uniform int tr_on;
uniform vec4 tr_box;
uniform vec4 tr_tex;
out vec4 frag;
vec4 tile_tex(sampler2D s, vec2 uv, float tile) {
    vec2 cell = vec2(mod(tile, tile_grid.x), floor(tile / tile_grid.x));
    vec2 inner = vec2(1.0 - 2.0 * tile_inset);
    vec2 a = (cell + tile_inset + fract(uv) * inner) / tile_grid;
    vec2 g = inner / tile_grid;
    return textureGrad(s, a, dFdx(uv) * g, dFdy(uv) * g);
}
void main() {
    int s = int(v_extra.x + 0.5);
    vec4 sc = slot_color[s];
    vec4 sp = slot_pbr[s];
    vec4 sm = slot_map[s];
    int region = int(sm.x + 0.5);
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_w);
    if (dot(N, V) < 0.0) N = -N;
    vec2 tuv = v_uv.xy * sp.w;
    float tile = sp.z;
    if (region == 2) { tuv = v_uv.xy * deck_tiles.y; tile = deck_tiles.x; }
    vec3 det = srgb(tile_tex(tile_color, tuv, tile).rgb) / detail_mean;
    vec4 mr = tile_tex(tile_mr, tuv, tile);
    float rdet = mr.g / rough_mean;
    vec3 a = sc.rgb * det;
    float rough = sp.x * rdet;
    float occ = 1.0;
    if (bk_on != 0 && region >= 1 && region <= 4) {
        vec2 t = clamp(region == 4 ? v_extra.zw : v_uv.zw, vec2(0.0), vec2(1.0));
        vec4 r = bk_rect[region];
        vec2 at = r.xy + t * r.zw;
        vec3 base = srgb(texture(bk_albedo, at).rgb);
        if (region == 4) {
            a = base * det;
        } else {
            vec3 orm = texture(bk_orm, at).rgb;
            float flat_k = 1.0;
            if (region == 2) {
                flat_k = max(smoothstep(0.35, 0.7, abs(normalize(v_n).y)), sm.w);
                float ns = orm.b * flat_k;
                vec2 nuv = v_uv.xy * deck_tiles.w;
                det = mix(det, srgb(tile_tex(tile_color, nuv, deck_tiles.z).rgb) / detail_mean, ns);
                rdet = mix(rdet, tile_tex(tile_mr, nuv, deck_tiles.z).g / rough_mean, ns);
            }
            a = mix(sc.rgb, base, flat_k) * det;
            rough = mix(sp.x * rdet, orm.g * rdet, flat_k);
            occ = mix(1.0, orm.r, flat_k);
            vec3 nb = texture(bk_normal, at).rgb * 2.0 - 1.0;
            nb = mix(vec3(0.0, 0.0, 1.0), nb, flat_k);
            N = wm_perturb(N, v_w, t, nb, -1.0);
            if (region == 1 && ov_on != 0) {
                vec2 c = wm_ov_hull(v_uv.zw);
                a = mix(a, ov_color * det, c.x);
                a *= 1.0 - 0.12 * c.y;
                rough = mix(rough, 0.24, c.x);
            } else if (region == 3 && tr_on != 0) {
                vec2 q = (v_uv.zw - tr_box.xy) / max(tr_box.zw - tr_box.xy, vec2(1e-6));
                vec2 c = wm_text_cov2(q, tr_tex);
                a = mix(a, ov_color * det, c.x);
                rough = mix(rough, 0.24, c.x);
            }
        }
    } else if (s == 0 && hl_on != 0) {
        a = det * wm_hull_livery(v_uv.zw, step(0.5, v_port));
    }
    vec3 m = tile_tex(tile_normal, tuv, tile).rgb * 2.0 - 1.0;
    m.xy *= sc.a;
    N = wm_perturb(N, v_w, tuv, m, -1.0);
    float metal = sp.y * mr.b;
    vec3 albedo = min(a, vec3(0.8));
    vec3 col = metal > 0.5 ? lit(albedo, N, V, clamp(rough, 0.03, 1.0), metal)
                           : lit_pbr(albedo, N, V, clamp(rough, 0.03, 1.0), occ);
    frag = vec4(col, 1.0);
}
"""

SAIL_BAKED_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
in float v_port;
flat in float v_side;
uniform sampler2D sk_albedo_port;
uniform sampler2D sk_albedo_stbd;
uniform sampler2D sk_normal;
uniform sampler2D sk_orm;
uniform sampler2D sk_detail;
uniform float sk_detail_tile;
uniform float sk_detail_amount;
uniform vec2 sk_shear;
uniform vec4 sk_rect;
out vec4 frag;
void main() {
    vec2 UV = v_uv.xy;
    vec2 p = vec2(UV.x * sk_shear.y, UV.y + UV.x * sk_shear.x);
    vec2 t = vec2((p.x - sk_rect.x) / sk_rect.z, (sk_rect.y - p.y) / sk_rect.w);
    vec3 a = srgb(v_side > 0.5 ? texture(sk_albedo_stbd, vec2(1.0 - t.x, t.y)).rgb : texture(sk_albedo_port, t).rgb);
    vec3 orm = texture(sk_orm, t).rgb;
    vec3 nm = texture(sk_normal, t).rgb * 2.0 - 1.0;
    vec3 dt = texture(sk_detail, vec2(p.x, -p.y) / sk_detail_tile).rgb;
    nm = normalize(vec3(nm.xy + (dt.xy * 2.0 - 1.0) * sk_detail_amount, nm.z));
    a *= mix(1.0, dt.b * 2.0, sk_detail_amount);
    vec2 nr = wm_sn_cov(p, v_side);
    vec2 fr = wm_sn_cov(p, 1.0 - v_side);
    a = mix(a, sn_color, nr.x) * (1.0 - 0.12 * nr.y);
    a = min(a, vec3(0.8));
    float rough = clamp(mix(orm.g, 0.4, nr.x), 0.05, 1.0);
    float trans = orm.b * (1.0 - 0.85 * nr.x) * (1.0 - 0.85 * fr.x);
    vec3 V = normalize(u_cam - v_w);
    vec3 L = normalize(u_sun);
    vec3 N = wm_perturb(normalize(v_n), v_w, p, nm, 1.0);
    float ndl = dot(N, L);
    float fwd = pow(max(dot(-V, L), 0.0), 4.0);
    vec3 diff = SUN * (max(ndl, 0.0) + max(-ndl, 0.0) * trans * (0.75 + 0.75 * fwd)) / PI;
    vec3 amb = sky_ambient(N);
    vec3 H = normalize(V + L);
    float nh = dot(N, H);
    float nl = max(ndl, 0.0);
    float nv = max(dot(N, V), 1e-4);
    float ia = 1.0 / max(rough, 0.05);
    float shd = (2.0 + ia) * pow(max(1.0 - nh * nh, 0.0), 0.5 * ia) / (2.0 * PI);
    vec3 spec = (0.03 + 0.35 * a) * shd / (4.0 * max(nl + nv - nl * nv, 1e-3)) * nl * SUN;
    float Fe = 0.04 + (max(1.0 - rough, 0.04) - 0.04) * pow(1.0 - nv, 5.0);
    vec3 sky_r = mix(sky_dir(reflect(-V, N)), mix(u_hor, u_zen, 0.5), clamp(rough * 1.3, 0.0, 1.0));
    frag = vec4(a * (amb * orm.r * (1.0 - Fe) + diff) + spec + orm.r * sky_r * Fe * 0.9, 1.0);
}
"""

# the class rope set (data_format.md §8.7): the baked braid tile on the rope's uv0 (metres along, the turn round)
ROPE_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
in float v_port;
flat in float v_side;
uniform sampler2D albedo_tex;
uniform sampler2D mr_tex;
uniform sampler2D normal_tex;
uniform vec2 uv_scale;
uniform vec4 albedo_color;
uniform float roughness;
out vec4 frag;
void main() {
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_w);
    if (dot(N, V) < 0.0) N = -N;
    vec2 t = v_uv.xy * uv_scale;
    vec3 a = min(srgb(texture(albedo_tex, t).rgb) * albedo_color.rgb, vec3(0.8));
    vec3 nb = texture(normal_tex, t).rgb * 2.0 - 1.0;
    N = wm_perturb(N, v_w, t, nb, 1.0);
    float rough = clamp(texture(mr_tex, t).g * roughness, 0.05, 1.0);
    frag = vec4(lit(a, N, V, rough, 0.0), 1.0);
}
"""

_images = {}


def image_texture(ctx, path, repeat=False, fallback=(255, 255, 255)):
    """An RGB image file as a mipmapped texture (data as stored; the shaders decode sRGB), cached."""
    key = (path, repeat)
    if key not in _images:
        if path and Path(path).exists():
            img = Image.open(path).convert("RGB")
            t = ctx.texture(img.size, 3, img.tobytes())
        else:
            t = ctx.texture((1, 1), 3, bytes(fallback))
        t.build_mipmaps()
        t.filter = (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
        t.anisotropy = 16.0
        t.repeat_x = t.repeat_y = repeat
        _images[key] = t
    return _images[key]


def detail_path(u, slot):
    """The slot's tiling detail image: the dumped path, else boatgen's texture set by slot."""
    p = u.get("albedo_tex")
    if isinstance(p, str) and Path(p).exists() and p.endswith((".jpg", ".png")):
        return p, u.get("mr_tex")
    sets = {"gelcoat": "orange_peel", "boottop": "orange_peel", "antifouling": "grain", "nonslip": "diamond"}
    s = sets.get(slot, "orange_peel")
    root = GAME.parent / "tools" / "boatgen" / "textures"
    return str(root / f"{s}_color.jpg"), str(root / f"{s}_mr.jpg")


def set_uniforms(prog, values):
    for k, v in values.items():
        if k not in prog or isinstance(v, str):
            continue
        u = prog[k]
        try:
            if isinstance(v, list) and v and isinstance(v[0], list):
                u.value = [tuple(float(x) for x in e[: u.dimension]) for e in v][: u.array_length]
            elif isinstance(v, list) and u.array_length > 1:
                u.value = [float(x) for x in v][: u.array_length]
            elif isinstance(v, list):
                u.value = tuple(float(x) for x in v[: u.dimension])
            elif isinstance(v, bool):
                u.value = int(v)
            else:
                u.value = v
        except Exception as e:  # noqa: BLE001
            print("uniform", k, e)


_text = {}


def text_texture(ctx, path):
    if path not in _text:
        img = Image.open(path).convert("L")
        t = ctx.texture(img.size, 1, img.tobytes())
        t.build_mipmaps()
        t.filter = (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
        t.anisotropy = 8.0
        t.repeat_x = t.repeat_y = False
        _text[path] = t
    return _text[path]


def render(ctx, d, size):
    sc = json.loads((d / "scene.json").read_text())
    w, h = size
    hull_inc = inc("hull_livery.gdshaderinc")
    boat = ctx.program(vertex_shader=VS, fragment_shader="#version 410\n" + LIGHT + hull_inc + BOAT_FS)
    sail = ctx.program(vertex_shader=VS, fragment_shader="#version 410\n" + LIGHT + inc("sail_cloth.gdshaderinc")
                       + inc("sail_livery.gdshaderinc") + SAIL_FS)
    baked_inc = inc("livery_text.gdshaderinc") + inc("livery_baked.gdshaderinc")
    boat_b = ctx.program(vertex_shader=VS, fragment_shader="#version 410\n" + LIGHT + PBR + baked_inc + BOAT_BAKED_FS)
    sail_b = ctx.program(vertex_shader=VS, fragment_shader="#version 410\n" + LIGHT + PBR + baked_inc + SAIL_BAKED_FS)
    rope = ctx.program(vertex_shader=VS, fragment_shader="#version 410\n" + LIGHT + PBR + baked_inc + ROPE_FS)
    atlas = ctx.program(vertex_shader=VS, fragment_shader="#version 410\n" + LIGHT + PBR + hull_inc
                        + inc("livery_baked.gdshaderinc") + BOAT_ATLAS_FS)
    sky = ctx.program(vertex_shader=spv.SKY_VS, fragment_shader="#version 410\n" + spv.LIGHT + spv.SKY_INC + spv.SKY_FS)
    tone = ctx.program(vertex_shader=spv.SKY_VS, fragment_shader=spv.TONE_FS)
    sea_p = ctx.program(vertex_shader=spv.VS, fragment_shader="#version 410\n" + spv.LIGHT + spv.FS)
    light = sc.get("light", spv.DEFAULT_LIGHT)
    for pr in (boat, sail, boat_b, sail_b, rope, atlas, sky, sea_p):
        for k, v in (("u_sun_col", light["sun_color"]), ("u_hor", light["horizon"]), ("u_zen", light["zenith"])):
            if k in pr:
                pr[k].value = tuple(v)
        if "u_ambient" in pr:
            pr["u_ambient"].value = float(light["ambient"])
    sky["u_cloud_cover"].value = float(light["cloud_cover"])
    sky["u_cloud_offset"].value = tuple(light["cloud_offset"])
    eye = np.array(sc["eye"], "f8")
    target = np.array(sc["target"], "f8")
    vp = spv.perspective(sc.get("fov", 50.0), w / h, sc.get("near", 0.3), 3000.0) @ spv.look_at(eye, target)
    vp_b = vp.T.astype("f4").tobytes()
    view = target - eye
    view[1] = 0.0
    view /= np.linalg.norm(view)
    side = np.cross(view, [0.0, 1.0, 0.0])
    sun = -view * 0.35 + side * 0.75 + np.array([0.0, 0.55, 0.0])
    if sc.get("sun") == "back":
        sun = view * 0.8 + side * 0.25 + np.array([0.0, 0.5, 0.0])

    ms = ctx.framebuffer(color_attachments=[ctx.renderbuffer((w, h), 4, samples=4, dtype="f2")],
                         depth_attachment=ctx.depth_renderbuffer((w, h), samples=4))
    hdr = ctx.texture((w, h), 4, dtype="f2")
    resolved = ctx.framebuffer(color_attachments=[hdr])
    ms.use()
    ctx.clear(0.0, 0.0, 0.0, 1.0)
    quad = ctx.buffer(np.array([-1, -1, 1, -1, -1, 1, 1, 1], "f4").tobytes())
    ctx.disable(moderngl.DEPTH_TEST)
    sky["u_inv_vp"].write(np.linalg.inv(vp).T.astype("f4").tobytes())
    sky["u_sun"].value = tuple(sun)
    ctx.vertex_array(sky, [(quad, "2f", "in_pos")]).render(moderngl.TRIANGLE_STRIP)
    ctx.enable(moderngl.DEPTH_TEST)
    sea_p["u_vp"].write(vp_b)
    sea_p["u_cam"].value = tuple(eye)
    sea_p["u_sun"].value = tuple(sun)
    sea_p["u_sea"].value = 1.0
    sea_p["u_sail"].value = 0.0
    sea_p["u_albedo"].value = (0.0, 0.0, 0.0)
    r = 2500.0
    sea = np.array([[eye[0] - r, 0.0, eye[2] - r, 0, 1, 0], [eye[0] + r, 0.0, eye[2] - r, 0, 1, 0],
                    [eye[0] - r, 0.0, eye[2] + r, 0, 1, 0], [eye[0] + r, 0.0, eye[2] + r, 0, 1, 0]], "f4")
    if sc.get("sea", True):
        ctx.vertex_array(sea_p, [(ctx.buffer(sea.tobytes()), "3f 3f", "in_pos", "in_normal")]).render(
            moderngl.TRIANGLE_STRIP)
    for prog in (boat, sail, boat_b, sail_b, rope, atlas):
        prog["u_vp"].write(vp_b)
        prog["u_cam"].value = tuple(eye)
        prog["u_sun"].value = tuple(sun)
    for m in sc["meshes"]:
        v = np.fromfile(d / (m["name"] + "_v.bin"), dtype="f4")
        i = np.fromfile(d / (m["name"] + "_i.bin"), dtype="i4")
        if v.size == 0 or i.size == 0:
            continue
        vb = ctx.buffer(v.tobytes())
        stride = int(m.get("stride", 11))
        fmt = [(vb, "3f 3f 4f 1f 4f", "in_pos", "in_normal", "in_uv", "in_port", "in_extra")] if stride == 15 else \
            [(vb, "3f 3f 4f 1f", "in_pos", "in_normal", "in_uv", "in_port")]
        if m["kind"] == "sail_baked":
            u = m["uniforms"]
            set_uniforms(sail_b, u)
            for unit, (k, rep) in enumerate([("sk_albedo_port", False), ("sk_albedo_stbd", False), ("sk_normal", False),
                                             ("sk_orm", False), ("sk_detail", True)]):
                image_texture(ctx, u.get(k), rep, (128, 128, 255) if k in ("sk_normal", "sk_detail") else (255, 255, 255)).use(unit)
                sail_b[k].value = unit
            text_texture(ctx, d / m["text"]).use(5)
            sail_b["livery_text"].value = 5
            ctx.enable(moderngl.CULL_FACE)
            ctx.front_face = "cw"
            ctx.vertex_array(sail_b, fmt, ctx.buffer(i.tobytes()), skip_errors=True).render(moderngl.TRIANGLES)
            ctx.disable(moderngl.CULL_FACE)
            continue
        if m["kind"] == "boat_atlas":
            u = m["uniforms"]
            set_uniforms(atlas, u)
            for unit, (k, rep, fb) in enumerate([("tile_color", True, (235, 235, 235)), ("tile_mr", True, (255, 204, 255)),
                                                 ("tile_normal", True, (128, 128, 255)),
                                                 ("bk_albedo", False, (255, 255, 255)), ("bk_normal", False, (128, 128, 255)),
                                                 ("bk_orm", False, (255, 255, 255))]):
                image_texture(ctx, u.get(k), rep, fb).use(unit)
                atlas[k].value = unit
            text_texture(ctx, d / m["text"]).use(6)
            atlas["livery_text"].value = 6
            ctx.vertex_array(atlas, fmt, ctx.buffer(i.tobytes()), skip_errors=True).render(moderngl.TRIANGLES)
            continue
        if m["kind"] == "rope":
            u = m["uniforms"]
            set_uniforms(rope, u)
            for unit, (k, fb) in enumerate([("albedo_tex", (255, 255, 255)), ("mr_tex", (255, 220, 0)),
                                            ("normal_tex", (128, 128, 255))]):
                image_texture(ctx, u.get(k), True, fb).use(unit)
                rope[k].value = unit
            ctx.vertex_array(rope, fmt, ctx.buffer(i.tobytes()), skip_errors=True).render(moderngl.TRIANGLES)
            continue
        if m["kind"] == "boat_baked":
            u = m["uniforms"]
            set_uniforms(boat_b, u)
            dp, mp = detail_path(u, m.get("slot", ""))
            image_texture(ctx, dp, True).use(0)
            image_texture(ctx, mp if mp and Path(str(mp)).exists() else None, True, (255, 204, 255)).use(1)
            for unit, k in enumerate(["bk_albedo", "bk_normal", "bk_orm"], start=2):
                image_texture(ctx, u.get(k), False, (128, 128, 255) if k == "bk_normal" else (255, 255, 255)).use(unit)
                boat_b[k].value = unit
            if u.get("bk_mask"):
                np_, nm_ = detail_path({}, "nonslip")
                image_texture(ctx, np_, True).use(6)
                image_texture(ctx, nm_, True).use(7)
                boat_b["ns_albedo_tex"].value = 6
                boat_b["ns_mr_tex"].value = 7
            boat_b["albedo_tex"].value = 0
            boat_b["mr_tex"].value = 1
            text_texture(ctx, d / m["text"]).use(5)
            boat_b["livery_text"].value = 5
            ctx.vertex_array(boat_b, fmt, ctx.buffer(i.tobytes()), skip_errors=True).render(moderngl.TRIANGLES)
            continue
        if m["kind"] == "sail":
            u = m["uniforms"]
            set_uniforms(sail, u)
            spv.cloth_texture(ctx, u.get("albedo_tex")).use(0)
            sail["albedo_tex"].value = 0
            text_texture(ctx, d / m["text"]).use(1)
            sail["livery_text"].value = 1
            ctx.enable(moderngl.CULL_FACE)  # each cloth layer faces its own side
            ctx.front_face = "cw"  # Godot meshes: clockwise front faces
            ctx.vertex_array(sail, fmt, ctx.buffer(i.tobytes()), skip_errors=True).render(moderngl.TRIANGLES)
            ctx.disable(moderngl.CULL_FACE)
            continue
        if m["kind"] == "hull":
            set_uniforms(boat, m["uniforms"])
            text_texture(ctx, d / m["text"]).use(1)
            boat["livery_text"].value = 1
            boat["hl_on"].value = 1
        else:
            boat["hl_on"].value = 0
        boat["u_albedo"].value = tuple(m["albedo"][:3])
        boat["u_rough"].value = float(m.get("rough", 0.5))
        boat["u_metal"].value = float(m.get("metal", 0.0))
        ctx.vertex_array(boat, fmt, ctx.buffer(i.tobytes()), skip_errors=True).render(moderngl.TRIANGLES)
    ctx.copy_framebuffer(resolved, ms)
    out = ctx.framebuffer(color_attachments=[ctx.renderbuffer((w, h), 4)])
    out.use()
    ctx.disable(moderngl.DEPTH_TEST)
    hdr.use(0)
    ctx.texture((1, 1), 4, np.zeros(4, "f2").tobytes(), dtype="f2").use(1)
    tone["u_hdr"].value = 0
    if "u_glow" in tone:
        tone["u_glow"].value = 1
    tone["u_exposure"].value = float(light["exposure"])
    tone["u_white"].value = float(light["white"])
    ctx.vertex_array(tone, [(quad, "2f", "in_pos")]).render(moderngl.TRIANGLE_STRIP)
    img = Image.frombytes("RGBA", (w, h), out.read(components=4)).transpose(Image.FLIP_TOP_BOTTOM).convert("RGB")
    return img, sc.get("note", "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1600x900")
    ap.add_argument("--publish", action="store_true")
    ap.add_argument("--dir", default=None, help="the dump folder to render (default generated/livery_preview; "
                    "the class character set of livery_preview_dump.gd `-- classes` is generated/class_preview)")
    ap.add_argument("shots", nargs="*")
    a = ap.parse_args()
    global OUT
    if a.dir:
        OUT = Path(a.dir).resolve()
    w, h = (int(x) for x in a.size.split("x"))
    names = a.shots or json.loads((OUT / "index.json").read_text())
    ctx = moderngl.create_standalone_context(require=410)
    tiles = []
    for n in names:
        img, note = render(ctx, OUT / n, (w, h))
        img.save(OUT / (n + ".png"))
        print(note)
        tiles.append((n, img))
        if a.publish:
            PUBLISHED.mkdir(parents=True, exist_ok=True)
            img.save(PUBLISHED / f"livery_{n}.jpg", quality=88)
    cols = 3
    tw, th = w // 2, h // 2
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + 18)), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for k, (n, img) in enumerate(tiles):
        x, y = (k % cols) * tw, (k // cols) * (th + 18)
        sheet.paste(img.resize((tw, th), Image.LANCZOS), (x, y + 18))
        dr.text((x + 6, y + 3), n, fill=(230, 230, 230))
    sheet.save(OUT / "contact.png")
    if a.publish:
        # the published sheet: a PNG at a third of the shot size per tile
        small = sheet.resize((sheet.width * 2 // 3, sheet.height * 2 // 3), Image.LANCZOS)
        small.save(PUBLISHED / "livery_contact.png", optimize=True)
        old = PUBLISHED / "livery_contact.jpg"
        if old.exists():
            old.unlink()
    print(f"wrote {len(tiles)} shots and contact.png to {OUT}")


if __name__ == "__main__":
    main()
