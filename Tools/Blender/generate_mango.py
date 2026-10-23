"""Build the FruitWave mango asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_mango.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/mango/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin orange #e9651d/#dda824 with
lit #fad948, dark #8b690d and a small red blush #881513; cut shows orange
flesh #f2ab1b/#e66a18/#fac727/#fbd84d with a flat dark pit #755109 and a
near-black edge #380b06.

Deliverables (in FruitWaveApp/Resources/Models/Mango/): mango.blend,
mango_reference.png/cut, mango_reference.json, mango_skin_basecolor.png,
mango_flesh_basecolor.png, mango_whole.usdz, mango_sliced.usdz,
mango_preview.png, mango.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "mango"
TITLE = "Mango"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.90, 0.58, 0.18)   # mid #e9651d/#dda824 family
FLESH_BASE = (0.95, 0.72, 0.18)  # mid #f2ab1b/#fac727 family
PIT = (0.46, 0.32, 0.06)         # flat pit #755109


def classify_skin(r: float, g: float, b: float) -> str:
    """Orange peel families plus the small red blush."""
    if r > 0.6 and g > 0.15 and b < 0.5 and r > g > b and (r - b) > 0.4:
        return "skin"
    if r > 0.45 and g < 0.25 and b < 0.2 and (r - g) > 0.3:
        return "skin"  # red blush
    if r > 0.9 and g > 0.85 and b > 0.35:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.85 and g > 0.4 and b < 0.5 and r > g > b and max(r, g, b) < 0.99


PROFILE = [
    (0.00, -0.74),
    (0.22, -0.74),
    (0.40, -0.72),
    (0.52, -0.64),
    (0.60, -0.48),
    (0.63, -0.28),
    (0.63, -0.08),
    (0.60, 0.12),
    (0.54, 0.30),
    (0.45, 0.46),
    (0.34, 0.58),
    (0.20, 0.66),
    (0.00, 0.70),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "MangoSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "MangoFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "MangoSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "MangoFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("MangoSkin_PBR", skin_image, roughness=0.35, specular=0.30)
    flesh = common.image_material("MangoFlesh_PBR", flesh_image, roughness=0.28, specular=0.70, planar_yz=True)
    pit = common.solid_material("MangoPit_PBR", (*PIT, 1), 0.45, specular=0.20)
    stem_material = common.solid_material("MangoStem_PBR", (0.35, 0.25, 0.10, 1), 0.55, specular=0.20)

    template = common.make_body_from_profile(
        "MangoBodyTemplate", PROFILE, lobes=0.010, lobe_count=6, asymmetry=0.012, y_scale=1.0, z_scale=1.0
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
                            points=((0.0, 0.0, 0.0), (0.010, 0.0, 0.06), (0.013, 0.0, 0.12), (0.010, 0.0, 0.18)))
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
        # Cap slot carries the flesh texture; the flat pit oval sits OUTSIDE
        # the half in front of it (the blade slices through the pit, so both
        # faces show it).
        pit_obj = common.make_ellipsoid(
            f"{root.name}_pit", pit,
            location=(-sign * 0.007, 0.0, 0.0), scale=(0.022, 0.20, 0.30),
        )
        common.parent_keep_transform(pit_obj, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "oval mango with stem nub, black background",
            "skin orange #e9651d/#dda824, lit #fad948, dark #8b690d, small red blush #881513",
            "cut face: orange flesh #f2ab1b/#e66a18/#fac727/#fbd84d with flat dark pit #755109",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "the blade slices through the pit: both halves show the flat pit oval",
            "pit oval size from the 10% #755109 share of the cut palette",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with mango-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "mango-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.66},
        "massKilograms": 0.30,
        "juiceColorSRGB": [1.0, 0.75, 0.25],
        "materialNotes": {
            "skin": "roughness 0.35, specular IOR level 0.30 (waxy peel)",
            "flesh": "roughness 0.28, specular IOR level 0.70 (wet cut face)",
            "pit": "flat #755109 oval, roughness 0.45",
        },
        "cutFaceStructure": {"pit": "flat oval on both halves", "pitScale": [0.022, 0.20, 0.30]},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
