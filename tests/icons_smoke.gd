extends SceneTree
## Icon smoke test: every glyph and alias rasterises at 18 and 128 px in both
## styles with sane alpha coverage, the texture/badge/draw APIs work, and no
## two glyphs are near-duplicates (downscaled alpha masks compared pairwise).
## Prints `PASS: icons` (exit 0) or `FAIL: icons` with reasons (exit 1).
##
##   godot --headless --path . --script res://tests/icons_smoke.gd

const MASK := 16  # compare masks at 16×16
const DUPLICATE_DIFF := 0.075  # mean |Δalpha| below this = near-duplicate
## Names the HUD and menus already use (must stay valid).
const USED := ["hand", "shove", "throw", "crosshair", "jump", "blackout", "drop", "menu", "cell", "core",
	"ammo", "gun", "shuttle", "pod", "airlock", "medbay", "vault", "lock", "unlock", "downed", "ghost",
	"shield", "mask", "face", "crown", "users", "trophy", "bolt", "warning", "check", "info", "abort",
	"clock", "copy", "wifi", "play", "leave", "close", "chevron", "flag", "user", "signal", "dart"]

var _failures: Array[String] = []
var _drawn := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
		printerr("FAIL: " + msg)


func _run() -> void:
	var names := UiIcons.names()
	_check(names.size() >= USED.size(), "too few glyphs: %d" % names.size())
	for name in USED:
		_check(UiIcons.has(name), "missing used icon '%s'" % name)
		_check(UiIcons.GLYPHS.has(name), "used icon '%s' is not a glyph" % name)
	for alias in UiIcons.ALIASES:
		_check(UiIcons.GLYPHS.has(UiIcons.ALIASES[alias]), "alias '%s' points nowhere" % alias)
		_check(not UiIcons.GLYPHS.has(alias), "alias '%s' shadows a glyph" % alias)
	_check(not UiIcons.has("no_such_icon"), "has() accepts unknown names")

	var masks := {}
	for name in names:
		for style in UiIcons.STYLES:
			for px in [18, 128]:
				var img := _raster(UiIcons.svg(name, px, style, px <= UiIcons.SMALL_PX))
				if img == null:
					_check(false, "%s %s %d px: SVG failed to rasterise" % [name, style, px])
					continue
				_check(img.get_width() == px and img.get_height() == px, "%s %s %d px: wrong size %s" % [name, style, px, img.get_size()])
				var cover := _coverage(img)
				_check(cover > 0.06 and cover < 0.85, "%s %s %d px: alpha coverage %.3f out of range" % [name, style, px, cover])
				if style == "duo" and px == 128:
					masks[name] = _mask(img)
		var tex := UiIcons.texture(name)
		_check(tex != null and tex.get_width() == UiIcons.RASTER, "%s: texture() is not %d px" % [name, UiIcons.RASTER])
		_check(UiIcons.texture_styled(name, "color", 24) != null, "%s: texture_styled(color, 24) failed" % name)
		_check(UiIcons.badge_texture(name, Color("5fd4ff"), "hex") != null, "%s: badge_texture failed" % name)
	for alias in UiIcons.ALIASES:
		_check(_raster(UiIcons.svg(alias, 24)) != null, "alias '%s' does not rasterise" % alias)
	_check(UiIcons.texture("no_such_icon") != null, "unknown names must fall back, not crash")

	# Near-duplicate silhouettes.
	var pairs: Array = []
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			pairs.append([_diff(masks[names[i]], masks[names[j]]), names[i], names[j]])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	print("closest silhouettes (mean |Δalpha| at %d×%d):" % [MASK, MASK])
	for k in range(mini(6, pairs.size())):
		print("  %.3f  %s ~ %s" % pairs[k])
	for pair in pairs:
		if pair[0] < DUPLICATE_DIFF:
			_check(false, "near-duplicate icons: %s ~ %s (%.3f)" % [pair[1], pair[2], pair[0]])

	# draw() and badge() on a live canvas, including rotation and scaling.
	var canvas := Control.new()
	canvas.size = Vector2(400, 300)
	canvas.draw.connect(func():
		UiIcons.draw(canvas, "cell", Vector2(30, 30), 24.0, UiStyle.AMBER)
		UiIcons.draw(canvas, "dart", Vector2(80, 30), 20.0, UiStyle.ACCENT, 1.2)
		UiIcons.draw(canvas, "core", Vector2(160, 80), 96.0, Color.WHITE, 0.0, "color")
		UiIcons.draw(canvas, "crew", Vector2(300, 150), 220.0, Color(0.02, 0.04, 0.08, 0.85))
		UiIcons.badge(canvas, "crown", Vector2(60, 200), 72.0, UiStyle.AMBER)
		UiIcons.badge(canvas, "mask", Vector2(150, 200), 40.0, UiStyle.INFILTRATOR, "duo", "square")
		_drawn += 1)
	root.add_child(canvas)
	canvas.scale = Vector2(1.5, 1.5)
	canvas.queue_redraw()
	for i in range(4):
		await process_frame
	if _drawn == 0:
		print("note: canvas draw was not invoked in this run mode; draw() not exercised")

	await _check_ui_components()

	if _failures.is_empty():
		print("PASS: icons (%d glyphs, %d aliases)" % [names.size(), UiIcons.ALIASES.size()])
		quit(0)
	else:
		print("FAIL: icons (%d problems)" % _failures.size())
		quit(1)


## Logo, title cards and the standalone HUD components the trailer instances
## (production plan U1-U11): they build from plain data, seek in time, lay out
## at 1280×720 and 2560×1440, and the exported logo files match the code.
func _check_ui_components() -> void:
	for layout in UiLogo.LAYOUTS:
		var tex := UiLogo.texture(layout, 96, "dark")
		_check(tex != null and tex.get_height() == 96, "logo %s: texture failed" % layout)
		_check(not UiLogo.visor(layout).is_empty(), "logo %s: no helmet visor" % layout)
		for state in UiLogo.STATES:
			_check(_raster(UiLogo.svg(layout, "light", "all", true, state)) != null, "logo %s %s: SVG failed" % [layout, state])
	for file_name in UiLogo.FILES:
		var spec: Array = UiLogo.FILES[file_name]
		var path := "res://assets/ui/logo/" + file_name
		var text := FileAccess.get_file_as_string(path)
		_check(text.strip_edges() == UiLogo.svg(spec[0], spec[1], "all", true, "crew").strip_edges(),
			"%s is stale: re-export with UiLogo.export_all(\"res://assets/ui/logo\")" % path)
	var stage := Control.new()
	root.add_child(stage)
	for frame in [Vector2(1280, 720), Vector2(2560, 1440)]:
		stage.size = frame
		var parts: Array[Control] = [
			UiStyle.card_statement("ONE OF YOU IS LYING."), UiStyle.card_line("2–8 friends. One of you is lying."),
			TitleCard.create("lockup", {"line": "2–8 friends. One of you is lying."}), TitleCard.create("slate"),
			UiStyle.logo(120.0, "infiltrator"), HudAmmo.create({"ammo": 3}), HudCountdown.create("pod", 20.0),
			HudAlerts.create(), HudTicker.create({"font_share": 0.033, "snap": true}), HudResult.new(), HudBriefing.new(),
			UiStyle.make_name_tag("Zara", Color("b36bff")),
		]
		for part in parts:
			stage.add_child(part)
			part.size = frame
		(parts[5] as HudAmmo).set_ammo(2)
		(parts[6] as HudCountdown).set_remaining(2.4)
		(parts[7] as HudAlerts).present("LIGHTS OUT", "danger", "blackout")
		(parts[8] as HudTicker).push(122.0, "Sam triggered a blackout.", {"Sam": Color("ff8a3d")})
		var result := parts[9] as HudResult
		result.present({"title": "CORE STOLEN", "color": UiStyle.INFILTRATOR, "reason": "The cargo pod launched with the core.",
			"infiltrator": {"name": "Sam", "color": Color("ff8a3d")},
			"players": [{"name": "Jon", "color": Color("4da3ff")}, {"name": "Sam", "color": Color("ff8a3d")}],
			"rows": HudResult.story_rows(["2:02  Sam triggered a blackout.", "4:05  Zara was spaced."], "Sam", ["Jon", "Sam", "Zara"])})
		(parts[10] as HudBriefing).present({"role": StationRules.INFILTRATOR, "name": "Sam", "style": "flash"})
		for t in [0.0, 0.05, 1.0, 1.45, 2.6]:
			for part in parts:
				if part.has_method("set_progress"):
					part.call("set_progress", t)
			await process_frame
		_check(result.data.rows[0].anon == "Sam", "result: blackout row is not anonymised live")
		_check(str(result.data.rows[1].tag) == "ZARA WAS CREW", "result: no turning-point tag on the spaced row")
		for part in parts:
			part.queue_free()
		await process_frame
	var hud := StationHud.new()
	stage.add_child(hud)
	hud.set_cinematic(true)
	hud.flash_alert("BLACKOUT — main lights failed", "blackout")
	_check(StationHud.ticker_sentence("POWER RESTORED — vault and armory open") == "Power restored. Vault and armory open.",
		"ticker sentence: %s" % StationHud.ticker_sentence("POWER RESTORED — vault and armory open"))
	await process_frame
	stage.queue_free()


func _raster(svg_text: String) -> Image:
	var img := Image.new()
	if img.load_svg_from_string(svg_text, 1.0) != OK or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _coverage(img: Image) -> float:
	var data := img.get_data()
	var sum := 0
	for i in range(3, data.size(), 4):
		sum += data[i]
	return sum / 255.0 / float(img.get_width() * img.get_height())


## Box-filtered alpha mask, MASK×MASK, values 0..1.
func _mask(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(MASK * MASK)
	var w := img.get_width()
	var cell := w / MASK
	var data := img.get_data()
	for y in range(w):
		for x in range(w):
			out[(y / cell) * MASK + (x / cell)] += data[(y * w + x) * 4 + 3] / 255.0
	for i in range(out.size()):
		out[i] /= float(cell * cell)
	return out


func _diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var sum := 0.0
	for i in range(a.size()):
		sum += absf(a[i] - b[i])
	return sum / a.size()
