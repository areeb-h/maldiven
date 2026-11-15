extends SceneTree
var out_dir := ""
var station: Node3D
var cam: Camera3D
var vfx: Vfx
var world: Node3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	call_deferred("run")

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + "/" + name + ".png")
	print("saved ", name)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	station = StationBuilder.build(world)
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		var node: Node3D = Props.make_socket(spec.kind)
		node.position = StationLayout.to_world(spec.pos)
		node.rotation.y = spec.facing
		world.add_child(node)
	vfx = Vfx.new()
	world.add_child(vfx)
	vfx.ambient_station(world)
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 1500
	world.add_child(cam)
	cam.current = true
	StationBuilder.set_power_state(station, "emergency")
	await _frames(20)
	cam.position = Vector3(62, 4.0, 3.0)
	cam.look_at(Vector3(62, 1.4, -5.5))
	vfx._ambient[0].next = 0.0
	vfx._ambient[1].next = 0.0
	await _frames(45)
	await _snap("st_engineering")
	# Third-person-ish view in the reactor room.
	cam.position = Vector3(55.5, 5.5, 13.5)
	cam.look_at(Vector3(62, 0.5, 19.3))
	vfx.burst("power_wave", Vector3(62, 0, 19.3))
	StationBuilder.set_power_state(station, "restored")
	await _frames(7)
	await _snap("st_wave_a")
	# Standing in the reactor-medical corridor watching it roll past.
	vfx.burst("power_wave", Vector3(62, 0, 19.3))
	cam.position = Vector3(36, 4.5, 23)
	cam.look_at(Vector3(48, 0.5, 20))
	await _frames(20)
	await _snap("st_wave_b")
	quit(0)
