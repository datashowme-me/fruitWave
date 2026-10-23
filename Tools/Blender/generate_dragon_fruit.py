"""Build the FruitWave dragon fruit asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_dragon_fruit.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/dragon_fruit/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): skin magenta
#ef255b/#9d0220/#92242d with green scale tips #cbb155 and brown flap
shadows #bb6f53; cut shows white flesh #d5c0ac (the largest cut family)
with a magenta skin rim. The tiny black seeds are below the measured
palette resolution.

Deliverables (in FruitWaveApp/Resources/Models/DragonFruit/):
dragon_fruit.blend, dragon_fruit_reference.png/cut, dragon_fruit_reference.json,
dragon_fruit_skin_basecolor.png, dragon_fruit_flesh_basecolor.png,
dragon_fruit_whole.usdz, dragon_fruit_sliced.usdz, dragon_fruit_preview.png,
dragon_fruit.json.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "dragon_fruit"
TITLE = "DragonFruit"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.78, 0.18, 0.30)   # mid #ef255b/#9d0220 family
FLESH_BASE = (0.85, 0.78, 0.70)  # white flesh #d5c0ac family
SCALE = (0.58, 0.70, 0.25)       # green scale flaps #cbb155 family
SEED = (0.04, 0.03, 0.03)        # near-black seeds

FLAP_ROWS = (-0.50, -0.25, 0.0, 0.25, 0.50)
SEED_RINGS = [(0.12, 10), (0.24, 12), (0.36, 14), (0.48, 16)]


def classify_skin(r: float, g: float, b: float) -> str:
    """Magenta peel (b > g); green scale tips as mark."""
    if r > 0.5 and b > g and r > b + 0.15:
        return "skin"
    if r > 0.7 and g > 0.55 and b > 0.25:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.75 and g > 0.65 and b > 0.55 and max(r, g, b) - min(r, g, b) < 0.25


def surface_radius(z: float) -> float:
    """Rough radius of the egg profile at height z (for flap bases)."""
    return max(0.16, 0.62 * math.sqrt(max(0.02, 1.0 - (z / 0.75) ** 2)))


PROFILE = [
    (0.00, -0.72),
    (0.20, -0.72),
    (0.40, -0.71),
    (0.54, -0.64),
    (0.62, -0.50),
    (0.64, -0.30),
    (0.63, -0.10),
    (0.58, 0.10),
    (0.50, 0.28),
    (0.40, 0.44),
    (0.28, 0.56),
    (0.16, 0.64),
    (0.00, 0.68),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "DragonFruitSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "DragonFruitFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "DragonFruitSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "DragonFruitFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("DragonFruitSkin_PBR", skin_image, roughness=0.35, specular=0.40)
    flesh = common.image_material("DragonFruitFlesh_PBR", flesh_image, roughness=0.30, specular=0.60, planar_yz=True)
    scale_material = common.solid_material("DragonFruitScale_PBR", (*SCALE, 1), 0.45, specular=0.30)
    seed = common.solid_material("DragonFruitSeed_PBR", (*SEED, 1), 0.30, specular=0.25)

    template = common.make_body_from_profile(
        "DragonFruitBodyTemplate", PROFILE, lobes=0.014, lobe_count=6, asymmetry=0.008, y_scale=1.0, z_scale=1.0
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
    # Scale flaps: four columns around the body, five rows up the side,
    # each flap radiating outward with its tip tilted up.
    for row_index, z in enumerate(FLAP_ROWS):
        radius = surface_radius(z)
        for column in range(4):
            theta = column * math.pi / 2.0 + (0.35 if row_index % 2 else 0.0)
            flap = common.make_leaf(
                f"{FRUIT}_flap_{row_index}_{column}", scale_material,
                location=(radius * math.cos(theta), radius * math.sin(theta), z),
                rotation=(0.0, -0.35, theta),
                length=0.30, width=0.16,
            )
            common.parent_keep_transform(flap, whole_root)

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = common.apply_boolean_half(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = common.apply_boolean_half(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        # Cap slot carries the white flesh; tiny black seeds scattered in
        # concentric rings across it.
        for ring_index, (radius, count) in enumerate(SEED_RINGS):
            ring = common.make_ellipsoid_ring(
                f"{root.name}_seeds_{ring_index}", seed, count, radius, sign, 0.005,
                scale=(0.006, 0.006, 0.012), phase=0.31 * ring_index,
            )
            common.parent_keep_transform(ring, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "egg-shaped dragon fruit with scale flaps, black background",
            "skin magenta #ef255b/#9d0220/#92242d, green scale tips #cbb155, brown flap shadows #bb6f53",
            "cut face: white flesh #d5c0ac (largest cut family) with magenta skin rim",
            "the tiny black seeds are below the measured palette resolution",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "flap layout (4 columns x 5 rows) from the green/brown palette shares",
            "seed ring counts (10/12/14/16) from dragon fruit structure; not measurable in the photo",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with dragon-fruit-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "dragon-fruit-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.66},
        "massKilograms": 0.30,
        "juiceColorSRGB": [0.95, 0.90, 0.85],
        "materialNotes": {
            "skin": "roughness 0.35, specular IOR level 0.40 (waxy peel)",
            "flesh": "roughness 0.30, specular IOR level 0.60 (wet cut face)",
            "scales": "green #93b240, roughness 0.45",
            "seeds": "near-black, roughness 0.30",
        },
        "cutFaceStructure": {"seedRings": SEED_RINGS, "seedScale": [0.006, 0.006, 0.012]},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
