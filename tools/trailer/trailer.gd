extends SceneTree
## Renders the Drift Station trailer (cut.gd) to a PNG sequence plus an audio cue
## sheet; tools/trailer/make_video.py turns them into the MP4 files.
##
## xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . --rendering-method mobile \
##     --resolution 1280x720 --fixed-fps 30 --script res://tools/trailer/trailer.gd \
##     -- --out <dir> [--fps 30] [--from 0] [--to 80] [--preview] [--check] [--msaa 4|2]
##
## Masters are rendered supersampled (e.g. --resolution 2560x1440) with 4x MSAA
## and downscaled to 1080p by make_video.py.
##
## --check (run with --headless) steps through each beat and only reports
## cameras inside geometry or blocked views; it renders nothing.
##
## Frames are taken at a fixed step of 1/fps seconds, so --fixed-fps must equal
## --fps. Godot's Movie Maker is not used: the cut needs to start on its first
## beat (not on engine start-up), and under software Vulkan the engine can stall
## during shutdown before Movie Maker finalises its WAV.

const CutScript := preload("res://tools/trailer/cut.gd")
const ShowcaseScript := preload("res://tools/showcase/showcase.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := ""
	var fps := 30.0
	var from := 0.0
	var to := -1.0
	var preview := false
	var check := false
	var msaa := 4
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var value := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--out":
				out = value
			"--fps":
				fps = float(value)
			"--from":
				from = float(value)
			"--to":
				to = float(value)
			"--preview":
				preview = true
			"--check":
				check = true
			"--msaa":
				msaa = int(value)
	if out.is_empty():
		push_error("trailer: pass --out <dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out.path_join("frames"))
	ShowcaseScript.configure_quality(root, preview, msaa)
	var cut: Node3D = CutScript.new()
	root.add_child(cut)
	cut.setup_cut(fps)
	if check:
		await _check(cut)
		quit(0)
		return
	var total: float = CutScript.total_seconds()
	if to < 0.0 or to > total:
		to = total
	# Warm up shaders and probes on the first beat before frame 0 is taken.
	for i in 4:
		cut.update(from)
		await process_frame
	cut.restart()
	var first := int(round(from * fps))
	var last := int(round(to * fps))
	var started := Time.get_ticks_msec()
	for f in range(first, last):
		cut.update(float(f) / fps)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(out.path_join("frames/f_%05d.png" % (f - first)))
		if (f - first) % int(fps * 10.0) == 0:
			print("trailer: %.1f s of %.1f rendered (%.0f s wall)" % [float(f) / fps, to, (Time.get_ticks_msec() - started) / 1000.0])
	var sheet := {"fps": fps, "from": from, "to": to, "frames": last - first, "cues": cut.cues,
		"render_seconds": (Time.get_ticks_msec() - started) / 1000.0}
	var file := FileAccess.open(out.path_join("cues.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(sheet, "\t"))
	file.close()
	# Under software Vulkan the engine can stall during shutdown; this line marks the end.
	print("trailer: done, %d frames in %.0f s" % [last - first, sheet.render_seconds])
	quit(0)


## Steps through every beat at 20 %, 50 % and 80 % of its length and reports
## camera problems.
func _check(cut: Node3D) -> void:
	var start := 0.0
	for beat: Array in CutScript.BEATS:
		var t := start
		while t < start + float(beat[1]):
			cut.update(t)
			await process_frame
			t += 1.0 / cut.fps
		for k in [0.2, 0.5, 0.8]:
			cut.update(start + float(beat[1]) * k)
			await physics_frame
			cut.check_view("%s @%.1f" % [beat[0], start + float(beat[1]) * k])
		start += float(beat[1])
	print("trailer: check done")
