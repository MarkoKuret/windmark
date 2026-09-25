#!/usr/bin/env python3
"""Offline preview of the sails, step 2 (no window): renders the shots dumped by tests/sail_preview_dump.gd.

Each shot is the boat as BoatView drew it (the sails bent by SailShape), lit by a low sun with a sky ambient, on a
flat sea under a sky gradient, rendered offscreen with OpenGL (moderngl) with 4x multisampling. The sails use the
cloth of shaders/sail_cloth.gdshaderinc (the same file Godot compiles, sail_visuals.md §11.1) with a GLSL copy of
the fragment and light functions of shaders/sail.gdshader, so panels, seams, patches, battens and the light
through the cloth match the engine's; there are no shadows. It is a stand-in for Godot's lighting, meant to judge
shapes and the cloth, not colours.

    python3 game/tests/sail_preview.py [--size 960x600] [--publish] [shot ...]

Writes game/generated/sail_preview/<shot>.png and contact.png (with --publish also game/tests/previews/sails_*.jpg).
Needs numpy, Pillow and moderngl (docs/THIRD_PARTY.md).
"""
import argparse
import json
import math
import os
from pathlib import Path

import moderngl
import numpy as np
from PIL import Image, ImageDraw

GAME = Path(__file__).resolve().parents[1]
OUT = GAME / "generated" / "sail_preview"
PUBLISHED = GAME / "tests" / "previews"

SAIL_VS = """
#version 410
uniform mat4 u_vp;
in vec3 in_pos;
in vec3 in_normal;
in vec4 in_uv;
out vec3 v_n;
out vec3 v_w;
out vec4 v_uv;
void main() {
    v_n = in_normal;
    v_w = in_pos;
    v_uv = in_uv;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

# sail.gdshader's fragment() and light() for one sun and a sky ambient (Godot adds the ambient itself)
SAIL_FS = """
in vec3 v_n;
in vec3 v_w;
in vec4 v_uv;
uniform vec3 u_cam;
uniform vec3 u_sun;
uniform vec3 albedo_color;
uniform sampler2D albedo_tex;
uniform vec2 uv_scale;
uniform float weave;
uniform float roughness;
uniform float backlight;
uniform vec3 fibre_color;
uniform float fibre_amount;
uniform vec3 telltale_color;
out vec4 frag;
const vec3 SUN = vec3(1.0, 0.95, 0.85) * 3.0;
const vec3 SKY_ZEN = vec3(0.25, 0.42, 0.75);
const float PI = 3.14159265359;
void main() {
    vec2 UV = v_uv.xy;
    float px = max(fwidth(UV.x), fwidth(UV.y));
    float layers; float stitch; float panel; float fibre; float mark;
    wm_cloth(UV, v_uv.w, px, layers, stitch, panel, fibre, mark);
    vec3 tex = texture(albedo_tex, UV * uv_scale).rgb;
    vec3 a = min(albedo_color * mix(vec3(1.0), tex, weave), vec3(0.8));
    a *= (1.0 - 0.045 * min(layers, 4.0)) * (1.0 - 0.45 * stitch) * (1.0 + 0.06 * (panel - 0.5));
    a = mix(a, fibre_color, fibre * fibre_amount);
    a = mix(a, telltale_color, mark);
    float rough = clamp(roughness + 0.1 * (panel - 0.5), 0.05, 1.0);
    float trans = backlight * exp(-0.8 * layers) * (1.0 - 0.6 * fibre * fibre_amount) * (1.0 - 0.6 * mark);
    vec3 V = normalize(u_cam - v_w);
    vec3 L = normalize(u_sun);
    vec3 N = normalize(v_n);
    if (dot(N, V) < 0.0) N = -N;  // the layer that faces the camera
    float ndl = dot(N, L);
    float fwd = pow(max(dot(-V, L), 0.0), 4.0);
    vec3 diff = SUN * (max(ndl, 0.0) + max(-ndl, 0.0) * trans * (0.75 + 0.75 * fwd)) / PI;
    vec3 amb = mix(vec3(0.16, 0.17, 0.19), SKY_ZEN * 0.6, 0.5 + 0.5 * N.y) * 0.6;
    vec3 H = normalize(V + L);
    float shin = 2.0 / max(pow(rough, 4.0), 1e-3) - 2.0;
    float spec = pow(max(dot(N, H), 0.0), shin) * (shin + 8.0) / (8.0 * PI);
    vec3 c = a * (amb + diff) + 0.04 * spec * max(ndl, 0.0) * SUN;
    frag = vec4(c, 1.0);
#ifdef CLOTH_DEBUG
    frag = vec4(layers / 4.0, stitch, panel, 1.0) * 3.0;
#endif
}
"""

VS = """
#version 410
uniform mat4 u_vp;
in vec3 in_pos;
in vec3 in_normal;
out vec3 v_n;
out vec3 v_w;
void main() {
    v_n = in_normal;
    v_w = in_pos;
    gl_Position = u_vp * vec4(in_pos, 1.0);
}
"""

FS = """
#version 410
in vec3 v_n;
in vec3 v_w;
uniform vec3 u_albedo;
uniform vec3 u_cam;
uniform vec3 u_sun;
uniform float u_sail;
uniform float u_sea;
out vec4 frag;
const vec3 SUN = vec3(1.0, 0.95, 0.85) * 3.0;
const vec3 SKY_ZEN = vec3(0.25, 0.42, 0.75);
const vec3 SKY_HOR = vec3(0.72, 0.80, 0.90);
void main() {
    vec3 V = normalize(u_cam - v_w);
    vec3 L = normalize(u_sun);
    if (u_sea > 0.5) {
        vec3 N = vec3(0.0, 1.0, 0.0);
        float f = 0.02 + 0.98 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
        vec3 sky = mix(SKY_HOR, SKY_ZEN, 0.3);
        vec3 c = mix(vec3(0.02, 0.07, 0.11), sky, f);
        vec3 H = normalize(L + V);
        c += SUN * pow(max(dot(N, H), 0.0), 400.0) * 0.5;
        float d = length(u_cam - v_w);
        c = mix(c, SKY_HOR, 1.0 - exp(-d * 0.002));
        frag = vec4(c, 1.0);
        return;
    }
    vec3 N = normalize(v_n);
    // one-sided cloth layers and back-face culled hull: shade the side that faces the camera
    if (dot(N, V) < 0.0) N = -N;
    float ndl = dot(N, L);
    vec3 amb = mix(vec3(0.16, 0.17, 0.19), SKY_ZEN * 0.6, 0.5 + 0.5 * N.y) * 0.6;
    vec3 c = u_albedo * (amb + SUN * max(ndl, 0.0) * 0.32);
    if (u_sail > 0.5) {
        c += u_albedo * SUN * max(-ndl, 0.0) * 0.3 * 0.32;   // back-light: the sun through the cloth
        vec3 H = normalize(L + V);
        c += SUN * 0.04 * pow(max(dot(N, H), 0.0), 24.0);
    } else {
        vec3 H = normalize(L + V);
        c += SUN * 0.08 * pow(max(dot(N, H), 0.0), 60.0);
    }
    frag = vec4(c, 1.0);
}
"""

SKY_VS = """
#version 410
in vec2 in_pos;
out vec2 v_p;
void main() { v_p = in_pos; gl_Position = vec4(in_pos, 0.9999, 1.0); }
"""

SKY_FS = """
#version 410
in vec2 v_p;
uniform mat4 u_inv_vp;
out vec4 frag;
void main() {
    vec4 a = u_inv_vp * vec4(v_p, -1.0, 1.0);
    vec4 b = u_inv_vp * vec4(v_p, 1.0, 1.0);
    vec3 d = normalize(b.xyz / b.w - a.xyz / a.w);
    float t = clamp(d.y, 0.0, 1.0);
    vec3 c = mix(vec3(0.72, 0.80, 0.90), vec3(0.25, 0.42, 0.75), pow(t, 0.6));
    frag = vec4(c, 1.0);
}
"""

TONE_FS = """
#version 410
in vec2 v_p;
uniform sampler2D u_hdr;
out vec4 frag;
vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
void main() {
    vec3 c = texture(u_hdr, v_p * 0.5 + 0.5).rgb;
    c = aces(c * 0.9);
    frag = vec4(pow(c, vec3(1.0 / 2.2)), 1.0);
}
"""


def look_at(eye, target, up=(0.0, 1.0, 0.0)):
    f = np.array(target, "f8") - eye
    f /= np.linalg.norm(f)
    s = np.cross(f, up)
    s /= np.linalg.norm(s)
    u = np.cross(s, f)
    m = np.identity(4)
    m[0, :3], m[1, :3], m[2, :3] = s, u, -f
    m[:3, 3] = -m[:3, :3] @ eye
    return m


def perspective(fov_deg, aspect, near, far):
    f = 1.0 / math.tan(math.radians(fov_deg) / 2.0)
    m = np.zeros((4, 4))
    m[0, 0], m[1, 1] = f / aspect, f
    m[2, 2], m[2, 3] = (far + near) / (near - far), 2.0 * far * near / (near - far)
    m[3, 2] = -1.0
    return m


CLOTH_INC = (GAME / "shaders" / "sail_cloth.gdshaderinc").read_text()
_textures = {}


def cloth_texture(ctx, path):
    if not path or not Path(path).exists():
        path = None
    if path not in _textures:
        if path:
            img = Image.open(path).convert("RGB")
            t = ctx.texture(img.size, 3, img.tobytes())
            t.build_mipmaps()
            t.filter = (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
            t.anisotropy = 8.0
        else:
            t = ctx.texture((1, 1), 3, bytes([255, 255, 255]))
        t.repeat_x = t.repeat_y = True
        _textures[path] = t
    return _textures[path]


def set_cloth(prog, cloth):
    for k, v in cloth.items():
        if k not in prog or k == "albedo_tex":
            continue
        u = prog[k]
        if k == "cloth_chord":
            u.value = [float(x) for x in v][:48]
        elif isinstance(v, list):
            u.value = tuple(float(x) for x in v[: u.dimension])
        elif isinstance(v, bool):
            u.value = int(v)
        else:
            u.value = v


def render(ctx, shot_dir, size):
    sc = json.loads((shot_dir / "scene.json").read_text())
    w, h = size
    prog = ctx.program(vertex_shader=VS, fragment_shader=FS)
    sail = ctx.program(vertex_shader=SAIL_VS, fragment_shader="#version 410\n"
                       + ("#define CLOTH_DEBUG\n" if os.environ.get("CLOTH_DEBUG") else "") + CLOTH_INC + SAIL_FS)
    sky = ctx.program(vertex_shader=SKY_VS, fragment_shader=SKY_FS)
    tone = ctx.program(vertex_shader=SKY_VS, fragment_shader=TONE_FS)
    eye = np.array(sc["eye"], "f8")
    target = np.array(sc["target"], "f8")
    vp = perspective(50.0, w / h, 0.3, 3000.0) @ look_at(eye, target)
    vp_b = vp.T.astype("f4").tobytes()
    # the sun low and from the side of the view, so the sails' curvature shows in the shading
    view = target - eye
    view[1] = 0.0
    view /= np.linalg.norm(view)
    side = np.cross(view, [0.0, 1.0, 0.0])
    sun = -view * 0.25 + side * 0.85 + np.array([0.0, 0.45, 0.0])
    if sc.get("sun") == "back":
        sun = view * 0.8 + side * 0.25 + np.array([0.0, 0.5, 0.0])  # behind the sails: the light through the cloth

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
    prog["u_vp"].write(vp_b)
    prog["u_cam"].value = tuple(eye)
    prog["u_sun"].value = tuple(sun)
    # the sea: a large flat disc at the waterline
    r = 2500.0
    sea = np.array([[eye[0] - r, 0.0, eye[2] - r, 0, 1, 0], [eye[0] + r, 0.0, eye[2] - r, 0, 1, 0],
                    [eye[0] - r, 0.0, eye[2] + r, 0, 1, 0], [eye[0] + r, 0.0, eye[2] + r, 0, 1, 0]], "f4")
    prog["u_sea"].value = 1.0
    prog["u_sail"].value = 0.0
    prog["u_albedo"].value = (0.0, 0.0, 0.0)
    ctx.vertex_array(prog, [(ctx.buffer(sea.tobytes()), "3f 3f", "in_pos", "in_normal")]).render(
        moderngl.TRIANGLE_STRIP)
    prog["u_sea"].value = 0.0
    for m in sc["meshes"]:
        v = np.fromfile(shot_dir / (m["name"] + "_v.bin"), dtype="f4")
        i = np.fromfile(shot_dir / (m["name"] + "_i.bin"), dtype="i4")
        if v.size == 0 or i.size == 0:
            continue
        if m.get("cloth") and (shot_dir / (m["name"] + "_uv.bin")).exists():
            uv = np.fromfile(shot_dir / (m["name"] + "_uv.bin"), dtype="f4")
            sail["u_vp"].write(vp_b)
            sail["u_cam"].value = tuple(eye)
            sail["u_sun"].value = tuple(sun)
            set_cloth(sail, m["cloth"])
            sail["albedo_color"].value = tuple(m["albedo"][:3])
            cloth_texture(ctx, m["cloth"].get("albedo_tex")).use(0)
            sail["albedo_tex"].value = 0
            ctx.enable(moderngl.CULL_FACE)  # as in Godot: each cloth layer faces its own side
            ctx.vertex_array(sail, [(ctx.buffer(v.tobytes()), "3f 3f", "in_pos", "in_normal"),
                                    (ctx.buffer(uv.tobytes()), "4f", "in_uv")],
                             ctx.buffer(i.tobytes())).render(moderngl.TRIANGLES)
            ctx.disable(moderngl.CULL_FACE)
            continue
        prog["u_albedo"].value = tuple(m["albedo"][:3])
        prog["u_sail"].value = 1.0 if m["sail"] else 0.0
        ctx.vertex_array(prog, [(ctx.buffer(v.tobytes()), "3f 3f", "in_pos", "in_normal")],
                         ctx.buffer(i.tobytes())).render(moderngl.TRIANGLES)
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
    ap.add_argument("--size", default="960x600")
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
        print(f"{n}: {note}")
        tiles.append((n, img))
        if a.publish:
            PUBLISHED.mkdir(parents=True, exist_ok=True)
            img.save(PUBLISHED / f"sails_{n}.jpg", quality=88)
    # contact sheet, 3 across, captioned
    cols = 3
    tw, th = w // 2, h // 2
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + 18)), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for k, (n, img) in enumerate(tiles):
        x, y = (k % cols) * tw, (k // cols) * (th + 18)
        sheet.paste(img.resize((tw, th), Image.LANCZOS), (x, y + 18))
        d.text((x + 6, y + 3), n, fill=(230, 230, 230))
    sheet.save(OUT / "contact.png")
    if a.publish:
        sheet.save(PUBLISHED / "sails_contact.jpg", quality=88)
    print(f"wrote {len(tiles)} shots and contact.png to {OUT}")


if __name__ == "__main__":
    main()
