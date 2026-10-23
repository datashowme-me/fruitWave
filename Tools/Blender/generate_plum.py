"""Build the FruitWave plum asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_plum.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/plum/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin deep purple #794b7c/#661f4a
with dusty bloom #9c9085; cut shows yellow-orange flesh #be8a47/#ecbe53
and a dark pit. The whole silhouette is near-square with a stem-end dip.

Deliverables (in FruitWaveApp/Resources/Models/Plum/): plum.blend,
plum_reference.png/cut, plum_reference.json, plum_skin_basecolor.png,
plum_flesh_basecolor.png, plum_whole.usdz, plum_sliced.usdz,
plum_preview.png, plum.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common, stone

FRUIT = "plum"
TITLE = "Plum"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.44, 0.22, 0.40)   # mid #794b7c/#661f4a family
FLESH_BASE = (0.92, 0.70, 0.28)  # mid #ecbe53/#be8a47 family
PIT = (0.25, 0.10, 0.15)
CAVITY = (0.32, 0.12, 0.20)


def classify_skin(r: float, g: float, b: float) -> str:
    """Deep purple skin, dusty bloom as mark."""
    if r > 0.15 and g < 0.45 and b > r and b > 0.18 and (b - g) > 0.08:
        return "skin"
    if r > 0.45 and g > 0.45 and b > 0.45:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.5 and g > 0.35 and b < 0.55 and r > g > b and max(r, g, b) < 0.97


PROFILE = [
    (0.00, -0.78),
    (0.18, -0.79),
    (0.38, -0.80),
    (0.58, -0.78),
    (0.72, -0.70),
    (0.80, -0.56),
    (0.82, -0.38),
    (0.80, -0.16),
    (0.74, 0.06),
    (0.64, 0.26),
    (0.50, 0.44),
    (0.34, 0.56),
    (0.18, 0.63),
    (0.00, 0.64),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "PlumSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "PlumFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "PlumSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "PlumFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("PlumSkin_PBR", skin_image, roughness=0.42, specular=0.22)
    flesh = common.image_material("PlumFlesh_PBR", flesh_image, roughness=0.26, specular=0.80, planar_yz=True)
    pit = common.solid_material("PlumPit_PBR", (*PIT, 1), 0.32, specular=0.25)
    cavity = common.solid_material("PlumCavity_PBR", (*CAVITY, 1), 0.38, specular=0.10)
    stem_material = common.solid_material("PlumStem_PBR", (0.32, 0.22, 0.10, 1), 0.55, specular=0.20)

    template = common.make_body_from_profile(
        "PlumBodyTemplate", PROFILE, lobes=0.012, lobe_count=5, asymmetry=0.005, y_scale=1.0, z_scale=1.0
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
    stem = common.make_stem(f"{FRUIT}_stem", stem_material, location=(0.0, 0.0, 0.60),
                            points=((0.0, 0.0, 0.0), (0.012, 0.0, 0.08), (0.017, 0.0, 0.16), (0.014, 0.0, 0.26)))
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

    stone.make_stone_cut_face(right_root, 1.0, pit, None, pit_scale=(0.10, 0.12, 0.14))
    stone.make_stone_cut_face(left_root, -1.0, None, cavity, pit_scale=(0.10, 0.12, 0.14))

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square plum with stem-end dip, black background",
            "skin deep purple #794b7c/#661f4a with dusty bloom #9c9085 (matte)",
            "no green family: short stem, no leaf",
            "cut face: yellow-orange flesh #be8a47/#ecbe53/#fcd45d, dark pit",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "bloom strength from the 10% #9c9085 palette share",
            "pit stays in one half (right) with a cavity impression on the other",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with plum-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "plum-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.82},
        "massKilograms": 0.08,
        "juiceColorSRGB": [0.75, 0.45, 0.20],
        "materialNotes": {
            "skin": "roughness 0.42, specular IOR level 0.22 (dusty bloom)",
            "flesh": "roughness 0.26, specular IOR level 0.80 (wet cut face)",
            "pit": "#401a26, roughness 0.32",
            "stem": "#523810, roughness 0.55",
        },
        "cutFaceStructure": {
            "pitHalf": "right",
            "pitScale": [0.10, 0.12, 0.14],
            "cavityHalf": "left",
        },
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
