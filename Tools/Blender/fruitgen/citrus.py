"""Shared citrus cut-face machinery: wedge fans, pith walls, ring, center.

Used by the citrus-family generators (lemon and later variants). The orange
generator keeps its own inline copy of this logic: its USDZ output is
device-verified and frozen for determinism, so it must not drift if this
module evolves.

Coordinate convention matches generate_orange.py: overlay fans live in the
local YZ plane with +X normal; the right half's cap faces -X so its overlays
sit at x = -sign * overlay_x and are flipped with rotation_euler.y = pi.
"""
from __future__ import annotations

import math

import bpy

from fruitgen import common


def make_wedge_fan(
    name: str,
    material: bpy.types.Material,
    angle0: float,
    angle1: float,
    r0: float,
    r1: float,
    sign: float,
    overlay_x: float,
    segments: int = 4,
) -> bpy.types.Object:
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
    fan.location.x = -sign * overlay_x
    fan.rotation_euler.y = math.pi if sign > 0 else 0.0
    fan.data.materials.append(material)
    for polygon in fan.data.polygons:
        polygon.use_smooth = True
    return fan


def make_citrus_cut_face(
    root: bpy.types.Object,
    sign: float,
    flesh: bpy.types.Material,
    pith: bpy.types.Material,
    segment_count: int,
    segment_gap: float,
    wedge_inner: float,
    wedge_outer: float,
    ring_inner: float,
    ring_outer: float,
    overlay_x: float,
) -> None:
    """Overlay the signature segment interior onto the boolean cap.

    sign is +1 for the right root and -1 for the left; the right half's cap
    faces -X so overlays sit at x = -sign * overlay_x.
    """
    step = 2.0 * math.pi / segment_count
    for index in range(segment_count):
        angle0 = index * step + segment_gap / 2
        angle1 = (index + 1) * step - segment_gap / 2
        wedge = make_wedge_fan(f"{root.name}_wedge_{index}", flesh, angle0, angle1, wedge_inner, wedge_outer, sign, overlay_x)
        common.parent_keep_transform(wedge, root)
        wall = make_wedge_fan(f"{root.name}_pith_wall_{index}", pith, angle1, angle1 + segment_gap, wedge_inner, ring_outer, sign, overlay_x)
        common.parent_keep_transform(wall, root)
    ring = make_wedge_fan(f"{root.name}_pith_ring", pith, 0.0, 2.0 * math.pi, ring_inner, ring_outer, sign, overlay_x, segments=48)
    common.parent_keep_transform(ring, root)
    center = common.make_ellipsoid(f"{root.name}_pith_center", pith, location=(-sign * 0.010, 0.0, 0.0), scale=(0.020, 0.105, 0.105))
    common.parent_keep_transform(center, root)
