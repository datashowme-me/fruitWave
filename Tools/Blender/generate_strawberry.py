"""Build the FruitWave strawberry asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_strawberry.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/strawberry/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): skin red
#cc462a/#e50403/#eb1611 with pale seed dots #b8b45a/#9d7f2e; cut shows red
flesh #ec1f18/#f95339 with a pale core #fba083 and dark seeds #805513.
Heart-shaped berry with a leafy calyx crown.

Deliverables (in FruitWaveApp/Resources/Models/Strawberry/):
strawberry.blend, strawberry_reference.png/cut, strawberry_reference.json,
strawberry_skin_basecolor.png, strawberry_flesh_basecolor.png,
strawberry_whole.usdz, strawberry_sliced.usdz, strawberry_preview.png,
strawberry.json.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "strawberry"
TITLE = "Strawberry"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.76, 0.12, 0.10)   # mid #cc462a/#e50403 family
FLESH_BASE = (0.88, 0.20, 0.16)  # mid #ec1f18/#f95339 family
CORE = (0.96, 0.72, 0.58)        # pale #fba083 family
SEED = (0.72, 0.68, 0.30)        # #b8b45a family
CALYX = (0.30, 0.42, 0.14)


def classify_skin(r: float, g: float, b: float) -> str:
    """Red skin family; pale seed dots count as mark so they survive."""
    if r > 0.45 and g < 0.30 and b < 0.25 and r > g > b and (r - b) > 0.25:
        return "skin"
    if r > 0.50 and g > 0.45 and b < 0.50 and r > b:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.6 and g < 0.55 and b < 0.45 and r > g > b and max(r, g, b) < 0.97


# Heart-shaped berry: wide shoulders near the calyx, rounded tapering tip.
PROFILE = [
    (0.00, -0.78),
    (0.14, -0.80),
    (0.28, -0.82),
    (0.42, -0.80),
    (0.52, -0.72),
    (0.58, -0.60),
    (0.61, -0.45),
    (0.62, -0.28),
    (0.60, -0.10),
    (0.55, 0.08),
    (0.46, 0.24),
    (0.34, 0.37),
    (0.20, 0.46),
    (0.08, 0.50),
    (0.00, 0.52),
]

SURFACE_SEED_COUNT = 28


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "StrawberrySkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "StrawberryFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "StrawberrySkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "StrawberryFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("StrawberrySkin_PBR", skin_image, roughness=0.30, specular=0.35)
    flesh = common.image_material("StrawberryFlesh_PBR", flesh_image, roughness=0.26, specular=0.75, planar_yz=True)
    core = common.solid_material("StrawberryCore_PBR", (*CORE, 1), 0.32, specular=0.50)
    seed = common.solid_material("StrawberrySeed_PBR", (*SEED, 1), 0.35, specular=0.20)
    calyx = common.solid_material("StrawberryCalyx_PBR", (*CALYX, 1), 0.45, specular=0.15)

    template = common.make_body_from_profile(
        "StrawberryBodyTemplate", PROFILE, lobes=0.020, lobe_count=7, asymmetry=0.006, y_scale=1.0, z_scale=1.0
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

    # Surface seed dots in a gentle double spiral, half-embedded in the skin.
    for index in range(SURFACE_SEED_COUNT):
        t = index / SURFACE_SEED_COUNT
        height = -0.72 + 1.16 * t
        radius = 0.35 + 0.22 * t
        theta = 2.4 * math.pi * t
        seed_obj = common.make_ellipsoid(
            f"{FRUIT}_surface_seed_{index}", seed,
            location=(radius * math.cos(theta) * 0.55, radius * math.sin(theta) * 0.55, height),
            scale=(0.008, 0.022, 0.035),
        )
        common.parent_keep_transform(seed_obj, whole_root)

    # Five calyx leaves around the crown.
    for index in range(5):
        theta = 2.0 * math.pi * index / 5
        leaf = common.make_leaf(
            f"{FRUIT}_calyx_leaf_{index}", calyx,
            location=(0.14 * math.cos(theta), 0.14 * math.sin(theta), 0.52),
            rotation=(0.30, 0.0, -theta), length=0.34, width=0.12,
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
        disk = common.make_cut_disk(f"{root.name}_flesh_disk", flesh, 0.60, sign)
        common.parent_keep_transform(disk, root)
        core_disk = common.make_annulus(f"{root.name}_core", core, 0.0, 0.18, sign, 0.004)
        common.parent_keep_transform(core_disk, root)
        for index, (dy, dz) in enumerate(((-0.30, 0.10), (0.05, 0.32), (0.25, -0.18))):
            seed_obj = common.make_ellipsoid(
                f"{root.name}_cut_seed_{index}", seed,
                location=(-sign * 0.008, dy, dz), scale=(0.008, 0.024, 0.038),
            )
            common.parent_keep_transform(seed_obj, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "heart-shaped berry, near-square bbox, black background",
            "skin red #cc462a/#e50403/#eb1611 with pale seed dots #b8b45a/#9d7f2e",
            "cut face: red flesh #ec1f18/#f95339, pale core #fba083, dark seeds #805513",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "seed count (28) and spiral placement from typical strawberry surface density",
            "calyx leaf count (5) from typical strawberry crowns",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with strawberry-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "strawberry-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.70},
        "massKilograms": 0.03,
        "juiceColorSRGB": [0.90, 0.20, 0.15],
        "materialNotes": {
            "skin": "roughness 0.30, specular IOR level 0.35",
            "flesh": "roughness 0.26, specular IOR level 0.75 (wet cut face)",
            "core": "#fba083 pale zone",
            "seeds": "#b8b45a, roughness 0.35",
            "calyx": "#4d6b24, roughness 0.45",
        },
        "cutFaceStructure": {"surfaceSeeds": SURFACE_SEED_COUNT, "coreRadius": 0.18},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
