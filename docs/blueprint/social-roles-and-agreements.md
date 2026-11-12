# Social roles, agreements and evidence

Version 0.3, 2026-11-12. Proposed design. This extends the experience blueprint without adding mandatory role classes to H1. The job board and agreements below are H2 experiments; H1 keeps transferable equipment, pings and ordinary conversation.

## Separate three kinds of role

| Layer | Example | Who can know it | Can it change? |
| --- | --- | --- | --- |
| Secret allegiance | Crew or infiltrator | Own private briefing; server knows all | Fixed for the round; no reconnect reroll |
| Public responsibility | Carry coordinator, repair lead, medic, scout, quartermaster | Anyone who sees the voluntary job board | Accept, relinquish or hand over at any time |
| Equipment capability | Cutter, medical kit, access token | Visible equipment and permitted inspection | Transfer through the ownership contract |

A repair lead is not automatically crew. A medic is not the only person allowed to revive. A security responsibility confers no power to reveal roles, eject a player or overrule the server. Starting equipment must not correlate with secret allegiance unless a later explicit mode changes that rule and explains it.

Public responsibilities are lightweight offers to coordinate, not exclusive classes. A job can be unclaimed or shared. The board never assigns an unwanted chore to the quietest participant. Private faction role assignment remains the server's job, with the disclosed distribution and no use of personality or microphone behaviour.

## Public jobs worth experimenting with

| Job | Useful choice | Handover opportunity | Failure to watch |
| --- | --- | --- | --- |
| Repair lead | Choose a route and ask for a tool or carrier | Give a tool and explain current progress | Everyone else waits for one expert |
| Quartermaster | Suggest where scarce tools should go | Offer a kit; recipient can decline | Hoarding all equipment becomes an absolute veto |
| Scout | Inspect a route and share a narrow observation | Ping a destination or guide a new player | Scouting becomes a complete live map of everyone |
| Medic | Decide whether a rescue changes the plan | Transfer supplies or ask someone to guard | Healing becomes a compulsory service role |
| Carry coordinator | Set a destination and release point | Another participant takes over without reset | Required coordination is just awkward controls |
| Security escort | Protect a transfer or mediate access | Relinquish the weapon or escort responsibility | One friend imposes mandatory obedience |

These are possible social contributions rather than six fixed slots. Test the board against ordinary self-organisation; remove it if it turns conversation into administration.

## Agreements create shared context, not guaranteed honesty

An H2 agreement card might say: **Meet at Engineering; bring the cutter; return it after the repair.** It has an author, named participants, a concrete world reference, optional acknowledgement, expiry and visible status. It must be quick to create with presets rather than a mobile typing exercise.

Proposed states: offered → acknowledged → completed, withdrawn or expired. Only an explicit recipient action acknowledges. A network delivery receipt means delivered, not understood or agreed. Changing the location/item creates a new revision and invalidates earlier acknowledgement. Participants can withdraw; the card is not a permanent contract.

The server can verify only narrow facts it actually observes, such as an item transfer or repair completion. It cannot verify that a player intended to help, promised sincerely or was morally justified. Do not silently mark a player dishonest, deduct reputation, force a transfer or award a faction advantage for breaking an agreement. Keeping or breaking a promise is part of the round's social interpretation.

## Facts, observations and claims

| Information type | Example | Presentation | Restriction |
| --- | --- | --- | --- |
| Authoritative public fact | Cargo pod countdown started | System event with server time | Reveal only the rule's public scope |
| Limited instrument fact | Credential K opened hatch 4 | Source, time and credential ID | Do not rewrite this as its original owner's identity |
| Personal observation | A player saw a case carried through a doorway | Player-authored statement or ping | Not certified by the server as a complete account |
| Agreement acknowledgement | A player accepted a tool-return plan | Named acknowledgement with revision | Not a lie detector or enforced intention |
| Accusation/inference | Someone thinks the scout stole the core | Clearly player-authored claim | Never style it as an official verdict |

System evidence remains truthful; players may misinterpret, omit or lie about what they know. The first mode has no fabricated system logs or hacked evidence that looks indistinguishable from trusted UI. A future forged-document mechanic needs a separate readable provenance rule before it can be added.

## Example: a disagreement with more than one response

1. Security records that credential K opened Cargo. Its original holder says they gave K away.
2. A witness saw a similar suit in the corridor but did not inspect the credential.
3. The group can request a handover, inspect a local record, negotiate an escort, guard an extraction route or keep repairing.
4. No interface combines those facts into a guilt percentage. There is no compulsory accusation meeting or automatic ejection.
5. The debrief can show the relevant transfer and hatch event with their scope, allowing an honest witness to have been mistaken.

## Participation without a microphone

The first contextual intents are **need help**, **bring item**, **meet here**, **acknowledged**, **cannot do this**, and **danger here**. Messages reference a valid visible sector/object or a location the player can legitimately select. They do not create enemy tracking, reveal a hidden role or prove that an area is safe.

Keep mute controls reachable during a round. Private groups may talk outside the game, so voice secrecy cannot be treated as an anti-collusion guarantee. Test the experience with one muted player, mixed language fluency, friends who disagree and friends who always defer to one organiser. Do not force equal speaking time or penalise silence.

## Acceptance experiments

- **SX-01 job handover:** the repair lead leaves the console; another player continues without exclusive skill permissions or a full objective reset.
- **SX-02 acknowledgement revision:** change an agreement after acceptance; the UI must show that the changed version is not yet accepted.
- **SX-03 truthful disagreement:** use the credential example; players can explain both the fact and what it does not prove.
- **SX-04 quiet contribution:** a muted player initiates a successful handover/rescue plan using supported pings.
- **SX-05 authority spoof:** a custom name, marker or agreement cannot resemble a server warning or imply administrative powers.
- **SX-06 social pressure:** observe whether declining a job or agreement is practically acceptable; redesign if the feature repeatedly enables exclusion.

See [coordination research](../research/coordination-and-participation.md) for supporting ideas and limitations, and [ADR 0016](../adr/0016-allegiance-jobs-and-equipment.md) / [ADR 0017](../adr/0017-evidence-provenance-and-agreements.md) for the proposed decisions.
