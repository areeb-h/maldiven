# ADR 0011: Explicit round lifecycle and information-preserving reconnect

Date: 2026-11-12. Status: Proposed.

Clarification: [ADR 0019](0019-uniform-roster-interruption.md) supersedes the faction-specific absence response below with the same grace/interruption policy for every fixed-roster slot. The remaining lifecycle direction is retained. Read the [roster contract](../blueprint/round-roster-and-continuity.md) for current proposed rules.

## Context
Short friend sessions need understandable outcomes and recovery from mobile interruptions. Secret roles, physical cargo and two extraction paths make informal client-side outcome logic unreliable.

## Decision
Implement an authoritative state machine: lobby → briefing → stabilisation → extraction window → resolution → debrief/lobby. Six players/five crew/one infiltrator is the first full mode. Eight-player role distribution remains a later balance decision.

Adjudicate crew extraction, infiltrator extraction and station loss separately according to the game specification. Serialize conflicting final actions deterministically. Gate action legality by state and replicate only the facts a particular client should know.

Reserve disconnected identities/roles/items for an initial 60-second reconnect grace. A new join cannot take over an existing role; late joins wait in a lobby-only state until the next round. Reconnect cannot reroll roles or duplicate items. Do not reveal a disconnected player's faction through UI or system messages.

If the infiltrator cannot return after grace, or connected player count drops below the supported minimum, end as interrupted with no competitive winner. Test exact continuation rules before relaxing this. Preserve secret roles until resolution/debrief; keep outside spectators out of active positional/role information and active voice.

## Consequences
Interruptions reduce completed-round counts, but fabricated wins would undermine tests. A bounded grace period balances continuity against waiting. External voice/collusion remains a social limitation. Multi-room persistence, bot replacements and host migration are deferred.

## Gate
P4 tests same-tick extraction, timeouts, reconnect, identity replacement, interrupted matches and per-client state/voice leakage. No client or room owner can issue an arbitrary win during a match.
