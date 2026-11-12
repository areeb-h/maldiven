# Round roster and continuity

Version 0.3, 2026-11-12. Proposed H1 clarification. This narrows the earlier lifecycle proposal: interruption policy must not itself become an infiltrator detector. See [ADR 0019](../adr/0019-uniform-roster-interruption.md).

## Freeze the competitive roster

Six authenticated identities are fixed when the private briefing begins. No mid-round replacement or active spectator joins the H1 round. Later arrivals may wait in a separate lobby view without active state, live tactical voice or secret data. Reconnect resumes a reserved identity through the authenticated ticket policy; it does not create another slot.

Host configuration changes occur before ready confirmation and clear ready state. The host cannot replace an absent player, reroll roles, transfer their allegiance or grant themselves an extra view during play. Host removal remains available for disruption but cannot manufacture a win.

## Same grace policy for every slot

Use the existing initial 60-second reconnect grace for every participant, irrespective of secret allegiance, equipment or objective involvement. The public status identifies a connection problem, not a faction. If any required roster slot remains absent when its grace expires, a still-active H1 round ends **interrupted**, with neither faction awarded a win.

This replaces an infiltrator-only abort rule: an observer must not be able to identify the absent infiltrator from whether the round aborts. The conservative H1 policy sacrifices continuity when any one person leaves. It can be abused to interrupt a private game; acknowledge this and provide host admission/rematch controls rather than secretly awarding competitive punishment or a role leak. A later smaller-roster continuation mode needs explicit balance, privacy and minimum-crew rules.

## Behaviour during grace

- Clear held movement, fire and microphone transmit intent; the server applies an input timeout.
- Drop/park carried cargo exactly once through the shared interaction contract. No item disappears into a reserved offline inventory merely because its owner left.
- Keep the avatar's injury/location state under server authority; ordinary injury/recovery rules continue. It does not gain invulnerability, remote input or a new role.
- Offline avatars do not count as connected occupants for starting or completing extraction. They cannot permanently obstruct a door or required spawn.
- Reconnect applies current authorised state and acknowledgement history. It does not restore an earlier position, ammunition count, health or ownership snapshot.
- Service-enforced voice membership/transmit eligibility follows current session state. A reconnect cannot keep an old active media membership as a second identity.

Offline inventory beyond carried cargo needs an explicit item-by-item policy before RND-003 is complete; critical transferable tools must have a safe recovery rather than permanent removal. Record such a policy in authoritative data, not an emergency client-side respawn.

## Resolution boundaries

A valid extraction may finish during grace using connected eligible occupants and the unique core. Once that terminal result commits, a later grace timeout cannot overwrite it. If grace expiry and another terminal deadline have exactly the same server timestamp, the proposed policy commits **interrupted** first; then, only for a still-active round, uses the existing extraction-before-station-failure tie policy. Commands accepted earlier in that tick, including an authenticated reconnect, are applied before deadlines as specified in the interaction contract.

All due terminal deadlines are ordered by absolute timestamp; the interruption preference applies only to an exact tie. Recheck required conditions at commit. Test just-before, equal and just-after boundaries rather than relying on frame order or client timers.

A reconnect can cancel its grace deadline only when the authenticated reconnect is received by the server at or before that deadline. A client timestamp is not evidence of timely arrival. Late processing of a command received after expiry must not revive an already expired reservation merely because deadline evaluation has not run yet. Define the exact server receive/sequence clock in NET-001/RND-003 and retain boundary test evidence.

## Acceptance cases

| ID | Case | Expected |
| --- | --- | --- |
| RC-01 | Repeat the same disconnect/expiry for each of six slots, covering both allegiances | Identical public grace/interrupted policy; no faction-specific status |
| RC-02 | Slot returns before deadline | Same identity/role; latest state; no duplicated equipment/media |
| RC-03 | Host removes any participant during an active round | Same absence policy; no competitive winner granted by host |
| RC-04 | Extraction completes before grace expires | Valid result stays committed; later timeout is inert |
| RC-05 | Extraction, grace and station deadline are equal | One interrupted result under the stated tie policy |
| RC-06 | An offline carrier blocks a hatch/holds a critical tool | Safe release/recovery, no permanent obstruction or extra item |
| RC-07 | A newcomer inspects waiting-lobby traffic/audio | No live competitive or secret view |
| RC-08 | A reconnect arrives after expiry but is processed before a delayed timer callback | Server receive deadline still applies; no resurrection of an expired slot |

Report interrupted rounds separately in both reliability and experience evaluation. A policy document does not prove continuity or privacy; the peer harness and physical-phone interruption tests remain required.
