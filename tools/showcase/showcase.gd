extends SceneTree
## Drift Station key-art showcase: renders the still sets to PNGs, one subfolder
## per set (1_characters, 2_station, 3_items, 4_moments).
##
## xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-method mobile \
##     --resolution 1920x1080 --fixed-fps 30 --script res://tools/showcase/showcase.gd \
##     -- --out <dir> [--set characters,items] [--only key[,key...]] [--preview]
##
## See tools/showcase/README.md for the shot list and how to add a shot.

## The sets, in render order. The first one builds the shared world.
const SETS: Array[Script] = [
	preload("res://tools/showcase/set_characters.gd"),
	preload("res://tools/showcase/set_station.gd"),
	preload("res://tools/showcase/set_items.gd"),
	preload("res://tools/showcase/set_moments.gd"),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := ""
	var only := PackedStringArray()
	var sets := PackedStringArray()
	var preview := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		elif args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1].split(",", false)
		elif args[i] == "--set" and i + 1 < args.size():
			sets = args[i + 1].split(",", false)
		elif args[i] == "--preview":
			preview = true
	if out.is_empty():
		push_error("showcase: pass --out <dir>")
		quit(2)
		return
	configure_quality(root, preview)
	var world: Node3D = SETS[0].new()
	root.add_child(world)
	world.setup()
	await world.wait(2)
	if not is_equal_approx(root.get_process_delta_time(), 1.0 / 30.0):
		push_warning("showcase: run with --fixed-fps 30 so bursts and poses land on the planned frame")
	var shots := 0
	var failed := 0
	for script in SETS:
		var folder: String = script.get_script_constant_map()["FOLDER"]
		if not sets.is_empty() and not folder.get_slice("_", 1) in sets:
			continue
		var node: Node3D = world if script == SETS[0] else script.new()
		if node != world:
			root.add_child(node)
			node.share_world(world)
		var dir := out.path_join(folder)
		for entry: Dictionary in node.SHOTS:
			if not only.is_empty() and not entry.key in only:
				continue
			DirAccess.make_dir_recursive_absolute(dir)
			var err: Error = await node.call(entry.method, dir)
			if err != OK:
				push_error("showcase: shot %s failed (%s)" % [entry.key, error_string(err)])
				failed += 1
			shots += 1
		node.end_set()
	# Under software Vulkan (lavapipe) the engine can stall during shutdown after a
	# 3D frame has been drawn; everything is saved by now, so this line marks the end.
	print("showcase: done, %d shot(s), %d failed" % [shots, failed])
	quit(1 if failed > 0 else 0)


## Desktop-grade settings for stills: MSAA, big shadow atlas, soft shadows,
## high-quality circular bokeh and no mesh LOD. `preview` keeps it cheap.
static func configure_quality(vp: Viewport, preview: bool) -> void:
	vp.msaa_3d = Viewport.MSAA_DISABLED if preview else Viewport.MSAA_4X
	vp.mesh_lod_threshold = 1.0 if preview else 0.0
	vp.positional_shadow_atlas_size = 2048 if preview else 8192
	vp.use_debanding = true
	RenderingServer.directional_shadow_atlas_set_size(2048 if preview else 8192, true)
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_LOW if preview else RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_LOW if preview else RenderingServer.DOF_BLUR_QUALITY_HIGH, not preview)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
