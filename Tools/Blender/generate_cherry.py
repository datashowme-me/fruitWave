"""Build the FruitWave cherry asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_cherry.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/cherry/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin #b2060c/#df0a0e with deep
shadows #64070b (matte, bright only 0.8%); cut shows flesh #c51319/#ed3e3e
and a tan pit #cb9659. The whole silhouette is near-square with a dimple at
the stem end; a single thin stem with no leaf (no green family in palette).

Deliverables (in FruitWaveApp/Resources/Models/Cherry/): cherry.blend,
cherry_reference.png/cut, cherry_reference.json, cherry_skin_basecolor.png,
cherry_flesh_basecolor.png, cherry_whole.usdz, cherry_sliced.usdz,
cherry_preview.png, cherry.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common, stone

FRUIT = "cherry"
TITLE = "Cherry"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.70, 0.10, 0.05)   # mid #b2060c family
FLESH_BASE = (0.78, 0.15, 0.12)  # mid #c51319 family
PIT = (0.80, 0.59, 0.35)         # #cb9659 family
CAVITY = (0.38, 0.08, 0.10)


def classify_skin(r: float, g: float, b: float) -> str:
    """Dark-red skin family, lit red zone as mark."""
    if r > 0.35 and g < 0.35 and b < 0.30 and r > g > b and (r - b) > 0.25:
        return "skin"
    if r > 0.55 and g > 0.15 and b > 0.12 and r > b and g > b:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.5 and g < 0.45 and r - b > 0.25 and max(r, g, b) < 0.96


PROFILE = [
    (0.00, -0.58),
    (0.20, -0.58),
    (0.38, -0.57),
    (0.50, -0.52),
    (0.55, -0.42),
    (0.56, -0.25),
    (0.55, -0.05),
    (0.52, 0.15),
    (0.47, 0.33),
    (0.39, 0.46),
    (0.28, 0.54),
    (0.22, 0.52),
    (0.14, 0.50),
    (0.00, 0.47),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "CherrySkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "CherryFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "CherrySkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "CherryFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("CherrySkin_PBR", skin_image, roughness=0.34, specular=0.35)
    flesh = common.image_material("CherryFlesh_PBR", flesh_image, roughness=0.26, specular=0.80, planar_yz=True)
    pit = common.solid_material("CherryPit_PBR", (*PIT, 1), 0.35, specular=0.25)
    cavity = common.solid_material("CherryCavity_PBR", (*CAVITY, 1), 0.40, specular=0.10)
    stem_material = common.solid_material("CherryStem_PBR", (0.35, 0.28, 0.10, 1), 0.55, specular=0.20)

    template = common.make_body_from_profile(
        "CherryBodyTemplate", PROFILE, lobes=0.010, lobe_count=5, asymmetry=0.004, y_scale=1.0, z_scale=1.0
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
    stem = common.make_stem(f"{FRUIT}_stem", stem_material, location=(0.0, 0.0, 0.52),
                            points=((0.0, 0.0, 0.0), (0.012, 0.0, 0.10), (0.018, 0.0, 0.22), (0.015, 0.0, 0.34)))
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

    stone.make_stone_cut_face(right_root, 1.0, pit, None, pit_scale=(0.09, 0.11, 0.12))
    stone.make_stone_cut_face(left_root, -1.0, None, cavity, pit_scale=(0.09, 0.11, 0.12))

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square cherry with stem-end dimple, black background",
            "skin families #b2060c, #df0a0e with deep shadows #64070b; matte (bright 0.8%)",
            "no green family: single thin stem, no leaf",
            "cut face: red flesh #c51319/#ed3e3e with tan pit #cb9659",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "stem length and dimple depth from silhouette",
            "pit stays in one half (right) with a cavity impression on the other",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with cherry-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "cherry-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.60},
        "massKilograms": 0.02,
        "juiceColorSRGB": [0.85, 0.15, 0.15],
        "materialNotes": {
            "skin": "roughness 0.34, specular IOR level 0.35 (matte red peel)",
            "flesh": "roughness 0.26, specular IOR level 0.80 (wet cut face)",
            "pit": "#cb9659, roughness 0.35",
            "stem": "#594719, roughness 0.55",
        },
        "cutFaceStructure": {
            "pitHalf": "right",
            "pitScale": [0.09, 0.11, 0.12],
            "cavityHalf": "left",
        },
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
