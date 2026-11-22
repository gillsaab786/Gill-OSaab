#!/usr/bin/env python3
"""Generates the original Gill-OSaab wallpapers (dark + light) and the logo.

Soft aurora glows over a deep gradient with flowing ribbons; no third-party art.
Usage: python3 tools/make_wallpaper.py <output wallpaper package dir>
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

W, H = 3840, 2160


def glow(xx, yy, cx, cy, r):
    d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / (r * r)
    return np.exp(-d2)


def ribbon(xx, yy, base, amp, freq, phase, width):
    centre = base + amp * np.sin(xx * freq + phase) + amp * 0.35 * np.sin(xx * freq * 2.3 + phase * 1.7)
    return np.exp(-((yy - centre) / width) ** 2)


def render(dark):
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    xn, yn = x / W, y / H
    if dark:
        top, bottom = np.array([8, 12, 28]), np.array([3, 4, 10])
        colours = [(np.array([31, 182, 201]), 0.30, 0.75, 0.55, 0.55),   # teal
                   (np.array([110, 72, 230]), 0.85, 0.25, 0.50, 0.45),   # violet
                   (np.array([40, 110, 255]), 0.55, 0.95, 0.45, 0.35)]   # blue
        ribbon_col, ribbon_alpha = np.array([120, 230, 240]), 0.22
    else:
        top, bottom = np.array([236, 242, 250]), np.array([214, 226, 242])
        colours = [(np.array([90, 210, 225]), 0.30, 0.75, 0.55, 0.45),
                   (np.array([170, 150, 255]), 0.85, 0.25, 0.50, 0.40),
                   (np.array([120, 170, 255]), 0.55, 0.95, 0.45, 0.30)]
        ribbon_col, ribbon_alpha = np.array([255, 255, 255]), 0.45

    img = top[None, None, :] * (1 - yn[..., None]) + bottom[None, None, :] * yn[..., None]
    for col, cx, cy, r, strength in colours:
        g = glow(xn, yn * (H / W), cx, cy * (H / W), r * 0.6)[..., None] * strength
        img = img * (1 - g) + col[None, None, :] * g

    for i, (base, amp, freq, phase, width) in enumerate([
        (0.58, 0.06, 5.2, 0.4, 0.010), (0.62, 0.05, 4.4, 1.6, 0.006),
        (0.66, 0.07, 3.7, 2.9, 0.004), (0.55, 0.04, 6.1, 4.2, 0.003),
    ]):
        r = ribbon(xn, yn, base, amp, freq, phase, width)[..., None] * ribbon_alpha * (1 - 0.18 * i)
        img = img * (1 - r) + ribbon_col[None, None, :] * r

    # gentle vignette
    v = 1 - 0.35 * (((xn - 0.5) ** 2 + (yn - 0.5) ** 2) * 1.6)
    if dark:
        img = img * v[..., None]
    img = np.clip(img, 0, 255).astype(np.uint8)
    im = Image.fromarray(img, "RGB").filter(ImageFilter.GaussianBlur(1.2))
    # fine grain to stop banding on 8-bit panels
    noise = (np.random.default_rng(7).normal(0, 1.6, (H, W, 1))).repeat(3, axis=2)
    out = np.clip(np.asarray(im).astype(np.float32) + noise, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGB")


def main(dest):
    dest = Path(dest)
    (dest / "contents/images").mkdir(parents=True, exist_ok=True)
    (dest / "contents/images_dark").mkdir(parents=True, exist_ok=True)
    dark, light = render(True), render(False)
    dark.save(dest / "contents/images_dark/3840x2160.png", optimize=True)
    light.save(dest / "contents/images/3840x2160.png", optimize=True)
    dark.resize((640, 360), Image.LANCZOS).save(dest / "contents/screenshot.png")
    print("wallpapers written to", dest)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/GillOSaab")
