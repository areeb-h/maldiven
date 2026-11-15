# ADR 0025: Listen server for the prototype

Date: 2026-11-15. Status: Accepted. Supersedes [ADR 0006](../archive/adr/0006-authoritative-multiplayer.md) (dedicated authoritative server) for the prototype.

## Context
We need friends playing full rounds this week. A dedicated authoritative server, PC launcher and invite tickets are a lot of machinery before we know the game is fun.

## Decision
Use Godot's built-in high-level multiplayer (`ENetMultiplayerPeer` + RPCs) with a listen server: any phone or PC hosts and plays.

- Clients are authoritative over their own movement and send it at ~20 Hz.
- The host is authoritative over items, roles, timers and round outcomes.
- Roles are sent privately, only to their owner.
- LAN discovery by UDP broadcast (port 24601), with manual IP entry as fallback. Game traffic on UDP 24600.
- Late joins are refused while a round runs.

## Consequences
- The host could cheat. Fine for friends.
- No dedicated server, PC launcher or invite flow is needed to play.
- Internet play needs a tunnel or relay (week 3).
- Revisit if/when we go public: dedicated server, server-side movement checks, reconnect.
