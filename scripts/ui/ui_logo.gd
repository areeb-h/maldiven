class_name UiLogo
extends RefCounted
## The DRIFT STATION logo. Original geometric letterforms drawn on a 10-unit
## cap grid: heavy 2.2-unit stems, 45° chamfered corners, square counters.
## The signature is the drift line: one thin horizontal slice through every
## letter at 70 % of the cap height, with everything below it slid left, as
## if the station had been knocked off its orbit. The emblem (a chamfered
## octagon hull around a diamond core) carries the same cut, aligned with
## STATION's, so the lockup reads as one object.
##
## One source of truth: the SVG is generated here. assets/ui/logo/*.svg are
## exports of it for the splash, store art and the trailer (re-export with
## `UiLogo.export_all(dir)`; tests/icons_smoke.gd checks the files match).
## Rasterised with ThorVG (Image.load_svg_from_string) at any size and cached.
##
## Layouts: "wordmark" (one line), "stacked" (DRIFT / STATION), "lockup"
## (emblem + stacked), "mark" (emblem only).
## Palettes: "dark" (for dark backgrounds), "light" (for light backgrounds),
## "mono" (white, tint it with modulate/colour).

const CAP := 10.0
const STEM := 2.2
const CHAMFER := 1.6
const TRACK := 1.3
const WORD_GAP := 4.4
const LINE_GAP := 2.6
const CUT_Y := 7.0  # top of the drift slice, from the cap top
const CUT_H := 0.6
const DRIFT := 0.7  # how far the lower slice sits to the left
const PAD := 1.0
const LAYOUTS := ["wordmark", "stacked", "lockup", "mark"]
const PALETTES := {
	"dark": ["#e8f1ff", "#5fd4ff"],
	"light": ["#0b1220", "#1679ad"],
	"mono": ["#ffffff", "#ffffff"],
}
const FILES := {
	"drift_station_lockup_dark.svg": ["lockup", "dark"],
	"drift_station_lockup_light.svg": ["lockup", "light"],
	"drift_station_stacked_dark.svg": ["stacked", "dark"],
	"drift_station_stacked_light.svg": ["stacked", "light"],
	"drift_station_wordmark_dark.svg": ["wordmark", "dark"],
	"drift_station_wordmark_light.svg": ["wordmark", "light"],
	"drift_station_mark.svg": ["mark", "dark"],
	"drift_station_mark_mono.svg": ["mark", "mono"],
}

static var _cache := {}
static var _glyphs := {}


## Chamfered rectangle (corner cuts tl, tr, br, bl in units).
static func _crect(x0: float, y0: float, x1: float, y1: float, tl := 0.0, tr := 0.0, br := 0.0, bl := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(x0, y0 + tl))
	if tl > 0.0:
		out.append(Vector2(x0 + tl, y0))
	out.append(Vector2(x1 - tr, y0))
	if tr > 0.0:
		out.append(Vector2(x1, y0 + tr))
	out.append(Vector2(x1, y1 - br))
	if br > 0.0:
		out.append(Vector2(x1 - br, y1))
	out.append(Vector2(x0 + bl, y1))
	if bl > 0.0:
		out.append(Vector2(x0, y1 - bl))
	return out


## Inner chamfer for a counter inset by STEM from an outer chamfer `c`.
static func _inner(c: float) -> float:
	return maxf(0.0, c - STEM * 0.586)


## Glyph table: letter -> {w: advance width, shapes: [[outer, hole...], ...]}.
## Shapes in one entry are filled even-odd (outer minus holes); separate
## entries union.
static func glyphs() -> Dictionary:
	if not _glyphs.is_empty():
		return _glyphs
	var s := STEM
	var w := 7.2
	var c := CHAMFER
	var big := 2.6
	var g := {}
	g["D"] = {"w": w, "shapes": [[_crect(0, 0, w, CAP, 0, big, big, 0), _crect(s, s, w - s, CAP - s, 0, _inner(big), _inner(big), 0)]]}
	g["R"] = {"w": w, "shapes": [
		[_crect(0, 0, w, 6.4, 0, 2.0, 0, 0), _crect(s, s, w - s, 6.4 - s, 0, _inner(2.0), 0, 0)],
		[_crect(0, 0, s, CAP)],
		[PackedVector2Array([Vector2(2.9, 6.0), Vector2(5.3, 6.0), Vector2(w, CAP), Vector2(w - 2.4, CAP)])],
	]}
	g["I"] = {"w": s, "shapes": [[_crect(0, 0, s, CAP)]]}
	var fw := 6.6
	g["F"] = {"w": fw, "shapes": [[PackedVector2Array([Vector2(0, c), Vector2(c, 0), Vector2(fw, 0), Vector2(fw, s),
		Vector2(s, s), Vector2(s, 4.1), Vector2(5.4, 4.1), Vector2(5.4, 4.1 + s), Vector2(s, 4.1 + s), Vector2(s, CAP),
		Vector2(0, CAP)])]]}
	var tw := 7.6
	var th := tw * 0.5
	g["T"] = {"w": tw, "shapes": [[PackedVector2Array([Vector2(0, 0), Vector2(tw, 0), Vector2(tw, s), Vector2(th + s * 0.5, s),
		Vector2(th + s * 0.5, CAP), Vector2(th - s * 0.5, CAP), Vector2(th - s * 0.5, s), Vector2(0, s)])]]}
	var m0 := 3.9
	var m1 := m0 + s
	g["S"] = {"w": w, "shapes": [[PackedVector2Array([Vector2(0, c), Vector2(c, 0), Vector2(w, 0), Vector2(w, s), Vector2(s, s),
		Vector2(s, m0), Vector2(w - c, m0), Vector2(w, m0 + c), Vector2(w, CAP - c), Vector2(w - c, CAP), Vector2(0, CAP),
		Vector2(0, CAP - s), Vector2(w - s, CAP - s), Vector2(w - s, m1), Vector2(c, m1), Vector2(0, m1 - c)])]]}
	var bar := 6.6
	g["A"] = {"w": w, "shapes": [[PackedVector2Array([Vector2(0, CAP), Vector2(0, big), Vector2(big, 0), Vector2(w - big, 0),
		Vector2(w, big), Vector2(w, CAP), Vector2(w - s, CAP), Vector2(w - s, bar), Vector2(s, bar), Vector2(s, CAP)]),
		_crect(s, s, w - s, bar - s, _inner(big), _inner(big), 0, 0)]]}
	g["O"] = {"w": w, "shapes": [[_crect(0, 0, w, CAP, big, big, big, big),
		_crect(s, s, w - s, CAP - s, _inner(big), _inner(big), _inner(big), _inner(big))]]}
	g["N"] = {"w": w, "shapes": [[_crect(0, 0, s, CAP)], [_crect(w - s, 0, w, CAP)],
		[PackedVector2Array([Vector2(0, 0), Vector2(2.5, 0), Vector2(w, CAP), Vector2(w - 2.5, CAP)])]]}
	_glyphs = g
	return g


## The emblem in a square of side `side` (units): chamfered octagon hull with
## a diamond core. Returns shapes like glyphs().
static func _mark_shapes(side: float) -> Array:
	var k := side / 24.0
	var hull_c := 7.0 * k
	var wall := STEM * 1.05
	var outer := _crect(0, 0, side, side, hull_c, hull_c, hull_c, hull_c)
	var inner := _crect(wall, wall, side - wall, side - wall, _inner(hull_c), _inner(hull_c), _inner(hull_c), _inner(hull_c))
	var mid := side * 0.5
	var r := 4.6 * k
	var core := PackedVector2Array([Vector2(mid, mid - r), Vector2(mid + r, mid), Vector2(mid, mid + r), Vector2(mid - r, mid)])
	return [[outer, inner], [core]]


## Pieces of the layout before the cut: [{shapes, color_index, offset: Vector2, cut_y}].
static func _pieces(layout: String) -> Array:
	var out := []
	var mark_side := CAP * 2.0 + LINE_GAP
	var text_x := 0.0
	if layout == "mark" or layout == "lockup":
		var shapes := _mark_shapes(mark_side)
		# The emblem's cut lines up with STATION's (second line) in the lockup.
		out.append({"shapes": [shapes[0]], "color": 0, "offset": Vector2.ZERO, "cut": CAP + LINE_GAP + CUT_Y})
		out.append({"shapes": [shapes[1]], "color": 1, "offset": Vector2.ZERO, "cut": CAP + LINE_GAP + CUT_Y})
		text_x = mark_side + 4.4
	if layout == "mark":
		return out
	var lines := []
	if layout == "wordmark":
		lines = [["DRIFT STATION", Vector2(text_x, 0)]]
	else:
		lines = [["DRIFT", Vector2(text_x, 0)], ["STATION", Vector2(text_x, CAP + LINE_GAP)]]
	var table := glyphs()
	for line in lines:
		var x: float = line[1].x
		var y: float = line[1].y
		var word_index := 0
		for ch in str(line[0]):
			if ch == " ":
				x += WORD_GAP - TRACK
				word_index += 1
				continue
			var glyph: Dictionary = table[ch]
			# DRIFT in the primary colour, STATION in the accent.
			var color_index := 1 if (str(line[0]) == "STATION" or word_index == 1) else 0
			out.append({"shapes": glyph.shapes, "color": color_index, "offset": Vector2(x, y), "cut": y + CUT_Y})
			x += float(glyph.w) + TRACK
	return out


## Cut every piece at its drift line: returns [{polys: [[outer, holes...]], color, part}]
## where part is "top" or "bottom" (bottom already slid left by DRIFT).
static func _cut(layout: String) -> Array:
	var out := []
	for piece in _pieces(layout):
		var cut: float = piece.cut
		var offset: Vector2 = piece.offset
		for shape in piece.shapes:
			for part in ["top", "bottom"]:
				var band := _crect(-1000, -1000, 1000, cut) if part == "top" else _crect(-1000, cut + CUT_H, 1000, 1000)
				var shift := Vector2.ZERO if part == "top" else Vector2(-DRIFT, 0)
				var rings := []
				for ring_index in range((shape as Array).size()):
					var poly := PackedVector2Array()
					for p in (shape[ring_index] as PackedVector2Array):
						poly.append(p + offset)
					for clipped in Geometry2D.intersect_polygons(poly, band):
						var moved := PackedVector2Array()
						for p in clipped:
							moved.append(p + shift)
						rings.append(moved)
				if not rings.is_empty():
					out.append({"rings": rings, "color": piece.color, "part": part})
	return out


## Bounds of the layout in units (padding included).
static func bounds(layout: String) -> Rect2:
	var key := "bounds:" + layout
	if _cache.has(key):
		return _cache[key]
	var box := Rect2()
	var first := true
	for entry in _cut(layout):
		for ring in entry.rings:
			for p in ring:
				if first:
					box = Rect2(p, Vector2.ZERO)
					first = false
				else:
					box = box.expand(p)
	box = box.grow(PAD)
	_cache[key] = box
	return box


static func aspect(layout: String) -> float:
	var box := bounds(layout)
	return box.size.x / box.size.y


static func _path(rings: Array, origin: Vector2) -> String:
	var d := ""
	for ring in rings:
		var first := true
		for p in ring:
			var q: Vector2 = p - origin
			d += ("M" if first else "L") + "%.3f %.3f " % [q.x, q.y]
			first = false
		d += "Z "
	return d.strip_edges()


## The logo as an SVG document. part: "all", "top" or "bottom" (for the drift
## animation: both parts share the same canvas).
static func svg(layout := "lockup", palette := "dark", part := "all") -> String:
	var box := bounds(layout)
	var colors: Array = PALETTES.get(palette, PALETTES.dark)
	var body := ""
	for entry in _cut(layout):
		if part != "all" and entry.part != part:
			continue
		body += "<path fill='%s' fill-rule='evenodd' d='%s'/>" % [colors[entry.color], _path(entry.rings, box.position)]
	return ("<svg xmlns='http://www.w3.org/2000/svg' width='%.3f' height='%.3f' viewBox='0 0 %.3f %.3f'>" %
		[box.size.x, box.size.y, box.size.x, box.size.y]) + "<title>Drift Station</title>" + body + "</svg>"


## Rasterised logo `px` tall (cached).
static func texture(layout := "lockup", px := 128, palette := "dark", part := "all") -> Texture2D:
	px = clampi(px, 8, 4096)
	var key := "%s|%d|%s|%s" % [layout, px, palette, part]
	if _cache.has(key):
		return _cache[key]
	var image := Image.new()
	var scale := float(px) / bounds(layout).size.y
	if image.load_svg_from_string(svg(layout, palette, part), scale) != OK:
		return null
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	if _cache.size() > 160:
		_cache.clear()
	_cache[key] = tex
	return tex


## Draw the logo with its top-left at `pos`, `height` px tall.
## reveal: 0..1 left-to-right wipe with a scan bar on the edge.
## slide: extra drift of the lower slice (in cap heights; animates to 0).
static func draw(canvas: CanvasItem, layout: String, pos: Vector2, height: float, palette := "dark",
		alpha := 1.0, reveal := 1.0, slide := 0.0, modulate := Color.WHITE) -> Vector2:
	var px := int(ceil(height))
	var top := texture(layout, px, palette, "top")
	var bottom := texture(layout, px, palette, "bottom")
	if top == null or bottom == null:
		return Vector2.ZERO
	var size := Vector2(height * aspect(layout), height)
	var tint := Color(modulate.r, modulate.g, modulate.b, modulate.a * alpha)
	var units := height / bounds(layout).size.y
	var k := clampf(reveal, 0.0, 1.0)
	if k <= 0.0:
		return size
	var tex_size := Vector2(top.get_width(), top.get_height())
	var src := Rect2(Vector2.ZERO, Vector2(tex_size.x * k, tex_size.y))
	var dst := Rect2(pos, Vector2(size.x * k, size.y))
	canvas.draw_texture_rect_region(top, dst, src, tint)
	var shove := Vector2(-slide * CAP * units, 0)
	canvas.draw_texture_rect_region(bottom, Rect2(dst.position + shove, dst.size), src, tint)
	if k < 1.0:
		var x := pos.x + size.x * k
		var accent := Color(PALETTES.dark[1]) if palette != "light" else Color(PALETTES.light[1])
		canvas.draw_rect(Rect2(x - 1.5, pos.y - height * 0.08, 3.0, height * 1.16), Color(accent.r, accent.g, accent.b, 0.9 * alpha))
		canvas.draw_rect(Rect2(x - 10.0, pos.y - height * 0.08, 10.0, height * 1.16), Color(accent.r, accent.g, accent.b, 0.18 * alpha))
	return size


## Write every logo file to `dir` (e.g. "res://assets/ui/logo"). Returns the
## number of files written.
static func export_all(dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	var written := 0
	for file_name in FILES:
		var spec: Array = FILES[file_name]
		var file := FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
		if file == null:
			continue
		file.store_string(svg(spec[0], spec[1]) + "\n")
		file.close()
		written += 1
	return written


## A Control that shows the logo fitted to its size (keeps aspect, aligns
## left or centre). Animate `reveal` and `slide` for the intro.
class View extends Control:
	var layout := "lockup":
		set(value):
			layout = value
			update_minimum_size()
			queue_redraw()
	var palette := "dark":
		set(value):
			palette = value
			queue_redraw()
	var logo_height := 96.0:
		set(value):
			logo_height = value
			update_minimum_size()
			queue_redraw()
	var center := false
	var reveal := 1.0:
		set(value):
			reveal = value
			queue_redraw()
	var slide := 0.0:
		set(value):
			slide = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _get_minimum_size() -> Vector2:
		return Vector2(logo_height * UiLogo.aspect(layout), logo_height)

	func _draw() -> void:
		var h := minf(logo_height, size.y)
		var w := h * UiLogo.aspect(layout)
		if w > size.x and size.x > 0.0:
			w = size.x
			h = w / UiLogo.aspect(layout)
		var x := (size.x - w) * 0.5 if center else 0.0
		UiLogo.draw(self, layout, Vector2(x, (size.y - h) * 0.5), h, palette, 1.0, reveal, slide)

	## Intro: wipe in with the scan bar, then the lower slice drifts home.
	func play_intro(delay := 0.0) -> Tween:
		reveal = 0.0
		slide = 1.2
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(self, "reveal", 1.0, 0.7).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "slide", 0.0, 1.1).set_delay(0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		return tween
