# Windmark venue generator

Builds a venue physics file (`windmark.venue/1`, `docs/specs/data_format.md` §6) from a hand-owned venue source
file (`windmark.venuesrc/1`, `docs/specs/venues.md` §5) and its coastline inputs: the land polygons (clipped and
simplified within the performance budget of `venues.md` §4.1), the obstacles, the wind field for the 8 sectors,
the current field, the sea exposure grid, and the venue's `conditions` and `briefing` blocks; with a `terrain`
block also the land heights from an elevation model and the drawn terrain file (`<id>.terrain.json` and `.bin`,
`data_format.md` §6.10, `venues.md` §5.7). Everything comes from the land shape, the elevation model and the
numbers in the source file; the generated files are never edited by hand.

## Running

```
cd tools/venuegen
uv venv .venv && uv pip install --python .venv/bin/python -e ".[test]"     # or: pip install -e ".[test]"
.venv/bin/python -m windmark_venuegen ../../data/venue_sources/practice_waters.venuesrc.json -o ../../data/venues/
.venv/bin/python -m windmark_venuegen --check ../../data/venues/*.venue.json
.venv/bin/python -m pytest
```

`-o FILE` (one source) or `-o DIR` (writes `<id>.venue.json`, and `<id>.terrain.json` and `.bin` beside it when
the source has a `terrain` block); without `-o` the files go next to the source. Every run validates its output
(spec rules, grid, vertex and triangle caps, file size) and prints notes (land vertices, dropped pieces, raised
tolerances, terrain triangles). Garda builds in about 5 s, Fremantle (16 by 12 km) in about 11 s.
`--check` also takes `*.terrain.json`. The test that regenerates every shipped venue skips a venue whose raw inputs
are not downloaded.

Dependencies: Python 3.9+, NumPy, pytest (tests). The GeoJSON and shapefile readers are our own (no GDAL).

## The model in short

- **Wind** (`venues.md` §5.3): land casts a wake downwind whose depth grows with the land height and which recovers
  over about 30 land heights while spreading sideways like a plane wake; near a shore the wind turns to run along
  it when it blows onshore (and slows right at the shore) and leaves it more square when it blows offshore; wind
  running along a long shore is a little stronger with the land on its right (northern hemisphere). Grids fade to
  `(1, 0)` at their edge.
- **Current** (§5.4): a stream of given speed and direction, slowed near the shore and over bank polygons, steered
  along the shore, zero on land; `ref_speed` is its 90th percentile over the water inside `bounds`.
- **Terrain** (§5.7): land heights for the wind model from the elevation model (above `water_level`, capped by
  `wind_height_max`), and the drawn terrain: an adaptive mesh (5 m at the shore near the racing water, coarser with
  distance, within 120k triangles with the horizon ridge) whose waterline is the physics land, plus a 10 m ground
  grid for the cameras. Without `dem` the land rises to each polygon's `height`.
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
| Practice | our own shapes | inline `polygons` in local metres (`practice_waters.venuesrc.json`) |
| Garda | Provincia autonoma di Trento, "Laghi e specchi d'acqua" and SRTM Water Body Data | one water polygon, `raw/garda/garda_lake.geojson`, made by the commands below |
| Solent | EMODnet Bathymetry satellite-derived coastline (MHW) | the MHW lines from the WFS (layer `emodnet:coastlines`, type MHW) are chained, polygonized and committed as small lon/lat land polygons by `data/venue_sources/solent/prepare.py` (download commands in its docstring), then read with `"role": "land"` |
| Trieste | EMODnet Bathymetry satellite-derived coastline (MHW) | polygons: `"role": "land"`; if the download is coastline lines, `"role": "shore_left"` or `"shore_right"` after checking which side is land (lines must run past the clip box) |
| Solent banks | EMODnet DTM | the WCS coverage `emodnet__mean` contoured by the same script (Bramble Bank at 2 m and 4 m depth) into `current.banks` polygons in local metres, each with a speed `factor` |
| Fremantle | Australian Coastline 50K 2024 (AIMS), V1-1 Full | land polygons (shapefile, lon/lat): the national file (40 MB zipped, in `raw/fremantle/`) is clipped once by `data/venue_sources/fremantle/clip_coastline.py` into two small GeoJSON files (Rottnest, mainland) that are committed, so the venue builds from a plain checkout; each is an input with `"role": "land"` and its own `height` |
| Solent fallback | OS Open Zoomstack | the land or sea polygons (GeoPackage, British National Grid): reproject to EPSG:4326, then `land` or `water` |
| Terrain heights | NASADEM | GeoTIFF tiles in `terrain.dem` (below); without them the wind effects use a `height` per input or polygon (`land_height` default) |

### Garda raw inputs

```
cd data/venue_sources/raw/garda          # from the repository root; PY=../../../../tools/venuegen/.venv/bin/python
mkdir -p pat nasadem
curl -L -o pat/laghi.zip https://siatservices.provincia.tn.it/idt/vector/p_TN_0f1fdc33-5c71-4c6d-81e7-25eb2ab0e599.zip
(cd pat && unzip -o laghi.zip)           # idrspacq/idrspacq.shp, ETRS89 / UTM 32N
for t in n45e010 n45e011 n46e010 n46e011; do
  curl -o nasadem/NASADEM_HGT_$t.tif https://opentopography.s3.sdsc.edu/raster/NASADEM/NASADEM_be/NASADEM_HGT_$t.tif
done
$PY -m windmark_venuegen.prep utm pat/idrspacq/idrspacq.shp pat_lakes.geojson --zone 32 --box 10.70 45.60 11.00 45.95 --min-area 100000
$PY -m windmark_venuegen.prep dem-water nasadem/NASADEM_HGT_n45e010.tif swbd_lake.geojson --level 63 --seed 10.855 45.86 --box 10.60 45.60 11.00 45.95
$PY -m windmark_venuegen.prep splice pat_lakes.geojson swbd_lake.geojson garda_lake.geojson --cut-lat 45.840
```

The Trentino lake polygon ends at the provincial border across the lake; south of 45.840 N the shore is the SRTM
water body as NASADEM carries it (the lake flattened to 63 m), traced along the cells and smoothed. The same tiles
are the elevation model (`water_level` 63).

### Terrain for another venue

Add to the source, with the NASADEM tiles that cover `bounds` grown by about 25 km (the horizon ridge):

```json
"terrain": { "dem": ["raw/<venue>/nasadem/NASADEM_HGT_s33e115.tif"], "source": "NASADEM 1 arc-second (NASA JPL, via OpenTopography)",
             "version": "v001", "downloaded": "YYYY-MM-DD", "licence": "public domain", "water_level": 0 }
```

Tiles: `https://opentopography.s3.sdsc.edu/raster/NASADEM/NASADEM_be/NASADEM_HGT_<n|s><lat><e|w><lon>.tif` (lower
left corner, e.g. `s33e115` covers 33 to 32 S, 115 to 116 E). `water_level` is the DEM height of the water (0 at
sea, the lake's level on a lake). `"terrain": {}` without `dem` still writes a terrain file, the land rising to
each polygon's `height`. Optional constants (defaults in `terrain.py`): `wind_height_max`, `margin`, `ridge`,
`tolerance`, `tolerance_per_km`, `shore_band`, `shore_slope`, `depth`, `hill_width` and the others listed there.

## Files

| Path | Role |
| --- | --- |
| `windmark_venuegen/geo.py` | GeoJSON and shapefile readers, lon/lat to local metres, roles and orientation |
| `windmark_venuegen/clip.py` | clip to the box and close the land along the box edge |
| `windmark_venuegen/simplify.py` | Douglas-Peucker with a per-vertex tolerance; the simple-polygon check |
| `windmark_venuegen/raster.py` | work raster: land mask and height, blurs, sampling, distances |
| `windmark_venuegen/fields.py` | wind field, current field, `ref_speed`, exposure |
| `windmark_venuegen/dem.py` | GeoTIFF elevation tiles (no GDAL), sampled on local metres |
| `windmark_venuegen/terrain.py` | wind heights from the DEM, the drawn terrain mesh, ridge and ground grid, their checks |
| `windmark_venuegen/prep.py` | raw download preparation: UTM shapefile to GeoJSON, a DEM's water body, splicing two water polygons |
| `windmark_venuegen/validate.py` | venue file checks (`data_format.md` §6, `venues.md` §4.1) |
| `windmark_venuegen/build.py` | source file to venue file, the JSON writer |
| `../../data/venue_sources/` | the hand-owned venue source files |
| `tests/` | unit tests and the check that every committed venue is the tool's output |
