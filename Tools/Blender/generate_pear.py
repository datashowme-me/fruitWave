"""Build the FruitWave pear asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_pear.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/pear/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin yellow-green
#bbb421/#ebec61/#717711/#90880f with deep #534d09; cut shows cream flesh
#f5e9ca/#e6d770/#f1e88b, skin #afab1d and a dark #61550f seed zone. No
distinct leaf-green family, so the stem carries no leaf.

Deliverables (in FruitWaveApp/Resources/Models/Pear/): pear.blend,
pear_reference.png/cut, pear_reference.json, pear_skin_basecolor.png,
pear_flesh_basecolor.png, pear_whole.usdz, pear_sliced.usdz,
pear_preview.png, pear.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "pear"
TITLE = "Pear"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.75, 0.74, 0.24)   # mid #bbb421/#ebec61 family
FLESH_BASE = (0.96, 0.91, 0.78)  # cream #f5e9ca family
CORE = (0.38, 0.33, 0.06)        # dark seed zone #61550f
CHAMBER = (0.90, 0.83, 0.62)     # darker cream around the core


def classify_skin(r: float, g: float, b: float) -> str:
    """Yellow-green peel families; lit cream zones as mark."""
    if r > 0.4 and g > 0.4 and b < 0.55 and abs(r - g) < 0.25 and r > b + 0.3:
        return "skin"
    if r > 0.85 and g > 0.8 and b > 0.3:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.85 and g > 0.75 and b > 0.35 and max(r, g, b) < 0.99


PROFILE = [
    (0.00, -0.98),
    (0.22, -0.99),
    (0.40, -0.96),
    (0.54, -0.88),
    (0.62, -0.72),
    (0.64, -0.50),
    (0.60, -0.28),
    (0.52, -0.10),
    (0.42, 0.08),
    (0.33, 0.24),
    (0.27, 0.38),
    (0.24, 0.48),
    (0.22, 0.58),
    (0.16, 0.66),
    (0.00, 0.70),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "PearSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "PearFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "PearSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "PearFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("PearSkin_PBR", skin_image, roughness=0.46, specular=0.28)
    flesh = common.image_material("PearFlesh_PBR", flesh_image, roughness=0.28, specular=0.70, planar_yz=True)
    core = common.solid_material("PearCore_PBR", (*CORE, 1), 0.35, specular=0.15)
    chamber = common.solid_material("PearChamber_PBR", (*CHAMBER, 1), 0.32, specular=0.45)
    stem_material = common.solid_material("PearStem_PBR", (0.35, 0.25, 0.10, 1), 0.55, specular=0.20)

    template = common.make_body_from_profile(
        "PearBodyTemplate", PROFILE, lobes=0.012, lobe_count=5, asymmetry=0.008, y_scale=1.0, z_scale=1.0
    )
    template.data.materials.append(skin)
    template.data.materials.append(flesh)

    whole_root = bpy.data.objects.new(f"{FRUIT}_whole", None)
    bpy.context.collection.objects.link(whole_root)
    whole = template.copy()
    whole.data = template.data.copy()
    whole.name = f"{FRUIT}_skin"
    bpy.context.collection.objects.link(whole)
    common.parent_keep_transform(whole, whole_root)
    stem = common.make_stem(f"{FRUIT}_stem", stem_material, location=(0.0, 0.0, 0.66),
                            points=((0.0, 0.0, 0.0), (0.012, 0.0, 0.08), (0.015, 0.0, 0.16), (0.011, 0.0, 0.24)))
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
        # Cap slot carries the flesh texture; the seed chamber ring and the
        # dark core sit OUTSIDE the half in front of it.
        chamber_ring = common.make_annulus(f"{root.name}_chamber", chamber, 0.10, 0.24, sign, 0.004)
        common.parent_keep_transform(chamber_ring, root)
        core_obj = common.make_ellipsoid(
            f"{root.name}_core", core,
            location=(-sign * 0.006, 0.0, 0.0), scale=(0.020, 0.16, 0.11),
        )
        common.parent_keep_transform(core_obj, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square pear, black background",
            "skin yellow-green #bbb421/#ebec61 with deep #717711/#90880f/#534d09",
            "no distinct leaf-green family: stem carries no leaf",
            "cut face: cream flesh #f5e9ca/#e6d770/#f1e88b with dark #61550f seed zone",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "seed chamber ring and dark core from the 6.2% #61550f share of the cut palette",
            "speckled lenticels are below palette resolution and come from the skin texture",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with pear-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "pear-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.66},
        "massKilograms": 0.18,
        "juiceColorSRGB": [0.90, 0.88, 0.50],
        "materialNotes": {
            "skin": "roughness 0.46, specular IOR level 0.28 (matte peel)",
            "flesh": "roughness 0.28, specular IOR level 0.70 (wet cut face)",
            "core": "#61550f, roughness 0.35",
            "chamber": "darker cream #e6d4a0, roughness 0.32",
        },
        "cutFaceStructure": {"chamberRing": [0.10, 0.24], "coreScale": [0.020, 0.16, 0.11]},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
