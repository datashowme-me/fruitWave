"""Build the FruitWave persimmon asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_persimmon.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/persimmon/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): skin bright orange
#ef4905/#b13c10/#d97f1c with lit #d7a12f/#e2c46d and a dark calyx family
#6f1403 plus 1.2% green (the four calyx lobes); cut shows orange flesh
#fa600d/#ed9222/#f2a732/#edbe5b. The whole is matte (bright 1.27%).

Deliverables (in FruitWaveApp/Resources/Models/Persimmon/):
persimmon.blend, persimmon_reference.png/cut, persimmon_reference.json,
persimmon_skin_basecolor.png, persimmon_flesh_basecolor.png,
persimmon_whole.usdz, persimmon_sliced.usdz, persimmon_preview.png,
persimmon.json.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "persimmon"
TITLE = "Persimmon"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.85, 0.36, 0.08)   # mid #ef4905/#d97f1c family
FLESH_BASE = (0.93, 0.63, 0.20)  # mid #ed9222/#f2a732 family
CALYX = (0.25, 0.28, 0.08)       # dark olive calyx lobes


def classify_skin(r: float, g: float, b: float) -> str:
    """Bright orange peel; lit cream zones as mark."""
    if r > 0.6 and g > 0.15 and b < 0.35 and r > g > b and (r - b) > 0.5:
        return "skin"
    if r > 0.85 and g > 0.75 and b > 0.35:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.8 and g > 0.3 and b < 0.45 and r > g > b and max(r, g, b) < 0.99


PROFILE = [
    (0.00, -0.58),
    (0.28, -0.58),
    (0.52, -0.56),
    (0.66, -0.46),
    (0.72, -0.30),
    (0.74, -0.10),
    (0.73, 0.10),
    (0.68, 0.28),
    (0.56, 0.42),
    (0.40, 0.50),
    (0.22, 0.54),
    (0.00, 0.55),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "PersimmonSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "PersimmonFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "PersimmonSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "PersimmonFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("PersimmonSkin_PBR", skin_image, roughness=0.50, specular=0.20)
    flesh = common.image_material("PersimmonFlesh_PBR", flesh_image, roughness=0.30, specular=0.65, planar_yz=True)
    calyx_material = common.solid_material("PersimmonCalyx_PBR", (*CALYX, 1), 0.55, specular=0.15)

    template = common.make_body_from_profile(
        "PersimmonBodyTemplate", PROFILE, lobes=0.010, lobe_count=6, asymmetry=0.006, y_scale=1.0, z_scale=1.0
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
    # Four calyx lobes around the flattened top, tips curling outward.
    for index in range(4):
        lobe = common.make_leaf(
            f"{FRUIT}_calyx_{index}", calyx_material,
            location=(0.0, 0.0, 0.50),
            rotation=(0.35, 0.0, index * math.pi / 2.0),
            length=0.30, width=0.12,
        )
        common.parent_keep_transform(lobe, whole_root)

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = common.apply_boolean_half(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = common.apply_boolean_half(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "squat persimmon, black background",
            "skin bright orange #ef4905/#b13c10/#d97f1c, matte (bright 1.27%)",
            "1.2% green palette share: the four calyx lobes at the top",
            "cut face: uniform orange flesh #fa600d/#ed9222/#f2a732/#edbe5b, no pit",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "calyx lobe count (4) from persimmon structure; color from the dark #6f1403/green shares",
            "uniform flesh: the cut palette shows no seed or core family",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with persimmon-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "persimmon-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.74},
        "massKilograms": 0.25,
        "juiceColorSRGB": [1.0, 0.55, 0.15],
        "materialNotes": {
            "skin": "roughness 0.50, specular IOR level 0.20 (matte peel)",
            "flesh": "roughness 0.30, specular IOR level 0.65 (wet cut face)",
            "calyx": "dark olive #40501a, roughness 0.55",
        },
        "cutFaceStructure": {"flesh": "uniform"},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
