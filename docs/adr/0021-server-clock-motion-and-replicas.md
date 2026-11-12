# ADR 0021: Server-clock motion and bounded pose replicas

Date: 2026-11-12. Status: Accepted for the initial NET-002 loopback lab. Extends ADR 0006/0020; production/device gates remain open.

## Context

The checked admission layer needs a shared space. Packet count, client timestamps and client position claims must not become movement authority. A small visible room can establish this boundary before roles, weapons and station content.

## Decision

Use a 30 Hz server physics clock, bounded normalised directional intent and 15 Hz complete public pose/roster snapshots. Identity stays bound to admission. Reject extra position/actor/delta-time fields, stale/large sequence jumps and invalid types/bounds. Coalesce held intent instead of advancing once per message. Use input timeout, bounded rate/queues and connection-generation checks. Keep reliable lifecycle control separate from unreliable ordered motion delivery.

Use shared authored collision, basic local prediction with soft/hard authoritative correction, and remote interpolation. Do not claim deterministic physics or a complete rollback/replay algorithm. The initial test omits avatar blocking/jumping and all hidden gameplay state. Mark departing peers before draining queued motion.

## Alternatives and consequences

Client-authoritative positions make an attractive toy demo but fail the authority boundary. Simulating extra steps per received packet rewards floods. A complete replay/historical-physics system adds scope before the first room. The current correction model needs further tuning and real-device evidence; public snapshot data must later be filtered for the actual game's information rules.

Application-level seeded delay/drop queues are diagnostic instrumentation. They leave auth/control unimpaired and cannot establish internet/phone performance. The separate movement compatibility IDs keep this protocol distinct from the draft future game-command schema.

## Validation

[Step 3](../milestones/2026-11-12-shared-movement.md) links the movement, admission and island regression evidence plus render-capture scope. Invalid intent, fixed speed, stale-input stop, obstacle collision, replica removal and nine two-client impairment profiles are included. P1's phone/native voice/encrypted transport gates remain open.
