#!/usr/bin/env python3
"""Renders the app icon: a disk platter whose surface is a neon treemap, set on
a deep-space glass tile. Writes the iconset PNGs into the asset catalog and the
128 px loose icon next to the sources.

    python3 tools/make_app_icon.py          # needs numpy and Pillow
    python3 tools/make_app_icon.py preview [out.png]  # writes just the 1024 px master
"""
import json
import pathlib
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
ICONSET = SRC / "Disk Inventory X" / "Images.xcassets" / "AppIcon.appiconset"

S = 2048                      # working resolution, scaled down at the end
CANVAS = 1024 * S // 1024
BODY = 824 * S // 1024        # macOS icon grid: 824 pt tile inside the 1024 pt canvas
C = S // 2

# The treemap palette (src/FileTypeColors.swift), brightest cells first.
PALETTE = ["00E5FF", "FFB000", "8A5CFF", "FF2BD6", "40B3FF", "B4FF73", "FF8573", "73FFF6"]


def rgb(hex_):
    return np.array([int(hex_[i:i + 2], 16) for i in (0, 2, 4)], float) / 255


def squircle_mask(size, n=5.0):
    """Superellipse approximating the continuous-corner macOS tile."""
    y, x = np.mgrid[0:S, 0:S].astype(float)
    r = size / 2
    d = (np.abs(x - C + 0.5) / r) ** n + (np.abs(y - C + 0.5) / r) ** n
    # anti-aliased edge from the implicit function's gradient
    edge = (1 - d) * r / n * 1.0
    return np.clip(edge + 0.5, 0, 1)


def layer(color, alpha):
    img = np.zeros((S, S, 4))
    img[..., :3] = color
    img[..., 3] = alpha
    return img


def over(base, top):
    """Premultiplied-free 'over' compositing of float RGBA arrays."""
    ta = top[..., 3:4]
    ba = base[..., 3:4]
    oa = ta + ba * (1 - ta)
    out_rgb = (top[..., :3] * ta + base[..., :3] * ba * (1 - ta)) / np.maximum(oa, 1e-9)
    return np.concatenate([out_rgb, oa], axis=-1)


def blur(arr, radius):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), float) / 255


def background():
    y, x = np.mgrid[0:S, 0:S].astype(float)
    # off-centre radial glow, indigo into near-black
    d = np.hypot(x - 0.30 * S, y - 0.22 * S) / S
    t = np.clip(d / 0.95, 0, 1)
    inner, outer = rgb("1B2466"), rgb("05070F")
    color = inner[None, None, :] * (1 - t[..., None]) ** 1.6 + outer[None, None, :] * (1 - (1 - t[..., None]) ** 1.6)
    img = layer(color, np.ones((S, S)))
    # stars
    rnd = random.Random(22)
    stars = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(stars)
    for _ in range(260):
        px, py = rnd.randrange(S), rnd.randrange(S)
        r = rnd.choice([1, 1, 1, 2, 2, 3]) * S / 1024
        draw.ellipse([px - r, py - r, px + r, py + r], fill=rnd.randrange(90, 255))
    star = np.asarray(stars.filter(ImageFilter.GaussianBlur(0.8 * S / 1024)), float) / 255
    return over(img, layer(np.array([0.85, 0.92, 1.0]), star * 0.8))


def split(rect, weights, axis):
    """Slice a rect (x, y, w, h) into pieces along 'x' or 'y' in proportion to weights."""
    x, y, w, h = rect
    total = sum(weights)
    out, pos = [], 0.0
    for wt in weights:
        f = wt / total
        out.append((x + pos * w, y, f * w, h) if axis == "x" else (x, y + pos * h, w, f * h))
        pos += f
    return out


def treemap_cells():
    """A hand-laid treemap filling the unit square: (x, y, w, h, palette index, brightness)."""
    cells = []
    left, right = split((0, 0, 1, 1), [0.54, 0.46], "x")
    left_top, left_bottom = split(left, [0.62, 0.38], "y")
    big, side = split(left_top, [0.68, 0.32], "x")
    cells.append((*big, 0, 1.0))
    for r, c, b in zip(split(side, [0.55, 0.45], "y"), (4, 6), (1.0, 0.9)):
        cells.append((*r, c, b))
    violet, rest = split(left_bottom, [0.5, 0.5], "x")
    cells.append((*violet, 2, 1.0))
    for r, c, b in zip(split(rest, [0.5, 0.5], "y"), (3, 6), (1.0, 1.0)):
        cells.append((*r, c, b))
    right_top, right_bottom = split(right, [0.40, 0.60], "y")
    amber, rest = split(right_top, [0.65, 0.35], "x")
    cells.append((*amber, 1, 1.0))
    for r, c, b in zip(split(rest, [0.5, 0.5], "y"), (5, 4), (1.0, 0.85)):
        cells.append((*r, c, b))
    a, b_ = split(right_bottom, [0.45, 0.55], "x")
    for r, c, br in zip(split(a, [0.6, 0.4], "y"), (5, 0), (0.9, 0.8)):
        cells.append((*r, c, br))
    magenta, tail = split(b_, [0.35, 0.65], "y")
    cells.append((*magenta, 3, 0.9))
    for r, c, br in zip(split(tail, [0.5, 0.5], "x"), (7, 6), (1.0, 0.85)):
        cells.append((*r, c, br))
    return cells


def platter():
    """The disk: treemap cells clipped to a ring, each a shaded cushion with a luminous edge."""
    side = int(0.70 * S)
    x0 = C - side // 2
    y0 = C - side // 2
    gap = int(0.007 * S)
    out = np.zeros((S, S, 4))
    glow = np.zeros((S, S, 3))

    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    radius = side / 2
    dist = np.hypot(xx - C + 0.5, yy - C + 0.5)
    ring = np.clip(radius - dist + 0.5, 0, 1) * np.clip(dist - 0.095 * S + 0.5, 0, 1)

    for (fx, fy, fw, fh, ci, bright) in treemap_cells():
        cx0, cy0 = x0 + fx * side + gap, y0 + fy * side + gap
        cx1, cy1 = x0 + (fx + fw) * side - gap, y0 + (fy + fh) * side - gap
        w, h = cx1 - cx0, cy1 - cy0
        col = rgb(PALETTE[ci]) * bright
        # cushion: paraboloid height, light from the top left
        u = np.clip((xx - cx0) / w, 0, 1) * 2 - 1
        v = np.clip((yy - cy0) / h, 0, 1) * 2 - 1
        nx, ny = u * 0.9, v * 0.9
        lx, ly, lz = -0.45, -0.55, 0.70
        norm = np.sqrt(nx * nx + ny * ny + 1)
        cosa = np.clip((nx * lx + ny * ly + lz) / norm, 0, 1)
        shade = 0.30 + 0.95 * cosa ** 1.4
        spec = np.clip(cosa - 0.78, 0, 1) ** 1.5 * 2.4
        base = np.clip(col[None, None, :] * shade[..., None] + spec[..., None] * 0.55, 0, 1)

        # rounded-rect mask with a soft edge
        rr = 0.028 * side
        qx = np.maximum(np.abs(xx - (cx0 + cx1) / 2) - w / 2 + rr, 0)
        qy = np.maximum(np.abs(yy - (cy0 + cy1) / 2) - h / 2 + rr, 0)
        m = np.clip(rr - np.hypot(qx, qy) + 0.5, 0, 1) * ring

        # bright rim just inside the cell edge, tinted by its color
        inner = np.clip(blur(m, 5 * S / 1024) * 0 + m, 0, 1)
        eroded = blur(m, 7 * S / 1024)
        rim = np.clip(m - np.clip((eroded - 0.5) * 2.2, 0, 1), 0, 1)
        base = np.clip(base + rim[..., None] * (col * 0.6 + 0.25)[None, None, :], 0, 1)

        cell = np.concatenate([base, m[..., None]], axis=-1)
        out = over(out, cell)
        glow += blur(m, 16 * S / 1024)[..., None] * col[None, None, :] * 0.55

    # soft neon bloom around the cells, under them
    bloom = layer(np.clip(glow, 0, 1) * 1.0, np.clip(glow.max(axis=-1), 0, 0.75) * ring.max())
    bloom[..., 3] *= np.clip(blur(ring, 22 * S / 1024) * 1.5, 0, 1)
    return over(bloom, out), ring


def rim_rings():
    """Hairline platter edge, spindle hole and a broken outer orbit."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cyan = (0, 229, 255)
    rp = int(0.35 * S)
    d.ellipse([C - rp, C - rp, C + rp, C + rp], outline=cyan + (230,), width=int(5 * S / 1024))
    hole = int(0.095 * S)
    d.ellipse([C - hole, C - hole, C + hole, C + hole], fill=(5, 7, 15, 255), outline=cyan + (255,),
              width=int(6 * S / 1024))
    inner = int(0.040 * S)
    d.ellipse([C - inner, C - inner, C + inner, C + inner], outline=(255, 255, 255, 140), width=int(3 * S / 1024))
    ro = int(0.39 * S)
    for start, end in ((200, 262), (292, 350), (20, 80)):
        d.arc([C - ro, C - ro, C + ro, C + ro], start, end, fill=(138, 92, 255, 200), width=int(5 * S / 1024))
    glow = img.filter(ImageFilter.GaussianBlur(10 * S / 1024))
    arr = np.asarray(img, float) / 255
    garr = np.asarray(glow, float) / 255
    out = over(garr, arr)
    out[..., :3] = np.where(out[..., 3:4] > 0, out[..., :3], 0)
    return out


def glass_sheen(mask):
    """Specular sheen over the upper half and a crisp rim light on the tile edge."""
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    # a big soft ellipse of light from the top left
    e = ((xx - 0.30 * S) / (0.80 * S)) ** 2 + ((yy - 0.02 * S) / (0.46 * S)) ** 2
    sheen = np.clip(1 - e, 0, 1) ** 1.8 * 0.20
    out = layer(np.array([0.85, 0.95, 1.0]), sheen * mask)

    # rim light: the tile mask minus an inset copy, brighter at the top
    inset = squircle_mask(BODY - int(0.016 * S))
    rim = np.clip(mask - inset, 0, 1)
    top = np.clip(1.15 - yy / (0.75 * S), 0.2, 1)
    out = over(out, layer(np.array([0.75, 0.95, 1.0]), rim * top * 0.55))
    inner_shadow = np.clip(blur(1 - mask, 9 * S / 1024) * mask, 0, 1)
    return over(out, layer(np.array([0.0, 0.0, 0.0]), inner_shadow * 0.45))


def render():
    mask = squircle_mask(BODY)
    tile = background()
    plat, _ = platter()
    tile = over(tile, plat)
    tile = over(tile, rim_rings())
    tile = over(tile, glass_sheen(mask))
    tile[..., 3] *= mask

    # soft drop shadow under the tile
    shadow_a = blur(np.roll(mask, int(0.014 * S), axis=0), 18 * S / 1024) * 0.55
    canvas = layer(np.zeros(3), shadow_a)
    canvas = over(canvas, tile)
    img = Image.fromarray((np.clip(canvas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    return img.resize((1024, 1024), Image.LANCZOS)


def main():
    master = render()
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        out = sys.argv[2] if len(sys.argv) > 2 else "dix-icon-1024.png"
        master.save(out)
        print("wrote", out)
        return

    sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    images = []
    for points, scale in sizes:
        px = points * scale
        name = f"DIXIcon {points}@{scale}.png"
        master.resize((px, px), Image.LANCZOS).save(ICONSET / name)
        images.append({"size": f"{points}x{points}", "idiom": "mac", "filename": name, "scale": f"{scale}x"})
    (ICONSET / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")

    small = master.resize((128, 128), Image.LANCZOS)
    small.save(SRC / "Disk Inventory Icon.png")
    small.save(SRC / "Disk Inventory Icon.tif", compression="tiff_lzw")
    print("icon written")


if __name__ == "__main__":
    main()
