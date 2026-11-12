# System design and interaction economy

Version 0.3. Proposal. H1 is the baseline slice; later entries are explicitly staged experiments. All balance numbers remain tuning hypotheses.

## Common simulation vocabulary
Every interactable has an entity ID, capabilities, authoritative state/revision, interaction range, visible feedback, recovery behaviour and optional public evidence. Players use the same verbs wherever possible: inspect, carry, give, use, operate, interrupt and revive. New content should reuse these contracts.

## System catalogue
| System | H1 behaviour | H2/H3 expansion | Recovery/invariant |
| --- | --- | --- | --- |
| Access | Credentials, public doors, timed manual override | Transferable permissions and local routing | No permanent veto by one disconnected player |
| Power | Restore one supply with a shared cell | Route limited capacity among services | Change is visible; emergency navigation persists |
| Cargo | Unique restricted core and ordinary props | Cargo contracts, inspection and visiting modules | An item has one owner/container at a time |
| Injury | Down, drop cargo, revive or medical recovery | Additional bounded injury states if useful | Inactivity/protection are bounded and visible |
| Communications | Proximity and one common radio | Intercom, team channels and explicit interference | Technical failure and intentional outage are distinguishable |
| Evidence | Partial truthful event/credential facts | Local sensors and limited forensics | System records never fabricate events |
| Extraction | Two rival routes and interruptible countdowns | Contract-specific escape conditions | One terminal outcome; no client-decided winner |
| Environment | One readable sabotage/critical failure | Seeded event combinations with a pressure budget | Recovery route or explicit terminal failure exists |
| Social expression | Emote, ping, handover, identifiable equipment | Crew decor, shared map annotations, hangar activities | Expression cannot spoof system authority or hidden identity |
| Physics | Bounded carry/drop, stable shared props | Tethered loads and gravity compartments | Server owns interactions; cosmetic debris cannot block goals |

## Power as a negotiation system
An H2 prototype can give the station three available power units and four service demands: communications relay, cargo control, medical support and observation/security. This is an illustrative tuning setup, not a proven optimum. The console explains consequences before commitment. Emergency signs, basic movement and a slow manual recovery remain available.

A player can change a switch, but cannot permanently monopolise the whole round. An override, alternative route or time-bounded recovery must exist. Do not punish the least vocal player by assigning them repetitive console duty. Make switching a decision rather than a click-frequency test.

## Information has an economy too
Evidence should answer a narrow question: which credential operated this door, whether this power circuit changed, whether a case was opened. It should leave intent open to discussion. A system record cannot identify a role, expose hidden inventory or assert an accusation as fact.

Radio is a common broadcast resource, not a private telepathy channel. Local speech supports a smaller conversation; radio reaches separated friends and exposes that message to the common channel. Always indicate the destination/audibility of a transmission. More channels are justified only after players understand the first two communication paths.

## Tools and weapons as interaction opportunities
| Tool concept | Meaningful use | Cost/counterplay | Introduction |
| --- | --- | --- | --- |
| Engineering cutter | Open a jammed hatch or repair a connection | Time, noise and visible work | H1 |
| Medical kit | Rescue someone and recover the team's options | Finite supplies; public medical recovery fallback | H1 |
| Stun projector | Interrupt a theft, defend a route or create a rescue | Visible weapon, limited charges, bounded injury | H1 combat experiment |
| Portable shield | Cover a repair, retreat or negotiation | Blocks a limited direction; limited energy | H2 |
| Magnetic tether | Guide a heavy load or retrieve equipment | Anchored range, line of sight, counter-release | H2 |
| Signal beacon | Mark a rendezvous or request help | Location/intent become public to recipients | H2 |
| Diagnostic scanner | Inspect a local system or cargo property | Range/time; imperfect scope | H2 |
| Energy sidearm | Higher-stakes conflict if nonlethal mode succeeds | Clear damage/recovery rules; separate preset | H2/H3 |
| Door brace | Briefly secure a retreat | Time cap, visible brace and public cutting point | H2 |

Do not add hidden one-shot eliminations simply to increase tension. A weapon's launch criterion includes whether people still contribute and communicate. Friendly fire consequences must be understandable; hidden damage multipliers or role-specific weapon immunity undermine fairness.

## Physics and gravity
H1 uses kinematic/controlled carry interactions for predictable networking. A shared load has one server-owned coordination state and multiple participants, not competing client physics owners. Release/drop resolves consistently if one carrier disconnects.

Gravity variation is an H3 compartment experiment: fixed entry/exit volumes, bounded movement rules and explicit transition feedback. Begin with slow-floating cargo before fully free player orientation. Verify camera comfort, motion sensitivity, recovery and network collision. Cosmetic sparks/debris do not become persistent obstacles or authoritative projectiles.

## Event director
Start with a small authored catalogue. Each event defines prerequisites, affected entities, warning, pressure cost, duration, recovery paths and incompatible events. The server selects only candidates satisfying the station graph and phase constraints. Use a logged seed for reproducibility; physics is still authoritative and is not assumed deterministic across machines.

Pressure is a design budget, not psychological profiling. Do not choose a victim from voice tone, inferred emotion or perceived vulnerability. Do not secretly alter faction outcomes, accuracy or ammunition. Escalation comes from public station conditions and documented event rules.

## Controlled complexity
Introduce one new decision at a time. An event cannot simultaneously disable voice, erase navigation and remove every route. Before scheduling a second incident, test whether the first already consumes the group's attention. Reveal the sequence in the debrief when appropriate so players can distinguish system events from intentional interference.

## Abuse and dominant-strategy review
For every mechanic, ask: Can one player monopolise it? Can it trap someone indefinitely? Does disconnect permanently remove a required item? Can it reveal a secret through error text or audio routing? Can an optimal player ignore everyone? Can a quiet player still act? If an answer threatens the pillars, redesign the mechanic before adding variations.

## Detailed extensions

Public jobs and acknowledgements are [optional H2 social experiments](social-roles-and-agreements.md), not exclusive classes or honesty scores. [Curated missions](missions-pacing-and-replay.md) need capability/recovery checks and independent secret-role randomisation. The [combat preset](combat-counterplay-and-recovery.md) is a versioned tuning proposal, not an implemented balance result. The [roster policy](round-roster-and-continuity.md) applies the same grace/interruption response to every participant.
