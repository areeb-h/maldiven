extends SceneTree
## Headless physics checks (run with --fixed-fps 60): items never tunnel through
## walls or floors, props settle and sleep clear of approach points and
## doorways, loose item poses reach the rules, the airlock vents bodies into
## space, ragdolls stay finite and settle, proxies push props, and the
## host -> client stream reproduces the host's results.

const DT := 1.0 / 60.0

var failures := 0
var checks := 0
var station: Node3D
var rules: StationRules
var phys: StationPhysics
var stub: Node3D
var walking := {}  # peer id -> velocity reported with its pose


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)


func _run() -> void:
	stub = Node3D.new()
	stub.name = "World"
	root.add_child(stub)
	station = StationBuilder.build(stub)
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		var node: Node3D = Props.make_socket(spec.kind)
		node.position = StationLayout.to_world(spec.pos)
		node.rotation.y = spec.facing
		stub.add_child(node)
	rules = StationRules.new()
	rules.physics_driven = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	rules.setup({1: {"name": "A"}, 2: {"name": "B"}, 3: {"name": "C"}}, rng)
	rules.tick(StationRules.BRIEFING_SECONDS + 0.1)
	var visuals := {}
	for item_id in StationLayout.ITEMS:
		visuals[item_id] = Props.make_item(StationLayout.ITEMS[item_id].kind)
	phys = StationPhysics.new()
	phys.setup(stub, rules, true, visuals)
	stub.add_child(phys)
	# Park the players far from everything so their proxies stay out of the way.
	for id in rules.players:
		rules.players[id].pos = Vector3(-30.0 - float(id) * 3.0, 0, 40)
	await _steps(3)
	await test_codec()
	await test_props_settle()
	await test_no_tunnelling()
	await test_item_sync()
	await test_proxy_pushes()
	await test_keep_clear()
	await test_airlock()
	await test_ragdoll()
	await test_replication()
	if failures == 0:
		print("PASS: physics smoke (%d checks)" % checks)
	quit(1 if failures else 0)


## One host tick per physics frame: rules, then physics (as StationWorld does).
func _steps(count: int) -> void:
	for i in range(count):
		for id in rules.players:
			phys.on_pose(id, rules.players[id].pos, walking.get(id, Vector3.ZERO))
		rules.tick(DT)
		for event in rules.drain_events():
			phys.on_event(event)
		await physics_frame


func _body(item_id: String) -> NetBody:
	return phys.item_body(item_id)


func test_codec() -> void:
	var worst := 0.0
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in range(200):
		var q := Quaternion(Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized(), r.randf_range(-PI, PI))
		var back := NetCodec.unpack_quat(NetCodec.pack_quat(q))
		worst = maxf(worst, q.angle_to(back))
	check(worst < 0.004, "quaternion packing within 0.25 deg (worst %.5f rad)" % worst)
	var packet := NetCodec.begin(12.5, 2)
	NetCodec.write_body(packet, 0, 7, NetCodec.FLAG_ASLEEP, 37, Vector3(-14.21, 0.333, 25.5), Quaternion.IDENTITY)
	NetCodec.write_body(packet, 1, 40, NetCodec.FLAG_TELEPORT, 2, Vector3(100, -3, -60), Quaternion(Vector3.UP, 1.0))
	var read := NetCodec.read(packet)
	check(packet.size() == NetCodec.HEADER_BYTES + 2 * NetCodec.BODY_BYTES and absf(read.time - 12.5) < 0.001, "packet header")
	var a: Array = read.bodies[0]
	check(a[0] == 7 and a[1] == NetCodec.FLAG_ASLEEP and a[2] == 37 % 32 and (a[3] as Vector3).distance_to(Vector3(-14.21, 0.333, 25.5)) < 0.005, "body round trip")
	check((read.bodies[1][4] as Quaternion).angle_to(Quaternion(Vector3.UP, 1.0)) < 0.004, "rotation round trip")


func test_props_settle() -> void:
	await _steps(240)
	var awake := 0
	var drift := 0.0
	for body in phys.props:
		if not body.visible:
			check(false, "%s found no clear spot" % body.name)
			continue
		if not body.sleeping:
			awake += 1
		drift = maxf(drift, body.global_position.distance_to(body.home.origin))
		check(not phys._overlaps_world(body, body.global_transform), "%s rests clear of static geometry" % body.name)
		var hit := PropLayout.intrusion(Vector2(body.global_position.x, body.global_position.z), body.bound_radius * 0.8)
		check(hit.is_empty() or float(hit.depth) < 0.02, "%s starts clear of approach points, spawns and doorways (%s)" % [body.name, hit])
	check(awake == 0, "all props asleep after 4 s (%d awake)" % awake)
	check(drift < 0.12, "props settle where they were placed (max drift %.3f m)" % drift)
	check(phys.props.size() >= 20 and phys.props.size() <= 30, "20-30 props (%d)" % phys.props.size())
	check(phys.awake_count() == 0, "nothing awake at rest")


## Throws at full speed (and much faster) into walls, corners, furniture and
## the floor: the item's centre must never cross a static surface.
func test_no_tunnelling() -> void:
	var space := stub.get_world_3d().direct_space_state
	var cases := []
	for room_id in ["commons", "medical", "engineering", "cargo", "command", "reactor"]:
		var c: Vector2 = StationLayout.ROOMS[room_id].center
		for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0.7, 0, 0.7)]:
			cases.append([Vector3(c.x, 1.1, c.y) + dir * 2.0, dir * 8.4 + Vector3(0, 3.4, 0)])
			cases.append([Vector3(c.x, 1.1, c.y) + dir * 1.0, dir * 24.0 + Vector3(0, 1.0, 0)])
		cases.append([Vector3(c.x + 1.0, 2.6, c.y), Vector3(0, -26, 0)])  # straight into the floor
	var tunnels := 0
	var outside := 0
	var item_ids := ["cell_1", "core", "gun"]
	for index in range(cases.size()):
		var item_id: String = item_ids[index % item_ids.size()]
		var body := _body(item_id)
		var at: Vector3 = cases[index][0]
		rules._make_loose(item_id, at, Quaternion.IDENTITY, cases[index][1])
		await _steps(1)
		var prev := body.global_transform * Vector3(0, 0.2, 0)
		for frame in range(150):
			await _steps(1)
			var now := body.global_transform * Vector3(0, 0.2, 0)
			if prev.distance_to(now) > 0.0005:
				var query := PhysicsRayQueryParameters3D.create(prev, now, PhysicsLayers.WORLD)
				query.hit_back_faces = false
				var hit := space.intersect_ray(query)
				if not hit.is_empty():
					tunnels += 1
					print("  tunnel: %s case %d frame %d %s -> %s through %s" % [item_id, index, frame, prev, now, hit.collider])
					break
			prev = now
			if body.sleeping and frame > 20:
				break
		var rest := body.global_position
		if rest.y < -0.3 or not StationLayout.is_walkable(rest + Vector3(0, 0, 0)):
			outside += 1
			print("  outside: %s case %d at %s" % [item_id, index, rest])
	check(tunnels == 0, "no item centre crossed a wall or floor in %d throws (%d did)" % [cases.size(), tunnels])
	check(outside == 0, "every thrown item ended inside the station (%d didn't)" % outside)
	for item_id in item_ids:
		rules.respawn_item(item_id)
	await _steps(30)


func test_item_sync() -> void:
	var c := StationLayout.ROOMS.medical.center
	rules._make_loose("cell_2", Vector3(c.x, 1.0, c.y), Quaternion.IDENTITY, Vector3(3, 2, 1))
	await _steps(4)
	var body := _body("cell_2")
	check(rules.items.cell_2.pos.distance_to(body.global_position) < 0.001, "loose item position written into the rules every tick")
	check(rules.items.cell_2.moving, "moving while it flies")
	var settled := false
	for i in range(360):
		await _steps(1)
		if body.sleeping:
			settled = true
			break
	await _steps(1)
	check(settled and not rules.items.cell_2.moving, "loose item comes to rest and sleeps")
	check(rules.items.cell_2.pos.distance_to(body.global_position) < 0.001 and rules.items.cell_2.rot.is_equal_approx(body.global_basis.get_rotation_quaternion()), "rest pose in the rules")
	rules.respawn_item("cell_2")
	await _steps(2)
	check(body.global_position.distance_to(StationLayout.to_world(StationLayout.ITEMS.cell_2.pos)) < 0.05, "respawn teleports the body")
	# Fell out of the world: back to its dock.
	rules._make_loose("cell_2", Vector3(0, -8, 80), Quaternion.IDENTITY, Vector3.ZERO)
	await _steps(4)
	check(StationLayout.room_at(rules.items.cell_2.pos) == "medical", "an item out of the world respawns")
	# A thrown item hits a standing player (proxy) and stuns them.
	var victim := 2
	rules.players[victim].pos = Vector3(c.x + 3.0, 0, c.y)
	rules.players[1].pos = Vector3(c.x - 2.0, 0, c.y)
	rules.players[1].yaw = PI / 2.0
	rules.players[1].holding = "cell_2"
	rules.items.cell_2.holder = 1
	await _steps(30)
	rules.players[1].shove_ready = 0.0
	rules.request_shove(1)
	var hit := false
	for i in range(60):
		await _steps(1)
		if rules.players[victim].stunned_until > rules.elapsed:
			hit = true
			break
	check(hit, "a thrown cell hitting a standing player's capsule stuns them")
	await _steps(120)
	check(rules.items.cell_2.flight.is_empty(), "the thrown cell cooled down")
	for id in rules.players:
		rules.players[id].pos = Vector3(-30.0 - float(id) * 3.0, 0, 40)
		rules.players[id].stunned_until = 0.0
	rules.respawn_item("cell_2")
	await _steps(30)


func test_proxy_pushes() -> void:
	var crate: NetBody = null
	for body in phys.props:
		if body.kind == "crate" and StationLayout.room_at(body.global_position) == "docking":
			crate = body
	check(crate != null, "a crate in Docking")
	if crate == null:
		return
	var start := crate.global_position
	var walk_from := start + Vector3(-1.6, 0, 0)
	walk_from.y = 0.0
	rules.players[1].pos = walk_from
	phys.on_pose(1, walk_from, Vector3.ZERO)
	await _steps(10)
	walking[1] = Vector3(3.0, 0, 0)
	for i in range(60):
		rules.players[1].pos = walk_from + Vector3(3.0 * DT * i, 0, 0)
		await _steps(1)
	walking.erase(1)
	var moved := crate.global_position - start
	check(moved.x > 0.5, "a walking player's proxy pushes a crate (moved %.2f m)" % moved.x)
	check(crate.global_position.y > -0.05 and crate.global_position.y < 0.3, "the pushed crate stays on the floor")
	rules.players[1].pos = Vector3(-33, 0, 40)
	crate.place(crate.home)
	await _steps(120)


## Shove every prop around, then let the keep-clear nudge run: nothing may rest
## on a socket approach point or inside a doorway.
func test_keep_clear() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	for body in phys.props:
		var dir := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized()
		body.sleeping = false
		body.apply_central_impulse(dir * body.mass * 2.5)
	# Also drop one right in a doorway and one on the vault approach.
	var door_crate := phys.props[0]
	door_crate.place(Transform3D(Basis.IDENTITY, Vector3(0.2, 0.05, -7.0)))
	var vault_prop := phys.props[1]
	var approach := PropLayout.approach_point("vault")
	vault_prop.place(Transform3D(Basis.IDENTITY, Vector3(approach.x, 0.05, approach.y)))
	await _steps(600)
	var bad := []
	for body in phys.props:
		var hit := PropLayout.intrusion(Vector2(body.global_position.x, body.global_position.z), body.bound_radius * 0.8, true)
		if not hit.is_empty() and float(hit.depth) > 0.06:
			bad.append("%s %.2f" % [body.name, hit.depth])
	check(bad.is_empty(), "no prop rests on an approach point or in a doorway: %s" % [bad])
	for body in phys.props:
		body.place(body.home)
	await _steps(200)


func test_airlock() -> void:
	var chamber := StationLayout.room_rect("airlock")
	var inside := []
	for body in phys.props:
		if chamber.has_point(Vector2(body.global_position.x, body.global_position.z)):
			inside.append(body)
	check(inside.size() >= 1, "props start in the airlock")
	var c := chamber.get_center()
	rules._make_loose("cell_1", Vector3(c.x + 1.5, 0.4, c.y + 0.5), Quaternion.IDENTITY, Vector3.ZERO)
	await _steps(60)
	var before: Vector3 = _body("cell_1").global_position
	# Cycle from the console: warning pull, then vent.
	var operator := 3
	var console := PropLayout.approach_point("airlock_console")
	rules.players[operator].pos = Vector3(console.x, 0, console.y)
	check(rules.request_interact(operator), "cycle the airlock")
	var pulled := false
	for i in range(int(StationRules.AIRLOCK_WARNING * 60.0) - 2):
		await _steps(1)
		if _body("cell_1").global_position.x < before.x - 0.2:
			pulled = true
	check(pulled, "decompression pulls a loose cell towards the outer door")
	check(phys.airlock_push(Vector3(c.x, 0, c.y)).x < -2.0, "players in the chamber feel a strong pull near the end")
	var corridor := StationLayout.corridor_rect("commons-airlock").get_center()
	var push := phys.airlock_push(Vector3(corridor.x, 0, corridor.y)).length()
	check(push > 1.0 and push < StationCrewWalk.WALK, "the corridor pull can be walked against (%.2f m/s)" % push)
	await _steps(70)
	var out := 0
	for body in inside + [_body("cell_1")]:
		if body.global_position.x < chamber.position.x - 2.0:
			out += 1
	check(out == inside.size() + 1, "vented bodies leave the chamber (%d of %d)" % [out, inside.size() + 1])
	await _steps(int(StationRules.VENT_DRIFT_SECONDS * 60.0))
	check(StationLayout.room_at(rules.items.cell_1.pos) == "engineering" and not _body("cell_1").is_ejected(), "the vented cell returns to its dock")
	await _steps(int(StationPhysics.PROP_DRIFT * 60.0))
	for body in inside:
		check(not body.is_ejected() and body.global_position.distance_to(body.home.origin) < 0.3, "%s respawns at home after drifting" % body.name)
	await _steps(int(StationRules.AIRLOCK_COOLDOWN * 60.0) + 10)


func test_ragdoll() -> void:
	var model := CrewModel.build(Color("4da3ff"), 1, 3)
	stub.add_child(model)
	model.global_position = Vector3(2, 0, 2)  # Commons, open floor
	for i in range(20):
		model.set_motion(3.0, true, false, false, DT)
	var rd := CrewRagdoll.spawn(model, stub, Vector3(0, 0, 1.5))
	check(rd != null, "ragdoll spawns")
	if rd == null:
		return
	rd.impulse(CrewBody.CHEST, Vector3(0, 0, -40))
	var settled_at := -1.0
	var finite := true
	var lowest := INF
	var stretch := 0.0
	for frame in range(300):
		await physics_frame
		model.set_motion(0.0, true, false, false, DT)
		rd.apply_pose()
		for bone in rd.parts:
			var p: Vector3 = rd.parts[bone].global_position
			finite = finite and p.is_finite()
			lowest = minf(lowest, p.y)
		# Joints hold: the thigh stays attached at the hip.
		var hip_world: Vector3 = rd.parts[CrewBody.HIPS].global_transform * (CrewBody.JOINTS[CrewBody.L_LEG] - CrewBody.JOINTS[CrewBody.HIPS])
		stretch = maxf(stretch, hip_world.distance_to(rd.parts[CrewBody.L_LEG].global_position))
		if rd.settled and settled_at < 0.0:
			settled_at = frame * DT
	check(finite and not rd.is_broken(), "ragdoll stays finite")
	check(lowest > -0.02, "no ragdoll part sinks into the floor (lowest origin %.3f)" % lowest)
	check(stretch < 0.06, "joints don't stretch (max %.3f m)" % stretch)
	check(settled_at > 0.0 and settled_at < 3.5, "ragdoll settles within 3.5 s (%.2f)" % settled_at)
	var pelvis: Vector3 = rd.pelvis_position()
	check(pelvis.y < 0.45, "the body ends up lying down (pelvis %.2f m)" % pelvis.y)
	# Knees only bend backwards: the shin's foot end is behind the thigh's plane.
	for side in [CrewBody.L_LEG, CrewBody.R_LEG]:
		var thigh: Basis = rd.parts[side].global_basis
		var shin_dir: Vector3 = -(rd.parts[side + 1].global_basis.y)
		var local := thigh.inverse() * shin_dir
		check(local.z < 0.25, "knee bends the right way (shin z %.2f in thigh space)" % local.z)
	for bone in model.bones:
		check(bone.transform.origin.is_finite(), "bone %s finite" % bone.name)
	rd.queue_free()
	model.queue_free()
	await _steps(2)
	check(CrewRagdoll.active_count == 0, "ragdoll budget released")


## A client physics node in its own world, fed by the host's stream packets
## (straight, no network): after a throw settles both agree.
func test_replication() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.disable_3d = false
	root.add_child(viewport)
	var client_stub := Node3D.new()
	viewport.add_child(client_stub)
	var mirror := StationRules.new()
	mirror.apply_snapshot(rules.public_snapshot(), 2, StationRules.CREW)
	var client := StationPhysics.new()
	client.setup(client_stub, mirror, false)
	client_stub.add_child(client)
	var packets := [0]
	phys.send_stream = func(data: PackedByteArray, reliable: bool, _to: int):
		packets[0] += data.size()
		client.receive(data, reliable)
	phys.send_full_state(2)
	var c := StationLayout.ROOMS.commons.center
	rules._make_loose("cell_3", Vector3(c.x + 2.0, 1.1, c.y + 2.0), Quaternion.IDENTITY, Vector3(5.0, 3.0, 2.0))
	var idle_bytes := 0
	# Fly, land, sleep, then one reliable keyframe of what changed; after
	# that a resting station sends nothing at all.
	for i in range(int((StationPhysics.KEYFRAME_INTERVAL + 5.0) * 60.0)):
		await _steps(1)
		mirror.apply_snapshot(rules.public_snapshot(), 2, StationRules.CREW)
	idle_bytes = packets[0]
	await _steps(int((StationPhysics.KEYFRAME_INTERVAL + 1.0) * 60.0))
	mirror.apply_snapshot(rules.public_snapshot(), 2, StationRules.CREW)
	for i in range(20):
		await process_frame
	var host_at: Vector3 = _body("cell_3").global_position
	var client_at: Vector3 = client.item_body("cell_3").global_position
	check(host_at.distance_to(client_at) < 0.02, "client replica rests where the host's body did (%.3f m)" % host_at.distance_to(client_at))
	check(mirror.items.cell_3.pos.distance_to(host_at) < 0.02, "client rules mirror follows the replica")
	check(packets[0] - idle_bytes == 0, "sleeping bodies cost nothing to replicate (%d B after rest)" % (packets[0] - idle_bytes))
	var prop_err := 0.0
	for k in range(phys.props.size()):
		prop_err = maxf(prop_err, phys.props[k].global_position.distance_to(client.props[k].global_position))
	check(prop_err < 0.02, "client props match the host (%.3f m)" % prop_err)
	phys.send_stream = Callable()
	viewport.queue_free()


class StationCrewWalk:
	const WALK := 3.4
