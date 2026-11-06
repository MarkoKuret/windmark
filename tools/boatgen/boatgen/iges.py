"""A minimal IGES reader for measured sail geometry (docs/specs/sail_visuals.md 6.5, the surface source): the
directory and parameter sections, rational B-spline surfaces (type 128) and curves (type 126), composite curves
(102), curves on a surface (142) and trimmed surfaces (144). Read only, as data: nothing in the file is executed.
"""
import numpy as np


class IgesError(ValueError):
    pass


def _num(s):
    s = s.strip()
    if not s:
        return 0.0
    return float(s.replace("D", "E").replace("d", "e"))


def read(path):
    """The entities of an IGES file: {de: {"type", "form", "params" (list of numbers; strings left as text)}}, `de`
    the entity's directory-entry line number (odd, from 1), as the parameter data refers to it."""
    with open(path, errors="ignore") as f:
        lines = f.read().splitlines()
    G = "".join(ln[:72] for ln in lines if len(ln) >= 73 and ln[72] == "G")
    pd = G[2] if len(G) > 2 and G[:2] == "1H" else ","
    rd = ";"
    if len(G) > 6 and G[3:5] == "1H":
        rd = G[5]
    D = [ln for ln in lines if len(ln) >= 73 and ln[72] == "D"]
    P = {}
    for ln in lines:
        if len(ln) >= 73 and ln[72] == "P":
            de = int(ln[64:72])
            P[de] = P.get(de, "") + ln[:64]
    if len(D) % 2:
        raise IgesError(f"{path}: odd directory section")
    out = {}
    for i in range(0, len(D), 2):
        typ = int(D[i][0:8])
        form = int(D[i + 1][32:40] or 0)
        de = i + 1
        raw = P.get(de, "").split(rd)[0]
        vals = []
        for tok in raw.split(pd)[1:]:
            try:
                vals.append(_num(tok))
            except ValueError:
                vals.append(tok.strip())
        out[de] = {"type": typ, "form": form, "params": vals}
    return out


def _basis(kn, deg, u):
    """B-spline basis functions (n_ctrl, len(u)) of the knot vector kn and degree deg at the parameters u."""
    kn = np.asarray(kn, dtype=np.float64)
    u = np.clip(np.atleast_1d(np.asarray(u, dtype=np.float64)), kn[deg], kn[-deg - 1])   # within the live range
    n = len(kn) - deg - 1
    B = np.zeros((len(kn) - 1, len(u)))
    for i in range(len(kn) - 1):
        B[i] = (kn[i] <= u) & (u < kn[i + 1])
    last = np.nonzero(kn[:-1] < kn[1:])[0][-1]      # u at the end of the range falls in the last live span
    B[last, u >= kn[-1]] = 1.0
    for k in range(1, deg + 1):
        Bn = np.zeros((len(kn) - 1 - k, len(u)))
        for i in range(len(kn) - 1 - k):
            d1, d2 = kn[i + k] - kn[i], kn[i + k + 1] - kn[i + 1]
            if d1 > 0:
                Bn[i] += (u - kn[i]) / d1 * B[i]
            if d2 > 0:
                Bn[i] += (kn[i + k + 1] - u) / d2 * B[i + 1]
        B = Bn
    return B[:n]


class Surface:
    """A rational B-spline surface (IGES type 128): eval(u, v) on its own parameter ranges."""

    def __init__(self, p):
        k1, k2, m1, m2 = (int(x) for x in p[:4])
        q = 9
        n1, n2 = k1 + m1 + 2, k2 + m2 + 2
        self.s = np.array(p[q:q + n1]); q += n1
        self.t = np.array(p[q:q + n2]); q += n2
        nc = (k1 + 1) * (k2 + 1)
        self.w = np.array(p[q:q + nc]).reshape(k2 + 1, k1 + 1); q += nc
        self.c = np.array(p[q:q + 3 * nc]).reshape(k2 + 1, k1 + 1, 3); q += 3 * nc
        self.u0, self.u1, self.v0, self.v1 = (float(x) for x in p[q:q + 4])
        self.m1, self.m2 = m1, m2

    def grid(self, u, v):
        """Points (len(v), len(u), 3) at every pair of the parameters u (first direction) and v (second)."""
        Bu = _basis(self.s, self.m1, u)            # (k1+1, nu)
        Bv = _basis(self.t, self.m2, v)            # (k2+1, nv)
        W = np.einsum("ji,ia,jb->ba", self.w, Bu, Bv)
        C = np.einsum("ji,jik,ia,jb->bak", self.w, self.c, Bu, Bv)
        return C / W[..., None]

    def at(self, u, v):
        """Points (n, 3) at the parameter pairs (u[k], v[k])."""
        u, v = np.atleast_1d(u), np.atleast_1d(v)
        Bu = _basis(self.s, self.m1, u)
        Bv = _basis(self.t, self.m2, v)
        W = np.einsum("ji,in,jn->n", self.w, Bu, Bv)
        C = np.einsum("ji,jik,in,jn->nk", self.w, self.c, Bu, Bv)
        return C / W[:, None]


class Curve:
    """A rational B-spline curve (IGES type 126): eval(u) on its own parameter range."""

    def __init__(self, p):
        k, m = int(p[0]), int(p[1])
        q = 6
        self.kn = np.array(p[q:q + k + m + 2]); q += k + m + 2
        self.w = np.array(p[q:q + k + 1]); q += k + 1
        self.c = np.array(p[q:q + 3 * (k + 1)]).reshape(k + 1, 3); q += 3 * (k + 1)
        self.u0, self.u1 = float(p[q]), float(p[q + 1])
        self.m = m

    def at(self, u):
        B = _basis(self.kn, self.m, u)
        W = self.w @ B
        return (self.c.T @ (B * self.w[:, None])).T / W[:, None]

    def sample(self, n):
        return self.at(np.linspace(self.u0, self.u1, n))


def curve_points(ents, de, n=64):
    """A model-space curve (126, or a composite 102 of them) sampled into a polyline (m, 3)."""
    e = ents[de]
    if e["type"] == 126:
        return Curve(e["params"]).sample(n)
    if e["type"] == 102:
        k = int(e["params"][0])
        parts = [curve_points(ents, int(d), n) for d in e["params"][1:1 + k]]
        return np.vstack(parts)
    raise IgesError(f"curve entity {de}: type {e['type']} not read")


def trimmed_surfaces(ents):
    """The trimmed surfaces (144) of a file: [{"de", "surface" (Surface), "outer" (model-space polyline of its outer
    boundary, or None)}]; plain surfaces (128) not referred to by a trimmed one are listed with outer None."""
    out, used = [], set()
    for de, e in sorted(ents.items()):
        if e["type"] != 144:
            continue
        sd, _, _, outer = (int(x) for x in e["params"][:4])
        used.add(sd)
        poly = None
        if outer and ents.get(outer, {}).get("type") == 142:
            p = ents[outer]["params"]
            model = int(p[3])
            if model and model in ents:
                poly = curve_points(ents, model)
        out.append({"de": de, "surface": Surface(ents[sd]["params"]), "outer": poly})
    for de, e in sorted(ents.items()):
        if e["type"] == 128 and de not in used:
            out.append({"de": de, "surface": Surface(e["params"]), "outer": None})
    return out
