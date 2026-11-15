class_name BotNav
extends RefCounted
## Waypoint graph over the station for bot players (see scripts/bots/README.md).
##
## Built from StationLayout: room centres, a 2 m grid inside every room, the
## corridor centre lines, the doorway points where corridors meet rooms, ramp
## feet and tops (StationLayout.PLATFORMS), socket approach points and item
## spawns. With a physics space, points that overlap station geometry (layer 1:
## walls, decor, socket fixtures, deck railings) are dropped and links are kept
## only when a crew-sized capsule can sweep along them; without one (pure tests)
## links follow the layout rectangles and the deck rule (change height only on
## a ramp). A* runs on an AStar3D. Pushable props and players are dynamic: the
## brains steer around those locally.

const GRID := 2.0  # m between room grid points
const ROOM_MARGIN := 0.9  # grid points stay this far from room walls
const CLEARANCE := 0.46  # capsule radius for point and link checks (crew capsule is 0.38)
const LINK_RANGE := 3.2  # m: candidate links
const SAMPLE := 0.25  # m between samples on a link (layout check)
const CAPSULE_BOTTOM := 0.3  # m: lower obstacles are stepped over
const CAPSULE_TOP := 1.7

var astar := AStar3D.new()
var points: Array[Vector3] = []
var kinds: Array[String] = []  # "room", "grid", "corridor", "door", "ramp", "approach", "item"
var regions: Array[String] = []  # room or corridor id the point lies in
var room_point := {}  # room id -> point index (its centre, or the clear point nearest it)
var approach_point := {}  # socket id -> point index
var physics_checked := false
var _space: PhysicsDirectSpaceState3D
var _capsule: CapsuleShape3D
var _buckets := {}  # Vector2i cell -> Array[int]

static var _shared: BotNav


## The graph for this station, built once per process (the layout never changes).
## Pass the world's space so geometry is respected; a layout-only graph is
## rebuilt with physics the first time a space is available.
static func shared(space: PhysicsDirectSpaceState3D) -> BotNav:
	if _shared == null or (space != null and not _shared.physics_checked):
		_shared = BotNav.new()
		_shared.build(space)
	elif space != null:
		_shared._space = space  # a new round's world: same geometry, new space
	return _shared


static func approach_of(socket_id: String) -> Vector3:
	var spec: Dictionary = StationLayout.SOCKETS[socket_id]
	var front := Vector3(sin(spec.facing), 0, cos(spec.facing))
	var at := StationLayout.to_world(spec.pos) + front * 1.2
	return Vector3(at.x, StationLayout.floor_height(at), at.z)


func build(space: PhysicsDirectSpaceState3D) -> void:
	_space = space
	physics_checked = space != null
	_capsule = CapsuleShape3D.new()
	_capsule.radius = CLEARANCE
	_capsule.height = CAPSULE_TOP - CAPSULE_BOTTOM
	astar.clear()
	points.clear()
	kinds.clear()
	regions.clear()
	_buckets.clear()
	for room_id in StationLayout.ROOMS:
		var rect := StationLayout.room_rect(room_id)
		var centre: Vector2 = StationLayout.ROOMS[room_id].center
		_add(centre, "room", room_id, true)
		var half := (rect.size * 0.5 - Vector2(ROOM_MARGIN, ROOM_MARGIN))
		var nx := int(floor(half.x / GRID))
		var nz := int(floor(half.y / GRID))
		for ix in range(-nx, nx + 1):
			for iz in range(-nz, nz + 1):
				if ix == 0 and iz == 0:
					continue
				_add(centre + Vector2(ix, iz) * GRID, "grid", room_id)
	for corridor_id in StationLayout.CORRIDORS:
		var spec: Dictionary = StationLayout.CORRIDORS[corridor_id]
		var rect := StationLayout.corridor_rect(corridor_id)
		var link: Vector2 = StationLayout.ROOMS[spec.b].center - StationLayout.ROOMS[spec.a].center
		var along_x := absf(link.x) > absf(link.y)
		var length: float = spec.size.x if along_x else spec.size.y
		var axis := Vector2(1, 0) if along_x else Vector2(0, 1)
		var start: Vector2 = rect.get_center() - axis * length * 0.5
		# Doorways: where the corridor meets each room wall.
		_add(start, "door", corridor_id, true)
		_add(start + axis * length, "door", corridor_id, true)
		var steps := maxi(1, int(round(length / GRID)))
		for k in range(1, steps):
			_add(start + axis * (length * float(k) / float(steps)), "corridor", corridor_id)
		_add(rect.get_center(), "corridor", corridor_id)
	for platform_id in StationLayout.PLATFORMS:
		var ramps: Array = StationLayout.PLATFORMS[platform_id].ramps
		for i in range(ramps.size()):
			var rr: Array = StationLayout.ramp_rect(platform_id, i)
			var rect: Rect2 = rr[0]
			var up: Vector2 = rr[1]
			var length: float = ramps[i].length
			var room: String = StationLayout.PLATFORMS[platform_id].room
			_add(rect.get_center() - up * (length * 0.5 + 0.7), "ramp", room)
			_add(rect.get_center(), "ramp", room)
			_add(rect.get_center() + up * (length * 0.5 + 0.7), "ramp", room)
	for socket_id in StationLayout.SOCKETS:
		var at := approach_of(socket_id)
		approach_point[socket_id] = _add(Vector2(at.x, at.z), "approach", str(StationLayout.SOCKETS[socket_id].room), true)
	for item_id in StationLayout.ITEMS:
		if StationLayout.ITEMS[item_id].has("pos"):
			var p: Vector2 = StationLayout.ITEMS[item_id].pos
			_add(p, "item", StationLayout.room_at(StationLayout.to_world(p)))
	for room_id in StationLayout.ROOMS:
		if not room_point.has(room_id):
			room_point[room_id] = _nearest_in_region(StationLayout.to_world(StationLayout.ROOMS[room_id].center), room_id)
	_link_all()


## Adds a point unless it overlaps geometry (or lies outside the deck). Keeps
## `force`d ones regardless and returns their index (else -1 when dropped).
func _add(flat: Vector2, kind: String, region: String, force := false) -> int:
	var at := StationLayout.to_world(flat)
	at.y = StationLayout.floor_height(at)
	if not StationLayout.is_walkable(at):
		return -1
	for index in _near(at, 0.6):
		if points[index].distance_to(at) < 0.6:
			if kind == "approach" or kind == "door":
				kinds[index] = kind
			return index
	var blocked := _blocked(at)
	if blocked and not force:
		return -1
	if blocked and kind == "room":
		return -1  # a decor piece stands on this room's centre: the nearest grid point stands in
	var index := points.size()
	points.append(at)
	kinds.append(kind)
	regions.append(region)
	astar.add_point(index, at)
	if kind == "room":
		room_point[region] = index
	var cell := _cell(at)
	if not _buckets.has(cell):
		_buckets[cell] = []
	_buckets[cell].append(index)
	return index


func _cell(at: Vector3) -> Vector2i:
	return Vector2i(int(floor(at.x / LINK_RANGE)), int(floor(at.z / LINK_RANGE)))


func _near(at: Vector3, radius: float) -> Array:
	var out := []
	var c := _cell(at)
	var reach := int(ceil(radius / LINK_RANGE))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if _buckets.has(key):
				out.append_array(_buckets[key])
	return out


func _nearest_in_region(at: Vector3, region: String) -> int:
	var best := -1
	var best_d := INF
	for index in range(points.size()):
		if regions[index] != region:
			continue
		var d := points[index].distance_to(at)
		if d < best_d:
			best_d = d
			best = index
	return best


func _link_all() -> void:
	for a in range(points.size()):
		for b in _near(points[a], LINK_RANGE):
			if b <= a:
				continue
			if _flat(points[a] - points[b]).length() > LINK_RANGE:
				continue
			if clear_line(points[a], points[b], true):
				astar.connect_points(a, b)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## A crew capsule standing here overlaps station geometry.
func _blocked(at: Vector3) -> bool:
	if _space == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, (CAPSULE_BOTTOM + CAPSULE_TOP) * 0.5, 0))
	query.collision_mask = PhysicsLayers.WORLD
	return not _space.intersect_shape(query, 1).is_empty()


## Can a crew member walk straight from a to b? Layout rule always (inside rooms
## and corridors with clearance, height changes only on ramps); with physics, a
## capsule sweep against the station geometry as well.
func clear_line(a: Vector3, b: Vector3, strict := false) -> bool:
	var flat := _flat(b - a)
	var length := flat.length()
	if length > 0.01:
		var side := Vector2(-flat.y, flat.x) / length * CLEARANCE
		# With physics the capsule sweep finds the walls; a few layout samples
		# still keep links inside the station's rooms and corridors.
		var count := int(ceil(length / SAMPLE)) if not physics_checked else 2
		var last_h := StationLayout.floor_height(a)
		for k in range(count + 1):
			var p := _flat(a) + flat * (float(k) / float(count))
			var p3 := Vector3(p.x, 0, p.y)
			if not StationLayout.is_walkable(p3):
				return false
			if strict and (not StationLayout.is_walkable(Vector3(p.x + side.x, 0, p.y + side.y)) \
					or not StationLayout.is_walkable(Vector3(p.x - side.x, 0, p.y - side.y))):
				return false
			var h := StationLayout.floor_height(p3)
			if absf(h - last_h) > 0.05 and not _on_ramp(p) and not physics_checked:
				return false  # off a deck edge (no railing data without physics)
			last_h = h
	if _space == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	var mid := (CAPSULE_BOTTOM + CAPSULE_TOP) * 0.5
	query.transform = Transform3D(Basis.IDENTITY, a + Vector3(0, mid, 0))
	query.motion = (b - a)
	query.collision_mask = PhysicsLayers.WORLD
	var result := _space.cast_motion(query)
	return result.size() == 0 or result[0] >= 1.0


func _on_ramp(p: Vector2) -> bool:
	for platform_id in StationLayout.PLATFORMS:
		for i in range((StationLayout.PLATFORMS[platform_id].ramps as Array).size()):
			var rect: Rect2 = StationLayout.ramp_rect(platform_id, i)[0]
			if rect.grow(0.3).has_point(p):
				return true
	return false


## The graph point to enter from `at`: the nearest one in a straight clear line.
func nearest(at: Vector3) -> int:
	var candidates := []
	for index in _near(at, LINK_RANGE * 1.5):
		candidates.append([_flat(points[index] - at).length(), index])
	if candidates.is_empty():
		var any := astar.get_closest_point(at)
		return any
	candidates.sort_custom(func(x, y): return x[0] < y[0])
	for k in range(mini(candidates.size(), 6)):
		if clear_line(at, points[candidates[k][1]]):
			return candidates[k][1]
	return candidates[0][1]


## World-space waypoints from `from` to `to` (ends at `to`); empty if no route.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _flat(to - from).length() < 10.0 and clear_line(from, to):
		out.append(to)
		return out
	var a := nearest(from)
	var b := nearest(to)
	if a < 0 or b < 0:
		return out
	out = astar.get_point_path(a, b)
	if out.is_empty() and a != b:
		return out
	out.append(to)
	return out


## Route length in metres (INF when unreachable).
func route_length(from: Vector3, to: Vector3) -> float:
	var route := path(from, to)
	if route.is_empty():
		return INF
	var total := 0.0
	var last := from
	for p in route:
		total += _flat(p - last).length()
		last = p
	return total


## True when every room's point reaches every other room's point.
func rooms_connected() -> bool:
	var first: int = room_point.values()[0]
	for room_id in room_point:
		var index: int = room_point[room_id]
		if index < 0 or (index != first and astar.get_id_path(first, index).is_empty()):
			return false
	return true


## A random clear point in a room (for wandering).
func random_point(room_id: String, rng: RandomNumberGenerator) -> Vector3:
	var pool := []
	for index in range(points.size()):
		if regions[index] == room_id and kinds[index] in ["grid", "room"]:
			pool.append(index)
	if pool.is_empty():
		return points[room_point.get(room_id, 0)]
	return points[pool[rng.randi_range(0, pool.size() - 1)]]
