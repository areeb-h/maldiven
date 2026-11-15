# Drift Station — roadmap

Updated 2026-11-15.

**Principle:** build the smallest fun thing, play it with friends every week, cut what's boring, double down on what creates stories.

**One rule for gates:** did people want another round? If yes, move on. Measured tech checks (frame time, latency, battery) only where a real problem shows up.

## Week 1 — Playable round

- [ ] Station greybox (8 rooms, two loops) + art pass (trim lighting, emergency red, space backdrop, suits)
- [ ] Listen-server host/join + LAN discovery, manual IP fallback
- [ ] Roles: one infiltrator, private role cards
- [ ] Cells → reactor → core → shuttle / pod
- [ ] Shove
- [ ] Blackout sabotage
- [ ] 10-minute round timer
- [ ] Result screen + event timeline
- [ ] Rematch back to lobby
- [ ] Touch controls
- [ ] Android build (0.4.0)

**Done when:** 5 rounds with friends in one room.

## Week 2 — Physical chaos

- [ ] Ragdoll knockdowns
- [ ] Carry bodies and objects with physics
- [ ] Throwables
- [ ] Stun tool
- [ ] Airlock that can eject someone into space
- [ ] Doors with manual override

**Done when:** someone laughs or yells.

## Week 3 — Voice + remote play

- [ ] In-game proximity voice (port Friends Lab PCM, then Opus if needed)
- [ ] Radio channel
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
