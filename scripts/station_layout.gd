class_name StationLayout
extends RefCounted
## Single source of truth for the Drift Station deck: rooms, corridors, sockets,
## item spawns and player spawns. Coordinates are metres on the XZ plane
## (Vector2(x, z)); the floor is at y = 0. Gameplay rules, the geometry builder,
## art and tests all read from here.

const WALL_HEIGHT := 3.2
const CORRIDOR_WIDTH := 3.0

## Rooms: centre and size (x width, z depth).
const ROOMS := {
	"command": {"name": "Command", "center": Vector2(0, -20), "size": Vector2(14, 12), "color": Color("4d7cff")},
	"security": {"name": "Security", "center": Vector2(40, -20), "size": Vector2(14, 12), "color": Color("e04f5f")},
	"commons": {"name": "Commons", "center": Vector2(0, 0), "size": Vector2(16, 14), "color": Color("e8b04a")},
	"docking": {"name": "Docking", "center": Vector2(20, 0), "size": Vector2(14, 12), "color": Color("3fc6a5")},
	"cargo": {"name": "Cargo", "center": Vector2(40, 0), "size": Vector2(14, 14), "color": Color("c9783a")},
	"engineering": {"name": "Engineering", "center": Vector2(62, 0), "size": Vector2(12, 12), "color": Color("f2d43d")},
	"reactor": {"name": "Reactor", "center": Vector2(62, 20), "size": Vector2(14, 12), "color": Color("9b5cff")},
	"medical": {"name": "Medical", "center": Vector2(0, 20), "size": Vector2(14, 12), "color": Color("5fd35f")},
}

## Corridors are axis-aligned rectangles that exactly bridge the gap between two
## room walls. Where a corridor meets a room wall, that wall has a doorway gap of
## CORRIDOR_WIDTH.
const CORRIDORS := {
	"command-commons": {"a": "command", "b": "commons", "center": Vector2(0, -10.5), "size": Vector2(3, 7)},
	"command-security": {"a": "command", "b": "security", "center": Vector2(20, -20), "size": Vector2(26, 3)},
	"security-cargo": {"a": "security", "b": "cargo", "center": Vector2(40, -10.5), "size": Vector2(3, 7)},
	"commons-docking": {"a": "commons", "b": "docking", "center": Vector2(10.5, 0), "size": Vector2(5, 3)},
	"docking-cargo": {"a": "docking", "b": "cargo", "center": Vector2(30, 0), "size": Vector2(6, 3)},
	"cargo-engineering": {"a": "cargo", "b": "engineering", "center": Vector2(51.5, 0), "size": Vector2(9, 3)},
	"engineering-reactor": {"a": "engineering", "b": "reactor", "center": Vector2(62, 10), "size": Vector2(3, 8)},
	"reactor-medical": {"a": "reactor", "b": "medical", "center": Vector2(31, 20), "size": Vector2(48, 3)},
	"medical-commons": {"a": "medical", "b": "commons", "center": Vector2(0, 10.5), "size": Vector2(3, 7)},
}

## Interaction sockets. "accepts" is the item kind it holds.
## facing: yaw in radians the fixture's front faces (towards the room interior).
const SOCKETS := {
	"vault": {"kind": "vault", "room": "command", "pos": Vector2(0, -23.5), "accepts": "core", "facing": 0.0},
	"reactor_1": {"kind": "reactor", "room": "reactor", "pos": Vector2(58, 23), "accepts": "cell", "facing": PI},
	"reactor_2": {"kind": "reactor", "room": "reactor", "pos": Vector2(62, 23.5), "accepts": "cell", "facing": PI},
	"reactor_3": {"kind": "reactor", "room": "reactor", "pos": Vector2(66, 23), "accepts": "cell", "facing": PI},
	"shuttle": {"kind": "shuttle", "room": "docking", "pos": Vector2(20, -1.5), "accepts": "core", "facing": 0.0},
	"pod": {"kind": "pod", "room": "cargo", "pos": Vector2(43.4, 4.5), "accepts": "core", "facing": -PI / 2},
}

## Static fixtures the art pass should build around sockets (non-interactive).
## Shuttle hull occupies the north part of Docking; pod sits in Cargo's SE corner.
const SHUTTLE_HULL := {"center": Vector2(20, -4.2), "size": Vector2(9, 3.4)}
const POD_HULL := {"center": Vector2(45.5, 4.5), "size": Vector2(2.6, 2.6)}

## Starting items. Cells start loose on the floor; the core starts in the vault.
const ITEMS := {
	"core": {"kind": "core", "socket": "vault"},
	"cell_1": {"kind": "cell", "pos": Vector2(64, -3)},
	"cell_2": {"kind": "cell", "pos": Vector2(-4, 23)},
	"cell_3": {"kind": "cell", "pos": Vector2(43, -23)},
}

const PLAYER_SPAWN_CENTER := Vector2(0, 0)
const PLAYER_SPAWN_RADIUS := 3.5


static func room_rect(room_id: String) -> Rect2:
	var room: Dictionary = ROOMS[room_id]
	return Rect2(room.center - room.size / 2.0, room.size)


static func corridor_rect(corridor_id: String) -> Rect2:
	var corridor: Dictionary = CORRIDORS[corridor_id]
	return Rect2(corridor.center - corridor.size / 2.0, corridor.size)


static func to_world(point: Vector2, height := 0.0) -> Vector3:
	return Vector3(point.x, height, point.y)


static func spawn_point(index: int, count: int) -> Vector3:
	var angle := TAU * float(index) / float(maxi(count, 1))
	var offset := Vector2(cos(angle), sin(angle)) * PLAYER_SPAWN_RADIUS
	return to_world(PLAYER_SPAWN_CENTER + offset)


## Room containing a world point, or "" when in a corridor/outside.
static func room_at(point: Vector3) -> String:
	var flat := Vector2(point.x, point.z)
	for room_id in ROOMS:
		if room_rect(room_id).has_point(flat):
			return room_id
	return ""


## True when the flat point is inside any walkable room or corridor.
static func is_walkable(point: Vector3) -> bool:
	var flat := Vector2(point.x, point.z)
	for room_id in ROOMS:
		if room_rect(room_id).has_point(flat):
			return true
	for corridor_id in CORRIDORS:
		if corridor_rect(corridor_id).has_point(flat):
			return true
	return false
