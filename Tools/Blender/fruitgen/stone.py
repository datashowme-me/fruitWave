"""Shared cut-face machinery for stone fruits (cherry, plum, peach).

The pit stays whole inside one half and protrudes slightly past the cut
cap; the other half carries a flat darker cavity disk that reads as the
pit's impression. The flesh itself is the boolean cap slot (material index
1) plus a texture-mapped flat disk overlay, exactly like the citrus cap.
"""
from __future__ import annotations

import bpy

from fruitgen import common


def make_stone_cut_face(
    root: bpy.types.Object,
    sign: float,
    pit: bpy.types.Material | None,
    cavity: bpy.types.Material | None,
    pit_scale: tuple[float, float, float],
    pit_x: float = 0.10,
) -> None:
    """sign +1: right half carries the pit; sign -1: cavity disk instead.

    The flesh is the boolean cap itself (material slot 1 on the template),
    so no flesh overlay is needed. Overlays must sit OUTSIDE the half
    (x = -sign * overlay_x) or the opaque boolean cap hides them.
    """
    if pit is not None:
        # Half-embedded: center inside the half, surface pokes past the cap.
        pit_obj = common.make_ellipsoid(f"{root.name}_pit", pit, location=(sign * pit_x, 0.0, 0.0), scale=pit_scale)
        common.parent_keep_transform(pit_obj, root)
    if cavity is not None:
        cavity_disk = common.make_annulus(f"{root.name}_cavity", cavity, 0.0, pit_scale[1] * 1.2, sign, 0.004)
        common.parent_keep_transform(cavity_disk, root)
