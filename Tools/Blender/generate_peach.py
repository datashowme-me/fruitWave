"""Build the FruitWave peach asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_peach.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/peach/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin is a blush gradient
#ee453f/#f2644c (red side) to #eec18a/#d28952 (yellow side); cut shows
yellow flesh #fada6c/#eaac4a with a red zone #ec5842 around the pit, pit
dark #280805. Fuzzy peach skin reads as matte with 2.9% bright.

Deliverables (in FruitWaveApp/Resources/Models/Peach/): peach.blend,
peach_reference.png/cut, peach_reference.json, peach_skin_basecolor.png,
peach_flesh_basecolor.png, peach_whole.usdz, peach_sliced.usdz,
peach_preview.png, peach.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common, stone

FRUIT = "peach"
TITLE = "Peach"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.75, 0.35, 0.25)   # mid blush #f2644c/#be462e family
FLESH_BASE = (0.93, 0.78, 0.35)  # mid #fada6c/#eaac4a family
RED_CENTER = (0.90, 0.32, 0.22)  # #ec5842 zone around the pit
PIT = (0.30, 0.08, 0.05)
CAVITY = (0.40, 0.16, 0.12)


def classify_skin(r: float, g: float, b: float) -> str:
    """Blush gradient: red and yellow skin families both count as skin."""
    if r > 0.45 and g > 0.10 and b < 0.60 and r > b and (r - g) < 0.55:
        return "skin"
    if r > 0.80 and g > 0.70 and b > 0.45:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.5 and g > 0.2 and r > b and g < 0.86 and max(r, g, b) < 0.97


PROFILE = [
    (0.00, -0.84),
    (0.20, -0.85),
    (0.42, -0.86),
    (0.64, -0.84),
    (0.80, -0.76),
    (0.88, -0.62),
    (0.91, -0.42),
    (0.90, -0.20),
    (0.85, 0.02),
    (0.76, 0.22),
    (0.63, 0.40),
    (0.48, 0.54),
    (0.30, 0.64),
    (0.12, 0.69),
    (0.00, 0.70),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "PeachSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "PeachFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "PeachSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "PeachFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("PeachSkin_PBR", skin_image, roughness=0.52, specular=0.18)
    flesh = common.image_material("PeachFlesh_PBR", flesh_image, roughness=0.30, specular=0.70, planar_yz=True)
    red_center = common.solid_material("PeachRedCenter_PBR", (*RED_CENTER, 1), 0.32, specular=0.60)
    pit = common.solid_material("PeachPit_PBR", (*PIT, 1), 0.35, specular=0.25)
    cavity = common.solid_material("PeachCavity_PBR", (*CAVITY, 1), 0.38, specular=0.12)
    stem_material = common.solid_material("PeachStem_PBR", (0.35, 0.25, 0.10, 1), 0.55, specular=0.20)

    template = common.make_body_from_profile(
        "PeachBodyTemplate", PROFILE, lobes=0.016, lobe_count=6, asymmetry=0.010, y_scale=1.0, z_scale=1.0
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
                            points=((0.0, 0.0, 0.0), (0.012, 0.0, 0.08), (0.017, 0.0, 0.16), (0.014, 0.0, 0.24)))
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

    stone.make_stone_cut_face(right_root, 1.0, pit, None, pit_scale=(0.09, 0.11, 0.13))
    stone.make_stone_cut_face(left_root, -1.0, None, cavity, pit_scale=(0.09, 0.11, 0.13))
    # The red zone around the pit on both faces, under the pit/cavity overlays.
    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        zone = common.make_annulus(f"{root.name}_red_zone", red_center, 0.0, 0.30, sign, 0.004)
        common.parent_keep_transform(zone, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square peach with stem-end dip, black background",
            "blush gradient skin: red #ee453f/#f2644c and yellow #eec18a/#d28952 families",
            "matte fuzzy peel (bright 2.9%), no leaf",
            "cut face: yellow flesh #fada6c/#eaac4a with red zone #ec5842 around the pit",
        ],
        inferred=[
            "unseen back mirrored from the front half; blush side placement from the photo rows",
            "peach crease not modelled (not measurable in the pixel profile)",
            "pit stays in one half (right) with a cavity impression on the other",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with wide blush-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "peach-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.90},
        "massKilograms": 0.15,
        "juiceColorSRGB": [1.0, 0.80, 0.40],
        "materialNotes": {
            "skin": "roughness 0.52, specular IOR level 0.18 (fuzzy matte peel)",
            "flesh": "roughness 0.30, specular IOR level 0.70 (wet cut face)",
            "redZone": "#ec5842 around pit",
            "pit": "#4d1408, roughness 0.35",
        },
        "cutFaceStructure": {
            "pitHalf": "right",
            "pitScale": [0.09, 0.11, 0.13],
            "cavityHalf": "left",
            "redZoneRadius": 0.30,
        },
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
