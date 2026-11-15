# ADR 0009: Add one recoverable weapon after the social loop works

Date: 2026-11-12. Status: Proposed.

## Context
The owner wants weapon use. Fast irreversible kills could remove participants from a voice-driven session and make random attacks more effective than negotiation.

## Decision
First prove cooperative and deduction rounds without combat. Then introduce one visible, limited-charge stun weapon, authoritative damage/down state, dropped cargo, revive and bounded medical recovery. All holders use the same rules. Downing is not permanent elimination in the initial slice.

Make range, cooldown, ammunition, immunity/recovery and timing tunable data. Test a two-hit downing rule and roughly 30-second maximum inactive period as initial settings, not established optima. Prevent indefinite stun/trap through server timers and door overrides. Add lethal weapons/shields only if the conflict experiment preserves contribution and social interaction.

The server validates shot requests and any latency compensation; bound historical rewind and decide door-state/line-of-sight timing explicitly. Prediction is presentation, not client authority over hits. Unreliable networks must not permit repeated damage or inventory duplication.

## Alternatives and consequences
Immediate lethal combat is simpler to understand but creates longer exclusion and voice-information problems. No weapons may be the better mode if tests show conflict overwhelms conversation. Recovery reduces exclusion but can weaken stakes; cargo loss, time and objective control supply initial costs to test.

## Gate
PT-04 compares with the no-weapon condition. Reject indefinite stunlock, repeated random attacking, long inactivity and unexplained hits. Maintenance drones/permanent death require a later ADR defining information and voice isolation.

## Rationale
Research-to-design interpretation is documented in docs/research/psychology-and-game-design.md; it does not prove that nonlethal weapons are universally more enjoyable.
