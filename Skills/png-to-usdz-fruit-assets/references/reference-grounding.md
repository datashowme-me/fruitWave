# Reference Grounding Contract

Use this contract whenever a PRD, design document, deck, PDF, or web page is named as the visual source.

## Acquisition

1. Read metadata for the exact source and record its stable ID/URL, title, and current revision or modification time.
2. Inspect the source structure for embedded or positioned images. When the source API omits visual layout, export/render it and verify every page visually or enumerate PDF image objects.
3. Match the requested fruit to a specific image using nearby caption/section context plus visual inspection.
4. Save the unedited extracted image under the project's source-art convention. Do not crop, recolor, denoise, or upscale the only preserved copy.

If no matching image exists, stop before Blender generation. Report the fruits/images that are actually present and request the missing image or explicit substitute authorization.

## Manifest

Store `<fruit>_reference.json` beside the source asset with at least:

```json
{
  "fruit": "apple",
  "source_kind": "google_doc|pdf|png|photo|other",
  "source_id_or_url": "...",
  "source_title": "...",
  "source_revision": "...",
  "extracted_image": "relative/path/to/apple_reference.png",
  "source_location": "tab/page/section/caption",
  "sha256": "...",
  "observed_features": ["..."],
  "inferred_features": ["unseen back", "interior when not shown"]
}
```

The manifest must point to a real, readable image and its SHA-256 must match before generation proceeds.

## Visual Acceptance

Create a matched-angle comparison containing the untouched reference and the Blender or RealityKit render. Evaluate at minimum:

- outer silhouette and asymmetry;
- dominant and secondary colors;
- marking size, density, direction, and randomness;
- material response, including roughness, waxiness, translucency, and wet cut flesh;
- characteristic stem, leaf, crown, calyx, core, pit, or seeds;
- plausibility through 360 degrees, while labeling geometry not visible in the source as inferred.

Passing USD validation does not imply visual acceptance. Do not call the asset PRD-accurate until the comparison passes and the physical Apple TV render has been inspected.
