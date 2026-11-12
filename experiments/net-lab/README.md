# NET-001 network lab

Standalone Godot 4.7.2 project for local admission tests. The island main scene and Android APK do not use this project. The parent `.gdignore` and export filters keep the experiment out of island builds.

Run from the repository root:

```bash
python tools/test_network_lab.py
```

The runner uses separate real Godot processes and a fresh temporary project. It creates a server, issues local credentials, starts multiple clients, exercises rejection/lifecycle cases and writes redacted logs plus `builds/network-lab/report.json`. Python 3.11+ and the checksum-pinned engine are used. No extra native addon, account or hosting service is required.

## Admission model

`compatibility.json` pins major/minor, content, rules and room IDs. The server generates a fresh epoch and twelve opaque credentials: two per synthetic identity, for six possible identities. A credential is a single-use bearer ticket scoped by the server's in-memory ledger to that identity, room epoch and a monotonic expiry. The default expiry is 60 seconds from startup; the test can shorten it. A client cannot extend expiry or assign its identity by changing packet fields.

The server writes credentials into an owner-only state directory/file. The test hands each client only its selected credential through an owner-only file. Tokens never appear in command arguments or diagnostic output. This local issuer/ledger is an experiment, not a deployed account or HTTPS ticket service.

SceneMultiplayer authentication gates admission. A valid ticket is consumed and identity reserved before completion. A second simultaneous peer for the same identity fails. A half-finished handshake times out and releases its reservation; the consumed ticket stays consumed. A fresh ticket can admit the same synthetic identity after disconnect. This does not implement the game's 60-second roster reservation, role/inventory restoration or match reconnection.

## Wire data

Join auth envelope: `kind`, `protocol_major`, `protocol_minor`, `content_id`, `rules_id`, `room_id`, `room_epoch`, `ticket`. Extra fields are rejected, including client-supplied identity. The server derives identity from its ledger. Auth data is limited to 1024 bytes and an ASCII JSON object; there is no object deserialisation. The accepted/welcome response identifies only that recipient and the agreed compatibility/epoch.

The NET-001 base server/client handle only a bounded `leave` message after admission. The separate NET-002 subclasses below add movement and public poses. Neither implements roles, combat, item actions or the draft game-command schema under `docs/specs/`.

The room capacity is at most six, with twelve transport connections and a bounded auth timeout. These are lab limits, not internet load/abuse certification. Server shutdown refuses admission, drains active/pending peers and clears state. Restarting a stopped directory clears its old stop/ready markers and generates a new epoch/ticket pool. Use one server process per state directory.

## Scope

Binding is hard-coded to IPv4 loopback. This transport does not establish encryption/server certificates, internet access, LAN/phone play, native voice or match recovery. The base admission client and extended movement client both have a join timeout that ends after admission and a separate leave timeout. The broader game systems remain separate gates.

## NET-002: shared 3D movement

```bash
python tools/test_movement_lab.py
python tools/run_movement_lab.py --seconds 60
```

The second command opens an actual desktop Godot client, plus a local server and headless companion. Use WASD/arrows, Shift to run and the Leave button/Escape to exit. It requires a desktop display; the Linux render-only `--virtual-display --capture /absolute/path/frame.png` option can use an installed Xorg dummy driver. That capture uses software GL and dummy audio, not native voice or phone rendering.

`movement_server.gd` reuses admission but loads `movement-compatibility.json`. It simulates CharacterBody3D motion at 30 Hz with static floor/wall/obstacle collision, normalised directional intent, walk/run caps, sequence/epoch checks, bounded queues/rate and a 250 ms input timeout. Packets do not carry authoritative positions, actor IDs or client delta time. Physics advances once per server tick, independently of packet count. Avatar-to-avatar collision and jumping are deliberately absent from this initial room.

Full public pose/roster snapshots run at 15 Hz using unreliable ordered traffic; admission/leave remain reliable. Queued deliveries are scoped to the connection generation and closing peers receive no new motion traffic. Clients render distinct suits, predict their own collision movement, apply soft corrections or a hard reset for large errors, and interpolate remote poses. This is not full input-history replay or a synchronised/deterministic cross-device physics simulation. A client waits/stops new motion when snapshots go stale.

`--rtt-ms` / `--loss-percent` in the movement server model motion-message impairment with application queues and seeded drops at each motion direction. They do not emulate OS networking, retransmission/control failures, NAT, jitter or a measured internet RTT. Auth/control still use ordinary loopback. The test report labels requested settings separately from observed acknowledgement delay, correction error and actual drop counters. Its nine profiles are 50/100/200 ms requested simulated round-trip delay crossed with 0/1/3% drops, using two clients.

The private control files used by tests can inject malformed input or tamper a local prediction. They are diagnostic inputs, not network privileges. Credentials remain private, are deleted with the temporary session, and are absent from the diagnostic logs. See the Step 3 milestone under `docs/milestones/` for scope and evidence.

## Relevant engine APIs

- https://docs.godotengine.org/en/4.7/classes/class_scenemultiplayer.html
- https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html
- https://docs.godotengine.org/en/4.7/classes/class_crypto.html
