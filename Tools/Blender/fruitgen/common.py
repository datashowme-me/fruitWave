"""Shared FruitWave asset-pipeline helpers extracted from generate_apple.py.

Each per-fruit generator (Tools/Blender/generate_<fruit>.py) supplies its
own silhouette, palette classification, materials and cut-face authoring;
everything here is behaviour genuinely shared by every fruit:

  * PRD reference grounding and per-fruit reference manifests
  * de-lit cylindrical skin maps and cut-flesh maps derived from the PRD PNGs
  * UsdPreviewSurface-only materials (clearcoat does not survive USDZ export)
  * surface-of-revolution bodies, stems, leaves, seeds
  * authored-cut halves (swap-instead-of-runtime-boolean)
  * USDZ export, EEVEE preview, runtime metadata

Deterministic: fixed seeds, fixed object names, fixed export settings.
"""
from __future__ import annotations

import json
import math
from array import array
from pathlib import Path
from typing import Callable, Sequence

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
MODELS = ROOT / "FruitWaveApp" / "Resources" / "Models"
PRD_MANIFEST = ROOT / "ArtSource" / "PRD-v1.0" / "manifest.json"


# ---------------------------------------------------------------------------
# Scene and reference handling
# ---------------------------------------------------------------------------

def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def load_reference(path: Path, name: str) -> bpy.types.Image:
    if not path.is_file():
        raise FileNotFoundError(f"Required PRD reference is missing: {path}")
    image = bpy.data.images.load(str(path), check_existing=False)
    image.name = name
    image.colorspace_settings.name = "sRGB"
    return image


def sample_image(image: bpy.types.Image, pixels: list[float], u: float, v: float) -> tuple[float, float, float, float]:
    width, height = image.size
    x = min(width - 1, max(0, int(u * (width - 1))))
    y = min(height - 1, max(0, int(v * (height - 1))))
    index = (y * width + x) * 4
    return tuple(pixels[index + channel] for channel in range(4))


def load_prd_entries(fruit: str) -> tuple[dict, dict, dict]:
    """Return (prd, whole_entry, cut_entry) for the fruit from the PRD index."""
    if not PRD_MANIFEST.is_file():
        raise FileNotFoundError(f"PRD reference index is missing: {PRD_MANIFEST}")
    prd = json.loads(PRD_MANIFEST.read_text())
    by_role = {a["role"]: a for a in prd["assets"] if a["fruit"] == fruit}
    if set(by_role) != {"whole", "cut"}:
        raise ValueError(f"PRD index lacks whole/cut references for {fruit}: {sorted(by_role)}")
    return prd, by_role["whole"], by_role["cut"]


# ---------------------------------------------------------------------------
# De-lit texture derivation from the PRD reference photos
# ---------------------------------------------------------------------------

def write_reference_skin_texture(
    reference: bpy.types.Image,
    path: Path,
    name: str,
    classify_skin: Callable[[float, float, float], str],
    base: tuple[float, float, float],
    width: int = 1024,
    height: int = 512,
) -> bpy.types.Image:
    """Remap the PRD whole fruit into a seamless cylindrical skin map.

    Each output row samples the corresponding photo row across the fruit's
    opaque span; longitudes beyond the front half mirror back, which keeps
    the unseen back plausible and the seam quiet. Non-skin pixels are
    refilled from the nearest valid skin column; everything is blended
    toward `base` to de-light the photograph so the baked lighting is not
    lit a second time in the renderer.
    """
    source_pixels = list(reference.pixels)
    src_w, src_h = reference.size

    def row_span(y: int) -> tuple[int, int] | None:
        xs = []
        for x in range(src_w):
            if source_pixels[(y * src_w + x) * 4 + 3] > 0.8:
                xs.append(x)
        return (xs[0], xs[-1]) if xs else None

    top = bottom = None
    for y in range(0, src_h, max(1, src_h // 64)):
        if row_span(y) is not None:
            top = y if top is None else min(top, y)
            bottom = y if bottom is None else max(bottom, y)
    if top is None or bottom is None:
        raise ValueError(f"PRD whole reference has no opaque content: {reference.name}")

    image = bpy.data.images.new(name, width=width, height=height, alpha=True)
    pixels = array("f")
    base_r, base_g, base_b = base
    for y in range(height):
        v = y / max(1, height - 1)
        source_y = int(top + v * (bottom - top))
        span = row_span(source_y)
        if span is None:
            span = (src_w // 2, src_w // 2)
        left, right = span
        valid_columns = [
            x for x in range(left, right + 1)
            if classify_skin(*source_pixels[(source_y * src_w + x) * 4:(source_y * src_w + x) * 4 + 3]) != "other"
        ]
        vertical_tone = 0.86 + 0.14 * math.sin((v - 0.15) * math.pi)
        row_base = (base_r * vertical_tone, base_g * vertical_tone, base_b * vertical_tone)
        for x in range(width):
            u = x / max(1, width - 1)
            t = 2.0 * u if u <= 0.5 else 2.0 * (1.0 - u)
            source_x = int(left + t * (right - left))
            r, g, b, _ = sample_image(reference, source_pixels, source_x / max(1, src_w - 1), source_y / max(1, src_h - 1))
            kind = classify_skin(r, g, b)
            if kind == "other" and valid_columns:
                nearest = min(valid_columns, key=lambda c: abs(c - source_x))
                r, g, b, _ = sample_image(reference, source_pixels, nearest / max(1, src_w - 1), source_y / max(1, src_h - 1))
                kind = "skin"
            if kind == "other":
                r, g, b = row_base
                kind = "skin"
            if kind == "mark":
                r = 0.62 * r + 0.38 * row_base[0]
                g = 0.62 * g + 0.38 * row_base[1]
                b = 0.62 * b + 0.38 * row_base[2]
            else:
                r = 0.50 * r + 0.50 * row_base[0]
                g = 0.50 * g + 0.50 * row_base[1]
                b = 0.50 * b + 0.50 * row_base[2]
            luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if luminance > 0.80:
                scale = 0.80 / luminance
                r, g, b = r * scale, g * scale, b * scale
            pixels.extend((min(r, 1.0), min(g, 1.0), min(b, 1.0), 1.0))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    return image


def write_reference_flesh_texture(
    reference: bpy.types.Image,
    path: Path,
    name: str,
    is_flesh: Callable[[float, float, float, float], bool],
    base: tuple[float, float, float],
    size: int = 768,
) -> bpy.types.Image:
    """Build a flesh map from the dominant flesh family of the cut photo.

    Locates the flesh mass from the measured color family, remaps a disk
    around its centroid, rejects specular patches, and blends toward `base`.
    """
    source_pixels = list(reference.pixels)
    src_w, src_h = reference.size
    points = []
    for y in range(0, src_h, 2):
        for x in range(0, src_w, 2):
            r, g, b, a = source_pixels[(y * src_w + x) * 4:(y * src_w + x) * 4 + 4]
            if is_flesh(r, g, b, a):
                points.append((x, y))
    if not points:
        raise ValueError(f"PRD cut reference has no flesh region: {reference.name}")
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)
    cx = (min_x + max_x) // 2
    cy = (min_y + max_y) // 2
    span = max(max_x - min_x, max_y - min_y)

    image = bpy.data.images.new(name, width=size, height=size, alpha=True)
    pixels = array("f")
    base_r, base_g, base_b = base
    for y in range(size):
        v = y / max(1, size - 1)
        for x in range(size):
            u = x / max(1, size - 1)
            du, dv = u - 0.5, v - 0.5
            radius = math.sqrt(du * du + dv * dv)
            if radius > 0.5:
                r, g, b = base_r, base_g, base_b
            else:
                sx = cx + du * span
                sy = cy + dv * span
                r, g, b, a = sample_image(reference, source_pixels, sx / max(1, src_w - 1), sy / max(1, src_h - 1))
                if not is_flesh(r, g, b, a):
                    r, g, b = base_r, base_g, base_b
                r = 0.55 * r + 0.45 * base_r
                g = 0.55 * g + 0.45 * base_g
                b = 0.55 * b + 0.45 * base_b
            pixels.extend((min(r, 1.0), min(g, 1.0), min(b, 1.0), 1.0))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    return image


# ---------------------------------------------------------------------------
# Materials (UsdPreviewSurface-compatible)
# ---------------------------------------------------------------------------

def image_material(
    name: str,
    image: bpy.types.Image,
    roughness: float,
    specular: float = 0.55,
    planar_yz: bool = False,
    planar_xz: bool = False,
) -> bpy.types.Material:
    """PBR material limited to UsdPreviewSurface channels.

    Clearcoat does not survive USDZ export, so the waxy/wet response is
    authored as Specular IOR Level, which RealityKit honours.
    """
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Linear"
    if planar_yz:
        coordinates = nodes.new("ShaderNodeTexCoord")
        separate = nodes.new("ShaderNodeSeparateXYZ")
        combine = nodes.new("ShaderNodeCombineXYZ")
        links.new(coordinates.outputs["Generated"], separate.inputs["Vector"])
        links.new(separate.outputs["Y"], combine.inputs["X"])
        links.new(separate.outputs["Z"], combine.inputs["Y"])
        links.new(combine.outputs["Vector"], texture.inputs["Vector"])
    elif planar_xz:
        coordinates = nodes.new("ShaderNodeTexCoord")
        separate = nodes.new("ShaderNodeSeparateXYZ")
        combine = nodes.new("ShaderNodeCombineXYZ")
        links.new(coordinates.outputs["Generated"], separate.inputs["Vector"])
        links.new(separate.outputs["X"], combine.inputs["X"])
        links.new(separate.outputs["Z"], combine.inputs["Y"])
        links.new(combine.outputs["Vector"], texture.inputs["Vector"])
    links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = specular
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def solid_material(name: str, color: tuple[float, float, float, float], roughness: float, specular: float = 0.25) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = specular
    return material


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def make_body_from_profile(
    name: str,
    profile: Sequence[tuple[float, float]],
    segments: int = 96,
    lobes: float = 0.0,
    lobe_count: int = 5,
    lobe_phase: float = 0.35,
    asymmetry: float = 0.0,
    y_scale: float = 0.97,
    z_scale: float = 1.02,
) -> bpy.types.Object:
    """Surface of revolution from an art-directed (radius, z) profile.

    The two centre vertices sit *inside* their adjacent rings so neither
    end can turn into a spike under smooth shading. Optional cosine lobes
    (citrus) and a subtle asymmetry keep the silhouette organic.
    """
    vertices: list[tuple[float, float, float]] = [(0.0, 0.0, profile[0][1] * z_scale)]
    rings: list[list[int]] = []
    for ring_index, (radius, z) in enumerate(profile[1:-1], start=1):
        ring: list[int] = []
        weight = math.sin(math.pi * ring_index / (len(profile) - 1))
        for segment in range(segments):
            theta = 2.0 * math.pi * segment / segments
            ripple = 1.0 + lobes * math.cos(theta * lobe_count + lobe_phase) * weight
            skew = 1.0 + asymmetry * math.sin(theta + 0.65) * weight
            ring.append(len(vertices))
            vertices.append((
                radius * ripple * skew * math.cos(theta),
                radius * y_scale * ripple * skew * math.sin(theta),
                z * z_scale,
            ))
        rings.append(ring)
    top_index = len(vertices)
    vertices.append((0.0, 0.0, profile[-1][1] * z_scale))

    faces: list[tuple[int, ...]] = []
    for segment in range(segments):
        following = (segment + 1) % segments
        faces.append((0, rings[0][following], rings[0][segment]))
    for lower, upper in zip(rings, rings[1:]):
        for segment in range(segments):
            following = (segment + 1) % segments
            faces.append((lower[segment], lower[following], upper[following], upper[segment]))
    for segment in range(segments):
        following = (segment + 1) % segments
        faces.append((rings[-1][segment], rings[-1][following], top_index))

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    body = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(body)
    for polygon in body.data.polygons:
        polygon.use_smooth = True
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.sphere_project(direction="ALIGN_TO_OBJECT", correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    return body


def make_stem(name: str, material: bpy.types.Material, location=(0.0, 0.0, 0.78), points=None, tilt: float = 0.18) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 3
    curve.bevel_depth = 0.045
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    if points is None:
        points = ((0.0, 0.0, 0.0), (0.01, 0.0, 0.17), (0.055, 0.0, 0.34), (0.04, 0.0, 0.50))
    spline.bezier_points.add(len(points) - 2)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    stem = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(stem)
    stem.location = location
    stem.rotation_euler.z = tilt
    stem.data.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    stem.select_set(True)
    bpy.context.view_layer.objects.active = stem
    # BasisCurves validate as USD but are not rendered by RealityKit on the
    # target Apple TV. Bake the bevel to a regular mesh.
    bpy.ops.object.convert(target="MESH")
    return stem


def make_leaf(name: str, material: bpy.types.Material, location=(0.03, 0.0, 0.82), rotation=(0.18, -0.30, 0.35), length: float = 0.72, width: float = 0.21) -> bpy.types.Object:
    segments = 16
    vertices: list[tuple[float, float, float]] = []
    for index in range(segments + 1):
        t = index / segments
        x = length * t
        half_width = width * math.sin(math.pi * t) ** 0.72
        bend = 0.045 * math.sin(math.pi * t)
        vertices.extend(((x, -half_width, bend), (x, half_width, bend)))
    faces = [(2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1) for i in range(segments)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    leaf = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(leaf)
    leaf.location = location
    leaf.rotation_euler = rotation
    leaf.data.materials.append(material)
    solidify = leaf.modifiers.new("LeafThickness", "SOLIDIFY")
    solidify.thickness = 0.012
    bevel = leaf.modifiers.new("LeafEdge", "BEVEL")
    bevel.width = 0.006
    bevel.segments = 2
    return leaf


def make_seed(name: str, material: bpy.types.Material, x: float, y: float, z: float, scale=(0.026, 0.075, 0.155), tilt: float = 0.28) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=(x, y, z))
    seed = bpy.context.object
    seed.name = name
    seed.scale = scale
    seed.rotation_euler.x = tilt if z > 0 else -tilt
    seed.data.materials.append(material)
    for polygon in seed.data.polygons:
        polygon.use_smooth = True
    return seed


def make_ellipsoid(name: str, material: bpy.types.Material, location=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0), segments: int = 32, rings: int = 16) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def parent_keep_transform(child: bpy.types.Object, parent: bpy.types.Object) -> None:
    child.parent = parent


def apply_boolean_half(source: bpy.types.Object, name: str, keep_right: bool) -> bpy.types.Object:
    half = source.copy()
    half.data = source.data.copy()
    bpy.context.collection.objects.link(half)
    half.name = name
    bpy.context.view_layer.objects.active = half
    half.select_set(True)

    bpy.ops.mesh.primitive_cube_add(size=2.0, location=((1.0 if keep_right else -1.0), 0, 0))
    cutter = bpy.context.object
    cutter.name = f"{name}_Cutter"
    cutter.scale = (1.0, 2.0, 2.0)
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
        center_x = sum(half.data.vertices[index].co.x for index in polygon.vertices) / len(polygon.vertices)
        is_cut_cap = abs(center_x) < 0.006 and abs(polygon.normal.x) > 0.94
        if is_cut_cap:
            polygon.material_index = 1
        polygon.use_smooth = not is_cut_cap
    return half


def make_cut_disk(name: str, material: bpy.types.Material, radius: float, sign: float, segments: int = 64) -> bpy.types.Object:
    """Flat disk covering the cut cap, mapped with the flesh texture.

    Built in the local YZ plane so the planar_yz flesh material samples the
    disk correctly; wound with a +X normal, then flipped for the right half.
    Placed just outside the cap (x = sign * 0.002) so it always renders in
    front of the boolean cap polygons.
    """
    vertices: list[tuple[float, float, float]] = [(0.0, 0.0, 0.0)]
    for segment in range(segments):
        theta = 2.0 * math.pi * segment / segments
        vertices.append((0.0, radius * math.cos(theta), radius * math.sin(theta)))
    faces = [
        (0, segment + 1, (segment + 1) % segments + 1)
        for segment in range(segments)
    ]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    disk = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(disk)
    disk.location.x = sign * 0.002
    # Left half (sign < 0) keeps the +X normal; right half flips to -X.
    disk.rotation_euler.y = math.pi if sign > 0 else 0.0
    disk.data.materials.append(material)
    for polygon in disk.data.polygons:
        polygon.use_smooth = True
    return disk


def make_annulus(name: str, material: bpy.types.Material, r0: float, r1: float, sign: float, overlay_x: float, segments: int = 64) -> bpy.types.Object:
    """Flat full-circle ring (or disk when r0=0) on the cut cap, in the local
    YZ plane, +X normal flipped for the right half — same overlay convention
    as make_cut_disk and the citrus wedge fans."""
    vertices: list[tuple[float, float, float]] = []
    for segment in range(segments):
        theta = 2.0 * math.pi * segment / segments
        for radius in (r0, r1):
            vertices.append((0.0, radius * math.cos(theta), radius * math.sin(theta)))
    faces = [(2 * i, 2 * i + 1, (2 * i + 3) % (2 * segments), (2 * i + 2) % (2 * segments)) for i in range(segments)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    ring = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ring)
    ring.location.x = -sign * overlay_x
    ring.rotation_euler.y = math.pi if sign > 0 else 0.0
    ring.data.materials.append(material)
    for polygon in ring.data.polygons:
        polygon.use_smooth = True
    return ring


def make_ellipsoid_ring(
    name: str,
    material: bpy.types.Material,
    count: int,
    radius: float,
    sign: float,
    overlay_x: float,
    scale: tuple[float, float, float],
    phase: float = 0.0,
) -> bpy.types.Object:
    """Ring of small ellipsoids on the cut cap (seed rings: kiwi, melons).

    One empty root holding `count` ellipsoids at `radius` in the local YZ
    plane, each rotated so its long axis points outward from the fruit axis.
    """
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for index in range(count):
        theta = phase + 2.0 * math.pi * index / count
        seed = make_ellipsoid(f"{name}_{index}", material, scale=scale)
        seed.location = (-sign * overlay_x, radius * math.cos(theta), radius * math.sin(theta))
        # R_x(theta - pi/2) maps the long axis (local z) to the radial
        # direction (0, cos theta, sin theta) and the wide axis (local y)
        # to the ring tangent, so seeds lie flat, length pointing outward.
        seed.rotation_euler.x = theta - math.pi / 2.0
        seed.parent = root
    return root


# ---------------------------------------------------------------------------
# Export, preview, manifests
# ---------------------------------------------------------------------------

def select_tree(roots: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    pending = list(roots)
    while pending:
        item = pending.pop()
        item.select_set(True)
        pending.extend(item.children)
    bpy.context.view_layer.objects.active = roots[0]


def export_usdz(path: Path, roots: list[bpy.types.Object]) -> None:
    select_tree(roots)
    bpy.ops.wm.usd_export(
        filepath=str(path),
        selected_objects_only=True,
        export_materials=True,
        export_textures_mode="NEW",
        relative_paths=True,
        generate_preview_surface=True,
        export_animation=False,
        export_uvmaps=True,
        export_normals=True,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
    )


def configure_preview(
    output: Path,
    prefix: str,
    whole_root: bpy.types.Object,
    sliced_roots: list[bpy.types.Object],
    labels: tuple[str, str] = ("whole", "cut"),
) -> None:
    whole_root.location = (-1.65, 0.05, 0)
    sliced_roots[0].location = (1.18, 0.0, 0.38)
    sliced_roots[0].rotation_euler = (0.0, -0.30, -0.18)
    sliced_roots[1].location = (1.85, 0.0, -0.35)
    sliced_roots[1].rotation_euler = (0.0, 0.26, 0.18)

    bpy.ops.object.camera_add(location=(0.2, -11.5, 1.25))
    camera = bpy.context.object
    camera.name = f"{prefix}PreviewCamera"
    camera.data.lens = 55
    camera.data.dof.use_dof = True
    camera.data.dof.focus_object = whole_root
    camera.data.dof.aperture_fstop = 7.5
    direction = Vector((0.10, 0.0, 0.10)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    for name, location, energy, size, color in [
        ("Key", (-3.0, -4.0, 5.5), 520, 4.0, (1.0, 0.90, 0.82)),
        ("Fill", (4.5, -2.0, 2.5), 700, 3.5, (0.72, 0.84, 1.0)),
        ("Rim", (1.0, 2.0, 4.0), 320, 3.0, (1.0, 0.52, 0.36)),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        light.rotation_euler = (Vector((0, 0, 0.2)) - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 0, -1.24))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor.data.materials.append(solid_material("PreviewFloorMaterial", (0.028, 0.034, 0.052, 1), 0.28))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output / f"{prefix}_preview.png")
    scene.render.film_transparent = False
    scene.world.color = (0.045, 0.050, 0.070)
    scene.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)


def write_reference_manifest(
    fruit: str,
    output: Path,
    prd: dict,
    whole_entry: dict,
    cut_entry: dict,
    observed: list[str],
    inferred: list[str],
    derived: list[dict],
) -> None:
    manifest = {
        "fruit": fruit,
        "source_kind": prd["source_kind"],
        "source_id_or_url": prd["source_url"],
        "source_title": prd["source_title"],
        "source_revision": prd["source_revision"],
        "source_modified_time": prd["source_modified_time"],
        "extracted_image": f"{fruit}_reference.png",
        "extracted_source": whole_entry["path"],
        "sha256": whole_entry["sha256"],
        "supplemental_images": [
            {"path": f"{fruit}_reference_cut.png", "source": cut_entry["path"], "sha256": cut_entry["sha256"], "role": "cut"}
        ],
        "derived_assets": derived,
        "observed_features": observed,
        "inferred_features": inferred,
        "inspection_method": "pixel-level programmatic measurement (no vision model available in the generating environment); human-eye verification required on device",
    }
    (output / f"{fruit}_reference.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def write_metadata(fruit: str, output: Path, metadata: dict) -> None:
    defaults = {
        "schemaVersion": 1,
        "fruit": fruit,
        "referenceManifest": f"{fruit}_reference.json",
        "referenceSkin": f"{fruit}_reference.png",
        "referenceCutFace": f"{fruit}_reference_cut.png",
        "derivedSkinAlbedo": f"{fruit}_skin_basecolor.png",
        "derivedFleshAlbedo": f"{fruit}_flesh_basecolor.png",
        "modelingBasis": "PRD v1.0 extracted reference images; unseen back and 3D interior inferred",
        "units": "meters",
        "wholeEntity": f"{fruit}_whole",
        "leftHalfEntity": f"{fruit}_half_left",
        "rightHalfEntity": f"{fruit}_half_right",
        "cutPlane": {"normal": [1, 0, 0], "distance": 0},
        "pivot": [0, 0, 0],
        "runtimeStrategy": "swap-whole-for-authored-halves",
        "integrationStatus": "acceptance-lab-only; gameplay spawn/split still uses FruitVisualData 2D lathe",
    }
    defaults.update(metadata)
    (output / f"{fruit}.json").write_text(json.dumps(defaults, ensure_ascii=False, indent=2) + "\n")
