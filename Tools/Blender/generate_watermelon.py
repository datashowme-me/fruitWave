"""Build the FruitWave watermelon asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_watermelon.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/watermelon/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): striped skin — dark greens
#133e0e/#215c14 and light stripes #78a529/#b4d154; cut shows red flesh
#e2362d, a pale rind ring #c1c370 and dark seeds. The stripe families both
classify as skin so the per-row remap preserves the banding.

Deliverables (in FruitWaveApp/Resources/Models/Watermelon/):
watermelon.blend, watermelon_reference.png/cut, watermelon_reference.json,
watermelon_skin_basecolor.png, watermelon_flesh_basecolor.png,
watermelon_whole.usdz, watermelon_sliced.usdz, watermelon_preview.png,
watermelon.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "watermelon"
TITLE = "Watermelon"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.18, 0.34, 0.12)   # mid #215c14/#133e0e family
FLESH_BASE = (0.82, 0.16, 0.12)  # red #e2362d family
RIND = (0.78, 0.80, 0.45)        # pale #c1c370 family
SEED = (0.05, 0.05, 0.05)


def classify_skin(r: float, g: float, b: float) -> str:
    """Both dark and light green stripe families count as skin; the remap
    keeps the horizontal banding they carry."""
    if g > r and g > b and g < 0.75 and b < 0.55:
        return "skin"
    if g > 0.70 and r > 0.45 and g > r and b < 0.60:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.6 and g < 0.45 and b < 0.45 and (r - g) > 0.45 and max(r, g, b) < 0.97


PROFILE = [
    (0.00, -1.18),
    (0.30, -1.20),
    (0.62, -1.22),
    (0.90, -1.16),
    (1.08, -1.02),
    (1.18, -0.80),
    (1.22, -0.52),
    (1.22, -0.20),
    (1.19, 0.12),
    (1.10, 0.42),
    (0.95, 0.68),
    (0.74, 0.90),
    (0.48, 1.06),
    (0.22, 1.15),
    (0.00, 1.18),
]

SEED_COUNT = 8
SEED_RING = 0.42


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "WatermelonSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "WatermelonFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "WatermelonSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "WatermelonFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("WatermelonSkin_PBR", skin_image, roughness=0.34, specular=0.28)
    flesh = common.image_material("WatermelonFlesh_PBR", flesh_image, roughness=0.24, specular=0.80, planar_yz=True)
    rind = common.solid_material("WatermelonRind_PBR", (*RIND, 1), 0.36, specular=0.30)
    seed = common.solid_material("WatermelonSeed_PBR", (*SEED, 1), 0.30, specular=0.25)

    template = common.make_body_from_profile(
        "WatermelonBodyTemplate", PROFILE, lobes=0.010, lobe_count=6, asymmetry=0.005, y_scale=1.0, z_scale=1.0
    )
    template.data.materials.append(skin)
    template.data.materials.append(rind)

    whole_root = bpy.data.objects.new(f"{FRUIT}_whole", None)
    bpy.context.collection.objects.link(whole_root)
    whole = template.copy()
    whole.data = template.data.copy()
    whole.name = f"{FRUIT}_skin"
    bpy.context.collection.objects.link(whole)
    common.parent_keep_transform(whole, whole_root)
    stem = common.make_stem(f"{FRUIT}_stem", common.solid_material("WatermelonStem_PBR", (0.35, 0.25, 0.10, 1), 0.55, specular=0.20),
                            location=(0.0, 0.0, 1.10),
                            points=((0.0, 0.0, 0.0), (0.020, 0.0, 0.10), (0.030, 0.0, 0.22), (0.022, 0.0, 0.32)))
    stem.scale = (1.0, 1.0, 0.7)
    common.parent_keep_transform(stem, whole_root)

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = common.apply_boolean_half(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = common.apply_boolean_half(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        # The boolean cap slot carries the rind; the red flesh disk overlays
        # it OUTSIDE the half (x = -sign * overlay_x), then the rind ring
        # sits just in front of the flesh at the rim.
        disk = common.make_annulus(f"{root.name}_flesh_disk", flesh, 0.0, 1.16, sign, 0.004)
        common.parent_keep_transform(disk, root)
        ring = common.make_annulus(f"{root.name}_rind_ring", rind, 1.08, 1.16, sign, 0.008)
        common.parent_keep_transform(ring, root)
        seeds = common.make_ellipsoid_ring(
            f"{root.name}_seeds", seed, SEED_COUNT, SEED_RING, sign, 0.010,
            scale=(0.012, 0.030, 0.065), phase=0.35,
        )
        common.parent_keep_transform(seeds, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square watermelon, black background",
            "striped skin: dark #133e0e/#215c14 and light #78a529/#b4d154 bands",
            "small stem, no leaf",
            "cut face: red flesh #e2362d, pale rind ring #c1c370, dark seeds",
        ],
        inferred=[
            "unseen back mirrored from the front half; stripe banding from the photo rows",
            "seed count (8 per half) and ring radius from typical watermelon structure",
            "rind thickness from the pale ring share of the cut palette",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with dual-green-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "watermelon-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 1.22},
        "massKilograms": 5.0,
        "juiceColorSRGB": [0.90, 0.25, 0.20],
        "materialNotes": {
            "skin": "roughness 0.34, specular IOR level 0.28 (striped rind)",
            "flesh": "roughness 0.24, specular IOR level 0.80 (wet cut face)",
            "rind": "#c7cc73, roughness 0.36",
            "seeds": "near-black, roughness 0.30",
        },
        "cutFaceStructure": {"seedsPerHalf": SEED_COUNT, "rindRing": [1.08, 1.16]},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
