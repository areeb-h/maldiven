# ADR 0002: Mobile rendering and handcrafted island

Date: 2026-11-12. Status: Superseded for active world design by [ADR 0008](0008-station-layout-and-assets.md). Rendering diagnostics remain in ADR 0004.

## Context
The visual concept prioritises inviting scenery and smooth roaming on Android. Advanced desktop rendering features cannot be assumed available or affordable on mobile.

## Decision
Start with the Mobile renderer, fixed afternoon lighting, restrained shadows and lightweight shader water. Evaluate baked lighting on imported meshes with suitable UV2 data. Build terrain and modular scenery in Blender and export explicit GLB assets. Use simplified collision meshes, imported mesh LOD, visibility ranges and spatially partitioned MultiMesh foliage where appropriate.

Use Blender 5.2 LTS as the proposed art baseline after testing exports against the pinned Godot version. Compatibility rendering is a separately tested target, not an assumed equivalent fallback. Defer Terrain3D until native mesh terrain demonstrably blocks authoring; its platform notes identify Android caveats. Native SpringArm3D precedes optional camera addons.

## Consequences
Art direction must respect mobile shader and overdraw budgets. Lighting, water and foliage are validated together in one representative slice. Mesh terrain offers predictable deployment but less convenient terrain editing than a dedicated plugin. Generated concept art remains a direction, not a screenshot or performance promise.

## Sources
- https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html
- https://www.blender.org/download/lts/
- https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html
- https://github.com/TokisanGames/Terrain3D/blob/main/doc/docs/platforms.md
