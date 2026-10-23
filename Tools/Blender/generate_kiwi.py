"""Build the FruitWave kiwi asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_kiwi.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/kiwi/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin fuzzy brown
#6c3a10/#95551c/#bf7d32 with lit tips #dd9b45/#edba72; cut shows green
flesh #b59d2e/#bcbe31/#d1d855, a brown edge and a pale core. No green
family in the whole palette, so no leaf.

Deliverables (in FruitWaveApp/Resources/Models/Kiwi/): kiwi.blend,
kiwi_reference.png/cut, kiwi_reference.json, kiwi_skin_basecolor.png,
kiwi_flesh_basecolor.png, kiwi_whole.usdz, kiwi_sliced.usdz,
kiwi_preview.png, kiwi.json.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "kiwi"
TITLE = "Kiwi"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.52, 0.30, 0.12)   # mid #6c3a10/#95551c family
FLESH_BASE = (0.75, 0.78, 0.28)  # green #b59d2e/#bcbe31 family
CENTER = (0.92, 0.92, 0.82)      # pale core
SEED = (0.05, 0.05, 0.05)

SEED_COUNT = 26
SEED_RING = 0.36


def classify_skin(r: float, g: float, b: float) -> str:
    """Fuzzy brown skin; lit tips as mark."""
    if r > 0.25 and g > 0.10 and b < 0.25 and r > g > b:
        return "skin"
    if r > 0.70 and g > 0.60 and b > 0.30:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.40 and g > 0.40 and b < 0.40 and abs(r - g) < 0.25 and max(r, g, b) < 0.96


PROFILE = [
    (0.00, -0.74),
    (0.20, -0.75),
    (0.40, -0.75),
    (0.56, -0.70),
    (0.66, -0.58),
    (0.71, -0.40),
    (0.72, -0.18),
    (0.69, 0.04),
    (0.62, 0.24),
    (0.51, 0.42),
    (0.36, 0.56),
    (0.20, 0.65),
    (0.00, 0.68),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "KiwiSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "KiwiFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "KiwiSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "KiwiFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("KiwiSkin_PBR", skin_image, roughness=0.56, specular=0.16)
    flesh = common.image_material("KiwiFlesh_PBR", flesh_image, roughness=0.28, specular=0.65, planar_yz=True)
    center = common.solid_material("KiwiCenter_PBR", (*CENTER, 1), 0.30, specular=0.45)
    seed = common.solid_material("KiwiSeed_PBR", (*SEED, 1), 0.30, specular=0.25)
    stem_material = common.solid_material("KiwiStem_PBR", (0.42, 0.30, 0.12, 1), 0.55, specular=0.20)

    template = common.make_body_from_profile(
        "KiwiBodyTemplate", PROFILE, lobes=0.012, lobe_count=6, asymmetry=0.005, y_scale=1.0, z_scale=1.0
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
                            points=((0.0, 0.0, 0.0), (0.010, 0.0, 0.06), (0.014, 0.0, 0.12), (0.011, 0.0, 0.18)))
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
        # Cap slot carries the flesh texture; the pale core ellipse and the
        # seed ring sit OUTSIDE the half in front of it.
        core_obj = common.make_ellipsoid(
            f"{root.name}_core", center,
            location=(-sign * 0.006, 0.0, 0.0), scale=(0.020, 0.16, 0.16),
        )
        common.parent_keep_transform(core_obj, root)
        seeds = common.make_ellipsoid_ring(
            f"{root.name}_seeds", seed, SEED_COUNT, SEED_RING, sign, 0.008,
            scale=(0.010, 0.022, 0.055), phase=0.3,
        )
        common.parent_keep_transform(seeds, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square fuzzy kiwi with stem nub, black background",
            "skin brown #6c3a10/#95551c/#bf7d32 with lit tips #dd9b45/#edba72",
            "no leaf in the whole palette",
            "cut face: green flesh #b59d2e/#bcbe31/#d1d855 with pale core",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "seed ring count (26) and radius from typical kiwi structure; the black seed dots are below the measured palette resolution",
            "fuzz from roughness 0.56 (no geometry fuzz)",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with kiwi-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "kiwi-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.75},
        "massKilograms": 0.10,
        "juiceColorSRGB": [0.60, 0.85, 0.25],
        "materialNotes": {
            "skin": "roughness 0.56, specular IOR level 0.16 (fuzzy)",
            "flesh": "roughness 0.28, specular IOR level 0.65 (wet cut face)",
            "center": "pale #ebebd1",
            "seeds": "near-black, roughness 0.30",
        },
        "cutFaceStructure": {"seedsPerHalf": SEED_COUNT, "coreScale": [0.020, 0.16, 0.16]},
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
