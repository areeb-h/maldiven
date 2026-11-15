extends SceneTree
## Headless smoke test for Vfx and CameraFx: every API and burst kind, bounded
## pools, clean highlight removal, item fx cleanup, hit-stop restore.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
		push_error("FAIL: " + msg)


func run() -> void:
	var scene := Node3D.new()
	scene.name = "VfxSmoke"
	root.add_child(scene)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 8)
	scene.add_child(cam)
	cam.current = true
	var vfx := Vfx.new()
	scene.add_child(vfx)
	await process_frame

	vfx.ambient_station(scene)
	vfx.ambient_station(scene)  # idempotent: replaces, does not stack
	for kind in Vfx.KINDS:
		vfx.burst(kind, Vector3(1, 0, 2), Vector3(0, 0, -1))
		vfx.burst(kind, Vector3(1, 0, 2), Vector3.UP, Color(0.2, 1.0, 0.4))
	vfx.burst("not_a_kind", Vector3.ZERO)
	vfx.countdown_pulse(Vector3(3, 0, 0), Color(1, 0.4, 0.05))
	vfx.tracer(Vector3(0, 1.2, 0), Vector3(6, 1.0, -3))

	# Items: a cell, a core on the floor, a ghost; then one gets freed.
	var cell := _dummy_item("Cell")
	var core := _dummy_item("Core")
	var ghost := _dummy_item("Ghost")
	for item in [cell, core, ghost]:
		scene.add_child(item)
	vfx.attach_item_fx(cell, "cell")
	vfx.attach_item_fx(core, "core")
	vfx.attach_item_fx(core, "core")  # re-attach replaces
	vfx.attach_item_fx(ghost, "ghost")
	check(vfx.item_fx_count() == 3, "three item fx records (got %d)" % vfx.item_fx_count())

	# Highlight: existing overlay must come back exactly.
	var socket := _dummy_item("Socket")
	scene.add_child(socket)
	var keep := StandardMaterial3D.new()
	var socket_mesh := socket.get_child(0) as MeshInstance3D
	socket_mesh.material_overlay = keep
	vfx.set_interact_highlight(socket, true)
	vfx.set_interact_highlight(socket, true, Color(1, 0.5, 0))
	check(socket_mesh.material_overlay != keep and socket_mesh.material_overlay != null, "highlight applied")
	vfx.set_interact_highlight(socket, false)
	check(socket_mesh.material_overlay == keep, "highlight restored previous overlay")
	vfx.set_interact_highlight(cell, true)
	var fx_root := cell.get_node("VfxItemFx")
	for child in fx_root.get_children():
		if child is MeshInstance3D:
			check((child as MeshInstance3D).material_overlay == null, "highlight skips vfx meshes")
	vfx.set_interact_highlight(cell, false)
	check((cell.get_child(0) as MeshInstance3D).material_overlay == null, "highlight removed cleanly")

	# Trails.
	var thrown := _dummy_item("Thrown")
	scene.add_child(thrown)
	vfx.attach_trail(thrown, Color(1, 0.6, 0.2))
	for i in range(6):
		var extra := _dummy_item("T%d" % i)
		scene.add_child(extra)
		vfx.attach_trail(extra, Color.WHITE)
	check(vfx.trail_count() <= Vfx.MAX_TRAILS, "trails bounded")

	# Camera fx.
	var cfx := CameraFx.new()
	cam.add_child(cfx)
	cfx.setup(cam)
	cfx.shake(0.8, 0.3)
	cfx.kick_fov(6.0, 0.25)
	cfx.set_run_fov(true)
	cfx.vibrate(30)
	cfx.hit_stop(0.05)
	check(Engine.time_scale < 1.0, "hit stop dips time scale")

	# Spam: 50 bursts of every kind.
	for n in range(50):
		for kind in Vfx.KINDS:
			vfx.burst(kind, Vector3(n * 0.1, 0, 0), Vector3(1, 0, 0))
		vfx.countdown_pulse(Vector3.ZERO, Color.RED)
		vfx.tracer(Vector3.ZERO, Vector3(5, 0, n))
	check(vfx.emitter_count() <= vfx.pool_capacity(), "emitters bounded: %d <= %d" % [vfx.emitter_count(), vfx.pool_capacity()])
	var slots := vfx.slot_count()

	for frame in range(120):
		if frame == 20:
			ghost.queue_free()
		if frame == 30:
			thrown.position = Vector3(2, 1, 0)
			vfx.detach_trail(thrown)
		await process_frame
	check(vfx.emitter_count() <= vfx.pool_capacity(), "emitters still bounded after frames")
	check(vfx.slot_count() == slots, "slot pools fixed size")
	check(vfx.item_fx_count() == 2, "freed item fx dropped (got %d)" % vfx.item_fx_count())
	check(is_equal_approx(Engine.time_scale, 1.0), "hit stop restored time scale")
	check(cam.fov > 70.5, "run fov widened (fov %.2f)" % cam.fov)
	cfx.set_run_fov(false)
	var children_before := vfx.get_child_count()
	for n in range(50):
		vfx.burst("shove_impact", Vector3.ZERO, Vector3.FORWARD)
	check(vfx.get_child_count() == children_before, "no node growth on reuse")

	if _failures.is_empty():
		print("PASS: vfx smoke (emitters %d/%d, slots %d)" % [vfx.emitter_count(), vfx.pool_capacity(), slots])
		quit(0)
	else:
		print("FAIL: vfx smoke: " + ", ".join(_failures))
		quit(1)


func _dummy_item(item_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = item_name
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.6, 0.3)
	mi.mesh = box
	mi.position.y = 0.3
	n.add_child(mi)
	return n
