#!/usr/bin/env python3
"""Generate Kinema's Apple app icon artwork.

The default rendition owns Kinema's velvet background. Dark and tinted
renditions contain only transparent foreground artwork, allowing Apple's
system-provided appearance backgrounds to show through. A separate 512px
raster keeps the macOS 1x slot exact.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

SIZE = 1024
CRIMSON = (218, 75, 67)
PROJECTOR_WHITE = (246, 237, 220)
TINTED_RED = (148, 148, 148, 255)
TINTED_WHITE = (244, 244, 244, 255)
# Kinema's own enclosure: deep cinema velvet, lifted subtly toward the mark.
# Appearance metadata remains system-owned; this is the brand's default field.
AUDITORIUM_EDGE = (22, 7, 10)
AUDITORIUM_GLOW = (49, 13, 17)

OUTPUT_DIRECTORY = Path(__file__).resolve().parents[1] / "Resources/Assets.xcassets/AppIcon.appiconset"


def draw_mark(
    draw: ImageDraw.ImageDraw,
    size: int,
    upper_color: tuple[int, ...],
    lower_color: tuple[int, ...],
) -> None:
    scale = size / SIZE
    radius = round(265 * scale)
    top_center = (round(553 * scale), round(468 * scale))
    bottom_center = (round(471 * scale), round(556 * scale))

    # Upper and lower halves of the same disc, shifted one beat apart.
    draw.pieslice(
        (
            top_center[0] - radius,
            top_center[1] - radius,
            top_center[0] + radius,
            top_center[1] + radius,
        ),
        start=180,
        end=360,
        fill=upper_color,
    )
    draw.pieslice(
        (
            bottom_center[0] - radius,
            bottom_center[1] - radius,
            bottom_center[0] + radius,
            bottom_center[1] + radius,
        ),
        start=0,
        end=180,
        fill=lower_color,
    )


def render_default_icon(output_name: str, size: int) -> None:
    edge = Image.new("RGB", (size, size), AUDITORIUM_EDGE)
    glow = Image.new("RGB", (size, size), AUDITORIUM_GLOW)
    radial = ImageOps.invert(Image.radial_gradient("L").resize((size, size)))
    radial = radial.point(lambda value: round(value * 0.78))
    image = Image.composite(glow, edge, radial)
    draw = ImageDraw.Draw(image)
    draw_mark(draw, size, CRIMSON, PROJECTOR_WHITE)

    output = OUTPUT_DIRECTORY / output_name
    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    image.save(output, "PNG")
    print(f"Wrote {output}")


def render_transparent_icon(
    output_name: str,
    upper_color: tuple[int, int, int, int],
    lower_color: tuple[int, int, int, int],
) -> None:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(image), SIZE, upper_color, lower_color)
    output = OUTPUT_DIRECTORY / output_name
    image.save(output, "PNG")
    print(f"Wrote {output}")


def main() -> None:
    render_default_icon("AppIcon.png", 1024)
    render_default_icon("AppIcon-mac.png", 512)
    render_transparent_icon("AppIcon-Dark.png", CRIMSON + (255,), PROJECTOR_WHITE + (255,))
    render_transparent_icon("AppIcon-Tinted.png", TINTED_RED, TINTED_WHITE)


if __name__ == "__main__":
    main()
