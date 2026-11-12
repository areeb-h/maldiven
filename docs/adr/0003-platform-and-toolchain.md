# ADR 0003: Offline Android and supporting toolchain

Date: 2026-11-12. Status: Superseded for active online architecture by [ADR 0006](0006-authoritative-multiplayer.md) and [ADR 0007](0007-native-voice-feasibility.md). Historical Android toolchain details remain applicable where verified.

## Context
The initial deliverable is an installable APK for physical-device testing. The repository is public. Builds must be reproducible without publishing credentials or restricted asset sources.

## Decision
Target Android arm64 first. Use the official Android SDK, OpenJDK 17 and version-matched Godot export templates; resolve exact SDK packages from the pinned documentation during setup. Use ADB/logcat, Godot profiler and Android Perfetto for measurement. Add pinned-engine CI checks before automated Android builds. Keep signing keys outside Git.

Use local versioned saves under user://, with validation and safe-spawn fallback. No backend, account or runtime network dependency is needed for the first milestone.

Prefer custom or redistribution-compatible assets. Kenney and Poly Haven are optional CC0 sources, with per-asset provenance recorded. Mixamo is optional: game use permission does not automatically permit raw source redistribution in a public repository. Review actual terms before committing third-party files. No paid tools or subscriptions are required initially.

## Consequences
Physical-phone testing remains necessary. Automation cannot establish touch comfort or sustained thermal performance. Public-source distribution requires more care than merely shipping a game executable.

## Sources
- https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html
- https://godotengine.org/releases/4.7/
- https://kenney.nl/support
- https://polyhaven.com/license
- https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html
