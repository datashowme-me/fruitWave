"""Build the FruitWave grape asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_grape.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/grape/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin purple #4b1b47/#7f2a73 with
lighter bloom #845c7d; cut shows purple flesh #7d1c53/#8d4e72 with pale
seed dots #d2ca7c. A single bare berry, no stem.

Deliverables (in FruitWaveApp/Resources/Models/Grape/): grape.blend,
grape_reference.png/cut, grape_reference.json, grape_skin_basecolor.png,
grape_flesh_basecolor.png, grape_whole.usdz, grape_sliced.usdz,
grape_preview.png, grape.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "grape"
TITLE = "Grape"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.42, 0.20, 0.40)   # mid #4b1b47/#7f2a73 family
FLESH_BASE = (0.52, 0.26, 0.38)  # mid #7d1c53/#8d4e72 family
SEED = (0.80, 0.76, 0.45)        # pale #d2ca7c family


def classify_skin(r: float, g: float, b: float) -> str:
    """Purple skin with lighter bloom as mark."""
    if r < 0.60 and b > r and b > 0.16 and g < 0.55:
        return "skin"
    if r > 0.45 and b > r and b > 0.35:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.3 and b > r and g < 0.72 and max(r, g, b) < 0.95


PROFILE = [
    (0.00, -0.62),
    (0.20, -0.63),
    (0.40, -0.63),
    (0.54, -0.57),
    (0.60, -0.46),
    (0.61, -0.30),
    (0.59, -0.12),
    (0.54, 0.06),
    (0.46, 0.22),
    (0.34, 0.35),
    (0.20, 0.45),
    (0.07, 0.50),
    (0.00, 0.52),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "GrapeSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "GrapeFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "GrapeSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "GrapeFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("GrapeSkin_PBR", skin_image, roughness=0.30, specular=0.30)
    flesh = common.image_material("GrapeFlesh_PBR", flesh_image, roughness=0.26, specular=0.75, planar_yz=True)
    seed = common.solid_material("GrapeSeed_PBR", (*SEED, 1), 0.35, specular=0.25)

    template = common.make_body_from_profile(
        "GrapeBodyTemplate", PROFILE, lobes=0.008, lobe_count=5, asymmetry=0.004, y_scale=1.0, z_scale=1.0
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

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = common.apply_boolean_half(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = common.apply_boolean_half(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        disk = common.make_cut_disk(f"{root.name}_flesh_disk", flesh, 0.58, sign)
        common.parent_keep_transform(disk, root)
        for index, (dy, dz) in enumerate(((-0.14, 0.12), (0.12, -0.16))):
            seed_obj = common.make_ellipsoid(
                f"{root.name}_seed_{index}", seed,
                location=(-sign * 0.008, dy, dz), scale=(0.015, 0.05, 0.09),
            )
            common.parent_keep_transform(seed_obj, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square bare grape berry, black background",
            "skin purple #4b1b47/#7f2a73 with bloom #845c7d (thin translucent bloom)",
            "no stem or leaf in the reference",
            "cut face: purple flesh #7d1c53/#8d4e72 with pale seed dots #d2ca7c",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "two seeds per half from the pale dot share of the cut palette",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with grape-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "grape-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.62},
        "massKilograms": 0.01,
        "juiceColorSRGB": [0.55, 0.25, 0.55],
        "materialNotes": {
            "skin": "roughness 0.30, specular IOR level 0.30 (thin bloom)",
            "flesh": "roughness 0.26, specular IOR level 0.75 (wet cut face)",
            "seeds": "#ccc275, roughness 0.35",
        },
        "cutFaceStructure": {"seedsPerHalf": 2},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
