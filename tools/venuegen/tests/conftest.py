import copy
import math
import os

import numpy as np
import pytest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def circle(cx, cy, r, n=48, wobble=0.0, seed=1):
    rng = np.random.default_rng(seed)
    a = np.linspace(0, 2 * math.pi, n, endpoint=False)
    rr = r * (1 + wobble * rng.uniform(-1, 1, n))
    return [[float(cx + q * math.cos(t)), float(cy + q * math.sin(t))] for q, t in zip(rr, a)]


BASE = {
    "schema": "windmark.venuesrc/1", "id": "test_bay", "name": "Test Bay", "version": 1,
    "origin": {"lat": 45.0, "lon": 13.0},
    "bounds": [-2000, -2000, 2000, 2000],
    "fetch": 10000,
    "coastline": [{"source": "test shapes", "frame": "local", "role": "land",
                   "polygons": [{"id": "isle", "height": 40, "points": circle(0, 2500, 400)}]}],
    "grids": {"wind": 200, "current": 200, "exposure": 200},
}


@pytest.fixture
def src(tmp_path):
    s = copy.deepcopy(BASE)
    s["_dir"] = str(tmp_path)
    return s
