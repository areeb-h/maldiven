extends SceneTree
## Temp render/measure harness for the station art pass (copied into the
## project only while rendering, then deleted).
##   godot --path . --rendering-method mobile --resolution 1600x900 \
##     --script res://tools/_station_shots.gd -- --out DIR [--only a,b] [--states e,r,b] [--measure]

const PITCH := -0.42
const ARM := 5.0

## key: [player x, player z, look dir x, look dir z]
const SHOTS := {
	"commons": [1.0, 4.5, 0.0, -1.0],
	"commons_west": [-1.5, 1.5, -1.0, -0.15],
	"commons_east": [-2.0, -1.0, 1.0, 0.35],
	"command": [0.0, -15.2, 0.0, -1.0],
	"command_side": [-3.5, -17.5, 1.0, -0.6],
	"security": [40.0, -15.8, 0.0, -1.0],
	"security_east": [38.0, -20.0, 1.0, 0.2],
	"docking": [20.0, 4.2, 0.0, -1.0],
	"cargo": [36.5, 2.0, 1.0, 0.25],
	"cargo_north": [40.0, 4.5, 0.0, -1.0],
	"engineering": [58.5, 3.0, 0.5, -1.0],
	"reactor": [62.0, 15.2, 0.0, 1.0],
	"medical": [0.0, 15.6, 0.0, 1.0],
	"medical_west": [3.5, 20.0, -1.0, 0.0],
	"corridor_service": [14.0, 20.0, 1.0, 0.0],
	"observation": [27.0, 20.0, 1.0, -0.35],
	"observation_back": [35.0, 18.5, -1.0, 0.45],
	"corridor_public": [10.0, -20.0, 1.0, 0.0],
	"airlock": [-7.5, 0.6, -1.0, 0.0],
}

var out := ""
var world: Node3D
var station: Node3D
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var avatar: Node3D
var flashlight: SpotLight3D
var vfx: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var only := PackedStringArray()
	var states := PackedStringArray(["emergency", "restored", "blackout"])
	var measure := false
	var overview := true
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		elif args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1].split(",", false)
		elif args[i] == "--states" and i + 1 < args.size():
			states = args[i + 1].split(",", false)
		elif args[i] == "--measure":
			measure = true
		elif args[i] == "--no-overview":
			overview = false
	DirAccess.make_dir_recursive_absolute(out)
	root.use_debanding = true
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	station = StationBuilder.build(world)
	print("BUILD_MS ", Time.get_ticks_msec() - t0)
	_place_gameplay_props()
	pivot = Node3D.new()
	pivot.top_level = true
	world.add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = ARM
	arm.margin = 0.25
	var cs := SphereShape3D.new()
	cs.radius = 0.25
	arm.shape = cs
	arm.collision_mask = 1
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 66
	camera.far = 1500.0
	camera.current = true
	arm.add_child(camera)
	if not measure:
		_add_avatar()
		if ResourceLoader.exists("res://scripts/vfx.gd"):
			vfx = load("res://scripts/vfx.gd").new()
			vfx.name = "Vfx"
			world.add_child(vfx)
			if vfx.has_method("ambient_station"):
				vfx.call("ambient_station", station)
	await _frames(4)
	if measure:
		await _measure()
		quit(0)
		return
	for state in states:
		StationBuilder.set_power_state(station, state)
		await create_timer(2.2).timeout
		if flashlight != null:
			flashlight.visible = state != "restored"
		if overview and (only.is_empty() or "overview" in only):
			await _overview(state)
		for key in SHOTS:
			if not only.is_empty() and not key in only:
				continue
			await _shot(key, state)
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _place_gameplay_props() -> void:
	var sockets := {}
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		var node: Node3D = Props.make_socket(spec.kind)
		node.position = StationLayout.to_world(spec.pos)
		node.rotation.y = spec.facing
		world.add_child(node)
		sockets[socket_id] = node
		node.call("set_state", false, spec.kind in ["vault", "armory"], false)
	for item_id in StationLayout.ITEMS:
		var spec: Dictionary = StationLayout.ITEMS[item_id]
		var item: Node3D = Props.make_item(spec.kind)
		if spec.has("socket"):
			var s: Node3D = sockets[spec.socket]
			s.add_child(item)
			item.transform = s.call("get_seat_transform")
			s.call("set_state", true, spec.kind in ["core", "gun"], false)
		else:
			world.add_child(item)
			item.position = StationLayout.to_world(spec.pos)


func _add_avatar() -> void:
	var path := "res://scripts/art/crew_model.gd"
	if ResourceLoader.exists(path):
		var script: Script = load(path)
		if script != null and script.can_instantiate():
			var built = script.call("build", Color(0.25, 0.55, 1.0), 0, 3)
			if built is Node3D:
				avatar = built
	if avatar == null:
		avatar = Props.make_crew_visual(Color(0.25, 0.55, 1.0))
	world.add_child(avatar)
	flashlight = Props.make_flashlight()
	world.add_child(flashlight)
	flashlight.visible = false


func _set_player(px: float, pz: float, dx: float, dz: float) -> void:
	var yaw := atan2(-dx, -dz)
	var p := Vector3(px, 0.0, pz)
	if avatar != null:
		avatar.position = p
		avatar.rotation.y = yaw + PI
	if flashlight != null:
		flashlight.global_transform = Transform3D(Basis.from_euler(Vector3(-0.25, yaw, 0)), p + Vector3(0, 1.55, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.25))
	pivot.global_position = p + Vector3(0, 1.6, 0)
	pivot.rotation = Vector3(PITCH, yaw, 0)
	arm.spring_length = ARM


func _shot(key: String, state: String) -> void:
	var s: Array = SHOTS[key]
	_set_player(s[0], s[1], s[2], s[3])
	await _frames(3)
	await create_timer(0.25).timeout
	await _save("%s_%s" % [key, state])


func _overview(state: String) -> void:
	pivot.global_position = Vector3(31, 0, 2)
	pivot.rotation = Vector3(-0.78, 0.0, 0)
	arm.spring_length = 0.0
	camera.position = Vector3(0, 0, 62)
	if avatar != null:
		avatar.position = Vector3(0, -50, 0)
	await _frames(4)
	await _save("overview_%s" % state)
	pivot.rotation = Vector3(-0.62, -0.75, 0)
	camera.position = Vector3(0, 0, 70)
	await _frames(4)
	await _save("overview2_%s" % state)
	camera.position = Vector3.ZERO


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [out, label]
	image.save_png(path)
	print("SHOT ", path)


func _measure() -> void:
	StationBuilder.set_power_state(station, "restored")
	await create_timer(2.0).timeout
	var cams := {
		"overview": func():
			pivot.global_position = Vector3(31, 0, 2)
			pivot.rotation = Vector3(-0.78, 0.0, 0)
			arm.spring_length = 0.0
			camera.position = Vector3(0, 0, 62),
		"commons_gameplay": func():
			camera.position = Vector3.ZERO
			_set_player(3.5, 0.0, 0.0, -1.0),
		"commons_gameplay_east": func():
			camera.position = Vector3.ZERO
			_set_player(-2.0, -1.0, 1.0, 0.35),
		"reactor_gameplay": func():
			camera.position = Vector3.ZERO
			_set_player(62.0, 15.2, 0.0, 1.0),
	}
	for state in ["restored", "emergency"]:
		StationBuilder.set_power_state(station, state)
		await create_timer(1.8).timeout
		for key in cams:
			(cams[key] as Callable).call()
			await _frames(8)
			var dc := 0
			var prim := 0
			var obj := 0
			var samples := 4
			for i in samples:
				await RenderingServer.frame_post_draw
				dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
				obj += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
			var vp := root
			var vis_dc := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var sh_dc := vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var vis_pr := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
			var sh_pr := vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
			print("MEASURE %s %s draw_calls=%d primitives=%d objects=%d | visible dc=%d prim=%d | shadow dc=%d prim=%d" % [state, key, dc / samples, prim / samples, obj / samples, vis_dc, vis_pr, sh_dc, sh_pr])
			await _save("measure_%s_%s" % [key, state])
	print("MEASURE_DONE")
