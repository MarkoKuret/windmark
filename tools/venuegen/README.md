# Windmark venue generator

Builds a venue physics file (`windmark.venue/1`, `docs/specs/data_format.md` §6) from a hand-owned venue source
file (`windmark.venuesrc/1`, `docs/specs/venues.md` §5) and its coastline inputs: the land polygons (clipped and
simplified within the performance budget of `venues.md` §4.1), the obstacles, the wind field for the 8 sectors,
the current field, the sea exposure grid, and the venue's `conditions` and `briefing` blocks. Everything in the
grids comes from the land shape and the numbers in the source file; the venue files are never edited by hand.

## Running

```
cd tools/venuegen
uv venv .venv && uv pip install --python .venv/bin/python -e ".[test]"     # or: pip install -e ".[test]"
.venv/bin/python -m windmark_venuegen ../../data/venue_sources/example_bay.venuesrc.json -o ../../data/venues/
.venv/bin/python -m windmark_venuegen --check ../../data/venues/*.venue.json
.venv/bin/python -m pytest
```

`-o FILE` (one source) or `-o DIR` (writes `<id>.venue.json`); without `-o` the file goes next to the source.
Every run validates its output (spec rules, grid and vertex caps, file size) and prints notes (land vertices,
dropped pieces, raised tolerances). A venue of 16 by 16 km builds in a few seconds.

Dependencies: Python 3.9+, NumPy, pytest (tests). The GeoJSON and shapefile readers are our own (no GDAL).

## The model in short

- **Wind** (`venues.md` §5.3): land casts a wake downwind whose depth grows with the land height and which recovers
  over about 30 land heights while spreading sideways like a plane wake; near a shore the wind turns to run along
  it when it blows onshore (and slows right at the shore) and leaves it more square when it blows offshore; wind
  running along a long shore is a little stronger with the land on its right (northern hemisphere). Grids fade to
  `(1, 0)` at their edge.
- **Current** (§5.4): a stream of given speed and direction, slowed near the shore and over bank polygons, steered
  along the shore, zero on land; `ref_speed` is its 90th percentile over the water inside `bounds`.
- **Exposure** (§5.5): for the typical wind direction, the open-water fetch averaged over the wave directions
  (square root, as the wind sea grows), faded out over about 100 m from the shore, 0 on land.

All constants have defaults in `windmark_venuegen/fields.py` and `build.py`; a venue overrides them in its source
file (`wind`, `current`, `exposure`, `simplify`, `grids` blocks). Unknown keys are refused.

## Coastline inputs

Raw downloads go in `data/venue_sources/raw/<venue>/` (ignored by git); the source file names them by path relative
to itself and records the source, version, download date and licence, which end up in the venue file's `source`
note. Inputs in lon/lat (`"frame": "lonlat"`) must be WGS84 / EPSG:4326; reproject anything else first, for example
`ogr2ogr -t_srs EPSG:4326 out.geojson in.gpkg` (GDAL is only needed on the machine that prepares the raw file).
Big files are fine: shapefile records whose box misses the venue are skipped.

| Venue | Source (`venues.md` §3) | How to feed it in |
| --- | --- | --- |
| Practice | our own shapes | inline `polygons` in local metres (`example_bay.venuesrc.json`) |
| Garda | Provincia autonoma di Trento, "Laghi e specchi d'acqua" | the lake polygon (shapefile, reprojected from ETRS89 / UTM 32N to EPSG:4326) with `"role": "water"`: the land is everything outside the lake; islands come from its holes |
| Garda (south of Trentino) | SRTM Water Body Data | the `SWBD` water polygons (shapefile, already lon/lat) with `"role": "water"`, as a second input for the shore outside Trentino |
| Solent, Trieste | EMODnet Bathymetry satellite-derived coastline (MHW) | polygons: `"role": "land"`; if the download is coastline lines, `"role": "shore_left"` or `"shore_right"` after checking which side is land (lines must run past the clip box) |
| Solent banks | EMODnet DTM | contour the banks (for example the 2 m depth line around Bramble Bank) into polygons and list them in `current.banks` with a speed `factor` |
| Fremantle | Australian Coastline 50K 2024 (AIMS) | land polygons (shapefile, lon/lat): `"role": "land"`; the national file is read with the box filter |
| Solent fallback | OS Open Zoomstack | the land or sea polygons (GeoPackage, British National Grid): reproject to EPSG:4326, then `land` or `water` |
| Terrain heights | NASADEM | not read yet: the wind effects use a `height` per input or polygon (`land_height` default); a later step can set them from the DEM |

## Files

| Path | Role |
| --- | --- |
| `windmark_venuegen/geo.py` | GeoJSON and shapefile readers, lon/lat to local metres, roles and orientation |
| `windmark_venuegen/clip.py` | clip to the box and close the land along the box edge |
| `windmark_venuegen/simplify.py` | Douglas-Peucker with a per-vertex tolerance; the simple-polygon check |
| `windmark_venuegen/raster.py` | work raster: land mask and height, blurs, sampling, distances |
| `windmark_venuegen/fields.py` | wind field, current field, `ref_speed`, exposure |
| `windmark_venuegen/validate.py` | venue file checks (`data_format.md` §6, `venues.md` §4.1) |
| `windmark_venuegen/build.py` | source file to venue file, the JSON writer |
| `../../data/venue_sources/` | the hand-owned venue source files |
| `tests/` | unit tests and the check that every committed venue is the tool's output |
