# Drift Station roadmap

Updated: 2026-11-12. Phase gates govern advancement. None of the multiplayer/station milestones below is implemented by the planning commit.

## Planning assumptions
One primary developer with AI assistance, Android first, friend-only testing and access to at least three actual Android devices through the owner/test group. Dedicated server and native audio integration are new work. Existing island movement/export work reduces setup effort but does not establish multiplayer, voice or gunplay readiness.

Allowances below are rough focused developer-days, not calendar commitments or empirical estimates. Total P1–P8 allowance is 70–120 days (approximately 14–24 full-time working weeks), excluding recruiting/testing delays and a broad commercial launch. Re-estimate after P1 and P3 using measured throughput. The gate owner is the project owner; implementation/test evidence must be attached to milestone notes.

## Dependencies and gates

Execution update: BASE-001's [initial desktop/headless foundation](milestones/2026-11-12-baseline.md) and NET-001's [local admission experiment](milestones/2026-11-12-network-admission.md) are implemented. The latter has 32 passing multi-process checks plus five island regressions for the same inputs. NET-002, production/encrypted admission, native voice, Android re-export and physical-phone validation remain open; P1 has not passed.

| Phase | Allowance | Work and concrete deliverable | Exit gate |
| --- | ---: | --- | --- |
| P0: direction and baseline | Documentation pass | Active plan, research, ADRs, roadmap, playtests; preserved island branch | All cross-links resolve; old/current scope distinguished; no claim of station implementation |
| P1: network and voice feasibility | 5–10 days | Three-phone network/voice experiment, headless server, candidate integration report, renderer check | Join over Wi-Fi/mobile data; microphone permission and audio route handling; no duplicate voice; mute/PTT work; demonstrate basic server authority; document costs/dependencies |
| P2: cooperative room | 5–10 days | Private join code, one room, one shared object, door, transfer and ready/restart loop | Three phones complete a cooperative interaction; reconnect preserves identity; simultaneous pickup has one owner; action requests cannot claim success |
| P3: six-player station greybox | 10–15 days | Eight sectors/two loops, proximity + shared radio, six-peer replication, cooperative rehearsal | Six players complete objective without infiltrator; paths readable; door recovery prevents softlocks; device/network budgets recorded |
| P4: deduction round | 10–15 days | Secret role, restricted core, one sabotage, rival extraction and deterministic round resolution | Six-player sessions reach valid outcomes; no role leakage through client snapshots/UI/voice; disconnect/abort rules pass; initial hypotheses reviewed |
| P5: one-weapon conflict | 10–15 days | Server-validated stun, down/revive, cargo drop, bounded medical recovery | Latency tests and simultaneous actions resolve correctly; no indefinite stun/trap; playtests retain contribution and conversation |
| P6: repeatable friends alpha | 10–20 days | Onboarding, pings, mute/host controls, post-round debrief, selected station art/sound | At least six distinct friend groups and 30 valid rounds; core fairness/contribution issues addressed; voluntary replay observed without prompting |
| P7: eight-player and device hardening | 10–15 days | Eight-player load, reconnection, slow-network tests, thermal/audio profiling | Supported devices hold baseline performance; no sustained memory drift or secret-state leaks; poor-network behaviour understandable |
| P8: limited release readiness | 10–20 days | Reproducible release pipeline, permission audit, service budget, operational runbook and supported-device list | Pilot cohort validates installation/upgrade and room lifecycle; owner approves concrete hosting/release scope |

P6 art exploration may overlap earlier phases only after voice feasibility and map scale are proven. Eight simulated clients are useful load tests; they cannot replace eight-player voice and human-session validation.

## Expanded scope and execution contracts
The [full experience blueprint](blueprint/vision-and-experience.md) retains broader ambitions: systemic power negotiation, richer social hangar, cooperative mode, event director, docking, gravity compartments and later boarding/expeditions. These are gated horizons beyond the foundation allowance above.

The [ordered backlog](blueprint/implementation-backlog.md) defines 28 implementation work packages and 14 expansion experiments. Use [interaction contracts](blueprint/interaction-contracts.md), [scenario cases](blueprint/scenarios-and-pre-mortem.md) and [release evidence](blueprint/verification-and-release.md) to define ready/done. P1/P3 estimates must be revised from measured work; an ambitious horizon is not silently included in the current estimate.

The [additional work packages](blueprint/content-authoring-and-tuning.md) add a first-session mockup scope, measured reaction/acoustic routes, evidence presentation, combat conservation and uniform roster handling. These H1 clarifications attach to their existing gates; public jobs, agreement cards and the fuller mission catalogue remain H2 experiments. Four additional playtest comparisons are recorded as PT-07–PT-10. No new schedule certainty or implementation is implied.

## Work packages
### P1: prove the difficult dependencies
- NET-001: versioned Godot client/server handshake, headless Linux export and bounded join ticket.
- NET-002: authoritative movement/action toy scene; introduce latency/loss in repeatable tests.
- VOI-001: evaluate official Android media SDK bridge versus native WebRTC integration; record licence, ABI, build and maintenance requirements.
- VOI-002: microphone permission denial/regrant, speaker/headphones/Bluetooth if supported, echo cancellation and app background/resume.
- VOI-003: demonstrate server-controlled listener eligibility; prove forbidden track subscription is denied, not merely quiet on an honest client.
- OPS-001: measure idle/active room CPU/RAM and voice bandwidth; choose a test region from actual latency to the friend group. No purchase is authorised by this roadmap.
- DEV-001: reproduce the two horizontal bands on the affected phone, compare Mobile+MSAA and Compatibility and document a supported configuration.

Time-box the voice spike. If the first Android voice experiment fails within the allowance, diagnose the failure, define the next concrete bridge/provider test and re-estimate the spike. Pause dependent content expansion while resolving the capability; preserve the voice pillar unless the owner deliberately changes it. The existing Godot WebRTC data-channel extension is not itself a complete voice stack.

### P2–P3: make cooperation enjoyable
- NET-003: item IDs, revisioned ownership and reliable action acknowledgements.
- MAP-001: modular greybox kit, room graph and all approved door-state reachability checks.
- MAP-002: test shortest/alternate routes, sightlines, camera obstruction and touch reachability.
- SOC-001: two-person power-cell interaction with immediate, legible feedback.
- SOC-002: tool/token handover, public manual door override and contextual pings.
- TST-001: run a no-infiltrator rehearsal and measure confusion, idle time and contribution before deception.

### P4–P5: introduce uncertainty, then violence
- RND-001: explicit match state machine, one infiltrator and private per-client state filters.
- RND-002: primary/alternate extraction, interrupts, timeout and same-tick resolution tests.
- RND-003: bounded reconnect slot and role-preserving identity; interruption outcome if a valid game cannot continue.
- SOC-003: incomplete access evidence and restricted-core warnings.
- CMB-001: intent-only shot requests, ammo/range/line-of-sight/cooldown validation and bounded lag handling.
- CMB-002: downing, dropped cargo, revive, protection and medical recovery.
- TST-002: compare cooperative, deduction and combat conditions using the playtest protocol; cut features that reduce the target experience.

### P6–P8: make it repeatable
- UX-001: short playable briefing and self-serve controls/voice check.
- ART-001: finish one social junction and one service corridor; expand only after performance checks.
- AUD-001: intelligibility and alarm hierarchy, per-player volume, pings and visual equivalents.
- OPS-002: room cleanup, crash/restart behaviour, server logs without secrets, capacity limits and measured cost model.
- REL-001: pinned SDK/addon/template versions, signed builds, test distribution and rollback instructions.
- TST-003: broaden to unfamiliar-with-the-game groups; evaluate mixed skill and muted-player participation.

## Initial engineering targets
These are proposed acceptance targets to validate during P1–P3, not guaranteed performance:
- 30 FPS baseline after 15 minutes of representative play; report p95 frame time and thermal behaviour, not averages alone.
- At six players, test 50/100/200 ms round-trip delay and 0/1/3% packet loss; measure reconciliation and action feedback.
- Voice conversational target: p95 mouth-to-ear latency below 250 ms on the agreed representative route; document measurement method, jitter and exceptions.
- Temporary disconnect: reserve the slot for an initial 60-second grace period. Rejoining cannot generate a new role or duplicate inventory.
- Invalid, replayed, oversized or rate-excessive action requests fail predictably; do not crash or reveal secrets.
- Voice routing and gameplay state recover after network switching/backgrounding or show a clear, recoverable failure state.

If a target is unrealistic, record the observed limit and change the supported conditions or design deliberately. Never label an unmeasured metric as passed.

## Initial play-experience gates
See [protocol](game-design/playtesting.md). For formative tests, target a group median of at least 4/5 for contribution, clarity and willingness to replay, with no persistent participant reporting exclusion at 1–2/5 across rounds. These thresholds are product decisions. Thirty rounds are exploratory, not a statistically powered superiority test. Outcome counts, station-loss frequency and player feedback guide balancing; do not mechanically force a 50% faction win rate by hiding unfair interventions.

## Risks, dependencies and fallback decisions
| Risk | Detection | Response |
| --- | --- | --- |
| Voice native integration/echo/routing fails | P1 physical-phone spike | Pause content; change integration or reduce communication features |
| Server costs exceed owner budget | Measured room and voice model | Cap rooms, reduce service scope or pause hosting decision |
| Guns turn sessions into random attacks | P5/P6 event and interview review | Tune access/recovery or return to nonlethal cooperation slice |
| Friends dominate/quiet people excluded | Per-player contribution/agency feedback | Improve pings, transferable tools, briefing and alternative participation |
| Deception relies on reading accents/anxiety | Observation and debrief | Strengthen world evidence; no lie-detection or vocal scoring |
| Android rendering/heat remains unstable | Actual-device profiles | Supported Compatibility option, lighter art/effects and narrower device support |
| Information leaks after downing/disconnect | Red-team state/voice inspection | Block affected feature/phase until filtered correctly |
| Scope expands before fun is proven | Gate review | Keep one map/mode/weapon; defer the rest explicitly |

## Completion evidence per milestone
Create a dated note containing source commit, APK/server versions, device/OS/network, participant/group counts, exact test conditions, observed results, unresolved defects, and a continue/change/stop decision. Links to CI outputs or voluntary screenshots are useful. A headless test does not establish voice quality, graphical quality or fun.
