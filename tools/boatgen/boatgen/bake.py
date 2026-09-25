"""Baked ambient occlusion per vertex, on the GPU (headless OpenGL through moderngl, no window).

For each of `DIRECTIONS` directions spread evenly over the sphere the occluders are drawn into an orthographic
depth map seen from that direction; a transform-feedback pass then tests every receiver vertex, nudged off its
surface along its normal, against the map. A vertex's occlusion is the cosine-weighted share of the directions of
its hemisphere in which it is hidden:

    ao = sum(max(n.d, 0) * visible(d)) / sum(max(n.d, 0))

stored as COLOR_0 (glTF multiplies the base colour by it). Only the fixed model is an occluder: the sails
(deformed at run time) neither cast nor receive, so their AO is not baked.
"""
import numpy as np

DIRECTIONS = 160
RESOLUTION = 2048

_DEPTH_VS = """
#version 410
in vec3 in_pos; uniform mat4 light_mvp;
void main() { gl_Position = light_mvp * vec4(in_pos, 1.0); }
"""
_DEPTH_FS = """
#version 410
void main() { }
"""
_TEST_VS = """
#version 410
in vec3 in_pos; in vec3 in_nrm;
uniform mat4 light_mvp; uniform vec3 dir; uniform sampler2D depth; uniform float nudge; uniform float bias;
out vec2 out_vis;
void main() {
    vec3 n = normalize(in_nrm);
    float w = max(dot(n, dir), 0.0);
    vec4 q = light_mvp * vec4(in_pos + n * nudge + dir * nudge, 1.0);
    vec3 p = q.xyz / q.w * 0.5 + 0.5;
    vec2 ts = 1.0 / vec2(textureSize(depth, 0));
    float lit = 0.0;
    for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++)
        lit += (p.z - bias > texture(depth, p.xy + vec2(i, j) * ts).r) ? 0.0 : 1.0;
    out_vis = vec2(w * lit / 9.0, w);
}
"""


_CTX = None


def gl_context():
    """The one headless OpenGL 4.1 context of the process, shared by the bake and the preview renderer (two
    standalone contexts would fight over which one is current)."""
    global _CTX
    if _CTX is None:
        import moderngl
        _CTX = moderngl.create_standalone_context(require=410)
    return _CTX


def sphere_directions(n):
    """n unit vectors spread evenly over the sphere (Fibonacci lattice)."""
    k = np.arange(n) + 0.5
    z = 1 - 2 * k / n
    r = np.sqrt(1 - z * z)
    a = k * np.pi * (3 - np.sqrt(5))
    return np.stack([r * np.cos(a), r * np.sin(a), z], -1)


def _look(eye, target, up):
    f = target - eye
    f = f / np.linalg.norm(f)
    s = np.cross(f, up)
    s /= np.linalg.norm(s)
    u = np.cross(s, f)
    M = np.eye(4)
    M[0, :3], M[1, :3], M[2, :3] = s, u, -f
    M[:3, 3] = -M[:3, :3] @ eye
    return M


def _ortho(r, n, f):
    M = np.eye(4)
    M[0, 0] = M[1, 1] = 1 / r
    M[2, 2], M[2, 3] = -2 / (f - n), -(f + n) / (f - n)
    return M


def bake_ao(geoms, occludes, directions=DIRECTIONS, resolution=RESOLUTION):
    """Per-vertex AO for each Geom in `geoms` (all in one frame); `occludes[i]` says whether geoms[i] casts.
    Returns a list of float arrays in [0, 1], 1 = open."""
    import moderngl
    P = np.vstack([g.P for g in geoms]).astype("f4")
    N = np.vstack([g.N for g in geoms]).astype("f4")
    occ_I = [g.I + off for g, off, o in zip(geoms, np.cumsum([0] + [len(g.P) for g in geoms])[:-1], occludes) if o]
    occ_I = np.vstack(occ_I).astype("u4")
    lo, hi = P.min(0).astype(np.float64), P.max(0).astype(np.float64)
    c = 0.5 * (lo + hi)
    rad = 0.5 * np.linalg.norm(hi - lo) * 1.02 + 0.05
    texel = 2 * rad / resolution
    ctx = gl_context()
    res_ = []
    track = lambda o: res_.append(o) or o
    try:
        depth_prog = track(ctx.program(vertex_shader=_DEPTH_VS, fragment_shader=_DEPTH_FS))
        test_prog = track(ctx.program(vertex_shader=_TEST_VS, varyings=["out_vis"]))
        pbuf = track(ctx.buffer(P.tobytes()))
        nbuf = track(ctx.buffer(N.tobytes()))
        depth_vao = track(ctx.vertex_array(depth_prog, [(pbuf, "3f", "in_pos")], track(ctx.buffer(occ_I.tobytes()))))
        test_vao = track(ctx.vertex_array(test_prog, [(pbuf, "3f", "in_pos"), (nbuf, "3f", "in_nrm")]))
        out = track(ctx.buffer(reserve=len(P) * 8))
        dtex = track(ctx.depth_texture((resolution, resolution)))
        dtex.repeat_x = dtex.repeat_y = False
        dtex.filter = (moderngl.NEAREST, moderngl.NEAREST)
        dtex.compare_func = ""          # plain depth reads, not a shadow sampler
        fbo = track(ctx.framebuffer(depth_attachment=dtex))
        acc = np.zeros((len(P), 2))
        test_prog["nudge"].value = float(max(0.006, 1.5 * texel))
        test_prog["bias"].value = float(0.002 / (4 * rad))
        test_prog["depth"].value = 0
        for d in sphere_directions(directions):
            up = np.array([0.0, 0.0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
            M = (_ortho(rad, 0.0, 4 * rad) @ _look(c + d * 2 * rad, c, up)).astype("f4")
            fbo.use()
            ctx.viewport = (0, 0, resolution, resolution)
            ctx.enable(moderngl.DEPTH_TEST)
            fbo.clear(depth=1.0)
            depth_prog["light_mvp"].write(M.T.tobytes())
            depth_vao.render()
            dtex.use(0)
            test_prog["light_mvp"].write(M.T.tobytes())
            test_prog["dir"].value = tuple(float(v) for v in d)
            test_vao.transform(out, moderngl.POINTS)
            acc += np.frombuffer(out.read(), dtype="f4").reshape(-1, 2)
        ctx.finish()
    finally:
        for o in reversed(res_):
            o.release()
    ao = np.where(acc[:, 1] > 1e-9, acc[:, 0] / np.maximum(acc[:, 1], 1e-9), 1.0)
    ao = np.clip(ao, 0.0, 1.0)
    res, off = [], 0
    for g in geoms:
        res.append(ao[off:off + len(g.P)])
        off += len(g.P)
    return res
