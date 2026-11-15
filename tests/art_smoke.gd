extends SceneTree
## Headless art/collision smoke test for StationBuilder + Props.
##   godot --headless --path . --script res://tests/art_smoke.gd

const CAPSULE_RADIUS := 0.38
const CAPSULE_HEIGHT := 1.8
const GRID := 0.5

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func fail(message: String) -> void:
	failures.append(message)
	print("FAIL: " + message)


func run() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var station: Node3D = StationBuilder.build(world)
	if station == null or station.name != "Station" or station.get_parent() != world:
		fail("build() must add and return a child named Station")
		_finish()
		return
	if station.find_children("*", "WorldEnvironment", true, false).is_empty():
		fail("station needs a WorldEnvironment")
	var shadowed := 0
	for sun in station.find_children("*", "DirectionalLight3D", true, false):
		if (sun as DirectionalLight3D).shadow_enabled:
			shadowed += 1
	if shadowed != 1:
		fail("station needs exactly one shadowed DirectionalLight3D, has %d" % shadowed)
	for i in range(3):
		await physics_frame
	var space := world.get_world_3d().direct_space_state

	# Floors under every room centre, corridor centre, socket and item spawn.
	var floor_points := {}
	for room_id in StationLayout.ROOMS:
		floor_points["room " + room_id] = StationLayout.ROOMS[room_id].center
	for corridor_id in StationLayout.CORRIDORS:
		floor_points["corridor " + corridor_id] = StationLayout.CORRIDORS[corridor_id].center
	for socket_id in StationLayout.SOCKETS:
		floor_points["socket " + socket_id] = StationLayout.SOCKETS[socket_id].pos
	for item_id in StationLayout.ITEMS:
		if StationLayout.ITEMS[item_id].has("pos"):
			floor_points["item " + item_id] = StationLayout.ITEMS[item_id].pos
	for label in floor_points:
		var p: Vector2 = floor_points[label]
		var hit := _ray(space, Vector3(p.x, 2.0, p.y), Vector3(p.x, -2.0, p.y))
		if hit.is_empty() or not (hit.collider is StaticBody3D) or absf((hit.position as Vector3).y) > 0.05:
			fail("no floor at y=0 under %s %s (hit %s)" % [label, p, hit.get("position", "nothing")])

	# Solid walls: a chest-height ray out through each room side away from doorways.
	for room_id in StationLayout.ROOMS:
		var r := StationLayout.room_rect(room_id)
		var probes := [
			[Vector2(r.position.x + 1.0, r.position.y + 0.8), Vector2(r.position.x + 1.0, r.position.y - 1.5)],
			[Vector2(r.end.x - 1.0, r.end.y - 0.8), Vector2(r.end.x - 1.0, r.end.y + 1.5)],
			[Vector2(r.position.x + 0.8, r.end.y - 1.0), Vector2(r.position.x - 1.5, r.end.y - 1.0)],
			[Vector2(r.end.x - 0.8, r.position.y + 1.0), Vector2(r.end.x + 1.5, r.position.y + 1.0)],
		]
		for probe in probes:
			var a: Vector2 = probe[0]
			var b: Vector2 = probe[1]
			if _ray(space, Vector3(a.x, 1.2, a.y), Vector3(b.x, 1.2, b.y)).is_empty():
				fail("wall missing for %s between %s and %s" % [room_id, a, b])

	# Open doorways: along each corridor axis into 1 m inside both rooms.
	for corridor_id in StationLayout.CORRIDORS:
		var spec: Dictionary = StationLayout.CORRIDORS[corridor_id]
		var c: Vector2 = spec.center
		for room_key in ["a", "b"]:
			var rc: Vector2 = StationLayout.ROOMS[spec[room_key]].center
			var ca: Vector2 = StationLayout.ROOMS[spec.a].center
			var cb: Vector2 = StationLayout.ROOMS[spec.b].center
			var along_x := absf(ca.x - cb.x) > absf(ca.y - cb.y)
			var axis := Vector2(signf(rc.x - c.x), 0) if along_x else Vector2(0, signf(rc.y - c.y))
			var half: float = (spec.size.x if axis.x != 0 else spec.size.y) * 0.5
			var target := c + axis * (half + 1.0)
			var hit := _ray(space, Vector3(c.x, 1.2, c.y), Vector3(target.x, 1.2, target.y))
			if not hit.is_empty():
				fail("doorway blocked in %s towards %s at %s" % [corridor_id, spec[room_key], hit.position])

	# Sockets exactly as world.gd places them; exercise every state.
	var sockets := {}
	for socket_id in StationLayout.SOCKETS:
		var sspec: Dictionary = StationLayout.SOCKETS[socket_id]
		var node: Node3D = Props.make_socket(sspec.kind)
		node.position = StationLayout.to_world(sspec.pos)
		node.rotation.y = sspec.facing
		world.add_child(node)
		sockets[socket_id] = node
		if not node.has_method("set_state") or not node.has_method("get_seat_transform"):
			fail("socket %s lacks set_state/get_seat_transform" % socket_id)
			continue
		for filled in [false, true]:
			for locked in [false, true]:
				for active in [false, true]:
					node.call("set_state", filled, locked, active)
		var seat: Transform3D = node.call("get_seat_transform")
		if seat.origin.y < 0.3 or seat.origin.y > 1.5:
			fail("socket %s seat height %s is odd" % [socket_id, seat.origin.y])
		node.call("set_state", false, sspec.kind == "vault", false)
	var core: Node3D = Props.make_item("core")
	(sockets["vault"] as Node3D).add_child(core)
	core.transform = (sockets["vault"] as Node3D).call("get_seat_transform")
	for i in range(3):
		await physics_frame

	# Reachability: flood fill a capsule-sized player from the spawn.
	var reach := _flood(space)
	var targets := {}
	for socket_id in StationLayout.SOCKETS:
		targets["socket " + socket_id] = StationLayout.SOCKETS[socket_id].pos
	for item_id in StationLayout.ITEMS:
		if StationLayout.ITEMS[item_id].has("pos"):
			targets["item " + item_id] = StationLayout.ITEMS[item_id].pos
	for room_id in StationLayout.ROOMS:
		targets["room " + room_id] = StationLayout.ROOMS[room_id].center
	for label in targets:
		var p: Vector2 = targets[label]
		var ok := false
		for cell in reach:
			if (cell as Vector2).distance_to(p) <= 1.5:
				ok = true
				break
		if not ok:
			fail("%s at %s is not reachable within 1.5 m" % [label, p])
	for cell in reach:
		var v: Vector2 = cell
		if not StationLayout.is_walkable(Vector3(v.x, 0, v.y)):
			fail("player can reach outside the station at %s" % v)
			break

	# Power states, in every order, including mid-tween switches.
	var fx := station as ArtStationFX
	for state in ["restored", "blackout", "emergency", "blackout", "restored"]:
		StationBuilder.set_power_state(station, state)
		for i in range(4):
			await process_frame
	StationBuilder.set_power_state(station, "emergency")
	await create_timer(1.6).timeout
	var expectations := {"restored": [true, 0.6], "blackout": [false, 0.1], "emergency": [true, 0.3]}
	for state in ["restored", "blackout", "emergency"]:
		StationBuilder.set_power_state(station, state)
		await create_timer(1.8).timeout
		var lit := 0
		for light in fx.room_lights:
			if light.visible and light.light_energy > 0.5:
				lit += 1
		var want_lit: bool = expectations[state][0]
		if (lit > 0) != want_lit:
			fail("power %s: %d room lights lit" % [state, lit])
		var ambient := fx.env.ambient_light_energy
		if state == "blackout" and ambient > float(expectations[state][1]):
			fail("blackout ambient too bright: %s" % ambient)
		if state != "blackout" and ambient < float(expectations[state][1]):
			fail("%s ambient too dark: %s" % [state, ambient])
		print("power %s ok: lights lit %d, ambient %.2f" % [state, lit, ambient])

	# Airlock cycle.
	for state in ["warning", "venting", "idle", "venting"]:
		StationBuilder.set_airlock_state(station, state)
		for i in range(5):
			await process_frame
	await create_timer(2.4).timeout
	if fx.airlock_state != "idle":
		fail("airlock must return to idle after venting, is " + fx.airlock_state)
	if fx.airlock_doors.size() != 2:
		fail("airlock needs two outer door leaves")

	# Items, crew, flashlight.
	for kind in ["cell", "core", "gun"]:
		var item: Node3D = Props.make_item(kind)
		world.add_child(item)
		var box := _aabb(item)
		var longest := maxf(box.size.y, maxf(box.size.x, box.size.z))
		if absf(box.position.y) > 0.03 or longest < 0.35 or longest > 0.85:
			fail("item %s bounds %s: origin must be bottom centre, ~0.5-0.6 m" % [kind, box])
		if kind == "gun":
			if not item.has_method("set_ammo"):
				fail("gun needs set_ammo")
			else:
				for n in [0, 1, 2, 3, 5, -1]:
					item.call("set_ammo", n)
		item.queue_free()
	var crew: Node3D = Props.make_crew_visual(Color(0.9, 0.3, 0.3))
	world.add_child(crew)
	for limb in ["LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
		if crew.find_child(limb, true, false) == null:
			fail("crew visual lost limb pivot " + limb)
	var hat := crew.find_child("hat_crown", true, false) as Node3D
	if hat != null and hat.visible:
		fail("crew hat must be hidden")
	if crew.find_child("Helmet", true, false) == null:
		fail("crew visual needs a helmet")
	var torso := crew.find_child("torso", true, false) as MeshInstance3D
	if torso != null and torso.get_surface_override_material(0) == null:
		fail("suit material must be a per-crew override")
	var flashlight := Props.make_flashlight()
	if not (flashlight is SpotLight3D) or flashlight.shadow_enabled or absf(flashlight.spot_range - 14.0) > 2.0:
		fail("flashlight must be an unshadowed ~14 m SpotLight3D")
	flashlight.free()

	# Budget report.
	var surfaces := 0
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m != null and (mi as MeshInstance3D).visible:
			surfaces += m.get_surface_count()
	var labels := world.find_children("*", "Label3D", true, false).size()
	var omnis := station.find_children("*", "OmniLight3D", true, false).size()
	var decals := station.find_children("*", "Decal", true, false).size()
	var probes_n := station.find_children("*", "ReflectionProbe", true, false).size()
	var shapes := station.find_children("*", "CollisionShape3D", true, false).size()
	print("budget: %d mesh surfaces + %d labels (~%d draw calls before culling), %d station omni lights, %d decals, %d reflection probes, %d collision shapes, %d reachable cells" % [surfaces, labels, surfaces + labels, omnis, decals, probes_n, shapes, reach.size()])
	if surfaces + labels > 400:
		fail("draw call estimate over budget")
	if omnis > 12:
		fail("too many omni lights")
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PASS: art smoke")
		quit(0)
	else:
		print("FAIL: art smoke (%d failures)" % failures.size())
		quit(1)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	return space.intersect_ray(query)


func _flood(space: PhysicsDirectSpaceState3D) -> Array:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var free_cache := {}
	var start := Vector2i(0, 0)
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var reached: Array = []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		var p := Vector2(cell) * GRID
		if p.x < -14 or p.x > 76 or p.y < -32 or p.y > 32:
			continue
		query.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 1.0, p.y))
		if not space.intersect_shape(query, 1).is_empty():
			continue
		# Needs floor beneath.
		if _ray(space, Vector3(p.x, 0.5, p.y), Vector3(p.x, -1.0, p.y)).is_empty():
			reached.append(p)
			continue
		reached.append(p)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return reached


func _aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		box = node.global_transform.affine_inverse() * box
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result
