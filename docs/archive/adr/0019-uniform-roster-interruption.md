# ADR 0019: Use a uniform H1 roster interruption policy

Date: 2026-11-12. Status: Proposed H1 clarification; supersedes the infiltrator-specific absence response in ADR 0011 without replacing its other lifecycle rules.

## Context

If only the infiltrator's prolonged absence aborts the game, the abort policy leaks allegiance. Continuing with arbitrary missing crew also interacts with the two-crew extraction minimum, carried items and host removal. H1 lacks evidence for balanced mid-round replacement.

## Decision

Freeze six competitive identities at briefing. Reserve each disconnected slot for the same initial 60-second grace. Any unrecovered slot interrupts a still-active round without a faction win. No H1 mid-round competitive replacement or active spectator. Reconnect uses current authorised state, clears stale input/media and never rerolls or refills equipment.

Use absolute deadline order; for exactly equal terminal timestamps, interruption precedes extraction, which precedes station loss. An already committed result is final. Apply accepted reconnect commands before deadline evaluation as specified by the interaction contract.

## Alternatives

- Infiltrator-only abort: leaks the absent player's role through the outcome.
- Automatic faction replacement/reveal: changes the information game and creates reroll opportunities.
- Continue at a flexible quorum: potentially smoother, but requires a tested smaller-roster ruleset and privacy policy.

## Consequences and validation

One player can interrupt a private game by leaving; host admission/rematch controls address this socially without fabricated winners. This is a conservative continuity tradeoff, not a universal multiplayer solution. Test RC-01–RC-08, expiry ties and both faction roles. See [roster contract](../blueprint/round-roster-and-continuity.md). The policy is proposed and not implemented.
