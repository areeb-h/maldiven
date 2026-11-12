# Maldiven

Android-first Godot project. **Active direction: Drift Station**, a proposed 3D social-survival game for friends with voice, cooperation, hidden objectives and recoverable conflict. The current executable is still the island 0.2.0 prototype.

## Planning
- [Active plan](docs/plan.md)
- [Game design and station layout](docs/game-design/drift-station.md)
- [Roadmap and milestone gates](docs/roadmap.md)
- [Psychology and game-design research](docs/research/psychology-and-game-design.md)
- [Playtest protocol](docs/game-design/playtesting.md)
- [Full production blueprint](docs/blueprint/vision-and-experience.md)
- [Implementation backlog and expansion ladder](docs/blueprint/implementation-backlog.md)
- [Technical contracts and failures](docs/blueprint/interaction-contracts.md)
- [ADRs](docs/adr/README.md)

## Current island prototype
An early stylised island using eight original GLB resources: shaped terrain, detailed cottage, curved palms, coastal rocks, jetty, grass, bench and human explorer. Flat water and simple procedural walking animation remain provisional. See [resources and screenshot follow-up](docs/resources.md).

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

Debug-signed 0.2.0 Mobile and Compatibility APKs were exported and structurally verified; see [build report](docs/android-build-0.2.0.md). Phone validation of rendering and controls remains outstanding. Station multiplayer, voice and weapons are planning work only. The next station milestone is the network/voice feasibility experiment.
