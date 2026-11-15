extends SceneTree
## Renders contact sheets for the UiIcons set so every glyph can be reviewed at
## real sizes, in every style, on dark glass and on a bright scene, plus a
## colour-blind (deuteranopia / protanopia) simulation of each sheet.
##
##   xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-method mobile \
##     --resolution 1600x1000 --script res://tools/icons/contact_sheet.gd [-- --out=/abs/dir]
##
## Extra user args (after `--`):
##   --out=DIR            output folder (default user://icons_contact)
##   --zoom=a,b,c         also render these icons alone at 18/24/32/48/96/192 px
##   --prefix=NAME        file name prefix (default "icons")
## Works with the old API (texture/draw only) so it can render a "before" sheet.

const ROW_H := 112
const PAGE_ROWS := 12
const LABEL_W := 132
const DARK_BG := Color("060a12")
const GLASS := Color(0.035, 0.06, 0.1, 0.82)
const BRIGHT_A := Color("dfe6ee")
const BRIGHT_B := Color("b9c6d6")

## Machado et al. 2009, severity 1.0 (linear RGB).
const DEUTAN := [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
const PROTAN := [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]

var _out := "user://icons_contact"
var _prefix := "icons"
var _zoom: PackedStringArray = []
var _styled := false
var _names: PackedStringArray = []
var _font: Font
var _api: Variant = load("res://scripts/ui/ui_icons.gd")


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--prefix="):
			_prefix = arg.substr(9)
		elif arg.begins_with("--zoom="):
			_zoom = arg.substr(7).split(",", false)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_font = UiStyle.font("bold")
	var probe: Object = _api.new()
	_styled = probe.has_method("texture_styled")
	if probe.has_method("names"):
		_names = _api.call("names")
	else:
		_names = PackedStringArray(UiIcons.GLYPHS.keys())
	print("contact sheet: %d icons, styled=%s" % [_names.size(), _styled])
	var pages := int(ceil(_names.size() / float(PAGE_ROWS)))
	for page in range(pages):
		var rows := _names.slice(page * PAGE_ROWS, mini(_names.size(), (page + 1) * PAGE_ROWS))
		var img := await _render(Vector2i(1500, 66 + rows.size() * ROW_H), _draw_rows.bind(rows, page, pages))
		_save(img, "%s_rows_%d" % [_prefix, page + 1], true)
	var overview := await _render(Vector2i(1500, _overview_height()), _draw_overview)
	_save(overview, "%s_overview" % _prefix, true)
	for name in _zoom:
		var zoomed := await _render(Vector2i(1500, 470), _draw_zoom.bind(name))
		_save(zoomed, "%s_zoom_%s" % [_prefix, name], false)
	quit(0)


# --- Rendering ----------------------------------------------------------------

func _render(size: Vector2i, painter: Callable) -> Image:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(viewport)
	var canvas := Control.new()
	canvas.size = Vector2(size)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	canvas.draw.connect(func(): painter.call(canvas))
	viewport.add_child(canvas)
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	viewport.queue_free()
	return img


func _save(img: Image, base: String, simulate: bool) -> void:
	var path := _out.path_join(base + ".png")
	img.save_png(path)
	print("  wrote ", ProjectSettings.globalize_path(path))
	if not simulate:
		return
	for pair in [["deutan", DEUTAN], ["protan", PROTAN]]:
		var sim := _simulate(img, pair[1])
		var sim_path := _out.path_join("%s_%s.png" % [base, pair[0]])
		sim.save_png(sim_path)
		print("  wrote ", ProjectSettings.globalize_path(sim_path))


## Colour-vision-deficiency simulation in linear RGB (lookup tables both ways).
func _simulate(src: Image, m: Array) -> Image:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var to_lin := PackedFloat32Array()
	to_lin.resize(256)
	for i in range(256):
		var c := i / 255.0
		to_lin[i] = c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
	var to_srgb := PackedByteArray()
	to_srgb.resize(4097)
	for i in range(4097):
		var v := i / 4096.0
		var s := v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055
		to_srgb[i] = int(round(clampf(s, 0.0, 1.0) * 255.0))
	var m00: float = m[0][0] * 4096.0
	var m01: float = m[0][1] * 4096.0
	var m02: float = m[0][2] * 4096.0
	var m10: float = m[1][0] * 4096.0
	var m11: float = m[1][1] * 4096.0
	var m12: float = m[1][2] * 4096.0
	var m20: float = m[2][0] * 4096.0
	var m21: float = m[2][1] * 4096.0
	var m22: float = m[2][2] * 4096.0
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var r := to_lin[data[i]]
		var g := to_lin[data[i + 1]]
		var b := to_lin[data[i + 2]]
		data[i] = to_srgb[clampi(int(m00 * r + m01 * g + m02 * b), 0, 4096)]
		data[i + 1] = to_srgb[clampi(int(m10 * r + m11 * g + m12 * b), 0, 4096)]
		data[i + 2] = to_srgb[clampi(int(m20 * r + m21 * g + m22 * b), 0, 4096)]
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


# --- Painters -----------------------------------------------------------------

func _icon(canvas: CanvasItem, name: String, center: Vector2, px: float, color: Color, style := "duo") -> void:
	if _styled:
		_api.call("draw", canvas, name, center, px, color, 0.0, style)
	elif style != "color":
		UiIcons.draw(canvas, name, center, px, color)


func _text(canvas: CanvasItem, at: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _bright_rect(canvas: CanvasItem, rect: Rect2) -> void:
	# A sunlit station floor: pale panels with a hazard stripe and a seam.
	canvas.draw_rect(rect, BRIGHT_A)
	canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.55), Vector2(rect.size.x, rect.size.y * 0.45)), BRIGHT_B)
	canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.55 - 2), Vector2(rect.size.x, 2)), Color(1, 1, 1, 0.7))


func _draw_rows(canvas: CanvasItem, rows: PackedStringArray, page: int, pages: int) -> void:
	var w := (canvas as Control).size.x
	canvas.draw_rect(Rect2(Vector2.ZERO, (canvas as Control).size), DARK_BG)
	_text(canvas, Vector2(16, 30), "DRIFT STATION ICONS  %d/%d" % [page + 1, pages], 22, UiStyle.TEXT)
	var heads := [[LABEL_W, "WHITE 18 24 32 48 96"], [LABEL_W + 330, "CYAN / AMBER / RED"],
		[LABEL_W + 668, "FULL COLOUR 24 48 96"], [LABEL_W + 930, "BRIGHT SCENE"]]
	for h in heads:
		_text(canvas, Vector2(h[0], 50), h[1], 13, UiStyle.MUTED)
	var bright_x := LABEL_W + 924.0
	for i in range(rows.size()):
		var name := rows[i]
		var top := 58.0 + i * ROW_H
		var mid := top + ROW_H * 0.5
		var glass := Rect2(Vector2(LABEL_W - 8, top + 4), Vector2(bright_x - LABEL_W + 2, ROW_H - 8))
		canvas.draw_rect(glass, GLASS)
		canvas.draw_rect(Rect2(glass.position, Vector2(glass.size.x, 1)), UiStyle.LINE)
		_text(canvas, Vector2(14, mid + 6), name, 18, UiStyle.TEXT)
		var x := LABEL_W + 6.0
		for px in [18, 24, 32, 48, 96]:
			_icon(canvas, name, Vector2(x + px * 0.5, mid), px, Color.WHITE)
			x += px + 12
		x += 4
		for tint in [UiStyle.ACCENT, UiStyle.AMBER, UiStyle.DANGER]:
			for px in [24, 48]:
				_icon(canvas, name, Vector2(x + px * 0.5, mid), px, tint)
				x += px + 10
			x += 6
		x = LABEL_W + 668.0
		for px in [24, 48, 96]:
			_icon(canvas, name, Vector2(x + px * 0.5, mid), px, Color.WHITE, "color")
			x += px + 14
		var bright := Rect2(Vector2(bright_x, top + 4), Vector2(w - bright_x - 10, ROW_H - 8))
		_bright_rect(canvas, bright)
		x = bright_x + 12
		for tint in [Color.WHITE, UiStyle.ACCENT, UiStyle.AMBER, UiStyle.DANGER]:
			_icon(canvas, name, Vector2(x + 16, mid), 32, tint)
			x += 44
		_icon(canvas, name, Vector2(x + 16, mid), 32, Color.WHITE, "color")
		x += 52
		_icon(canvas, name, Vector2(x + 40, mid), 80, Color.WHITE, "color")


func _overview_height() -> int:
	var rows := int(ceil(_names.size() / 12.0))
	return 70 + rows * 112 + 60 + 2 * 160 + 30


func _draw_overview(canvas: CanvasItem) -> void:
	var size := (canvas as Control).size
	canvas.draw_rect(Rect2(Vector2.ZERO, size), DARK_BG)
	_text(canvas, Vector2(16, 34), "SILHOUETTES: 48 px WHITE  |  FULL COLOUR 48 px  |  18 px", 20, UiStyle.TEXT)
	var cell := Vector2(122, 112)
	for i in range(_names.size()):
		var col := i % 12
		var row := i / 12
		var origin := Vector2(14 + col * cell.x, 56 + row * cell.y)
		canvas.draw_rect(Rect2(origin, cell - Vector2(6, 6)), GLASS)
		_icon(canvas, _names[i], origin + Vector2(30, 36), 48, Color.WHITE)
		_icon(canvas, _names[i], origin + Vector2(84, 36), 48, Color.WHITE, "color")
		_icon(canvas, _names[i], origin + Vector2(84, 80), 18, UiStyle.ACCENT)
		_icon(canvas, _names[i], origin + Vector2(60, 80), 18, Color.WHITE)
		_text(canvas, origin + Vector2(6, 100), _names[i], 13, UiStyle.MUTED)
	var y := 56 + int(ceil(_names.size() / 12.0)) * cell.y + 20
	_text(canvas, Vector2(16, y + 8), "BADGES", 20, UiStyle.TEXT)
	if not _styled:
		return
	var picks := ["face", "mask", "cell", "core", "gun", "shuttle", "pod", "airlock", "medbay", "crown", "trophy", "ghost", "downed", "blackout"]
	var accents := [UiStyle.CREW, UiStyle.INFILTRATOR, UiStyle.AMBER, UiStyle.ACCENT, Color("ff8a4a"), UiStyle.CREW, UiStyle.INFILTRATOR,
		UiStyle.AMBER, UiStyle.GOOD, UiStyle.AMBER, UiStyle.AMBER, UiStyle.GHOST, UiStyle.AMBER, UiStyle.AMBER]
	for i in range(picks.size()):
		var at := Vector2(70 + i * 102, y + 90)
		_api.call("badge", canvas, picks[i], at, 92.0, accents[i], "color", "hex" if i % 2 == 0 else "square")
		_api.call("badge", canvas, picks[i], at + Vector2(-22, 100), 44.0, accents[i], "duo", "hex" if i % 2 == 0 else "square")
		_api.call("badge", canvas, picks[i], at + Vector2(24, 100), 44.0, accents[i], "color", "square" if i % 2 == 0 else "hex")


func _draw_zoom(canvas: CanvasItem, name: String) -> void:
	var size := (canvas as Control).size
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * 0.5, size.y)), DARK_BG)
	_bright_rect(canvas, Rect2(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y)))
	_text(canvas, Vector2(16, 30), name, 22, UiStyle.TEXT)
	var x := 16.0
	for px in [18, 24, 32, 48, 96]:
		_icon(canvas, name, Vector2(x + px * 0.5, 110), px, Color.WHITE)
		_icon(canvas, name, Vector2(x + px * 0.5, 210), px, UiStyle.AMBER)
		x += px + 14
	_icon(canvas, name, Vector2(x + 100, 140), 192, Color.WHITE)
	_icon(canvas, name, Vector2(x + 100, 350), 192, Color.WHITE, "color")
	_icon(canvas, name, Vector2(110, 360), 192, UiStyle.ACCENT)
	x = size.x * 0.5 + 16
	for px in [18, 24, 32, 48, 96]:
		_icon(canvas, name, Vector2(x + px * 0.5, 110), px, UiStyle.ACCENT)
		_icon(canvas, name, Vector2(x + px * 0.5, 210), px, Color.WHITE, "color")
		x += px + 14
	_icon(canvas, name, Vector2(x + 100, 140), 192, UiStyle.DANGER)
	_icon(canvas, name, Vector2(x + 100, 350), 192, Color.WHITE, "color")
	_icon(canvas, name, Vector2(size.x * 0.5 + 110, 360), 192, Color.WHITE)
