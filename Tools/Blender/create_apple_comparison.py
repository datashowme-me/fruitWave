"""Create the source-reference versus Blender-render acceptance sheet.

Three equal-width tiles: PRD whole reference, PRD cut reference, and the
Blender preview render, so colors and silhouette can be compared directly.
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
MODEL_ROOT = ROOT / "FruitWaveApp" / "Resources" / "Models" / "Apple"
REFERENCE_ROOT = MODEL_ROOT  # PRD-extracted references live beside the deliverables

TILE = 800
LABEL = 46
GAP = 40
MARGIN = 40


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    copy = image.convert("RGB")
    copy.thumbnail(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", size, (24, 26, 30))
    canvas.paste(copy, ((size[0] - copy.width) // 2, (size[1] - copy.height) // 2))
    return canvas


def main() -> None:
    whole = Image.open(REFERENCE_ROOT / "apple_reference.png")
    cut = Image.open(REFERENCE_ROOT / "apple_reference_cut.png")
    render = Image.open(MODEL_ROOT / "apple_preview.png")

    width = MARGIN * 2 + TILE * 3 + GAP * 2
    height = LABEL + TILE + MARGIN
    sheet = Image.new("RGB", (width, height), (18, 20, 24))
    draw = ImageDraw.Draw(sheet)

    x0 = MARGIN
    y0 = LABEL
    sheet.paste(fit(whole, (TILE, TILE)), (x0, y0))
    x1 = MARGIN + TILE + GAP
    sheet.paste(fit(cut, (TILE, TILE)), (x1, y0))
    x2 = MARGIN + (TILE + GAP) * 2
    render_tile = (TILE, int(TILE * 9 / 16))
    sheet.paste(fit(render, render_tile), (x2, y0 + (TILE - render_tile[1]) // 2))

    draw.text((x0, 12), "PRD v1.0 — whole", fill=(235, 238, 244))
    draw.text((x1, 12), "PRD v1.0 — cut", fill=(235, 238, 244))
    draw.text((x2, 12), "BLENDER PREVIEW — reference-driven geometry and PBR", fill=(235, 238, 244))

    sheet.save(MODEL_ROOT / "apple_comparison.png", quality=95)


if __name__ == "__main__":
    main()
