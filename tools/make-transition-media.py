#!/usr/bin/env python3
"""Render Gill(OS)'s Game Mode startup movie and the mode-switch sound (original artwork).

  python3 tools/make-transition-media.py OUTDIR   ->  OUTDIR/deck_startup.webm, OUTDIR/mode-switch.wav
Needs Pillow and ffmpeg (libvpx-vp9). The movie is what Steam plays as Game Mode starts.
"""
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
W, H, FPS, SECONDS, SS = 1280, 800, 30, 2.4, 2
WALL = os.path.join(os.path.dirname(__file__), "../files/system/usr/share/wallpapers/GillOSaab/contents/thumb-dark.jpg")


def ease_out_back(t, s=1.9):
    t -= 1
    return t * t * ((s + 1) * t + s) + 1


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/google-noto/NotoSans-Bold.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def gamepad(d, cx, cy, s, alpha):
    white = (255, 255, 255, alpha)
    d.rounded_rectangle((cx - 0.42 * s, cy - 0.22 * s, cx + 0.42 * s, cy + 0.24 * s), radius=0.22 * s, outline=white,
                        width=max(2, int(0.045 * s)))
    t = 0.04 * s
    d.rectangle((cx - 0.27 * s - t, cy - 0.11 * s, cx - 0.27 * s + t, cy + 0.11 * s), fill=white)
    d.rectangle((cx - 0.38 * s, cy - t, cx - 0.16 * s, cy + t), fill=white)
    for bx, by in ((0.2, -0.05), (0.29, 0.05)):
        r = 0.045 * s
        d.ellipse((cx + bx * s - r, cy + by * s - r, cx + bx * s + r, cy + by * s + r), fill=white)


def frame(i, n, bg, wordmark):
    t = i / FPS
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    # background: dark Tide, fading in, slowly pushing in
    zoom = 1.0 + 0.04 * t / SECONDS + 0.25 * smooth((t - 1.9) / 0.5)
    bw, bh = int(w * zoom), int(h * zoom)
    b = bg.resize((bw, bh), Image.BILINEAR).crop(((bw - w) // 2, (bh - h) // 2, (bw - w) // 2 + w, (bh - h) // 2 + h))
    fade = smooth(t / 0.45) * (1 - smooth((t - 1.95) / 0.45))
    img = Image.blend(img, b.convert("RGBA"), fade * 0.85)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # the glass tile springs in
    p = max(0.0, min(1.0, (t - 0.15) / 0.75))
    scale = ease_out_back(p) if p > 0 else 0
    scale *= 1 + 0.5 * smooth((t - 1.9) / 0.5)
    out = 1 - smooth((t - 1.9) / 0.45)
    size = 300 * SS * scale
    cx, cy = w / 2, h / 2 - 50 * SS
    if size > 4:
        a = int(255 * out * smooth(p * 3))
        box = (cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2)
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(glow).rounded_rectangle(box, radius=size * 0.26, fill=(60, 140, 255, int(a * 0.55)))
        img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(40 * SS)))
        d.rounded_rectangle(box, radius=size * 0.26, fill=(255, 255, 255, int(a * 0.16)),
                            outline=(255, 255, 255, int(a * 0.75)), width=max(2, int(3 * SS)))
        d.rounded_rectangle((box[0] + 6 * SS, box[1] + 6 * SS, box[2] - 6 * SS, box[1] + size * 0.45),
                            radius=size * 0.22, fill=(255, 255, 255, int(a * 0.08)))
        gamepad(d, cx, cy, size * 0.78, a)
        # shine sweeping across the glass
        sp = (t - 1.15) / 0.55
        if 0 < sp < 1:
            shine = Image.new("L", (w, h), 0)
            sx = box[0] - size * 0.4 + sp * size * 1.8
            ImageDraw.Draw(shine).polygon([(sx, box[1]), (sx + size * 0.18, box[1]), (sx - size * 0.12, box[3]),
                                           (sx - size * 0.30, box[3])], fill=int(110 * out))
            mask = Image.new("L", (w, h), 0)
            ImageDraw.Draw(mask).rounded_rectangle(box, radius=size * 0.26, fill=255)
            shine = Image.composite(shine, Image.new("L", (w, h), 0), mask).filter(ImageFilter.GaussianBlur(6 * SS))
            layer = Image.alpha_composite(layer, Image.merge("RGBA", [Image.new("L", (w, h), 255)] * 3 + [shine]))
            d = ImageDraw.Draw(layer)
    # wordmark rises in under the tile
    q = smooth((t - 0.7) / 0.5) * out
    if q > 0:
        tw = d.textlength(wordmark, font=FONT)
        d.text((cx - tw / 2, cy + 200 * SS + (1 - q) * 24 * SS), wordmark, font=FONT, fill=(255, 255, 255, int(235 * q)))
    img = Image.alpha_composite(img, layer)
    return img.convert("RGB").resize((W, H), Image.LANCZOS)


def sound(path):
    """A short two-note glassy chime (original), like a console's mode switch."""
    rate = 48000
    notes = [(0.00, 0.28, 880.0), (0.09, 0.40, 1318.5)]
    total = int(rate * 0.55)
    samples = [0.0] * total
    for start, dur, f in notes:
        s0 = int(start * rate)
        for k in range(int(dur * rate)):
            t = k / rate
            env = min(1.0, t / 0.004) * math.exp(-t * 9)
            v = env * (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * f * 2.01 * t)
                       + 0.12 * math.sin(2 * math.pi * f * 3.0 * t))
            if s0 + k < total:
                samples[s0 + k] += 0.28 * v
    with wave.open(path, "wb") as wv:
        wv.setnchannels(1)
        wv.setsampwidth(2)
        wv.setframerate(rate)
        wv.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    FONT = font(64 * SS)
    bg = Image.open(WALL).convert("RGB") if os.path.exists(WALL) else Image.new("RGB", (W, H), (8, 20, 60))
    n = int(FPS * SECONDS)
    with tempfile.TemporaryDirectory() as tmp:
        for i in range(n):
            frame(i, n, bg, "Gill(OS)").save(f"{tmp}/f{i:03d}.png")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", f"{tmp}/f%03d.png",
                        "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "36", "-pix_fmt", "yuv420p", "-row-mt", "1",
                        f"{OUT}/deck_startup.webm"], check=True)
        frame(int(1.3 * FPS), n, bg, "Gill(OS)").save(f"{OUT}/preview.jpg") if os.environ.get("PREVIEW") else None
    sound(f"{OUT}/mode-switch.wav")
