"""Physical constants and unit helpers. Everything inside the VPP is SI (m, kg, s, N, rad)."""

import math

G = 9.81                 # gravity, m/s^2
RHO_WATER = 1025.0       # sea water density, kg/m^3 (15 degC)
NU_WATER = 1.19e-6       # sea water kinematic viscosity, m^2/s (15 degC, ITTC 2011 fresh/sea water tables)
RHO_AIR = 1.225          # air density, kg/m^3 (ISA sea level)

KNOT = 1852.0 / 3600.0   # m/s per knot
DEG = math.pi / 180.0


def kn(v_ms):
    """m/s -> knots."""
    return v_ms / KNOT


def ms(v_kn):
    """knots -> m/s."""
    return v_kn * KNOT
