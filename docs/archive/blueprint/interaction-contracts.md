# State, concurrency and failure contracts

Version 0.3. These contracts are intended to be implemented and tested; they are not runtime guarantees today.

## Non-negotiable invariants
| ID | Invariant | Typical counterexample to test |
| --- | --- | --- |
| INV-01 | One logical item has at most one holder/container | Two simultaneous pickups both succeed |
| INV-02 | A round has at most one committed terminal result | Two clients see different winners |
| INV-03 | Hidden role facts reach only authorised recipients | Snapshot, log or spectator view exposes the infiltrator |
| INV-04 | A reconnect preserves identity, role and valid ownership | Rejoin rerolls role or duplicates cargo |
| INV-05 | A previously resolved transaction is not applied twice | Lost acknowledgement repeats a transfer |
| INV-06 | A supported door state has a route or bounded manual recovery | One credential holder permanently blocks a player |
| INV-07 | Down/recovery/control-loss durations are bounded | Repeated stuns remove a participant for the whole round |
| INV-08 | Client claims cannot grant authority | Forged damage, arbitrary position or faction assignment |
| INV-09 | Forbidden listeners do not receive private media | Honest client mutes audio that a modified client can still hear |
| INV-10 | A rule/content version is explicit for a room | Mixed clients interpret an objective differently |

## Transaction states
| Action | Preconditions | Atomic state change | Cancellation/recovery |
| --- | --- | --- | --- |
| Pickup | Item free, valid range, capacity, current revision | Holder changes once; revision increments | Rejected stale claim gets current allowed view |
| Give/transfer | Actor owns item, recipient eligible/in range and accepts | Ownership moves once | Timeout leaves original ownership; no half-transfer |
| Shared carry | Enough eligible participants and route/pose valid | One cooperative-action record references carriers | Disconnect releases/parks the object safely under server control |
| Revive | Valid down state, resource and uninterrupted proximity | Consume resource and restore once | Consume a medical charge only on successful completion; interruption uses no charge; no double revive |
| Door override | Door eligible, actor in range, recovery path allowed | Deadline/door revision updated | Timeout/disconnect clears operator state; bounded fallback remains |
| Arm extraction | Correct phase, route ready, core and occupants valid | Countdown owned by room server | Removing prerequisites interrupts; UI explains public cause |
| Fire | Weapon owned, charges/cooldown/pose/phase valid | Consume one charge and create one server projectile | Duplicate shot ID cannot create another projectile |

Handover uses recipient acceptance to avoid forcing unwanted equipment onto a player. Source-of-truth ownership and visual attachment must agree after corrections.

## Countdown semantics
Use server deadlines, not client decrement counters. Clients display estimated remaining time and can correct smoothly. Interruption is a state transition with a reason, not a silent reset. Resolve final-tick completion against the authoritative event sequence; once the outcome commits, later inputs cannot change it.

A unique core cannot satisfy two extraction routes simultaneously. If both routes are armed at different times, only the route with current valid prerequisites can complete. Proposed tick order: apply accepted commands in the server-assigned sequence, advance authoritative movement/projectiles, resolve interaction changes, then evaluate due deadlines ordered by their absolute server deadline. For exactly equal terminal deadlines, an unrecovered required roster slot causes interruption first, then a still-valid extraction takes precedence over station failure. An already committed result cannot be overwritten by a later deadline. Revalidate prerequisites immediately before committing. Two simultaneously valid extractions with one unique core are an invariant violation: fail the round as interrupted and retain diagnostic evidence, rather than arbitrarily inventing a winner. Test the policy explicitly; never depend on dictionary iteration order. The [roster contract](round-roster-and-continuity.md) supplies the grace/occupancy cases.

## Proposed failure responses
| Failure | Player-facing response | Authoritative/operational response |
| --- | --- | --- |
| Brief packet loss | Continue local presentation; show delayed action state when necessary | Sequence inputs, reject stale transactions, bounded reconciliation |
| Connection lost | Reconnecting indicator and a cancellable return-to-lobby path | Reserve identity for initial 60-second grace; freeze/release unsafe interactions |
| Any fixed-roster participant fails to return | Uniform honest interruption explanation without faction inference | Same grace for every slot; interrupt a still-active H1 round; no fabricated faction win |
| Session service unavailable | Retry with clear status; never show a fake joined room | Reject new admissions; avoid corrupting active room authority |
| Voice unavailable | Visible voice warning, local mute and pings | Fail closed for channels requiring confidential routing; bounded retries |
| Room server crashes | Return to room/retry or explicit interrupted result | H1 restarts in lobby; do not claim seamless mid-round recovery |
| Unsupported client/content | Explain update requirement before entry | Reject handshake; no partial participation |
| App backgrounds | Clear held controls and transmit intent | Stop stale input, apply platform audio policy and reserve reconnect identity |
| Renderer fault | Supported settings/variant and useful diagnostics | Track affected configuration; no automatic claim that device driver is fixed |

## Identity and capabilities
Room codes are discovery, not blanket administrative permission. Join tickets have a bounded lifetime and room/version scope. Derive permissions server-side. A lobby owner can configure allowed presets before start and remove a disruptive participant through a defined host-control path; they cannot grant themselves secret-state access or declare a competitive winner during a match.

Do not expose faction-specific failure codes to bystanders. Public rejection examples: out of range, busy, wrong phase, prerequisites changed. Keep private validation details in an authorised context.

## Version and migration policy
Use protocol major/minor plus content/rules IDs. Reject incompatible majors. Declare which minor combinations are supported; absence of a compatibility test means unsupported. A new map/tool action needs versioned capability data and a server validator. Pin a room to its version through completion, then roll new clients/rooms deliberately.

The schema is a draft for commands, not a complete network protocol: joining, acknowledgements, snapshots, privacy policy and media signalling still require implementations and companion schemas before P2/P4 gates can pass.

The [combat contract](combat-counterplay-and-recovery.md) adds proposed tag/recovery/charge semantics. The [social contract](social-roles-and-agreements.md) defines future agreement revisions and evidence provenance; those H2 messages are not supported by the current draft command schema.
