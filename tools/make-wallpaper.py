#!/usr/bin/env python3
"""Render Gill-OSaab's "Tide" wallpaper: layered glass folds, light and dark.

Original artwork, drawn procedurally: python3 tools/make-wallpaper.py OUTDIR [WIDTH HEIGHT]
"""
import sys
import numpy as np
from PIL import Image

W, H = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (3840, 2160)
out = sys.argv[1] if len(sys.argv) > 1 else "."

y, x = np.mgrid[0:H, 0:W].astype(np.float32)
u, v = x / W, y / H

PALETTES = {
    # sky top, sky bottom, fold colours back→front, rim light
    "dark": dict(top=(4, 10, 34), bottom=(10, 32, 96),
                 folds=[(18, 52, 140), (22, 76, 190), (30, 104, 228), (44, 132, 255), (12, 40, 120)],
                 rim=(150, 205, 255), glow=(70, 140, 255), vig=0.25),
    "light": dict(top=(205, 228, 255), bottom=(150, 192, 252), vig=0.08,
                  folds=[(150, 190, 250), (110, 160, 245), (70, 130, 235), (40, 105, 225), (165, 200, 252)],
                  rim=(255, 255, 255), glow=(255, 255, 255)),
}

# fold edges: (base height, [(amplitude, frequency, phase)...]) back to front
FOLDS = [
    (0.42, [(0.07, 1.1, 0.4), (0.03, 2.3, 1.9)]),
    (0.55, [(0.08, 0.9, 2.2), (0.025, 2.9, 0.3)]),
    (0.66, [(0.07, 1.3, 4.0), (0.03, 2.1, 2.6)]),
    (0.77, [(0.06, 1.0, 5.3), (0.02, 3.3, 1.2)]),
    (0.90, [(0.05, 1.5, 0.9), (0.02, 2.7, 4.4)]),
]


def edge(base, waves):
    e = np.full(W, base, np.float32)
    xs = np.linspace(0, 1, W, dtype=np.float32)
    for a, f, p in waves:
        e += a * np.sin(2 * np.pi * f * xs + p)
    return e[None, :] * H


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def render(name):
    p = PALETTES[name]
    top, bot = np.array(p["top"], np.float32), np.array(p["bottom"], np.float32)
    img = top + (bot - top) * smooth(v)[..., None]
    # a soft light source upper-right
    d = np.sqrt((u - 0.72) ** 2 * 1.8 + (v - 0.18) ** 2)
    img += np.array(p["glow"], np.float32) * (0.22 * np.exp(-d * d / 0.06))[..., None]

    for i, (base, waves) in enumerate(FOLDS):
        e = edge(base, waves)
        depth = (y - e) / H                       # >0 below the fold edge
        inside = smooth(depth * 400 + 0.5)        # anti-aliased edge
        col = np.array(p["folds"][i], np.float32)
        # the face darkens with depth and lightens toward the right, like curved glass
        shade = 1.0 - 0.55 * smooth(depth / 0.35) + 0.18 * (u - 0.5)
        face = col * shade[..., None]
        # shadow cast on what is behind, just above the edge
        shadow = np.exp(-np.clip(-depth, 0, None) / 0.018) * (1 - inside)
        img *= (1 - 0.35 * shadow)[..., None]
        img = img * (1 - inside[..., None]) + face * inside[..., None]
        # bright rim on the crest that fades along the fold
        rim = np.exp(-np.clip(depth, 0, None) / 0.004) * inside
        rim *= 0.55 + 0.45 * np.sin(2 * np.pi * (u * 1.3 + i * 0.21)) ** 2
        img += np.array(p["rim"], np.float32) * (0.55 * rim)[..., None]
        # inner sheen a little under the rim
        sheen = np.exp(-((depth - 0.03) ** 2) / 0.0004) * inside
        img += np.array(p["rim"], np.float32) * (0.10 * sheen)[..., None]

    # vignette and film grain so gradients don't band
    vig = 1 - p["vig"] * smooth(np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * 1.4)
    img *= vig[..., None]
    img += np.random.default_rng(7).normal(0, 1.2, img.shape).astype(np.float32)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


if __name__ == "__main__":
    import os
    for name, folder in (("dark", "images_dark"), ("light", "images")):
        os.makedirs(f"{out}/{folder}", exist_ok=True)
        im = render(name)
        im.save(f"{out}/{folder}/{W}x{H}.png", optimize=True)
        if name == "dark":
            im.resize((W // 8, H // 8), Image.LANCZOS).save(f"{out}/screenshot.png")
