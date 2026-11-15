extends SceneTree
## Temporary render harness for the item/socket art pass (copied into the project
## only while rendering, then deleted).
##   godot --path . --rendering-method mobile --resolution 1600x900 --script res://_items_render.gd -- --mode studio --out DIR

var out := ""
var mode := "studio"
var only := PackedStringArray()
var powers := PackedStringArray(["emergency", "restored"])
var world: Node3D
var cam: Camera3D
var station: Node3D
var vfx: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out":
			out = args[i + 1]
		elif args[i] == "--mode":
			mode = args[i + 1]
		elif args[i] == "--only":
			only = args[i + 1].split(",", false)
		elif args[i] == "--powers":
			powers = args[i + 1].split(",", false)
	DirAccess.make_dir_recursive_absolute(out)
	root.use_debanding = true
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	cam = Camera3D.new()
	cam.fov = 40
	cam.near = 0.02
	cam.far = 800
	world.add_child(cam)
	cam.current = true
	match mode:
		"studio":
			await _studio()
		"held":
			await _held()
		"sockets":
			await _sockets()
	quit(0)


func _want(key: String) -> bool:
	return only.is_empty() or key in only


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save(name: String) -> void:
	var img := await _grab()
	img.save_png(out.path_join(name + ".png"))
	print("SAVED ", name)


func _look(from: Vector3, at: Vector3, fov := 40.0) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, at, Vector3.UP)


# --- studio close-ups ----------------------------------------------------------------

func _studio_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.05, 0.065)
	var sky := Sky.new()
	sky.sky_material = ArtMaterials.sky_material(Vector3(0.5, 0.7, -0.4))
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.66)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 2.0
	env.glow_enabled = true
	env.glow_normalized = false
	for level in range(7):
		env.set_glow_level(level, [0.0, 1.0, 0.8, 0.6, 0.4, 0.0, 0.0][level])
	env.glow_strength = 1.1
	env.glow_bloom = 0.01
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	world.add_child(key)
	key.look_at_from_position(Vector3.ZERO, Vector3(-0.6, -0.7, -0.5), Vector3.UP)
	key.light_color = Color(1.0, 0.95, 0.88)
	key.light_energy = 1.3
	key.shadow_enabled = true
	var rim := DirectionalLight3D.new()
	world.add_child(rim)
	rim.look_at_from_position(Vector3.ZERO, Vector3(0.5, -0.3, 0.85), Vector3.UP)
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 0.9
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.11, 0.115, 0.13)
	fm.roughness = 0.55
	floor_mi.material_override = fm
	world.add_child(floor_mi)


func _studio() -> void:
	_studio_env()
	var items := {"cell": Vector3(0, 0.29, 0), "core": Vector3(0, 0.33, 0), "gun": Vector3(0, 0.07, 0.11)}
	var dists := {"cell": 1.35, "core": 1.4, "gun": 0.62}
	for kind in items:
		if not _want(kind):
			continue
		var item: Node3D = Props.make_item(kind)
		world.add_child(item)
		var c: Vector3 = items[kind]
		var d: float = dists[kind]
		var angles := [[0.55, 0.28], [PI * 0.5 + 0.05, 0.12], [PI + 0.7, 0.45]]
		if kind == "gun":
			angles = [[1.0, 0.3], [PI * 0.5, 0.05], [-2.3, 0.35]]
		var idx := 0
		for a in angles:
			var yaw: float = a[0]
			var pitch: float = a[1]
			var from := c + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
			_look(from, c, 40.0)
			await _frames(6)
			await _save("%s_%d" % [kind, idx])
			idx += 1
		if kind == "gun":
			for n in [0, 1, 2]:
				item.call("set_ammo", n)
				_look(c + Vector3(-0.25, 0.12, -0.5), c + Vector3(0, 0.03, 0), 40.0)
				await _frames(4)
				await _save("gun_ammo%d" % n)
		item.queue_free()
		await _frames(2)


# --- held by a crew member -----------------------------------------------------------

func _station_world(power: String) -> void:
	if station == null:
		station = StationBuilder.build(world)
		vfx = load("res://scripts/vfx.gd").new()
		vfx.name = "Vfx"
		world.add_child(vfx)
		vfx.call("ambient_station", station)
	StationBuilder.set_power_state(station, power)
	await create_timer(2.0).timeout


func _held() -> void:
	for power in powers:
		await _station_world(power)
		for kind in ["cell", "core", "gun"]:
			if not _want(kind):
				continue
			var body := CharacterBody3D.new()
			world.add_child(body)
			body.position = Vector3(2.5, 0, 2.0)
			var m: CrewModel = CrewModel.build(Color("4da3ff"), 0, 1)
			body.add_child(m)
			var item: Node3D = Props.make_item(kind)
			if kind == "gun":
				m.hand_anchor.add_child(item)
				m.set_aiming(true)
			else:
				m.carry_anchor.add_child(item)
				vfx.call("attach_item_fx", item, kind)
			for i in 90:
				m.set_motion(0.0, true, kind != "gun", false, 1.0 / 60.0)
				await process_frame
			var head := body.position + Vector3(0, 1.6, 0)
			# Behind-left over the shoulder (gameplay), front three-quarter, side.
			var views := [[PI + 0.5, -0.32, 5.0], [0.6, -0.2, 4.5], [-PI * 0.5, -0.25, 3.0]]
			if kind == "gun":
				views = [[PI - 0.35, -0.2, 3.4], [0.9, -0.15, 4.5], [-PI * 0.5 + 0.2, -0.15, 2.4]]
			var vi := 0
			for v in views:
				var yaw: float = v[0]
				var pitch: float = v[1]
				var dist: float = v[2]
				var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
				_look(head + dir * dist, head + Vector3(0, -0.45, 0), 66.0)
				for i in 4:
					m.set_motion(0.0, true, kind != "gun", false, 1.0 / 60.0)
					await process_frame
				await _save("held_%s_%s_%d" % [kind, power, vi])
				vi += 1
			body.queue_free()
			await _frames(2)


# --- sockets in the station ---------------------------------------------------------

const SEAT_ITEM := {"vault": "core", "reactor": "cell", "shuttle": "core", "pod": "core", "armory": "gun"}


func _sockets() -> void:
	var sockets := {}
	await _station_world(powers[0])
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		var node: Node3D = Props.make_socket(spec.kind)
		node.name = "Socket_" + socket_id
		node.position = StationLayout.to_world(spec.pos)
		node.rotation.y = spec.facing
		world.add_child(node)
		sockets[socket_id] = node
		node.call("set_state", false, spec.kind in ["vault", "armory"], false)
	var groups := {"vault": ["vault"], "reactor": ["reactor_1", "reactor_2", "reactor_3"], "shuttle": ["shuttle"], "pod": ["pod"],
		"armory": ["armory"], "medbay": ["medbay"], "airlock_console": ["airlock_console"]}
	var states := [[false, false, false], [true, false, false], [false, true, false], [true, true, false],
		[false, false, true], [true, false, true], [false, true, true], [true, true, true]]
	for power in powers:
		await _station_world(power)
		for g in groups:
			if not _want(g):
				continue
			var ids: Array = groups[g]
			var main_id: String = ids[ids.size() / 2]
			var spec: Dictionary = StationLayout.SOCKETS[main_id]
			var p := StationLayout.to_world(spec.pos)
			var fwd := Vector3(sin(spec.facing), 0, cos(spec.facing))
			var right := Vector3(fwd.z, 0, -fwd.x)
			# [distance, camera height, look-at height, sideways share]
			var cams := {"vault": [4.4, 2.4, 1.45, 0.3], "armory": [3.9, 2.0, 1.45, 0.3], "medbay": [3.8, 2.1, 1.1, 0.45],
				"shuttle": [3.6, 1.9, 1.2, 0.4], "pod": [3.6, 1.9, 1.2, 0.4], "airlock_console": [3.2, 1.8, 1.2, 0.4]}
			var cfg: Array = cams.get(g, [3.6, 1.9, 1.15, 0.35])
			var from: Vector3 = p + fwd * float(cfg[0]) + right * float(cfg[0]) * float(cfg[3]) + Vector3(0, float(cfg[1]), 0)
			var at: Vector3 = p + Vector3(0, float(cfg[2]), 0)
			if g == "reactor":
				from = Vector3(68.6, 2.3, 20.2)
				at = Vector3(62.4, 1.0, 23.2)
			var sheet := Image.create(3200, 900, false, Image.FORMAT_RGB8)
			var si := 0
			for st in states:
				var items: Array[Node3D] = []
				for id in ids:
					var sock: Node3D = sockets[id]
					sock.call("set_state", st[0], st[1], st[2])
					if st[0] and SEAT_ITEM.has(spec.kind):
						var it: Node3D = Props.make_item(SEAT_ITEM[spec.kind])
						sock.add_child(it)
						it.transform = sock.call("get_seat_transform")
						items.append(it)
				_look(from, at, 55.0)
				await create_timer(0.9).timeout
				var img := await _grab()
				img.resize(800, 450, Image.INTERPOLATE_LANCZOS)
				sheet.blit_rect(img, Rect2i(0, 0, 800, 450), Vector2i((si % 4) * 800, (si / 4) * 450))
				if si == 0 or si == 4 or si == 1:
					var full := await _grab()
					full.save_png(out.path_join("socket_%s_%s_s%d.png" % [g, power, si]))
				for it in items:
					it.queue_free()
				si += 1
			sheet.save_png(out.path_join("sheet_%s_%s.png" % [g, power]))
			print("SAVED sheet ", g, " ", power)
			for id in ids:
				(sockets[id] as Node3D).call("set_state", false, StationLayout.SOCKETS[id].kind in ["vault", "armory"], false)
