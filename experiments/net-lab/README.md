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

Only a bounded `leave` message is handled after admission. Other application messages are rejected; gameplay commands, roles, movement, combat and replication are not implemented. The draft game-command schema under `docs/specs/` is a different future protocol boundary.

The room capacity is at most six, with twelve transport connections and a bounded auth timeout. These are lab limits, not internet load/abuse certification. Server shutdown refuses admission, drains active/pending peers and clears state. Restarting a stopped directory clears its old stop/ready markers and generates a new epoch/ticket pool. Use one server process per state directory.

## Scope

Binding is hard-coded to IPv4 loopback. This transport does not implement or establish encryption/server certificates, internet access, LAN/phone play, native voice, gameplay authority or match recovery. Those remain separate gates. The probe client's join timeout ends after admission; it can hold a session and later leave, and it has a separate leave timeout.

## Relevant engine APIs

- https://docs.godotengine.org/en/4.7/classes/class_scenemultiplayer.html
- https://docs.godotengine.org/en/4.7/classes/class_enetmultiplayerpeer.html
- https://docs.godotengine.org/en/4.7/classes/class_crypto.html
