# ADR 0007: Prove native Android voice early; isolate the provider

Date: 2026-11-12. Status: Proposed; no voice vendor or SDK version selected.

## Context
Voice is part of the core experience. Game-state networking and real-time microphone media have different requirements. The existing APK is offline, uses prebuilt export templates and requests no microphone permission.

## Decision
P1 must prove three-phone voice before detailed station construction. Define a VoiceSession boundary for join/leave, PTT, mute, listener eligibility, gain, microphone state and reconnect. Game authority owns proximity/radio membership; the media transport handles capture, codec, jitter and playback. The initial social slice uses proximity plus one shared radio channel.

Evaluate:
1. Official Android real-time media SDK through a thin Godot Android/Kotlin plugin bridge. LiveKit Android is a researched candidate, not a selected drop-in Godot solution. Verify native callbacks, lifecycle and audio routes.
2. A native WebRTC-based path with explicit media support. Godot's documented native extension/data-channel support does not by itself provide a complete voice application. Evaluate capture, Opus, echo cancellation, signalling, relay and service interoperability.
3. Existing maintained Godot voice integrations only if Android ABI, licence, maintenance, routing controls and end-to-end tests are demonstrated. Do not assume desktop support implies Android support.

Request microphone permission only when entering voice; voice-only operation does not require camera access. Inspect merged manifests and SDK requirements. Adding a native plugin may require Gradle/custom Android export, changing the current build pipeline.

## Information boundary
Local volume attenuation alone cannot enforce private channels. A candidate must demonstrate that forbidden subscriptions/rooms are rejected by the service/server. Avoid raw voice recording by default. Clearly document that external Discord/collusion cannot be prevented by in-game routing.

## Gate and consequences
Test permission denial/regrant, speakers/headphones, supported Bluetooth routes, echo, muted participation, background/resume, Wi-Fi/data transition, measured mouth-to-ear latency and resource cost. Freeze provider/version only after passing. If the time-box fails, pause content and revise integration/scope; do not silently replace built-in voice with an external-call requirement.

## Sources
- https://docs.godotengine.org/en/4.7/tutorials/networking/webrtc.html (page warns it may be outdated; verify pinned release)
- https://github.com/godotengine/webrtc-native
- https://docs.livekit.io/transport/sdk-platforms/
- https://docs.livekit.io/transport/sdk-platforms/android/
