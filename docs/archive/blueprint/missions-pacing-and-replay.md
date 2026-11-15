# Missions, pacing and replay

Version 0.3, 2026-11-12. Proposed content design. H1 still has one shared repair, one sabotage, one core and rival extractions. The catalogue below supplies curated extensions, not six extra mandatory chores in every round.

## Build a decision, then an interaction

A mission card records a shared need, who can contribute, an object or location, alternative solutions, visible consequences, progress persistence, failure recovery and the information it publishes. A player should be able to explain why the action matters before performing it.

The interaction should release attention for talking: align a cell in an obvious socket, negotiate a route, decide where to use a kit, or inspect a local instrument. Avoid random wiring screens, repeated tapping and long isolated timers whose only purpose is to consume time. A difficult input sequence is not automatically an interesting mission.

## Curated mission catalogue

| ID | Mission and social decision | Alternative/recovery | Horizon |
| --- | --- | --- | --- |
| MIS-01 | Cell relay: two carriers choose how to bring a power cell from Engineering to Reactor | Park/release at a safe point; public manual route recovery; another eligible carrier can replace one | H1 baseline candidate |
| MIS-02 | Cargo inspection: compare a local manifest with a case at Cargo; decide whether to share the result | Slower physical inspection supplies the core-identification fallback; no identity verdict | H2 |
| MIS-03 | Medical reserve: deliver an optional kit from Cargo to Medical or keep it mobile for a rescue | Basic bounded medical recovery remains available even if the delivery is skipped | H2 |
| MIS-04 | Coolant bypass: choose a repair approach at Reactor after power returns | Clear progress survives a handover; slower manual recovery prevents a unique-tool softlock | H2 |
| MIS-05 | Door bus repair: restore convenient credential operation at Security | Timed manual override and tested alternate routes remain available | H2 |
| MIS-06 | Relay alignment: restore the common radio service from Command | Proximity and contextual pings remain; real connection faults have separate UI | H2 |

The [mission fixture](../specs/mission-cards.v1.json) assigns versioned IDs, references and prerequisites to these proposals. None is a runtime quest implementation. Cargo inspection reports a case property, not a player's secret allegiance. Do not combine all cards into the first session.

## More than one contribution per situation

For the cell relay, possible contributions include carrying, choosing a route, checking a hatch, bringing an access token, negotiating with its holder or preparing the destination. Not every person must hold a button. A shared object has safe release and continuity so a player can change tasks.

Use checkpoints only where the physical state supports them: a seated cell stays seated; an interrupted tool action does not magically complete. The server records authoritative progress and its revision. Never silently duplicate a cell as a recovery shortcut.

## Pacing by phase, not a compulsory script

| Phase | Desired decision | Public cue | What must stay possible |
| --- | --- | --- | --- |
| Orientation | Where do I go; what can I contribute? | Named sectors, shared goal, visible equipment | Ask, inspect, practise, decline a responsibility |
| Stabilisation | Which route and resources should we commit? | Shared power state and repair feedback | Negotiate, regroup, exchange tools |
| Divergence | Who should carry the core and watch the alternatives? | Core availability and partial evidence | Genuine cooperation, escort, theft or observation |
| Crisis | What should we interrupt or save? | Local incident plus explicit extraction warning | Counterplay, rescue, manual recovery |
| Resolution | Why did this outcome occur? | Server result and scoped event timeline | Ask questions, rematch or leave |

The 12–15 minute round remains a tuning hypothesis. Measure these phases before assigning an exact duration to each. Players may avoid a crisis or reach extraction early; do not spawn a retaliatory incident simply because someone is winning. A quiet regrouping period is useful if the group chooses it.

## Replay comes from combinations with consequences

Vary a small number of understandable conditions: starting equipment placement, a selected mission route, a tested hatch inconvenience, or one public system event. Keep the base station recognisable so a second round rewards learning. Present the chosen rules/preset before ready confirmation; reveal only information players are entitled to know during play.

Private role assignment must use an independent server-side source of randomness, not a seed sent to clients for visible content. Reproducing a mission layout is not permission to derive the infiltrator. A debrief can identify the public variant after resolution without disclosing future assignments.

Curated presets precede a combinatorial generator:

| Preset | Intended session | Content rule |
| --- | --- | --- |
| Rehearsal | Learn movement, voice, handover and the cell | No infiltrator, no weapon, no random crisis |
| Last Departure baseline | First complete deduction mode | H1 shared repair and one sabotage; fixed readable equipment |
| Rescue emphasis | H2 test of optional medical decisions | Add MIS-03; compare with baseline without changing weapon rules |
| Service disruption | H2 test of one inconvenient system | Choose one of MIS-05 or MIS-06; preserve recovery |
| Negotiation | H2 power experiment | Change service allocation only; do not also change roles/map/weapon |

These presets need their own evidence and are not supported options in the current APK.

## The danger of predictable or unbeatable play

- If all players escort the core together every round, inspect whether timing/routes create any meaningful cost before imposing artificial separation.
- If delaying the round always benefits one faction, inspect repair/extraction requirements and the station-loss outcome. A station loss still benefits neither faction.
- If the best infiltrator strategy is immediate violence, compare access/ammunition and non-weapon opportunities before adding more weapons.
- If rescue is consistently irrational, review cargo, recovery and outcome rules rather than inventing an invisible kindness score.
- If players always camp a doorway, test sightlines, bypass time and objective placement; more random events may only disguise a layout problem.

Treat these as candidate strategies to observe, not solved equilibria. Do not promise that a paper rule eliminates a dominant strategy.

## Debrief and continued play

Show the outcome, decisive extraction/cargo facts and a short optional factual timeline. Do not rank players by supposed honesty, intelligence or friendship. Any voluntary recognition should describe a concrete event and avoid a score that can be farmed by repeatedly injuring/reviving a friend.

A later cosmetic expedition can connect independent missions through a hangar emblem, souvenirs or decorations. A lost round need not erase weeks of social progress. Shared decoration edits require permissions/undo; no one should be able to spend someone else's currency or delete their ownership. Economy and monetisation need a separate decision before implementation.

See [content authoring](content-authoring-and-tuning.md) for validation and [playtesting](../game-design/playtesting.md) for comparisons.
