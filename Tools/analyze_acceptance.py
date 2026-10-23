#!/usr/bin/env python3
"""Pixel analysis of FruitWave acceptance evidence (no-vision proxy, NOT a
substitute for human review).

For each fruit, extract classify_skin/is_flesh from its Blender generator
(via AST, so the analysis always matches the generator's own families) and
apply them to four images:
  device-whole      Docs/Evidence/<fruit>-acceptance/evidence_<fruit>_whole.png
  device-sliced     ... evidence_<fruit>_sliced.png
  blender-preview   Models/<Title>/<fruit>_preview.png
  prd-reference     ArtSource/PRD-v1.0/FruitReferences/<fruit>/whole.png

Writes pixel-analysis.json (one NDJSON object per image, same schema as the
apple/orange/lemon archives) plus a one-line summary to stdout for the
M1-Verification.md table.

Usage: analyze_acceptance.py <fruit> [<fruit> ...]
"""
from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GENERATORS = ROOT / "Tools" / "Blender"
MODELS = ROOT / "FruitWaveApp" / "Resources" / "Models"
PRD = ROOT / "ArtSource" / "PRD-v1.0" / "FruitReferences"
EVIDENCE = ROOT / "Docs" / "Evidence"


def extract_functions(fruit: str) -> dict:
    """AST-extract classify_skin/is_flesh and color bases from the generator."""
    src = ast.parse((GENERATORS / f"generate_{fruit}.py").read_text())
    out: dict = {}
    for node in ast.walk(src):
        if isinstance(node, ast.FunctionDef) and node.name == "classify_skin" and "classify_skin" not in out:
            out[node.name] = ast.unparse(node)
        elif isinstance(node, ast.FunctionDef) and node.name in ("is_flesh", "is_cream", "is_pith") \
                and "is_flesh" not in out and len(node.args.args) == 4:
            out["is_flesh"] = ast.unparse(node)
        elif isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id in ("SKIN_BASE", "FLESH_BASE", "PITH_BASE") \
                        and t.id not in out:
                    out[t.id] = ast.literal_eval(node.value)
    missing = {"classify_skin", "is_flesh"} - out.keys()
    if missing:
        raise SystemExit(f"{fruit}: generator missing {sorted(missing)}")
    namespace: dict = {}
    for fn in ("classify_skin", "is_flesh"):
        exec(out[fn], namespace)
    flesh_fn = next(v for k, v in namespace.items()
                    if k in ("is_flesh", "is_cream", "is_pith") and callable(v))
    # Device-lab and PRD lighting are brighter than the generators' ceiling
    # (`max < 0.9x`) allows; relax alpha + brightness ceilings, keep the hue
    # family tests. Same treatment the archived apple analysis used.
    relaxed_src = re.sub(r"\ba > 0\.8\b", "a > 0.2", out["is_flesh"])
    relaxed_src = re.sub(r"max\(r, g, b\) < 0\.9\d*", "max(r, g, b) < 1.10", relaxed_src)
    relaxed_src = re.sub(r"\bmaximum < 0\.9\d*", "maximum < 1.10", relaxed_src)
    relaxed_ns: dict = {}
    exec(relaxed_src, relaxed_ns)
    flesh_relaxed = next(v for v in relaxed_ns.values() if callable(v))
    return {
        "classify_skin": namespace["classify_skin"],
        "is_flesh": flesh_relaxed,
        "flesh_base": out.get("FLESH_BASE") or out.get("PITH_BASE"),
    }


def analyze_image(image: np.ndarray, size: tuple[int, int], classify_skin, is_flesh) -> dict:
    """image: HxWx4 float array in 0..1 (sRGB); size = original W,H."""
    h, w = image.shape[:2]
    r, g, b, a = image[..., 0], image[..., 1], image[..., 2], image[..., 3]
    lum = 0.299 * r + 0.587 * g + 0.114 * b

    skin = np.zeros_like(lum, dtype=bool)
    for value in ("skin", "mark"):
        skin |= np.array([classify_skin(rr, gg, bb) == value
                          for rr, gg, bb in zip(r.ravel(), g.ravel(), b.ravel())],
                         dtype=bool).reshape(h, w)
    flesh = np.array([is_flesh(rr, gg, bb, aa) for rr, gg, bb, aa in
                      zip(r.ravel(), g.ravel(), b.ravel(), a.ravel())],
                     dtype=bool).reshape(h, w)

    sampled = h * w
    def stats(mask):
        if not mask.any():
            return 0.0, [0, 0, 0], [0.0, 0.0, 0.0, 0.0], 0.0
        ys, xs = np.nonzero(mask)
        mean = [round(float(v) * 255) for v in
                (r[mask].mean(), g[mask].mean(), b[mask].mean())]
        bbox = [round(float(xs.min()) / w * 100, 1), round(float(ys.min()) / h * 100, 1),
                round(float(xs.max()) / w * 100, 1), round(float(ys.max()) / h * 100, 1)]
        p95 = round(float(np.percentile(lum[mask], 95)) * 255, 1)
        return 100.0 * mask.sum() / sampled, mean, bbox, p95

    skin_pct, skin_mean, skin_bbox, skin_p95 = stats(skin)
    flesh_pct, flesh_mean, _, _ = stats(flesh)
    bright_skin = skin & (lum >= 235.0 / 255.0)
    return {
        "size": [size[0], size[1]], "sampled_pixels": sampled,
        "skin_pct": round(skin_pct, 2), "skin_mean_rgb": skin_mean,
        "skin_bbox_pct": skin_bbox, "skin_p95_lum": skin_p95,
        "flesh_pct": round(flesh_pct, 2), "flesh_mean_rgb": flesh_mean,
        "dark_background_pct": round(100.0 * (lum < 0.10).sum() / sampled, 2),
        "bright_flesh_pct_of_skin": round(100.0 * bright_skin.sum() / max(skin.sum(), 1), 2),
    }


def load_image(path: Path, stride: int) -> np.ndarray:
    img = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0
    return img[::stride, ::stride]
def run(fruit: str) -> str:
    """Analyze one fruit; writes pixel-analysis.json and returns its summary line."""
    title = "".join(w.capitalize() for w in fruit.split("_"))
    funcs = extract_functions(fruit)
    out_dir = EVIDENCE / f"{fruit}-acceptance"
    rows = []
    summary = {"fruit": fruit,
               "flesh_base_rgb": [int(v * 255) for v in (funcs["flesh_base"] or ())]}
    for key, path, stride in (
        ("device-whole", out_dir / f"evidence_{fruit}_whole.png", 2),
        ("device-sliced", out_dir / f"evidence_{fruit}_sliced.png", 2),
        ("blender-preview", MODELS / title / f"{fruit}_preview.png", 2),
        ("prd-reference", PRD / fruit / "whole.png", 2),
    ):
        if not path.exists():
            print(f"{fruit}: MISSING {path}", file=sys.stderr)
            continue
        with Image.open(path) as im:
            size = im.size
        row = analyze_image(load_image(path, stride), size, funcs["classify_skin"], funcs["is_flesh"])
        row["image"] = key
        rows.append(row)
        summary[key] = row
    (out_dir / "pixel-analysis.json").write_text(
        "\n".join(json.dumps(r) for r in rows) + "\n")
    return json.dumps(summary)


if __name__ == "__main__":
    for fruit in sys.argv[1:]:
        print(run(fruit))
