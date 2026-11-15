# Implementation status

Updated 2026-11-12.

## Movement foundation

The [BASE-001 initial build foundation](milestones/2026-11-12-baseline.md) is now implemented: checked toolchain manifest, checksum-pinned Linux bootstrap, engine guard shared with Android export, fresh-copy validation, pack export and packaged startup. All five desktop/headless checks passed; an incorrect 4.6.3 engine was explicitly rejected. The [evidence record](milestones/evidence/baseline-2026-11-12.json) identifies the run. This is the first execution step following the planning passes; P1 network/voice and physical-phone gates remain open.

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
The owner selected a space-station social-game direction. The main executable remains the island 0.2.0 prototype. Active station plan, research, roadmap, playtests and ADRs are under docs/. A separate local admission/shared-movement lab is implemented; an isolated native PCM voice/phone candidate is now implemented, while tools/weapons, hosted session services, the station map and match rules remain unimplemented. Preserve the island baseline on archive/island-v0.2.0. The P1 technical feasibility gate remains open.

## Step 2: local network admission

NET-001's [loopback server/client lab](milestones/2026-11-12-network-admission.md) implements explicit compatibility IDs, single-use tickets, identity reservation, duplicate/capacity rejection, monotonic expiry, fresh epochs and lifecycle cleanup. The original 32 integration checks are retained as regressions; the historical [Step 2 evidence](milestones/evidence/network-admission-2026-11-12.json) remains available. Current combined results are linked under Step 3.

## Step 3: shared 3D movement

The [NET-002 lab](milestones/2026-11-12-shared-movement.md) implements a 3D room, authoritative 30 Hz motion, 15 Hz public pose snapshots, basic local prediction/correction, remote interpolation and desktop controls. It rejects forged position/identity/delta-time input, bounds speed/rate/queues, stops stale input and removes departed avatars. Thirty movement checks include nine explicitly simulated application-level delay/drop profiles with two clients. Admission and island regressions are rerun for the same inputs; see [current evidence](milestones/evidence/shared-movement-2026-11-12.json). An actual software-GL frame with two connected peers was captured. The island APK, native voice, phone integration and match recovery are not implemented by this local step.

## Expanded planning pass
The production blueprint now covers broader social-space modes, shared station systems, technical modules, transaction/failure invariants, mobile/art/audio production, 20 scenario cases, rollout/recovery, 28 ordered work packages and 14 expansion experiments. Draft JSON command schema/examples and station topology are planning artifacts. New ADRs 0012–0015 remain proposed. No station gameplay, online service, voice integration or new APK was implemented by this expansion.

## Social, mission and experience expansion

Additional proposed design now covers allegiance versus public jobs/equipment, explicit agreement/evidence provenance, six mission candidates, pacing/replay, spatial reaction/audio boundaries, map families, a first combat tuning preset and a twelve-state first-session storyboard. Nine additional work packages clarify H1 acceptance and stage H2 experiments. PT-07–PT-10 plus SX/CX/RC acceptance cases remain to implement/run. Research addendum R09/R10 documents primary-source ideas and limitations. ADRs 0016–0019 are proposed; 0019 supersedes the faction-specific absence response in 0011. The uniform roster policy avoids using abort behaviour as a role detector. No executable, voice integration, interactive mockup or APK changed in this planning pass.

## Step 4: Friends Lab phone build and PC server

The [Friends Lab milestone](milestones/2026-11-12-friends-phone.md) adds the separate 0.3.0 Android package, invite/join/retry UI, move/talk touch pointers, explicit microphone permission, certificate-checked ENet DTLS, native PCM capture/playback, server-enforced nearby/radio routing and mute/lifecycle controls. A cross-platform Python PC launcher and detailed [Windows/phone instructions](pc-server-and-phone.md) are supplied. See [current combined evidence](milestones/evidence/friends-phone-2026-11-12.json). Linux loopback checks, native dummy-audio lifecycle/generator checks and APK structure are verified; physical Android, real LAN and Windows-specific checks remain open. This does not close ADR 0007's media/provider decision or the three-phone P1 gate.

## PC host with phone on another network

A [launcher-only tunnel follow-up](milestones/2026-11-12-public-tunnel.md) adds `--public-address` and documents a free Playit UDP route. The existing 0.3.0 APK can use the generated public-IP invite. Four Python endpoint tests and 21 Friends Lab integration checks pass in the scoped evidence; actual Windows/Playit-to-phone connectivity remains to be tested.

## Friends Lab 0.3.1: invite entry

The [0.3.1 update](android-build-0.3.1.md) adds defensive clipboard handling, bounded formatting normalization, input readiness feedback and native invite-file import. The PC launcher exports private crew .txt files. The original package/signing identity is retained. Scoped desktop/package checks pass; physical Android paste/picker validation remains pending.
