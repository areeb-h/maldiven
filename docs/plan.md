# Active project plan: Drift Station

Updated: 2026-11-12. Repository: Maldiven. Drift Station is a working game title; availability has not been checked.

## Direction
Build an Android-first, third-person 3D social survival game for friends aboard a failing space station. Cooperation, voice, transferable equipment, incomplete information and limited combat should generate memorable shared stories. Six players and one infiltrator are the first complete-round target; eight players is a later validation target. A 12–15 minute round is an initial pacing hypothesis.

The main executable remains the 0.2.0 island resource prototype. The checked build foundation and a separate local server/client admission experiment are implemented, with evidence linked below. Gameplay multiplayer, voice, station art and the proposed match rules remain unimplemented.

## Read in this order
1. [Game design](game-design/drift-station.md): experience, concrete rules, scope and station layout.
2. [Research and design rationale](research/psychology-and-game-design.md) plus [coordination addendum](research/coordination-and-participation.md): ten sources across the two registers, evidence limits and testable applications.
3. [Roadmap](roadmap.md): work packages, dependencies, acceptance gates, planning allowances and stop conditions.
4. [Playtest protocol](game-design/playtesting.md): hypotheses, measurements and iteration decisions.
5. [Architecture decisions](adr/README.md): current decisions, proposed technologies and superseded island assumptions.

## Design pillars
- Useful cooperation: actions create reasons to ask, negotiate, help and trust.
- Meaningful choice: multiple ways to contribute; transferable tools instead of rigid class dependence.
- Readable uncertainty: truthful but incomplete world evidence, visible equipment and clear causes of failure.
- Recoverable conflict: early weapons create rescue/escape decisions; avoid long inactive periods.
- Comfortable mobile play: stable rendering, intelligible voice, readable layout and simple touch controls.

These are product hypotheses informed by research, not claims that academic theories guarantee fun or superiority over another game.

## First complete slice
One compact station, six private-room players, one infiltrator, proximity voice plus one shared radio channel, transferable access/tool equipment, one shared repair objective, one restricted core, one sabotage, one stun weapon with injury/recovery, and two competing extraction paths. Full match state, reconnect, win/loss and a short debrief are required.

This first slice is the foundation of a broader systemic station/social-space vision; see the blueprint below. A cooperative rehearsal with no infiltrator precedes deduction tests. Networking and native Android voice must work before station art expansion. Public matchmaking, multiple maps, large role rosters, lethal weapons, permanent elimination, maintenance drones, multiple radio channels, ranked progression and monetisation are deferred.

## Expanded production blueprint
- [Vision and experience](blueprint/vision-and-experience.md): signature situations, social lobby, mode family and H0–H4 expansion.
- [System design](blueprint/system-design.md): power/access/cargo/voice/evidence interactions and future tools.
- [Technical architecture](blueprint/technical-architecture.md): authority, native voice boundaries, replication and deployment.
- [Interaction contracts](blueprint/interaction-contracts.md): invariants, concurrency, deadlines and failure recovery.
- [Mobile, art and audio](blueprint/mobile-art-and-audio.md): two-thumb UX, screens, asset pipeline and measured budgets.
- [Verification and release](blueprint/verification-and-release.md): layered tests, rollout, rollback and evidence gates.
- [Scenarios and pre-mortem](blueprint/scenarios-and-pre-mortem.md): 20 difficult cases and narrative playtests.
- [Implementation backlog](blueprint/implementation-backlog.md): 28 ordered work packages, 14 expansion experiments and decisions to close.
- [Draft protocol/schema examples](specs/room-command.schema.json) and [station topology](specs/station-map.v1.json): machine-readable planning fixtures, not runtime implementations.

See [planning validation](blueprint/planning-validation.md) for the checks actually performed and their limits.

## Added social and content design

- [Social roles, agreements and evidence](blueprint/social-roles-and-agreements.md): allegiance versus jobs/equipment, voluntary coordination, facts versus accusations and muted participation.
- [Missions, pacing and replay](blueprint/missions-pacing-and-replay.md): six mission candidates, curated presets and decisions that vary between rounds.
- [Spatial design and map families](blueprint/spatial-design-and-map-families.md): sector encounter purpose, measured reaction opportunities and future map directions.
- [Combat and counterplay](blueprint/combat-counterplay-and-recovery.md): a proposed first tuning preset, ammunition conservation, rescue and anti-chain rules.
- [First-session storyboard](blueprint/first-session-storyboard.md): concrete mockup beats, twelve UI states and three review scenes; no interactive mockup built yet.
- [Round roster and continuity](blueprint/round-roster-and-continuity.md): uniform grace/interruption without an allegiance leak.
- [Content authoring and tuning](blueprint/content-authoring-and-tuning.md): nine additional work packages and the [mission fixture](specs/mission-cards.v1.json).

These additions clarify the foundation and stage H2/H3 content; they do not add every proposed feature to H1 or change its rough schedule allowance. ADRs 0016–0019 record the proposed choices. The current APK is unchanged.

## Preserve previous work
The [island plan](archive/island-plan.md), resource generator and APK build reports remain historical references. Preserve the complete island baseline on an archive branch before further implementation. Keep the repository name and package IDs until naming and migration are deliberately decided. Reuse movement, touch, camera, profiling and build tooling where suitable; tropical scenery is not the station art set.

## Immediate next milestone

Step 1, the [checked desktop/headless build foundation](milestones/2026-11-12-baseline.md), and Step 2, the [NET-001 local admission lab](milestones/2026-11-12-network-admission.md), are implemented and verified within their stated scope. Next is NET-002 authoritative shared movement, followed by integrating a visible scene and proving native voice. The whole P1 milestone below is still open.

P1: a time-boxed technical experiment with a dedicated game server and a native Android voice candidate, tested across actual phones and Wi-Fi/mobile data. Produce a technology decision, measured latency/battery/build impact, and a repeatable test. No hosting subscription or paid service is committed by this plan.
