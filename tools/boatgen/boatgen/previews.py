"""Preview images of a generated boat, rendered headless from the exported GLB files."""
import os

import numpy as np

from . import lines
from .render import Renderer, orbit


def heel_matrix(deg):
    """Heel to starboard in the glTF frame (rotation about +Z, the bow axis): +Y tips toward -X."""
    a = np.radians(deg)
    return np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1.0]])


def render_all(boat, out_dir, preview_dir, size=(1600, 1000), log=print):
    os.makedirs(preview_dir, exist_ok=True)
    cid = boat.cls["id"]
    L = boat.hull.L
    top = boat.rig.z_top
    glb = os.path.join(out_dir, f"{cid}.glb")
    files = []
    r = Renderer(*size)

    def shot(name, **kw):
        path = os.path.join(preview_dir, f"{cid}_{name}.png")
        r.render(path, **kw)
        files.append(path)

    # 1. hero: upwind, heeled, from the windward bow quarter
    posed = os.path.join(out_dir, f"{cid}_upwind.glb")
    boat.write_posed_glb(posed, "upwind")
    r.load(posed, transform=heel_matrix(14))
    t = np.array([0.0, 0.36 * top, 0.05 * L])
    shot("upwind", eye=orbit(t, 1.95 * top, 38, 9), target=t, fov=36)
    # 2. deck: flat standard model from the starboard quarter, sails hidden
    r.load(glb, hide=("sail_",))
    t = np.array([0.0, 0.55, -0.12 * L])
    shot("deck", eye=orbit(t, 0.62 * L, -145, 34), target=t, fov=42)
    # 3. profile: the model as exported (flat standard sails), dry, from starboard
    r.load(glb, hide=tuple(f"sail_{sid}" for sid, s in boat.sails.items() if s.type not in ("main", "jib", "genoa")))
    t = np.array([0.0, 0.42 * top - 0.3 * boat.app.draft, 0.1 * L])
    shot("profile", eye=orbit(t, 2.2 * top, -90, 3), target=t, fov=33, water=False, ground=True)
    # 4. downwind with the spinnaker (or reaching with a code zero)
    kinds = {s.type for s in boat.sails.values()}
    pose = "downwind" if kinds & {"spinnaker_asym", "spinnaker_sym"} else ("reaching" if "code_zero" in kinds else None)
    if pose:
        posed = os.path.join(out_dir, f"{cid}_{pose}.glb")
        boat.write_posed_glb(posed, pose)
        r.load(posed, transform=heel_matrix(7))
        t = np.array([-0.1 * L, 0.38 * top, 0.1 * L])
        shot(pose, eye=orbit(t, 2.0 * top, -128, 8), target=t, fov=38)
    # 5. uv check on the flat model
    r.load(glb, hide=("sail_",))
    t = np.array([0.0, 0.2, 0.0])
    shot("uv", eye=orbit(t, 0.95 * L, -38, 22), target=t, fov=40, uv_check=True, water=False, ground=True)
    # 6. lines plan
    path = os.path.join(preview_dir, f"{cid}_lines.png")
    lines.draw(boat.hull, {"draft": boat.app.draft, "profiles": boat.app.profiles()}, path,
               f"{boat.cls['name']}: lines (profile with buttocks, half-breadths with waterlines, body plan)")
    files.append(path)
    log(f"  previews: {', '.join(os.path.basename(f) for f in files)} ({r.tri_count} triangles in the last view)")
    return files
