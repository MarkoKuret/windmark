"""Terrain heights: GeoTIFF elevation tiles (NASADEM 1 arc-second, venues.md §3) read without GDAL, mosaicked and
sampled on local east/north metres around the venue origin.

Supported GeoTIFFs: one band of int16, int32 or float32, uncompressed or deflate, in strips or tiles, without a
predictor, geographic (lon/lat) with a pixel scale and one tie point (what NASADEM and SRTM tiles are)."""

from __future__ import annotations

import math
import os
import struct
import zlib

import numpy as np

from .geo import InputError, lonlat_to_enu

_TYPES = {(1, 16): "u2", (2, 16): "i2", (2, 32): "i4", (3, 32): "f4"}  # (SampleFormat, BitsPerSample)


def read_geotiff(path):
    """(heights (rows, cols) float64 with NaN for no-data, lon of column 0, lat of row 0, dlon, dlat), where
    (lon, lat) are the pixel centres and rows run north to south."""
    with open(path, "rb") as f:
        data = f.read()
    bo = {b"II": "<", b"MM": ">"}.get(data[:2])
    if bo is None or struct.unpack(bo + "H", data[2:4])[0] != 42:
        raise InputError(f"{path}: not a (classic) TIFF")
    off = struct.unpack(bo + "I", data[4:8])[0]
    n = struct.unpack(bo + "H", data[off:off + 2])[0]
    tags = {}
    sizes = {1: 1, 2: 1, 3: 2, 4: 4, 11: 4, 12: 8, 16: 8}
    fmts = {1: "B", 2: "c", 3: "H", 4: "I", 11: "f", 12: "d", 16: "Q"}
    for k in range(n):
        e = off + 2 + 12 * k
        tag, typ, cnt = struct.unpack(bo + "HHI", data[e:e + 8])
        sz = sizes.get(typ, 1) * cnt
        vo = e + 8 if sz <= 4 else struct.unpack(bo + "I", data[e + 8:e + 12])[0]
        raw = data[vo:vo + sz]
        if typ == 2:
            tags[tag] = raw.decode("latin1").rstrip("\0")
        elif typ in fmts:
            tags[tag] = struct.unpack(bo + fmts[typ] * cnt, raw)
    w, h = tags[256][0], tags[257][0]
    bits = tags.get(258, (16,))[0]
    comp = tags.get(259, (1,))[0]
    sfmt = tags.get(339, (1,))[0]
    if (sfmt, bits) not in _TYPES:
        raise InputError(f"{path}: sample format {sfmt}, {bits} bits not supported")
    if tags.get(277, (1,))[0] != 1 or tags.get(317, (1,))[0] != 1:
        raise InputError(f"{path}: only one band without a predictor is supported")
    if comp not in (1, 8, 32946):
        raise InputError(f"{path}: compression {comp} not supported (none or deflate)")
    dt = np.dtype(bo + _TYPES[(sfmt, bits)])
    out = np.zeros((h, w), dt)

    def chunk(i, nbytes):
        raw = data[offs[i]:offs[i] + counts[i]]
        if comp != 1:
            raw = zlib.decompress(raw)
        return np.frombuffer(raw[:nbytes], dt)

    if 322 in tags:  # tiles
        tw, th = tags[322][0], tags[323][0]
        offs, counts = tags[324], tags[325]
        per_row = (w + tw - 1) // tw
        for i in range(len(offs)):
            ty, tx = divmod(i, per_row)
            t = chunk(i, tw * th * dt.itemsize).reshape(th, tw)
            y0, x0 = ty * th, tx * tw
            out[y0:y0 + th, x0:x0 + tw] = t[:min(th, h - y0), :min(tw, w - x0)]
    else:
        rps = tags.get(278, (h,))[0]
        offs, counts = tags[273], tags[279]
        for i in range(len(offs)):
            y0 = i * rps
            rows = min(rps, h - y0)
            out[y0:y0 + rows] = chunk(i, rows * w * dt.itemsize).reshape(rows, w)
    a = out.astype(np.float64)
    nodata = tags.get(42113)
    if nodata:
        a[a == float(nodata)] = np.nan
    a[a <= -32767] = np.nan
    scale, tie = tags[33550], tags[33922]
    dlon, dlat = scale[0], scale[1]
    lon0, lat0 = tie[3] - tie[0] * dlon, tie[4] + tie[1] * dlat
    # GTRasterTypeGeoKey (1025): 1 = PixelIsArea (tie point at the corner), 2 = PixelIsPoint (at the centre)
    keys = tags.get(34735, ())
    area = True
    for k in range(4, len(keys), 4):
        if keys[k] == 1025:
            area = keys[k + 3] == 1
    if area:
        lon0, lat0 = lon0 + dlon / 2, lat0 - dlat / 2
    return a, lon0, lat0, dlon, dlat


class Dem:
    """A mosaic of elevation tiles, sampled bilinearly at lon/lat; NaN outside the tiles and where no-data."""

    def __init__(self, paths):
        self.tiles = []
        for p in paths:
            if not os.path.exists(p):
                raise InputError(f"terrain file not found: {p} (raw downloads are kept out of the repo; see README)")
            self.tiles.append(read_geotiff(p))

    def sample(self, lon, lat):
        lon = np.asarray(lon, float)
        lat = np.asarray(lat, float)
        out = np.full(lon.shape, np.nan)
        for a, lon0, lat0, dlon, dlat in self.tiles:
            u = (lon - lon0) / dlon
            v = (lat0 - lat) / dlat
            ok = (u >= 0) & (v >= 0) & (u <= a.shape[1] - 1) & (v <= a.shape[0] - 1) & np.isnan(out)
            if not ok.any():
                continue
            uu, vv = u[ok], v[ok]
            i = np.minimum(np.floor(uu).astype(int), a.shape[1] - 2)
            j = np.minimum(np.floor(vv).astype(int), a.shape[0] - 2)
            tu, tv = uu - i, vv - j
            r0 = a[j, i] * (1 - tu) + a[j, i + 1] * tu
            r1 = a[j + 1, i] * (1 - tu) + a[j + 1, i + 1] * tu
            out[ok] = r0 * (1 - tv) + r1 * tv
        return out

    def sample_local(self, x, y, origin):
        lon, lat = enu_to_lonlat(x, y, origin)
        return self.sample(lon, lat)


def enu_to_lonlat(x, y, origin):
    """Local east/north metres (on the ground, height 0) to lon/lat degrees: the inverse of lonlat_to_enu by
    Newton steps on a local linearisation (converges to millimetres in two steps over a venue)."""
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    lat0 = float(origin["lat"])
    lon0 = float(origin["lon"])
    m_lat = 111132.954 - 559.822 * math.cos(2 * math.radians(lat0))
    m_lon = 111412.84 * math.cos(math.radians(lat0))
    lon = lon0 + x / m_lon
    lat = lat0 + y / m_lat
    for _ in range(3):
        e, n = lonlat_to_enu(lon, lat, origin)
        lon = lon + (x - e) / m_lon
        lat = lat + (y - n) / m_lat
    return lon, lat

