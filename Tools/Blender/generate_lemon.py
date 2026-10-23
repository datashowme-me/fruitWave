"""Build the FruitWave lemon asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_lemon.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/lemon/{whole,cut}.png. Pristine copies
live beside the deliverables as lemon_reference.png / lemon_reference_cut.png.
Measured palette (Tools/Blender/grounding_report.json): skin #d99408/#e8b614
family with lit zones #fcde12 and strong gloss #fcef5f (8.8% bright vs the
orange's 0.8% — the lemon peel is shinier); cut shows flesh #f1cd4b/#e9b61d
and pith #f7e6a4. No green family in the whole palette: a small stem nub,
no leaf.

Deliverables (in FruitWaveApp/Resources/Models/Lemon/): lemon.blend,
lemon_reference.png/cut, lemon_reference.json, lemon_skin_basecolor.png,
lemon_flesh_basecolor.png, lemon_whole.usdz, lemon_sliced.usdz,
lemon_preview.png, lemon.json.

The cut face uses the shared citrus machinery (fruitgen.citrus): pith ring
inside the peel, eight flesh wedges with thin pith walls, pith center, all
as flat overlay meshes on the boolean cap. No seeds (the reference shows
none).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import citrus, common

FRUIT = "lemon"
TITLE = "Lemon"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

# De-lit blend targets derived from the measured palettes.
SKIN_BASE = (0.87, 0.64, 0.06)   # mid lemon #deA310 family
FLESH_BASE = (0.93, 0.75, 0.16)  # bright flesh #edbf29 family
PITH = (0.97, 0.90, 0.64)        # #f7e6a4 family


def classify_skin(r: float, g: float, b: float) -> str:
    """Lemon families: saturated yellow skin, bright specular gloss mark."""
    if r > 0.55 and g > 0.42 and b < 0.30 and r > g > b and (r - b) > 0.35:
        return "skin"
    if r > 0.80 and g > 0.75 and b < 0.50 and r > g > b:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.55 and g > 0.42 and b < 0.60 and r > g > b and max(r, g, b) < 0.96


# The measured silhouette is near-square (bbox 98.6 x 98.2), so the
# elongation stays modest; the end nubs and tucked equator are lemon
# convention and marked inferred in the reference manifest.
PROFILE = [
    (0.00, -0.86),
    (0.07, -0.78),
    (0.16, -0.79),
    (0.34, -0.80),
    (0.55, -0.78),
    (0.72, -0.70),
    (0.83, -0.56),
    (0.89, -0.36),
    (0.90, -0.14),
    (0.86, 0.08),
    (0.78, 0.30),
    (0.64, 0.50),
    (0.46, 0.66),
    (0.26, 0.75),
    (0.10, 0.79),
    (0.00, 0.84),
]

SEGMENT_COUNT = 8
SEGMENT_GAP = 0.05           # radians of pith wall between wedges
WEDGE_INNER = 0.08
WEDGE_OUTER = 0.66
PITH_RING_INNER = 0.68
PITH_RING_OUTER = 0.80
OVERLAY_X = 0.006            # overlay meshes sit just outside the cap


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "LemonSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "LemonFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "LemonSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "LemonFleshBaseColor", is_flesh, FLESH_BASE)

    # The lemon peel is measurably glossier than the orange (8.8% bright).
    skin = common.image_material("LemonSkin_PBR", skin_image, roughness=0.22, specular=0.65)
    flesh = common.image_material("LemonFlesh_PBR", flesh_image, roughness=0.24, specular=0.85, planar_yz=True)
    pith = common.solid_material("LemonPith_PBR", (*PITH, 1), 0.38, specular=0.30)
    stem_material = common.solid_material("LemonStem_PBR", (0.42, 0.30, 0.12, 1), 0.60, specular=0.20)

    template = common.make_body_from_profile(
        "LemonBodyTemplate", PROFILE, lobes=0.020, lobe_count=6, asymmetry=0.006, y_scale=1.0, z_scale=1.0
    )
    template.data.materials.append(skin)
    # The boolean cap slot is the pith: wedges and rings overlay it, and the
    # sliver that remains reads as the pith/peel edge.
    template.data.materials.append(pith)

    whole_root = bpy.data.objects.new(f"{FRUIT}_whole", None)
    bpy.context.collection.objects.link(whole_root)
    whole = template.copy()
    whole.data = template.data.copy()
    whole.name = f"{FRUIT}_skin"
    bpy.context.collection.objects.link(whole)
    common.parent_keep_transform(whole, whole_root)
    stem = common.make_stem(f"{FRUIT}_stem", stem_material, location=(0.0, 0.0, 0.80),
                            points=((0.0, 0.0, 0.0), (0.014, 0.0, 0.08), (0.024, 0.0, 0.16), (0.020, 0.0, 0.24)))
    stem.scale = (1.0, 1.0, 0.8)
    common.parent_keep_transform(stem, whole_root)

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = common.apply_boolean_half(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = common.apply_boolean_half(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    citrus.make_citrus_cut_face(
        right_root, 1.0, flesh, pith,
        SEGMENT_COUNT, SEGMENT_GAP, WEDGE_INNER, WEDGE_OUTER, PITH_RING_INNER, PITH_RING_OUTER, OVERLAY_X,
    )
    citrus.make_citrus_cut_face(
        left_root, -1.0, flesh, pith,
        SEGMENT_COUNT, SEGMENT_GAP, WEDGE_INNER, WEDGE_OUTER, PITH_RING_INNER, PITH_RING_OUTER, OVERLAY_X,
    )

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-square lemon filling the frame (bbox 98.6 x 98.2), black background",
            "skin families #d99408, #e8b614, #fcde12 with deep shadows #776006",
            "strong specular gloss #fcef5f (8.8% bright vs orange 0.8%: shinier peel)",
            "no green family in the whole palette: stem nub only, no leaf",
            "cut face: flesh #f1cd4b/#e9b61d wedges separated by pale pith #f7e6a4",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "elongation and end nubs from lemon convention; the reference bbox is near square so both stay modest",
            "segment count (8), wedge radii and pith thickness from typical lemon structure",
            "no seeds: none visible in the measured cut palette",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with lemon-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "lemon-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.85},
        "massKilograms": 0.10,
        "juiceColorSRGB": [1.0, 0.85, 0.25],
        "materialNotes": {
            "skin": "roughness 0.22, specular IOR level 0.65 (glossy waxy peel)",
            "flesh": "roughness 0.24, specular IOR level 0.85 (wet segment face)",
            "pith": "#f7e6a4, roughness 0.38",
            "stem": "#6b4d1f, roughness 0.60",
        },
        "cutFaceStructure": {
            "segments": SEGMENT_COUNT,
            "pithRing": [PITH_RING_INNER, PITH_RING_OUTER],
            "wedgeRadii": [WEDGE_INNER, WEDGE_OUTER],
        },
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
