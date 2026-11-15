# Spatial design and map families

Version 0.3, 2026-11-12. Proposed design. The eight-sector [station topology](../specs/station-map.v1.json) remains the H1 source of truth. This document adds encounter and readability constraints rather than replacing its edges with an untested new map.

## A room needs a social purpose

| Sector | Intended encounter | Landmark/interaction cue | Camping or confusion risk |
| --- | --- | --- | --- |
| Docking | Regroup, escort and decide who boards | Large shuttle silhouette and visible boarding boundary | One position controls all departure approaches |
| Commons | Meet, divide work and hear shared status | Central station model, seating edge, broad sign views | All useful play happens here; the rest becomes transit |
| Command | Compare partial information and communicate | Observation window and recognisable instrument wall | A console provides a complete player-tracking map |
| Security | Negotiate access and equipment handover | Visible equipment rack and distinct hatch framing | A credential holder permanently vetoes everyone |
| Cargo | Inspect, carry and dispute ownership | Core cradle silhouette and clear pod warning | Core and pod are so close that theft has no response window |
| Engineering | Arrange a shared load and prepare a route | Cell socket, workbench and obvious safe parking point | Props create collisions or a carrier is trapped |
| Reactor | Complete a shared repair under pressure | Large stable machinery shape and repair state | Visual effects obscure people, exits or progress |
| Medical | Rescue, recover and change plans | Recovery bay and supply station with several approaches | Recovery protection creates a safe firing/cargo exploit |

Landmarks use shape, text/pictogram and placement; colour supports them. The decorative language should make a screenshot recognisable without requiring the HUD.

## Distances mean opportunities to react

Measure four routes separately: spawn-to-first-useful-action, Engineering-to-Reactor carry, Cargo-to-pod loading, and the longest supported intervention route to a warning. The earlier 20–40 second distant-route target and provisional 20-second pod countdown may conflict. Do not claim every distant player can always stop a launch.

The first greybox must measure ordinary and carrying speeds, hatch delays, warning delivery, recognition, turn-around and interaction time. Decide deliberately which positions offer a realistic response and which require assigning a guard in advance. If theft is effectively instant, add a visible preparation/loading step or reposition the pod interface before changing the whole station scale.

Use a reaction budget as a design worksheet:

**Available warning time − network/notice delay − travel − required interruption action = response margin.**

This is not a guaranteed human reaction model. Record observed recognition times and individual differences in actual play. A positive arithmetic margin alone does not prove the situation feels fair.

## Encounters without permanent chokepoints

Provide a meeting area and narrower transitions, but do not give a single corridor permanent control over every critical objective. Validate both logical connectivity and usable clearance for a shared load, downed body and camera. A connected graph can still be physically unusable.

For every approved hatch condition, record: remaining objective paths, manual recovery location/time, cargo clearance, line of sight, possible camping positions and whether a disconnected avatar can obstruct the route. Manual operation needs an understandable interaction point on both relevant sides.

The planning check found ten disconnected cases among 36 two-corridor closure combinations. Treat those as forbidden incident combinations until a bounded recovery is authored and tested. A pretty map overview cannot overrule the topology result.

## Sight and sound are different maps

An observation window can reveal a carried object without carrying speech. A wall can hide someone while the common radio remains audible. Test these deliberately. The HUD must not imply that a nearby voice is definitely in a room if the routing only knows a coarse acoustic zone.

Use explicit acoustic portals/room adjacency first. A hatch transition needs a documented policy for gaining/losing listeners and a measured service acknowledgement delay. Service-enforced routing reduces delivery to forbidden recipients; it cannot retract audio already delivered or stop a recipient recording it. Do not advertise instantaneous perfect privacy at a moving doorway.

## Third-person camera and touch constraints

The camera can reveal around corners. Choose the permitted advantage deliberately and test symmetric access from both sides. The server still validates shots from authoritative muzzle/geometry; seeing over an obstacle must not allow firing through it.

Test doors at close camera distance, turning while carrying, handover near a wall, downed posture, extraction crowded by six avatars and UI readability against bright windows. A camera fade is presentation, not permission to expose private entity fields. Avoid tiny interaction points and rails that repeatedly snag a landscape-phone player.

## Map family, after the first station works

| Family | Social identity | New mechanic justified | Horizon and entry gate |
| --- | --- | --- | --- |
| Relay station | Close meetings, readable loops, short interventions | Establish the existing systems | H1 |
| Salvage yard | Escort a load between a station and one attached module | Docking, bounded module authority/audio | H3 after EXP-09 |
| Research ring | Observe across windows, coordinate a slow floating load | One controlled gravity compartment | H3 after EXP-10 |
| Twin-crew berth | Bargain across two docked spaces | Boarding contracts and participant boundary | H3 after EXP-13 |
| Expedition stop | A familiar crew returns to a new authored problem | Independent mission continuity and cosmetic hub | H4 after EXP-14 |

These are content directions, not promises of additional release maps. Avoid rebuilding the physics, weapons and UI for every theme. Exterior views can convey scale without committing to fully flyable space or continuous planet travel.

## Greybox evidence sheet

Record route times, encounter locations, missed warnings, repeated wrong turns, camera obstruction, shared-object stalls, camping positions and phone frame/thermal results. Compare a changed route against the same rules/build conditions. Finish one readable public junction and one service segment only after these observations are useful.
