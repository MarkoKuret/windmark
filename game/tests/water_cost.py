#!/usr/bin/env python3
"""GPU cost of the sea surface with and without the whitecaps (water_render.md §4.4, §7), offline and headless.

Draws the sea grid of dumped preview shots (tests/water_preview_dump.gd) with the offline preview's water program,
which compiles the same shader include as Godot (sea_common.gdshaderinc), once with WM_WHITECAPS and once without:
a depth pre-pass of the grid, then the shading pass with depth test EQUAL (each visible water pixel shaded once,
as Godot's opaque pass after its pre-pass), one finished frame per repetition, the median wall time; water pixels
counted with an occlusion query. On the development Mac this is the M1's GPU through OpenGL 4.1 on Metal: a proxy for Godot's
Metal or Vulkan shaders, good for the ratio, not the absolute time.

    godot --headless --path game -s res://tests/water_preview_dump.gd -- whitecaps
    python3 game/tests/water_cost.py [--size 1280x800] [--repeat 100] [--tier L|M|H] [shot ...]
"""
import argparse
import json
import sys
import time
from pathlib import Path

import moderngl
import numpy as np

import water_preview as wp

GAME = Path(__file__).resolve().parents[1]
SHOTS = ["whitecaps_24kn_chase", "whitecaps_12kn_chase"]
DEPTH_FS = "out vec4 frag;\nvoid main() { frag = vec4(0.0); }\n"


TIER = None   # --tier: draw the shot with another tier's shader (L, M, H)


def programs(ctx, sc, caps):
    wp.NO_CAPS = not caps
    tier = {"L": 1, "M": 2, "H": 3}[TIER or sc["tier"]]
    hdr = wp.header(tier, {1: 2, 2: 3, 3: 4}[tier])
    fs = hdr + wp.inc("sky_common.gdshaderinc") + wp.LIGHTING + wp.WATER_FS
    return ctx.program(vertex_shader=hdr + wp.WATER_VS, fragment_shader=fs), \
        ctx.program(vertex_shader=hdr + wp.WATER_VS, fragment_shader="#version 410\n" + DEPTH_FS)


def measure(ctx, d, size, repeat, caps):
    sc = json.loads((d / "scene.json").read_text())
    w, h = size
    water, depth = programs(ctx, sc, caps)
    cam = sc["camera"]
    basis = np.array(cam["basis"]).T
    origin = np.array(cam["origin"])
    view = np.eye(4)
    view[:3, :3] = basis.T
    view[:3, 3] = -basis.T @ origin
    vp = wp.perspective(cam["fov"], w / h, max(cam["near"], 0.3), cam["far"]) @ view
    tex = {"detail_tex": wp.texture_from_png(ctx, d / "detail.png", 4),
           "foam_tex": wp.texture_from_png(ctx, d / "foam.png", 3),
           "caps_tex": wp.texture_from_png(ctx, d / "caps.png", 4),
           "expo_tex": ctx.texture((2, 2), 1, np.ones(4, "f4").tobytes(), dtype="f4"),
           "land_tex": ctx.texture((2, 2), 2, np.ones(8, "f4").tobytes(), dtype="f4"),
           "wake_tex": ctx.texture((1, 1), 4, bytes([128, 128, 128, 255]))}
    for unit, (name, t) in enumerate(tex.items()):
        t.use(unit)
        for p in (water, depth):
            wp.set_if(p, name, unit)
    for p in (water, depth):
        wp.set_uniforms(p, sc["water"])
        p["u_vp"].write(vp.T.astype("f4").tobytes())
        p["u_sea_pos"].value = tuple(sc["sea_position"])
    for k, v in {"u_cam": tuple(origin), "u_fog_density": float(sc["fog"]["density"]),
                 "u_fog_color": tuple(sc["fog"]["color"][:3]), "u_ambient": float(sc["ambient_energy"]),
                 "u_use_shadow_map": 0.0}.items():
        wp.set_if(water, k, v)
    pos = wp.load_bin(d, "grid_pos.bin", "f4", 3)
    uv = wp.load_bin(d, "grid_uv.bin", "f4", 2)
    idx = wp.load_bin(d, "grid_idx.bin", "i4", 1)
    vbo = ctx.buffer(np.hstack([pos, uv]).astype("f4").tobytes())
    ibo = ctx.buffer(idx.astype("i4").tobytes())
    vao_w = ctx.vertex_array(water, [(vbo, "3f 2f", "in_pos", "in_uv")], ibo)
    vao_d = ctx.vertex_array(depth, [(vbo, "3f 2f", "in_pos", "in_uv")], ibo)
    fbo = ctx.framebuffer(color_attachments=[ctx.renderbuffer((w, h), 4, dtype="f2")],
                          depth_attachment=ctx.depth_renderbuffer((w, h)))
    fbo.use()
    ctx.clear(0, 0, 0, 1, depth=1.0)
    ctx.enable(moderngl.DEPTH_TEST | moderngl.CULL_FACE)
    ctx.front_face = "cw"
    ctx.depth_func = "<"
    vao_d.render()
    ctx.depth_func = "=="
    qs = ctx.query(samples=True)
    with qs:
        vao_w.render()
    pixels = qs.samples
    ctx.finish()
    # one frame per repetition, each finished before the next, timed on the wall clock: a tile-based GPU (the
    # M1) would otherwise merge repeated draws in one pass and shade only the last (hidden surface removal), and
    # GL timer queries on Metal do not time them reliably. The frame overhead cancels in the difference.
    times = []
    for _ in range(repeat):
        t0 = time.perf_counter()
        vao_w.render()
        ctx.finish()
        times.append(time.perf_counter() - t0)
    ms = 1e3 * float(np.median(times))
    return {"ms": ms, "pixels": pixels, "ns_per_px": 1e6 * ms / max(pixels, 1)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1280x800")
    ap.add_argument("--repeat", type=int, default=100)
    ap.add_argument("--tier", choices=["L", "M", "H"], help="the tier's shader instead of the shot's")
    ap.add_argument("shots", nargs="*")
    a = ap.parse_args()
    global TIER
    TIER = a.tier
    size = tuple(int(x) for x in a.size.split("x"))
    ctx = moderngl.create_standalone_context(require=410)
    print(f"{'shot':22s} {'caps':5s} {'pixels':>9s} {'ms/frame':>9s} {'ns/px':>7s}")
    for s in a.shots or SHOTS:
        d = wp.OUT / s
        if not (d / "scene.json").exists():
            print("missing dump", d, "(run tests/water_preview_dump.gd -- whitecaps)")
            return 1
        res = {}
        for caps in (False, True, False, True):   # interleaved, the second of each counts (warm)
            res[caps] = measure(ctx, d, size, a.repeat, caps)
        for caps in (False, True):
            r = res[caps]
            print(f"{s:22s} {'yes' if caps else 'no':5s} {r['pixels']:9d} {r['ms']:9.3f} {r['ns_per_px']:7.3f}")
        print(f"{s:22s} whitecaps add {res[True]['ms'] - res[False]['ms']:+.3f} ms "
              f"({100.0 * (res[True]['ms'] / res[False]['ms'] - 1.0):+.0f} %) at {size[0]}x{size[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
