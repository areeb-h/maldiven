# Implementation status

Updated 2026-11-12.

## Movement foundation
- Godot 4.7.2 stable downloaded and executed successfully. Earlier download timeout resolved on retry.
- Procedural blockout, capsule explorer, camera-relative movement, run, jump buffer/coyote time, spring-arm camera collision, independent touch pointers, pause/resume and spawn recovery implemented.
- Headless editor import and runtime smoke tests passed on 4.7.2. Automated tests cover floor contact, movement, stopping, jump, recovery, three-finger movement/look/jump and pause.
- Android APK export now succeeds with the official 4.7.2 templates. Signature verification, ARM64 packaging, absence of requested permissions and 16 KB ZIP alignment checks passed. Physical APK installation, touch behaviour, GPU rendering/visual inspection and device performance remain unverified.
- Character animation, detailed terrain, polished water, sound, settings and saves remain planned.

Run: `godot --headless --path . --script res://tests/movement_smoke.gd`.

## Resource pass and screenshot follow-up
- Eight original GLBs now replace the blockout geometry. Reproducible Blender generator, collision proxies, shared materials and Cycles previews supplied.
- GLB import/collision tests and movement tests pass.
- 2x MSAA applied as a candidate workaround for reported horizontal Vulkan bands; Compatibility diagnostic builder supplied. Neither workaround is verified on the affected phone yet.
- Touch HUD removes desktop help; wide-screen aspect expands.
- The existing 0.1.0 APK predates this resource pass. Build a new APK before expecting these changes on the phone.
- See docs/resources.md for resource counts, preview limitations and rebuild instructions.
