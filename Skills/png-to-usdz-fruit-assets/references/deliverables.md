# Deliverable Contract

For a fruit slug `<fruit>`, keep source artifacts together under the project's asset-source convention and deliver at least:

```text
<fruit>.blend
<fruit>_reference.png
<fruit>_reference.json
<fruit>_whole.usdz
<fruit>_sliced.usdz
<fruit>.json
<fruit>_preview.png
<fruit>_comparison.png
```

Source textures may accompany the `.blend`. Runtime packaging should normally include only both USDZ files and metadata.

The reference image and manifest are required when the user names a visual source such as a PRD. They remain source artifacts and must not be shipped in the app bundle unless separately requested.

## Required scene structure

- `<fruit>_whole.usdz` has one stable root representing the intact fruit.
- `<fruit>_sliced.usdz` contains independently transformable `<fruit>_half_left` and `<fruit>_half_right` roots.
- Characteristic secondary geometry such as stem, leaf, crown, peel, core, pit, or seeds uses descriptive stable names.
- Both files use matching scale, orientation, materials, and origin conventions.

## Metadata minimum

The JSON should record:

- asset and fruit identifiers;
- generator version or script path;
- units and nominal dimensions;
- whole and sliced filenames;
- root/entity names used by runtime code;
- intended pivot behavior;
- texture/material notes;
- polygon or mesh complexity summary when available.

## Automated checks

Run `xcrun usdchecker` against both USDZ files. Both must end in `Success!`.

Inspect the USDA representation with `xcrun usdcat` when verifying root names, materials, or hierarchy. Confirm the two half names rather than assuming Blender collection names survived export.

Build the app after resource changes and inspect the final `.app` bundle to confirm the intended USDZ and JSON files are present while `.blend` and preview/source textures are excluded.

## Visual acceptance

Verify on the target Apple TV, not only in Blender:

- the whole fruit remains credible through a full rotation;
- the silhouette is recognizable from multiple angles;
- materials are neither flat nor overexposed/plastic;
- texture seams, pixel-like speckles, and tiling are not distracting;
- the cut surface has flesh plus characteristic core, pit, or seeds;
- both halves are visible and can separate without overlap;
- the model fits the gameplay camera and does not clip UI;
- sustained FPS and memory are recorded under the target scene load.

## Completion boundary

Asset-pipeline completion means the authored files pass structure, export, bundle, and RealityKit acceptance. It does not mean gameplay integration is complete. State separately whether spawn logic, collision replacement, split physics, juice particles, sound, scoring, and pooling use the new asset.
