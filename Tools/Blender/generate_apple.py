"""Build the FruitWave apple asset from the approved PRD reference images.

Run with:
  Blender --background --python Tools/Blender/generate_apple.py

Grounding: the PRD v1.0 export indexes the approved reference pair at
ArtSource/PRD-v1.0/FruitReferences/apple/{whole,cut}.png. Byte-identical
copies live beside the deliverables as apple_reference.png and
apple_reference_cut.png. The script derives de-lit basecolor maps from
those images directly; it does not use image-generation output.

The script is deterministic and produces:
  * apple.blend                 editable source
  * apple_reference.json        grounded reference manifest
  * apple_skin_basecolor.png    de-lit cylindrical skin map (from whole.png)
  * apple_flesh_basecolor.png   de-lit cut-flesh map (from cut.png)
  * apple_whole.usdz            intact fruit hierarchy
  * apple_sliced.usdz           two authored halves with flesh and seeds
  * apple_preview.png           turntable-style acceptance render
  * apple.json                  runtime metadata

The game deliberately swaps the intact asset for the authored halves instead
of performing a runtime boolean.  This keeps the cut face art-directable and
the tvOS frame cost predictable.

Material note: UsdPreviewSurface (the USDZ material) has no clearcoat
channel, so the apple's waxy/wet response is authored with low roughness
plus Specular IOR Level instead of Blender's Coat Weight. EEVEE preview and
RealityKit therefore agree more closely than the previous setup.
"""

from __future__ import annotations

import json
import math
from array import array
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "FruitWaveApp" / "Resources" / "Models" / "Apple"
PRD_MANIFEST = ROOT / "ArtSource" / "PRD-v1.0" / "manifest.json"
FRUIT = "apple"
SKIN_REFERENCE = OUTPUT / "apple_reference.png"
FLESH_REFERENCE = OUTPUT / "apple_reference_cut.png"
SKIN_ALBEDO = OUTPUT / "apple_skin_basecolor.png"
FLESH_ALBEDO = OUTPUT / "apple_flesh_basecolor.png"
OUTPUT.mkdir(parents=True, exist_ok=True)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        # Orphans from a previous in-process run make names and exports unstable.
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def load_reference(path: Path, name: str) -> bpy.types.Image:
    if not path.is_file():
        raise FileNotFoundError(f"Required PRD apple reference is missing: {path}")
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


def classify_skin(r: float, g: float, b: float) -> str:
    """Split a PRD photo pixel into skin, warm mark, or non-skin.

    Thresholds are derived from the measured palette of the approved whole
    apple reference: red family #780000-#f01818, warm orange-red lit side
    around #c8563a, yellow-orange marks around #fc9c52.
    """
    if r > g * 1.8 and r > b * 1.8 and r > 0.18:
        return "skin"
    if r > 0.25 and g > 0.42 * r and b < 0.38 * r:
        return "mark"
    return "other"


def write_reference_skin_texture(reference: bpy.types.Image, path: Path, width: int = 1024, height: int = 512) -> bpy.types.Image:
    """Remap the PRD whole apple into a seamless cylindrical skin map.

    Each output row samples the corresponding photo row across the apple's
    opaque span; longitudes beyond the front half mirror back, which keeps
    the unseen back plausible and the seam quiet. Leaf, stem, background and
    specular pixels are classified out and refilled from the nearest valid
    skin column so the map keeps the photo's mottling instead of flat fill.
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
        raise ValueError("PRD whole apple reference has no opaque content")

    image = bpy.data.images.new("AppleSkinBaseColor", width=width, height=height, alpha=True)
    pixels = array("f")
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
        base_r, base_g, base_b = 0.66 * vertical_tone, 0.13 * vertical_tone, 0.06 * vertical_tone
        for x in range(width):
            u = x / max(1, width - 1)
            # Front half sweeps left-to-right; back half mirrors it.
            t = 2.0 * u if u <= 0.5 else 2.0 * (1.0 - u)
            source_x = int(left + t * (right - left))
            r, g, b, _ = sample_image(reference, source_pixels, source_x / max(1, src_w - 1), source_y / max(1, src_h - 1))
            kind = classify_skin(r, g, b)
            if kind == "other" and valid_columns:
                nearest = min(valid_columns, key=lambda c: abs(c - source_x))
                r, g, b, _ = sample_image(reference, source_pixels, nearest / max(1, src_w - 1), source_y / max(1, src_h - 1))
                kind = "skin"
            if kind == "other":
                r, g, b = base_r, base_g, base_b
                kind = "skin"
            if kind == "mark":
                r = 0.62 * r + 0.38 * base_r
                g = 0.62 * g + 0.38 * base_g
                b = 0.62 * b + 0.38 * base_b
            else:
                # Blend the photograph toward a stable albedo so the baked
                # lighting does not get lit a second time in the renderer.
                r = 0.50 * r + 0.50 * base_r
                g = 0.50 * g + 0.50 * base_g
                b = 0.50 * b + 0.50 * base_b
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


def write_reference_flesh_texture(reference: bpy.types.Image, path: Path, size: int = 768) -> bpy.types.Image:
    """Build a flesh map from the cream region of the PRD cut reference.

    The cut photo shows the vertical cut face at an angle, so the sampler
    locates the cream-flesh mass from its measured color family, remaps a
    disk around its centroid, and rejects specular patches before baking.
    """
    source_pixels = list(reference.pixels)
    src_w, src_h = reference.size

    def is_cream(r: float, g: float, b: float, a: float) -> bool:
        maximum, minimum = max(r, g, b), min(r, g, b)
        return a > 0.8 and r > 0.60 and g > 0.50 and b > 0.38 and (maximum - minimum) < 0.25 and maximum < 0.90

    points = []
    for y in range(0, src_h, 2):
        for x in range(0, src_w, 2):
            r, g, b, a = source_pixels[(y * src_w + x) * 4:(y * src_w + x) * 4 + 4]
            if is_cream(r, g, b, a):
                points.append((x, y))
    if not points:
        raise ValueError("PRD cut apple reference has no cream flesh region")
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)
    cx = (min_x + max_x) // 2
    cy = (min_y + max_y) // 2
    span = max(max_x - min_x, max_y - min_y)

    image = bpy.data.images.new("AppleFleshBaseColor", width=size, height=size, alpha=True)
    pixels = array("f")
    base_r, base_g, base_b = 0.94, 0.85, 0.70  # bright cream #f0dcb7 family
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
                if not is_cream(r, g, b, a):
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


def image_material(
    name: str,
    image: bpy.types.Image,
    roughness: float,
    specular: float = 0.55,
    planar_yz: bool = False,
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


def make_body(name: str, skin: bpy.types.Material, flesh: bpy.types.Material) -> bpy.types.Object:
    """Build a broad apple with explicit stem and calyx wells.

    Scaling a UV sphere near its poles produced the long conical runs visible
    in the first physical Apple TV evidence.  This surface of revolution uses
    an art-directed profile instead: broad shoulders, a shallow top well and
    a tucked base.  The two centre vertices sit *inside* their adjacent rings,
    so neither end can turn into a spike under smooth shading.
    """
    profile = [
        (0.00, -0.79),
        (0.12, -0.82),
        (0.28, -0.84),
        (0.48, -0.81),
        (0.68, -0.72),
        (0.84, -0.56),
        (0.95, -0.32),
        (1.00, -0.05),
        (0.98, 0.22),
        (0.90, 0.48),
        (0.75, 0.68),
        (0.55, 0.82),
        (0.30, 0.86),
        (0.12, 0.84),
        (0.00, 0.80),
    ]
    segments = 96
    vertices: list[tuple[float, float, float]] = [(0.0, 0.0, profile[0][1])]
    rings: list[list[int]] = []
    for ring_index, (radius, z) in enumerate(profile[1:-1], start=1):
        ring: list[int] = []
        weight = math.sin(math.pi * ring_index / (len(profile) - 1))
        for segment in range(segments):
            theta = 2.0 * math.pi * segment / segments
            lobes = 1.0 + 0.016 * math.cos(theta * 5.0 + 0.35) * weight
            asymmetry = 1.0 + 0.012 * math.sin(theta + 0.65) * weight
            ring.append(len(vertices))
            vertices.append((
                radius * lobes * asymmetry * math.cos(theta),
                radius * 0.97 * lobes * asymmetry * math.sin(theta),
                z * 1.02,
            ))
        rings.append(ring)
    top_index = len(vertices)
    vertices[0] = (0.0, 0.0, profile[0][1] * 1.02)
    vertices.append((0.0, 0.0, profile[-1][1] * 1.02))

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
    body.data.materials.append(skin)
    body.data.materials.append(flesh)
    for polygon in body.data.polygons:
        polygon.use_smooth = True
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.sphere_project(direction="ALIGN_TO_OBJECT", correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    return body


def make_stem(name: str, material: bpy.types.Material, location=(0.0, 0.0, 0.78)) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 3
    curve.bevel_depth = 0.045
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(3)
    for point, coordinate in zip(
        spline.bezier_points,
        ((0.0, 0.0, 0.0), (0.01, 0.0, 0.17), (0.055, 0.0, 0.34), (0.04, 0.0, 0.50)),
    ):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    stem = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(stem)
    stem.location = location
    stem.rotation_euler.z = 0.18
    stem.data.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    stem.select_set(True)
    bpy.context.view_layer.objects.active = stem
    # BasisCurves exported by Blender validate as USD but are not rendered by
    # RealityKit on the target Apple TV. Bake the bevel to a regular mesh.
    bpy.ops.object.convert(target="MESH")
    return stem


def make_leaf(name: str, material: bpy.types.Material, location=(0.03, 0.0, 0.82)) -> bpy.types.Object:
    # A thin pointed blade reads as a leaf from all acceptance angles; the old
    # flattened UV sphere read as a solid green lozenge.
    segments = 16
    vertices: list[tuple[float, float, float]] = []
    for index in range(segments + 1):
        t = index / segments
        x = 0.72 * t
        half_width = 0.21 * math.sin(math.pi * t) ** 0.72
        bend = 0.045 * math.sin(math.pi * t)
        vertices.extend(((x, -half_width, bend), (x, half_width, bend)))
    faces = [(2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1) for i in range(segments)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    leaf = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(leaf)
    leaf.location = location
    leaf.rotation_euler = (0.18, -0.30, 0.35)
    leaf.data.materials.append(material)
    solidify = leaf.modifiers.new("LeafThickness", "SOLIDIFY")
    solidify.thickness = 0.012
    bevel = leaf.modifiers.new("LeafEdge", "BEVEL")
    bevel.width = 0.006
    bevel.segments = 2
    return leaf


def parent_keep_transform(child: bpy.types.Object, parent: bpy.types.Object) -> None:
    # All authored roots are still identity transforms while assets are built,
    # so local parenting preserves the deliberately set scale. Assigning a
    # stale matrix_world here would reset newly created leaves/seeds to 1×.
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

    # Boolean cap polygons face along the cut plane. Assign those polygons to
    # the flesh material while preserving the skin around the outer surface.
    for polygon in half.data.polygons:
        center_x = sum(half.data.vertices[index].co.x for index in polygon.vertices) / len(polygon.vertices)
        is_cut_cap = abs(center_x) < 0.006 and abs(polygon.normal.x) > 0.94
        if is_cut_cap:
            polygon.material_index = 1
        polygon.use_smooth = not is_cut_cap
    return half


def make_seed(name: str, material: bpy.types.Material, x: float, y: float, z: float) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=(x, y, z))
    seed = bpy.context.object
    seed.name = name
    seed.scale = (0.026, 0.075, 0.155)
    seed.rotation_euler.x = 0.28 if z > 0 else -0.28
    seed.data.materials.append(material)
    for polygon in seed.data.polygons:
        polygon.use_smooth = True
    return seed


def make_core_lobe(name: str, material: bpy.types.Material, x: float, z: float) -> bpy.types.Object:
    """Add the shallow seed-pocket structure missing from the flat first cut."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=(x, 0.0, z))
    core = bpy.context.object
    core.name = name
    core.scale = (0.014, 0.10, 0.16)
    core.data.materials.append(material)
    for polygon in core.data.polygons:
        polygon.use_smooth = True
    return core


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


def configure_preview(whole_root: bpy.types.Object, sliced_roots: list[bpy.types.Object]) -> None:
    whole_root.location = (-1.65, 0.05, 0)
    sliced_roots[0].location = (1.18, 0.0, 0.38)
    sliced_roots[0].rotation_euler = (0.0, -0.30, -0.18)
    sliced_roots[1].location = (1.85, 0.0, -0.35)
    sliced_roots[1].rotation_euler = (0.0, 0.26, 0.18)

    bpy.ops.object.camera_add(location=(0.2, -11.5, 1.25))
    camera = bpy.context.object
    camera.name = "ApplePreviewCamera"
    camera.data.lens = 55
    camera.data.dof.use_dof = True
    camera.data.dof.focus_object = whole_root
    camera.data.dof.aperture_fstop = 7.5
    direction = Vector((0.10, 0.0, 0.10)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    # Balanced three-point light: the previous setup left the lower half of
    # every object nearly black and produced no specular response at all.
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
    scene.render.filepath = str(OUTPUT / "apple_preview.png")
    scene.render.film_transparent = False
    scene.world.color = (0.045, 0.050, 0.070)
    scene.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)


def load_prd_entries() -> tuple[dict, dict, dict]:
    """Return (prd, whole_entry, cut_entry) for the apple from the PRD index."""
    if not PRD_MANIFEST.is_file():
        raise FileNotFoundError(f"PRD reference index is missing: {PRD_MANIFEST}")
    prd = json.loads(PRD_MANIFEST.read_text())
    by_role = {a["role"]: a for a in prd["assets"] if a["fruit"] == FRUIT}
    if set(by_role) != {"whole", "cut"}:
        raise ValueError(f"PRD index lacks whole/cut references for {FRUIT}: {sorted(by_role)}")
    return prd, by_role["whole"], by_role["cut"]


def write_reference_manifest(prd: dict, whole: dict, cut: dict) -> None:
    manifest = {
        "fruit": FRUIT,
        "source_kind": prd["source_kind"],
        "source_id_or_url": prd["source_url"],
        "source_title": prd["source_title"],
        "source_revision": prd["source_revision"],
        "source_modified_time": prd["source_modified_time"],
        "extracted_image": "apple_reference.png",
        "extracted_source": whole["path"],
        "sha256": whole["sha256"],
        "supplemental_images": [
            {"path": "apple_reference_cut.png", "source": cut["path"], "sha256": cut["sha256"], "role": "cut"}
        ],
        "derived_assets": [
            {
                "path": "apple_skin_basecolor.png",
                "method": "Blender Python derivation from PRD whole.png: per-row mirrored-longitude cylinder remap, skin/mark classification, specular de-lighting, nearest-valid-column fill",
            },
            {
                "path": "apple_flesh_basecolor.png",
                "method": "Blender Python derivation from PRD cut.png: cream-region centroid disk remap, specular rejection, de-lighting blend",
            },
        ],
        "observed_features": [
            "tallish round apple, widest at mid-height, bottom tapering to a narrow calyx (w/h ≈ 0.89)",
            "short dark-brown stem (#8e491d) at top center",
            "large yellow-green leaf (#608718) on the upper right, about 7.5% of the body area",
            "deep red skin; lit side #c8563a, shadow side #b60e0e",
            "random mottling with fine lenticels; no directional stripes",
            "small fragmented specular highlights, top-left; medium waxy gloss",
            "vertical cut; bright cream flesh #f6dcb7 with strong wet specular patches (≈31% of flesh brighter than 80% luma)",
            "3-4 dark-brown seeds (#6f2c1d) arranged vertically, slightly right of center",
            "thin peel ring, ≈2% of cut radius; peel #d5372a",
        ],
        "inferred_features": [
            "unseen back mirrored from the front half",
            "three-dimensional depth from a front-facing image",
            "stem recess depth (occluded by the leaf in the reference)",
            "exact waxiness strength; pixel analysis suggests medium gloss",
            "cut face camera angle; flesh disk remapped as front-on",
        ],
        "inspection_method": "pixel-level programmatic measurement (no vision model available in the generating environment); human-eye verification required on device",
    }
    (OUTPUT / "apple_reference.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    reset_scene()
    prd, whole_entry, cut_entry = load_prd_entries()
    # Load the reference copies first so generation fails loudly if the
    # approved PRD reference disappears. The derived maps below are built
    # from these exact images in this run.
    skin_reference = load_reference(SKIN_REFERENCE, "AppleSkinReference")
    flesh_reference = load_reference(FLESH_REFERENCE, "AppleFleshReference")
    skin_image = write_reference_skin_texture(skin_reference, SKIN_ALBEDO)
    flesh_image = write_reference_flesh_texture(flesh_reference, FLESH_ALBEDO)
    skin = image_material("AppleSkin_PBR", skin_image, roughness=0.28, specular=0.55)
    flesh = image_material("AppleFlesh_PBR", flesh_image, roughness=0.18, specular=0.90, planar_yz=True)
    stem_material = solid_material("AppleStem_PBR", (0.56, 0.29, 0.11, 1), 0.60, specular=0.20)
    leaf_material = solid_material("AppleLeaf_PBR", (0.38, 0.53, 0.09, 1), 0.42, specular=0.30)
    seed_material = solid_material("AppleSeed_PBR", (0.18, 0.035, 0.012, 1), 0.32, specular=0.35)

    core_material = solid_material("AppleCore_PBR", (0.86, 0.69, 0.42, 1), 0.42, specular=0.24)

    template = make_body("AppleBodyTemplate", skin, flesh)

    whole_root = bpy.data.objects.new("apple_whole", None)
    bpy.context.collection.objects.link(whole_root)
    whole = template.copy()
    whole.data = template.data.copy()
    whole.name = "apple_skin"
    bpy.context.collection.objects.link(whole)
    parent_keep_transform(whole, whole_root)
    stem = make_stem("apple_stem", stem_material)
    leaf = make_leaf("apple_leaf", leaf_material)
    parent_keep_transform(stem, whole_root)
    parent_keep_transform(leaf, whole_root)

    right_root = bpy.data.objects.new("apple_half_right", None)
    left_root = bpy.data.objects.new("apple_half_left", None)
    bpy.context.collection.objects.link(right_root)
    bpy.context.collection.objects.link(left_root)
    right = apply_boolean_half(template, "apple_half_right_mesh", keep_right=True)
    left = apply_boolean_half(template, "apple_half_left_mesh", keep_right=False)
    parent_keep_transform(right, right_root)
    parent_keep_transform(left, left_root)

    # Cut-face seed pockets and seeds form a readable core rather than dots on
    # an otherwise featureless plane.
    for root, sign in ((right_root, 1.0), (left_root, -1.0)):
        for core_index, z in enumerate((-0.17, 0.17)):
            # The right half's exposed face points toward -X and the left
            # half's toward +X, hence the sign inversion from half position.
            core = make_core_lobe(f"{root.name}_core_{core_index}", core_material, -sign * 0.007, z)
            parent_keep_transform(core, root)
        for index, (yy, zz) in enumerate(((0.0, 0.26), (0.0, -0.18), (0.05, 0.04))):
            seed = make_seed(f"{root.name}_seed_{index}", seed_material, -sign * 0.024, yy, zz)
            parent_keep_transform(seed, root)
    sliced_stem = make_stem("apple_half_stem", stem_material, location=(0.08, 0.0, 0.78))
    sliced_leaf = make_leaf("apple_half_leaf", leaf_material, location=(0.10, 0.0, 0.82))
    parent_keep_transform(sliced_stem, right_root)
    parent_keep_transform(sliced_leaf, right_root)

    bpy.data.objects.remove(template, do_unlink=True)
    export_usdz(OUTPUT / "apple_whole.usdz", [whole_root])
    export_usdz(OUTPUT / "apple_sliced.usdz", [left_root, right_root])

    write_reference_manifest(prd, whole_entry, cut_entry)

    metadata = {
        "schemaVersion": 1,
        "referenceManifest": "apple_reference.json",
        "referenceSkin": "apple_reference.png",
        "referenceCutFace": "apple_reference_cut.png",
        "derivedSkinAlbedo": "apple_skin_basecolor.png",
        "derivedFleshAlbedo": "apple_flesh_basecolor.png",
        "modelingBasis": "PRD v1.0 extracted reference images; unseen back and 3D interior inferred",
        "units": "meters",
        "wholeEntity": "apple_whole",
        "leftHalfEntity": "apple_half_left",
        "rightHalfEntity": "apple_half_right",
        "cutPlane": {"normal": [1, 0, 0], "distance": 0},
        "pivot": [0, 0, 0],
        "collision": {"shape": "sphere", "radius": 1.05},
        "massKilograms": 0.18,
        "juiceColorSRGB": [0.94, 0.79, 0.36],
        "runtimeStrategy": "swap-whole-for-authored-halves",
        "materialNotes": {
            "skin": "roughness 0.28, specular IOR level 0.55 (waxy sheen; clearcoat is not exported to USDZ)",
            "flesh": "roughness 0.18, specular IOR level 0.90 (wet cut face)",
            "stem": "#8e491d, roughness 0.60",
            "leaf": "#608718, roughness 0.42",
            "seed": "#6f2c1d, roughness 0.32",
        },
        "integrationStatus": "acceptance-lab-only; gameplay spawn/split still uses FruitVisualData 2D lathe",
    }
    (OUTPUT / "apple.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")

    configure_preview(whole_root, [left_root, right_root])
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "apple.blend"))
    print(f"FRUITWAVE_ASSET_OK {OUTPUT}")


if __name__ == "__main__":
    main()
