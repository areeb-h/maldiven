extends SceneTree
## Fast headless icon preview: composes rasterised icons straight into an Image
## (no renderer), so it runs with --headless while iterating on glyphs.
##
##   godot --headless --path . --script res://tools/icons/preview.gd -- \
##     --out=/abs/file.png [--names=cell,core] [--zoom=2]
##
## Each row: duo white at 18 24 32 48 96 and amber/red at 24 | colour 24 48 96 on
## dark glass | duo cyan 32 and colour 32 48 on a bright floor. `--zoom` scales
## the sheet up with nearest filtering to inspect the pixel-exact small sizes.

const DARK := Color("0a1220")
const BRIGHT := Color("d5dde7")


func _initialize() -> void:
	var out := "user://icons_preview.png"
	var names := UiIcons.names()
	var zoom := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--names="):
			names = arg.substr(8).split(",", false)
		elif arg.begins_with("--zoom="):
			zoom = int(arg.substr(7))
	var row_h := 104
	var sheet := Image.create(1180, row_h * names.size() + 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("050810"))
	for i in range(names.size()):
		var top := 4 + i * row_h
		sheet.fill_rect(Rect2i(4, top, 830, row_h - 4), DARK)
		sheet.fill_rect(Rect2i(838, top, 338, row_h - 4), BRIGHT)
		sheet.fill_rect(Rect2i(838, top + 60, 338, row_h - 64), BRIGHT.darkened(0.12))
		var mid := top + (row_h - 4) / 2
		var x := 12
		for px in [18, 24, 32, 48, 96]:
			_put(sheet, names[i], "duo", px, "#ffffff", x, mid)
			x += px + 12
		for ink in ["#ffe14d", "#ff4d5e", "#4d8dff"]:
			_put(sheet, names[i], "duo", 24, ink, x, mid)
			x += 34
		x += 14
		for px in [24, 48, 96]:
			_put(sheet, names[i], "color", px, "#ffffff", x, mid)
			x += px + 14
		x = 848
		_put(sheet, names[i], "duo", 32, "#5fd4ff", x, mid)
		x += 44
		_put(sheet, names[i], "duo", 32, "#ffffff", x, mid)
		x += 44
		_put(sheet, names[i], "duo", 48, "#ff4d5e", x, mid)
		x += 60
		_put(sheet, names[i], "color", 32, "#ffffff", x, mid)
		x += 44
		_put(sheet, names[i], "color", 80, "#ffffff", x, mid)
	if zoom > 1:
		sheet.resize(sheet.get_width() * zoom, sheet.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("preview: ", ProjectSettings.globalize_path(out))
	quit(0)


func _put(sheet: Image, name: String, style: String, px: int, ink: String, x: int, mid: int) -> void:
	var small := px <= UiIcons.SMALL_PX
	var parts: Dictionary = UiIcons._compose(UiIcons.GLYPHS[name], style, small, ink, "", UiIcons._spread(px))
	var img: Image = UiIcons._image(UiIcons._doc(px, parts.defs, parts.body), parts.shadow, px, 0.0)
	sheet.blend_rect(img, Rect2i(0, 0, px, px), Vector2i(x, mid - px / 2))
