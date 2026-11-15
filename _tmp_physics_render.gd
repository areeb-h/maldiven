extends SceneTree
## Temporary: renders physics moments for visual review (run with --fixed-fps 60).

const OUT := "/tmp/claude-0/-home-user-maldiven/31b9ade9-c535-5a0e-b4db-12a801c32fe1/scratchpad/physics/iter/"
var stub: Node3D
var station: Node3D
var rules: StationRules
var phys: StationPhysics
var cam: Camera3D
var only := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	stub = Node3D.new()
	stub.name = "World"
	root.add_child(stub)
	station = StationBuilder.build(stub)
	StationBuilder.set_power_state(station, "restored")
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
	rules.setup({1: {"name": "A"}, 2: {"name": "B"}}, rng)
	rules.tick(StationRules.BRIEFING_SECONDS + 0.1)
	for id in rules.players:
		rules.players[id].pos = Vector3(-40.0 - id * 3.0, 0, 45)
	var visuals := {}
	for item_id in StationLayout.ITEMS:
		visuals[item_id] = Props.make_item(StationLayout.ITEMS[item_id].kind)
	phys = StationPhysics.new()
	phys.setup(stub, rules, true, visuals)
	stub.add_child(phys)
	for item_id in visuals:
		phys.item_body(item_id).add_child(visuals[item_id])
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 1500
	stub.add_child(cam)
	cam.current = true
	await _steps(30)
	if only == "" or "ragdoll" in only.split(","):
		await shot_ragdoll()
	if only == "" or "carry" in only.split(","):
		await shot_carry()
	if only == "" or "stagger" in only.split(","):
		await shot_stagger()
	if only == "" or "items" in only.split(","):
		await shot_items()
	if only == "" or "props" in only.split(","):
		await shot_props()
	if only == "" or "vent" in only.split(","):
		await shot_vent()
	quit()


func _steps(n: int) -> void:
	for i in range(n):
		rules.tick(1.0 / 60.0)
		for event in rules.drain_events():
			phys.on_event(event)
		await physics_frame


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + label + ".png")
	print("SHOT ", label)


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)


func _crew(id: int, color: Color, at: Vector3, yaw: float, variant := 0) -> CrewMember:
	var c := CrewMember.new()
	c.setup(id, false, "P%d" % id, color, at)
	c.number = id
	c.variant = variant
	stub.add_child(c)
	c.snap_facing(yaw)
	c.set_remote_pose(at, yaw, 0.0)
	return c


func shot_ragdoll() -> void:
	var a := _crew(11, Color("ff5a5a"), Vector3(2.0, 0, 2.5), PI * 0.15)
	_look(Vector3(4.6, 1.35, 1.2), Vector3(1.6, 0.55, 1.9))
	await _steps(40)
	await _snap("ragdoll_0_standing")
	var dir := Vector3(-0.4, 0, -1).normalized()
	var at := Vector3(2.0, 0, 2.5) + dir * StationRules.DOWN_SLUMP
	var yaw := atan2(dir.x, dir.z) + PI
	a.reactions.collapse(dir, at, yaw)
	a.snap_facing(yaw)
	a.set_life_state("downed")
	a.set_remote_pose(at, yaw, 0.0)
	var marks := {6: "1", 15: "2", 26: "3", 40: "4", 70: "5", 150: "6", 260: "7"}
	for f in range(261):
		await _steps(1)
		if marks.has(f):
			await _snap("ragdoll_%s" % marks[f])
	a.queue_free()
	await _steps(2)


func shot_carry() -> void:
	var carrier := _crew(12, Color("4da3ff"), Vector3(-3.0, 0, -1.0), PI / 2.0, 1)
	var body := _crew(13, Color("ffd23f"), Vector3(-2.3, 0, -1.0), PI / 2.0, 2)
	body.set_life_state("downed")
	await _steps(10)
	body.carrier = carrier
	body.set_carried(true)
	carrier.carrying_body = true
	var pos := Vector3(-3.0, 0, -1.0)
	var yaw := PI / 2.0
	for f in range(200):
		var speed := 3.4 * StationRules.CARRY_SPEED.body
		if f > 110:
			yaw += 0.025  # turning: limbs swing out
		pos += Vector3(sin(yaw), 0, cos(yaw)) * speed / 60.0
		carrier.set_remote_pose(pos, yaw, speed)
		body.set_remote_pose(pos + Vector3(sin(yaw), 0, cos(yaw)) * 0.7, yaw, 0.0)
		_look(pos + Vector3(-0.6, 1.6, 3.4), pos + Vector3(0.6, 0.8, 0))
		await _steps(1)
		if f in [60, 125, 150, 190]:
			await _snap("carry_%d" % f)
	carrier.queue_free()
	body.queue_free()
	await _steps(2)


func shot_stagger() -> void:
	var c := _crew(14, Color("53d769"), Vector3(-2.0, 0, 4.0), 0.0, 3)
	var pusher := _crew(15, Color("c77dff"), Vector3(-2.0, 0, 5.2), PI, 0)
	_look(Vector3(1.6, 1.5, 2.6), Vector3(-2.0, 0.9, 3.0))
	await _steps(20)
	pusher.visual.play_shove()
	await _steps(8)
	var dir := Vector3(0, 0, -1)
	c.reactions.stagger(dir, 1.0)
	c.visual.play_hit()
	c.stunned = true
	var pos := Vector3(-2.0, 0, 4.0)
	var vel := 6.5
	for f in range(60):
		vel = maxf(0.0, vel - 9.0 / 60.0)
		pos += dir * vel / 60.0
		c.set_remote_pose(pos, 0.0, 0.0)
		await _steps(1)
		if f in [4, 10, 18, 28, 42]:
			await _snap("stagger_%02d" % f)
	c.queue_free()
	pusher.queue_free()
	await _steps(2)


func shot_items() -> void:
	# Docking floor: a cell and the core thrown across, bouncing and tumbling.
	_look(Vector3(21.2, 1.25, 4.4), Vector3(18.4, 0.45, 1.6))
	rules._make_loose("cell_2", Vector3(15.6, 1.1, 1.4), Quaternion.IDENTITY, Vector3(6.2, 3.0, 0.4))
	rules._make_loose("core", Vector3(15.4, 1.0, 2.6), Quaternion.IDENTITY, Vector3(5.4, 2.6, -0.3))
	await _steps(1)
	rules.items.cell_2.flight = {}
	rules.items.core.flight = {}
	for f in range(110):
		await _steps(1)
		if f in [14, 26, 34, 44, 60, 109]:
			await _snap("items_%03d" % f)
	rules.respawn_item("core")
	rules.respawn_item("cell_2")
	await _steps(30)


func shot_props() -> void:
	# Docking: a shove topples the barrel into the crate, a thrown cell knocks the chair.
	var b: NetBody = null
	var ch: NetBody = null
	for body in phys.props:
		if StationLayout.room_at(body.global_position) == "docking":
			if body.kind == "barrel":
				b = body
			elif body.kind == "chair":
				ch = body
	_look(Vector3(19.6, 1.9, 0.8), Vector3(18.4, 0.4, 4.6))
	await _snap("props_before")
	phys.on_event({"type": "swing", "at": b.global_position + Vector3(-1.1, 0, -0.9), "dir": Vector3(0.75, 0, 0.6).normalized()})
	rules._make_loose("cell_1", Vector3(20.5, 1.2, 0.5), Quaternion.IDENTITY, Vector3(5.2, 2.2, 3.4))
	for f in range(120):
		await _steps(1)
		if f in [8, 18, 30, 50, 119]:
			await _snap("props_%03d" % f)
	rules.respawn_item("cell_1")
	await _steps(10)


func shot_vent() -> void:
	var r := StationLayout.room_rect("airlock")
	var c := r.get_center()
	rules._make_loose("cell_3", Vector3(c.x + 0.8, 0.2, c.y - 0.6), Quaternion.IDENTITY, Vector3.ZERO)
	rules._make_loose("gun", Vector3(c.x + 1.2, 0.2, c.y + 0.7), Quaternion.IDENTITY, Vector3.ZERO)
	var victim := _crew(16, Color("ff9f40"), Vector3(c.x + 0.6, 0, c.y + 0.2), PI / 2.0, 1)
	await _steps(30)
	_look(Vector3(-9.3, 1.9, 1.3), Vector3(-14.4, 0.7, -0.4))
	StationBuilder.set_airlock_state(station, "warning")
	rules.airlock_state = "warning"
	rules.airlock_left = StationRules.AIRLOCK_WARNING
	var wf := 0
	while rules.airlock_state == "warning":
		await _steps(1)
		wf += 1
		if wf in [60, 150, 205]:
			await _snap("vent_warning_%03d" % wf)
	StationBuilder.set_airlock_state(station, "venting")
	victim.reactions.space_out((StationPhysics.airlock_door() - victim.global_position).normalized())
	victim.visible = false
	for f in range(150):
		await _steps(1)
		if f in [3, 8, 14, 22, 34, 60]:
			await _snap("vent_%02d" % f)
