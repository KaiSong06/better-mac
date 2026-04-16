#!/usr/bin/env python3
"""
Generate a placeholder app icon for better-mac.

Design: black rounded square with a centered white waveform glyph. Matches the
in-app aesthetic (black notch, white waveform) so the Dock icon reads as the
same thing as what's rendering on screen.

Emits every size the asset catalog expects:
    icon_16x16.png, icon_16x16@2x.png,
    icon_32x32.png, icon_32x32@2x.png,
    icon_128x128.png, icon_128x128@2x.png,
    icon_256x256.png, icon_256x256@2x.png,
    icon_512x512.png, icon_512x512@2x.png

Outputs to better-mac/Resources/Assets.xcassets/AppIcon.appiconset/.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "better-mac" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"


def rounded_square(size: int, radius_frac: float = 0.225) -> Image.Image:
    """Create a black rounded-square canvas with transparent corners.

    macOS app icons use a specific squircle shape; we approximate with a
    rounded rectangle at 22.5% corner radius which is what Apple's own icon
    grid uses as the outer bezel.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(size * radius_frac)
    draw.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=radius,
        fill=(0, 0, 0, 255),
    )
    return img


def draw_waveform(img: Image.Image, color=(255, 255, 255, 240)) -> None:
    """Overlay a centered sine-wave line on the given image."""
    draw = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    inset = int(w * 0.18)
    line_w = max(2, int(w * 0.04))
    amplitude = int(h * 0.18)
    cycles = 1.4

    mid_y = h / 2
    start_x = inset
    end_x = w - inset
    span = end_x - start_x

    # Build a polyline at ~2 pixels per step for smooth rendering.
    step = max(1, int(span / 200))
    points: list[tuple[float, float]] = []
    x = start_x
    while x <= end_x:
        t = (x - start_x) / span
        y = mid_y + amplitude * math.sin(2 * math.pi * cycles * t)
        points.append((x, y))
        x += step
    if points[-1][0] < end_x:
        t = 1.0
        y = mid_y + amplitude * math.sin(2 * math.pi * cycles * t)
        points.append((end_x, y))

    draw.line(points, fill=color, width=line_w, joint="curve")

    # Two soft accent dots at either end for extra personality.
    dot_r = max(2, int(w * 0.028))
    for (cx, cy) in (points[0], points[-1]):
        draw.ellipse(
            (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
            fill=color,
        )


def render(size: int) -> Image.Image:
    # Render at 4x then downsample for clean edges at tiny sizes.
    supersample = 4 if size < 256 else 2
    big = size * supersample
    img = rounded_square(big)
    draw_waveform(img)
    return img.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)

    sizes = [
        (16, 1, "icon_16x16.png"),
        (16, 2, "icon_16x16@2x.png"),
        (32, 1, "icon_32x32.png"),
        (32, 2, "icon_32x32@2x.png"),
        (128, 1, "icon_128x128.png"),
        (128, 2, "icon_128x128@2x.png"),
        (256, 1, "icon_256x256.png"),
        (256, 2, "icon_256x256@2x.png"),
        (512, 1, "icon_512x512.png"),
        (512, 2, "icon_512x512@2x.png"),
    ]

    for pt, scale, name in sizes:
        px = pt * scale
        out = ICONSET / name
        render(px).save(out, format="PNG", optimize=True)
        print(f"wrote {out.relative_to(ROOT)} ({px}×{px})")


if __name__ == "__main__":
    main()
