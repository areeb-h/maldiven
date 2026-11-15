# Drift Station — roadmap

Updated 2026-11-15.

**Principle:** build the smallest fun thing, play it with friends every week, cut what's boring, double down on what creates stories.

**One rule for gates:** did people want another round? If yes, move on. Measured tech checks (frame time, latency, battery) only where a real problem shows up.

## Week 1 — Playable round

- [x] Station greybox (8 rooms, two loops) + art pass (trim lighting, emergency red, space backdrop, suits)
- [x] Listen-server host/join + LAN discovery, manual IP fallback
- [x] Roles: one infiltrator, private role cards
- [x] Cells → reactor → core → shuttle / pod
- [x] Shove
- [x] Blackout sabotage
- [x] 10-minute round timer
- [x] Result screen + event timeline
- [x] Rematch back to lobby
- [x] Touch controls
- [ ] Android build (0.4.0)

**Done when:** 5 rounds with friends in one room.

## Week 2 — The gun question

- [x] One gun in the Security armory (3 rounds, aim-assisted, walls block), unlocks with power
- [x] Downed state: drop everything, get up after 25 s or get revived at the medbay
- [x] Drag downed players
- [x] Airlock off Commons: 3.5 s warning, vents everyone inside
- [x] Spaced players become ghosts (fly through walls, visible only to other ghosts)
- [x] New wins: space the infiltrator (crew) / space all crew (infiltrator)
- [x] Throwing: shove while carrying throws it; hits stun and knock items loose
- [x] Rules tests for every mechanic + networked bot round: shoot → drag → airlock
- [ ] Character ragdoll-style downed/ghost/aim poses (procedural crew model)
- [ ] Gunshot tracer, decompression and revive VFX + sounds
- [ ] Lobby warm-up arena: paintball shooting and shoving while you wait
- [ ] Doors with manual override (moved from week 2 plan; needs door art)

**Done when:** someone laughs or yells, and "who gets the gun?" becomes an argument.

## Week 3 — Voice + remote play

- [ ] In-game proximity voice (port Friends Lab PCM, then Opus if needed)
- [ ] Radio channel
- [ ] Ghosts hear each other, not the living (until week 4's window-banging)
- [ ] Internet play via tunnel/relay

**Done when:** a full remote round with no Discord.

## Week 4 — The signature

- [ ] Vacuum is silent: depressurised sections cut proximity voice, only radio works
- [ ] Infiltrator can vent a section or jam the radio
- [ ] Dead players drift outside the hull: bang on windows, exterior cameras, one vote at the intercom
- [ ] Emergency intercom in Command: anyone can call a meeting
- [ ] Maybe 2 infiltrators at 7–8 players

**Done when:** a round where the silence or the dead changed the outcome.

## Weeks 5+ — Make it pretty and repeatable

- [ ] Art and audio pass
- [ ] Mission variants
- [ ] Cosmetic suits
- [ ] Settings
- [ ] Onboarding

Then public/online questions (relay, matchmaking) only if friends keep asking to play.

## Parking lot

Good ideas from the [archived blueprint](archive/blueprint/), not scheduled:

- **Power routing negotiation** — limited power, more systems than it can feed; someone has to choose.
- **Event director** — a small set of authored station incidents that keep pressure up without scripting outcomes.
- **Docking modules** — a visiting module docks mid-round with a shortcut and new places to hide things.
- **Gravity rooms** — one compartment with low or no gravity; slow-floating cargo first.
- **Salvage Shift** — co-op mode with no traitor, just the station trying to kill you.
- **Double Contract** — teams with partly conflicting cargo goals who can negotiate.
- **Agreement cards** — lightweight in-game "I'll escort you" promises that the timeline remembers.
- **Better debrief timeline** — map replay, per-player paths, "who saw what" highlights.

## Known risks

- Android rendering bands on one phone → Compatibility renderer fallback ([ADR 0004](adr/0004-device-rendering-workaround.md)).
- Voice echo without AEC → headphones first, then a proper voice stack if it hurts.
- LAN broadcast blocked on some routers / Android → manual IP entry.
- Host can cheat → acceptable among friends.
- Phones overheating in long sessions → check only if people complain; lighter effects first.
