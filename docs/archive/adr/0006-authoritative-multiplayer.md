# ADR 0006: Dedicated server authority and per-client information

Date: 2026-11-12. Status: Proposed; transport/security details gated by P1.

Implementation note: [ADR 0020](0020-local-admission-experiment.md) and its [evidence](../milestones/2026-11-12-network-admission.md) establish an isolated loopback admission experiment. Gameplay authority, encrypted internet transport, Android/voice and match reconnect remain unimplemented/open; this does not accept every production detail below.

## Context
Doors, tools, core possession, weapons and secret roles require consistent outcomes and controlled disclosure. A friend's phone acting as trusted host creates continuity, battery and authority problems.

## Decision
Prototype a headless Godot game server using the existing GDScript codebase and high-level ENet peer. Start with a versioned handshake and one authoritative room. Clients submit bounded input/action intent; the server validates movement, range, ownership, timing, line of sight and round state. Clients cannot declare hits, grant access, assign roles or choose winners.

Use separate reliable action/control and sequenced movement channels. Server-side event IDs and revisions make duplicate/replayed item or extraction requests idempotent. Prediction/interpolation/reconciliation are explicit implementation work; Godot RPCs do not supply fairness automatically.

Construct per-client views. Do not broadcast all roles/inventories and hide them only in the UI. Validate reconnect identity and preserve roles/items. Strip presentation from the server export while retaining required collision/data.

Use HTTPS for control/join tickets. ENet alone is not an encryption guarantee. Evaluate documented ENetConnection DTLS setup and certificate validation on the pinned Android/server builds; unencrypted transport is limited to isolated local experiments. Prove the chosen encrypted path before hosted internet play. No custom cryptography.

## Alternatives and consequences
Peer authority is simpler initially but exposes trust/continuity problems. A separate non-Godot simulation service adds duplicate physics/rules work now. Dedicated hosting creates operational and cost responsibilities; region and capacity require measurements and owner budget. Backend service language/provider remains undecided.

## Gate
P1 demonstrates client/server interaction on real networks; P4 tests secret-state filtering and round authority. Include forged/replayed/out-of-range requests, simultaneous pickup, latency/loss, process restart and disconnect tests.

## Sources
- https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html
- https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html
- https://docs.godotengine.org/en/4.7/classes/class_enetconnection.html
