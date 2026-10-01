"""Command line (tools/liverybake/README.md):

    python3 -m liverybake [CLASS ...] [--livery ID] [--force] [--only PART ...] [--deck] [--no-stage]
                          [--stage-only] [--out DIR] [--hull-size N] [--sail-size N] [--quiet]

Bakes the starting livery textures of each class (default: every data/liveries/*.liveries.json) into
data/liveries/<class>/ where they are missing, never over hand-edited files unless asked (--force, --only), then
stages them for the game (game/generated/liveries, with Godot import settings).
"""
import argparse
import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np

from . import cloth, geometry, hull, sails, text
from .common import DATA, STAGE, Writer, save_normal, save_orm, save_png

PARTS = ("hull", "keel", "deck", "sails")


def livery_file(class_id, data=DATA):
    return json.loads((Path(data) / f"{class_id}.liveries.json").read_text())


def _write_json(path, obj):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(obj, indent=1, default=float) + "\n")


def _r(v, n=6):
    return [round(float(x), n) for x in v]


def bake_class(class_id, a, writer, log):
    liv = livery_file(class_id, a.data)
    geo = geometry.load(class_id)
    out = Path(a.out) / class_id
    origin = geo["origin_x"]
    for lv in liv["liveries"]:
        if a.livery and lv["id"] not in a.livery:
            continue
        folder = out / lv["id"]
        key = f"{class_id}:{lv['id']}"
        new_folder = writer.may_write(folder, "*")
        lay_path = folder / "layout.json"
        lay = json.loads(lay_path.read_text()) if lay_path.exists() else {}
        lay.update({"schema": "windmark.liverylayout/1", "class": class_id, "livery": lv["id"]})
        changed = False
        if new_folder or writer.may_write(folder, "hull"):
            t = time.time()
            r = hull.bake_hull(geo, lv, a.hull_size, a.hull_size // 2, key=key)
            paths = [folder / "hull_albedo.png", folder / "hull_normal.png", folder / "hull_orm.png"]
            save_png(paths[0], r["albedo"], srgb=True)
            save_normal(paths[1], r["normal"])
            save_png(paths[2], r["orm"], srgb=False)
            writer.note(paths, True)
            log(f"{class_id}/{lv['id']}: hull {a.hull_size}x{a.hull_size // 2} in {time.time() - t:.1f} s")
            changed = True
        else:
            writer.note([folder / "hull_*.png"], False)
        if new_folder or writer.may_write(folder, "keel"):
            r = hull.bake_keel(geo, lv, a.keel_size, key=key)
            save_png(folder / "keel_albedo.png", r["albedo"], srgb=True)
            x0, z0, x1, z1 = r["rect"]
            lay["keel"] = {"rect": _r([x0 - origin, z1, x1 - x0, z1 - z0]), "size": list(r["size"])}
            writer.note([folder / "keel_albedo.png"], True)
            changed = True
        if a.deck and (new_folder or writer.may_write(folder, "deck") or not (folder / "deck_albedo.png").exists()):
            r = hull.bake_deck(geo, lv)
            save_png(folder / "deck_albedo.png", r["albedo"], srgb=True)
            x0, y0, x1, y1 = r["rect"]
            lay["deck"] = {"rect": _r([x0 - origin, y1, x1 - x0, y1 - y0]), "size": list(r["size"])}
            writer.note([folder / "deck_albedo.png"], True)
            changed = True
        if changed:
            _write_json(lay_path, lay)
    # the class sail set, shared by every boat
    folder = out / "sails"
    want = [s for s in geo["sails"] if writer.may_write(folder, "sails") or writer.may_write(folder, s["id"])]
    if not want:
        writer.note([folder / "*"], False)
        return
    boats = liv.get("boats", [])
    nations = [b["nation"] for b in boats if b.get("nation")]
    nation_asp = max([text.aspect(n) for n in nations] + [text.aspect("MMM")]) if nations else 0.0
    number_asp = max([text.aspect(b["sail_number"]) for b in boats] + [text.aspect("888")])
    lay_path = folder / "layout.json"
    lay = json.loads(lay_path.read_text()) if lay_path.exists() else {}
    lay.update({"schema": "windmark.saillayout/1", "class": class_id})
    lay.setdefault("sails", {})
    for s in want:
        t = time.time()
        r = sails.bake_sail(s, liv, geo["loa"], liv["insignia"]["text"], nation_asp, number_asp, a.sail_size,
                            key=class_id)
        sid = s["id"]
        paths = [folder / f"{sid}_port_albedo.png", folder / f"{sid}_stbd_albedo.png", folder / f"{sid}_normal.png",
                 folder / f"{sid}_orm.png"]
        save_png(paths[0], r["albedo_port"], srgb=True)
        save_png(paths[1], r["albedo_stbd"], srgb=True)
        save_normal(paths[2], r["normal"])
        save_png(paths[3], r["orm"], srgb=False)
        writer.note(paths, True)
        info = r["info"]
        tx = info["text"]
        lay["sails"][sid] = {
            "type": info["type"], "cloth": info["cloth"], "shear": _r(info["shear"], 7), "rect": _r(info["rect"]),
            "size": info["size"], "texel_m": round(info["texel_m"], 6),
            "text": {"axis": _r(tx["axis"], 7), "up": _r(tx["up"], 7), "tack": _r(tx["tack"]), "h": round(tx["h"], 4),
                     "rows": [{"kind": rw["kind"], "port": _r(rw["port"], 4), "stbd": _r(rw["stbd"], 4)}
                              for rw in tx["rows"]]},
        }
        log(f"{class_id}/sails/{sid}: {info['cloth']} {info['size'][0]}x{info['size'][1]} in {time.time() - t:.1f} s"
            + ("" if info["arc_ok"] else " (numbers outside the rules' arc)"))
    _write_json(lay_path, lay)


# ----------------------------------------------------------------------------------------------------------------
# staging for the game: copies with Godot import settings (game/generated is git-ignored)

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode={mode}
compress/high_quality={hq}
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def import_settings(name):
    """VRAM-compressed with mipmaps: albedo in the high-quality format (BPTC / ASTC), normal maps as two-channel
    RGTC, ORM in the standard format; the cloth detail tiles lossless."""
    if name.startswith("_cloth/"):
        return IMPORT.format(mode=0, hq="false", normal=2)
    if name.endswith("_normal.png"):
        return IMPORT.format(mode=2, hq="false", normal=1)
    if name.endswith("_albedo.png"):
        return IMPORT.format(mode=2, hq="true", normal=2)
    return IMPORT.format(mode=2, hq="false", normal=2)


def stage(classes, data=DATA, dest=STAGE, log=print):
    """Copies the livery textures and layouts of `classes` to `dest` (only changed files), writes each image's
    import settings once, and writes the shared cloth detail tiles. Returns the number of files copied."""
    n = 0
    for c in classes:
        src = Path(data) / c
        if not src.exists():
            continue
        for f in sorted(src.rglob("*")):
            if f.is_dir() or f.suffix not in (".png", ".json"):
                continue
            rel = f.relative_to(Path(data))
            d = Path(dest) / rel
            d.parent.mkdir(parents=True, exist_ok=True)
            if not d.exists() or d.read_bytes() != f.read_bytes():
                shutil.copyfile(f, d)
                n += 1
            if f.suffix == ".png":
                imp = d.with_name(d.name + ".import")
                if not imp.exists():
                    imp.write_text(import_settings(str(rel.as_posix())))
    cdir = Path(dest) / "_cloth"
    cdir.mkdir(parents=True, exist_ok=True)
    for name in sails.CLOTHS:
        p = cdir / f"{name}_detail.png"
        if not p.exists():
            save_png(p, cloth.detail(name), srgb=False)
            n += 1
        imp = p.with_name(p.name + ".import")
        if not imp.exists():
            imp.write_text(import_settings(f"_cloth/{p.name}"))
    log(f"staged {n} changed files in {dest}")
    return n


def main(argv=None):
    ap = argparse.ArgumentParser(prog="liverybake", description=__doc__.split("\n\n")[0])
    ap.add_argument("classes", nargs="*", help="class ids (default: every data/liveries/*.liveries.json)")
    ap.add_argument("--livery", action="append", default=[], help="only this livery id (repeatable)")
    ap.add_argument("--force", action="store_true", help="rewrite the selected folders, hand edits included")
    ap.add_argument("--only", action="append", default=[], help="rewrite only these parts: hull, keel, deck, sails "
                                                                  "or a sail id (repeatable)")
    ap.add_argument("--deck", action="store_true", help="also write the optional deck colour template")
    ap.add_argument("--no-stage", action="store_true", help="do not stage the textures for the game")
    ap.add_argument("--stage-only", action="store_true", help="only stage (no bake)")
    ap.add_argument("--data", default=str(DATA), help="livery files folder (default data/liveries)")
    ap.add_argument("--out", default=None, help="texture output folder (default: the data folder)")
    ap.add_argument("--stage-dir", default=str(STAGE))
    ap.add_argument("--hull-size", type=int, default=4096)
    ap.add_argument("--sail-size", type=int, default=2048)
    ap.add_argument("--keel-size", type=int, default=1024)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    np.seterr(all="ignore")
    a.out = a.out or a.data
    log = (lambda *x: None) if a.quiet else print
    for p in a.only:
        if p not in PARTS and not p.replace("_", "").isalnum():
            ap.error(f"--only {p}: one of {', '.join(PARTS)} or a sail id")
    classes = a.classes or sorted(p.name.split(".")[0] for p in Path(a.data).glob("*.liveries.json"))
    if not a.stage_only:
        writer = Writer(force=a.force, only=a.only)
        for c in classes:
            bake_class(c, a, writer, log)
        if writer.kept and not writer.written:
            log("kept the existing (hand-owned) textures; --force or --only PART to rebake")
    if not a.no_stage:
        stage(classes, a.out, a.stage_dir, log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
