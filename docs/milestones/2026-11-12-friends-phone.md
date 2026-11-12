# Step 4: installable Friends Lab and PC host

Date: 2026-11-12. VOI-001 native PCM candidate and phone integration. P1 remains open until physical-device testing.

The separate net-lab project now exports an Android Friends Lab with a private invite menu, independently owned move/talk fingers, nearby/radio push-to-talk, microphone permission handling, incoming mute and return-to-menu on leave/failure. The root island app remains available. This is the shared test room, not the finished station map or social match.

`python tools/run_friends_server.py` is the PC host entry point. On Windows pass the pinned Godot console EXE as shown in the [full PC and phone guide](../pc-server-and-phone.md). No Android build dependencies are required to host. The launcher keeps certificates, keys and private invites outside Git, limits the default room to the PC's chosen private interface, opens a local invite page, and drains the server on Ctrl+C. Windows firewall commands and troubleshooting are documented. Windows execution/ACL correctness have not been tested on a native Windows host here.

The phone verifies the invite's server certificate over ENet DTLS and then uses the existing single-use identity admission. No unsafe-certificate or plaintext fallback is implemented. The server routes a fixed PCM16/16 kHz/20 ms format to admitted listeners using authoritative positions. Capture/playback, framing, voice routing and join UI are separate code units. See [ADR 0022](../adr/0022-lan-phone-and-pcm-voice-experiment.md) for bounds and tradeoffs. Headphones are the starting test setup; AEC/Opus/audio route recovery and production media selection remain open.

## Evidence

The [combined record](evidence/friends-phone-2026-11-12.json) includes input/engine fingerprints, synthetic friends checks, 32 admission regressions, 30 movement regressions, five island build checks and APK structural evidence. The exported Friends desktop pack starts through the actual packaged application entry point. A real two-client software-GL UI frame was inspected; no microphone hardware or audible output was available in that capture.

Synthetic frames reach another client's native generator, nearby range is checked using server motion, radio crosses that range, and mute discards incoming audio locally. Negative checks cover missing grants, forged speaker/epoch/size, stale sequences, rate floods and an unrelated server certificate. Lifecycle checks cover independent touch IDs, native capture start/stop under dummy input, denied permission state, release/background policy, invite errors and clean exits. The launcher smoke uses `--local-only`: this build environment has no LAN interface/route, so it does not establish PC-to-phone connectivity. Intentional bad-certificate handshakes produce explicit expected TLS errors; ordinary cases must remain free of engine/script errors.

One-shot diagnostic malformed motion probes use reliable delivery so an absent server rejection cannot merely be a lost diagnostic packet. Production motion still uses unreliable ordered delivery, and normal voice uses unreliable frames.

## Owner test next

Install `maldiven-friends-0.3.0-arm64.apk`, pull the repository on the PC, start the server, copy different crew invites to two phones and run the guide's acceptance table. Then repeat on three actual phones. Check permission denial/regrant, walk-and-talk, headphone audibility, nearby/radio range, mute, background/screen lock/call interruption, leave/retry, server shutdown and a 15-minute session.

Do not mark P1 complete yet: no real Windows execution, Android install, physical microphone/speaker/Bluetooth route, Wi-Fi/mobile-data transition, conversational latency, six-phone fanout or thermal measurements have been observed here. Automatic match reconnection/reservation, public hosting/relay, the finished station, weapons, hidden roles, shared-object transactions and round rules remain later steps. If native audio proves unreliable, use these results to choose the next media candidate before expanding station content.
