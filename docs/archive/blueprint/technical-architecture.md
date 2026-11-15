# Technical architecture and capability plan

Version 0.3. This remains the target architecture. The main game is the island prototype; [local admission and initial shared motion](../milestones/2026-11-12-shared-movement.md) are now implemented in the isolated lab. The named production modules and broader systems below are proposals unless linked evidence states otherwise.

## Boundaries
| Component | Owns | Must not own |
| --- | --- | --- |
| Android Godot client | Input, prediction/presentation, UI, device settings | Authoritative roles, inventory, damage or outcomes |
| Godot room server | Match simulation, validated actions, eligibility and per-client views | Microphone capture, client-only visuals or billing secrets in snapshots |
| Session/control service | Join codes, short-lived tickets, room discovery/allocation | Continuous player movement or unrestricted role disclosure |
| Voice adapter/service | Media capture/playback/transport and enforced listener permissions | Gameplay verdicts or unvalidated client-defined room membership |
| Operations layer | Build/version rollout, room limits, health and minimal diagnostic events | Default raw voice recording or permanent identity profiling |

Keep control-service language/provider open until P1 measurements. A small deployment is sufficient to prove one room; multiple services on this diagram do not mandate a complex production cluster.

## Client modules
- InputRouter: finger ownership, action state, UI capture, accessibility and background reset.
- LocalPlayerController: intended motion and prediction; authoritative corrections remain visible/debuggable.
- InteractionPresenter: eligible action prompts, progress and rejection reasons without secret details.
- RoomReplica: versioned snapshots/events with per-entity revisions.
- VoiceSession: provider-neutral lifecycle and eligibility application.
- Presentation: camera, animation, effects, sound and cosmetic props.
- SessionUI: join, reconnect, briefing, round, outcome and rematch states.
- SettingsStore: local sensitivity/audio/accessibility only; cannot change authoritative rules mid-round.

## Server modules
- SessionAuthority: authenticated identity, room epoch, protocol/version and reconnect reservation.
- CommandValidator: bounds, rate, timing, actor capability and duplicate handling.
- Simulation: movement/collision plus door/item/cooperative-action state.
- MatchDirector: state machine, role assignment, objectives, countdowns and single outcome commit.
- InformationPolicy: per-client entity/field visibility and voice eligibility.
- EventJournal: minimal diagnostic facts with restricted access; redact secrets/tickets.
- RoomLifecycle: allocation, interruption, orderly finish and cleanup.

## Simulation and replication
Start by measuring a 30 Hz authoritative simulation with 10–20 Hz snapshots; these rates are engineering seeds, not performance claims. Keep rendering independent. Separate sequenced input/movement traffic from reliable transactions and lifecycle events. Bound packet sizes and retained history.

Use prediction for local responsiveness and interpolation for remote actors. Correct invalid motion without permitting client teleport claims. Do not use cross-device deterministic lockstep as a shortcut for 3D physics. Event ordering and seeded director decisions can be reproducible without assuming floating-point physics is identical on all devices.

Interest filtering is an information boundary. Separate visible world state, participant-private facts, faction facts and server-only state. Do not send hidden state and rely on UI concealment. Reconnection sends an authorised fresh view, not a dump of the complete room.

## Commands and revision model
See the [draft schema](../specs/room-command.schema.json). The authenticated connection determines the actor; an actor ID supplied by a client never grants authority. Room epoch prevents previous-round actions being applied to a new round. Sequence and command ID handle ordering/retry; expected entity revision handles contention.

All state-changing actions return an accepted/rejected result with command ID, server tick, relevant revision and an allowed reason code. Retrying an identical accepted transaction returns its recorded result within the retention window. Reusing an ID with a different payload is rejected. A lost acknowledgement is not permission to apply an operation twice.

## Combat contract
The first stun implementation uses server-simulated projectiles with swept collision and client-predicted visuals. The server reconstructs muzzle origin from authoritative pose; clients supply bounded aim intent, not arbitrary hit targets or damage. Validate active weapon, ammunition, cooldown, phase and injury state. Projectile presentation is corrected to the authoritative result.

Hitscan/rewind is a later option requiring its own tested historical door/occlusion policy. Never accept unrestricted client timestamps or rewind through a currently closed barrier without an explicit fairness rule. Recovery protection is visible and ends under defined aggressive/core-carry actions; it cannot become an invulnerable extraction exploit.

## Voice lifecycle
Join ticket → microphone consent/check → media connection → eligible-listener policy → explicit transmit state → retry/reconnect or orderly leave. Opening the app must not silently publish microphone audio. PTT and local mute respond immediately; server/service eligibility changes are acknowledged and observable in diagnostics.

The provider spike must prove forbidden subscriptions fail. If confidentiality cannot be enforced, do not label the affected channel private or ship hidden-role mechanics that depend on it. Keep technical connection loss distinct from in-game interference. Voice-only operation does not justify camera capture.

## Deployment progression
1. Local headless room and automated clients.
2. One test region, bounded rooms, real-phone tests and manual allocation.
3. Automated room cleanup, admission limits and a concrete service budget.
4. Only after measurements: multiple room workers/regions and broader discovery.

Use pinned export templates/native libraries, separate server/client release artifacts and a protocol compatibility policy. Authoritative room logic and clients must agree on the content/rules version. No provider purchase or public release is part of writing this plan.
