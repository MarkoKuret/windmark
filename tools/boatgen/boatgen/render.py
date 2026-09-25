"""Headless preview renderer for generated boats (OpenGL 4.1 core through moderngl's standalone context).

Reads the GLB back (so the preview checks the exported file), then draws it with a sun shadow map, GGX
specular, a sky-gradient reflection and screen-space ambient occlusion. Surface detail that a real texture set
would provide (non-slip pattern, carbon weave, sail panel seams) is drawn procedurally from the mesh UVs, which
doubles as a check of the UV layout. `uv_check=True` renders a metric checker on uv0 instead.
"""
import numpy as np
from PIL import Image

from .gltf import read_glb

MAT_IDS = {"gelcoat": 0, "nonslip": 1, "antifouling": 2, "boottop": 3, "carbon": 4, "metal": 5, "sailcloth": 6,
           "glass": 7, "rope": 8, "rubber": 9}

VS = """
#version 410
in vec3 in_pos; in vec3 in_nrm; in vec2 in_uv0; in vec2 in_uv1;
uniform mat4 mvp; uniform mat4 light_mvp;
out vec3 v_pos; out vec3 v_nrm; out vec2 v_uv0; out vec2 v_uv1; out vec4 v_lpos;
void main() {
    v_pos = in_pos; v_nrm = in_nrm; v_uv0 = in_uv0; v_uv1 = in_uv1;
    v_lpos = light_mvp * vec4(in_pos, 1.0);
    gl_Position = mvp * vec4(in_pos, 1.0);
}
"""

FS = """
#version 410
in vec3 v_pos; in vec3 v_nrm; in vec2 v_uv0; in vec2 v_uv1; in vec4 v_lpos;
uniform vec4 base_color; uniform float metallic; uniform float roughness; uniform int mat_id;
uniform vec3 cam_pos; uniform vec3 sun_dir; uniform sampler2D shadow_map; uniform int uv_check;
uniform int water_on; uniform int hull_livery; uniform int battens;
layout(location = 0) out vec4 frag;

vec3 sky(vec3 d) {
    float h = clamp(d.y, -1.0, 1.0);
    vec3 zen = vec3(0.10, 0.27, 0.62), hor = vec3(0.66, 0.77, 0.90), gnd = vec3(0.05, 0.12, 0.17);
    vec3 c = h > 0.0 ? mix(hor, zen, pow(h, 0.55)) : mix(hor * 0.6, gnd, pow(-h, 0.4));
    float s = max(dot(d, sun_dir), 0.0);
    return c + vec3(1.0, 0.92, 0.8) * (pow(s, 600.0) * 30.0 + pow(s, 12.0) * 0.25);
}

float shadow() {
    vec3 p = v_lpos.xyz / v_lpos.w * 0.5 + 0.5;
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 1.0;
    float s = 0.0; vec2 ts = 1.0 / vec2(textureSize(shadow_map, 0));
    for (int i = -2; i <= 2; i++) for (int j = -2; j <= 2; j++) {
        float d = texture(shadow_map, p.xy + vec2(i, j) * ts * 1.2).r;
        s += (p.z - 0.0007 > d) ? 0.0 : 1.0;
    }
    return s / 25.0;
}

float aa_pattern(float v, float w) { // band-limited square wave in [0,1]
    return clamp(0.5 + 0.5 * sin(v) / max(1.0, w * 1.0), 0.0, 1.0);
}

void main() {
    vec3 N = normalize(v_nrm);
    if (!gl_FrontFacing) N = -N;
    vec3 V = normalize(cam_pos - v_pos);
    vec3 albedo = base_color.rgb;
    float rough = roughness, metal = metallic;
    vec2 uv = v_uv0;
    if (uv_check == 1) {
        vec2 c = floor(uv / 0.25);
        float k = mod(c.x + c.y, 2.0);
        albedo = mix(vec3(0.15), vec3(0.85), k) * (0.6 + 0.4 * fract(vec3(0.13, 0.37, 0.71) * float(mat_id + 1) * 3.1));
        rough = 0.6; metal = 0.0;
    } else if (mat_id == 1) { // non-slip: raised diamond pattern, faded out where it would alias
        float f = 2.0 * 3.14159 / 0.03;
        float w = length(fwidth(uv)) * f;
        float p = sin(uv.x * f + uv.y * f) * sin(uv.x * f - uv.y * f);
        float fade = clamp(1.5 - w * 0.5, 0.0, 1.0);
        albedo *= 1.0 + 0.10 * p * fade;
        rough = 0.85;
    } else if (mat_id == 4) { // carbon twill
        float f = 2.0 * 3.14159 / 0.012;
        float w = length(fwidth(uv)) * f;
        float fade = clamp(1.5 - w * 0.4, 0.0, 1.0);
        float t = step(0.5, fract((uv.x + uv.y) / 0.024)) * 2.0 - 1.0;
        albedo *= 1.0 + 0.35 * t * fade;
    } else if (mat_id == 6) { // sailcloth: horizontal panel seams every 0.9 m, radial cloth tone
        float s = abs(fract(uv.y / 0.9) - 0.5) * 0.9;
        float w = fwidth(uv.y) * 1.5 + 0.008;
        albedo *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, w, 0.45 - s));
        albedo *= 0.96 + 0.04 * sin(uv.x * 0.7);
        // edge tapes and batten pockets from the normalised uv1 (u: luff 0 -> leech 1, v: head 0 -> foot 1)
        vec2 s1 = v_uv1;
        float eu = min(s1.x, 1.0 - s1.x), ev = 1.0 - s1.y;
        float tape = 1.0 - smoothstep(0.012, 0.018, min(eu, ev));
        float bv = fract(s1.y * 5.0);
        // full-length battens (the two layers mirror uv1, so luff and leech are not told apart here)
        float batten = (1.0 - smoothstep(0.004, 0.007, abs(bv - 0.5) * 0.2)) * step(0.04, eu)
                       * step(0.08, s1.y) * step(s1.y, 0.92) * float(battens);
        albedo = mix(albedo, vec3(0.12, 0.13, 0.15), max(tape, batten * 0.45));
    }
    if (hull_livery == 1 && mat_id == 0 && uv_check == 0) {
        // demonstration livery through uv1: a sheer stripe on both hull bands
        float vb = fract(v_uv1.y * 2.0);   // 0 at the sheer of each band
        float u = v_uv1.x;
        float stripe = smoothstep(0.06, 0.065, vb) * (1.0 - smoothstep(0.10 + 0.05 * u, 0.105 + 0.05 * u, vb));
        albedo = mix(albedo, vec3(0.03, 0.10, 0.30), stripe);
    }
    vec3 L = normalize(sun_dir);
    vec3 H = normalize(L + V);
    float NL = max(dot(N, L), 0.0), NV = max(dot(N, V), 1e-3), NH = max(dot(N, H), 0.0);
    float a = rough * rough, a2 = a * a;
    float D = a2 / (3.14159 * pow(NH * NH * (a2 - 1.0) + 1.0, 2.0));
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    float G = NL / (NL * (1.0 - k) + k) * NV / (NV * (1.0 - k) + k);
    vec3 F0 = mix(vec3(0.04), albedo, metal);
    vec3 F = F0 + (1.0 - F0) * pow(1.0 - max(dot(H, V), 0.0), 5.0);
    vec3 spec = D * G * F / max(4.0 * NL * NV, 1e-3);
    float sh = shadow();
    vec3 sun = vec3(3.6, 3.4, 3.1);
    vec3 diff = albedo * (1.0 - metal) / 3.14159;
    vec3 amb = albedo * (1.0 - metal) * mix(vec3(0.16, 0.15, 0.14), vec3(0.34, 0.42, 0.56), N.y * 0.5 + 0.5);
    vec3 R = reflect(-V, N);
    vec3 Fr = F0 + (1.0 - F0) * pow(1.0 - NV, 5.0);
    vec3 env = sky(R) * Fr * pow(1.0 - rough, 2.2) * (metal > 0.5 ? 1.0 : 0.6);
    if (metal > 0.5) env = sky(R) * albedo * (1.0 - rough * 0.7) * 0.8;
    vec3 col = (diff + spec) * sun * NL * sh + amb + env;
    if (mat_id == 6) { // sail translucency: light through the cloth from behind
        col += albedo * sun * max(dot(-N, L), 0.0) * 0.30 * sh;
    }
    if (water_on == 1 && v_pos.y < 0.0) { // under water: absorb toward the water colour with depth
        float d = -v_pos.y;
        col = mix(col, vec3(0.01, 0.07, 0.09), 1.0 - exp(-d * 0.9));
    }
    frag = vec4(col, 1.0);
}
"""

WATER_FS = """
#version 410
in vec3 v_pos; in vec3 v_nrm; in vec2 v_uv0; in vec2 v_uv1; in vec4 v_lpos;
uniform vec3 cam_pos; uniform vec3 sun_dir; uniform sampler2D shadow_map;
layout(location = 0) out vec4 frag;
vec3 sky(vec3 d) {
    float h = clamp(d.y, -1.0, 1.0);
    vec3 zen = vec3(0.10, 0.27, 0.62), hor = vec3(0.66, 0.77, 0.90);
    vec3 c = mix(hor, zen, pow(max(h, 0.0), 0.55));
    float s = max(dot(d, sun_dir), 0.0);
    return c + vec3(1.0, 0.92, 0.8) * (pow(s, 900.0) * 40.0);
}
void main() {
    vec2 p = v_pos.xz;
    float dist = length(cam_pos - v_pos);
    float amp = exp(-dist / 35.0);   // ripples fade out before they alias
    vec3 N = normalize(vec3(amp * (0.035 * sin(p.x * 0.9 + p.y * 0.35) + 0.02 * sin(p.x * 2.3 - p.y * 1.7)),
                            1.0, amp * (0.035 * sin(p.y * 0.7 - p.x * 0.25) + 0.02 * sin(p.y * 2.1 + p.x * 1.6))));
    vec3 V = normalize(cam_pos - v_pos);
    float F = 0.02 + 0.98 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
    vec3 R = reflect(-V, N);
    vec3 deep = vec3(0.006, 0.045, 0.075);
    vec3 s = v_lpos.xyz / v_lpos.w * 0.5 + 0.5;
    float sh = 1.0;
    if (s.x > 0.0 && s.x < 1.0 && s.y > 0.0 && s.y < 1.0) sh = (s.z - 0.001 > texture(shadow_map, s.xy).r) ? 0.55 : 1.0;
    vec3 col = mix(deep * sh, sky(R), F);
    float fade = exp(-length(v_pos.xz) * 0.004);
    frag = vec4(col, mix(1.0, 0.62 + 0.38 * F, fade));
}
"""

SHADOW_VS = """
#version 410
in vec3 in_pos; uniform mat4 light_mvp;
void main() { gl_Position = light_mvp * vec4(in_pos, 1.0); }
"""
SHADOW_FS = """
#version 410
void main() { }
"""

POST_VS = """
#version 410
in vec2 in_pos; out vec2 uv;
void main() { uv = in_pos * 0.5 + 0.5; gl_Position = vec4(in_pos, 0.0, 1.0); }
"""
POST_FS = """
#version 410
in vec2 uv; uniform sampler2D color_tex; uniform sampler2D depth_tex;
uniform mat4 inv_proj; uniform mat4 proj; uniform vec2 texel; uniform float ao_radius; uniform vec3 bg_top;
uniform vec3 bg_bot; uniform int bg_on;
out vec4 frag;
vec3 view_pos(vec2 t) {
    float d = texture(depth_tex, t).r * 2.0 - 1.0;
    vec4 p = inv_proj * vec4(t * 2.0 - 1.0, d, 1.0);
    return p.xyz / p.w;
}
vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
void main() {
    vec4 c = texture(color_tex, uv);
    float d = texture(depth_tex, uv).r;
    vec3 col = c.rgb;
    if (d >= 1.0) {
        col = bg_on == 1 ? mix(bg_bot, bg_top, uv.y) : col;
    } else {
        // screen-space ambient occlusion: normal-oriented hemisphere around the view-space position
        vec3 P = view_pos(uv);
        vec3 N = normalize(cross(view_pos(uv + vec2(texel.x, 0.0)) - P, view_pos(uv + vec2(0.0, texel.y)) - P));
        if (dot(N, -P) < 0.0) N = -N;
        float occ = 0.0; int n = 0;
        for (int i = 0; i < 24; i++) {
            float a = float(i) * 2.39996;
            float z = fract(float(i) * 0.618034) * 0.9 + 0.1;
            float rr = sqrt(1.0 - z * z);
            vec3 d = vec3(cos(a) * rr, sin(a) * rr, z);
            vec3 t = normalize(abs(N.z) < 0.9 ? cross(N, vec3(0, 0, 1)) : cross(N, vec3(1, 0, 0)));
            vec3 bt = cross(N, t);
            vec3 dir = (t * d.x + bt * d.y + N * d.z) * ao_radius * (0.25 + 0.75 * fract(float(i) * 0.3819));
            vec3 S = P + dir;
            vec4 q = proj * vec4(S, 1.0);
            vec2 st = q.xy / q.w * 0.5 + 0.5;
            if (st.x < 0.0 || st.x > 1.0 || st.y < 0.0 || st.y > 1.0) { n++; continue; }
            vec3 Q = view_pos(st);
            float range = smoothstep(0.0, 1.0, ao_radius / max(abs(P.z - Q.z), 1e-4));
            occ += (Q.z >= S.z + 0.03 * ao_radius ? 1.0 : 0.0) * range;
            n++;
        }
        float ao = 1.0 - 0.75 * occ / max(float(n), 1.0);
        col *= ao;
    }
    col = aces(col * 0.9);
    frag = vec4(pow(col, vec3(1.0 / 2.2)), 1.0);
}
"""


def _set(prog, name, value):
    if name in prog:
        prog[name].value = value


def _write(prog, name, data):
    if name in prog:
        prog[name].write(data)


def look_at(eye, target, up=(0, 1, 0)):
    f = np.asarray(target, dtype=np.float64) - eye
    f /= np.linalg.norm(f)
    s = np.cross(f, up)
    s /= np.linalg.norm(s)
    u = np.cross(s, f)
    M = np.eye(4)
    M[0, :3], M[1, :3], M[2, :3] = s, u, -f
    M[:3, 3] = -M[:3, :3] @ eye
    return M


def perspective(fov_deg, aspect, near, far):
    f = 1 / np.tan(np.radians(fov_deg) / 2)
    M = np.zeros((4, 4))
    M[0, 0], M[1, 1] = f / aspect, f
    M[2, 2], M[2, 3] = (far + near) / (near - far), 2 * far * near / (near - far)
    M[3, 2] = -1
    return M


def ortho(l, r, b, t, n, f):
    M = np.eye(4)
    M[0, 0], M[1, 1], M[2, 2] = 2 / (r - l), 2 / (t - b), -2 / (f - n)
    M[0, 3], M[1, 3], M[2, 3] = -(r + l) / (r - l), -(t + b) / (t - b), -(f + n) / (f - n)
    return M


class Renderer:
    def __init__(self, width=1600, height=1000, samples=8):
        import moderngl
        self.mgl = moderngl
        self.ctx = moderngl.create_standalone_context(require=410)
        self.W, self.H = width, height
        ctx = self.ctx
        self.prog = ctx.program(vertex_shader=VS, fragment_shader=FS)
        self.water_prog = ctx.program(vertex_shader=VS, fragment_shader=WATER_FS)
        self.shadow_prog = ctx.program(vertex_shader=SHADOW_VS, fragment_shader=SHADOW_FS)
        self.post_prog = ctx.program(vertex_shader=POST_VS, fragment_shader=POST_FS)
        # multisampled scene target and single-sample resolve targets
        self.ms_color = ctx.renderbuffer((width, height), 4, samples=samples, dtype="f2")
        self.ms_depth = ctx.depth_renderbuffer((width, height), samples=samples)
        self.ms_fbo = ctx.framebuffer([self.ms_color], self.ms_depth)
        self.color_tex = ctx.texture((width, height), 4, dtype="f2")
        self.depth_tex = ctx.depth_texture((width, height))
        self.res_fbo = ctx.framebuffer([self.color_tex], self.depth_tex)
        self.out_tex = ctx.texture((width, height), 4)
        self.out_fbo = ctx.framebuffer([self.out_tex])
        self.shadow_tex = ctx.depth_texture((4096, 4096))
        self.shadow_tex.repeat_x = self.shadow_tex.repeat_y = False
        self.shadow_fbo = ctx.framebuffer(depth_attachment=self.shadow_tex)
        quad = np.array([-1, -1, 1, -1, -1, 1, 1, 1], dtype="f4")
        self.quad = ctx.vertex_array(self.post_prog, [(ctx.buffer(quad), "2f", "in_pos")])

    def load(self, glb_path, extra=None, hide=(), transform=None, battened=()):
        self.battened = tuple(battened)
        prims, doc = read_glb(glb_path)
        if transform is not None:
            R = np.asarray(transform, dtype=np.float64)
            prims = [(n, m, P @ R.T, N @ R.T, u0, u1, I) for n, m, P, N, u0, u1, I in prims]
        if extra:
            prims = prims + extra
        mats = {m["name"]: m for m in doc["materials"]}
        self.objs = []
        allP = []
        for name, mat, P, N, uv0, uv1, I in prims:
            if any(h in name for h in hide):
                continue
            data = np.hstack([P, N, uv0, uv1]).astype("f4")
            vbo = self.ctx.buffer(data.tobytes())
            ibo = self.ctx.buffer(I.astype("u4").tobytes())
            fmt = [(vbo, "3f 3f 2f 2f", "in_pos", "in_nrm", "in_uv0", "in_uv1")]
            vao = self.ctx.vertex_array(self.prog, fmt, ibo)
            svao = self.ctx.vertex_array(self.shadow_prog, [(vbo, "3f 12x 8x 8x", "in_pos")], ibo)
            m = mats.get(mat, {"pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1],
                                                        "metallicFactor": 0, "roughnessFactor": 0.5}})
            pbr = m["pbrMetallicRoughness"]
            self.objs.append((name, mat, vao, svao, pbr))
            allP.append(P)
        allP = np.vstack(allP)
        self.bmin, self.bmax = allP.min(0), allP.max(0)
        self.tri_count = sum(len(p[6]) for p in prims)

    def render(self, path, eye, target, fov=30.0, water=True, sun=(0.45, 0.75, 0.35), uv_check=False,
               livery=False, ground=False, background=None):
        ctx = self.ctx
        eye = np.asarray(eye, dtype=np.float64)
        sun = np.asarray(sun, dtype=np.float64)
        sun /= np.linalg.norm(sun)
        c = 0.5 * (self.bmin + self.bmax)
        rad = np.linalg.norm(self.bmax - self.bmin) * 0.55 + 2.0
        Lv = look_at(c + sun * rad * 2, c, up=(0, 0, 1) if abs(sun[1]) > 0.99 else (0, 1, 0))
        Lp = ortho(-rad, rad, -rad, rad, 0.1, rad * 4)
        light = (Lp @ Lv).astype("f4")
        # shadow pass
        self.shadow_fbo.use()
        ctx.viewport = (0, 0, 4096, 4096)
        ctx.enable(self.mgl.DEPTH_TEST)
        ctx.disable(self.mgl.CULL_FACE)
        self.shadow_fbo.clear(depth=1.0)
        _write(self.shadow_prog, "light_mvp", light.T.tobytes())
        for name, mat, vao, svao, pbr in self.objs:
            svao.render()
        # main pass
        V = look_at(eye, target)
        near = max(0.05, np.linalg.norm(eye - target) * 0.02)
        Pm = perspective(fov, self.W / self.H, near, near * 4000)
        mvp = (Pm @ V).astype("f4")
        self.ms_fbo.use()
        ctx.viewport = (0, 0, self.W, self.H)
        bg = (0.66, 0.77, 0.90) if background is None else background
        self.ms_fbo.clear(*bg, 1.0, depth=1.0)
        self.shadow_tex.use(0)
        p = self.prog
        _write(p, "mvp", mvp.T.tobytes())
        _write(p, "light_mvp", light.T.tobytes())
        _set(p, "cam_pos", tuple(eye))
        _set(p, "sun_dir", tuple(sun))
        _set(p, "shadow_map", 0)
        _set(p, "uv_check", int(uv_check))
        _set(p, "water_on", int(water))
        _set(p, "hull_livery", int(livery))
        for name, mat, vao, svao, pbr in self.objs:
            _set(p, "base_color", tuple(pbr["baseColorFactor"]))
            _set(p, "metallic", pbr["metallicFactor"])
            _set(p, "roughness", pbr["roughnessFactor"])
            _set(p, "mat_id", MAT_IDS.get(mat, 0))
            _set(p, "battens", int(name in self.battened))
            vao.render()
        if water or ground:
            S = 400.0
            y = 0.0 if water else float(self.bmin[1]) - 0.02
            q = np.array([[-S, y, -S], [S, y, -S], [S, y, S], [-S, y, S]], dtype=np.float64)
            data = np.hstack([q, np.tile([0, 1, 0], (4, 1)), q[:, [0, 2]], q[:, [0, 2]]]).astype("f4")
            I = np.array([0, 2, 1, 0, 3, 2], dtype="u4")
            if water:
                prog = self.water_prog
                _write(prog, "mvp", mvp.T.tobytes())
                _write(prog, "light_mvp", light.T.tobytes())
                _set(prog, "cam_pos", tuple(eye))
                _set(prog, "sun_dir", tuple(sun))
                _set(prog, "shadow_map", 0)
                ctx.enable(self.mgl.BLEND)
                ctx.blend_func = self.mgl.SRC_ALPHA, self.mgl.ONE_MINUS_SRC_ALPHA
            else:
                prog = self.prog
                _set(prog, "uv_check", 0)
                _set(prog, "base_color", (0.55, 0.56, 0.57, 1.0))
                _set(prog, "metallic", 0.0)
                _set(prog, "roughness", 0.9)
                _set(prog, "mat_id", 0)
                _set(prog, "hull_livery", 0)
                _set(prog, "water_on", 0)
            vao = ctx.vertex_array(prog, [(ctx.buffer(data.tobytes()), "3f 3f 2f 2f", "in_pos", "in_nrm", "in_uv0",
                                           "in_uv1")], ctx.buffer(I.tobytes()))
            vao.render()
            ctx.disable(self.mgl.BLEND)
        # resolve and post-process (SSAO, tone map)
        ctx.copy_framebuffer(self.res_fbo, self.ms_fbo)
        self.out_fbo.use()
        ctx.disable(self.mgl.DEPTH_TEST)
        self.color_tex.use(1)
        self.depth_tex.use(2)
        pp = self.post_prog
        _set(pp, "color_tex", 1)
        _set(pp, "depth_tex", 2)
        _write(pp, "inv_proj", np.linalg.inv(Pm).astype("f4").T.tobytes())
        _write(pp, "proj", Pm.astype("f4").T.tobytes())
        _set(pp, "texel", (1 / self.W, 1 / self.H))
        _set(pp, "ao_radius", float(np.linalg.norm(eye - target) * 0.012))
        _set(pp, "bg_top", (0.30, 0.50, 0.80))
        _set(pp, "bg_bot", (0.78, 0.85, 0.93))
        _set(pp, "bg_on", 1)
        self.quad.render(self.mgl.TRIANGLE_STRIP)
        img = np.frombuffer(self.out_fbo.read(components=3), dtype=np.uint8).reshape(self.H, self.W, 3)
        Image.fromarray(img[::-1]).save(path)


def orbit(target, dist, az_deg, el_deg):
    """Camera position in the glTF frame: azimuth 0 = from ahead (+Z), 90 = from port (+X)."""
    az, el = np.radians(az_deg), np.radians(el_deg)
    t = np.asarray(target, dtype=np.float64)
    return t + dist * np.array([np.sin(az) * np.cos(el), np.sin(el), np.cos(az) * np.cos(el)])
