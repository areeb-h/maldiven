# Drift Station physics

Host-authoritative physics for a listen-server phone game. The host simulates;
clients render. Nothing a client simulates can change gameplay state.

## Collision layers

| Bit | Value | What | Collides with (mask) |
| --- | --- | --- | --- |
| 1 | 1 | World: station geometry, socket fixtures | — (static) |
| 2 | 2 | Remote players (CharacterBody3D puppets) | world, players |
| 3 | 4 | Local player (CharacterBody3D) | world, players, **props** |
| 4 | 8 | Loose items (host RigidBody3D / client replica) | world, items, props (+ proxies while thrown) |
| 5 | 16 | Pushable props (host RigidBody3D / client kinematic replica) | world, items, props, proxies |
| 6 | 32 | Player proxies (host-only AnimatableBody3D) | — (kinematic, pushes) |
| 7 | 64 | Ragdoll parts (client-local, cosmetic) | world only |

Constants live in `physics_layers.gd` (`PhysicsLayers`). Client item replicas
have no collision at all; client prop replicas are solid for the local player.

## Pieces

- `station_physics.gd` (`StationPhysics`, one per `StationWorld`): item bodies,
  props, proxies, airlock decompression, keep-clear nudges, respawns,
  replication (host send / client receive + interpolation).
- `net_body.gd` (`NetBody`): a replicated RigidBody3D (item or prop). Host:
  dynamic, CCD, sleeping. Client: frozen kinematic replica with a 100 ms
  interpolation buffer.
- `player_proxy.gd` (`PlayerProxy`): host-side kinematic capsule per player.
  Remote players' proxies are *led* by RTT + 125 ms (the clients'
  interpolation delay + half a pose interval) using the velocity in their pose
  packets, so a pushed prop is already moving when the pushing client sees it.
- `net_codec.gd` (`NetCodec`): 12 bytes per body (id, flags+epoch, 3 × s16
  position at 5 mm, smallest-three quaternion in 32 bits).
- `crew_ragdoll.gd` (`CrewRagdoll`): 11 Jolt bodies, cone-twist joints (spine,
  neck, shoulders, hips) and limited hinges (elbows, knees), created in the rig's
  rest pose so limits are pose independent, then moved to the live pose.
  Velocity clamps and a finite check; limbs that start inside walls are pulled
  out first. Writes bone rotations into `CrewModel.bones` and calls `_upload()`.
- `crew_reactions.gd` (`CrewReactions`): per-avatar reaction layer on top of the
  model's animation: stagger (angular springs + catch-balance steps with IK),
  ragdoll collapse then blend into the downed pose, dangling limbs while carried
  (verlet chains), and the spaced corpse (weightless ragdoll that fades to a ghost).
- `props/prop_factory.gd`, `props/prop_layout.gd`: procedural prop meshes and
  colliders (crate, small crate, barrel, cart, chair, toolbox, canister), the 28
  starting spots and the keep-clear zones.

## Authority and the rules

- `StationRules` keeps the logical item state: `{kind, holder, pos, rot, vel,
  socket, ammo, flight, moving, lost, epoch}`. An item with `holder == 0` and
  no socket is *loose*: the host has an active body for it and writes its pose
  into `pos/rot/vel/moving` every physics tick, so pickup ranges and snapshots
  stay right.
- `epoch` increments whenever an item becomes loose or teleports (drop, throw,
  knock-loose, respawn). The host reactivates the body at the rules pose and
  launch velocity; clients drop stale interpolation samples.
- Throws: `rules._throw` gives the item a velocity (8.4 m/s along the facing,
  3.4 m/s up, scaled by kind) and `flight = {by, start}` (hot). The host tests
  hot items against standing proxies every tick (`StationPhysics._try_hit`) and
  calls `rules.item_hit()` for the same stun/drop as a shove; a hot item cools
  when it slows below 1.6 m/s, or after 2.5 s.
- Without physics (`rules.physics_driven == false`, unit tests) throws follow a
  simple ballistic arc with a distance hit test.
- Vented items get `lost` (they drift for 3 s, then return to their dock);
  bodies that fall out of the world or rest out of reach for 4 s respawn.

## Replication

- Stream: host → clients at 25 Hz, `unreliable_ordered` on its own channel (1),
  only bodies that are awake, plus 6 packets after a body falls asleep or
  teleports (so the rest pose survives packet loss). Sleeping bodies cost
  nothing.
- Keyframes: reliable, every 3 s, only bodies that changed since the last one;
  a full state goes to a client when its world asks (`Net.request_physics_sync`).
- Clients estimate the host clock from the fastest packets and render each body
  100 ms in the past, interpolating position (lerp) and rotation (slerp),
  bridging a late packet by ≤ 80 ms of extrapolation, and snapping on teleports
  or > 4 m jumps.

### Bandwidth (8 players: host + 7 clients)

Per packet: 5 B header + 12 B/body + ~60 B RPC/ENet/UDP/IP overhead.

| Situation | Awake bodies | Per client | Host upload (7 clients) |
| --- | --- | --- | --- |
| Quiet station | 0 | 0 B/s | 0 B/s |
| Typical scrum (a thrown cell, a few props) | 6 | ~3.3 KB/s | ~23 KB/s |
| Airlock vent / everything moving (worst case) | 33 | ~11.4 KB/s | ~80 KB/s (seconds) |

Pose packets grew by one Vector3 (velocity): +240 B/s per client upstream.

## Players

- Local movement stays client-authoritative (`crew_member.gd`): momentum,
  slopes up to 46°, floor snap, step-up for ledges ≤ 0.25 m (visual eases up),
  knockback that slides along and bounces off walls (no tunnelling: shape-cast
  movement, speed capped at 24 m/s), pushing a prop costs speed by its mass
  (`push` in `PropFactory.SPECS`), heavy props slamming into you knock you back
  (`bumped` events from the host).
- Airlock decompression: during the 3.5 s warning a growing pull towards the
  outer door acts on bodies (force) and on players (a velocity bias of up to
  2.8 m/s in the chamber, 2.2 in the corridor, fading into Commons). Walking out
  is possible but slow; standing still slides you in. On vent, everything in
  the chamber is blown out through the door (collision off, weightless).

## Budget

28 props + 5 items, all sleeping when still. Ragdolls: at most 4 at once,
only within 34 m of the camera, physics bodies only while active (≈ 1–3 s),
then back to the animated rig. The physics tick stays 60 Hz.
