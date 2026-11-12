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
- [Social roles, agreements and evidence](docs/blueprint/social-roles-and-agreements.md)
- [Missions and replay](docs/blueprint/missions-pacing-and-replay.md)
- [First-session storyboard](docs/blueprint/first-session-storyboard.md)
- [ADRs](docs/adr/README.md)

## Current island prototype
An early stylised island using eight original GLB resources: shaped terrain, detailed cottage, curved palms, coastal rocks, jetty, grass, bench and human explorer. Flat water and simple procedural walking animation remain provisional. See [resources and screenshot follow-up](docs/resources.md).

Open `project.godot` in Godot Standard and run the main scene.

- Desktop: WASD to move, right-mouse drag to look, Space to jump, Escape to pause. Full movement input runs; Shift also selects run speed.
- Touch: left-side floating stick, right-side drag to look, bottom-right jump, top-right pause.
- Pause menu: resume or return to beach.
- Out-of-bounds recovery returns the explorer to spawn.

## Versions and validation

The [checked build foundation](docs/milestones/2026-11-12-baseline.md) is implemented. Run `python tools/validate_project.py` to bootstrap the pinned Linux engine and perform fresh import, existing regression checks, pack export and packaged startup. Dependencies and release checksums are in `toolchain.lock.json`; the ambient `godot` command is not assumed to be the correct version. Python 3.11+ is required for these helpers.

Godot 4.7.2 stable Standard, with matching export templates required for platform export. The engine binary was downloaded successfully after an initial connection timeout. Import, startup and movement smoke checks are run against 4.7.2.

Mobile renderer and built-in Jolt are configured. Use `godot --headless --path . --editor --import` to check imports. Use `godot --headless --path . --quit-after 120` for a basic startup smoke check. These checks cannot establish visual quality or Android performance.

## Plan
See [development plan](docs/plan.md) and [ADRs](docs/adr/README.md).

Step 2's [local network admission lab](docs/milestones/2026-11-12-network-admission.md) is implemented. Run `python tools/test_network_lab.py` for actual headless server/client tests of compatibility, single-use credentials, duplicate identities and lifecycle cleanup. It is an isolated loopback project; shared movement, phone networking and voice are next gates.

Debug-signed 0.2.0 Mobile and Compatibility APKs were exported and structurally verified; see [build report](docs/android-build-0.2.0.md). Phone validation of rendering and controls remains outstanding. Local admission is implemented in the separate lab; the island APK has no multiplayer, voice or weapons. The next execution step is authoritative shared movement; the wider P1 network/voice feasibility milestone remains open.
