"""Sheets for the posed preview models: each set headsail or flying sail gets its working sheet from the clew
through its lead to a winch (wrapped on the drum, tail flaked in the cockpit) and a slack lazy sheet to the other
side; flying sails also get their tack line and halyard.

The exported model has no headsail or kite sheets: those follow the trimmed sail at run time, so the engine
draws them from the lead points in the physics sidecar (`rig.sheet_leads`, physics.py). The mainsheet is its own
node (hardware.py).
"""
import numpy as np

from .hardware import rope, rope_coil, rope_tube
from .mesh import Part, translate


def sheet_leads(boat):
    """Lead points of the sheets, in the boat's internal frame (x from the transom), starboard side (y < 0):
    {"headsail": [car block, winch], "flying": [quarter block, winch]} and the winch drum diameters."""
    lead = boat.leads
    L = boat.hull.L
    s = (L / 12.0) ** 0.7
    xw, yw, zw, dw = lead["primary"]
    car = lead["jib_car"] * [1, -1, 1]
    # flying sails: a block on the aft quarter, near the sheer
    xq = 0.35 * s + 0.25 * s
    yq = float(boat.hull.bs(np.array([xq]))[0]) - 0.1 * s
    zq = float(boat.deck.deck_z(xq, yq)) + 0.06 * s
    fly_w = lead.get("secondary", lead["primary"])
    return {"headsail": {"lead": car, "winch": np.array([xw, -yw, zw]), "drum": dw},
            "flying": {"lead": np.array([xq, -yq, zq]),
                       "winch": np.array([fly_w[0], -fly_w[1], fly_w[2]]), "drum": fly_w[3]}}


def _wrap(winch, drum, r, side=-1.0, turns=3):
    """Turns of line round a winch drum (points from the lower turn up to the tailer)."""
    th = np.linspace(0, 2 * np.pi * turns, 20 * turns)
    rr = 0.5 * drum + r
    z = winch[2] + drum * (0.34 + 0.25 * th / th[-1])
    return np.stack([winch[0] + rr * np.cos(th), winch[1] + side * rr * np.sin(th), z], -1)


def sheets(boat, corners, types):
    """Part with the sheets of the set sails; `corners` maps sail id to its posed {tack, clew, head} points and
    `types` to its sail type. The sails are set to starboard (port tack), so the working sheets are on starboard."""
    part = Part()
    L = boat.hull.L
    s = (L / 12.0) ** 0.7
    r = max(0.0045, 0.0055 * s)
    ld = sheet_leads(boat)
    deck = boat.deck
    for sid, c in corners.items():
        t = types[sid]
        if t == "main":
            continue
        fly = t in ("code_zero", "spinnaker_asym", "spinnaker_sym")
        slot = "rope_kite_sheet" if fly else "rope_sheet"
        k = ld["flying" if fly else "headsail"]
        clew = c["clew"]
        lead, winch, drum = k["lead"], k["winch"], k["drum"]
        wrap = _wrap(winch, drum, r)
        start = wrap[0]
        pts = [clew, lead, start]
        # working sheet: a nearly straight run under load, then the turns on the drum and the tail into the cockpit
        part.add(slot, rope(pts, r, sag=0.004))
        part.add(slot, rope_tube(wrap, r, 6, caps=False))
        top = wrap[-1]
        x_tail = winch[0] - 0.35 * s
        y_tail = -0.5 * float(deck.yc(x_tail))
        zf = float(deck.floor_z(x_tail))
        part.add(slot, rope([top, top + [0.02 * s, 0.05 * s, 0.03 * s], [x_tail, y_tail, zf + r]], r, sag=0.02))
        part.extend(rope_coil(0.13 * s, 3, r, slot), translate([x_tail - 0.1 * s, y_tail, zf]))
        # lazy sheet: slack from the clew round the front of the sail to the other side's lead
        lazy_lead = lead * [1, -1, 1]
        mid = 0.5 * (clew + lazy_lead)
        if fly:
            # a kite's lazy sheet runs round the forestay
            fwd = np.array([boat.rig.x_tack + 0.3 * s, 0.0, boat.rig.z_tack + 1.2 * s])
            part.add(slot, rope([clew, fwd, lazy_lead], r * 0.9, sag=0.06))
        else:
            mid[2] = float(deck.surface(mid[0], mid[1])[0]) + 0.04 * s
            part.add(slot, rope([clew, mid, lazy_lead], r * 0.9, sag=0.01))
        part.add(slot, rope([lazy_lead, lazy_lead + [-0.6 * s, 0, -0.04 * s]], r * 0.9))
        if fly:
            # tack line down to the sprit end or the pole end, halyard from the head into the mast
            tack = c["tack"]
            end = boat.rig.sprit_end if boat.rig.sprit > 0 else boat.rig.pole_end
            if np.linalg.norm(tack - end) > 0.02:
                part.add(slot, rope([tack, end], r))
            head = c["head"]
            mast = np.array([boat.rig.x_mast + 0.5 * boat.rig.chord, 0.0, min(head[2] + 0.05, boat.rig.z_top - 0.1)])
            part.add("rope_halyard_kite", rope([head, mast], r))
    return part
