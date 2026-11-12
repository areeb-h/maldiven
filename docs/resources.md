# First original resource pack

Created 2026-11-12. Eight original GLB resources generated from editable Blender Python source. No external models, texture downloads, licences or paid tools are required. Tested with the available Blender 4.3.2 and Godot 4.7.2, rather than the proposed Blender 5.2 art baseline.

| Resource | Details | Exported triangles including collision proxies |
| --- | --- | ---: |
| Cottage | Pitched roof, tile ridges, porch posts, framed windows, door, planters | 2,058 |
| Palm | Curved segmented trunk, rings, nine fronds with individual mesh leaflets | 1,968 |
| Coastal rocks | Three faceted rocks with collision | 240 |
| Jetty | Planks, supports, posts and sagging rope rails | 2,292 |
| Grass tuft | Solid triangular blades; no alpha textures | 9 |
| Bench | Planked seat/back, legs and simplified collision | 352 |
| Island terrain | Continuous ring mesh, sand/grass materials, shoreline and surface-conforming path | 1,454 |
| Explorer | Stylised human, hat, clothing, separate limb pivots | 972 |

All eight GLBs total approximately 630 KiB. Counts describe resources, not the total scene draw calls or device performance. Shared palettes and static meshes merged by material reduce scene fragmentation. Character animation currently uses simple procedural limb swings, not a production animation rig.

## Rebuild

```bash
blender --background --factory-startup --python tools/generate_assets.py
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/assets_smoke.gd
godot --headless --path . --script res://tests/movement_smoke.gd
```

GLBs and import settings live under assets/models. Generator outputs Blender source previews under assets/previews; .gdignore prevents importing the preview scenes into the game. GLBs use metres, Y-up in Godot. Model front is +Z; controller rotates it toward movement. Solids use Godot's -col / -colonly import naming for static collision. Cottage interiors remain closed; porch/jetty traversal still needs device playtesting.

## Preview limits

The delivered overview and close-up are Cycles renders of these exact resource meshes, not image-generated concept art or Godot screenshots. They show geometry/material composition; Android lighting, shadows and water will differ. The scene remains an early stylised art pass. Water is a flat material, buildings share one design, palms are static and the map is deliberately sparse. Further art work should follow resource review and device validation.

## Screenshot follow-up

Two horizontal corruption bands were reported on the Android prototype. A similar confirmed Godot/Vulkan issue appears in https://github.com/godotengine/godot/issues/115217 . The report includes OnePlus devices; later comments discuss Adreno render-pass/tile behaviour and workarounds including 2x MSAA and Compatibility rendering. This is a plausible diagnosis, not confirmation of the user's exact GPU/driver fault.

The Mobile project now uses 2x MSAA (msaa_3d=1). This also reduces jagged edges. The workaround must be verified on the affected phone. If bands remain, generate a separate Compatibility test with tools/build_android.py; it uses a separate package ID and can be installed side by side. It is a diagnostic alternative, not a claim that all graphical faults are solved.

```bash
python3 tools/build_android.py --godot /path/to/godot --renderer mobile
python3 tools/build_android.py --godot /path/to/godot --renderer compatibility
```

Mobile HUD omits desktop keyboard instructions. Stretch aspect expands for wide screens. Other reported bugs need concrete reproduction steps; this change does not claim to resolve unspecified gameplay bugs.
