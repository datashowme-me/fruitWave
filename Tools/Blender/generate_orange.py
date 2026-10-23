"""Build the FruitWave orange asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_orange.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/orange/{whole,cut}.png. Pristine copies
live beside the deliverables as orange_reference.png / orange_reference_cut.png.
Measured palette (Tools/Blender/grounding_report.json): skin #e65508/#a34507
family with lit highlights #f3af31/#d6810f; cut shows flesh #f6a620/#fa7e0f,
pith #fbe69a. No green family in the whole palette, so the whole fruit gets
a small stem nub but no leaf.

Deliverables (in FruitWaveApp/Resources/Models/Orange/): orange.blend,
orange_reference.png/cut, orange_reference.json, orange_skin_basecolor.png,
orange_flesh_basecolor.png, orange_whole.usdz, orange_sliced.usdz,
orange_preview.png, orange.json.

The cut face is the orange's signature interior: a pith ring inside the
peel, nine moon-shaped flesh wedges with thin pith walls, and a pith
center, all as flat overlay meshes on the boolean cap. No seeds (the
reference shows none).
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "orange"
TITLE = "Orange"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

# De-lit blend targets derived from the measured palettes.
SKIN_BASE = (0.86, 0.42, 0.06)   # mid orange #db6b0f family
FLESH_BASE = (0.94, 0.58, 0.12)  # bright flesh #f0941f family
PITH = (0.98, 0.90, 0.60)        # #fae699 family
PEEL_EDGE = (0.90, 0.45, 0.08)   # deeper peel ring


def classify_skin(r: float, g: float, b: float) -> str:
    """Orange families: saturated orange skin, lighter yellow-orange mark."""
    if r > 0.55 and g > 0.22 and b < 0.40 and r > g > b and (r - b) > 0.28:
        return "skin"
    if r > 0.60 and g > 0.48 and b < 0.55 and r > b:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.55 and g > 0.28 and b < 0.50 and r > g > b and (r - b) > 0.30 and max(r, g, b) < 0.96


# Nearly-spherical body, slightly smaller than the apple asset, with a
# subtle five-lobe citrus ripple and tucked ends.
PROFILE = [
    (0.00, -0.80),
    (0.15, -0.81),
    (0.34, -0.82),
    (0.55, -0.80),
    (0.74, -0.74),
    (0.87, -0.60),
    (0.94, -0.40),
    (0.96, -0.18),
    (0.94, 0.06),
    (0.88, 0.30),
    (0.76, 0.52),
    (0.58, 0.68),
    (0.36, 0.77),
    (0.16, 0.80),
    (0.00, 0.78),
]

SEGMENT_COUNT = 9
SEGMENT_GAP = 0.045          # radians of pith wall between wedges
WEDGE_INNER = 0.10
WEDGE_OUTER = 0.75
PITH_RING_INNER = 0.78
PITH_RING_OUTER = 0.88
OVERLAY_X = 0.006            # overlay meshes sit just outside the cap


def make_wedge_fan(name: str, material: bpy.types.Material, angle0: float, angle1: float, r0: float, r1: float, sign: float, segments: int = 4) -> bpy.types.Object:
    """Pie-sector fan in the local YZ plane, normal +X, flipped for the
    right half so every overlay faces outward from its half."""
    vertices: list[tuple[float, float, float]] = []
    for index in range(segments + 1):
        t = index / segments
        angle = angle0 + t * (angle1 - angle0)
        for radius in (r0, r1):
            vertices.append((0.0, radius * math.cos(angle), radius * math.sin(angle)))
    faces = [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2) for i in range(segments)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    fan = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(fan)
    fan.location.x = -sign * OVERLAY_X
    fan.rotation_euler.y = math.pi if sign > 0 else 0.0
    fan.data.materials.append(material)
    for polygon in fan.data.polygons:
        polygon.use_smooth = True
    return fan


def make_citrus_cut_face(root: bpy.types.Object, sign: float, flesh: bpy.types.Material, pith: bpy.types.Material) -> None:
    """Overlay the signature segment interior onto the boolean cap.

    sign is +1 for the right root and -1 for the left; the right half's cap
    faces -X so overlays sit at x = -sign * OVERLAY_X.
    """
    step = 2.0 * math.pi / SEGMENT_COUNT
    for index in range(SEGMENT_COUNT):
        angle0 = index * step + SEGMENT_GAP / 2
        angle1 = (index + 1) * step - SEGMENT_GAP / 2
        wedge = make_wedge_fan(f"{root.name}_wedge_{index}", flesh, angle0, angle1, WEDGE_INNER, WEDGE_OUTER, sign)
        common.parent_keep_transform(wedge, root)
        wall = make_wedge_fan(f"{root.name}_pith_wall_{index}", pith, angle1, angle1 + SEGMENT_GAP, WEDGE_INNER, PITH_RING_OUTER, sign)
        common.parent_keep_transform(wall, root)
    ring = make_wedge_fan(f"{root.name}_pith_ring", pith, 0.0, 2.0 * math.pi, PITH_RING_INNER, PITH_RING_OUTER, sign, segments=48)
    common.parent_keep_transform(ring, root)
    center = common.make_ellipsoid(f"{root.name}_pith_center", pith, location=(-sign * 0.010, 0.0, 0.0), scale=(0.020, 0.105, 0.105))
    common.parent_keep_transform(center, root)


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "OrangeSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "OrangeFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "OrangeSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "OrangeFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("OrangeSkin_PBR", skin_image, roughness=0.30, specular=0.48)
    flesh = common.image_material("OrangeFlesh_PBR", flesh_image, roughness=0.24, specular=0.85, planar_yz=True)
    pith = common.solid_material("OrangePith_PBR", (*PITH, 1), 0.38, specular=0.30)
    peel = common.solid_material("OrangePeel_PBR", (*PEEL_EDGE, 1), 0.34, specular=0.40)
    stem_material = common.solid_material("OrangeStem_PBR", (0.42, 0.30, 0.12, 1), 0.60, specular=0.20)

    template = common.make_body_from_profile(
        "OrangeBodyTemplate", PROFILE, lobes=0.035, lobe_count=5, asymmetry=0.008, y_scale=0.99, z_scale=1.0
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
    stem = common.make_stem(f"{FRUIT}_stem", stem_material, location=(0.0, 0.0, 0.74),
                            points=((0.0, 0.0, 0.0), (0.015, 0.0, 0.10), (0.03, 0.0, 0.20), (0.025, 0.0, 0.30)))
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

    make_citrus_cut_face(right_root, 1.0, flesh, pith)
    make_citrus_cut_face(left_root, -1.0, flesh, pith)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "near-spherical orange filling the frame (bbox aspect 1.00), black background",
            "skin families #e65508, #a34507, #d6810f with lit highlights #f3af31",
            "no green family in the whole palette: stem nub only, no leaf",
            "cut face: flesh #f6a620/#fa7e0f wedges separated by pale pith #fbe69a",
            "medium waxy gloss (bright 0.8% of bbox on whole, 5.2% on cut)",
        ],
        inferred=[
            "unseen back mirrored from the front half",
            "five-lobe citrus ripple and tucked ends from the silhouette; strength inferred",
            "segment count (9), wedge radii and pith thickness from typical orange structure",
            "no seeds: none visible in the measured cut palette",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with orange-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "orange-flesh centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": 0.85},
        "massKilograms": 0.15,
        "juiceColorSRGB": [1.0, 0.62, 0.10],
        "materialNotes": {
            "skin": "roughness 0.30, specular IOR level 0.48 (pebbled waxy peel)",
            "flesh": "roughness 0.24, specular IOR level 0.85 (wet segment face)",
            "pith": "#fae699, roughness 0.38",
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
