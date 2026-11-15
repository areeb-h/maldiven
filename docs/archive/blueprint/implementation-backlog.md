# Implementation-ready backlog and expansion ladder

Version 0.3. Task rows describe required work; execution notes below identify implemented portions. A task is not completed by the existence of this document. The earlier roadmap supplies phase allowances; this file supplies ready-to-pick work and evidence.

## Foundation critical path

Execution: BASE-001's [initial baseline](../milestones/2026-11-12-baseline.md), NET-001's [local admission](../milestones/2026-11-12-network-admission.md) and NET-002's [initial shared-movement lab](../milestones/2026-11-12-shared-movement.md) are implemented within their documented scope. Native voice selection/pinning, full prediction replay, real-network/Android validation and production admission remain open. VOI-001 is next before content expansion. Other task rows remain planned unless a linked implementation record states otherwise.

| Order / task | Deliverable | Prerequisite | Acceptance evidence |
| --- | --- | --- | --- |
| 1 / BASE-001 | Pinned client/server/native dependency manifest and build IDs | Current source baseline | Clean import/export reproduced; old island remains accessible |
| 2 / NET-001 | Version handshake, one headless room, authenticated identity boundary | BASE-001 | Mismatch rejected, no ghost peer, room epoch changes on restart |
| 3 / NET-002 | Input intent, authoritative motion and simple replica | NET-001 | Forged teleport rejected; delay/loss results recorded |
| 4 / VOI-001 | Native Android voice candidate experiment | BASE-001 | Three phones exchange intelligible audio; dependency/build costs recorded |
| 5 / VOI-002 | Permission, PTT/mute, audio-route and lifecycle handling | VOI-001 | Denial/regrant/background/headset test record |
| 6 / VOI-003 | Service-enforced listener eligibility | VOI-001/NET-001 | Forbidden subscription attempt fails; eligibility changes acknowledged |
| 7 / OPS-001 | Single-region test room, bounded admission/cleanup and cost measurement | NET-001/VOI-001 | Measured room/media resource use; no unbounded idle rooms |
| 8 / DEV-001 | Affected-phone renderer decision | Current APK variants | Screenshot/repro comparison; supported configuration recorded |
| 9 / NET-003 | Item transaction/revision service and action result schema | NET-002 | SC-01/02/07 pass in peer harness |
| 10 / SOC-001 | Shared power cell and carry/release interaction | NET-003 | SC-03 passes; three-phone cooperative session |
| 11 / SOC-002 | Transfer acceptance, access token and manual hatch recovery | NET-003 | No half-transfer or permanent access veto; SC-04 |
| 12 / MAP-001 | Eight-sector greybox from station-map specification | SOC-001/DEV-001 | Graph/door-state checks and measured route times |
| 13 / MAP-002 | Camera, sightline, touch and cue pass | MAP-001 | Physical-phone route/camera check; no GUI-through-input |
| 14 / TST-001 | Cooperative rehearsal report | MAP-002/VOI-003 | Contribution/confusion counterexamples and a design decision |
| 15 / RND-001 | Roles, per-client visibility and round state machine | TST-001 | SC-11/14 plus transition/secret-state tests |
| 16 / RND-002 | Core/extraction/deadline adjudication | RND-001/NET-003 | SC-05 and final-tick cases; one terminal result |
| 17 / RND-003 | Reconnect reservation and interruption policy | RND-001 | SC-06/18/19; no reroll/duplicate items |
| 18 / SOC-003 | Partial evidence and clear extraction warnings | RND-002 | Honest-witness scenario; no role leak in error text |
| 19 / TST-002A | No-weapon deduction session report | SOC-003/RND-003 | PT-03/06 and revision decisions |
| 20 / CMB-001 | One server projectile/weapon and authoritative charges | TST-002A | SC-07/08; replicated shot/hit results under delay |
| 21 / CMB-002 | Down/drop/revive/medical recovery and protection | CMB-001 | SC-09; bounded inactivity and no invulnerable-core exploit |
| 22 / TST-002B | Weapon/no-weapon comparison | CMB-002 | PT-04 with per-player agency and retaliation patterns |
| 23 / UX-001 | Home/join/voice check/briefing/debrief/rematch | Proven state machines | First-session journey completed by unfamiliar players |
| 24 / ART-001 | Commons/service visual slice and character action set | MAP-002/TST-002A | Actual-engine device capture plus measured frame/thermal budget |
| 25 / AUD-001 | Speech/cue mix, pings and accessibility settings | VOI-002/ART-001 | Overlapping alarm/door/weapon intelligibility test |
| 26 / OPS-002 | Crash/admission/version/cleanup runbook | Proven room lifecycle | Release rehearsal exercises interruption and rollback |
| 27 / REL-001 | Signed candidate builds, compatibility/rollback artifacts | OPS-002/DEV-001 | Install/update and supported-device matrix |
| 28 / TST-003 | Multi-group friends-alpha evaluation | UX-001/AUD-001/REL-001 | Existing six-group/30-round formative gate with failed rounds retained |

Tasks on separate boundaries can proceed together once dependencies are met. Parallel implementation does not replace integration/physical-phone evidence or imply all experiments can be completed immediately.

## Feature readiness record
Before starting a task, record: target experience, source rule/contract, dependency versions, actor/authority, state transitions, public/private fields, cancellation/disconnect handling, acceptance tests, device evidence needed and rollback/cut option. A task with unknown native voice viability cannot be marked ready for polished content work.

## Expansion backlog
| ID | Opportunity | Entry condition | Smallest convincing experiment |
| --- | --- | --- | --- |
| EXP-01 | Power routing creates negotiations | H1 complete and readable | Four service demands, three units, clear manual fallback |
| EXP-02 | Shared map annotations and rendezvous beacons | Pings already useful | Two marker types with expiry/ownership and no role spoofing |
| EXP-03 | Intercom and team channels | Initial proximity/radio understood | One physical intercom; routing/permission tests |
| EXP-04 | Portable shield and repair defence | One-weapon comparison positive | One directional shield and a repair/retreat scenario |
| EXP-05 | Magnetic cargo tether | Stable server-owned carry | One anchored load with bounded collision and release |
| EXP-06 | Event director | Core rules and map states validated | Three authored incidents, pressure budget and reproducible event log |
| EXP-07 | Cooperative Salvage Shift | Rehearsal enjoyable across groups | Three repair/salvage variants and a shared extraction |
| EXP-08 | Richer hangar and cosmetic identity | Reliable joins/rematch | Crew emblem, suit palette and one optional lobby activity |
| EXP-09 | Visiting docking module | Topology/audio contracts stable | One pre-authored module connects two validated ports |
| EXP-10 | Gravity compartment | Cargo/controls performant and comfortable | One slow-floating cargo room with reliable exits |
| EXP-11 | Double Contract negotiation mode | Main mode clear and replayable | Two explicit partly conflicting cargo contracts; no new map |
| EXP-12 | Higher-stakes energy weapon preset | Nonlethal mode supports social play | Separate preset with explicit injury/elimination/voice policy |
| EXP-13 | Boarding Incident | Docking experiment successful | Two small crews meet across one attachment, with a tested participant cap |
| EXP-14 | Social expedition | Repeated voluntary return and operating budget | Independent missions sharing a cosmetic hub; no persistent power advantage |

Each experiment receives a scope/estimate and playtest before it becomes a release commitment. Keep the long-term ideas visible instead of silently treating them as work already included in the foundation schedule.

## Additional design work packages

The [content/traceability plan](content-authoring-and-tuning.md) defines nine additional work packages, DES-001 through TST-004 with their explicit IDs and dependencies. RUL-004, CMB-003, INF-004 and MAP-003 clarify existing H1 task acceptance; SOC-004/005 and CNT-001 stage later features. Do not add every expansion to the original 28-task foundation estimate. The [storyboard](first-session-storyboard.md) is the scope for a reviewable mockup, not a completed mockup artifact.

## Decisions to close through evidence
| Decision | Owner/evidence | When |
| --- | --- | --- |
| Voice provider/native bridge/version | Native engineer experiment + owner budget | P1 |
| Transport encryption integration | Packet/handshake/certificate tests | Before hosted internet play |
| Supported Android renderer/device set | Physical-phone profiles, including reported bands | P1/P3 and every visual release |
| Final room size and infiltrator count | Group playtest and load evidence | Six-player first; eight-player gate later |
| Injury timings/ammunition/weapon inclusion | PT-04 comparison | P5/P6 |
| Event density and map travel scale | Rehearsal/route observations | P3 then EXP-06 |
| Hosting region/capacity/spend | Measured routes, resource use and concrete quotes | Before deployment purchase |
| Final title/package migration | Name/availability and migration review | Before broader distribution |
