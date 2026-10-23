"""Build the FruitWave pineapple asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_pineapple.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/pineapple/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): skin brown-orange
#d09927/#b1791e/#923e0b/#af5b14 with lit #e2c042 and a green crown
#36390d; cut shows yellow flesh #f9d746/#dfb32b, pale #fbe66e, brown rind
#4d320a/#c87518 and a greenish #6e6b15 edge. The whole is matte
(bright 0.53%).

Deliverables (in FruitWaveApp/Resources/Models/Pineapple/):
pineapple.blend, pineapple_reference.png/cut, pineapple_reference.json,
pineapple_skin_basecolor.png, pineapple_flesh_basecolor.png,
pineapple_whole.usdz, pineapple_sliced.usdz, pineapple_preview.png,
pineapple.json.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "pineapple"
TITLE = "Pineapple"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.68, 0.42, 0.12)   # mid #d09927/#af5b14 family
FLESH_BASE = (0.94, 0.80, 0.30)  # mid #f9d746/#dfb32b family
CORE = (0.97, 0.90, 0.55)        # pale core #fbe66e family
RIND = (0.70, 0.42, 0.10)        # brown rind ring #c87518 family
CROWN = (0.22, 0.26, 0.06)       # green crown #36390d family

CROWN_LEAVES = 12


def classify_skin(r: float, g: float, b: float) -> str:
    """Brown-orange peel families (the diamond pattern rides along); the
    green crown rows classify as other and get refilled from skin columns."""
    if r > 0.45 and g > 0.15 and b < 0.30 and r > g > b and (r - b) > 0.30:
        return "skin"
    if r > 0.9 and g > 0.75 and b > 0.35:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.8 and g > 0.6 and b > 0.15 and r > b + 0.4 and max(r, g, b) < 0.99


PROFILE = [
    (0.00, -0.76),
    (0.30, -0.77),
    (0.52, -0.76),
    (0.68, -0.72),
    (0.74, -0.62),
    (0.76, -0.46),
    (0.77, -0.20),
    (0.77, 0.10),
    (0.76, 0.36),
    (0.72, 0.54),
    (0.62, 0.66),
    (0.44, 0.73),
    (0.00, 0.75),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "PineappleSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "PineappleFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "PineappleSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "PineappleFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("PineappleSkin_PBR", skin_image, roughness=0.55, specular=0.16)
    flesh = common.image_material("PineappleFlesh_PBR", flesh_image, roughness=0.30, specular=0.65, planar_yz=True)
    core = common.solid_material("PineappleCore_PBR", (*CORE, 1), 0.30, specular=0.50)
    rind = common.solid_material("PineappleRind_PBR", (*RIND, 1), 0.40, specular=0.20)
    crown_material = common.solid_material("PineappleCrown_PBR", (*CROWN, 1), 0.55, specular=0.20)

    template = common.make_body_from_profile(
        "PineappleBodyTemplate", PROFILE, lobes=0.015, lobe_count=8, asymmetry=0.006, y_scale=1.0, z_scale=1.0
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
    # Stiff crown leaves radiating from the top, tips splayed outward.
    for index in range(CROWN_LEAVES):
        leaf = common.make_leaf(
            f"{FRUIT}_crown_{index}", crown_material,
            location=(0.0, 0.0, 0.70),
            rotation=(0.0, -math.pi / 2.0 + 0.10, index * 2.0 * math.pi / CROWN_LEAVES),
            length=0.85, width=0.12,
        )
        common.parent_keep_transform(leaf, whole_root)

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = common.apply_boolean_half(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = common.apply_boolean_half(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        # Cap slot carries the flesh texture; rind ring and pale core disk
        # sit OUTSIDE the half in front of it.
        core_disk = common.make_annulus(f"{root.name}_core", core, 0.0, 0.16, sign, 0.004)
        common.parent_keep_transform(core_disk, root)
        rind_ring = common.make_annulus(f"{root.name}_rind", rind, 0.62, 0.72, sign, 0.008)
        common.parent_keep_transform(rind_ring, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "barrel-shaped pineapple, black background",
            "skin brown-orange #d09927/#b1791e/#923e0b/#af5b14, matte (bright 0.53%)",
            "green crown #36390d (9.3% of the whole palette)",
            "cut face: yellow flesh #f9d746/#dfb32b, pale #fbe66e core, brown rind #4d320a/#c87518",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "crown leaf count (12) and length from the green share of the whole palette",
            "diamond pattern rides along on the skin texture remap; no geometry scales",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with pineapple-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "pineapple-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.78},
        "massKilograms": 1.2,
        "juiceColorSRGB": [0.95, 0.85, 0.45],
        "materialNotes": {
            "skin": "roughness 0.55, specular IOR level 0.16 (matte peel)",
            "flesh": "roughness 0.30, specular IOR level 0.65 (wet cut face)",
            "core": "pale #fbe66e, roughness 0.30",
            "rind": "#b26b17 ring, roughness 0.40",
            "crown": "green #385015, roughness 0.55",
        },
        "cutFaceStructure": {"coreRadius": 0.16, "rindRing": [0.62, 0.72]},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
