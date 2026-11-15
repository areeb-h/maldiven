extends SceneTree
## Drift Station key-art showcase: renders the shot list in shots.gd to PNGs.
##
## xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-method mobile \
##     --resolution 1920x1080 --fixed-fps 30 --script res://tools/showcase/showcase.gd \
##     -- --out <dir> [--only key[,key...]]
##
## See tools/showcase/README.md for the shot list and how to add a shot.

const ShotsScript := preload("res://tools/showcase/shots.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := ""
	var only := PackedStringArray()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		elif args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1].split(",", false)
	if out.is_empty():
		push_error("showcase: pass --out <dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_configure_quality()
	var studio: Node3D = ShotsScript.new()
	root.add_child(studio)
	studio.setup()
	await studio.wait(2)
	if not is_equal_approx(root.get_process_delta_time(), 1.0 / 30.0):
		push_warning("showcase: run with --fixed-fps 30 so bursts and poses land on the planned frame")
	var failed := 0
	var shots := 0
	for entry: Dictionary in studio.SHOTS:
		if not only.is_empty() and not entry.key in only:
			continue
		var err: Error = await studio.call(entry.method, out)
		if err != OK:
			push_error("showcase: shot %s failed (%s)" % [entry.key, error_string(err)])
			failed += 1
		shots += 1
	# Under software Vulkan (lavapipe) the engine can stall during shutdown after a
	# 3D frame has been drawn; everything is saved by now, so this line marks the end.
	print("showcase: done, %d shot(s), %d failed" % [shots, failed])
	quit(1 if failed > 0 else 0)


## Desktop-grade settings for stills: MSAA, big shadow atlas, soft shadows,
## high-quality circular bokeh and no mesh LOD.
func _configure_quality() -> void:
	root.msaa_3d = Viewport.MSAA_4X
	root.mesh_lod_threshold = 0.0
	root.positional_shadow_atlas_size = 8192
	root.use_debanding = true
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
