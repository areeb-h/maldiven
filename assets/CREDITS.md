# Asset credits

## Station textures (`assets/textures/`)

All station textures are original and generated procedurally by
`scripts/art/texture_gen.gd` (FastNoiseLite + hand-written height/colour rules).
No third-party textures, HDRIs or models are used. CC0 sources (ambientCG,
Poly Haven) were not reachable from the build environment, so nothing was
downloaded.

| File | Contents | Source | Licence |
| --- | --- | --- | --- |
| `floor_plate_{albedo,normal,orm}.png` | 2 m tile: four bevelled diamond-tread plates, bolts, grime | generated (`texture_gen.gd`) | project-original |
| `wall_panel_{albedo,normal,orm}.png` | 2 m tile: two bevelled painted panels, screws, vent, edge chips, streaks | generated (`texture_gen.gd`) | project-original |
| `metal_paint_{albedo,normal,orm}.png` | 1 m tile: painted metal with scratches (props, triplanar) | generated (`texture_gen.gd`) | project-original |
| `grime_decal.png` | RGBA smudge for floor `Decal` nodes | generated (`texture_gen.gd`) | project-original |

ORM packing: R = ambient occlusion, G = roughness, B = metallic.
Regenerate with
`godot --headless --path . --script res://scripts/art/texture_gen.gd`, then
re-import (`--headless --editor --import --quit`).

## Sky, planet, station geometry

Starfield/nebula sky, gas giant, moon and all station geometry are procedural
shaders and meshes in `scripts/art/` and `scripts/station_builder.gd`.
