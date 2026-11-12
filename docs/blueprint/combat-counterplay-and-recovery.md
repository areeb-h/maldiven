# Combat, counterplay and recovery

Version 0.3, 2026-11-12. Proposed experiment specification extending ADR 0009. H1 tests one stun projector after the no-weapon round works. The later tool catalogue is not an instruction to build an arsenal first.

## Every weapon needs a social use and a response

The stun projector should interrupt a theft, cover a repair, protect a rescue or create space to retreat. For each use, record what the target can perceive and do. Surprise is allowed; invisible, uninterruptible exclusion is not the intended first mode.

| Situation | Holder's choice | Other player's response | Failure to detect |
| --- | --- | --- | --- |
| A case is carried toward the pod | Warn, escort, fire or guard another approach | Drop/return cargo, retreat, use cover or ask for help | Shooting everyone is always cheaper than checking |
| A repair is contested | Cover a teammate or negotiate access | Alternate route, visible interruption or regroup | Repair is impossible without the one armed friend |
| Someone is down | Rescue, guard, recover cargo or leave | Teammate approaches from another route; medical fallback | Body camping dominates every following action |
| A weapon changes hands | Accept a voluntary transfer or leave it | Recipient can decline; others see the new holder | A transfer duplicates ammunition or hides ownership |

No faction gets invisible resistance or special aiming rules. The weapon model, projectile and interaction feedback need readable silhouettes on a phone.

## Proposed first tuning preset

These are **unvalidated starting values**, to change in a versioned preset after observation. They do not alter the current executable.

| Parameter | Initial candidate | Reason to measure/change |
| --- | --- | --- |
| Down threshold | Two confirmed hits within the tag window | Can the target recognise danger and respond? |
| Tag window | 8 seconds after the most recent confirmed hit | Too short rewards spam; too long makes old damage confusing |
| Weapon charges | Six per round, belonging to the weapon | Enough for choices without unlimited suppression |
| Fire cooldown | 1 second, server-enforced | Test reaction and aim comfort under delay |
| Down inactivity cap | 30 seconds, as already proposed | Include travel/revive and interruptions in the actual measurement |
| Revive commitment | 3 seconds of valid proximity | Long enough to expose a choice; short enough to preserve participation |
| Recovery protection | At most 4 seconds | Prevent immediate chains without enabling a protected attack |

Range, projectile speed, spread and aim assistance remain CMB-001 measurement decisions before the first group combat test. Do not add invisible accuracy handicaps based on whether someone is winning. Confirm/lock these values with an explicit content/rules ID before comparison sessions.

## Injury state and control

Proposed states are ready, tagged, down and recovering. A first hit gives an immediate clear visual/audio cue without forced camera shaking. An expired tag returns to ready. A second valid hit inside the window enters down, drops carried cargo once and cancels unsafe interactions. Downed players can use supported communication/pings; they do not become hidden spectators with extra information.

A successful revive consumes a medical charge once and enters recovering. If the inactivity deadline arrives first, bounded medical recovery applies. At an exactly equal revive/recovery deadline, commit one recovery transition and consume a charge only if the revive transaction wins the server's documented ordering. Damage received while already down must not restart the cap. Keep recovery/public connection state visible without disclosing allegiance.

Recovery protection blocks incoming stun, but cannot protect an attack or core transport: an accepted fire, core pickup or hostile interruption request ends protection before eligibility/damage resolution. Refuse attacks while down. Moving to cover or using a ping does not end protection. The server enforces these rules; a client icon is not the protection mechanism.

Medical return needs an authored clear spawn and safe fallback. Do not create a collision pile in the bay, teleport someone into a locked space or return their dropped core to them. If a valid return point is unavailable, record the fault and use a tested fallback rather than extending inactivity indefinitely.

## Ammunition is a conserved resource

Charges attach to the unique weapon, not to its current holder or reconnect session. Drop, give, disconnect, revive and rejoin never refill it. A rejected/duplicate shot does not create a projectile or consume another charge. The default round has no automatic refilling; a later recharge station is a separate economy experiment with ownership and camping checks.

Balance must use actual hit/miss/interrupt events and player explanations. Total damage is not a measure of useful contribution. Do not award a persistent kill leaderboard or hidden bounty for repeated friendly attacks in the initial social mode.

## Disarm and consent

H1 offers voluntary handover and pickup of an unheld weapon; it does not add an instant remote confiscation command. Forced disarm is an H2 experiment only if the base response options are insufficient. It would need visible range/commitment, interruption, a clear dropped-item result and the same anti-duplication rules as cargo.

Host removal is an explicit social control, not a combat move or a guilt verdict. Apply the [roster policy](round-roster-and-continuity.md) without granting a competitive win.

## Tool combinations to earn later

| Combination | Intended moment | Required restriction |
| --- | --- | --- |
| Shield + repair | Hold a direction while another repairs | Bounded arc/energy, visible counter-route, no permanent corridor seal |
| Tether + cargo | Recover a dropped load or guide it through a module | Anchored limits, release, no player restraint in the first tether test |
| Beacon + rescue | Ask someone to approach a known route | Scoped marker, expiry, no automatic enemy reveal |
| Cutter + brace | Trade a temporary hold for a noisy manual opening | Public cutting point and bounded delay on relevant sides |
| Energy sidearm + recovery | Test greater stakes in a separate preset | Explicit injury/elimination, voice and spectator rules first |

## Combat acceptance cases

- **CX-01:** transfer a weapon after three shots; exactly three of the proposed six charges remain.
- **CX-02:** shoot a recovering player repeatedly; incoming hits neither restart recovery nor extend down time.
- **CX-03:** a protected player requests fire/core pickup; protection cannot survive the accepted aggressive action.
- **CX-04:** down a carrier in a hatch; cargo drops once, the route has recovery and the camera remains usable.
- **CX-05:** revive and automatic recovery are due together; one state transition and at most one correct resource deduction occur.
- **CX-06:** compare the same group/rules with and without the weapon; record rescue, retaliation, exclusion and explanations of outcomes.

These supplement SC-07–SC-09 and PT-04. A successful automated case does not establish enjoyable combat.
