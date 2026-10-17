#!/usr/bin/env python3
"""Offline preview of the venue land and the course, step 2 (no window): renders the shots dumped by
tests/course_preview_dump.gd.

The water, wakes and sky are drawn as tests/water_preview.py draws them (its shaders and lighting stand-in are
reused), with the sea overlays (lines and circles, water_render.md section 6) mixed in as the Godot water shader
does. The land uses the shared land_common.gdshaderinc on its baked vertex colours; props, marks, boats and flags
are lit vertex colours; the guides are unshaded. Colours are close to, not identical with, the engine's.

    python3 game/tests/course_preview.py [--size 1280x720] [--publish] [shot ...]

Writes game/generated/course_preview/<shot>.png (with --publish also game/tests/previews/course_<shot>.jpg).
Needs numpy, Pillow and moderngl (docs/THIRD_PARTY.md).
"""
import argparse
import json
import sys
from pathlib import Path

import moderngl
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import water_preview as wp  # noqa: E402

GAME = Path(__file__).resolve().parents[1]
OUT = GAME / "generated" / "course_preview"
PUBLISHED = GAME / "tests" / "previews"
LAND_INC = (GAME / "scenes" / "venue" / "land_common.gdshaderinc").read_text()
BOAT_INC = (GAME / "scenes" / "course" / "course_boat_common.gdshaderinc").read_text()

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
#if TIER >= 2
    vec2 g = wm_faded_slope(v_local, v_spacing, px) * v_expo;
    n_geo = normalize(n_geo + vec3(-g.x, 0.0, g.y));
#endif
    WmSurface S = wm_surface(v_local, v_eta, n_geo, view, dist, px, vec2(0.0), v_land);
#ifdef WM_WHITECAPS
    wm_apply_caps(S, v_local, px, v_expo, dist, n_geo);
#endif
    vec4 ov = wm_overlays(v_local, dist, view.y, v_eta, u_cam.y - (v_wpos.y - v_eta));
    vec3 albedo = mix(S.albedo, ov.rgb * 0.8, ov.a);
    vec3 emission = mix(S.emission, ov.rgb * 0.35, ov.a);
    float rough = mix(S.roughness, 0.5, ov.a);
    vec3 c = shade(albedo, rough, S.specular, S.normal, view) + emission;
    frag = vec4(fogged(c, v_wpos), 1.0);
}
"""

MESH_VS = """
#version 410
uniform mat4 u_vp;
in vec3 in_pos;
in vec3 in_normal;
in vec4 in_color;
in vec3 in_opos;
in vec3 in_onormal;
out vec3 v_n;
out vec3 v_wpos;
out vec4 v_col;
out vec3 v_opos;
out vec3 v_on;
void main() {
    v_n = in_normal;
    v_opos = in_opos;
    v_on = in_onormal;
    v_wpos = in_pos;
    v_col = in_color;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

MESH_FS = """
in vec3 v_n;
in vec3 v_wpos;
in vec4 v_col;
in vec3 v_opos;
in vec3 v_on;
uniform int u_kind;      // 0 prop (vertex colour), 1 land, 2 unshaded, 3 albedo, 4 boat
uniform vec3 u_albedo;
uniform float u_rough;
uniform float u_bare;
out vec4 frag;
void main() {
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_wpos);
    if (dot(N, V) < 0.0 && u_kind != 1) N = -N;
    vec3 c;
    if (u_kind == 2) {
        c = v_col.rgb * 1.2;
    } else if (u_kind == 1) {
        vec3 alb = wm_land_albedo(v_col.rgb, v_wpos, N.y, length(u_cam - v_wpos), u_bare);
        c = shade(alb, wm_land_roughness(v_col.a), 0.35, N, V);
    } else if (u_kind == 4) {
        vec3 alb;
        float rough;
        wm_cb_surface(v_col.rgb, v_opos, normalize(v_on), length(u_cam - v_wpos), alb, rough);
        c = shade(alb, rough, 0.5, N, V);
    } else if (u_kind == 3) {
        c = shade(u_albedo, u_rough, 0.5, N, V);
    } else {
        c = shade(v_col.rgb, u_rough, 0.5, N, V);
    }
    frag = vec4(fogged(c, v_wpos), 1.0);
}
"""


def render(ctx, d, size):
    sc = json.loads((d / "scene.json").read_text())
    w, h = size
    tier = {"L": 1, "M": 2, "H": 3}[sc["tier"]]
    hdr = wp.header(tier, sc["detail_layers"])
    sky_inc = wp.inc("sky_common.gdshaderinc")
    wake_inc = wp.inc("wake_common.gdshaderinc")
    cam = sc["camera"]
    basis = np.array(cam["basis"]).T
    origin = np.array(cam["origin"])
    view = np.eye(4)
    view[:3, :3] = basis.T
    view[:3, 3] = -basis.T @ origin
    proj = wp.perspective(cam["fov"], w / h, max(cam["near"], 0.3), cam["far"])
    vp = proj @ view
    vp_bytes = vp.T.astype("f4").tobytes()
    inv_vp = np.linalg.inv(vp).T.astype("f4").tobytes()
    common = {
        "u_cam": tuple(origin),
        "u_cloud_cover": float(sc["sky"].get("cloud_cover", 0.3)),
        "u_cloud_offset": tuple(sc["sky"].get("cloud_offset", [0.0, 0.0])),
        **wp.fog_uniforms(sc["fog"]),
        "u_ambient": float(sc["ambient_energy"]),
    }
    water = ctx.program(vertex_shader=hdr + wp.WATER_VS, fragment_shader=hdr + sky_inc + wp.LIGHTING + WATER_FS)
    wake = ctx.program(vertex_shader=hdr + wake_inc + wp.WAKE_VS,
                       fragment_shader=hdr + sky_inc + wp.LIGHTING + wake_inc + wp.WAKE_FS)
    mesh = ctx.program(vertex_shader=MESH_VS, fragment_shader=hdr + sky_inc + wp.LIGHTING + LAND_INC + BOAT_INC + MESH_FS)
    sky = ctx.program(vertex_shader=wp.SKY_VS, fragment_shader=hdr + sky_inc + wp.LIGHTING + wp.SKY_FS)
    tone = ctx.program(vertex_shader=wp.SKY_VS, fragment_shader=wp.TONEMAP_FS)

    detail = wp.texture_from_png(ctx, d / "detail.png", 4)
    foam = wp.texture_from_png(ctx, d / "foam.png", 3)
    caps = wp.texture_from_png(ctx, d / "caps.png", 4)
    if sc["exposure"]:
        e = np.fromfile(d / "expo.bin", dtype="f4")
        expo = ctx.texture((sc["exposure"]["nx"], sc["exposure"]["ny"]), 1, e.tobytes(), dtype="f4")
    else:
        expo = ctx.texture((2, 2), 1, np.ones(4, dtype="f4").tobytes(), dtype="f4")
    expo.filter = (moderngl.NEAREST, moderngl.NEAREST)
    # the venue's land-effect speed factor (water_render.md §4.3); without it the sampler would read another unit
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
    for p in (water, wake, mesh, sky):
        wp.set_uniforms(p, sc["water"])
        for k, v in common.items():
            wp.set_if(p, k, v)
        for name, (_, unit) in units.items():
            wp.set_if(p, name, unit)
        if "u_vp" in p:
            p["u_vp"].write(vp_bytes)
    wp.set_uniforms(wake, sc["wake_uniforms"])
    wp.set_uniforms(sky, {k: v for k, v in sc["sky"].items() if k in ("sky_horizon", "sky_zenith", "sun_dir", "sun_color")})
    sky["u_inv_vp"].write(inv_vp)
    water["u_sea_pos"].value = tuple(sc["sea_position"])

    color_rb = ctx.renderbuffer((w, h), 4, samples=4, dtype="f2")
    depth_rb = ctx.depth_renderbuffer((w, h), samples=4)
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
    ctx.front_face = "cw"
    pos = wp.load_bin(d, "grid_pos.bin", "f4", 3)
    uv = wp.load_bin(d, "grid_uv.bin", "f4", 2)
    idx = wp.load_bin(d, "grid_idx.bin", "i4", 1)
    vbo = ctx.buffer(np.hstack([pos, uv]).astype("f4").tobytes())
    ctx.vertex_array(water, [(vbo, "3f 2f", "in_pos", "in_uv")], ctx.buffer(idx.astype("i4").tobytes())).render(
        moderngl.TRIANGLES)

    kinds = {"prop": 0, "land": 1, "unshaded": 2, "albedo": 3, "boat": 4}
    for m in sc["meshes"]:
        mp = wp.load_bin(d, m["name"] + "_pos.bin", "f4", 3)
        mn = wp.load_bin(d, m["name"] + "_normal.bin", "f4", 3)
        mi = wp.load_bin(d, m["name"] + "_idx.bin", "i4", 1)
        if m.get("color"):
            mc = wp.load_bin(d, m["name"] + "_color.bin", "f4", 4)
        else:
            mc = np.ones((mp.shape[0], 4), dtype="f4")
        mesh["u_kind"].value = kinds[m["kind"]]
        mesh["u_albedo"].value = tuple(m["albedo"][:3])
        mesh["u_rough"].value = float(m.get("roughness", 0.6))
        if "u_bare" in mesh:
            mesh["u_bare"].value = float(m.get("bare_rock", 1.0))
        if m["kind"] == "land":
            ctx.enable(moderngl.CULL_FACE)
        else:
            ctx.disable(moderngl.CULL_FACE)
        if m["kind"] == "boat":
            mo = wp.load_bin(d, m["name"] + "_opos.bin", "f4", 3)
            mon = wp.load_bin(d, m["name"] + "_onormal.bin", "f4", 3)
        else:
            mo, mon = mp, mn
        vb = ctx.buffer(np.hstack([mp, mn, mc, mo, mon]).astype("f4").tobytes())
        ctx.vertex_array(mesh, [(vb, "3f 3f 4f 3f 3f", "in_pos", "in_normal", "in_color", "in_opos", "in_onormal")],
                         ctx.buffer(mi.astype("i4").tobytes())).render(moderngl.TRIANGLES)
    ctx.disable(moderngl.CULL_FACE)

    ctx.enable(moderngl.BLEND)
    ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA
    ctx.depth_mask = False
    for r in sc["wakes"]:
        if "indices" not in r:
            continue
        rp = wp.load_bin(d, r["name"] + "_pos.bin", "f4", 3)
        ru = wp.load_bin(d, r["name"] + "_uv.bin", "f4", 2)
        rc = wp.load_bin(d, r["name"] + "_color.bin", "f4", 4)
        ri = wp.load_bin(d, r["name"] + "_idx.bin", "i4", 1)
        rv = ctx.buffer(np.hstack([rp, ru, rc]).astype("f4").tobytes())
        ctx.vertex_array(wake, [(rv, "3f 2f 4f", "in_pos", "in_uv", "in_color")],
                         ctx.buffer(ri.astype("i4").tobytes())).render(moderngl.TRIANGLES)
    ctx.depth_mask = True
    ctx.disable(moderngl.BLEND)

    ctx.copy_framebuffer(fbo_res, fbo)
    return wp.tonemapped(ctx, tone, resolved, quad, sc, w, h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--publish", action="store_true", help="also write JPEG copies to game/tests/previews")
    ap.add_argument("shots", nargs="*")
    a = ap.parse_args()
    size = tuple(int(x) for x in a.size.split("x"))
    shots = a.shots or sorted(p.name for p in OUT.iterdir() if (p / "scene.json").exists())
    if not shots:
        print("no dumped shots in %s: run tests/course_preview_dump.gd first" % OUT)
        return 1
    ctx = moderngl.create_standalone_context(require=410)
    for s in shots:
        img = render(ctx, OUT / s, size)
        path = OUT / (s + ".png")
        img.save(path)
        print("wrote", path)
        if a.publish:
            PUBLISHED.mkdir(exist_ok=True)
            jpg = PUBLISHED / ("course_" + s + ".jpg")
            img.save(jpg, quality=88)
            print("wrote", jpg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
