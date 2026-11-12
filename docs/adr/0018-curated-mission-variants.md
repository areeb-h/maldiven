# ADR 0018: Curate mission variants before procedural combinations

Date: 2026-11-12. Status: Proposed for H2; H1 keeps one shared repair. Extends ADR 0008/0014.

## Context

Replay needs variation, but combinations of objective prerequisites, scarce items and blocked doors can produce impossible rounds. A graph with valid references does not establish useful physical routes or meaningful alternative choices.

## Decision

Author versioned mission cards and a few reviewed presets. Validate references, prerequisite closure, horizons, capabilities, recovery and event/topology compatibility before admission. Keep secret role randomisation independent of any public/replayable content seed. Pin active rooms to their content; no live balance edits during a round.

## Alternatives

- Unrestricted random combinations: more theoretical variety, larger invalid-state space.
- One permanent scripted sequence: simpler, but may make later rounds predictable.
- Full custom editor/mod platform now: disproportionate tooling/security scope before content throughput is measured.

## Consequences and validation

The [mission catalogue](../specs/mission-cards.v1.json) is a planning fixture, not an implemented content runner. MIS-01 alone is H1; later cards must not become H1 prerequisites. CNT-001 must add runtime/preset admission validation. Human PT-09 and physical greybox evidence remain required after static checks pass.
