# Verification, release and recovery blueprint

Version 0.2. A plan cannot establish flawless behaviour; release confidence comes from evidence, bounded failure and a clear recovery path. Every row below describes work still to implement unless a milestone note links actual evidence.

## Acceptance layers
| Layer | Scope | Evidence |
| --- | --- | --- |
| Pure rule tests | Item ownership, deadlines, outcome ordering, role visibility | Fast automated examples plus generated action sequences |
| Server integration | Multiple peers, reconnect, duplicate/invalid commands | Repeatable headless harness and restricted packet traces |
| Native audio/device | Capture, permission, echo, routes, lifecycle | Actual Android devices and measured voice results |
| Gameplay usability | Controls, goal clarity, contribution and fair uncertainty | Structured group sessions and contradictory feedback retained |
| Performance/soak | Thermal play, RAM/voice/network drift and cleanup | Representative runs with devices, versions and raw measurements |
| Delivery/operations | Install/update, admission, room crash and rollback | Release candidate rehearsal and runbook execution |

No bot or headless test substitutes for hearing speech, seeing the renderer fault or deciding whether a group enjoys the round.

## Deterministic rule checks and generated sequences
For each invariant INV-01–INV-10, implement targeted tests and generated command sequences. Use recorded seeds to reproduce command histories, not to assert cross-platform deterministic physics. Examples: repeated pickup/give/drop, concurrent revive, disconnect mid-carry, phase transition during interaction, simultaneous extraction and expired-ticket retry.

State-machine tests enumerate allowed/forbidden transitions. A terminal result is written once. Invalid messages are bounded and rejected without crashes or private error details. Keep failures as regression cases.

## Network and device matrix
Exercise 50/100/200 ms RTT and 0/1/3% loss as initial test conditions, plus jitter, reorder/duplicate requests, timeout and Wi-Fi/mobile switching. These are test inputs, not a promise of good play at all combinations. Measure local prediction corrections and action acknowledgement delay.

Start with the owner's affected OnePlus configuration and additional Android GPU/device families available to the group. Record exact model, OS and renderer rather than assuming brand-wide compatibility. Include speaker, wired/USB and supported Bluetooth routes, denial/regrant of microphone access, calls/audio interruption where safely testable, screen lock/background and battery-saving behaviour.

## Play experience
Use the existing [protocol](../game-design/playtesting.md), extended with scenario cases. Report per-player agency/inclusion and group differences. Look for dominant roles, long waiting, weapon abuse, arbitrary suspicion, unreadable evidence, excessive chatter burden and network problems mistaken for betrayal.

A majority enjoying a session does not justify ignoring one repeatedly excluded participant. Compare no-infiltrator, deduction and weapon conditions. Do not expand the role or weapon roster until the current condition supports the pillars.

## Release gates
- **R0 local lab:** automated commands and one room work; no public claim of online readiness.
- **R1 invited technical test:** bounded admissions, measured native voice, clear bug-report path and exact build IDs.
- **R2 friends alpha:** complete rules, measured performance, reconnect/cleanup, private-state and voice eligibility checks.
- **R3 limited pilot:** installation/upgrade rehearsal, signed reproducible artifacts, compatibility policy, agreed operating budget and an exercised interruption/rollback path.
- **R4 broader release:** only after real demand, operational capacity and appropriate player-support/moderation processes exist. Private lobbies alone do not establish readiness for public matchmaking.

Ship claims must match the gate. 'Package signature verified' is not 'phone tested'; 'phone tested' is not 'fun proven'; 'fun in one friend group' is not 'better than every competitor'.

## Rollout and incident handling
Pin client, room-server, native audio SDK and content versions. New rooms can use a new compatible version while active rooms finish on their pinned rules. If a client/server combination is incompatible, explain the update requirement before joining.

Have a server admission switch, bounded room count and a rollback to the prior known-good artifacts. Disabling new admissions should not invent an outcome for active rooms. A crashed H1 room restarts in lobby or ends interrupted; seamless migration is a later feature requiring a durable snapshot/event recovery design and tests.

Incident note: build IDs, affected conditions, observed symptoms, minimal reproduction, immediate mitigation, evidence of recovery and follow-up regression. Keep access tokens and private-role/voice data out of public reports. Do not ask players to send secrets.

## Minimum operational measurements
Room CPU/RAM, active/idle room count, joins/failures, RTT/loss, voice connection failure, session interruption, crash rate and per-build install failures. Use minimal retention and pseudonymous session IDs with an explicit data policy before collecting remote diagnostics.

Cost planning uses measured concurrency and media fan-out: room-hours × hosting rate + voice traffic/participant usage × service rate + storage/monitoring. Actual prices/provider/region require a later concrete decision; this plan does not commit money or invent free unlimited hosting.

## Definition of ready / done
A work package is **ready** when rules/contracts, dependencies, failure states and its acceptance method are clear. It is **done** only when code/assets, necessary automated checks, applicable physical-phone evidence, documentation and unresolved limitations are recorded against a commit. A documentation-only milestone can be complete while the planned capability is still unimplemented.
