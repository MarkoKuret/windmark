"""Every fitting touches what it is fitted to (tools/boatgen/README.md "Attachments"): the tiller on the rudder head,
the mainsheet blocks on the boom and the traveller car, the shroud and stay ends on their rigging screws, chainplates,
stemhead, spreader tips and mast, and all deck hardware on the deck, with no gap over 5 mm on the meshes as built.

Run from tools/boatgen: python3 -m unittest discover -s tests
"""
import os
import unittest

import numpy as np

from boatgen import classfile
from boatgen.attach import MAX_GAP, gap, pieces
from boatgen.build import Boat
from boatgen.mesh import Part, superellipsoid_box, tube

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "data", "classes")

# attachments every class must have (piece, one of the hosts), and those of its steering and rig
REQUIRED = [
    ("mainsheet_upper", "mainsheet_bail"), ("mainsheet_bail", "boom"), ("mainsheet_lower", "traveller_car"),
    ("traveller_car", "traveller"), ("traveller", "deck"),
    ("mainsheet_part_0", "mainsheet_upper"), ("mainsheet_part_0", "mainsheet_lower"),
    ("cap_port_0_a", "screw_cap_port"), ("cap_stbd_0_a", "screw_cap_stbd"), ("screw_cap_port", "chainplate_port_cap"),
    ("lower_port_a", "screw_lower_port"), ("screw_lower_port", "chainplate_port_lower"), ("lower_port_b", "mast"),
    ("chainplate_port_cap", "deck"), ("chainplate_stbd_cap", "deck"), ("chainplate_port", "deck"),
    ("forestay_a", "screw_forestay"), ("forestay_b", "hounds"), ("screw_forestay", "stemhead"), ("stemhead", "deck"),
    ("mast_step", "deck"), ("spreader_0_port", "mast"), ("gooseneck", "mast"), ("vang_foot", "vang_tang"),
    ("boom_bail", "boom"), ("jib_track_1", "deck"), ("jib_car_1", "jib_track_1"), ("winch_primary_1", "deck"),
    ("keel_fin", "hull"),
]
REQUIRED_TILLER = [("tiller", "tiller_socket"), ("tiller_socket", "rudder_head"), ("tiller_bolt", "rudder_head"),
                   ("rudder_head", "rudder"), ("pintle_strap_0", "gudgeon_0"), ("gudgeon_plate_0", "deck")]
REQUIRED_WHEEL = [("wheel", "wheel_shaft"), ("pedestal", "deck"), ("rudder_bearing", "deck"), ("rudder_stock", "hull")]
REQUIRED_BACKSTAY = [("backstay_a", "crane")]
REQUIRED_BACKSTAY_SPLIT = [("backstay_b", "backstay_split"), ("backstay_leg_port_b", "screw_backstay_port"),
                           ("screw_backstay_port", "backstay_plate_port"), ("backstay_plate_port", "deck")]
REQUIRED_BACKSTAY_SINGLE = [("backstay_b", "screw_backstay"), ("screw_backstay", "backstay_plate"),
                            ("backstay_plate", "deck")]


class GapMeasureTest(unittest.TestCase):
    """The measure itself: touching, cutting in and apart."""

    def test_measure(self):
        plate = superellipsoid_box((0.2, 0.2, 0.01), 0.2, center=(0, 0, -0.005))     # top face at z = 0
        T = plate.P[plate.I]
        # a post standing on it, 4 mm and 20 mm above it, and one pushed right through it (no vertex near a face)
        for z0, want in ((0.0, 0.0), (0.004, 0.004), (0.02, 0.02), (-0.03, 0.0)):
            with self.subTest(z0=z0):
                p = Part().add("metal", tube(np.array([[0, 0, z0], [0, 0, z0 + 0.3]]), 0.01, 8), tag="post")
                pts = pieces([p])["post"][0]
                self.assertAlmostEqual(gap(pts, T), want, delta=0.0015)


class AttachmentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        np.seterr(all="ignore")
        cls.boats = {cid: _boat(cid)
                     for cid in ("wm7", "wm12", "wm16", "wm21")}
        cls.gaps = {cid: b.attachment_gaps() for cid, b in cls.boats.items()}

    def test_no_gaps(self):
        for cid, gs in self.gaps.items():
            bad = [f"{piece} -> {'|'.join(hosts)}: {1000 * g:.1f} mm" for piece, hosts, g in gs if g > MAX_GAP]
            with self.subTest(boat=cid):
                self.assertFalse(bad, f"{cid}: {len(bad)} of {len(gs)} fittings stand off their host:\n  "
                                 + "\n  ".join(bad))

    def test_required(self):
        for cid, gs in self.gaps.items():
            boat = self.boats[cid]
            have = {(piece, h) for piece, hosts, _ in gs for h in hosts}
            want = list(REQUIRED)
            want += REQUIRED_WHEEL if boat.cls["deck"]["steering"] == "wheel" else REQUIRED_TILLER
            want += [(f"grinder_{k}", "deck") for k in range(boat.cls["deck"].get("grinders", 0))]
            if boat.cls["deck"]["wheel"].get("twin") and boat.cls["deck"]["steering"] == "wheel":
                want += [("wheel_2", "wheel_shaft_2"), ("wheel_shaft_2", "binnacle_2"), ("pedestal_2", "deck")]
            if boat.cls["rig"]["backstay"]:
                want += REQUIRED_BACKSTAY
                want += REQUIRED_BACKSTAY_SPLIT if boat.rig.split_backstay() else REQUIRED_BACKSTAY_SINGLE
            for n in range(len(boat.rig.spreaders)):
                want += [(f"cap_port_{n}_b", f"spreader_{n}_port_tip"), (f"cap_stbd_{n}_b", f"spreader_{n}_stbd_tip")]
            want += [(f"cap_port_{len(boat.rig.spreaders)}_b", "mast")]
            if boat.rig.sprit > 0:
                want += [("bobstay_a", "sprit_end"), ("bobstay_b", "bobstay_eye"), ("bobstay_eye", "hull")]
            missing = [w for w in want if w not in have]
            with self.subTest(boat=cid):
                self.assertFalse(missing, f"{cid}: attachments not recorded: {missing}")
            with self.subTest(boat=cid, what="count"):
                self.assertGreater(len(gs), 100)


class LifelineTest(unittest.TestCase):
    """Every lifeline segment ends on its fitting (a stanchion's top or eye, the pushpit or the pulpit) with no gap,
    every stanchion between the pushpit and the pulpit carries both tiers, and the layout is a real boat's: the
    stanchions stand between the pushpit's and the pulpit's ends, none doubling one of their legs, at most 2.2 m
    apart (data_format.md 3.7 look rules)."""

    @classmethod
    def setUpClass(cls):
        np.seterr(all="ignore")
        cls.boats = {cid: _boat(cid) for cid in ("wm7", "wm12", "wm16", "wm21")}

    def _recs(self):
        for cid, boat in self.boats.items():
            if boat.cls["deck"]["lifelines"]:
                self.assertIsNotNone(boat.lifelines)
                yield cid, boat, boat.lifelines

    def test_segment_ends_on_their_fittings(self):
        n = 0
        for cid, boat, rec in self._recs():
            geo = pieces(boat.parts)
            bad = []
            for name, tier, a, b, ha, hb in rec["segments"]:
                pts = geo[name][0]
                for end, host in ((a, ha), (b, hb)):
                    near = pts[np.linalg.norm(pts - end, axis=1) < 0.02]       # the segment's last 2 cm
                    g = gap(near, geo[host][1]) if len(near) else np.inf
                    n += 1
                    if g > 0.001:
                        bad.append(f"{name} end on {host}: {1000 * g:.1f} mm")
            with self.subTest(boat=cid):
                self.assertFalse(bad, f"{cid}: lifeline ends off their fittings:\n  " + "\n  ".join(bad))
        self.assertGreater(n, 20)

    def test_every_stanchion_carries_both_tiers(self):
        for cid, boat, rec in self._recs():
            segs = {}
            for name, tier, a, b, ha, hb in rec["segments"]:
                segs.setdefault((name.split("_")[1], tier), []).append((a, b))

            def dist(p, side, tier):
                d = np.inf
                for a, b in segs[(side, tier)]:
                    t = np.clip((p - a) @ (b - a) / max((b - a) @ (b - a), 1e-12), 0, 1)
                    d = min(d, float(np.linalg.norm(a + t * (b - a) - p)))
                return d
            bad = []
            for st, (top, eye) in rec["stanchions"].items():
                side = st.split("_")[1]
                for tier, p in ((1.0, top), (0.55, eye)):
                    if dist(p, side, tier) > 0.001:
                        bad.append(f"{st} tier {tier}: {1000 * dist(p, side, tier):.1f} mm off the line")
                    hosts = [h for _, t, _a, _b, ha, hb in rec["segments"] if t == tier for h in (ha, hb)]
                    if hosts.count(st) != 2:
                        bad.append(f"{st} tier {tier}: {hosts.count(st)} segment ends on it, not 2")
            with self.subTest(boat=cid):
                self.assertFalse(bad, f"{cid}: stanchions the lifelines miss:\n  " + "\n  ".join(bad))

    def test_layout(self):
        for cid, boat, rec in self._recs():
            for side in ("1", "-1"):
                xs = sorted(float(t[0]) for nm, (t, e) in rec["stanchions"].items() if nm.split("_")[1] == side)
                up = [s for s in rec["segments"] if s[0].split("_")[1] == side and s[1] == 1.0]
                aft = [float(s[2][0]) for s in up if s[4].startswith("pushpit")]
                fwd = [float(s[3][0]) for s in up if s[5] == "pulpit"]
                with self.subTest(boat=cid, side=side):
                    self.assertEqual((len(aft), len(fwd)), (1, 1), "each tier runs from the pushpit to the pulpit")
                    spacing = np.diff([aft[0]] + xs + [fwd[0]])
                    self.assertTrue(np.all(spacing > 1.0), f"a stanchion doubles a fitting: spacing {spacing}")
                    self.assertTrue(np.all(spacing <= 2.2), f"stanchions over 2.2 m apart: {spacing}")


class RopeLeadTest(unittest.TestCase):
    """The halyards led from the mast foot lie on the deck and the coachroof where they run along them (the rope's
    underside 0 to 5 mm off the deck mesh), are never inside the deck or the coachroof anywhere, and pass through
    their exit plate, turning block, organiser and clutch (data_format.md 3.7 look rules)."""

    @classmethod
    def setUpClass(cls):
        np.seterr(all="ignore")
        cls.boats = {cid: _boat(cid) for cid in ("wm7", "wm12", "wm16", "wm21")}

    def test_leads_lie_on_the_deck(self):
        from boatgen.attach import _point_tri_dist
        for cid, boat in self.boats.items():
            deck = boat.deck
            T = pieces([boat.parts["deck"]])["deck"][1]
            self.assertTrue(boat.rope_paths, f"{cid}: no halyard leads recorded")
            bad = []
            for tag, (P, r, flags) in boat.rope_paths.items():
                lying = 0.0
                for a, b, fa, fb in zip(P[:-1], P[1:], flags[:-1], flags[1:]):
                    n = max(1, int(np.ceil(np.linalg.norm(b - a) / 0.01)))
                    q = a + (b - a) * np.linspace(0, 1, n + 1)[:, None]
                    under = q[:, 2] - r - deck.surface_z(q[:, 0], q[:, 1])      # the rope's underside
                    ondeck = np.abs(q[:, 1]) < deck.hull.bs(q[:, 0]) - 0.03
                    if np.any(ondeck & (under < -0.0005)):
                        i = int(np.argmin(np.where(ondeck, under, np.inf)))
                        bad.append(f"{tag}: {-1000 * under[i]:.1f} mm into the surface at x {q[i, 0]:.2f}")
                        break
                    if fa and fb:                       # a span along the surface: lying on the deck mesh
                        d = _point_tri_dist(q, T) - r
                        lying += float(np.linalg.norm(b - a))
                        if d.max() > 0.005:
                            i = int(np.argmax(d))
                            bad.append(f"{tag}: {1000 * d[i]:.1f} mm above the deck mesh at x {q[i, 0]:.2f}")
                            break
                if lying < 0.5:
                    bad.append(f"{tag}: only {lying:.2f} m lying on the deck")
            with self.subTest(boat=cid):
                self.assertFalse(bad, f"{cid}: leads off the surface:\n  " + "\n  ".join(bad))

    def test_leads_pass_their_fittings(self):
        for cid, boat in self.boats.items():
            gs = {(p, h): g for p, hs, g in boat.attachment_gaps() for h in hs}
            for tag in boat.rope_paths:
                side, k = tag.split("_")[1:3]
                for host in (f"halyard_exit_{side}_{k}", f"mast_block_{side}_{k}", f"organiser_{side}",
                             f"clutches_{side}"):
                    with self.subTest(boat=cid, lead=tag, host=host):
                        self.assertIn((tag, host), gs)
                        self.assertLessEqual(gs[(tag, host)], MAX_GAP)


_BOATS = {}


def _boat(cid):
    """The class built once for every test class here."""
    if cid not in _BOATS:
        _BOATS[cid] = Boat(classfile.load(os.path.join(CLASSES, f"{cid}.boat.json")), log=lambda *a: None)
    return _BOATS[cid]
