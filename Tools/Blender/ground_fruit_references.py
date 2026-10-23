#!/usr/bin/env python3
"""Ground every PRD v1.0 fruit reference pair before any modeling.

Per fruit: verify both PNGs against the PRD manifest hashes, copy pristine
copies into the fruit's model directory, and measure a pixel profile
(silhouette bbox, quantized palette, interior dark/bright clusters) written
as <fruit>_grounding.json. The generating environment has no vision model,
so these measurements are the observed-facts basis for the per-fruit
reference manifests.

Run from the repository root:
  python3 Tools/Blender/ground_fruit_references.py
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PRD_MANIFEST = ROOT / "ArtSource" / "PRD-v1.0" / "manifest.json"
MODELS = ROOT / "FruitWaveApp" / "Resources" / "Models"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def profile(path: Path) -> dict:
    """Pixel profile: silhouette + palette + bright/dark clusters."""
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    rgba = image.getdata()
    min_x = min_y = 10 ** 9
    max_x = max_y = -1
    opaque = 0
    # Downsampled luminance map for cluster stats.
    small = image.convert("RGB").resize((96, 96))
    lum_rows = []
    for py in range(96):
        row = []
        for px in range(96):
            r, g, b = small.getpixel((px, py))
            row.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
        lum_rows.append(row)
    for y in range(height):
        for x in range(width):
            _, _, _, a = rgba[y * width + x]
            if a > 0.8:
                opaque += 1
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
    if opaque == 0:
        return {"opaque_pct": 0.0}
    bbox = {
        "left_pct": round(100 * min_x / width, 1),
        "right_pct": round(100 * max_x / width, 1),
        "top_pct": round(100 * min_y / height, 1),
        "bottom_pct": round(100 * max_y / height, 1),
        "width_pct": round(100 * (max_x - min_x) / width, 1),
        "height_pct": round(100 * (max_y - min_y) / height, 1),
        "aspect_w_h": round((max_x - min_x) / max(1, (max_y - min_y)), 3),
    }
    quantized = small.quantize(colors=8, method=Image.MEDIANCUT)
    palette = sorted(quantized.getcolors(96 * 96), reverse=True)
    colors = []
    for count, index in palette:
        r, g, b = quantized.getpalette()[3 * index:3 * index + 3]
        colors.append({"pct": round(100 * count / (96 * 96), 1), "rgb": [r, g, b]})
    # Corner colors approximate the background family.
    corners = [small.getpixel(p) for p in ((2, 2), (93, 2), (2, 93), (93, 93))]
    background = tuple(round(sum(channel[i] for channel in corners) / 4) for i in range(3))
    # Bright clusters (specular) and dark clusters (seeds/pits) inside the
    # opaque bbox, measured on the downsampled map.
    bright = dark = 0
    for py in range(96):
        for px in range(96):
            x_frac = px / 96
            y_frac = py / 96
            if not (bbox["left_pct"] / 100 <= x_frac <= bbox["right_pct"] / 100):
                continue
            if not (bbox["top_pct"] / 100 <= y_frac <= bbox["bottom_pct"] / 100):
                continue
            lum = lum_rows[py][px]
            if lum > 215:
                bright += 1
            elif lum < 45:
                dark += 1
    inside = 96 * 96
    return {
        "opaque_pct": round(100 * opaque / (width * height), 2),
        "bbox": bbox,
        "palette": colors,
        "background_rgb": list(background),
        "bright_pct_of_bbox": round(100 * bright / inside, 2),
        "dark_pct_of_bbox": round(100 * dark / inside, 2),
    }


def main() -> None:
    if not PRD_MANIFEST.is_file():
        raise FileNotFoundError(f"PRD reference index is missing: {PRD_MANIFEST}")
    prd = json.loads(PRD_MANIFEST.read_text())
    report = {}
    for entry in sorted(prd["assets"], key=lambda a: (a["fruit"], a["role"])):
        fruit = entry["fruit"]
        role = entry["role"]
        source = ROOT / entry["path"]
        digest = sha256(source)
        verified = digest == entry["sha256"]
        title = fruit.title().replace("_", "")
        out_dir = MODELS / title
        out_dir.mkdir(parents=True, exist_ok=True)
        suffix = "" if role == "whole" else "_cut"
        pristine = out_dir / f"{fruit}_reference{suffix}.png"
        shutil.copyfile(source, pristine)
        report.setdefault(fruit, {})[role] = {
            "sha256_verified": verified,
            "source": entry["path"],
            "pristine_copy": str(pristine.relative_to(ROOT)),
            "profile": profile(source),
        }
        print(f"{fruit:14s} {role:5s} hash={'OK' if verified else 'MISMATCH'} {pristine.name}")
    (ROOT / "Tools" / "Blender" / "grounding_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    )
    print("grounding_report.json written")


if __name__ == "__main__":
    main()
