# ADR 0013: Specify transactions, visibility and failures before adding content

Date: 2026-11-12. Status: Proposed; schemas are draft planning artifacts.

## Context
Shared cargo, revives, doors and extraction can fail under simultaneous action, replay, delay or reconnect. Retrofitting ownership and privacy after many content scripts would be costly.

## Decision
Adopt INV-01–INV-10 and the command/revision model in docs/blueprint/interaction-contracts.md. Use a draft closed-field command schema with actor identity derived from the authenticated connection. Room epoch, sequence, command ID and entity revision address stale rounds, retries and contention. Structural schema validation is only the first layer; semantic authority/range/state checks remain server work.

Make countdowns authoritative deadlines. Serialize accepted actions and commit one terminal outcome. Enforce private media delivery at the service boundary rather than honest-client volume alone. Describe bounded failure/recovery to players.

## Consequences
Schemas and examples need versioning, tests and change discipline. The current command schema is deliberately incomplete: acknowledgement/snapshot/join/media contracts still need companion schemas and implementations. A passing JSON-schema example is not proof of network security or gameplay correctness.

## Gate
P2 transaction tests and P4 state/privacy tests exercise the scenario cookbook, including duplicate commands, conflicting pickup, disconnect and final-tick outcomes. Changes to these semantics require updating the contract and regression cases.
