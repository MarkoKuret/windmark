"""Command line (tools/liverybake/README.md):

    python3 -m liverybake [CLASS ...] [--livery ID] [--force] [--only PART ...] [--no-stage] [--stage-only]
                          [--normals-from-relief] [--out DIR] [--hull-size N] [--transom-size N] [--deck-size N] [--sail-size N]
                          [--rope-size N] [--quiet]

Bakes the starting livery textures of each class (default: every data/liveries/*.liveries.json) into
data/liveries/<class>/ where a part's files are all missing, never over hand-edited files unless asked (--force,
--only), makes each sail's normal map from its relief image (data_format.md §8.5), then stages them for the game
(game/generated/liveries, with Godot import settings).
"""
import argparse
import hashlib
import io
import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

from . import cloth, deck, geometry, hull, ropes, sails, text
from .common import DATA, STAGE, Writer, save_normal, save_orm, save_png, save_relief

PARTS = ("hull", "keel", "transom", "deck", "sails", "ropes")


def livery_file(class_id, data=DATA):
    return json.loads((Path(data) / f"{class_id}.liveries.json").read_text())


def _write_json(path, obj):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(obj, indent=1, default=float) + "\n")


def _r(v, n=6):
    return [round(float(x), n) for x in v]


HULL_FILES = ("hull_albedo.png", "hull_normal.png", "hull_orm.png")
TRANSOM_FILES = ("transom_albedo.png", "transom_normal.png", "transom_orm.png")
DECK_FILES = ("deck_albedo.png", "deck_normal.png", "deck_orm.png")
SAIL_SUFFIXES = ("_port_albedo.png", "_stbd_albedo.png", "_normal.png", "_orm.png", "_relief.png")


def _save_set(folder, names, r):
    """Writes an albedo (sRGB), normal and ORM map (linear) of a bake result."""
    save_png(folder / names[0], r["albedo"], srgb=True)
    save_normal(folder / names[1], r["normal"])
    save_png(folder / names[2], r["orm"], srgb=False)
    return [folder / n for n in names]


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
        lay_path = folder / "layout.json"
        lay = json.loads(lay_path.read_text()) if lay_path.exists() else {}
        lay.update({"schema": "windmark.liverylayout/1", "class": class_id, "livery": lv["id"]})
        changed = False
        if writer.may_write(folder, "hull", HULL_FILES):
            t = time.time()
            r = hull.bake_hull(geo, lv, a.hull_size, a.hull_size // 2, key=key)
            writer.note(_save_set(folder, HULL_FILES, r), True)
            log(f"{class_id}/{lv['id']}: hull {a.hull_size}x{a.hull_size // 2} in {time.time() - t:.1f} s")
            changed = True
        else:
            writer.note([folder / f for f in HULL_FILES], False)
        if writer.may_write(folder, "keel", ("keel_albedo.png",)):
            r = hull.bake_keel(geo, lv, a.keel_size, key=key)
            save_png(folder / "keel_albedo.png", r["albedo"], srgb=True)
            x0, z0, x1, z1 = r["rect"]
            lay["keel"] = {"rect": _r([x0 - origin, z1, x1 - x0, z1 - z0]), "size": list(r["size"])}
            writer.note([folder / "keel_albedo.png"], True)
            changed = True
        if writer.may_write(folder, "transom", TRANSOM_FILES):
            t = time.time()
            r = hull.bake_transom(geo, lv, a.transom_size, key=key)
            writer.note(_save_set(folder, TRANSOM_FILES, r), True)
            lay["transom"] = {"rect": _r(r["rect"]), "size": list(r["size"])}
            log(f"{class_id}/{lv['id']}: transom {r['size'][0]}x{r['size'][1]} in {time.time() - t:.1f} s")
            changed = True
        else:
            writer.note([folder / f for f in TRANSOM_FILES], False)
        if writer.may_write(folder, "deck", DECK_FILES):
            t = time.time()
            r = deck.bake_deck(geo, lv, a.deck_size, key=key)
            writer.note(_save_set(folder, DECK_FILES, r), True)
            x0, yt, w, h = r["rect"]
            lay["deck"] = {"rect": _r([x0 - origin, yt, w, h]), "size": list(r["size"])}
            log(f"{class_id}/{lv['id']}: deck {r['size'][0]}x{r['size'][1]} in {time.time() - t:.1f} s")
            changed = True
        else:
            writer.note([folder / f for f in DECK_FILES], False)
        if changed:
            _write_json(lay_path, lay)
    # the class rope set (data_format.md §8.7), shared by every boat
    folder = out / "rig"
    if writer.may_write(folder, "ropes", ropes.FILES):
        t = time.time()
        r = ropes.bake_ropes(liv, a.rope_size, key=class_id)
        paths = []
        for fn, img in r["albedo"].items():
            paths.append(folder / f"rope_{fn}_albedo.png")
            save_png(paths[-1], img, srgb=True)
        save_normal(folder / "rope_normal.png", r["normal"])
        save_png(folder / "rope_orm.png", r["orm"], srgb=False)
        writer.note(paths + [folder / "rope_normal.png", folder / "rope_orm.png"], True)
        log(f"{class_id}/rig: {len(r['albedo'])} ropes {a.rope_size}x{a.rope_size} in {time.time() - t:.1f} s")
    else:
        writer.note([folder / "*"], False)
    # the class sail set, shared by every boat
    folder = out / "sails"
    want = [s for s in geo["sails"]
            if writer.may_write(folder, s["id"], [s["id"] + x for x in SAIL_SUFFIXES], also=("sails",))]
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
        paths = [folder / (sid + x) for x in SAIL_SUFFIXES]
        save_png(paths[0], r["albedo_port"], srgb=True)
        save_png(paths[1], r["albedo_stbd"], srgb=True)
        save_normal(paths[2], r["normal"])
        save_png(paths[3], r["orm"], srgb=False)
        save_relief(paths[4], r["relief"])
        writer.note(paths, True)
        info = r["info"]
        tx = info["text"]
        lay["sails"][sid] = {
            "type": info["type"], "cloth": info["cloth"], "relief_m": info["relief_m"], "shear": _r(info["shear"], 7),
            "rect": _r(info["rect"]),
            "size": info["size"], "texel_m": round(info["texel_m"], 6),
            "text": {"axis": _r(tx["axis"], 7), "up": _r(tx["up"], 7), "tack": _r(tx["tack"]), "h": round(tx["h"], 4),
                     "rows": [{"kind": rw["kind"], "port": _r(rw["port"], 4), "stbd": _r(rw["stbd"], 4)}
                              for rw in tx["rows"]]},
        }
        log(f"{class_id}/sails/{sid}: {info['cloth']} {info['size'][0]}x{info['size'][1]} in {time.time() - t:.1f} s"
            + ("" if info["arc_ok"] else " (numbers outside the rules' arc)"))
    _write_json(lay_path, lay)


def normals_from_relief(classes, data=DATA, log=print):
    """Rewrites each sail's normal map from its relief image (data_format.md §8.5) where the relief exists and the
    normal map differs from what it gives. Returns the number of maps written."""
    n = 0
    for c in classes:
        folder = Path(data) / c / "sails"
        lay_path = folder / "layout.json"
        if not lay_path.exists():
            continue
        lay = json.loads(lay_path.read_text()).get("sails", {})
        for sid, info in sorted(lay.items()):
            rp, npth = folder / f"{sid}_relief.png", folder / f"{sid}_normal.png"
            if not rp.exists():
                continue
            relief = np.asarray(Image.open(rp).convert("L"))
            nrm = sails.normal_from_relief(relief, float(info["texel_m"]), float(info.get("relief_m", sails.RELIEF_M)))
            enc = (np.clip(nrm * 0.5 + 0.5, 0, 1) * 255.0 + 0.5).astype(np.uint8)
            if npth.exists() and np.array_equal(np.asarray(Image.open(npth).convert("RGB")), enc):
                continue
            save_normal(npth, nrm)
            n += 1
            log(f"{c}/sails/{sid}: normal map made from {rp.name}")
    return n


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


# the hand-owned images the game reads through the boat atlas, not staged themselves
ATLAS_SOURCES = ("hull_", "deck_", "transom_", "keel_")
SAIL_MAPS = ("_albedo.png", "_normal.png", "_orm.png")


def _stamp(folder):
    p = Path(folder) / ".stage.json"
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return {}


def _save_stamp(folder, st):
    p = Path(folder) / ".stage.json"
    js = json.dumps(st, indent=1, sort_keys=True) + "\n"
    if not p.exists() or p.read_text() != js:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(js)


def _digest(*blobs):
    h = hashlib.sha256()
    for b in blobs:
        h.update(b if isinstance(b, bytes) else str(b).encode())
    return h.hexdigest()[:20]


def _half_png(src, normal):
    """A sail image at half its size (Lanczos; normals renormalised), as PNG bytes."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    small = im.resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS)
    a = np.asarray(small, dtype=np.float32) / 255.0
    if normal:
        n = a * 2 - 1
        n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
        a = n * 0.5 + 0.5
    buf = io.BytesIO()
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(buf, "PNG", compress_level=6)
    return buf.getvalue()


def _put(path, data):
    """Writes bytes when they differ; True when written."""
    path = Path(path)
    if path.exists() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def _import_file(d, rel):
    imp = d.with_name(d.name + ".import")
    if not imp.exists():
        imp.write_text(import_settings(rel))


def stage(classes, data=DATA, dest=STAGE, log=print, hd=False):
    """Stages the livery textures of `classes` in `dest` for the game (only changed files) with their import
    settings: per livery the boat atlas (atlas.py: hull, deck with the painted hardware, transom, keel; 2048, or
    4096 with `hd`) and layout.json, the rope set, the sails at half size (full with `hd`) and the shared cloth
    detail tiles. Returns the number of files written."""
    from . import atlas
    n = 0
    code = _digest(*(Path(__file__).with_name(f).read_bytes() for f in ("atlas.py", "painted.py")))
    for c in classes:
        src = Path(data) / c
        if not src.exists():
            continue
        for f in sorted(src.rglob("*")):
            if f.is_dir() or f.suffix not in (".png", ".json") or f.name.endswith("_relief.png"):
                continue    # a relief image is the source of its normal map, the game does not load it
            rel = f.relative_to(Path(data))
            d = Path(dest) / rel
            if f.name.startswith(ATLAS_SOURCES):
                # read through the atlas: a copy staged before is removed
                for old in (d, d.with_name(d.name + ".import")):
                    if old.exists():
                        old.unlink()
                continue
            if f.parent.name == "sails" and f.name.endswith(SAIL_MAPS) and not hd:
                st = _stamp(d.parent)
                key = _digest(f.read_bytes(), "half")
                if st.get(f.name) != key or not d.exists():
                    if _put(d, _half_png(f, f.name.endswith("_normal.png"))):
                        n += 1
                    st[f.name] = key
                    _save_stamp(d.parent, st)
            elif _put(d, f.read_bytes()):
                n += 1
            if f.suffix == ".png":
                _import_file(d, str(rel.as_posix()))
        # the boat atlas of every livery folder with a hull set
        liv = livery_file(c, data) if (Path(data) / f"{c}.liveries.json").exists() else {}
        rs = ropes.rope_set(liv) if liv else {}
        for folder in sorted(p.parent for p in src.glob("*/hull_albedo.png")):
            need = [folder / f"{k}_{m}.png" for k in ("hull", "deck", "transom") for m in ("albedo", "normal", "orm")]
            need.append(folder / "keel_albedo.png")
            if not all(p.exists() for p in need):
                log(f"{folder}: incomplete hull, deck, transom or keel set, no boat atlas")
                continue
            out = Path(dest) / folder.relative_to(Path(data))
            size = 2 * atlas.SIZE if hd else atlas.SIZE
            key = _digest(code, size, geometry._key(c), json.dumps(rs, sort_keys=True),
                          *(p.read_bytes() for p in need))
            st = _stamp(out)
            files = [out / f"atlas_{m}.png" for m in ("albedo", "normal", "orm")] + [out / "atlas.json"]
            if st.get("atlas") == key and all(p.exists() for p in files):
                continue
            t = time.time()
            images, meta = atlas.build(folder, geometry.load(c), rs, size)
            n += len(atlas.write(out, images, meta))
            for m in ("albedo", "normal", "orm"):
                _import_file(out / f"atlas_{m}.png", f"{c}/{folder.name}/atlas_{m}.png")
            st["atlas"] = key
            _save_stamp(out, st)
            log(f"{c}/{folder.name}: boat atlas {size}x{size} in {time.time() - t:.1f} s")
    cdir = Path(dest) / "_cloth"
    cdir.mkdir(parents=True, exist_ok=True)
    for name in sails.CLOTHS:
        p = cdir / f"{name}_detail.png"
        tmp = cdir / f".{name}_detail.png"
        save_png(tmp, cloth.detail(name), srgb=False)
        if not p.exists() or p.read_bytes() != tmp.read_bytes():
            tmp.replace(p)
            n += 1
        else:
            tmp.unlink()
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
    ap.add_argument("--only", action="append", default=[], help="rewrite only these parts: hull, keel, transom, "
                                                                  "deck, sails, ropes or a sail id (repeatable)")
    ap.add_argument("--no-stage", action="store_true", help="do not stage the textures for the game")
    ap.add_argument("--stage-only", action="store_true", help="only stage (no bake)")
    ap.add_argument("--normals-from-relief", action="store_true",
                    help="only make the sails' normal maps from their relief images (no bake), then stage")
    ap.add_argument("--data", default=str(DATA), help="livery files folder (default data/liveries)")
    ap.add_argument("--out", default=None, help="texture output folder (default: the data folder)")
    ap.add_argument("--stage-dir", default=str(STAGE))
    ap.add_argument("--hull-size", type=int, default=4096)
    ap.add_argument("--sail-size", type=int, default=2048)
    ap.add_argument("--keel-size", type=int, default=1024)
    ap.add_argument("--transom-size", type=int, default=2048)
    ap.add_argument("--deck-size", type=int, default=4096)
    ap.add_argument("--rope-size", type=int, default=ropes.SIZE)
    ap.add_argument("--hd", action="store_true", help="stage the boat atlas at 4096 and the sails at full size")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    np.seterr(all="ignore")
    a.out = a.out or a.data
    log = (lambda *x: None) if a.quiet else print
    for p in a.only:
        if p not in PARTS and not p.replace("_", "").isalnum():
            ap.error(f"--only {p}: one of {', '.join(PARTS)} or a sail id")
    classes = a.classes or sorted(p.name.split(".")[0] for p in Path(a.data).glob("*.liveries.json"))
    if not a.stage_only and not a.normals_from_relief:
        writer = Writer(force=a.force, only=a.only)
        for c in classes:
            bake_class(c, a, writer, log)
        if writer.kept and not writer.written:
            log("kept the existing (hand-owned) textures; --force or --only PART to rebake")
    normals_from_relief(classes, a.out, log)
    if not a.no_stage:
        stage(classes, a.out, a.stage_dir, log, hd=a.hd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
