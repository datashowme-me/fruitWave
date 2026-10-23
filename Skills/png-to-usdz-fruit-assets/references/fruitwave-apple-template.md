# FruitWave Apple Reference

Use the current apple implementation as the baseline when adding another fruit to FruitWave:

- Approved PRD reference catalog: `ArtSource/PRD-v1.0/manifest.json`
- Approved per-fruit PNGs: `ArtSource/PRD-v1.0/FruitReferences/<fruit>/whole.png` and `cut.png`
- Generator: `Tools/Blender/generate_apple.py`
- Source and exports: `FruitWaveApp/Resources/Models/Apple/`
- RealityKit acceptance view: `FruitWaveApp/UI/AppleAssetLabView.swift`
- Resource inclusion/exclusion: `project.yml`

## Generation

Run from the repository root:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python Tools/Blender/generate_apple.py
```

Create a new generator per fruit or extract shared helpers only when at least two generators genuinely share the behavior. Preserve deterministic output and print an explicit success marker only after previews, `.blend`, metadata, and both USDZ files exist.

## Adaptation checklist

- Replace the silhouette and characteristic geometry; do not merely recolor the apple.
- Author the real interior structure for that fruit.
- Tune roughness, coat, texture scale, lights, and camera using Apple TV screenshots.
- Update root and half names everywhere the acceptance/runtime loader depends on them.
- Add the new runtime resources without shipping `.blend`, preview PNGs, or standalone source textures.
- Start by loading the new fruit in an isolated RealityKit acceptance surface. Integrate into live gameplay only after it passes.

The apple implementation demonstrated that Blender preview quality can differ materially from RealityKit. In particular, verify light intensity, model scale, texture speckle size, gloss, and half separation on the physical Apple TV.
