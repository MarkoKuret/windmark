"""Command line: python3 -m boatgen CLASS.boat.json [...] [--out DIR] [--previews DIR] [--no-previews]"""
import argparse
import json
import os
import sys
import time

import numpy as np

from . import classfile, physics, sail_set, textures
from .build import Boat


# Godot import settings of the boat GLBs: the engine's automatic levels of detail (sail_visuals.md 11.4), no
# shadow meshes (the generator writes the shadow proxy); written once, Godot completes the file on import
GLB_IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

meshes/ensure_tangents=false
meshes/generate_lods=true
meshes/create_shadow_meshes=false
meshes/light_baking=0
"""


def write_import(path):
    imp = path + ".import"
    if not os.path.exists(imp) or "meshes/generate_lods=true" not in open(imp).read():
        with open(imp, "w") as f:
            f.write(GLB_IMPORT)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="boatgen", description="Build a boat model and physics sidecar from a class file")
    ap.add_argument("classes", nargs="+", help="boat-class files (windmark.boatclass/1)")
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--out", default=os.path.join(here, "out"), help="output directory for .glb and .json")
    ap.add_argument("--previews", default=os.path.join(here, "previews"), help="preview image directory")
    ap.add_argument("--no-previews", action="store_true", help="skip rendering")
    ap.add_argument("--size", default="1600x1000", help="preview size WxH")
    ap.add_argument("--no-textures", action="store_true", help="PBR factors only, no embedded texture set")
    ap.add_argument("--no-bake", action="store_true", help="skip the baked ambient occlusion (COLOR_0)")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    # numpy's BLAS on some platforms raises spurious floating-point flags inside matmul; the GLB writer
    # checks every exported array for finite values instead
    np.seterr(all="ignore")
    log = (lambda *x: None) if a.quiet else print
    os.makedirs(a.out, exist_ok=True)
    for path in a.classes:
        t0 = time.time()
        try:
            cls = classfile.load(path)
        except classfile.ClassFileError as e:
            print(f"{path}: {e}", file=sys.stderr)
            return 2
        try:
            boat = Boat(cls, log=log)
        except ValueError as e:         # a sail planform that cannot be drawn (sails.py)
            print(f"{path}: {e}", file=sys.stderr)
            return 2
        boat.textures, boat.bake = not a.no_textures, not a.no_bake
        if boat.textures:
            textures.write_shared(a.out)
            boat.tex_uri = "_tex"
        cid = cls["id"]
        glb = os.path.join(a.out, f"{cid}.glb")
        parts = boat.write_game_glb(glb)
        write_import(glb)
        tris, surf, sail_tris = boat.model_counts(parts)
        game = {"triangles": tris, "surfaces": surf, "sail_triangles": sail_tris,
                "nodes": sorted(list(parts) + ["shadow"])}
        col = physics.collision(boat)
        physics.write_collision_glb(boat, col, os.path.join(a.out, f"{cid}_collision.glb"))
        side = {
            "schema": "windmark.boatgen.physics/1",
            "class_id": cid, "class_version": cls["version"],
            "frame": "body: x forward, y port, z up, m; origin on the centreline at the DWL, mid LWL. "
                     "GLB axes: (X, Y, Z) = (y, z, x)",
            "hydrostatics": physics.hydrostatics(boat),
            "perf_inputs": physics.perf_inputs(boat),
            "waterline": physics.waterline(boat),
            "buoyancy_samples": physics.buoyancy_samples(boat),
            "collision_meshes": {k: {"vertices": physics._r(physics.to_body(g.P, boat.origin_x()), 4),
                                     "triangles": g.I.tolist()} for k, g in col.items()},
            "rig": physics.rig_data(boat),
            "sails": physics.sail_data(boat),
            "model": {"file": os.path.basename(glb), "triangles": tris, "surfaces": surf, "sail_triangles": sail_tris,
                      "full_triangles": boat.tri_count(), "nodes": game["nodes"], "pivots": sorted(boat.pivots)},
        }
        with open(os.path.join(a.out, f"{cid}.physics.json"), "w") as f:
            json.dump(side, f, indent=1)
        # the preview poses as drawn, for the game's sail shape parity test (sail_set.py)
        sail_set.write_sets(boat, os.path.join(a.out, f"{cid}.sets.json"))
        h = side["hydrostatics"]
        log(f"  game model: {tris} triangles in {surf} surfaces, sails {sail_tris}")
        log(f"  {glb}: full model {boat.tri_count()} triangles; displaced {h['displaced_mass_generated_kg']} kg "
            f"({h['displacement_error_pct']:+.2f} %), LCB {h['lcb_pct_lwl_aft_of_fwd_end']} % LWL, "
            f"Cp {h['prismatic']}, Cm {h['midship']}")
        if not a.no_previews:
            from .previews import render_all
            w, hgt = (int(v) for v in a.size.split("x"))
            render_all(boat, a.out, a.previews, (w, hgt), log=log)
        log(f"  done in {time.time() - t0:.1f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
