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
        cls.boats = {cid: Boat(classfile.load(os.path.join(CLASSES, f"{cid}.boat.json")), log=lambda *a: None)
                     for cid in ("wm7", "wm12")}
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
