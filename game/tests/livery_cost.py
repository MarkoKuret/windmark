#!/usr/bin/env python3
"""Per-pixel cost of the liveries, procedural against baked (WM-081, WM-016.29), offline and headless.

Draws the sails and the hull of dumped preview shots (tests/livery_preview_dump.gd, baked, and with `-- procedural`
the fallback) with the offline preview's programs, which compile the same shader includes as Godot: a depth
pre-pass of the whole boat, then only the measured surfaces with depth test EQUAL (each visible pixel shaded once,
as Godot's opaque pass after its pre-pass), repeated, timed with GL timer queries; pixels counted with an occlusion
query. On the development Mac this is the M1's GPU (the owner's MacBook Air M1 has the same GPU family), through
OpenGL 4.1 on Metal: a proxy for Godot's Metal or Vulkan shaders, good for the ratio, not the absolute time.

    godot --headless --path game -s res://tests/livery_preview_dump.gd -- main_wm7_close jib_wm12_laminate hull_wm7_stbd
    godot --headless --path game -s res://tests/livery_preview_dump.gd -- procedural main_wm7_close jib_wm12_laminate hull_wm7_stbd
    python3 game/tests/livery_cost.py [--size 1920x1080] [--repeat 60]
"""
import argparse
import json
import re
from pathlib import Path

import moderngl
import numpy as np

import livery_preview as lp
import sail_preview as spv

GAME = Path(__file__).resolve().parents[1]
DUMPS = {"procedural": GAME / "generated" / "livery_preview_procedural", "baked": GAME / "generated" / "livery_preview"}
SHOTS = ["main_wm7_close", "jib_wm12_laminate", "hull_wm7_stbd"]

DEPTH_FS = "#version 410\nout vec4 frag;\nvoid main() { frag = vec4(0.0); }\n"

# boat.gdshader's topsides on the procedural livery path with the same light as the baked program: the slot's
# detail albedo and roughness samples, the livery colour, graphic and text (hull_livery.gdshaderinc)
PROC_HULL_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
in float v_port;
flat in float v_side;
uniform sampler2D albedo_tex;
uniform sampler2D mr_tex;
uniform vec2 uv_scale;
uniform float roughness;
out vec4 frag;
void main() {
    vec3 N = normalize(v_n);
    vec3 V = normalize(u_cam - v_w);
    if (dot(N, V) < 0.0) N = -N;
    vec2 UV = v_uv.xy * uv_scale;
    vec3 a = srgb(texture(albedo_tex, UV).rgb) / hl_tex_mean * wm_hull_livery(v_uv.zw, step(0.5, v_port));
    float rough = clamp(texture(mr_tex, UV).g * roughness, 0.03, 1.0);
    frag = vec4(lit_pbr(min(a, vec3(0.8)), N, V, rough, 1.0), 1.0);
}
"""


def programs(ctx):
    inc = lp.inc
    head = "#version 410\n" + lp.LIGHT
    baked = inc("livery_text.gdshaderinc") + inc("livery_baked.gdshaderinc")
    return {
        "hull": ctx.program(vertex_shader=lp.VS, fragment_shader=head + lp.PBR + inc("hull_livery.gdshaderinc")
                            + "uniform float hl_tex_mean;\n" + PROC_HULL_FS),
        "sail": ctx.program(vertex_shader=lp.VS, fragment_shader=head + inc("sail_cloth.gdshaderinc")
                            + inc("sail_livery.gdshaderinc") + lp.SAIL_FS),
        "boat_baked": ctx.program(vertex_shader=lp.VS, fragment_shader=head + lp.PBR + baked + lp.BOAT_BAKED_FS),
        "sail_baked": ctx.program(vertex_shader=lp.VS, fragment_shader=head + lp.PBR + baked + lp.SAIL_BAKED_FS),
        "boat_atlas": ctx.program(vertex_shader=lp.VS, fragment_shader=head + lp.PBR + inc("hull_livery.gdshaderinc")
                                  + inc("livery_baked.gdshaderinc") + lp.BOAT_ATLAS_FS),
        "depth": ctx.program(vertex_shader=lp.VS, fragment_shader=DEPTH_FS),
    }


def bind(ctx, prog, kind, m, d):
    u = m.get("uniforms", {})
    lp.set_uniforms(prog, u)
    if kind == "sail":
        spv.cloth_texture(ctx, u.get("albedo_tex")).use(0)
        prog["albedo_tex"].value = 0
    elif kind == "sail_baked":
        for unit, k in enumerate(["sk_albedo_port", "sk_albedo_stbd", "sk_normal", "sk_orm", "sk_detail"]):
            lp.image_texture(ctx, u.get(k), k == "sk_detail").use(unit)
            prog[k].value = unit
    elif kind == "boat_baked":
        dp, mp = lp.detail_path(u, m.get("slot", ""))
        lp.image_texture(ctx, dp, True).use(0)
        lp.image_texture(ctx, mp, True).use(1)
        prog["albedo_tex"].value = 0
        prog["mr_tex"].value = 1
        for unit, k in enumerate(["bk_albedo", "bk_normal", "bk_orm"], start=2):
            lp.image_texture(ctx, u.get(k), False).use(unit)
            prog[k].value = unit
    elif kind == "boat_atlas":
        for unit, k in enumerate(["tile_color", "tile_mr", "tile_normal", "bk_albedo", "bk_normal", "bk_orm"]):
            lp.image_texture(ctx, u.get(k), k.startswith("tile_")).use(unit)
            prog[k].value = unit
        lp.text_texture(ctx, d / m["text"]).use(6)
        prog["livery_text"].value = 6
        return
    if "livery_text" in prog:
        lp.text_texture(ctx, d / m["text"]).use(5)
        prog["livery_text"].value = 5
    if kind == "hull":
        dp, mp = lp.detail_path(u, "gelcoat")
        lp.image_texture(ctx, dp, True).use(0)
        lp.image_texture(ctx, mp, True).use(1)
        prog["albedo_tex"].value = 0
        prog["mr_tex"].value = 1


def fmt(m, vb):
    """The dumped vertex layout (tests/livery_preview_dump.gd: 15 floats, or 11 in older dumps)."""
    if int(m.get("stride", 11)) == 15:
        return [(vb, "3f 3f 4f 1f 4f", "in_pos", "in_normal", "in_uv", "in_port", "in_extra")]
    return [(vb, "3f 3f 4f 1f", "in_pos", "in_normal", "in_uv", "in_port")]


def measure(ctx, P, d, size, repeat):
    sc = json.loads((d / "scene.json").read_text())
    w, h = size
    eye = np.array(sc["eye"], "f8")
    target = np.array(sc["target"], "f8")
    vp = spv.perspective(sc.get("fov", 50.0), w / h, 0.3, 3000.0) @ spv.look_at(eye, target)
    vp_b = vp.T.astype("f4").tobytes()
    light = spv.DEFAULT_LIGHT
    for pr in P.values():
        pr["u_vp"].write(vp_b)
        for k, v in (("u_cam", eye), ("u_sun", (0.3, 0.6, 0.7)), ("u_sun_col", light["sun_color"]),
                     ("u_hor", light["horizon"]), ("u_zen", light["zenith"])):
            if k in pr:
                pr[k].value = tuple(v)
        if "u_ambient" in pr:
            pr["u_ambient"].value = 1.0
    fbo = ctx.framebuffer(color_attachments=[ctx.renderbuffer((w, h), 4, dtype="f2")],
                          depth_attachment=ctx.depth_renderbuffer((w, h)))
    fbo.use()
    ctx.clear(0, 0, 0, 1)
    ctx.enable(moderngl.DEPTH_TEST)
    ctx.depth_func = "<"
    meshes = []
    for m in sc["meshes"]:
        v = np.fromfile(d / (m["name"] + "_v.bin"), dtype="f4")
        i = np.fromfile(d / (m["name"] + "_i.bin"), dtype="i4")
        if v.size == 0 or i.size == 0:
            continue
        vb, ib = ctx.buffer(v.tobytes()), ctx.buffer(i.tobytes())
        meshes.append((m, vb, ib))
        ctx.vertex_array(P["depth"], fmt(m, vb), ib, skip_errors=True).render()
    out = {}
    ctx.depth_func = "=="
    # sails, and the topsides (the hull's gelcoat surface, the one the procedural livery paints)
    for group, kinds in (("sails", ("sail", "sail_baked")), ("tops", ("hull", "boat_baked", "boat_atlas"))):
        sel = [(m, vb, ib) for m, vb, ib in meshes if m["kind"] in kinds
               and (group != "tops" or (m["node"] == "hull" and m.get("slot", "gelcoat") == "gelcoat"))]
        if not sel:
            continue
        vaos = []
        for m, vb, ib in sel:
            prog = P[m["kind"]]
            vaos.append((m, prog, ctx.vertex_array(prog, fmt(m, vb), ib, skip_errors=True)))
        qs = ctx.query(samples=True)
        with qs:
            for m, prog, vao in vaos:
                bind(ctx, prog, m["kind"], m, d)
                vao.render()
        pixels = qs.samples
        for m, prog, vao in vaos:      # warm up
            bind(ctx, prog, m["kind"], m, d)
            vao.render()
        ctx.finish()
        q = ctx.query(time=True)
        with q:
            for _ in range(repeat):
                for m, prog, vao in vaos:
                    bind(ctx, prog, m["kind"], m, d)
                    vao.render()
        ctx.finish()
        ms = q.elapsed / 1e6 / repeat
        out[group] = {"ms": ms, "pixels": pixels, "ns_per_px": 1e6 * ms / max(pixels, 1)}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--repeat", type=int, default=60)
    a = ap.parse_args()
    size = tuple(int(x) for x in a.size.split("x"))
    ctx = moderngl.create_standalone_context(require=410)
    P = programs(ctx)
    print(f"GPU: {ctx.info['GL_RENDERER']}, {size[0]}x{size[1]}, {a.repeat} repeats, visible pixels shaded once")
    print(f"{'shot':22s} {'surface':6s} {'path':11s} {'pixels':>9s} {'ms/frame':>9s} {'ns/px':>7s}")
    res = {}
    for shot in SHOTS:
        for path, root in DUMPS.items():
            d = root / shot
            if not (d / "scene.json").exists():
                print(f"{shot}: no {path} dump (see the module notes)")
                continue
            for group, r in measure(ctx, P, d, size, a.repeat).items():
                res[(shot, group, path)] = r
                print(f"{shot:22s} {group:6s} {path:11s} {r['pixels']:9d} {r['ms']:9.3f} {r['ns_per_px']:7.3f}")
    for (shot, group, path), r in res.items():
        if path == "baked" and (shot, group, "procedural") in res:
            p = res[(shot, group, "procedural")]
            print(f"{shot} {group}: baked costs {r['ns_per_px'] / p['ns_per_px']:.2f} of the procedural per pixel")
    # the shaders' size: sampler reads and source lines of the fragment paths
    def count(src):
        body = re.sub(r"//[^\n]*", "", src)
        return body.count("texture("), len([ln for ln in body.splitlines() if ln.strip()])
    for name, src in (("sail.gdshader + sail_cloth + sail_livery (procedural)",
                       lp.inc("sail_cloth.gdshaderinc") + lp.inc("sail_livery.gdshaderinc") + lp.SAIL_FS),
                      ("sail_baked.gdshader + livery_baked", lp.inc("livery_baked.gdshaderinc") + lp.SAIL_BAKED_FS)):
        t, n = count(src)
        print(f"{name}: {t} texture reads in the source, {n} lines")


if __name__ == "__main__":
    main()
