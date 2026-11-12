# Maldiven

Offline Android-first island roaming game built with Godot and typed GDScript.

## Current prototype
A small procedural blockout with beach, cottages, palms, jetty, slope, stairs and camera-obstruction wall. Placeholder geometry and flat water establish movement; this is not the finished island or the concept art's visual quality.

Open `project.godot` in Godot Standard and run the main scene.

- Desktop: WASD to move, right-mouse drag to look, Space to jump, Escape to pause. Full movement input runs; Shift also selects run speed.
- Touch: left-side floating stick, right-side drag to look, bottom-right jump, top-right pause.
- Pause menu: resume or return to beach.
- Out-of-bounds recovery returns the explorer to spawn.

## Versions and validation
Godot 4.7.2 stable Standard, with matching export templates required for platform export. The engine binary was downloaded successfully after an initial connection timeout. Import, startup and movement smoke checks are run against 4.7.2.

Mobile renderer and built-in Jolt are configured. Use `godot --headless --path . --editor --import` to check imports. Use `godot --headless --path . --quit-after 120` for a basic startup smoke check. These checks cannot establish visual quality or Android performance.

## Plan
See [development plan](docs/plan.md) and [ADRs](docs/adr/README.md).

A debug-signed ARM64 Android APK has been exported and structurally verified; see [Android build and testing](docs/android-build.md). Next: install and test it on the phone, tune movement/camera, then replace the blockout with the designed island. Saves, sound, animated character art and graphics settings are not implemented yet.
