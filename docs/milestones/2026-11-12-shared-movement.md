# Step 3: shared movement in a 3D room

Date: 2026-11-12. NET-002 initial local implementation. The separate network lab now has a visible 3D client, authoritative movement and remote replicas. The island APK is unchanged; real phone/network and voice gates remain open.

## Implemented

`movement_server.gd` and `movement_client.gd` extend the checked admission scripts. A separate compatibility manifest identifies this movement mode. The same static room geometry is built for server collision and client prediction: floor, perimeter walls and a central obstacle. Distinct procedural suits and labels identify the local and remote players. Keyboard movement, running, a following camera and Leave/Escape controls are implemented.

The server simulates CharacterBody3D motion at 30 Hz and sends full public pose/roster snapshots at 15 Hz. Input has exactly `kind`, `room_epoch`, `seq`, `move_x`, `move_z` and `sprint`; identity comes from admission. Positions, actor claims and client delta-time fields are rejected. Finite bounded axes are normalised, walk/run speed is capped at 4/6 m/s, and packets do not advance physics. Sequence checks, a 90-packet/s window, bounded queues and a 250 ms held-input timeout limit stale/flooded intent.

Clients predict local collision movement, softly correct ordinary differences, hard-correct large discrepancies and interpolate remote snapshots. Prediction is a first approximation, without full input-history rollback/replay or cross-device deterministic physics. Full snapshots remove departed avatars. Delayed deliveries carry connection generations; peers leaving or shutting down receive no new motion deliveries. This fixed the queued-send disconnect race found during testing.

The initial room has no avatar-to-avatar blocking, jumping, tools, roles, combat or station missions. A fresh admission for an identity starts a new lab avatar; it is not match-state restoration. Keyboard mapping/focus-policy code is present; the automated focus case drives the same policy through a diagnostic file and does not replace physical-device background/input testing.

## Verification

The [combined evidence](evidence/shared-movement-2026-11-12.json) records results, engine/input fingerprints and the actual profile observations. All 30 movement checks, 32 admission regressions and five island build checks pass for identical inputs. The movement checks cover two real clients, matching authoritative replicas, floor/obstacle collision, ownership, release/stale-input stopping, forbidden fields/types, sequence/epoch rejection, local prediction tampering, rate/speed bounds, disconnect removal and fresh admission.

Nine profiles cross requested **50/100/200 ms simulated round-trip delay** with **0/1/3% motion-message loss**, using two clients. Server application queues impose half the delay in each motion direction and seeded drops. Auth/control still use ordinary loopback. This is not OS packet impairment, jitter/reordering, measured internet RTT or a six-phone load test. Actual drop counters and input-to-snapshot p95 acknowledgement delay are reported separately from the requested settings. Short-run correction-error observations are not comfort/performance guarantees.

The `prediction_error_p95_m` field is the pre-correction distance to a received, aged authority snapshot; it is not time-aligned prediction accuracy. Acknowledgement intervals include fixed-tick/snapshot scheduling and application queues, so they must not be presented as measured transport RTT or voice latency.

The source also passes an actual software-GL client capture with two connected peers and clean session exit. It uses an authenticated virtual Xorg display and dummy audio; it establishes a rendered desktop frame, not Android rendering, sound or voice readiness. The captured image is delivered separately, with its checksum in the evidence.

## Run it

From the repository root, Python 3.11+ and the pinned engine:

```bash
python tools/test_network_lab.py
python tools/test_movement_lab.py
python tools/validate_project.py
python tools/run_movement_lab.py --seconds 60
```

The last command requires a desktop display and opens the real client alongside a server/headless companion. On the checked Linux capture host, an installed Xorg dummy driver supports `--virtual-display --capture /absolute/path/preview.png`. That mode deliberately uses software GL/dummy audio. Temporary tickets are removed on cleanup; build reports/logs stay under `builds/` and are not shipped in the island pack.

## Remaining work

P1 is still open. Next is the native Android voice feasibility experiment and client/device integration, before station art expansion. Encrypted/public transport, physical touch/camera comfort, real loss/network switching, full prediction replay, abrupt transport-death recovery and the match's identity/role/inventory reservation need their own implementation and evidence. No new APK is delivered by this desktop/local milestone.
