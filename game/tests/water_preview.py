#!/usr/bin/env python3
"""Offline preview of the water, step 2 (no window): renders the shots dumped by tests/water_preview_dump.gd.

The water, wake and sky colours come from the same shader functions Godot runs (shaders/sea_common.gdshaderinc,
sky_common.gdshaderinc, wake_common.gdshaderinc), compiled here as GLSL 4.1 on an offscreen OpenGL context, with
the uniforms, meshes and textures Godot computed. Only the lighting model around them is a stand-in for Godot's
Forward+ (GGX sun specular, Schlick sky reflection, Lambert, exponential fog, Godot's ACES curve), so colours are
close to, not identical with, the engine's. Boats are drawn flat-lit from their imported meshes.

    python3 game/tests/water_preview.py [--size 1280x720] [--no-wakes] [--publish] [shot ...]

Writes game/generated/water_preview/<shot>.png (with --publish also game/tests/previews/water_<shot>.jpg). Needs numpy, Pillow and moderngl (docs/THIRD_PARTY.md).
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


def inc(name):
    return (SHADERS / name).read_text()


SAMPLERS = """
uniform sampler2D expo_tex;
uniform sampler2D land_tex;
uniform sampler2D detail_tex;
uniform sampler2D foam_tex;
uniform sampler2D wake_tex;
"""

LIGHTING = """
uniform vec3 u_cam;
uniform float u_cloud_cover;
uniform vec2 u_cloud_offset;
uniform float u_fog_density;
uniform vec3 u_fog_color;
uniform float u_ambient;

const float WM_PI = 3.14159265;

vec3 env_sky(vec3 d) {
    return wm_sky_color(d, normalize(sun_dir), sky_horizon, sky_zenith, sun_color, u_cloud_cover, u_cloud_offset, 0.0);
}

// Stand-in for Godot's PBR: F0 = 0.16 specular^2, GGX with alpha = roughness^2, Schlick sky reflection.
vec3 shade(vec3 albedo, float rough, float spec, vec3 N, vec3 V) {
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
    vec3 direct = sun_color * NdotL * (albedo * (1.0 - F) + WM_PI * D * vis * F);
    float Fe = f0 + (max(1.0 - rough, f0) - f0) * pow(1.0 - NdotV, 5.0);
    vec3 R = reflect(-V, N);
    vec3 refl = env_sky(R) * Fe;
    vec3 amb = albedo * mix(sky_horizon, sky_zenith, 0.5) * u_ambient * (1.0 - Fe);
    return direct + refl + amb;
}

vec3 fogged(vec3 c, vec3 wpos) {
    float f = 1.0 - exp(-u_fog_density * length(u_cam - wpos));
    return mix(c, u_fog_color, f);
}
"""


def header(tier, layers):
    return f"#version 410\n#define TIER {tier}\n#define WM_DETAIL_LAYERS {layers}\n" + SAMPLERS + inc("sea_common.gdshaderinc")


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
#if TIER >= 2
    float px = max(length(fwidth(v_local)), 1e-3);
    vec2 g = wm_faded_slope(v_local, v_spacing, px) * v_expo;
    n_geo = normalize(n_geo + vec3(-g.x, 0.0, g.y));
#endif
    WmSurface S = wm_surface(v_local, v_eta, n_geo, view, dist, vec2(0.0), v_land);
    vec3 c = shade(S.albedo, S.roughness, S.specular, S.normal, view) + S.emission;
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
out vec3 v_wpos;
void main() {
    v_wpos = wm_wake_drape(in_pos, u_cam, grid_q, grid_segments);
    v_uv = in_uv;
    v_a = in_color.a;
    v_c = in_color.r;
    gl_Position = u_vp * vec4(v_wpos, 1.0);
}
"""

WAKE_FS = """
in vec2 v_uv;
in float v_a;
in float v_c;
in vec3 v_wpos;
out vec4 frag;
void main() {
    float a = wm_wake_alpha(v_uv, v_c, v_a, texture(foam_tex, v_uv * vec2(1.5, 2.0)).r, texture(foam_tex, v_uv * vec2(0.6, 0.7) + 0.37).g);
    vec3 V = normalize(u_cam - v_wpos);
    vec3 c = shade(col_foam, 0.6, 0.3, vec3(0.0, 1.0, 0.0), V);
    frag = vec4(fogged(c, v_wpos), a);
}
"""

BOAT_VS = """
#version 410
uniform mat4 u_vp;
in vec3 in_pos;
in vec3 in_normal;
out vec3 v_n;
out vec3 v_wpos;
void main() {
    v_n = in_normal;
    v_wpos = in_pos;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

BOAT_FS = """
in vec3 v_n;
in vec3 v_wpos;
uniform vec3 u_albedo;
out vec4 frag;
void main() {
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_wpos);
    if (dot(N, V) < 0.0) N = -N;
    vec3 c = shade(u_albedo, 0.5, 0.5, N, V);
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
void main() {
    vec3 c = texture(u_hdr, v_ndc * 0.5 + 0.5).rgb * u_exposure;
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


def render(ctx, d, size, wakes=True):
    sc = json.loads((d / "scene.json").read_text())
    w, h = size
    tier = {"L": 1, "M": 2, "H": 3}[sc["tier"]]
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
        "u_fog_density": float(sc["fog"]["density"]),
        "u_fog_color": tuple(sc["fog"]["color"][:3]),
        "u_ambient": float(sc["ambient_energy"]),
    }

    water = ctx.program(vertex_shader=hdr_inc + WATER_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + WATER_FS)
    wake = ctx.program(vertex_shader=hdr_inc + wake_inc + WAKE_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + wake_inc + WAKE_FS)
    boat = ctx.program(vertex_shader=BOAT_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + BOAT_FS)
    sky = ctx.program(vertex_shader=SKY_VS, fragment_shader=hdr_inc + sky_inc + LIGHTING + SKY_FS)
    tone = ctx.program(vertex_shader=SKY_VS, fragment_shader=TONEMAP_FS)

    # textures shared by the water and the wakes
    detail = texture_from_png(ctx, d / "detail.png", 4)
    foam = texture_from_png(ctx, d / "foam.png", 3)
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
             "land_tex": (land, 4)}
    for tex, unit in units.values():
        tex.use(unit)

    for p in (water, wake, boat, sky):
        set_uniforms(p, sc["water"])
        for k, v in common.items():
            set_if(p, k, v)
        for name, (_, unit) in units.items():
            set_if(p, name, unit)
        if "u_vp" in p:
            p["u_vp"].write(vp_bytes)
    set_uniforms(wake, sc["wake_uniforms"])
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
    for b in sc["boat"]:
        if "normal" not in b or "indices" not in b:
            continue
        bp = load_bin(d, b["name"] + "_pos.bin", "f4", 3)
        bn = load_bin(d, b["name"] + "_normal.bin", "f4", 3)
        bi = load_bin(d, b["name"] + "_idx.bin", "i4", 1)
        boat["u_albedo"].value = tuple(b["albedo"][:3])
        bv = ctx.buffer(np.hstack([bp, bn]).astype("f4").tobytes())
        ctx.vertex_array(boat, [(bv, "3f 3f", "in_pos", "in_normal")], ctx.buffer(bi.astype("i4").tobytes())).render(
            moderngl.TRIANGLES)

    ctx.enable(moderngl.BLEND)
    ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA
    fbo.depth_mask = False  # the ribbons do not write depth (depth_draw_never)
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
    fbo.depth_mask = True
    ctx.disable(moderngl.BLEND)

    ctx.copy_framebuffer(fbo_res, fbo)
    out_tex = ctx.texture((w, h), 4)
    out_fbo = ctx.framebuffer(color_attachments=[out_tex])
    out_fbo.use()
    ctx.disable(moderngl.DEPTH_TEST)
    resolved.use(0)
    tone["u_hdr"].value = 0
    tone["u_exposure"].value = float(sc["tonemap"]["exposure"])
    tone["u_white"].value = float(sc["tonemap"]["white"])
    ctx.vertex_array(tone, [(quad, "2f", "in_pos")]).render(moderngl.TRIANGLES)
    img = Image.frombytes("RGBA", (w, h), out_fbo.read(components=4)).transpose(Image.FLIP_TOP_BOTTOM)
    return img.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--no-wakes", action="store_true", help="leave the wake ribbons out")
    ap.add_argument("--publish", action="store_true",
                    help="also write JPEG copies to game/tests/previews (the committed previews)")
    ap.add_argument("shots", nargs="*")
    a = ap.parse_args()
    size = tuple(int(x) for x in a.size.split("x"))
    shots = a.shots or sorted(p.name for p in OUT.iterdir() if (p / "scene.json").exists())
    if not shots:
        print("no dumped shots in %s: run tests/water_preview_dump.gd first" % OUT)
        return 1
    ctx = moderngl.create_standalone_context(require=410)
    for s in shots:
        img = render(ctx, OUT / s, size, not a.no_wakes)
        path = OUT / (s + (".nowake" if a.no_wakes else "") + ".png")
        img.save(path)
        print("wrote", path)
        if a.publish:
            PUBLISHED.mkdir(exist_ok=True)
            jpg = PUBLISHED / ("water_" + s + ".jpg")
            img.save(jpg, quality=88)
            print("wrote", jpg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
