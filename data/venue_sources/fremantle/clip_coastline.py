"""Cuts the Fremantle coastline inputs out of the national Australian Coastline 50K 2024 file.

The national shapefile (AIMS, NESP MaC 3.17, V1-1, CC-BY 4.0, about 40 MB zipped) stays out of the repo; this
script clips it to a box around Gage Roads that contains the venue's field box (bounds grown by 3 km) and writes
two small GeoJSON files next to it, so the venue builds from a plain checkout:

  rottnest.geojson   Rottnest Island (whole)
  mainland.geojson   the mainland shore from Cottesloe to Woodman Point, with the moles, rocks and islets

Download (once) into data/venue_sources/raw/fremantle/ (ignored by git):

  curl -L -o full.zip "https://nextcloud.eatlas.org.au/s/DcGmpS3F5KZjgAG/download?path=%2FV1-1%2F&files=Full"
  unzip full.zip

Then, from tools/venuegen:  .venv/bin/python ../../data/venue_sources/fremantle/clip_coastline.py
"""

import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools", "venuegen"))

from windmark_venuegen.clip import clip_to_box  # noqa: E402
from windmark_venuegen.geo import polygon_paths, read_shapefile  # noqa: E402

SHP = os.path.join(HERE, "..", "raw", "fremantle", "Full", "AU_NESP-MaC-3-17_AIMS_Aus-Coastline-50k_2024_V1-1.shp")
BOX = (115.42, -32.13, 115.80, -31.90)  # lon/lat; holds the field box of fremantle.venuesrc.json
ROTTNEST_EAST = 115.58  # every piece west of this is Rottnest


def main():
    paths = []
    for kind, rings, _ in read_shapefile(SHP, BOX):
        if kind == "polygon":
            paths += polygon_paths([np.asarray(r, float)[:, :2] for r in rings], "land", None)
    out = {"rottnest": [], "mainland": []}
    for r in clip_to_box(paths, BOX):
        p = np.asarray(r["points"], float)
        key = "rottnest" if p[:, 0].max() < ROTTNEST_EAST else "mainland"
        ring = [[round(float(x), 7), round(float(y), 7)] for x, y in p]
        ring.append(ring[0])
        out[key].append([ring])
    for key, polys in out.items():
        doc = {"type": "FeatureCollection",
               "note": "Clipped from Australian Coastline 50K 2024 (NESP MaC 3.17, AIMS) V1-1, CC-BY 4.0",
               "features": [{"type": "Feature", "properties": {},
                             "geometry": {"type": "MultiPolygon", "coordinates": polys}}]}
        with open(os.path.join(HERE, f"{key}.geojson"), "w") as f:
            json.dump(doc, f, separators=(",", ":"))
        print(key, len(polys), "polygons", sum(len(p[0]) for p in polys), "vertices")


if __name__ == "__main__":
    main()
