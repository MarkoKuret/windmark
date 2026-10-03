"""liverybake: the ownership rule, the layouts and the textures' rules (data_format.md §8.5, §8.6,
sail_visuals.md §11.2). Small images so the run is quick; the class geometry comes from the cache (one boat build
per class the first time, about 15 s each)."""
import json
import os
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from liverybake import __main__ as cli  # noqa: E402
from liverybake import common, geometry, sails, text  # noqa: E402

SMALL = ["--hull-size", "256", "--sail-size", "128", "--keel-size", "64", "--no-stage", "--quiet"]


def bake(out, *extra):
    assert cli.main(["wm7", "--out", str(out)] + SMALL + list(extra)) == 0


def files(root):
    return {str(p.relative_to(root)): p.read_bytes() for p in Path(root).rglob("*") if p.is_file()}


@pytest.fixture(scope="module")
def baked(tmp_path_factory):
    out = tmp_path_factory.mktemp("liveries")
    bake(out)
    return out


def test_writes_the_folders(baked):
    hull = baked / "wm7" / "navy"
    for f in ("hull_albedo.png", "hull_normal.png", "hull_orm.png", "keel_albedo.png", "layout.json"):
        assert (hull / f).exists(), f
    assert Image.open(hull / "hull_albedo.png").size == (256, 128)
    for sid in ("main", "jib", "kite"):
        for suf in ("_port_albedo.png", "_stbd_albedo.png", "_normal.png", "_orm.png"):
            assert (baked / "wm7" / "sails" / (sid + suf)).exists(), sid + suf
    assert not (hull / "deck_albedo.png").exists()          # only on request


def test_hand_edits_are_never_overwritten(tmp_path):
    bake(tmp_path)
    p = tmp_path / "wm7" / "navy" / "hull_albedo.png"
    Image.new("RGB", (8, 8), (255, 0, 0)).save(p)            # a hand edit
    s = tmp_path / "wm7" / "sails" / "main_port_albedo.png"
    Image.new("RGB", (8, 8), (0, 255, 0)).save(s)
    before = files(tmp_path)
    bake(tmp_path)
    assert files(tmp_path) == before, "a bake without --force or --only changed hand-owned files"
    # --only keel rewrites the keel (and its layout entry) and nothing else
    bake(tmp_path, "--only", "keel")
    after = files(tmp_path)
    changed = {k for k in after if after[k] != before.get(k)}
    assert changed <= {"wm7/navy/keel_albedo.png", "wm7/navy/layout.json"}
    assert after["wm7/navy/hull_albedo.png"] == before["wm7/navy/hull_albedo.png"]
    # --only main rewrites that sail only
    bake(tmp_path, "--only", "main")
    after2 = files(tmp_path)
    changed = {k for k in after2 if after2[k] != after.get(k)}
    assert "wm7/sails/main_port_albedo.png" in changed
    assert all(k.startswith("wm7/sails/main_") or k == "wm7/sails/layout.json" for k in changed), changed
    # --force rewrites everything selected
    bake(tmp_path, "--force")
    assert Image.open(p).size == (256, 128)


def test_deterministic(tmp_path, baked):
    bake(tmp_path)
    a, b = files(tmp_path), files(baked)
    assert a.keys() == b.keys()
    assert all(a[k] == b[k] for k in a), [k for k in a if a[k] != b[k]]


def test_albedo_cap(baked):
    for p in Path(baked).rglob("*_albedo.png"):
        assert np.asarray(Image.open(p)).max() <= 231, p


def test_hull_zones(baked):
    """The boot stripe sits at its height above the DWL and the topsides above it, in the livery's colours."""
    geo = geometry.load("wm7")
    W, H = 256, 128
    A = __import__("liverybake.hull", fromlist=["atlas"]).atlas(geo, W, H)
    img = np.asarray(Image.open(Path(baked) / "wm7" / "navy" / "hull_albedo.png"), dtype=float)
    z_af, z_bt = geo["boot_top"]
    mid = W // 2
    col = A["z"][: H // 2, mid]
    boot = np.where((col > z_af + 0.015) & (col < z_bt - 0.015) & A["valid"][: H // 2, mid])[0]
    tops = np.where((col > 0.3) & A["valid"][: H // 2, mid])[0]
    assert boot.size and tops.size
    liv = json.loads((common.DATA / "wm7.liveries.json").read_text())["liveries"][0]["hull"]
    want_boot = np.array([int(liv["boot_stripe"][i:i + 2], 16) for i in (1, 3, 5)])
    want_top = np.array([int(liv["topsides"][i:i + 2], 16) for i in (1, 3, 5)])
    assert np.abs(img[boot[len(boot) // 2], mid] - want_boot).max() < 30
    assert np.abs(np.median(img[tops, mid], axis=0) - want_top).max() < 20


def test_sail_layout(baked):
    lay = json.loads((Path(baked) / "wm7" / "sails" / "layout.json").read_text())["sails"]
    assert set(lay) == {"main", "jib", "kite"}
    assert lay["jib"]["text"]["rows"] == []                  # Appendix G: no number on a jib
    main = lay["main"]["text"]
    kinds = [r["kind"] for r in main["rows"]]
    assert kinds == ["insignia", "nation", "number"]
    assert main["h"] == pytest.approx(sails.number_height(7.2))
    stbd_bottom = min(r["stbd"][1] - r["stbd"][3] for r in main["rows"])
    port_top = max(r["port"][1] + r["port"][3] for r in main["rows"])
    assert stbd_bottom > port_top, "the starboard stack is uppermost"
    kite = lay["kite"]
    assert kite["cloth"] == "nylon" and [r["kind"] for r in kite["text"]["rows"]] == ["nation", "number"]
    # the image rectangle holds the whole sail plan
    geo = geometry.load("wm7")
    for s in geo["sails"]:
        pl = geometry.sail_plan(s, geo["loa"])
        x0, yt, w, h = lay[s["id"]]["rect"]
        pts = pl["plan"].reshape(-1, 2)
        assert pts[:, 0].min() >= x0 and pts[:, 0].max() <= x0 + w and pts[:, 1].max() <= yt and pts[:, 1].min() >= yt - h


def test_number_slots_fit_the_fleet(baked):
    """Every boat's nation and number fit their slots at the full height (no shrinking for a 1 to 3 digit
    number)."""
    liv = json.loads((common.DATA / "wm7.liveries.json").read_text())
    lay = json.loads((Path(baked) / "wm7" / "sails" / "layout.json").read_text())["sails"]["main"]["text"]
    rows = {r["kind"]: r for r in lay["rows"]}
    for b in liv["boats"]:
        for kind, s in (("number", b["sail_number"]), ("nation", b.get("nation", ""))):
            if not s:
                continue
            box = rows[kind]["port"]
            assert box[3] * text.aspect(s) <= box[2] + 1e-6, (kind, s)


def test_stbd_is_the_port_view_mirrored(baked):
    """Away from the insignia and the tell-tales the starboard image is the port image mirrored."""
    d = Path(baked) / "wm7" / "sails"
    port = np.asarray(Image.open(d / "kite_port_albedo.png"), dtype=int)
    stbd = np.asarray(Image.open(d / "kite_stbd_albedo.png"), dtype=int)
    assert np.abs(port - stbd[:, ::-1]).max() <= 1


def test_stage_import_settings(baked, tmp_path):
    n = cli.stage(["wm7"], baked, tmp_path, log=lambda *a: None)
    assert n > 0
    imp = (tmp_path / "wm7" / "navy" / "hull_normal.png.import").read_text()
    assert "compress/mode=2" in imp and "compress/normal_map=1" in imp
    assert "compress/high_quality=true" in (tmp_path / "wm7" / "navy" / "hull_albedo.png.import").read_text()
    assert (tmp_path / "_cloth" / "nylon_detail.png").exists()
    assert cli.stage(["wm7"], baked, tmp_path, log=lambda *a: None) == 0     # nothing changed, nothing copied
