#!/usr/bin/env python3
"""Checks that the treemap's file-kind palette stays distinguishable for
color-blind users.

Reads the neon palette from src/FileTypeColors.swift (`paletteHex`), pushes each
color through the same normalization the treemap applies (TMVCushionRenderer),
dims it to a typical mid-cushion brightness, simulates normal, protan, deutan and
tritan color vision (Machado et al. 2009, severity 1.0) and prints the smallest
CIEDE2000 distance between any two colors per vision type. Exits with status 1
if that distance drops below MIN_DELTA_E.

    python3 tools/palette_check.py          # needs numpy
"""
import itertools
import pathlib
import re
import sys

import numpy as np

MIN_DELTA_E = 5.0
BASE_BRIGHTNESS = 1.8   # TMVCushionRenderer.BASE_BRIGHTNESS
SHADE = 0.78            # typical brightness factor of a cushion's surface

SOURCE = pathlib.Path(__file__).resolve().parent.parent / "src" / "FileTypeColors.swift"

# Machado, Oliveira & Fernandes (2009), severity 1.0, applied in linear RGB.
VISION = {
    "normal": np.eye(3),
    "protan": np.array([[0.152286, 1.052583, -0.204868],
                        [0.114503, 0.786281, 0.099216],
                        [-0.003882, -0.048116, 1.051998]]),
    "deutan": np.array([[0.367322, 0.860646, -0.227968],
                        [0.280085, 0.672501, 0.047413],
                        [-0.011820, 0.042940, 0.968881]]),
    "tritan": np.array([[1.255528, -0.076749, -0.178779],
                        [-0.078411, 0.930809, 0.147602],
                        [0.004733, 0.691367, 0.303900]]),
}

RGB_TO_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                       [0.2126729, 0.7151522, 0.0721750],
                       [0.0193339, 0.1191920, 0.9503041]])
WHITE = RGB_TO_XYZ @ np.ones(3)


def palette():
    text = SOURCE.read_text()
    body = re.search(r"paletteHex[^=]*=\s*\[(.*?)\]", text, re.S).group(1)
    return [int(h, 16) for h in re.findall(r"0x([0-9A-Fa-f]{6})", body)]


def normalize(rgb):
    """TMVCushionRenderer.normalize: component sum 1.8, clamp to 1 and redistribute."""
    total = sum(rgb)
    c = [v * BASE_BRIGHTNESS / total for v in rgb] if total else list(rgb)
    for i in range(3):
        if c[i] > 1:
            j, k = (x for x in range(3) if x != i)
            h = (c[i] - 1) / 2
            c[i] = 1
            c[j] += h
            c[k] += h
            if c[j] > 1:
                c[k] += c[j] - 1
                c[j] = 1
            elif c[k] > 1:
                c[j] += c[k] - 1
                c[k] = 1
            break
    return np.array(c)


def to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_lab(linear):
    xyz = RGB_TO_XYZ @ np.clip(linear, 0, 1) / WHITE
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.array([116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])])


def delta_e_2000(lab1, lab2):
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp, dCp = L2 - L1, C2p - C1p
    if C1p * C2p == 0:
        dhp = 0
    else:
        dhp = h2p - h1p
        dhp = dhp - 360 if dhp > 180 else dhp + 360 if dhp < -180 else dhp
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dhp / 2))
    Lpm, Cpm = (L1 + L2) / 2, (C1p + C2p) / 2
    if C1p * C2p == 0:
        hpm = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hpm = (h1p + h2p) / 2
    else:
        hpm = (h1p + h2p + 360) / 2 if h1p + h2p < 360 else (h1p + h2p - 360) / 2
    T = (1 - 0.17 * np.cos(np.radians(hpm - 30)) + 0.24 * np.cos(np.radians(2 * hpm))
         + 0.32 * np.cos(np.radians(3 * hpm + 6)) - 0.20 * np.cos(np.radians(4 * hpm - 63)))
    d_theta = 30 * np.exp(-(((hpm - 275) / 25) ** 2))
    Rc = 2 * np.sqrt(Cpm ** 7 / (Cpm ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lpm - 50) ** 2 / np.sqrt(20 + (Lpm - 50) ** 2)
    Sc, Sh = 1 + 0.045 * Cpm, 1 + 0.015 * Cpm * T
    Rt = -np.sin(np.radians(2 * d_theta)) * Rc
    return float(np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2
                         + Rt * (dCp / Sc) * (dHp / Sh)))


def main():
    hexes = palette()
    shown = []
    for h in hexes:
        rgb = [((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255]
        shown.append(np.clip(normalize(rgb) * 2.5 / BASE_BRIGHTNESS * SHADE, 0, 1))

    failed = False
    print(f"{len(hexes)} palette colors, minimum CIEDE2000 between any two:")
    for name, matrix in VISION.items():
        labs = [to_lab(matrix @ to_linear(c)) for c in shown]
        worst = min((delta_e_2000(labs[i], labs[j]), i, j)
                    for i, j in itertools.combinations(range(len(labs)), 2))
        print(f"  {name:7s} {worst[0]:5.2f}   (#{hexes[worst[1]]:06X} vs #{hexes[worst[2]]:06X})")
        failed |= worst[0] < MIN_DELTA_E

    if failed:
        print(f"FAIL: some pair is closer than {MIN_DELTA_E}")
        sys.exit(1)
    print(f"OK: every pair is at least {MIN_DELTA_E} apart for every vision type")


if __name__ == "__main__":
    main()
