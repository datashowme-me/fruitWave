"""Build the FruitWave blueberry asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_blueberry.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/blueberry/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): skin is dusty blue
#243467/#3f588b/#5f819f with pale bloom #93b3c6 (the 12.8% share reads as
the bloom powder on the berry); cut shows pale lavender flesh
#ccb2cd/#6b6e8c. No pit, no stem (the reference is a bare berry).

Deliverables (in FruitWaveApp/Resources/Models/Blueberry/): blueberry.blend,
blueberry_reference.png/cut, blueberry_reference.json,
blueberry_skin_basecolor.png, blueberry_flesh_basecolor.png,
blueberry_whole.usdz, blueberry_sliced.usdz, blueberry_preview.png,
blueberry.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "blueberry"
TITLE = "Blueberry"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.25, 0.33, 0.55)   # mid #243467/#3f588b family
FLESH_BASE = (0.78, 0.72, 0.80)  # pale lavender #ccb2cd family


def classify_skin(r: float, g: float, b: float) -> str:
    """Dusty blue skin; the pale bloom powder counts as mark."""
    if b > r and b > 0.22 and g < 0.72 and (b - g) > 0.10:
        return "skin"
    if r > 0.40 and g > 0.50 and b > 0.55 and b > r:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.45 and g > 0.50 and b > 0.45 and (b - r) < 0.35 and max(r, g, b) < 0.95


PROFILE = [
    (0.00, -0.52),
    (0.18, -0.53),
    (0.36, -0.53),
    (0.48, -0.48),
    (0.53, -0.38),
    (0.54, -0.22),
    (0.52, -0.06),
    (0.48, 0.10),
    (0.40, 0.24),
    (0.30, 0.35),
    (0.18, 0.43),
    (0.06, 0.46),
    (0.00, 0.47),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "BlueberrySkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "BlueberryFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "BlueberrySkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "BlueberryFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("BlueberrySkin_PBR", skin_image, roughness=0.50, specular=0.18)
    flesh = common.image_material("BlueberryFlesh_PBR", flesh_image, roughness=0.30, specular=0.60, planar_yz=True)

    template = common.make_body_from_profile(
        "BlueberryBodyTemplate", PROFILE, lobes=0.008, lobe_count=5, asymmetry=0.004, y_scale=1.0, z_scale=1.0
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
        disk = common.make_cut_disk(f"{root.name}_flesh_disk", flesh, 0.50, sign)
        common.parent_keep_transform(disk, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square bare berry, black background",
            "skin dusty blue #243467/#3f588b/#5f819f with pale bloom #93b3c6",
            "no stem or leaf in the reference",
            "cut face: pale lavender flesh #ccb2cd/#6b6e8c, no pit",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "bloom powder from the 12.8% pale palette share",
            "no crown/calyx: not visible in the pixel profile",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with blueberry-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "blueberry-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.55},
        "massKilograms": 0.01,
        "juiceColorSRGB": [0.45, 0.30, 0.60],
        "materialNotes": {
            "skin": "roughness 0.50, specular IOR level 0.18 (dusty bloom)",
            "flesh": "roughness 0.30, specular IOR level 0.60 (wet cut face)",
        },
        "cutFaceStructure": {"pit": "none"},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
