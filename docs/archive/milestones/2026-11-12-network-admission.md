# Step 2: local network admission

Date: 2026-11-12. Work package: NET-001 local lab. Status: implemented and checked on Linux x86-64 with the pinned Godot 4.7.2 engine. P1's real-network/native-voice/phone gates remain open.

## Implemented behaviour

The standalone project under `experiments/net-lab/` runs separate real headless server and client processes. The server binds only to `127.0.0.1`, selects an available UDP port and creates one room epoch per process startup. The island remains the main game; its export filters exclude the experiment.

An explicit compatibility manifest carries protocol major/minor, content, rules and room IDs. The supported lab matrix is exactly the pinned values. The closed admission envelope additionally carries the epoch and one opaque ticket. A client-supplied identity field is rejected. The server assigns identity from its own ticket ledger before admitting a peer.

For this lab, the server issues two 32-random-byte single-use bearer tickets for each of six synthetic identities. Tickets are scoped by the in-memory ledger to the current room epoch and a server-monotonic deadline, normally 60 seconds from startup. The local credential directory/file permissions are checked as 0700/0600 on Linux. Credentials are passed in private files and excluded from arguments, diagnostic output and committed evidence. No custom signature or encryption scheme is introduced.

Authentication reserves identity and consumes its ticket before admission completes. Duplicate identities and full rooms are rejected, including simultaneous attempts. An unfinished handshake times out and releases its reservation without restoring the consumed ticket. A newly issued unused ticket can admit the same identity after disconnect; this is not the game's role/inventory-preserving reconnect feature.

The server permits at most six room participants and twelve transport connections, bounds auth/application JSON at 1024/256 bytes, and disables object decoding and client relaying. The lab handles only an explicit leave request after admission. Unknown application requests cannot declare a winner or invoke gameplay; there is no gameplay implementation in this project.

Shutdown refuses new admission, drains active/pending peers and clears reservations. A stopped state directory can be reused: old stop/ready markers are cleared, and the new epoch/ticket pool rejects the prior process's credentials. Use a separate state directory per running server.

## Evidence actually collected

The [machine-readable record](evidence/network-admission-2026-11-12.json) stores the complete result set, compatibility, engine checksum, input fingerprint and the island regression result for the same inputs.

| Coverage | Observed result |
| --- | --- |
| Local server readiness and credential permissions | Pass |
| Valid admission and two distinct live clients | Pass |
| Duplicate identity, simultaneous identity claims and room capacity | Pass |
| Major/minor/fractional protocol, content/rules/room and epoch mismatches | Pass |
| Unknown, replayed and expired tickets | Pass |
| Client identity field, malformed/oversized/non-ASCII auth data | Rejected |
| Rejected attempts do not consume an otherwise valid ticket | Pass |
| Silent and half-completed authentication | Times out; reservations clear; no admitted ghost |
| Leave and later fresh-ticket admission for the same identity | Pass |
| Unsupported post-admission application message | Rejected |
| Restart using the same state directory | New epoch; old credentials rejected; new admission works |
| Accepted session outlives its join timeout | Pass; join and leave timeouts are separate |
| Shutdown with active and pending clients | Pass; no post-shutdown admission; zero retained identities |
| Credential absence and engine-error absence in logs | Pass |

There are **32 passing network integration checks**. The five island baseline checks also pass for the same input fingerprint: clean import, assets/collision, movement/touch/pause, pack export and packaged startup. The exported island pack contains no experiment files. The Python test runner refuses `-O`, so disabling assertions cannot silently produce a passing report.

Development checks caught malformed-JSON error logging, a null-peer cleanup path, join-timeout lifetime coupling and stale restart markers. The final source uses checked parsing, deferred client peer disposal, separate lifecycle timers and explicit restart cleanup. These cases are retained in the integration coverage. The lab uses a small worker pool for multiple local probe processes; these runs do not establish production capacity or network latency.

## Repeat the checks

From the repository root, with Python 3.11+:

```bash
python tools/test_network_lab.py
python tools/validate_project.py
```

Both helpers bootstrap/validate the pinned engine. Logs and reports go to `builds/network-lab/` and `builds/baseline/`. The network runner copies the experiment into a fresh temporary project and removes its temporary credentials after process cleanup. No phone, account, provider purchase or hosted endpoint is required for this lab.

## Limits and next milestone

This is a local admission boundary, not a deployed account/control service. Public/LAN transport encryption, real network switching/loss, Android permissions and devices, voice, gameplay replication, private-role views and the 60-second match roster recovery policy have not been implemented or validated here. A local synthetic identity is not evidence of account authentication or a restored match state. There is no new APK from this step.

Next is NET-002: a small authoritative movement scene, bounded input intent, remote replicas and correction/disconnect behaviour. Verify forged position/input claims and record delay/loss behaviour before integrating a visible station scene. Native voice remains a separate early P1 experiment before art expansion.

See [ADR 0020](../adr/0020-local-admission-experiment.md) and the [lab usage/protocol notes](../../experiments/net-lab/README.md).
