extends SceneTree
## Scratch renderer: builds a dark test bay, fires each effect, saves PNGs.

var out_dir := ""
var vfx: Vfx
var cam: Camera3D
var scene: Node3D
var only: PackedStringArray = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	call_deferred("run")

func _floor_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11, 0.115, 0.125)
	m.metallic = 0.75
	m.roughness = 0.42
	return m

func _build_bay() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = false
	for level in range(7):
		env.set_glow_level(level, [0.0, 1.0, 0.8, 1.0, 0.6, 0.0, 0.0][level])
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mi.mesh = pm
	floor_mi.material_override = _floor_mat()
	scene.add_child(floor_mi)
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.25, 0.27, 0.3)
	box_mat.metallic = 0.5
	box_mat.roughness = 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for p in [Vector3(-3, 0, -2), Vector3(3.5, 0, -3), Vector3(-4.5, 0, 2.5), Vector3(5, 0, 1.5), Vector3(0, 0, -6), Vector3(-8, 0, -8), Vector3(9, 0, -9), Vector3(14, 0, 4), Vector3(-15, 0, 6), Vector3(20, 0, -14), Vector3(-22, 0, -18), Vector3(30, 0, 10)]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.8, 1.8)
		bm.size = Vector3(s, s * rng.randf_range(0.6, 1.4), s)
		mi.mesh = bm
		mi.material_override = box_mat
		mi.position = p + Vector3(0, bm.size.y * 0.5, 0)
		mi.rotation.y = rng.randf() * PI
		scene.add_child(mi)
	# Back wall segments.
	for x in range(-30, 31, 6):
		var w := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(5.6, 3.2, 0.4)
		w.mesh = wb
		w.material_override = box_mat
		w.position = Vector3(x, 1.6, -12)
		scene.add_child(w)
	var omni := OmniLight3D.new()
	omni.position = Vector3(0, 3, 1)
	omni.light_color = Color(1.0, 0.85, 0.7)
	omni.light_energy = 1.6
	omni.omni_range = 16
	scene.add_child(omni)
	var dl := DirectionalLight3D.new()
	dl.rotation = Vector3(-0.9, 0.6, 0)
	dl.light_energy = 0.45
	dl.light_color = Color(0.6, 0.7, 1.0)
	scene.add_child(dl)
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 500
	scene.add_child(cam)
	cam.current = true

func _socket() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.35
	cm.height = 0.76
	mi.mesh = cm
	mi.position.y = 0.38
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.19, 0.21)
	m.metallic = 0.6
	mi.material_override = m
	n.add_child(mi)
	return n

func _person(color: Color) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	mi.mesh = cap
	mi.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	mi.material_override = m
	n.add_child(mi)
	return n

func _shot(name: String, cam_pos: Vector3, look: Vector3, frames: int, setup: Callable) -> void:
	if not only.is_empty() and not only.has(name):
		return
	if vfx != null:
		vfx.queue_free()
	for c in scene.get_children():
		if c.has_meta("temp"):
			c.queue_free()
	await process_frame
	vfx = Vfx.new()
	scene.add_child(vfx)
	cam.position = cam_pos
	cam.look_at(look)
	await process_frame
	var tick: Callable = setup.call()
	for f in range(frames):
		if tick.is_valid():
			tick.call(f)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	print("saved ", name)

func _temp(n: Node3D, at: Vector3) -> Node3D:
	n.set_meta("temp", true)
	n.position = at
	scene.add_child(n)
	return n

func run() -> void:
	_build_bay()
	var near := Vector3(0, 1.9, 3.6)
	await _shot("pickup", near, Vector3(0, 0.5, 0), 9, func():
		vfx.burst("pickup", Vector3.ZERO, Vector3.UP, Color(1.0, 0.6, 0.14))
		return Callable())
	await _shot("drop", Vector3(0, 1.5, 3.0), Vector3(0, 0.3, 0), 8, func():
		vfx.burst("drop", Vector3.ZERO)
		return Callable())
	await _shot("insert_cell", Vector3(0, 1.7, 2.6), Vector3(0, 0.8, 0), 12, func():
		_temp(_socket(), Vector3.ZERO)
		vfx.burst("insert_cell", Vector3.ZERO)
		return Callable())
	await _shot("shove_impact", Vector3(-2.6, 1.6, 2.4), Vector3(0, 1.0, 0), 5, func():
		_temp(_person(Color(0.8, 0.3, 0.3)), Vector3(0.6, 0, 0))
		vfx.burst("shove_impact", Vector3(0.6, 0, 0), Vector3(1, 0, 0))
		return Callable())
	await _shot("footstep_dust", Vector3(0, 0.9, 1.8), Vector3(0, 0.1, 0), 8, func():
		vfx.burst("footstep_dust", Vector3(-0.2, 0, 0), Vector3(0, 0, -1))
		vfx.burst("footstep_dust", Vector3(0.25, 0, -0.5), Vector3(0, 0, -1))
		return Callable())
	await _shot("power_wave", Vector3(-6, 9, 22), Vector3(0, 0, -2), 34, func():
		vfx.burst("power_wave", Vector3(0, 0, -4))
		return Callable())
	await _shot("power_wave_early", Vector3(-4, 4, 14), Vector3(0, 1, -4), 12, func():
		vfx.burst("power_wave", Vector3(0, 0, -4))
		return Callable())
	await _shot("blackout_flicker", Vector3(0, 1.6, 7), Vector3(0, 1.8, 0), 22, func():
		vfx.burst("blackout_flicker", Vector3(0, 0, 0))
		return Callable())
	await _shot("launch", Vector3(-6, 2.5, 7), Vector3(0, 1.2, 0), 50, func():
		vfx.burst("launch", Vector3(0, 2.6, 0), Vector3.UP)
		return Callable())
	await _shot("alarm_strobe", Vector3(0, 2.6, 7), Vector3(0, 1.5, 0), 22, func():
		vfx.burst("alarm_strobe", Vector3(0, 0, 0))
		return Callable())
	await _shot("countdown_pulse", Vector3(0, 1.9, 3.0), Vector3(0, 0.4, 0), 14, func():
		_temp(_socket(), Vector3.ZERO)
		vfx.countdown_pulse(Vector3.ZERO, Color(1.0, 0.42, 0.04))
		return Callable())
	await _shot("items", Vector3(0, 1.6, 3.4), Vector3(0, 0.6, 0), 70, func():
		var cell := _temp(Props.make_item("cell"), Vector3(-0.7, 0, 0))
		var core := _temp(Props.make_item("core"), Vector3(0.7, 0, 0))
		vfx.attach_item_fx(cell, "cell")
		vfx.attach_item_fx(core, "core")
		return Callable())
	await _shot("core_beam", Vector3(0, 4, 12), Vector3(0, 2.5, 0), 70, func():
		var core := _temp(Props.make_item("core"), Vector3(0, 0, 0))
		vfx.attach_item_fx(core, "core")
		return Callable())
	await _shot("highlight", Vector3(0, 1.7, 3.0), Vector3(0, 0.6, 0), 10, func():
		var s := _temp(_socket(), Vector3(-0.5, 0, 0))
		var cell := _temp(Props.make_item("cell"), Vector3(0.6, 0, 0))
		vfx.set_interact_highlight(s, true)
		vfx.set_interact_highlight(cell, true, Color(1.0, 0.7, 0.2))
		return Callable())
	await _shot("hl_hull", Vector3(0, 1.7, 3.0), Vector3(0, 0.6, 0), 6, func():
		var s := _temp(_socket(), Vector3(-0.5, 0, 0))
		vfx.set_interact_highlight(s, true)
		var mi := s.get_child(0) as MeshInstance3D
		(mi.material_overlay as ShaderMaterial).next_pass = null
		return Callable())
	await _shot("hl_rim", Vector3(0, 1.7, 3.0), Vector3(0, 0.6, 0), 6, func():
		var s := _temp(_socket(), Vector3(-0.5, 0, 0))
		vfx.set_interact_highlight(s, true)
		var mi := s.get_child(0) as MeshInstance3D
		mi.material_overlay = (mi.material_overlay as ShaderMaterial).next_pass
		return Callable())
	await _shot("muzzle_tracer", Vector3(-1.5, 1.8, 4), Vector3(2, 1.2, -2), 3, func():
		vfx.burst("muzzle_flash", Vector3(-1, 1.3, 0), Vector3(0.8, 0, -0.6).normalized())
		vfx.tracer(Vector3(-1, 1.3, 0), Vector3(3.3, 0.9, -3.2))
		return Callable())
	await _shot("muzzle", Vector3(0, 1.4, 1.6), Vector3(0, 1.3, 0), 2, func():
		vfx.burst("muzzle_flash", Vector3(-0.3, 1.3, 0), Vector3(1, 0, -0.3).normalized())
		return Callable())
	await _shot("downed", Vector3(0, 1.6, 3.2), Vector3(0, 0.3, 0), 10, func():
		vfx.burst("downed", Vector3.ZERO)
		return Callable())
	await _shot("revive", Vector3(0, 1.6, 4.2), Vector3(0, 1.0, 0), 30, func():
		_temp(_person(Color(0.3, 0.5, 0.8)), Vector3.ZERO)
		vfx.burst("revive", Vector3.ZERO)
		return Callable())
	await _shot("airlock_vent", Vector3(-5, 2.4, 6), Vector3(2, 1.2, -1), 22, func():
		vfx.burst("airlock_vent", Vector3(-1, 0, 0), Vector3(1, 0, -0.3).normalized())
		return Callable())
	await _shot("spaced", Vector3(0, 2, 5), Vector3(0, 1, 0), 40, func():
		var body := _temp(_person(Color(0.8, 0.6, 0.2)), Vector3.ZERO)
		vfx.burst("spaced", Vector3.ZERO, Vector3(2.4, 0.6, 0))
		return func(f: int): body.position = Vector3(f * 0.04, f * 0.01, 0); body.rotation.z = -f * 0.05)
	await _shot("trail_ghost", Vector3(0, 2.2, 5), Vector3(0, 1, 0), 40, func():
		var thrown := _temp(Props.make_item("cell"), Vector3(-2, 1, 0))
		vfx.attach_trail(thrown, Color(1.0, 0.6, 0.15))
		var ghost := _temp(_person(Color(0.5, 0.6, 0.8, 1.0)), Vector3(2, 0, -1))
		vfx.attach_item_fx(ghost, "ghost")
		return func(f: int): thrown.position = Vector3(-2.5 + f * 0.09, 1.0 + sin(f * 0.08) * 0.8, 0.5 - f * 0.02))
	await _shot("amb_steam", Vector3(62, 3.0, 1.0), Vector3(62, 1.4, -5.5), 40, func():
		vfx.ambient_station(scene)
		vfx._ambient[0].next = 0.0
		vfx._ambient[1].next = 0.0
		vfx._ambient[2].next = 0.3
		return Callable())
	await _shot("amb_conduit", Vector3(36.5, 2.6, -2.5), Vector3(35.5, 2.3, -6.8), 26, func():
		vfx.ambient_station(scene)
		vfx._ambient[2].next = 0.3
		return Callable())
	quit(0)
