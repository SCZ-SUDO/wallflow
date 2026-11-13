#!/usr/bin/env python3
"""Generates Wallflow's app icon (aurora lines + play glyph) and .icns."""

import math
import os
import subprocess

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048  # supersampled canvas
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources")
ICONSET = os.path.join(OUT, "AppIcon.iconset")


def gradient(size, stops, start=(0, 0), end=(1, 1)):
    """Linear gradient through color stops: [(pos, (r,g,b)), ...]."""
    w, h = size
    y, x = np.mgrid[0:h, 0:w]
    dx, dy = end[0] - start[0], end[1] - start[1]
    t = ((x / (w - 1)) - start[0]) * dx + ((y / (h - 1)) - start[1]) * dy
    t = np.clip(t / (dx * dx + dy * dy), 0, 1)
    arr = np.zeros((h, w, 3), dtype=np.float32)
    positions = [p for p, _ in stops]
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        mask = (t >= p0) & (t <= p1)
        local = (t[mask] - p0) / max(p1 - p0, 1e-6)
        for c in range(3):
            arr[mask, c] = c0[c] + (c1[c] - c0[c]) * local
    arr[t < positions[0]] = stops[0][1]
    arr[t > positions[-1]] = stops[-1][1]
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def curve_points(base, amp, wavelength, phase, size=S):
    points = []
    for px in range(-40, size + 41, 6):
        y = (
            base
            + amp * math.sin(2 * math.pi * px / wavelength + phase)
            + amp * 0.32 * math.sin(2 * math.pi * px / (wavelength * 0.37) - phase * 1.3)
        )
        points.append((px, y))
    return points


def aurora_layer(size):
    """Thin, luminous ribbons; screened on top of the body."""
    glow = Image.new("RGB", (size, size), (0, 0, 0))

    curves = [
        # base, amplitude, wavelength, phase, color, width
        (1210, 78, 1500, 0.2, (44, 226, 190), 5),
        (1280, 96, 1700, 1.6, (64, 170, 255), 4),
        (1365, 110, 1900, 3.1, (170, 92, 255), 5),
        (1435, 88, 1600, 4.4, (255, 108, 168), 4),
        (1490, 60, 1200, 5.5, (80, 240, 220), 3),
    ]

    for base, amp, wl, phase, color, width in curves:
        points = curve_points(base, amp, wl, phase, size)

        # Soft bloom.
        bloom = Image.new("RGB", (size, size), (0, 0, 0))
        bd = ImageDraw.Draw(bloom)
        bd.line(points, fill=tuple(int(c * 0.45) for c in color), width=width * 7, joint="curve")
        bloom = bloom.filter(ImageFilter.GaussianBlur(width * 6))
        glow = ImageChops.screen(glow, bloom)

        # Bright core.
        core = Image.new("RGB", (size, size), (0, 0, 0))
        cd = ImageDraw.Draw(core)
        cd.line(points, fill=color, width=width, joint="curve")
        core = core.filter(ImageFilter.GaussianBlur(1.6))
        glow = ImageChops.screen(glow, core)

    return glow


def radial_glow(size, center, radius, color, strength):
    yy, xx = np.mgrid[0:size, 0:size]
    dist = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    alpha = np.clip(1 - dist, 0, 1) ** 2 * strength
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[..., 0] = color[0]
    rgba[..., 1] = color[1]
    rgba[..., 2] = color[2]
    rgba[..., 3] = alpha.astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def main():
    os.makedirs(ICONSET, exist_ok=True)

    # Rounded-square body with a deep-space gradient.
    body = gradient(
        (S, S),
        [
            (0.0, (10, 9, 26)),
            (0.38, (26, 18, 66)),
            (0.68, (64, 32, 128)),
            (1.0, (132, 50, 172)),
        ],
        start=(0.08, 0.0),
        end=(0.92, 1.0),
    )

    # Aurora ribbons, screened low so they glow rather than wash out.
    aurora = aurora_layer(S)
    body = ImageChops.screen(body, aurora.point(lambda v: int(v * 0.55)))

    body = body.convert("RGBA")

    # Soft light behind the play glyph.
    body = Image.alpha_composite(
        body,
        radial_glow(S, (S * 0.52, S * 0.47), S * 0.30, (150, 120, 255), 66),
    )

    # Vignette to focus the centre.
    yy, xx = np.mgrid[0:S, 0:S]
    dist = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S * 0.72)
    alpha = np.clip(dist - 0.72, 0, 1) * 150
    vignette = np.zeros((S, S, 4), dtype=np.uint8)
    vignette[..., 3] = alpha.astype(np.uint8)
    body = Image.alpha_composite(body, Image.fromarray(vignette, "RGBA"))

    # Play triangle, with a soft drop shadow.
    tri = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx, cy = S * 0.515, S * 0.485
    side = S * 0.150
    points = [
        (cx - side * 0.60, cy - side * 0.92),
        (cx - side * 0.60, cy + side * 0.92),
        (cx + side * 1.05, cy),
    ]

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.polygon([(x + 10, y + 18) for x, y in points], fill=(8, 4, 24, 130))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    tri = Image.alpha_composite(shadow, tri)

    td = ImageDraw.Draw(tri)
    td.polygon(points, fill=(255, 255, 255, 255))
    td.line([points[0], points[1], points[2], points[0]], fill=(255, 255, 255, 255), width=18, joint="curve")
    tri = tri.filter(ImageFilter.GaussianBlur(1.1))
    body = Image.alpha_composite(body, tri)

    # Inner rim light.
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.rounded_rectangle(
        [84, 84, S - 84, S - 84],
        radius=190,
        outline=(255, 255, 255, 34),
        width=5,
    )
    body = Image.alpha_composite(body, rim)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([80, 80, S - 80, S - 80], radius=190, fill=255)
    body.putalpha(mask)

    icon = body.resize((1024, 1024), Image.LANCZOS)
    icon.save(os.path.join(OUT, "AppIcon-1024.png"))

    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(
            os.path.join(ICONSET, f"icon_{size}x{size}.png")
        )
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(
            os.path.join(ICONSET, f"icon_{size}x{size}@2x.png")
        )

    subprocess.run(
        ["iconutil", "-c", "icns", ICONSET, "-o", os.path.join(OUT, "AppIcon.icns")],
        check=True,
    )
    print("icon written:", os.path.abspath(os.path.join(OUT, "AppIcon.icns")))


if __name__ == "__main__":
    main()
