# Drift Station: game design specification v0.1

Date: 2026-11-12. Status: proposal for implementation and playtesting. Numerical settings are tuning seeds, not research-derived optima.

## Experience and audience
A small group of friends should finish a round with a story about a rescue, bargain, misunderstanding or betrayal. Design primarily for friends on Android with different levels of gaming skill. Third-person stylised 3D, landscape, short sessions, private invite rooms. Begin at six players; test eight after the six-player loop works.

The ambition is richer cooperation and social interaction. A claim of being better than Among Us requires comparative player evidence and is not a release criterion.

## Scenario
An evacuation shuttle is docked at a damaged station. The crew must stabilise essential power and evacuate with a restricted core. One infiltrator appears to be crew but wants to steal that core and launch a separate cargo escape pod. Both factions initially benefit from restoring power, creating room for genuine cooperation before interests diverge.

## Match state and resolution
| State | Behaviour |
| --- | --- |
| Lobby | Invite/join, voice check, ready state and accessible controls; no role assignment yet |
| Briefing | Server assigns five crew and one infiltrator, explains shared goal and private objective |
| Stabilisation | Repair power and prepare shuttle; core remains visible in a locked cargo cradle |
| Extraction window | Core becomes transferable; crew can ready the main shuttle; infiltrator can arm cargo pod |
| Resolution | Server selects a single outcome; actions freeze; all-player debrief voice opens |

Prototype win conditions:
- Crew: main shuttle departs with the core and at least two crew aboard. Other survivors may also board. Gate launch on power/shuttle prerequisites; use a visible countdown that can be interrupted by removing the core before launch completion.
- Infiltrator: launch the cargo pod with the core before a crew departure completes. Arming produces a station-wide warning and an interruptible countdown, initially 20 seconds.
- Station loss: an unresolved critical failure countdown expires. Both factions lose; failure is not counted as an infiltrator win.
- If conflicting final actions occur on the same simulation tick, resolve against a deterministic event sequence, then broadcast one result. Never infer a winner on clients.
- A round timer initially caps play at 15 minutes, ending in station loss if neither faction has completed extraction. Tune the cap after observing actual rounds.

The two-crew evacuation minimum is a testable attempt to preserve cooperation. Watch for premature unwinnable states and unfair pressure to abandon friends. Change the rule if it creates passive waiting or unnecessary stalemates.

## Participant continuity

The H1 roster is fixed at briefing. Apply the same initial 60-second reconnect grace to every slot, regardless of allegiance; any unrecovered slot interrupts a still-active round without a competitive winner. No mid-round replacement or active spectator joins. A valid result committed earlier during grace remains final. See the [roster contract](../blueprint/round-roster-and-continuity.md) for extraction occupancy, offline item recovery and exact deadline ties. This clarifies the earlier lifecycle proposal without introducing a faction-specific abort signal.

## Moment-to-moment loop
See a need or opportunity → find a person, tool or route → communicate and commit → act together or interfere → observe consequences → revise trust and priorities.

Physical interaction examples: two people transport a bulky power cell; one person holds a manual hatch while another carries equipment; players exchange an access token; someone drags an injured person to medical. Avoid long hold-to-complete chores and dexterity tests that consume attention needed for talking.

## Starting responsibilities and equipment
Everyone shares basic movement and interaction. Starting kits offer different opportunities but can be handed over. Avoid a repair that becomes permanently impossible because its only qualified player disconnects.

| Item/access | Initial function | Counterplay/recovery |
| --- | --- | --- |
| Access token | Operate a limited set of doors | Public timed manual override; ownership can change |
| Engineering tool | Repair one circuit and cut a jammed hatch | Spare tool or slower manual recovery path |
| Medical kit | Stabilise/revive a downed player | Medical recovery prevents permanent exclusion |
| Cargo scanner | Distinguish restricted core from ordinary cases | Core remains identifiable through a slower public inspection |
| Radio | Shared push-to-talk channel | Proximity speech and contextual pings remain available |

Prototype only the minimum kits required by the slice. Private optional crew side-objectives are an expansion experiment after the main objective is understood.

## Communication
Proximity voice encourages local groups. A single common push-to-talk radio bridges separated groups. Prototype a range around 8–12 metres, but tune using actual room geometry and intelligibility. Use room/door connectivity for simple audibility rules before attempting expensive continuous acoustic simulation.

Always show microphone/transmit status and radio channel. Provide local mute, volume controls, push-to-talk and short contextual pings. Microphone denial does not crash or prevent a supported muted-player route. Distinguish an intentional in-game outage from a real connection problem. No voice cloning, lie detector, automatic vocal profiling or default voice recording.

Multiple channels, intercom broadcasts and intentional radio jamming follow the first voice/playtest gate, not the initial three-phone experiment.

## Evidence and deduction
World evidence is reliable about events but incomplete about intent. A log may show a credential opened a hatch; it does not prove the credential's original owner used it. Carrying a tool is visible. Removing a core makes a physical absence and alarm. Logs must not expose roles or provide a perfect route history.

No automatic verdicts, compulsory accusation meetings or instant ejection in the first mode. Players may gather, negotiate, escort, interrupt or temporarily disarm. The game must give quiet participants useful ways to contribute. A confident speaker is not automatically correct; a pause or accent is not evidence of deception.

## First combat experiment
One clearly visible stun weapon, shared rules for all holders, limited charges, telegraphed aim/fire, server-validated range/line-of-sight and injury state. Use a prototype two-hit downing rule and short effective range; test whether this leaves enough time to respond. Exact damage, charges and timing belong in tunable data.

A downed player drops carried cargo. A teammate can revive them; otherwise a bounded medical recovery returns them after a short period with empty hands. Test a roughly 30-second maximum inactive period and temporary recovery protection. Prevent indefinite stun chains and locked-room trapping through server timers and manual door overrides.

The weapon must support bargaining, interruption, protection and rescue. If random attacks dominate sessions, adjust access/ammunition/recovery or remove the weapon until cooperation works. Lethal energy weapons, shields and permanent death are later experiments. Maintenance drones are deferred until information and voice separation can be demonstrated.

## Station blockout
One deck, approximately 70 by 50 metres as an initial scale. Strong sector names, pictograms and shapes; colour is a supporting cue. Short sightlines, observation windows and two connected loops. No lethal airlock, exclusive infiltrator vents, free-form destruction or zero-gravity simulation initially.

| Sector | Neighbours | Reason to visit |
| --- | --- | --- |
| Docking | Commons, Cargo | Main shuttle and arrival |
| Commons | Docking, Command, Medical | Social junction, clear shared status |
| Command | Commons, Security | Information, access and later intercom |
| Security | Command, Cargo | Controlled equipment and partial access records |
| Cargo | Security, Docking, Engineering | Restricted core and alternate escape pod |
| Engineering | Cargo, Reactor | Power-cell cooperation and repair |
| Reactor | Engineering, Medical | Critical shared objective |
| Medical | Reactor, Commons | Recovery and rescue destination |

Public loop: Docking → Commons → Command → Security → Cargo → Docking.
Service loop: Commons → Command → Security → Cargo → Engineering → Reactor → Medical → Commons.
The table mirrors the [machine-readable topology](../specs/station-map.v1.json), which is the versioned topology source of truth. Keep both aligned. A blocked door must leave a viable route or a bounded manual recovery. Verify reachability automatically for approved door states.

Measure travel times and encounters. A starting target is 20–40 seconds between distant objectives at ordinary movement speed, with destinations visible before all details are known. Do not polish a layout whose social encounter rate fails.

## Art and audio
Readable industrial science fiction: modular floors/walls, distinct door silhouettes, large exterior windows, restrained emissives, utility equipment with identifiable shapes. Start with a compact reusable kit instead of a large map. Emergency state changes must retain readable navigation. Preserve the Mobile/Compatibility diagnostic path until the reported Android bands are understood.

Sound priorities: speech intelligibility, door/alarm recognition, item feedback and ambience that ducks under speech. No dependable tactical information should exist only in colour or audio.

## Explicitly deferred
Public matchmaking, persistent accounts, ranked systems, paid progression, procedural stations, multiple decks, NPC enemies, spaceflight, ship-to-ship combat, many role classes and large weapon rosters. The island executable remains available while station work proceeds.

## Expanded design references
This is the H1 rule specification. The [experience blueprint](../blueprint/vision-and-experience.md) extends the ambition beyond H1. [System design](../blueprint/system-design.md) stages additional tools, power negotiation and director/docking/gravity possibilities. The [interaction contracts](../blueprint/interaction-contracts.md) define proposed concurrency/failure semantics and exact deadline tie policy. None is implemented by the documentation pass.

The [combat specification](../blueprint/combat-counterplay-and-recovery.md) gives an explicitly unvalidated first tuning preset. [Mission/replay design](../blueprint/missions-pacing-and-replay.md), [social design](../blueprint/social-roles-and-agreements.md) and [spatial design](../blueprint/spatial-design-and-map-families.md) add concrete situations and H2/H3 experiments. Later mission cards and public jobs do not silently become part of the H1 rules.
