# Third-party code and assets

| Name | Where used | Licence | Source |
| --- | --- | --- | --- |
| NumPy | tools/boatgen, tools/vpp (build time only), game/tests/water_preview.py and course_preview.py (test time only) | BSD-3-Clause | https://numpy.org |
| Pillow | tools/boatgen (build time only: PNG output), game/tests/water_preview.py and course_preview.py (test time only) | MIT-CMU (HPND) | https://python-pillow.org |
| moderngl, glcontext | tools/boatgen previews (build time only: headless OpenGL), game/tests/water_preview.py and course_preview.py (test time only) | MIT | https://github.com/moderngl/moderngl |
| SciPy | tools/vpp (build time only: root finding) | BSD-3-Clause | https://scipy.org |
| Matplotlib | tools/vpp (build time only: polar plots) | Matplotlib licence (PSF-based, BSD-compatible) | https://matplotlib.org |
| pytest | tools/vpp tests | MIT | https://pytest.org |
| doctest 2.4.12 | core tests (`core/third_party/doctest`, test builds only) | MIT | https://github.com/doctest/doctest |
| godot-cpp 10.0.0-stable (commit 507ed9d) | the GDExtension (`game/native`; fetched by `game/native/build.sh` into `game/native/third_party`, not committed), linked into `game/bin/libwindmark_godot.*` | MIT | https://github.com/godotengine/godot-cpp |
| ambientCG Plastic013A | tools/boatgen/textures/orange_peel_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Plastic013A |
| ambientCG Rubber004 | tools/boatgen/textures/grain_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Rubber004 |
| ambientCG Fabric004 | tools/boatgen/textures/carbon_twill_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Fabric004 |
| ambientCG Metal009 | tools/boatgen/textures/brushed_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Metal009 |
| ambientCG Fabric062 | tools/boatgen/textures/weave_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Fabric062 |
| ambientCG Rope002 | tools/boatgen/textures/braid_* (processed: grey, 512 px), embedded in generated boat GLBs | CC0 1.0 | https://ambientcg.com/a/Rope002 |
| Barlow Semi Condensed (Jeremy Tribby) | Race HUD type: game/fonts/barlow (Medium, SemiBold, Bold TTF and OFL.txt, unmodified, from the Google Fonts repository ofl/barlowsemicondensed, 2026-09-29); game/tests/race_hud_preview.py draws the previews with the same files; the mock-ups load it from Google Fonts | SIL Open Font License 1.1 | https://github.com/jpt/barlow, files from https://github.com/google/fonts/tree/main/ofl/barlowsemicondensed |
