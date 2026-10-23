"""Build the FruitWave banana asset from the approved PRD references.

Run with:
  Blender --background --python Tools/Blender/generate_banana.py

Grounding: PRD v1.0 indexes the approved pair at
ArtSource/PRD-v1.0/FruitReferences/banana/{whole,cut}.png. Measured palette
(Tools/Blender/grounding_report.json): skin yellow #cf9612/#f6c421/#ea9a0e
with bright #fdeb84 and a dark tip family; cut shows cream flesh
#fcedb4/#fde663/#f8d355, yellow peel #d6a11b/#f1b41b and a dark brown
#875b0c seed-line family. The whole fills the frame nearly square, so the
photo is taken down the fruit's length; a crescent body reads as banana
immediately, and the cut is authored LENGTHWISE (halves split along the
arc in the Y direction), matching the dominant cream face of the cut photo.

Bend: each cross-section rotates around Y by phi = BEND * z, so the tips
bow toward +X symmetrically and the midline stays in the XZ plane; the
y=0 cut therefore contains the full arc and each half keeps both tips.

Deliverables (in FruitWaveApp/Resources/Models/Banana/): banana.blend,
banana_reference.png/cut, banana_reference.json, banana_skin_basecolor.png,
banana_flesh_basecolor.png, banana_whole.usdz, banana_sliced.usdz,
banana_preview.png, banana.json.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # find fruitgen/

import bpy

from fruitgen import common

FRUIT = "banana"
TITLE = "Banana"
OUTPUT = common.MODELS / TITLE
SKIN_REFERENCE = OUTPUT / f"{FRUIT}_reference.png"
FLESH_REFERENCE = OUTPUT / f"{FRUIT}_reference_cut.png"
SKIN_ALBEDO = OUTPUT / f"{FRUIT}_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / f"{FRUIT}_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)

SKIN_BASE = (0.85, 0.62, 0.10)   # mid #cf9612/#f6c421 family
FLESH_BASE = (0.97, 0.90, 0.60)  # cream #fcedb4/#fde663 family
SEED = (0.53, 0.36, 0.05)        # dark brown #875b0c seed line
STEM = (0.58, 0.38, 0.04)        # stem stub #945f09 family
SCAR = (0.08, 0.05, 0.02)        # dark bottom tip

BEND = 0.24     # rad per unit z; tip rotation ~0.29 rad, bow ~0.34
HALF_LENGTH = 1.2
SEED_STRIP_HALF_WIDTH = 0.028
SEED_STRIP_HALF_LENGTH = 1.02


def classify_skin(r: float, g: float, b: float) -> str:
    """Yellow peel families; bright cream-lit zones as mark."""
    if r > 0.5 and g > 0.3 and b < 0.5 and r > g > b and (r - b) > 0.35:
        return "skin"
    if r > 0.9 and g > 0.8 and b > 0.4:
        return "mark"
    return "other"


def is_flesh(r: float, g: float, b: float, a: float) -> bool:
    return a > 0.8 and r > 0.9 and g > 0.75 and b > 0.25


def bend_around_y(obj: bpy.types.Object) -> None:
    """Crescent bend: rotate each vertex around Y by BEND * z.

    x' = x cos phi + z sin phi, z' = -x sin phi + z cos phi with
    phi = BEND * z. Both tips bow toward +X and the midline (x = 0
    before the bend) stays in the XZ plane, so the lengthwise cut at
    y = 0 contains the whole arc.
    """
    for vertex in obj.data.vertices:
        phi = BEND * vertex.co.z
        cos_phi, sin_phi = math.cos(phi), math.sin(phi)
        x, z = vertex.co.x, vertex.co.z
        vertex.co.x = x * cos_phi + z * sin_phi
        vertex.co.z = -x * sin_phi + z * cos_phi
    obj.data.update()


def apply_banana_boolean(source: bpy.types.Object, name: str, keep_right: bool) -> bpy.types.Object:
    """Same as common.apply_boolean_half but cutting along y = 0, so the
    crescent body splits lengthwise and each half keeps both tips."""
    half = source.copy()
    half.data = source.data.copy()
    bpy.context.collection.objects.link(half)
    half.name = name
    bpy.context.view_layer.objects.active = half
    half.select_set(True)

    bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0.0, (1.0 if keep_right else -1.0), 0.0))
    cutter = bpy.context.object
    cutter.name = f"{name}_Cutter"
    cutter.scale = (2.0, 1.0, 2.0)
    bpy.context.view_layer.objects.active = half
    modifier = half.modifiers.new("AuthoredCut", "BOOLEAN")
    modifier.operation = "INTERSECT"
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

    # Boolean cap polygons face along the cut plane. Assign those polygons
    # to material slot 1 (the cut-face material) and keep them faceted while
    # the outer surface stays smooth.
    for polygon in half.data.polygons:
        center_y = sum(half.data.vertices[index].co.y for index in polygon.vertices) / len(polygon.vertices)
        is_cut_cap = abs(center_y) < 0.006 and abs(polygon.normal.y) > 0.94
        if is_cut_cap:
            polygon.material_index = 1
        polygon.use_smooth = not is_cut_cap
    return half


def make_seed_strip(name: str, material: bpy.types.Material, sign: float) -> bpy.types.Object:
    """Thin dark strip following the arc, on the cut face just outside the
    half (y = -sign * 0.004, same overlay convention as make_annulus)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    strip = bpy.context.object
    strip.name = name
    strip.scale = (SEED_STRIP_HALF_WIDTH, 0.004, SEED_STRIP_HALF_LENGTH)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bend_around_y(strip)
    strip.location.y = -sign * 0.004
    strip.data.materials.append(material)
    for polygon in strip.data.polygons:
        polygon.use_smooth = False
    return strip


PROFILE = [
    (0.00, -1.20),
    (0.06, -1.19),
    (0.14, -1.16),
    (0.22, -1.10),
    (0.30, -1.00),
    (0.37, -0.85),
    (0.41, -0.65),
    (0.43, -0.40),
    (0.44, -0.10),
    (0.44, 0.15),
    (0.43, 0.40),
    (0.41, 0.65),
    (0.37, 0.85),
    (0.30, 1.00),
    (0.22, 1.10),
    (0.14, 1.16),
    (0.06, 1.19),
    (0.00, 1.20),
]


def main() -> None:
    common.reset_scene()
    prd, whole_entry, cut_entry = common.load_prd_entries(FRUIT)
    skin_reference = common.load_reference(SKIN_REFERENCE, "BananaSkinReference")
    flesh_reference = common.load_reference(FLESH_REFERENCE, "BananaFleshReference")
    skin_image = common.write_reference_skin_texture(skin_reference, SKIN_ALBEDO, "BananaSkinBaseColor", classify_skin, SKIN_BASE)
    flesh_image = common.write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO, "BananaFleshBaseColor", is_flesh, FLESH_BASE)

    skin = common.image_material("BananaSkin_PBR", skin_image, roughness=0.38, specular=0.45)
    flesh = common.image_material("BananaFlesh_PBR", flesh_image, roughness=0.26, specular=0.70, planar_xz=True)
    seed = common.solid_material("BananaSeed_PBR", (*SEED, 1), 0.40, specular=0.15)
    stem_material = common.solid_material("BananaStem_PBR", (*STEM, 1), 0.50, specular=0.20)
    scar_material = common.solid_material("BananaScar_PBR", (*SCAR, 1), 0.45, specular=0.10)

    template = common.make_body_from_profile(
        "BananaBodyTemplate", PROFILE, lobes=0.05, lobe_count=5, asymmetry=0.003, y_scale=1.0, z_scale=1.0
    )
    template.data.materials.append(skin)
    template.data.materials.append(flesh)
    bend_around_y(template)

    tip_phi = BEND * HALF_LENGTH
    top_tip = (HALF_LENGTH * math.sin(tip_phi), 0.0, HALF_LENGTH * math.cos(tip_phi))
    # Bottom tip bows to the same +X side; outward tangent there is the
    # negative-z derivative of the bent midline.
    bottom_tip = (HALF_LENGTH * math.sin(-tip_phi), 0.0, HALF_LENGTH * math.cos(tip_phi))
    bottom_tangent = (
        math.sin(-tip_phi) + (-HALF_LENGTH) * BEND * math.cos(-tip_phi),
        0.0,
        math.cos(-tip_phi) - (-HALF_LENGTH) * BEND * math.sin(-tip_phi),
    )
    bottom_outward = (-bottom_tangent[0] / math.hypot(bottom_tangent[0], bottom_tangent[2]),
                      0.0,
                      -bottom_tangent[2] / math.hypot(bottom_tangent[0], bottom_tangent[2]))

    whole_root = bpy.data.objects.new(f"{FRUIT}_whole", None)
    bpy.context.collection.objects.link(whole_root)
    whole = template.copy()
    whole.data = template.data.copy()
    whole.name = f"{FRUIT}_skin"
    bpy.context.collection.objects.link(whole)
    common.parent_keep_transform(whole, whole_root)

    stem = common.make_ellipsoid(
        f"{FRUIT}_stem", stem_material,
        location=(top_tip[0] + 0.05 * math.sin(tip_phi), 0.0, top_tip[2] + 0.05 * math.cos(tip_phi)),
        scale=(0.05, 0.05, 0.13),
    )
    stem.rotation_euler.y = tip_phi
    common.parent_keep_transform(stem, whole_root)
    scar = common.make_ellipsoid(
        f"{FRUIT}_scar", scar_material,
        location=(bottom_tip[0] + 0.04 * bottom_outward[0], 0.0, bottom_tip[2] + 0.04 * bottom_outward[2]),
        scale=(0.05, 0.05, 0.09),
    )
    scar.rotation_euler.y = math.atan2(bottom_outward[0], bottom_outward[2])
    common.parent_keep_transform(scar, whole_root)

    right_root = bpy.data.objects.new(f"{FRUIT}_half_right", None)
    left_root = bpy.data.objects.new(f"{FRUIT}_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = apply_banana_boolean(template, f"{FRUIT}_half_right_mesh", keep_right=True)
    left = apply_banana_boolean(template, f"{FRUIT}_half_left_mesh", keep_right=False)
    common.parent_keep_transform(right, right_root)
    common.parent_keep_transform(left, left_root)

    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        strip = make_seed_strip(f"{root.name}_seed_strip", seed, sign)
        common.parent_keep_transform(strip, root)

    bpy.data.objects.remove(template, do_unlink=True)
    common.export_usdz(OUTPUT / f"{FRUIT}_whole.usdz", [whole_root])
    common.export_usdz(OUTPUT / f"{FRUIT}_sliced.usdz", [left_root, right_root])

    common.write_reference_manifest(
        FRUIT, OUTPUT, prd, whole_entry, cut_entry,
        observed=[
            "whole photo fills the frame nearly square: photographed down the fruit's length",
            "skin yellow #cf9612/#f6c421/#ea9a0e with bright #fdeb84 and dark tip family",
            "cut face: cream flesh #fcedb4/#fde663/#f8d355, yellow peel, dark brown #875b0c seed line",
        ],
        inferred=[
            "the crescent bend (BEND 0.24 rad/unit) is banana-typical; the photo does not show it",
            "the cut is authored lengthwise so both halves keep the full arc",
            "five ridge lobes (lobe_count 5) from banana structure",
            "seed strip from the dark #875b0c family of the cut palette",
        ],
        derived=[
            {"path": f"{FRUIT}_skin_basecolor.png", "method": "per-row mirrored-longitude cylinder remap with banana-family classification, de-lighting blend"},
            {"path": f"{FRUIT}_flesh_basecolor.png", "method": "banana-cream centroid disk remap, specular rejection, de-lighting blend"},
        ],
    )

    common.write_metadata(FRUIT, OUTPUT, {
        "collision": {"shape": "sphere", "radius": HALF_LENGTH},
        "massKilograms": 0.12,
        "juiceColorSRGB": [0.95, 0.85, 0.40],
        "materialNotes": {
            "skin": "roughness 0.38, specular IOR level 0.45 (satin peel)",
            "flesh": "roughness 0.26, specular IOR level 0.70 (wet cut face)",
            "seedLine": "#875b0c strip, roughness 0.40",
            "stem": "#945f09 nub, roughness 0.50",
        },
        "cutFaceStructure": {
            "split": "lengthwise",
            "bendRadPerUnit": BEND,
            "seedStripHalfWidth": SEED_STRIP_HALF_WIDTH,
            "seedStripHalfLength": SEED_STRIP_HALF_LENGTH,
        },
    })

    common.configure_preview(OUTPUT, FRUIT, whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / f"{FRUIT}.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
