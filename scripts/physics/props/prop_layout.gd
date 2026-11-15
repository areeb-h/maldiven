class_name PropLayout
extends RefCounted
## Where the pushable props start, and the zones they must never block.
##
## Placement rules (checked by tests/physics_smoke.gd and enforced at runtime by
## StationPhysics' keep-clear nudge):
## - clear of static geometry and of every socket fixture,
## - never on a socket approach point, an item spawn, a player spawn or the
##   room centres the bots teleport to,
## - never inside a doorway volume, so a doorway can be partly blocked by a
##   tumbling prop but never sealed.

## [kind, Vector2(x, z), yaw, room-or-corridor whose colour the accent uses]
const PROPS := [
	["crate_small", Vector2(-4.6, -24.6), 0.3, "command"],
	["chair", Vector2(5.0, -23.8), PI, "command"],
	["toolbox", Vector2(5.6, -15.2), 0.4, "command"],
	["crate", Vector2(44.8, -22.4), 0.2, "security"],
	["barrel", Vector2(45.9, -25.1), 0.0, "security"],
	["chair", Vector2(40.5, -23.6), PI, "security"],
	["crate_small", Vector2(-2.6, -6.3), 0.25, "commons"],
	["barrel", Vector2(2.8, -6.3), 0.0, "commons"],
	["chair", Vector2(6.4, -3.0), 2.0, "commons"],
	["cart", Vector2(-4.6, 5.9), 0.0, "commons"],
	["toolbox", Vector2(2.8, 6.3), -0.5, "commons"],
	["canister", Vector2(-14.35, -1.55), 0.0, "airlock"],
	["toolbox", Vector2(-14.25, 1.5), 0.6, "airlock"],
	["barrel", Vector2(16.6, 5.2), 0.0, "docking"],
	["crate", Vector2(21.3, 5.0), -0.15, "docking"],
	["chair", Vector2(24.6, 3.0), -2.2, "docking"],
	["barrel", Vector2(39.4, 6.3), 0.0, "cargo"],
	["crate", Vector2(40.65, 6.1), 0.1, "cargo"],
	["canister", Vector2(42.6, -6.2), 0.0, "cargo"],
	["toolbox", Vector2(62.2, -4.4), 0.2, "engineering"],
	["barrel", Vector2(57.2, 4.9), 0.0, "engineering"],
	["crate", Vector2(66.6, -3.6), -0.3, "engineering"],
	["canister", Vector2(56.0, 25.2), 0.0, "reactor"],
	["crate_small", Vector2(67.8, 15.0), 0.4, "reactor"],
	["chair", Vector2(-4.2, 17.75), -PI / 2.0, "medical"],
	["cart", Vector2(5.2, 15.4), 0.2, "medical"],
	["canister", Vector2(6.3, 24.6), 0.0, "medical"],
	["crate_small", Vector2(36.3, 19.6), 0.3, "observation"],
]

## Extra bot/test standing spots that must stay clear (metres, XZ).
const EXTRA_CLEAR := [Vector2(0, -5), Vector2(0, -1.4)]
const APPROACH_CLEAR := 1.25  # radius kept free around socket approach points
const SPAWN_CLEAR := 1.0  # around item and player spawns
const CENTRE_CLEAR := 1.6  # around room centres
const DOOR_DEPTH := 1.1  # how far a doorway's keep-clear volume reaches into each side


static func accent(room: String) -> Color:
	if StationLayout.ROOMS.has(room):
		return StationLayout.ROOMS[room].color
	return Color("8fa3b8")


static func approach_point(socket_id: String) -> Vector2:
	var spec: Dictionary = StationLayout.SOCKETS[socket_id]
	return spec.pos + Vector2(sin(spec.facing), cos(spec.facing)) * 1.2


## Circles [centre: Vector2, radius] that props must not overlap.
static func clear_circles() -> Array:
	var out := []
	for socket_id in StationLayout.SOCKETS:
		out.append([approach_point(socket_id), APPROACH_CLEAR])
	for item_id in StationLayout.ITEMS:
		var spec: Dictionary = StationLayout.ITEMS[item_id]
		if spec.has("pos"):
			out.append([spec.pos, SPAWN_CLEAR])
	for index in range(8):
		var p := StationLayout.spawn_point(index, 8)
		out.append([Vector2(p.x, p.z), SPAWN_CLEAR])
	for room_id in StationLayout.ROOMS:
		out.append([StationLayout.ROOMS[room_id].center, CENTRE_CLEAR])
	for p in EXTRA_CLEAR:
		out.append([p, SPAWN_CLEAR])
	return out


static func approach_circles() -> Array:
	var out := []
	for socket_id in StationLayout.SOCKETS:
		out.append([approach_point(socket_id), APPROACH_CLEAR])
	return out


## Doorway volumes (Rect2 on XZ): where a corridor meets a room, the gap in the
## wall plus DOOR_DEPTH on both sides.
static func door_rects() -> Array:
	var out := []
	for corridor_id in StationLayout.CORRIDORS:
		var spec: Dictionary = StationLayout.CORRIDORS[corridor_id]
		var c := StationLayout.corridor_rect(corridor_id)
		for room_id in [spec.a, spec.b]:
			var r := StationLayout.room_rect(room_id)
			if absf(c.end.y - r.position.y) < 0.01 or absf(c.position.y - r.end.y) < 0.01:
				var z := r.position.y if absf(c.end.y - r.position.y) < 0.01 else r.end.y
				out.append(Rect2(c.position.x, z - DOOR_DEPTH, c.size.x, DOOR_DEPTH * 2.0))
			elif absf(c.end.x - r.position.x) < 0.01 or absf(c.position.x - r.end.x) < 0.01:
				var x := r.position.x if absf(c.end.x - r.position.x) < 0.01 else r.end.x
				out.append(Rect2(x - DOOR_DEPTH, c.position.y, DOOR_DEPTH * 2.0, c.size.y))
	return out


## How far (m) a prop of bounding radius `radius` at `p` intrudes into the nearest
## keep-clear zone, and the flat direction that pushes it out. {} when clear.
## `runtime`: only the zones gameplay needs kept clear while playing (doorways
## and socket approach points), not the spawn and room-centre spots that only
## matter for the starting layout.
static func intrusion(p: Vector2, radius: float, runtime := false) -> Dictionary:
	var worst := {}
	var depth_max := 0.0
	for circle in (approach_circles() if runtime else clear_circles()):
		var offset: Vector2 = p - circle[0]
		var depth: float = float(circle[1]) + radius - offset.length()
		if depth > depth_max:
			depth_max = depth
			worst = {"depth": depth, "dir": offset.normalized() if offset.length() > 0.01 else Vector2.RIGHT}
	for rect: Rect2 in door_rects():
		var grown := rect.grow(radius)
		if not grown.has_point(p):
			continue
		# Push out along the shortest axis (sideways out of the doorway).
		var exits := [[p.x - grown.position.x, Vector2.LEFT], [grown.end.x - p.x, Vector2.RIGHT],
			[p.y - grown.position.y, Vector2.UP], [grown.end.y - p.y, Vector2.DOWN]]
		exits.sort_custom(func(a, b): return a[0] < b[0])
		if exits[0][0] > depth_max:
			depth_max = exits[0][0]
			worst = {"depth": exits[0][0], "dir": exits[0][1]}
	return worst
