"""Build the FruitWave cantaloupe asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_cantaloupe.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/cantaloupe/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): skin is netted tan
#a98242/#ca954e/#deaf69 with bright net ridges #f5d191; cut shows orange
flesh #e8a846/#f68d24/#f0c277. The seed cavity reads in the pale
center of the cut face.

Deliverables (in FruitWaveApp/Resources/Models/Cantaloupe/):
cantaloupe.blend, cantaloupe_reference.png/cut, cantaloupe_reference.json,
cantaloupe_skin_basecolor.png, cantaloupe_flesh_basecolor.png,
cantaloupe_whole.usdz, cantaloupe_sliced.usdz, cantaloupe_preview.png,
cantaloupe.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "cantaloupe"
TITLE = "Cantaloupe"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.68, 0.51, 0.27)   # mid #a98242/#ca954e family
FLESH_BASE = (0.90, 0.62, 0.24)  # mid #e8a846/#f68d24 family
CAVITY = (0.95, 0.82, 0.55)      # pale seed-cavity center
SEED = (0.88, 0.78, 0.48)


def classify_skin(r: float, g: float, b: float) -> str:
    """Netted tan skin; bright net ridges as mark."""
    if r > 0.50 and g > 0.35 and b < 0.55 and r > g > b and (r - b) > 0.15:
        return "skin"
    if r > 0.85 and g > 0.72 and b > 0.45:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.5 and g > 0.3 and b < 0.60 and r > g > b and max(r, g, b) < 0.97


PROFILE = [
    (0.00, -1.04),
    (0.26, -1.06),
    (0.54, -1.08),
    (0.78, -1.04),
    (0.94, -0.92),
    (1.03, -0.72),
    (1.06, -0.46),
    (1.05, -0.16),
    (0.98, 0.14),
    (0.86, 0.42),
    (0.68, 0.66),
    (0.46, 0.84),
    (0.24, 0.96),
    (0.00, 1.00),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "CantaloupeSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "CantaloupeFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "CantaloupeSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "CantaloupeFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("CantaloupeSkin_PBR", skin_image, roughness=0.46, specular=0.20)
    flesh = common.image_material("CantaloupeFlesh_PBR", flesh_image, roughness=0.26, specular=0.75, planar_yz=True)
    cavity = common.solid_material("CantaloupeCavity_PBR", (*CAVITY, 1), 0.34, specular=0.30)
    seed = common.solid_material("CantaloupeSeed_PBR", (*SEED, 1), 0.35, specular=0.25)

    template = common.make_body_from_profile(
        "CantaloupeBodyTemplate", PROFILE, lobes=0.020, lobe_count=10, asymmetry=0.008, y_scale=1.0, z_scale=1.0
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
    stem = common.make_stem(f"{FRUIT}_stem", common.solid_material("CantaloupeStem_PBR", (0.30, 0.24, 0.10, 1), 0.55, specular=0.20),
                            location=(0.0, 0.0, 0.94),
                            points=((0.0, 0.0, 0.0), (0.020, 0.0, 0.10), (0.030, 0.0, 0.20), (0.022, 0.0, 0.30)))
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
        disk = common.make_cut_disk(f"{root.name}_flesh_disk", flesh, 0.98, sign)
        common.parent_keep_transform(disk, root)
        cavity_disk = common.make_annulus(f"{root.name}_cavity", cavity, 0.0, 0.26, sign, 0.004)
        common.parent_keep_transform(cavity_disk, root)
        seeds = common.make_ellipsoid_ring(
            f"{root.name}_cavity_seeds", seed, 8, 0.15, sign, 0.006,
            scale=(0.010, 0.022, 0.050), phase=0.5,
        )
        common.parent_keep_transform(seeds, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square cantaloupe with stem, black background",
            "netted tan skin #a98242/#ca954e/#deaf69 with bright ridges #f5d191",
            "cut face: orange flesh #e8a846/#f68d24/#f0c277",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "netting from the bright ridge family; lobe depth from the palette contrast",
            "seed cavity size (0.26) and 8 seeds from typical cantaloupe structure",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with cantaloupe-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "cantaloupe-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 1.05},
        "massKilograms": 1.2,
        "juiceColorSRGB": [1.0, 0.65, 0.25],
        "materialNotes": {
            "skin": "roughness 0.46, specular IOR level 0.20 (netted rind)",
            "flesh": "roughness 0.26, specular IOR level 0.75 (wet cut face)",
            "cavity": "pale #f2d18c seed bed",
            "seeds": "#e0c77a, roughness 0.35",
        },
        "cutFaceStructure": {"cavityRadius": 0.26, "seedsPerHalf": 8},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
