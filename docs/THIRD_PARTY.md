# Third-party code and assets

| Name | Where used | Licence | Source |
| --- | --- | --- | --- |
| NumPy | tools/boatgen, tools/vpp (build time only), game/tests/water_preview.py (test time only) | BSD-3-Clause | https://numpy.org |
| Pillow | tools/boatgen (build time only: PNG output), game/tests/water_preview.py (test time only) | MIT-CMU (HPND) | https://python-pillow.org |
| moderngl, glcontext | tools/boatgen previews (build time only: headless OpenGL), game/tests/water_preview.py (test time only) | MIT | https://github.com/moderngl/moderngl |
| SciPy | tools/vpp (build time only: root finding) | BSD-3-Clause | https://scipy.org |
| Matplotlib | tools/vpp (build time only: polar plots) | Matplotlib licence (PSF-based, BSD-compatible) | https://matplotlib.org |
| pytest | tools/vpp tests | MIT | https://pytest.org |
| doctest 2.4.12 | core tests (`core/third_party/doctest`, test builds only) | MIT | https://github.com/doctest/doctest |
