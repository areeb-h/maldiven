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
- Version 0.2.0 Mobile and Compatibility diagnostic APKs now export successfully and pass structural/package checks. Physical-device validation is pending. See docs/android-build-0.2.0.md.
- See docs/resources.md for resource counts, preview limitations and rebuild instructions.

## Active direction: station social game
The owner selected a space-station social-game direction. The executable remains the island 0.2.0 prototype. Active station plan, research, roadmap, playtests and ADRs are under docs/. Multiplayer, voice, weapons, session services and station art are not implemented. Preserve the island baseline on archive/island-v0.2.0. The immediate next milestone is the P1 technical feasibility experiment.

## Expanded planning pass
The production blueprint now covers broader social-space modes, shared station systems, technical modules, transaction/failure invariants, mobile/art/audio production, 20 scenario cases, rollout/recovery, 28 ordered work packages and 14 expansion experiments. Draft JSON command schema/examples and station topology are planning artifacts. New ADRs 0012–0015 remain proposed. No station gameplay, online service, voice integration or new APK was implemented by this expansion.

## Social, mission and experience expansion

Additional proposed design now covers allegiance versus public jobs/equipment, explicit agreement/evidence provenance, six mission candidates, pacing/replay, spatial reaction/audio boundaries, map families, a first combat tuning preset and a twelve-state first-session storyboard. Nine additional work packages clarify H1 acceptance and stage H2 experiments. PT-07–PT-10 plus SX/CX/RC acceptance cases remain to implement/run. Research addendum R09/R10 documents primary-source ideas and limitations. ADRs 0016–0019 are proposed; 0019 supersedes the faction-specific absence response in 0011. The uniform roster policy avoids using abort behaviour as a role detector. No executable, voice integration, interactive mockup or APK changed in this planning pass.
