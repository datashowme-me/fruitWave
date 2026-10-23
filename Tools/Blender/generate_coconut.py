"""Build the FruitWave coconut asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_coconut.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/coconut/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin is dry brown husk
#b06937/#8f4a21/#dd9959 with deep shadows #5d240b; cut shows white meat
#e9e0d8, a brown shell ring #c39a77/#783615 and a dark hollow center.
The whole is a bare sphere with no stem (the three eye dots are below the
measured palette resolution and omitted).

Deliverables (in FruitWaveApp/Resources/Models/Coconut/): coconut.blend,
coconut_reference.png/cut, coconut_reference.json,
coconut_skin_basecolor.png, coconut_flesh_basecolor.png,
coconut_whole.usdz, coconut_sliced.usdz, coconut_preview.png,
coconut.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "coconut"
TITLE = "Coconut"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.65, 0.38, 0.18)   # mid #b06937/#8f4a21 family
FLESH_BASE = (0.90, 0.87, 0.84)  # white meat #e9e0d8 family
SHELL = (0.50, 0.24, 0.10)       # brown shell ring
HOLLOW = (0.05, 0.04, 0.03)


def classify_skin(r: float, g: float, b: float) -> str:
    """Dry brown husk; lit husk fibers as mark."""
    if r > 0.35 and g > 0.15 and b < 0.40 and r > g > b and (r - b) > 0.20:
        return "skin"
    if r > 0.70 and g > 0.50 and b > 0.25:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.80 and g > 0.75 and b > 0.70 and (max(r, g, b) - min(r, g, b)) < 0.20


PROFILE = [
    (0.00, -0.88),
    (0.22, -0.90),
    (0.46, -0.90),
    (0.66, -0.84),
    (0.78, -0.72),
    (0.84, -0.54),
    (0.85, -0.30),
    (0.83, -0.06),
    (0.77, 0.18),
    (0.66, 0.40),
    (0.51, 0.58),
    (0.32, 0.72),
    (0.14, 0.80),
    (0.00, 0.82),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "CoconutSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "CoconutFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "CoconutSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "CoconutFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("CoconutSkin_PBR", skin_image, roughness=0.62, specular=0.12)
    flesh = common.image_material("CoconutFlesh_PBR", flesh_image, roughness=0.30, specular=0.55, planar_yz=True)
    shell = common.solid_material("CoconutShell_PBR", (*SHELL, 1), 0.40, specular=0.25)
    hollow = common.solid_material("CoconutHollow_PBR", (*HOLLOW, 1), 0.60, specular=0.05)

    template = common.make_body_from_profile(
        "CoconutBodyTemplate", PROFILE, lobes=0.006, lobe_count=6, asymmetry=0.004, y_scale=1.0, z_scale=1.0
    )
    template.data.materials.append(skin)
    template.data.materials.append(shell)

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
        # Cap slot carries the shell; the white meat ring overlays it
        # outside the half, then the dark hollow center on top.
        meat = common.make_annulus(f"{root.name}_meat_ring", flesh, 0.30, 0.74, sign, 0.004)
        common.parent_keep_transform(meat, root)
        hollow_disk = common.make_annulus(f"{root.name}_hollow", hollow, 0.0, 0.30, sign, 0.008)
        common.parent_keep_transform(hollow_disk, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square bare coconut, black background",
            "dry brown husk #b06937/#8f4a21/#dd9959 with deep shadows #5d240b",
            "no stem in the reference",
            "cut face: white meat #e9e0d8, brown shell ring #c39a77/#783615, dark hollow",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "meat thickness (0.30-0.74) from the white share of the cut palette",
            "the three germination eyes are below palette resolution and omitted",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with coconut-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "coconut-meat centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.86},
        "massKilograms": 0.6,
        "juiceColorSRGB": [0.95, 0.92, 0.88],
        "materialNotes": {
            "skin": "roughness 0.62, specular IOR level 0.12 (dry fibrous husk)",
            "flesh": "roughness 0.30, specular IOR level 0.55 (meat)",
            "shell": "#7f3d1a, roughness 0.40",
            "hollow": "near-black, roughness 0.60",
        },
        "cutFaceStructure": {"meatRing": [0.30, 0.74], "hollowRadius": 0.30},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
