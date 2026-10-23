"""Build the FruitWave pomegranate asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_pomegranate.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/pomegranate/{whole,cut}.png. Measured
palette (Tools/Blender/grounding_report.json): skin deep red
#94050d/#6b0408 with lit #d84d41/#c20814 and a dark crown family; cut
shows packed red seeds #ab0f18/#c83e40/#d4101b/#e27a6e on pale pith
#fbc5ad. The whole is matte (bright 0.51%).

Deliverables (in FruitWaveApp/Resources/Models/Pomegranate/):
pomegranate.blend, pomegranate_reference.png/cut, pomegranate_reference.json,
pomegranate_skin_basecolor.png, pomegranate_flesh_basecolor.png,
pomegranate_whole.usdz, pomegranate_sliced.usdz, pomegranate_preview.png,
pomegranate.json.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "pomegranate"
TITLE = "Pomegranate"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.62, 0.12, 0.10)   # mid #94050d/#d84d41 family
PITH_BASE = (0.94, 0.78, 0.65)   # pale pith #fbc5ad
SEED = (0.78, 0.20, 0.16)        # mid #ab0f18/#d4101b family
CROWN = (0.32, 0.07, 0.05)       # dark calyx crown

SEED_RINGS = [(0.14, 8), (0.28, 12), (0.42, 16), (0.55, 20), (0.66, 24)]
SEED_SCALE = (0.030, 0.040, 0.075)
CROWN_NUBS = 6


def classify_skin(r: float, g: float, b: float) -> str:
    """Deep red peel families; lit salmon zones as mark."""
    if r > 0.3 and g < 0.35 and b < 0.30 and r > g > b and (r - b) > 0.25:
        return "skin"
    if r > 0.85 and g > 0.5 and b > 0.45:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.85 and g > 0.6 and b > 0.5 and r > g > b


PROFILE = [
    (0.00, -0.80),
    (0.24, -0.80),
    (0.46, -0.79),
    (0.64, -0.74),
    (0.74, -0.62),
    (0.79, -0.44),
    (0.80, -0.22),
    (0.79, 0.02),
    (0.74, 0.24),
    (0.65, 0.42),
    (0.50, 0.56),
    (0.32, 0.66),
    (0.14, 0.72),
    (0.00, 0.73),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "PomegranateSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "PomegranateFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "PomegranateSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "PomegranateFleshBaseColor", is_flesh, PITH_BASE)

    skin = common.image_material("PomegranateSkin_PBR", skin_image, roughness=0.45, specular=0.25)
    pith = common.image_material("PomegranatePith_PBR", flesh_image, roughness=0.35, specular=0.50, planar_yz=True)
    seed = common.solid_material("PomegranateSeed_PBR", (*SEED, 1), 0.25, specular=0.60)
    crown = common.solid_material("PomegranateCrown_PBR", (*CROWN, 1), 0.50, specular=0.15)

    template = common.make_body_from_profile(
        "PomegranateBodyTemplate", PROFILE, lobes=0.010, lobe_count=6, asymmetry=0.006, y_scale=1.0, z_scale=1.0
    )
    template.data.materials.append(skin)
    template.data.materials.append(pith)

    whole_root = bpy.data.objects.new(f"{FRUIT}_whole", None)
    bpy.context.collection.objects.link(whole_root)
    whole = template.copy()
    whole.data = template.data.copy()
    whole.name = f"{FRUIT}_skin"
    bpy.context.collection.objects.link(whole)
    common.parent_keep_transform(whole, whole_root)
    # Calyx crown: six small nubs around the top, tilted outward.
    tilt = 0.45
    for index in range(CROWN_NUBS):
        theta = 2.0 * math.pi * index / CROWN_NUBS
        ry = math.asin(math.sin(tilt) * math.cos(theta))
        rx = math.acos(math.cos(tilt) / math.cos(ry))
        nub = common.make_ellipsoid(
            f"{FRUIT}_crown_{index}", crown,
            location=(0.12 * math.cos(theta), 0.12 * math.sin(theta), 0.66),
            scale=(0.03, 0.03, 0.10),
        )
        nub.rotation_euler = (rx, ry, 0.0)
        common.parent_keep_transform(nub, whole_root)

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = common.apply_boolean_half(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = common.apply_boolean_half(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        # Cap slot carries the pale pith; the packed red seeds sit OUTSIDE
        # the half in front of it, arranged in concentric rings.
        for ring_index, (radius, count) in enumerate(SEED_RINGS):
            ring = common.make_ellipsoid_ring(
                f"{root.name}_seeds_{ring_index}", seed, count, radius, sign, 0.006,
                scale=SEED_SCALE, phase=0.5 * ring_index,
            )
            common.parent_keep_transform(ring, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square pomegranate with calyx crown, black background",
            "skin deep red #94050d/#6b0408 with lit #d84d41/#c20814, matte (bright 0.51%)",
            "cut face: packed red seeds #ab0f18/#c83e40/#d4101b/#e27a6e on pale pith #fbc5ad",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "seed ring counts (8/12/16/20/24) and the crown nub count from the seed and dark-crown palette shares",
            "pith is the flesh (slot 1) of the cut face; seeds are overlay geometry",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with pomegranate-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "pomegranate-pith centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.80},
        "massKilograms": 0.25,
        "juiceColorSRGB": [0.85, 0.15, 0.20],
        "materialNotes": {
            "skin": "roughness 0.45, specular IOR level 0.25 (leathery peel)",
            "pith": "roughness 0.35, specular IOR level 0.50 (wet cut face)",
            "seeds": "glossy #c73229 arils, roughness 0.25, specular IOR level 0.60",
            "crown": "dark #520b08 nubs, roughness 0.50",
        },
        "cutFaceStructure": {"seedRings": SEED_RINGS, "seedScale": list(SEED_SCALE)},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
