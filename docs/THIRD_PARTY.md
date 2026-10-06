# Third-party code and assets

| Name | Where used | Licence | Source |
| --- | --- | --- | --- |
| NumPy | tools/boatgen, tools/vpp, tools/venuegen, tools/soundgen, tools/liverybake (build time only), game/tests/water_preview.py and course_preview.py (test time only) | BSD-3-Clause | https://numpy.org |
| Pillow | tools/boatgen, tools/liverybake (build time only: PNG output and text), game/tests/water_preview.py and course_preview.py (test time only) | MIT-CMU (HPND) | https://python-pillow.org |
| moderngl, glcontext | tools/boatgen previews (build time only: headless OpenGL), game/tests/water_preview.py, course_preview.py, livery_preview.py and livery_cost.py (test time only) | MIT | https://github.com/moderngl/moderngl |
| SciPy | tools/vpp (build time only: root finding), tools/liverybake (build time only: the nearest-texel fill) | BSD-3-Clause | https://scipy.org |
| Matplotlib | tools/vpp (build time only: polar plots) | Matplotlib licence (PSF-based, BSD-compatible) | https://matplotlib.org |
| pytest | tools/vpp and tools/venuegen tests | MIT | https://pytest.org |
| doctest 2.4.12 | core tests (`core/third_party/doctest`, test builds only) | MIT | https://github.com/doctest/doctest |
| godot-cpp 10.0.0-stable (commit 507ed9d) | the GDExtension (`game/native`; fetched by `game/native/build.sh` into `game/native/third_party`, not committed), linked into `game/bin/libwindmark_godot.*` | MIT | https://github.com/godotengine/godot-cpp |
| ambientCG Plastic013A | tools/boatgen/textures/orange_peel_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Plastic013A |
| ambientCG Rubber004 | tools/boatgen/textures/grain_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Rubber004 |
| ambientCG Fabric004 | tools/boatgen/textures/carbon_twill_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Fabric004 |
| ambientCG Metal009 | tools/boatgen/textures/brushed_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Metal009 |
| ambientCG Fabric062 | tools/boatgen/textures/weave_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Fabric062 |
| ambientCG Rope002 | tools/boatgen/textures/braid_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Rope002 |
| Barlow Semi Condensed (Jeremy Tribby) | Race HUD and menu type, the logo (Black Italic and ExtraBold Italic, game/scenes/menu/wordmark.gd) and the livery text (boat names, sail numbers, insignia; Bold; tools/liverybake sets the baked insignia with the same file): game/fonts/barlow (Medium, SemiBold, Bold TTF and OFL.txt, unmodified, from the Google Fonts repository ofl/barlowsemicondensed, 2026-09-29); Black Italic and ExtraBold Italic TTF added unmodified from the same place, 2026-10-05; game/tests/race_hud_preview.py draws the previews with the same files; the mock-ups load it from Google Fonts | SIL Open Font License 1.1 | https://github.com/jpt/barlow, files from https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed |
| FFmpeg | tools/soundgen (build time only: run as an external program to encode the synthesised sounds as Ogg Vorbis; nothing of it is linked or shipped, and `--wav` works without it). The default sound set `game/audio/default` is our own synthesis and has no third-party content | LGPL-2.1-or-later (the program, not distributed) | https://ffmpeg.org |
| Laghi e specchi d'acqua (Provincia autonoma di Trento) | **Planned** (WM-105, WM-106): Lake Garda shoreline at the Trentino north end, read by tools/venuegen into the venue file and the drawn land (`docs/specs/venues.md` §3); raw downloads not committed | CC-BY 4.0 | https://dati.trentino.it (GeoCatalogo PAT) |
| EMODnet Bathymetry: satellite-derived coastline (Mean High Water) and DTM | **Planned** (WM-105, WM-107, WM-112): Solent and Gulf of Trieste shorelines; the DTM shapes the Solent current field and bank exclusions | CC-BY 4.0 | https://emodnet.ec.europa.eu/en/bathymetry |
| Australian Coastline 50K 2024 (AIMS, NESP MaC 3.17) | **Planned** (WM-105, WM-108): Fremantle and Rottnest shorelines | CC-BY 4.0 | https://www.data.gov.au/data/dataset/australian-coastline-50k-2024-nesp-mac-3-17-aims |
| NASADEM 1 arc-second (NASA JPL, SRTM reprocessed) | **Planned** (WM-105 to WM-112): terrain heights of the drawn land at every real venue | Public domain (US government work) | https://www.earthdata.nasa.gov/data/catalog/lpcloud-nasadem-hgt-001 |
| SRTM Water Body Data (NASA, NGA) | **Planned** (WM-105, WM-106): Lake Garda shoreline outside Trentino; fallback shoreline for any venue | Public domain (US government work) | https://lpdaac.usgs.gov/products/srtmswbdv003/ |
| OS Open Zoomstack (Ordnance Survey) | **Planned fallback** (WM-107): Solent shoreline if EMODnet is too coarse; contains OS data © Crown copyright and database right | Open Government Licence v3.0 (attribution; accepted by the owner 2026-10-06) | https://www.ordnancesurvey.co.uk/products/os-open-zoomstack |
