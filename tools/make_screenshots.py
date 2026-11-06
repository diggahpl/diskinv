#!/usr/bin/env python3
"""Compose screenshots from window captures of Disk Inventory Xs.

The captures are real windows of the app showing the demo folder
(tools/make_demo_folder.py), taken with `screencapture -o -l <window id>`.
Each one is placed on a deep-space canvas under a caption, at 2880x1800
(Retina 16:10), and also scaled to 1440x900.

usage: tools/make_screenshots.py OUT_DIR SPEC.json
  SPEC.json: [{"image": "window.png", "title": "...", "subtitle": "...", "name": "01-overview"}, ...]
  (image paths are relative to the spec file)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

WIDTH, HEIGHT = 2880, 1800
SPACE_TOP = (11, 16, 32)
SPACE_BOTTOM = (5, 7, 14)
ACCENT = (0, 229, 255)
FONT = "/System/Library/Fonts/SFNS.ttf"


def load_font(size, weight):
    font = ImageFont.truetype(FONT, size)
    try:
        font.set_variation_by_name(weight)
    except Exception:  # fixed-weight font: keep what we got
        pass
    return font


def background():
    """Deep-space gradient with a faint cyan glow behind the caption."""
    y = np.linspace(0, 1, HEIGHT)[:, None, None]
    pixels = (np.array(SPACE_TOP) * (1 - y) + np.array(SPACE_BOTTOM) * y) * np.ones((1, WIDTH, 1))
    xs = np.linspace(-1, 1, WIDTH)[None, :]
    ys = np.linspace(0, 1, HEIGHT)[:, None]
    glow = np.clip(1 - np.sqrt((xs / 0.9) ** 2 + (ys / 0.4) ** 2), 0, 1) ** 2
    pixels = pixels + glow[..., None] * np.array([0, 70, 90])
    return Image.fromarray(np.clip(pixels, 0, 255).astype("uint8"), "RGB")


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def compose(window_path, title, subtitle):
    canvas = background().convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    title_font = load_font(92, "Bold")
    subtitle_font = load_font(44, "Regular")
    title_width = draw.textlength(title, font=title_font)
    draw.text(((WIDTH - title_width) / 2, 96), title, font=title_font, fill=(255, 255, 255))
    subtitle_width = draw.textlength(subtitle, font=subtitle_font)
    draw.text(((WIDTH - subtitle_width) / 2, 214), subtitle, font=subtitle_font, fill=(150, 205, 220))

    window = Image.open(window_path).convert("RGBA")
    max_w, max_h = 2560, 1390
    scale = min(max_w / window.width, max_h / window.height)
    size = (round(window.width * scale), round(window.height * scale))
    window = window.resize(size, Image.LANCZOS)
    left = (WIDTH - size[0]) // 2
    top = 330 + (max_h - size[1]) // 2

    # shadow
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((left, top + 24, left + size[0], top + size[1] + 24), radius=40, fill=(0, 0, 0, 200))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(window, (left, top))
    return canvas.convert("RGB")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    out_dir, spec_path = sys.argv[1], sys.argv[2]
    base = os.path.dirname(os.path.abspath(spec_path))
    os.makedirs(out_dir, exist_ok=True)
    for entry in json.load(open(spec_path)):
        image = compose(os.path.join(base, entry["image"]), entry["title"], entry["subtitle"])
        image.save(os.path.join(out_dir, entry["name"] + "-2880x1800.png"), optimize=True)
        image.resize((1440, 900), Image.LANCZOS).save(os.path.join(out_dir, entry["name"] + "-1440x900.png"), optimize=True)
        print(entry["name"])


main()
