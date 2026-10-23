---
name: png-to-usdz-fruit-assets
description: Extract and ground fruit art references from a PRD, PNG, or photo, then turn them into reusable whole and pre-sliced USD/USDZ assets for RealityKit/tvOS. Use for FruitWave fruit modeling, Blender Python generation, cut-surface authoring, USDZ packaging, or device acceptance; do not use for generic image conversion or unrelated 3D assets.
---

# PNG to USDZ Fruit Assets

Build a real 3D fruit asset rather than extruding the PNG. Treat the approved image as shape, color, and texture reference; infer the unseen back and interior deliberately. A PRD title, prose description, existing procedural model, or remembered visual is not an image reference.

## Ground the Visual Reference First

Before modeling, read [references/reference-grounding.md](references/reference-grounding.md) and create the required reference manifest.

- When the user names a PRD, inspect the actual current revision and enumerate its embedded images. Export or render the PRD when necessary to verify that images are really present.
- In FruitWave, check `ArtSource/PRD-v1.0/manifest.json` before fetching or inventing a reference. It indexes the approved whole/cut PNG pairs under `ArtSource/PRD-v1.0/FruitReferences/<fruit>/` and records their source revision and hashes.
- Extract the exact fruit reference into the repository's source-art area without modifying the PRD. Preserve an unedited copy.
- Match the requested fruit by surrounding caption, section, alt text, and visual inspection. Do not select an image merely because the document title or prose mentions the fruit.
- If the PRD contains no image for the requested fruit, stop before modeling and report that precise mismatch. Ask for the missing reference image or an explicit decision to use a substitute. Do not silently fall back to procedural colors, web search, or a different fruit.
- Existing generated textures and models may be engineering baselines, but they are not evidence that the PRD was followed.

## Route the Fruit

- Prefer Blender Python parameterization for regular fruit: apple, orange, lemon, melon, peach, plum, pear, cherry, grape, coconut, or similarly describable forms.
- Use an open image-to-3D model only as an optional starting mesh for irregular surfaces such as pineapple or strawberry. Blender remains the source of truth for cleanup, topology, materials, cut geometry, optimization, and export.
- If a clean parameterization is practical, do not introduce a hosted paid generator merely for speed.
- For an MVP, author a whole model and two pre-cut halves. Do not implement runtime mesh Boolean cutting unless the user explicitly requests it.

## Workflow

1. Resolve the PRD revision or supplied image, extract the exact reference, write its manifest, and visually inspect it before touching geometry.
2. Record the fruit silhouette, asymmetry, characteristic surface details, palette, gloss/roughness cues, stem/leaves, and any visible interior. Separate observed facts from inferred back/interior details.
3. Start with one fruit and produce it end to end before batching variants.
4. In Blender Python, generate or clean the mesh, apply transforms, keep deterministic object names, create UVs where needed, and author PBR-friendly materials with controlled roughness and highlights. Use the approved reference to drive shape and material decisions; do not substitute generic sinusoidal color noise for observed markings.
5. Produce separate authored assets for the intact fruit and its two sliced halves. Include interior flesh, core/seeds when visible, stem/leaves when characteristic, and origins suitable for separation animation.
6. Export USDZ with embedded textures. Keep the `.blend`, preview render, reference manifest, comparison render, and source textures in the repository; ship only runtime files in the app bundle unless the project specifies otherwise.
7. Validate structure and materials before integrating. Then compare the reference and a matched-angle render side by side, load in RealityKit, rotate through 360 degrees, toggle whole/sliced states, and record actual device FPS and memory.
8. Fix visual defects found on device, especially silhouette mismatch, generic or repeated markings, overexposure, excessive gloss, obvious texture tiling, clipping, wrong scale, missing cut faces, reversed normals, or overlapping halves.

When working in the FruitWave repository, read [references/fruitwave-apple-template.md](references/fruitwave-apple-template.md) and adapt the existing apple generator rather than starting from scratch. For the exact file contract and acceptance gates, read [references/deliverables.md](references/deliverables.md).

## Invariants

- Preserve consistent units, axes, scale, naming, and pivots across every fruit.
- Keep whole and sliced files independently loadable; never rely on hidden editor state.
- Use stable semantic names for the slice roots: `<fruit>_half_left` and `<fruit>_half_right`.
- A low-confidence or guessed interior must be called out in the handoff instead of presented as source-accurate.
- Never claim PRD fidelity unless the manifest identifies the exact extracted image and the handoff includes a reference-versus-render comparison.
- Do not overwrite an existing manually refined asset without first inspecting it and preserving intentional work.
- Do not claim completion from Blender preview alone. USD validation and RealityKit rendering are required for a tvOS deliverable.

## Handoff

Report the PRD/file source and revision, extracted reference path, observed-versus-inferred features, generated files, modeling route, comparison result, validation results, measured device performance, visual limitations, and whether the new fruit is only in the acceptance lab or already wired into gameplay.
