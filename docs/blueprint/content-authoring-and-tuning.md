# Content authoring, tuning and traceability

Version 0.3, 2026-11-12. Proposed production workflow. The fixture in this pass validates planning references only; no authoring tool, mission runner or live configuration system is implemented.

## Keep rules, presentation and experiments separate

| Content | Examples | Authority/version boundary |
| --- | --- | --- |
| Competitive rules | Injury, extraction, item capacity | Room-pinned rules version, server-enforced |
| Authored world data | Rooms, hatches, spawn/return points | Matching client/server content version |
| Mission cards | Prerequisites, capabilities, recovery | Validated catalogue and compatible preset |
| Presentation | Signs, materials, sound/animation | Must faithfully express the pinned rules |
| Experiment record | One changed parameter and observations | Build/condition ID; never silently changes a running round |

Data-driven does not mean clients can choose arbitrary damage, import scripts or override authority. H1 uses bundled versioned content. Remote updates, user-generated maps and mod scripting require their own security/distribution design later.

## Mission authoring contract

Each mission defines ID, horizon, capability dependencies, start/destination sectors, prerequisite mission IDs, required/optional status, visible progress, alternative/recovery and public evidence. A case that lacks recovery or uses a secret faction as its only operator is not ready.

The [draft catalogue](../specs/mission-cards.v1.json) describes six cards. Only MIS-01 is an H1 candidate. MIS-02–MIS-06 are H2 candidates; they are not dependencies to start H1. All share the current eight-sector map references. The fixture is a planning format, not a complete JSON Schema or runtime protocol.

Before selecting cards for a preset, check prerequisite closure, horizon compatibility, supported capabilities, supply counts, travel/reaction margins and event/door reachability. Acyclic prerequisites alone do not prove the group can complete the objectives. One unique resource cannot be required simultaneously by incompatible objectives without a deliberate, reversible allocation rule.

## Authoring loop

1. Write the player-facing decision and name the failure it could create.
2. Place a greybox object, cue, interaction and safe return/release point.
3. Add authority/state transitions and failure cases using the shared contracts.
4. Validate references, topology, collision/clearance and privacy views.
5. Play on the target phone with a small group; record the observed decision and confusion.
6. Keep, revise or remove the card; only then finish the reusable assets and sound.

Tooling can eventually show a map overlay of objectives, acoustic zones, recovery points and reachable routes. Its first useful output is a specific invalid reference or path, not a large custom editor. Reuse ordinary Godot scenes/resources and the repository until a measured authoring bottleneck justifies a plugin.

## Tuning ledger

Every changed parameter records: old/new value, hypothesis, rule/preset ID, dependent cues, acceptance test, observed result and rollback value. Change one principal variable in a formative comparison where practical. Do not silently adjust ammunition, timers or faction odds between rounds in the same named condition.

For example, changing the pod warning from its provisional 20 seconds also affects HUD wording, route/intervention expectations, deadline cases and briefing. Changing stun protection affects invulnerability tests, feedback, camera/mobility and extraction exploits. A tuning edit is not isolated merely because it changes one number.

## Expansion work packages from this pass

These extend the original 28 foundation packages without renumbering them or adding them to the 70–120 day allowance. H1 clarifications below must be attached to their existing implementation tasks before those tasks are considered done; they are not optional post-release fixes.

| ID | Deliverable | Dependency/phase | Acceptance |
| --- | --- | --- | --- |
| DES-001 | Reviewable first-session UI mockup | Existing plan; before UX-001 polish | Three review scenes and all twelve error/round states represented; simulations labelled |
| RUL-004 | Uniform frozen-roster/grace policy | RND-001/003; H1 P4 | Any unrecovered slot interrupts without a faction-specific outcome; boundary ordering tested |
| CMB-003 | Versioned first tuning preset and ammo conservation | CMB-001/002; H1 P5 | CX-01–CX-06, including transfer/rejoin and equal-deadline recovery |
| SOC-004 | Voluntary public responsibility board | TST-003; H2 | SX-01/04/06; compare against unstructured cooperation |
| SOC-005 | Acknowledged, revisioned agreement cards | NET-003/SOC-004; H2 | SX-02/05; no automatic honesty/reputation claim |
| INF-004 | Evidence source/scope presentation | SOC-003; H1 P4 | SX-03 plus traffic/private-field checks |
| MAP-003 | Reaction and acoustic boundary worksheet | MAP-001/002/VOI-003; H1 P3 | Measured intervention routes and listener-transition delay; no privacy overclaim |
| CNT-001 | Mission catalogue validator and preset admission checks | EXP-06/07; H2 | Reference/dependency/horizon/recovery failures caught before room creation |
| TST-004 | Coordination and rescue-economy comparisons | Appropriate implemented feature | PT-07–PT-10 reports, with disagreements and technical failures retained |

These are proposed tasks. Documentation of acceptance does not mean the tests ran.

## Content release checks

For each candidate build: list pinned map/preset/rules/native versions, fixture/runtime differences, supported devices, asset provenance and applicable test evidence. A room stays on its starting content. Reject unknown mission/action IDs and unsupported capabilities at admission. Roll back future room creation without modifying an active round's rules.

## Planning validation in this pass

Recheck Markdown targets against the repository tree; parse the mission JSON; check unique IDs, sector references, prerequisite existence/acyclicity, H1 dependency closure and recovery fields. Preserve results in the [planning validation record](planning-validation.md). These checks do not establish mission fairness, simulation correctness, reachable physical geometry or device performance.
