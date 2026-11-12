# ADR 0022: LAN phone invites and a native PCM voice experiment

Date: 2026-11-12. Status: Accepted for the isolated Friends Lab experiment. Production media/provider decision and physical-device gates remain open.

## Context

The owner has cloned the repository to a desktop and wants to run its server while testing an Android APK. NET-001/002 established local identity admission and motion, but loopback addresses cannot connect a phone to a PC. ADR 0007 requires a native-phone voice feasibility gate before station content. A complete media SDK bridge is a larger candidate integration; a bounded native PCM baseline gives us an installable experiment now without claiming production audio features.

## Decision

Keep the root island project and package. Export `experiments/net-lab` separately as **Maldiven Friends Lab**, package `com.areebh.maldiven.friends`, version 0.3.0. Ship an invite screen and two independently owned touch regions for movement/PTT. The PC launcher validates the pinned Standard engine, binds a chosen private IPv4 interface and creates local private invites. Initial support is one LAN, six crew slots, no public service or router forwarding. `--local-only` is explicitly a development option, unusable from a phone.

Use ENet DTLS with the exact trusted X509 certificate carried in a privately transferred invite and common name `maldiven.local`. No unsafe TLS or plaintext fallback. The PC keeps its private key outside Git in a restricted state directory. A single-use credential still establishes identity; the certificate authenticates the server and protects transport. Invites are bearer credentials: their out-of-band transfer must be trusted. Invites expire after 600 seconds; the running admitted session does not. This is a fresh lab admission, not match-state recovery.

Add a native media candidate using `AudioStreamMicrophone`/`AudioEffectCapture` and `AudioStreamGenerator`. PCM is mono 16 kHz, 16-bit little-endian, 320 samples per 20 ms. A fixed 24-byte header makes each frame 664 bytes before ENet/DTLS/UDP overhead. The header contains a room-epoch tag, server-authenticated speaker slot, send channel, burst and sequence. Clients submit the reserved speaker byte 255; the server stamps identity and assigns monotonic output bursts across leave/rejoin. Room tags are fencing metadata, not authentication.

The reliable voice-control message requests a current PTT grant. Capture begins only while the button remains held, permission is granted and the server acknowledges that burst. Release, sound mute, leave, focus loss, background and disconnect stop capture and clear pending input. Permission regrant or foregrounding never silently restarts a hold. The mic bus is zero-volume after capture effects to avoid monitoring the microphone locally. Already delivered playback buffers can drain after a sender releases.

The server enforces the current grant, exact packet shape/size, epoch, channel, client sequence and authenticated connection. It permits at most 60 valid frames/s and bounds control starts to 12/s. Nearby voice routes only within 8 metres using server positions; radio routes to the other admitted crew. Selecting a channel affects sending; listeners hear both. No occlusion or distance gain exists yet. A bounded ten-frame receive queue drops oldest excess; two frames prime native playback, and stale streams stop after 250 ms. These are simple lab buffers, not a proven adaptive jitter implementation.

Audio is decrypted in server memory for routing. There is no audio recording, transcription or payload logging. Transport encryption is not participant-to-participant end-to-end encryption.

## Alternatives and consequences

- Unencrypted LAN ENet would be simpler but expose credentials/media on Wi-Fi; rejected for the phone build.
- A hosted provider/Opus/AEC pipeline remains a production candidate under ADR 0007. This PCM path adds a baseline candidate; it does not close that selection or the three-phone gate.
- No native addon, Gradle build, vendor account or service subscription is required for this experiment. PCM costs 256 kbit/s of raw audio per active talker, plus the frame header and transport overhead; server fanout scales with listeners. It is not a mobile-data cost or scalability solution.
- Headphones are the initial supported test setup. Echo cancellation, noise suppression, gain control, codec compression, Bluetooth/audio focus routing and measured mouth-to-ear latency are not established.
- Shared game/media transport is practical for this small experiment. Production voice may need independent transport, congestion control, relay, lifecycle and provider-specific operations. Keep capture/playback in `voice_audio.gd`, framing in `voice_wire.gd`, and routing/session control in the phone client/server.

## Verification and gate

See the [Step 4 milestone](../milestones/2026-11-12-friends-phone.md), [combined evidence](../milestones/evidence/friends-phone-2026-11-12.json) and [PC/phone guide](../pc-server-and-phone.md). Synthetic PCM over real certificate-checked DTLS, native generator consumption, capture adapter lifecycle, touch ownership, invite recovery and launcher shutdown are executable checks. Intentional certificate failures are expected engine TLS errors in the negative case only. Single-shot malformed movement probes now use reliable delivery for diagnostic evidence; real movement and production voice remain unreliable media.

Linux loopback and APK structural checks cannot close Android permissions/audio/route, Windows firewall/ACL, real Wi-Fi, thermal or latency gates. Run the guide on the owner's PC and at least three physical phones before advancing P1.

## Primary references

- https://docs.godotengine.org/en/4.7/classes/class_enetconnection.html
- https://docs.godotengine.org/en/4.7/classes/class_tlsoptions.html
- https://docs.godotengine.org/en/4.7/classes/class_audioeffectcapture.html
- https://docs.godotengine.org/en/4.7/classes/class_audiostreammicrophone.html
- https://docs.godotengine.org/en/4.7/classes/class_audiostreamgenerator.html
- https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html
