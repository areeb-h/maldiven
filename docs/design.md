# Drift Station — design

Updated 2026-11-15. This is the one design doc. If it disagrees with anything in `docs/archive/`, this wins.

## Pitch

A dying space station, a handful of friends, one traitor. Everyone needs the power back on. Only some of you want the same ending. Drift Station is a third-person 3D social-deduction game for 2–8 friends on Android phones (and PC), played in short, loud rounds full of shoving, carrying, blackouts and betrayal. It should make stories you retell afterwards: "I had the core, I was *at the shuttle*, and Sam shoved me into the dark."

How we work: **find the fun first, harden later.** Build the smallest fun thing, play it with friends every week, cut what's boring, double down on what creates stories.

## Pillars

- **Useful cooperation.** The station needs hands. Carrying cells and guarding the core give people real reasons to team up, and the traitor a reason to help at first.
- **Readable uncertainty.** You always know what happened (lights went out, the core moved, the pod is armed). You don't know who meant it.
- **Transferable equipment.** Items, not classes. Anything can be dropped, taken, handed over or stolen. Nobody is the only one who can fix something.
- **No long inactivity.** Rounds are short, stuns are short, and from week 4 even the dead keep playing.

## The round

2–8 players. One is the **infiltrator**; everyone else is **crew**. A round lasts at most 10 minutes.

1. **Briefing (~6 s).** Everyone spawns in Commons. Each player sees a private role card. Roles go only to their owner.
2. **Stabilise.** The power is out. Emergency red lighting only. Three power cells are lying loose in Engineering, Medical and Security. Carry them to the three Reactor sockets. The infiltrator wants this too: without power the core stays locked.
3. **Extraction.** The third cell goes in, the lights come up, and the core vault in Command and the armory in Security unlock. Now interests split, and somebody is about to pick up the only gun.
   - **Crew win:** load the core into the shuttle in Docking and survive the 30 s launch countdown. Anyone can pull the core back out to abort.
   - **Infiltrator win:** load the core into the cargo pod in Cargo. Only the infiltrator can arm it. Arming sets off a station-wide alarm and a 20 s countdown. Anyone can pull the core out.
   - **Station lost:** the 10-minute round timer runs out. Everyone loses.
   - **Spaced:** cycle the airlock with the infiltrator inside and the crew win on the spot. Space every crewmate and the infiltrator wins.
4. **Result.** The outcome, who the infiltrator was, and a short event timeline of the round: who moved which cell, who took the core, who shoved whom, when the blackout hit. The host can send everyone back to the lobby for a rematch.

## Roles

- **Crew.** Restore power, get the core onto the shuttle, keep an eye on each other.
- **Infiltrator.** Look like crew. Help restore power (or not). Get the core into the pod. Has one extra verb: sabotage.

At 7–8 players we'll try two infiltrators (week 4).

## The map

One deck, about 84 × 52 m, eight rooms in two loops plus an airlock. The layout lives in `scripts/station_layout.gd`; geometry, rules and tests all read from it.

| Room | What's there |
| --- | --- |
| Commons | Spawn, the social junction, the airlock console |
| Airlock | Small dead-end chamber off Commons. Cycle it and anyone inside is spaced |
| Command | Core vault (locked until power is back) |
| Security | Power cell, the armory (one gun) |
| Docking | The shuttle (crew escape) |
| Cargo | The cargo pod (infiltrator escape) |
| Engineering | Power cell |
| Reactor | Three cell sockets |
| Medical | Power cell, the medbay (instant revive) |

- **Public loop:** Docking – Commons – Command – Security – Cargo – Docking.
- **Service loop:** Cargo – Engineering – Reactor – Medical – Commons. Long, quiet corridors: good for a private chat or an ambush.

The core's two exits (shuttle and pod) sit one corridor apart, in Docking and Cargo. That's deliberate: every extraction is contested.

## Verbs

| Verb | Who | Notes |
| --- | --- | --- |
| Walk / run / jump | Everyone | |
| Carry | Everyone | One item at a time. Carrying slows you down. |
| Interact | Everyone | Pick up, drop, insert into a socket, pull out of a socket. |
| Shove | Everyone | Short range. Knocks the target back, stuns ~1 s, makes them drop what they carry (or the body they're dragging). 3 s cooldown. |
| Throw | Everyone | Shove while carrying something throws it ~7 m. A hit stuns for 1.6 s and makes the target drop what they carry. |
| Shoot | Whoever holds the gun | One gun, 3 rounds, never refills. Aim-assisted (about 20° cone, 18 m, walls block). A hit downs the target. |
| Drag | Everyone | Pick up a downed player and drag them (slow). Drop them anywhere, revive them at the medbay, or put them in the airlock. |
| Cycle airlock | Everyone | 3.5 s warning with klaxon and countdown, then everything inside is vented. 20 s cooldown. |
| Sabotage: Blackout | Infiltrator | Station-wide lights out for ~25 s. Name tags hidden, flashlights only. 75 s cooldown. |

**The gun question.** There is exactly one gun and it unlocks when the power comes back. Whoever holds it is the most trusted or most feared person aboard, and it can be shoved or thrown out of their hands. Being shot doesn't kill you: you're **downed** for 25 s (or until someone revives you at the medbay), you drop everything, and you're a body someone can drag. The only real death is the airlock, which takes teamwork or a good ambush. Spaced players become **ghosts**: they float through walls, see everything, and only other ghosts can see them.

Shove is still the everyday tool: slapstick, fair (everyone has it), and it turns every core run into a scrum.

## Communication

- **Week 1:** no in-game voice. Play in the same room or on a Discord call. That's fine. It tells us if the round is fun before we spend weeks on audio.
- **Week 3:** in-game proximity voice, ported from the Friends Lab PCM voice code ([experiment notes](pc-server-and-phone.md)), plus one radio channel everyone can hear.
- **Week 4:** vacuum cuts proximity voice (see below).

## Networking

Listen server ([ADR 0025](adr/0025-listen-server-prototype.md)). Any phone or PC hosts from the main menu and plays. Others on the same Wi-Fi see the room automatically, or type the host's IP. The host owns items, roles, timers and outcomes; each client owns its own movement. The host could cheat. Among friends, we don't care.

## Look

Readable industrial sci-fi, built to run on phones. Emissive trim lighting, emergency red during Stabilise and the blackout that warms up when power comes back, stars and a planet through the windows, glow, props, and coloured crew suits with helmets so you can tell people apart at a glance.

## Bold ideas

These are why this game exists. Week 2 and week 4 are built around them.

- **Vacuum is silent.** Depressurised sections cut proximity voice. Only the radio works. The infiltrator can vent a section or jam the radio. Shouting at someone through a window who can't hear you is the game.
- **The dead drift outside.** Players thrown out of an airlock (or otherwise dead) float outside the hull. They can bang on windows, watch through exterior cameras and get one vote at the intercom. Nobody sits on a death screen.
- **Physical comedy.** Jolt ragdolls, carrying bodies and objects, throwing things, airlocks that eject people into space. When something goes wrong it should look funny.
- **Optional emergency intercom.** No compulsory meetings. Anyone can walk to Command and call one. Calling it is itself a move that people will read into.
- **Blackout and flashlights.** Darkness turns a known room into a stranger's room. Name tags vanish, beams sweep, someone grabs the core.
- **The timeline is the story.** The end-of-round timeline is a story generator: "wait, *you* had cell two?" Make it good enough that people argue over it before hitting rematch.

## Not doing yet

Public matchmaking, accounts, dedicated servers, anti-cheat, reconnect, ranked anything, monetisation, multiple maps, procedural stations, more weapons, NPC enemies, a big role roster, spaceflight. Some of these come back if friends keep asking to play. Ideas we liked but parked are in the [roadmap parking lot](roadmap.md#parking-lot); the full earlier plan is in the [archive](archive/README.md).
