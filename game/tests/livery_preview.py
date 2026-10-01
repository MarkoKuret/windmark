#!/usr/bin/env python3
"""Offline preview of the liveries, step 2 (no window): renders the shots dumped by tests/livery_preview_dump.gd.

The boats are drawn as the sail scene paints them: the topsides with shaders/hull_livery.gdshaderinc (colour,
graphic, name and number), the sails with sail_cloth.gdshaderinc and sail_livery.gdshaderinc (cloth, panel colours,
sail numbers on both sides and through the cloth), each boat's text texture, and the other slots in their
(livery) colours; the same files Godot compiles. Lighting, sea and sky are the stand-in of tests/sail_preview.py
(a low sun, a sky ambient, a flat sea, no shadows): for judging the liveries, not the engine's exact colours.

    python3 game/tests/livery_preview.py [--size 1600x900] [--publish] [shot ...]

Writes game/generated/livery_preview/<shot>.png and contact.png (with --publish also
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
    v_side = gl_VertexID >= sl_layer_n ? 1.0 : 0.0;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

LIGHT = """
uniform vec3 u_cam;
uniform vec3 u_sun;
const vec3 SUN = vec3(1.0, 0.95, 0.85) * 3.0;
const vec3 SKY_ZEN = vec3(0.25, 0.42, 0.75);
const float PI = 3.14159265359;
vec3 lit(vec3 albedo, vec3 N, vec3 V, float rough, float metal) {
    vec3 L = normalize(u_sun);
    float ndl = max(dot(N, L), 0.0);
    vec3 amb = mix(vec3(0.16, 0.17, 0.19), SKY_ZEN * 0.6, 0.5 + 0.5 * N.y) * 0.6;
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
    vec3 amb = mix(vec3(0.16, 0.17, 0.19), SKY_ZEN * 0.6, 0.5 + 0.5 * N.y) * 0.6;
    vec3 H = normalize(V + L);
    float shin = 2.0 / max(pow(rough, 4.0), 1e-3) - 2.0;
    float spec = pow(max(dot(N, H), 0.0), shin) * (shin + 8.0) / (8.0 * PI);
    frag = vec4(a * (amb + diff) + 0.04 * spec * max(ndl, 0.0) * SUN, 1.0);
}
"""


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
    sky = ctx.program(vertex_shader=spv.SKY_VS, fragment_shader=spv.SKY_FS)
    tone = ctx.program(vertex_shader=spv.SKY_VS, fragment_shader=spv.TONE_FS)
    sea_p = ctx.program(vertex_shader=spv.VS, fragment_shader=spv.FS)
    eye = np.array(sc["eye"], "f8")
    target = np.array(sc["target"], "f8")
    vp = spv.perspective(sc.get("fov", 50.0), w / h, 0.3, 3000.0) @ spv.look_at(eye, target)
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
    ctx.vertex_array(sea_p, [(ctx.buffer(sea.tobytes()), "3f 3f", "in_pos", "in_normal")]).render(
        moderngl.TRIANGLE_STRIP)
    for prog in (boat, sail):
        prog["u_vp"].write(vp_b)
        prog["u_cam"].value = tuple(eye)
        prog["u_sun"].value = tuple(sun)
    for m in sc["meshes"]:
        v = np.fromfile(d / (m["name"] + "_v.bin"), dtype="f4")
        i = np.fromfile(d / (m["name"] + "_i.bin"), dtype="i4")
        if v.size == 0 or i.size == 0:
            continue
        vb = ctx.buffer(v.tobytes())
        fmt = [(vb, "3f 3f 4f 1f", "in_pos", "in_normal", "in_uv", "in_port")]
        if m["kind"] == "sail":
            u = m["uniforms"]
            set_uniforms(sail, u)
            spv.cloth_texture(ctx, u.get("albedo_tex")).use(0)
            sail["albedo_tex"].value = 0
            text_texture(ctx, d / m["text"]).use(1)
            sail["livery_text"].value = 1
            ctx.enable(moderngl.CULL_FACE)  # each cloth layer faces its own side
            ctx.front_face = "cw"  # Godot meshes: clockwise front faces
            ctx.vertex_array(sail, fmt, ctx.buffer(i.tobytes())).render(moderngl.TRIANGLES)
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
        ctx.vertex_array(boat, fmt, ctx.buffer(i.tobytes())).render(moderngl.TRIANGLES)
    ctx.copy_framebuffer(resolved, ms)
    out = ctx.framebuffer(color_attachments=[ctx.renderbuffer((w, h), 4)])
    out.use()
    ctx.disable(moderngl.DEPTH_TEST)
    hdr.use(0)
    tone["u_hdr"].value = 0
    ctx.vertex_array(tone, [(quad, "2f", "in_pos")]).render(moderngl.TRIANGLE_STRIP)
    img = Image.frombytes("RGBA", (w, h), out.read(components=4)).transpose(Image.FLIP_TOP_BOTTOM).convert("RGB")
    return img, sc.get("note", "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="1600x900")
    ap.add_argument("--publish", action="store_true")
    ap.add_argument("shots", nargs="*")
    a = ap.parse_args()
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
        sheet.save(PUBLISHED / "livery_contact.jpg", quality=88)
    print(f"wrote {len(tiles)} shots and contact.png to {OUT}")


if __name__ == "__main__":
    main()
