# Active project plan: Drift Station

Updated: 2026-11-12. Repository: Maldiven. Drift Station is a working game title; availability has not been checked.

## Direction
Build an Android-first, third-person 3D social survival game for friends aboard a failing space station. Cooperation, voice, transferable equipment, incomplete information and limited combat should generate memorable shared stories. Six players and one infiltrator are the first complete-round target; eight players is a later validation target. A 12–15 minute round is an initial pacing hypothesis.

The current executable remains the 0.2.0 island resource prototype. Multiplayer, voice, station art and the proposed game rules are not implemented. This commit changes planning documents only.

## Read in this order
1. [Game design](game-design/drift-station.md): experience, concrete rules, scope and station layout.
2. [Research and design rationale](research/psychology-and-game-design.md): eight sources, evidence limits and testable applications.
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

A cooperative rehearsal with no infiltrator precedes deduction tests. Networking and native Android voice must work before station art expansion. Public matchmaking, multiple maps, large role rosters, lethal weapons, permanent elimination, maintenance drones, multiple radio channels, ranked progression and monetisation are deferred.

## Preserve previous work
The [island plan](archive/island-plan.md), resource generator and APK build reports remain historical references. Preserve the complete island baseline on an archive branch before further implementation. Keep the repository name and package IDs until naming and migration are deliberately decided. Reuse movement, touch, camera, profiling and build tooling where suitable; tropical scenery is not the station art set.

## Immediate next milestone
P1: a time-boxed technical experiment with a dedicated game server and a native Android voice candidate, tested across actual phones and Wi-Fi/mobile data. Produce a technology decision, measured latency/battery/build impact, and a repeatable test. No hosting subscription or paid service is committed by this plan.
