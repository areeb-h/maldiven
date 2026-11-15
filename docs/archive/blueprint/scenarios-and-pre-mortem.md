# Scenario cookbook and pre-mortem

Version 0.2. Tabletop tests first, then automated/in-device reproductions. These scenarios are acceptance work, not claims they currently pass.

## Core scenario cases
| ID | Setup/action | Expected behaviour | Contracts |
| --- | --- | --- | --- |
| SC-01 | Two people pick up the core on the same tick | One succeeds; the other receives an allowed stale/busy response; no duplicate core | INV-01/05 |
| SC-02 | A giver disconnects while a recipient accepts | Transfer is either committed once or cancelled with original ownership; no half-state | INV-01/04/05 |
| SC-03 | One carrier backgrounds mid-hatch | Held input/transmit clears; load parks/drops safely; route remains recoverable | INV-04/06 |
| SC-04 | A credential holder locks a teammate in and leaves | Alternate route or timed manual override remains; role not exposed by error text | INV-03/06 |
| SC-05 | Core leaves an armed shuttle at the deadline | Authoritative ordering cancels or completes exactly once according to the documented tick rule | INV-01/02 |
| SC-06 | Infiltrator's connection fails during extraction | Grace/identity policy is applied; no new role or fabricated victory | INV-02/04 |
| SC-07 | A client replays a successful shot/transfer packet | It cannot create more projectiles, consume twice or duplicate an item | INV-05/08 |
| SC-08 | A client requests a remote hit through a closed door | Server rejects/does not apply it; client visuals reconcile | INV-08 |
| SC-09 | Two players chain-stun a recovering player | Protection and duration rules bound exclusion; feedback is visible | INV-07 |
| SC-10 | A modified listener subscribes to a forbidden voice track | Service/server denies delivery; volume-only muting is not accepted as a pass | INV-09 |
| SC-11 | A late join or spectator inspects room traffic | They receive only their allowed lobby/spectator view; no active secret facts | INV-03/10 |
| SC-12 | Voice drops while station radio interference is active | UI distinguishes connectivity failure from the fictional event; pings remain usable | INV-09 |
| SC-13 | Two incidents would close every path to medical | Director rejects the invalid combination or provides a tested bounded recovery | INV-06 |
| SC-14 | An old client tries to join a newly deployed room | Version handshake explains incompatibility; no partial ghost participant | INV-10 |
| SC-15 | A muted new player is ignored during discussion | They retain useful actions/pings; playtest captures exclusion rather than averaging it away | Pillars/PT-02/06 |
| SC-16 | Everyone uses the common radio continuously | Channel behaviour is legible; evaluate whether local conversation has value and whether UI/mixing needs simplification | PT-02 |
| SC-17 | Players always abandon rescues to optimise extraction | Examine incentives and contribution; revise win/cargo/recovery rules instead of blaming players | PT-04/06 |
| SC-18 | An owner removes a disruptive participant | Host-control policy handles identity/role fairly and interrupts if needed; host cannot declare themselves winner | INV-02/03/04 |
| SC-19 | Server process crashes with a core in transit | Clear interrupted/lobby recovery; no false promise of seamless round continuation | INV-01/02 |
| SC-20 | A driver fault reproduces the two horizontal bands | Compare supported Mobile+MSAA/Compatibility configurations and record device evidence | DEV-001 |

## Narrative playtests
### The locked hatch
Two carriers approach a hatch while the credential holder is elsewhere. Test three solutions: negotiation over radio, manual override, alternate route. Observe whether all three are understandable and whether one player becomes an involuntary door attendant.

### The honest witness
A player sees a credential operate a door; the credential has been transferred earlier. Test whether truthful partial evidence supports a fair disagreement and whether the debrief resolves it. If the interface states a person's guilt, the evidence design is wrong.

### The rescue bargain
A downed player drops cargo. Another player can rescue, take the cargo, call help or guard the route. Observe meaningful choice, recovery time and whether one option dominates every round. Add no scripted reward that secretly favours betrayal.

### The visiting module (H3)
A cargo module docks and opens a new connection. Validate topology, audibility and authority before testing new contracts. The event must not silently strand players, create duplicate worlds or invalidate extraction rules.

## Pre-mortem: assume the alpha disappoints
| Failure story | Leading indicator | Prevention/response |
| --- | --- | --- |
| 'It looks good, but we do not talk about anything useful' | Conversation unrelated to actions; solo-optimal play | Shared decisions/objects, fewer chores and PT-01 |
| 'The loudest friend runs every round' | Repeated low agency for others | Transferable tools, pings, independent evidence and mixed-participation tests |
| 'We spend more time fixing voice than playing' | Echo, unclear transmit/route states, many reconnects | P1 audio gate before art expansion |
| 'Guns turn it into random attacks' | Immediate downing and retaliation loops | Compare no-weapon mode; adjust or remove current combat experiment |
| 'The game cheats when someone is winning' | Unexplained interventions or inconsistent deadlines | Public rules, bounded director, deterministic result ordering |
| 'Nobody understands why we lost' | Poor outcome recall; false accusations of bugs | Clear countdowns/rejections and factual debrief |
| 'A quiet player cannot participate' | Repeated low inclusion despite high group average | Actionable pings, optional mic, visible responsibilities and per-player review |
| 'A small update breaks half the phones' | Unpinned native dependencies or missing device checks | Reproducible builds, compatibility matrix and pilot rollout |
| 'More content made performance collapse' | Long-frame/thermal regressions in the same route | Representative art slice and enforced measured budgets |
| 'We cannot afford active rooms' | Unknown voice fan-out/idle room usage | Measure early; admission/cleanup limits and owner-approved budget |

Use a pre-mortem to create tests and alternatives, not to declare these failures inevitable.
