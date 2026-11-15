extends SceneTree
## Headless art/collision smoke test for StationBuilder + Props.
##   godot --headless --path . --script res://tests/art_smoke.gd
##
## Checks: floors under every room, corridor, socket, approach point and item
## spawn; solid walls; doorways clear across their width at chest height;
## approach points and item spawns clear of colliders within 0.4 m; raised decks
## and ramps walkable (floor raycasts along their paths, capsule headroom); a
## height-aware capsule flood fill from the spawn reaches every target and never
## leaves the station; every registered prop has a collider hugging its visual
## bounds (within a few cm) and every free-standing prop mesh overlaps a
## collider; power states, airlock, items, crew; draw-call budget.

const CAPSULE_RADIUS := 0.38
const CAPSULE_HEIGHT := 1.8
const GRID := 0.5
const MAX_STEP := 0.13  # floor height change allowed between 0.5 m flood cells (ramps rise 0.1)
const PROP_TOLERANCE := 0.07  # collider edge vs visual edge

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

	# Floors under every room centre, corridor centre, socket, approach point
	# and item spawn: flat deck floor at y = 0.
	var floor_points := {}
	for room_id in StationLayout.ROOMS:
		floor_points["room " + room_id] = StationLayout.ROOMS[room_id].center
	for corridor_id in StationLayout.CORRIDORS:
		floor_points["corridor " + corridor_id] = StationLayout.CORRIDORS[corridor_id].center
	for socket_id in StationLayout.SOCKETS:
		floor_points["socket " + socket_id] = StationLayout.SOCKETS[socket_id].pos
		floor_points["approach " + socket_id] = _approach(socket_id)
	for item_id in StationLayout.ITEMS:
		if StationLayout.ITEMS[item_id].has("pos"):
			floor_points["item " + item_id] = StationLayout.ITEMS[item_id].pos
	for label in floor_points:
		var p: Vector2 = floor_points[label]
		var hit := _ray(space, Vector3(p.x, 0.5, p.y), Vector3(p.x, -2.0, p.y))
		if label.begins_with("socket"):
			hit = _ray(space, Vector3(p.x, 0.05, p.y), Vector3(p.x, -2.0, p.y))
		if hit.is_empty() or not (hit.collider is StaticBody3D) or absf((hit.position as Vector3).y) > 0.05:
			fail("no floor at y=0 under %s %s (hit %s)" % [label, p, hit.get("position", "nothing")])
		if StationLayout.floor_height(Vector3(p.x, 0, p.y)) != 0.0:
			fail("%s at %s sits on a platform or ramp" % [label, p])

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

	# Doorways: clear at chest (1.2 m) and knee (0.5 m) height across the
	# middle 2 m of the 3 m opening, from the corridor centre to 1.5 m inside
	# both rooms.
	for corridor_id in StationLayout.CORRIDORS:
		var spec: Dictionary = StationLayout.CORRIDORS[corridor_id]
		var c: Vector2 = spec.center
		var ca: Vector2 = StationLayout.ROOMS[spec.a].center
		var cb: Vector2 = StationLayout.ROOMS[spec.b].center
		var along_x := absf(ca.x - cb.x) > absf(ca.y - cb.y)
		for room_key in ["a", "b"]:
			var rc: Vector2 = StationLayout.ROOMS[spec[room_key]].center
			var axis := Vector2(signf(rc.x - c.x), 0) if along_x else Vector2(0, signf(rc.y - c.y))
			var side := Vector2(axis.y, axis.x)
			var half: float = (spec.size.x if axis.x != 0 else spec.size.y) * 0.5
			for lateral in [-1.0, 0.0, 1.0]:
				for y in [0.5, 1.2]:
					var from: Vector2 = c + side * float(lateral)
					var target: Vector2 = from + axis * (half + 1.5)
					var hit := _ray(space, Vector3(from.x, y, from.y), Vector3(target.x, y, target.y))
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

	# Approach points (where bots and players stand to use a socket) and item
	# spawns: nothing solid within 0.4 m between knee and head height.
	var clear_points := {}
	for socket_id in StationLayout.SOCKETS:
		clear_points["approach " + socket_id] = _approach(socket_id)
	for item_id in StationLayout.ITEMS:
		if StationLayout.ITEMS[item_id].has("pos"):
			clear_points["item " + item_id] = StationLayout.ITEMS[item_id].pos
	var probe_shape := CylinderShape3D.new()
	probe_shape.radius = 0.4
	probe_shape.height = 1.4
	var probe_q := PhysicsShapeQueryParameters3D.new()
	probe_q.shape = probe_shape
	probe_q.collision_mask = 1
	for label in clear_points:
		var p: Vector2 = clear_points[label]
		probe_q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 1.0, p.y))
		var hits := space.intersect_shape(probe_q, 4)
		if not hits.is_empty():
			fail("%s at %s has a collider within 0.4 m (%s)" % [label, p, (hits[0].collider as Node).get_path()])

	# Raised decks and ramps: floor heights match the layout along every ramp
	# and across the deck, slopes stay gentle and a capsule fits on top.
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var cap_q := PhysicsShapeQueryParameters3D.new()
	cap_q.shape = capsule
	cap_q.collision_mask = 1
	var platform_cells := 0
	for pid in StationLayout.PLATFORMS:
		var pspec: Dictionary = StationLayout.PLATFORMS[pid]
		var deck: Rect2 = pspec.rect
		var h: float = pspec.height
		for i in range((pspec.ramps as Array).size()):
			var rr: Array = StationLayout.ramp_rect(pid, i)
			var rect: Rect2 = rr[0]
			var up: Vector2 = rr[1]
			var length: float = pspec.ramps[i].length
			var foot := rect.get_center() - up * (length * 0.5)
			var prev_y := 0.0
			var t := -0.6
			while t <= length + 0.9:
				var q := foot + up * t
				var fh := _floor_at(space, q)
				var want := StationLayout.floor_height(Vector3(q.x, 0, q.y))
				if absf(fh - want) > 0.05:
					fail("%s ramp %d: floor %.3f at %s, layout says %.3f" % [pid, i, fh, q, want])
				if absf(fh - prev_y) > 0.2 * 0.25 + 0.02:
					fail("%s ramp %d: step of %.3f m at %s (too steep)" % [pid, i, fh - prev_y, q])
				cap_q.transform = Transform3D(Basis.IDENTITY, Vector3(q.x, fh + CAPSULE_HEIGHT * 0.5 + 0.06, q.y))
				if not space.intersect_shape(cap_q, 1).is_empty():
					fail("%s ramp %d: no headroom for a player at %s" % [pid, i, q])
				prev_y = fh
				t += 0.2
		for gx in range(1, int(deck.size.x / 0.5)):
			for gz in range(1, int(deck.size.y / 0.5)):
				var q := deck.position + Vector2(gx * 0.5, gz * 0.5)
				var fh := _floor_at(space, q)
				if fh < h + 0.5 and absf(fh - h) > 0.03:
					fail("%s: deck floor %.3f at %s, want %.2f" % [pid, fh, q, h])
				platform_cells += 1

	# Reachability: height-aware flood fill of a capsule-sized player from the spawn.
	var reach := _flood(space)
	var targets := {}
	for socket_id in StationLayout.SOCKETS:
		targets["socket " + socket_id] = StationLayout.SOCKETS[socket_id].pos
		targets["approach " + socket_id] = _approach(socket_id)
	for item_id in StationLayout.ITEMS:
		if StationLayout.ITEMS[item_id].has("pos"):
			targets["item " + item_id] = StationLayout.ITEMS[item_id].pos
	for room_id in StationLayout.ROOMS:
		targets["room " + room_id] = StationLayout.ROOMS[room_id].center
	for pid in StationLayout.PLATFORMS:
		targets["deck " + pid] = (StationLayout.PLATFORMS[pid].rect as Rect2).get_center()
	for label in targets:
		var p: Vector2 = targets[label]
		var tolerance := 0.5 if label.begins_with("approach") or label.begins_with("item") or label.begins_with("deck") else 1.5
		var ok := false
		for cell in reach:
			if (cell as Vector2).distance_to(p) <= tolerance:
				ok = true
				break
		if not ok:
			fail("%s at %s is not reachable within %.1f m" % [label, p, tolerance])
	for cell in reach:
		var v: Vector2 = cell
		if not StationLayout.is_walkable(Vector3(v.x, 0, v.y)):
			fail("player can reach outside the station at %s" % v)
			break

	# Props: every registered prop (visual bounds) has a collider that hugs it.
	var fx := station as ArtStationFX
	var checked := 0
	for prop in fx.props:
		var size: Vector3 = prop.size
		var center: Vector3 = prop.center
		var bottom := center.y - size.y * 0.5
		if size.y <= 0.3 or bottom > 0.3:
			continue
		checked += 1
		_check_prop(space, prop)
	# And every other free-standing mesh (sockets, spinners) on the floor
	# inside the walkable area overlaps some collider.
	var loose := 0
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name in ["Mesh", "ShadowProxy"] and (m.get_parent().name.begins_with("Room_") or m.get_parent().name.begins_with("Corridor_") or m.get_parent().name == "Exterior"):
			continue
		if m.get_parent() == station or not m.visible:
			continue
		var box := m.global_transform * m.get_aabb()
		if box.size.y <= 0.3 or box.position.y > 0.3 or box.size.x > 20.0:
			continue
		var c := box.get_center()
		if not StationLayout.is_walkable(Vector3(c.x, 0, c.z)):
			continue
		var b := BoxShape3D.new()
		b.size = Vector3(box.size.x * 0.6, minf(box.size.y, 1.6) * 0.6, box.size.z * 0.6)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = b
		q.collision_mask = 1
		q.transform = Transform3D(Basis.IDENTITY, Vector3(c.x, box.position.y + minf(box.size.y, 1.6) * 0.5, c.z))
		loose += 1
		if space.intersect_shape(q, 1).is_empty():
			fail("mesh %s (%s) has no collider over its footprint" % [m.get_path(), box])
	print("props: %d registered props with colliders checked, %d free-standing meshes checked" % [checked, loose])

	# Power states, in every order, including mid-tween switches.
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
	var instances := 0
	for mi in station.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m != null and (mi as MeshInstance3D).visible:
			surfaces += m.get_surface_count()
			instances += 1
	var labels := station.find_children("*", "Label3D", true, false).size()
	var omnis := station.find_children("*", "OmniLight3D", true, false).size()
	var decals := station.find_children("*", "Decal", true, false).size()
	var probes_n := station.find_children("*", "ReflectionProbe", true, false).size()
	var shapes := station.find_children("*", "CollisionShape3D", true, false).size()
	print("budget: %d station mesh instances (%d surfaces) + %d labels, %d station omni lights, %d decals, %d reflection probes, %d collision shapes, %d reachable cells, %d deck cells" % [instances, surfaces, labels, omnis, decals, probes_n, shapes, reach.size(), platform_cells])
	if surfaces + labels > 400:
		fail("draw call estimate over budget")
	if omnis > 16:
		fail("too many omni lights")
	for node in station.get_children():
		if node.name.begins_with("Room_") and node.find_children("*", "Decal", true, false).size() > 6:
			fail("%s has more than 6 decals (Mobile: 8 per mesh)" % node.name)
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PASS: art smoke")
		quit(0)
	else:
		print("FAIL: art smoke (%d failures)" % failures.size())
		quit(1)


func _approach(socket_id: String) -> Vector2:
	var spec: Dictionary = StationLayout.SOCKETS[socket_id]
	return spec.pos + Vector2(sin(spec.facing), cos(spec.facing)) * 1.2


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	return space.intersect_ray(query)


## Walkable floor height under a flat point (a hit above 0.6 m is a prop: 9.0).
func _floor_at(space: PhysicsDirectSpaceState3D, p: Vector2) -> float:
	var hit := _ray(space, Vector3(p.x, 1.5, p.y), Vector3(p.x, -1.0, p.y))
	if hit.is_empty():
		return -9.0
	var y: float = (hit.position as Vector3).y
	return y if y <= 0.6 else 9.0


## Every registered prop: a collider inside its footprint, and colliders whose
## faces sit within PROP_TOLERANCE of the visual faces (rays from 0.35 m out).
func _check_prop(space: PhysicsDirectSpaceState3D, prop: Dictionary) -> void:
	var size: Vector3 = prop.size
	var center: Vector3 = prop.center
	var basis := Basis(Vector3.UP, float(prop.yaw))
	var bottom := center.y - size.y * 0.5
	var probe_h := minf(size.y, 1.6)
	var b := BoxShape3D.new()
	b.size = Vector3(maxf(size.x * 0.6, 0.02), probe_h * 0.6, maxf(size.z * 0.6, 0.02))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = b
	q.collision_mask = 1
	q.transform = Transform3D(basis, Vector3(center.x, bottom + probe_h * 0.5, center.z))
	if space.intersect_shape(q, 1).is_empty():
		fail("prop %s at %s has no collider" % [prop.name, center])
		return
	var y := bottom + clampf(size.y * 0.5, 0.15, 1.2)
	var measured := 0
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var half: float = absf(dir.x) * size.x * 0.5 + absf(dir.z) * size.z * 0.5
		var out: Vector3 = basis * dir
		var face := Vector3(center.x, y, center.z) + out * half
		var start := face + out * 0.35
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = start
		pq.collision_mask = 1
		if not space.intersect_point(pq, 1).is_empty():
			continue  # against a wall or another prop: this side can't be probed
		var hit := _ray(space, start, Vector3(center.x, y, center.z))
		if hit.is_empty():
			fail("prop %s: no collider face towards %s" % [prop.name, out])
			continue
		var d := start.distance_to(hit.position)
		if d > 0.35 + PROP_TOLERANCE:
			fail("prop %s: collider %.2f m inside the visual face towards %s (a player clips in)" % [prop.name, d - 0.35, out])
		elif d >= 0.35 - PROP_TOLERANCE:
			measured += 1
	if measured == 0:
		fail("prop %s at %s: no side where the collider matches the visual face" % [prop.name, center])


func _flood(space: PhysicsDirectSpaceState3D) -> Array:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var start := Vector2i(0, 0)
	var queue: Array[Vector2i] = [start]
	var heights := {start: 0.0}
	var reached: Array = []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		var p := Vector2(cell) * GRID
		var fh: float = heights[cell]
		query.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, fh + CAPSULE_HEIGHT * 0.5 + 0.06, p.y))
		if not space.intersect_shape(query, 1).is_empty():
			continue
		reached.append(p)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if heights.has(n):
				continue
			var np := Vector2(n) * GRID
			if np.x < -16 or np.x > 76 or np.y < -32 or np.y > 32:
				continue
			var nh := _floor_at(space, np)
			if nh < -1.0 or absf(nh - fh) > MAX_STEP:
				continue
			heights[n] = nh
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
