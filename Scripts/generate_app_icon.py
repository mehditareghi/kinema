#!/usr/bin/env python3
"""Generate the Kinema app icon foreground — wine/cinema-rose K on transparent canvas.

Apple applies the squircle mask, glass, and background in iOS 26+.
Do not bake in a rounded-rect background or drop shadows.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
# #C45B6A — matches KinemaTheme.accent (wine / cinema rose)
WINE = (196, 91, 106, 255)
OUTPUT = Path(__file__).resolve().parents[1] / "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def draw_k(draw: ImageDraw.ImageDraw, center: tuple[float, float], scale: float, fill) -> None:
    """Bold geometric K with uniform stroke weight."""
    cx, cy = center
    t = scale * 0.17
    stem_left = cx - scale * 0.34
    stem_right = stem_left + t
    top = cy - scale * 0.46
    bottom = cy + scale * 0.46
    joint = cy

    draw.rounded_rectangle(
        (stem_left, top, stem_right, bottom),
        radius=int(t * 0.34),
        fill=fill,
    )

    upper = [
        (stem_right - t * 0.08, joint - t * 0.62),
        (cx + scale * 0.34, top + t * 0.35),
        (cx + scale * 0.34 - t, top + t * 0.35 + t * 0.82),
        (stem_right - t * 0.08, joint - t * 0.62 + t * 0.82),
    ]
    draw.polygon(upper, fill=fill)

    lower = [
        (stem_right - t * 0.08, joint + t * 0.62 - t * 0.82),
        (cx + scale * 0.36, bottom - t * 0.35 - t * 0.82),
        (cx + scale * 0.36 - t, bottom - t * 0.35),
        (stem_right - t * 0.08, joint + t * 0.62),
    ]
    draw.polygon(lower, fill=fill)


def main() -> None:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw_k(draw, (SIZE * 0.5, SIZE * 0.5), SIZE * 0.52, WINE)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, "PNG")
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
