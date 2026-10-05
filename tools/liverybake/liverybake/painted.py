"""Painted hardware (data_format.md §8.5 "Staged boat atlas", sail_visuals.md §11.4): the fittings the game's levels
of detail do not model (tracks, hatches, organisers, small cleats, turning blocks, the halyards on deck, coils and
tails) drawn into the deck maps from the generator's full-detail pieces seen from above.

The pieces are rasterised top down at twice the target resolution (the topmost surface wins), then averaged: per
texel the coverage, colour by material, relief from the pieces' own normals (the boat frame's x, y and z are the
image's right, up and out, so a boat-frame normal is already a tangent-space normal of the plan view) and roughness.
Baked shading makes the flat paint read solid: a soft contact shadow round every fitting (occlusion and a little
albedo), the low parts of a fitting darker and its upper edges lighter. Deterministic: no noise, fixed order.
"""
import numpy as np

from .common import ALBEDO_MAX, F32, blur, hex_lin, smoothstep

# slot -> (linear albedo, roughness); the rope slots take the class rope set's colours
SLOTS = {
    "metal": ((0.45, 0.45, 0.46), 0.30),
    "rubber": ((0.045, 0.045, 0.045), 0.80),
    "carbon": ((0.04, 0.04, 0.042), 0.35),
    "glass": ((0.025, 0.03, 0.036), 0.06),
    "gelcoat": ((0.72, 0.72, 0.70), 0.25),
    "nonslip": ((0.47, 0.47, 0.45), 0.80),
    "rope": ((0.34, 0.33, 0.31), 0.85),
}
ROPE_FN = {"rope_halyard": "halyard", "rope_control": "control", "rope_mainsheet": "mainsheet",
           "rope_sheet": "sheet", "rope_kite_sheet": "kite_sheet"}


def slot_look(slot, rope_set):
    """(linear albedo (3,), roughness) of a piece's material slot; rope_set: ropes.rope_set(livery file)."""
    if slot in ROPE_FN and ROPE_FN[slot] in rope_set:
        c, f, _ = rope_set[ROPE_FN[slot]]
        a = (14 * hex_lin(c) + 2 * hex_lin(f)) / 16
        return np.minimum(a, ALBEDO_MAX).astype(F32), 0.85
    a, r = SLOTS.get(slot, SLOTS["metal"])
    return np.asarray(a, dtype=F32), r


def rasterize(pieces, plan, W, H, ss=2):
    """Top-down raster of the pieces over the plan rectangle (x0, y_top, length, height; boat frame) into W x H
    texels: (coverage (H, W), slot index (H, W) of the topmost piece at ss x (-1 none), normal (H*ss, W*ss, 3),
    height above the deck (H*ss, W*ss), the slot names)."""
    x0, yt, w, h = plan
    Ws, Hs = W * ss, H * ss
    sx, sy = Ws / w, Hs / h
    zbuf = np.full((Hs, Ws), -np.inf)
    sid = np.full((Hs, Ws), -1, np.int16)
    nrm = np.zeros((Hs, Ws, 3), F32)
    hgt = np.zeros((Hs, Ws), F32)
    names = sorted({p["slot"] for p in pieces})
    for p in pieces:
        k = names.index(p["slot"])
        P, I, N, Hv = p["P"], p["I"], p["N"], p["H"]
        px = (P[:, 0] - x0) * sx
        py = (yt - P[:, 1]) * sy
        for t in I:
            a, b, c = t
            ax, ay, bx, by, cx, cy = px[a], py[a], px[b], py[b], px[c], py[c]
            area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if abs(area) < 1e-9:
                continue
            i0 = max(int(np.floor(min(ax, bx, cx))), 0)
            i1 = min(int(np.ceil(max(ax, bx, cx))), Ws - 1)
            j0 = max(int(np.floor(min(ay, by, cy))), 0)
            j1 = min(int(np.ceil(max(ay, by, cy))), Hs - 1)
            if i1 < i0 or j1 < j0:
                continue
            gx, gy = np.meshgrid(np.arange(i0, i1 + 1) + 0.5, np.arange(j0, j1 + 1) + 0.5)
            w0 = ((bx - gx) * (cy - gy) - (cx - gx) * (by - gy)) / area
            w1 = ((cx - gx) * (ay - gy) - (ax - gx) * (cy - gy)) / area
            w2 = 1.0 - w0 - w1
            ins = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not ins.any():
                continue
            z = w0 * P[a, 2] + w1 * P[b, 2] + w2 * P[c, 2]
            sub = zbuf[j0:j1 + 1, i0:i1 + 1]
            win = ins & (z > sub)
            if not win.any():
                continue
            sub[win] = z[win]
            sid[j0:j1 + 1, i0:i1 + 1][win] = k
            n = w0[..., None] * N[a] + w1[..., None] * N[b] + w2[..., None] * N[c]
            nrm[j0:j1 + 1, i0:i1 + 1][win] = n[win]
            hgt[j0:j1 + 1, i0:i1 + 1][win] = (w0 * Hv[a] + w1 * Hv[b] + w2 * Hv[c])[win]
    nl = np.linalg.norm(nrm, axis=-1, keepdims=True)
    nrm = np.where(nl > 1e-6, nrm / np.maximum(nl, 1e-9), np.array([0, 0, 1.0], F32)).astype(F32)
    # faces seen from below (the underside of a lip) read as facing up
    nrm[..., 2] = np.abs(nrm[..., 2])
    return sid, nrm, hgt, names


def _down(a, ss):
    """Average ss x ss blocks."""
    H, W = a.shape[0] // ss, a.shape[1] // ss
    return a.reshape(H, ss, W, ss, *a.shape[2:]).mean(axis=(1, 3)).astype(F32)


def bake(pieces, plan, W, H, rope_set, ss=2):
    """The painted layer over a W x H deck image: {"cov" (H, W), "albedo" (H, W, 3) linear (premultiplied by
    nothing: the colour where covered), "normal" (H, W, 3), "occ", "rough" (H, W), "shadow" (H, W): the contact
    shadow (0..1) for the deck under and round the fittings}."""
    sid, nrm, hgt, names = rasterize(pieces, plan, W, H, ss)
    cov_s = (sid >= 0).astype(F32)
    alb_s = np.zeros(sid.shape + (3,), F32)
    rough_s = np.zeros(sid.shape, F32)
    for k, n in enumerate(names):
        a, r = slot_look(n, rope_set)
        m = sid == k
        alb_s[m] = a
        rough_s[m] = r
    # baked shading on the fittings: low parts darker, upper edges (tilted faces high up) lighter
    up = smoothstep(0.0, 0.035, hgt)
    tilt = np.clip((1.0 - nrm[..., 2]) * 1.6, 0.0, 1.0)
    shade = (0.62 + 0.38 * up) * (1.0 + 0.22 * tilt * up)
    alb_s = alb_s * shade[..., None]
    occ_s = 0.7 + 0.3 * up
    cov = _down(cov_s, ss)
    c = np.maximum(cov, 1e-6)
    albedo = (_down(alb_s * cov_s[..., None], ss) / c[..., None]).astype(F32)
    rough = (_down(rough_s * cov_s, ss) / c).astype(F32)
    occ = (_down(occ_s * cov_s, ss) / c).astype(F32)
    n = _down(nrm * cov_s[..., None], ss) + np.array([0, 0, 1.0], F32) * (1.0 - cov)[..., None]
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    # contact shadow: the coverage blurred over a few centimetres (texels from the plan's scale)
    px = 0.5 * (plan[2] / W + plan[3] / H)
    sh = np.clip(blur(cov, max(1.0, 0.02 / px)) * 1.6, 0.0, 1.0)
    return {"cov": cov, "albedo": np.minimum(albedo, ALBEDO_MAX), "normal": n.astype(F32), "occ": occ,
            "rough": rough, "shadow": sh.astype(F32)}


def composite(alb, nrm, orm, layer):
    """The deck maps (linear albedo (H, W, 3), unit normals (H, W, 3), ORM (H, W, 3) in 0..1) with the painted
    layer over them. Returns new arrays."""
    cov = layer["cov"][..., None]
    sh = layer["shadow"]
    outside = (1.0 - layer["cov"])
    a = alb * (1.0 - 0.22 * sh * outside)[..., None]
    a = a * (1 - cov) + layer["albedo"] * cov
    n = nrm * (1 - cov) + layer["normal"] * cov
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    o = orm.copy()
    o[..., 0] = orm[..., 0] * (1.0 - 0.45 * sh * outside) * (1 - layer["cov"]) + layer["occ"] * layer["cov"]
    o[..., 1] = orm[..., 1] * (1 - layer["cov"]) + layer["rough"] * layer["cov"]
    o[..., 2] = orm[..., 2] * (1.0 - np.clip(layer["cov"] + np.clip(sh - 0.5, 0, 1) * 2.0, 0.0, 1.0))
    return a.astype(F32), n.astype(F32), o.astype(F32)
