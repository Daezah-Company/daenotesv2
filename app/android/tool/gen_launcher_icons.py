#!/usr/bin/env python3
"""Render Android launcher icons from the DaeNotes monogram."""

from pathlib import Path
import sys

from PIL import Image


DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def render(size: int, source: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    # Preserve the landscape monogram's proportions. At 70% of the canvas
    # width, its 1.7:1 shape leaves vertical padding about twice the horizontal
    # padding, matching the requested spacing without stretching it.
    source = source.crop(source.getchannel("A").getbbox())
    max_logo_size = round(size * 0.70)
    scale = min(max_logo_size / source.width, max_logo_size / source.height)
    logo = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas.alpha_composite(
        logo,
        ((size - logo.width) // 2, (size - logo.height) // 2),
    )
    return canvas


def render_adaptive_foreground(source: Image.Image, size: int = 2048) -> Image.Image:
    """Center the monogram in a transparent adaptive-icon canvas."""
    source = source.crop(source.getchannel("A").getbbox())
    # Android scales adaptive foreground layers up to fill the icon mask.
    # Use 52% here to compensate for the TECNO launcher's adaptive-icon scale.
    max_logo_size = round(size * 0.52)
    scale = min(max_logo_size / source.width, max_logo_size / source.height)
    logo = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(
        logo,
        ((size - logo.width) // 2, (size - logo.height) // 2),
    )
    return canvas


if __name__ == "__main__":
    resources = Path(sys.argv[1])
    source_path = Path(__file__).resolve().parents[2] / "assets/branding/daenotes_monogram.png"
    source = Image.open(source_path).convert("RGBA")
    adaptive_output = resources / "drawable-nodpi/daenotes_icon_foreground_square.png"
    adaptive_output.parent.mkdir(parents=True, exist_ok=True)
    render_adaptive_foreground(source).save(
        adaptive_output
    )
    print(adaptive_output)
    for folder, size in DENSITIES.items():
        output = resources / folder / "ic_launcher.png"
        output.parent.mkdir(parents=True, exist_ok=True)
        render(size, source).save(output)
        print(output)
