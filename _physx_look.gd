extends SceneTree
## Look at the current carried pose in the station.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var st := StationBuilder.build(w)
	StationBuilder.set_power_state(st, "restored")
	var carrier := CrewModel.build(Color("4da3ff"), 1, 2)
	w.add_child(carrier)
	carrier.position = Vector3(0, 0, 2)
	var body := CrewModel.build(Color("ff5a5a"), 0, 1)
	w.add_child(body)
	body.position = Vector3(0, 0, 2.7)
	body.set_downed(true)
	body.set_carried(true)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(3.2, 1.8, 3.6)
	cam.look_at(Vector3(0, 0.6, 2.4))
	cam.current = true
	for i in 60:
		carrier.set_motion(1.5, true, true, false, 1.0 / 60.0)
		body.set_motion(0.0, true, false, false, 1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-maldiven/31b9ade9-c535-5a0e-b4db-12a801c32fe1/scratchpad/look_carry.png")
	quit()
