extends SceneTree
func _initialize() -> void:
	call_deferred("_go")
func _go() -> void:
	var mode := OS.get_cmdline_user_args()[0]
	var holder := Node3D.new()
	root.add_child(holder)
	var s := StationBuilder.build(holder)
	if "vfx" in mode:
		var v := Vfx.new()
		holder.add_child(v)
		v.ambient_station(s)
	if "dof" in mode:
		RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	if "atlas" in mode:
		root.positional_shadow_atlas_size = 8192
		RenderingServer.directional_shadow_atlas_set_size(8192, true)
	if "sock" in mode:
		holder.add_child(Props.make_socket("vault"))
	if "msaa" in mode:
		root.msaa_3d = Viewport.MSAA_4X
	if "soft" in mode:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	if "bokeh" in mode:
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	if "cam" in mode:
		var c := Camera3D.new()
		c.attributes = CameraAttributesPractical.new()
		holder.add_child(c)
		c.current = true
	await process_frame
	await process_frame
	if "clean" in mode:
		for c in holder.find_children("*", "Camera3D", true, false):
			(c as Camera3D).attributes = null
		holder.free()
		await process_frame
	print("quitting ", mode)
	quit(0)
