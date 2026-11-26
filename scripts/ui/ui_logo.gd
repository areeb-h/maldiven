class_name UiLogo
extends RefCounted
## The DRIFT STATION logo, drawn in code from an original stencil face: heavy
## geometric letters on a 10-unit cap grid (2.2-unit stems, 45° chamfers,
## square counters) with one stencil gap through every letter at 72 % of its
## cap height, like the station's floor lettering.
##
## The lockup sets DRIFT large and STATION small, tracked out to DRIFT's width
## on the same grid. The O of STATION is a crew helmet seen head-on: a domed
## hull, a dark visor and two LED eyes. Its state is the game's premise:
## "crew" shows white eyes, "infiltrator" snaps them to the red V.
##
## Layouts: "lockup" (DRIFT over STATION), "wordmark" (one line, for narrow
## slots), "mark" (the helmet O alone; matches the app icon).
## Palettes: "dark" (on dark backgrounds), "light", "mono".
##
## Static textures are generated from an SVG built here (ThorVG, cached at the
## exact pixel height); the visor and eyes are drawn live so the state can
## flip. assets/ui/logo/*.svg are exports of the same geometry (state crew),
## written by `UiLogo.export_all(dir)` and checked by tests/icons_smoke.gd.

const CAP := 10.0
const STEM := 2.2
const CHAMFER := 1.6
const TRACK := 1.3
const WORD_GAP := 4.4
const LINE_GAP := 2.2
const STATION_SCALE := 0.56
const CUT_AT := 0.72  # stencil gap position, share of the cap height
const CUT_H := 0.55
const PAD := 1.0
const LAYOUTS := ["lockup", "wordmark", "mark"]
const STATES := ["crew", "infiltrator"]
const PALETTES := {
	"dark": ["#e8f1ff", "#5fd4ff"],
	"light": ["#0b1220", "#1679ad"],
	"mono": ["#ffffff", "#ffffff"],
}
const VISOR := Color("04121c")
const EYES := Color("e8f1ff")
const V_RED := Color("ff4d5e")
const FILES := {
	"drift_station_lockup_dark.svg": ["lockup", "dark"],
	"drift_station_lockup_light.svg": ["lockup", "light"],
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


## Inner chamfer for a counter inset by `wall` from an outer chamfer `c`.
static func _inner(c: float, wall := STEM) -> float:
	return maxf(0.0, c - wall * 0.586)


## Glyph table: letter -> {w, shapes: [[outer, holes...], ...]}; rings inside
## one shape are filled even-odd, separate shapes union. "O" is the helmet;
## its visor (counter) is listed in "visor".
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
	# The helmet O: a wider, domed hull with thinner walls around the visor.
	var ow := 9.4
	var wall := 1.9
	var dome := 3.8
	var chin := 2.2
	var top_cut := minf(_inner(dome, wall) + 0.2, (ow - wall * 2.0) * 0.42)
	var visor := _crect(wall, wall + 0.5, ow - wall, CAP - wall, top_cut, top_cut, _inner(chin, wall), _inner(chin, wall))
	g["O"] = {"w": ow, "shapes": [[_crect(0, 0, ow, CAP, dome, dome, chin, chin), visor]], "visor": visor}
	g["N"] = {"w": w, "shapes": [[_crect(0, 0, s, CAP)], [_crect(w - s, 0, w, CAP)],
		[PackedVector2Array([Vector2(0, 0), Vector2(2.5, 0), Vector2(w, CAP), Vector2(w - 2.5, CAP)])]]}
	_glyphs = g
	return g


static func _advance(word: String, track: float) -> float:
	var table := glyphs()
	var width := 0.0
	for ch in word:
		width += float(table[ch].w)
	return width + track * float(word.length() - 1)


## Lines of the layout: [[word, origin, scale, tracking, color_index], ...].
static func _lines(layout: String) -> Array:
	match layout:
		"mark":
			return [["O", Vector2.ZERO, 1.0, 0.0, 1]]
		"wordmark":
			return [["DRIFT", Vector2.ZERO, 1.0, TRACK, 0],
				["STATION", Vector2(_advance("DRIFT", TRACK) + WORD_GAP, 0), 1.0, TRACK, 1]]
	# Lockup: STATION small, tracked out to DRIFT's width, on the same grid.
	var top := _advance("DRIFT", TRACK)
	var glyph_width := _advance("STATION", 0.0) * STATION_SCALE
	var track := (top - glyph_width) / 6.0
	return [["DRIFT", Vector2.ZERO, 1.0, TRACK, 0],
		["STATION", Vector2(0, CAP + LINE_GAP), STATION_SCALE, track, 1]]


## Placed letters: [{shapes (placed rings), color, cut_y, cut_h, visor?}].
static func _placed(layout: String) -> Array:
	var key := "placed:" + layout
	if _cache.has(key):
		return _cache[key]
	var out := []
	var table := glyphs()
	for line in _lines(layout):
		var word: String = line[0]
		var origin: Vector2 = line[1]
		var k: float = line[2]
		var x := origin.x
		for ch in word:
			var glyph: Dictionary = table[ch]
			var shapes := []
			for shape in glyph.shapes:
				var rings := []
				for ring in shape:
					var placed := PackedVector2Array()
					for p in (ring as PackedVector2Array):
						placed.append(Vector2(x, origin.y) + p * k)
					rings.append(placed)
				shapes.append(rings)
			var entry := {"shapes": shapes, "color": line[4], "cut_y": origin.y + CAP * k * CUT_AT, "cut_h": CUT_H * maxf(k, 0.7)}
			if glyph.has("visor"):
				var visor := PackedVector2Array()
				for p in (glyph.visor as PackedVector2Array):
					visor.append(Vector2(x, origin.y) + p * k)
				entry["visor"] = visor
			out.append(entry)
			x += float(glyph.w) * k + float(line[3])
	_cache[key] = out
	return out


## Cut every letter at its stencil gap: [{rings, color, part: "top"|"bottom"}].
static func _cut(layout: String) -> Array:
	var key := "cut:" + layout
	if _cache.has(key):
		return _cache[key]
	var out := []
	for letter in _placed(layout):
		var cut: float = letter.cut_y
		for shape in letter.shapes:
			for part in ["top", "bottom"]:
				var band := _crect(-1000, -1000, 1000, cut) if part == "top" else _crect(-1000, cut + float(letter.cut_h), 1000, 1000)
				var rings := []
				for ring in shape:
					for clipped in Geometry2D.intersect_polygons(ring, band):
						rings.append(clipped)
				if not rings.is_empty():
					out.append({"rings": rings, "color": letter.color, "part": part})
	_cache[key] = out
	return out


## Bounds of the layout in units (padding included).
static func bounds(layout: String) -> Rect2:
	var key := "bounds:" + layout
	if _cache.has(key):
		return _cache[key]
	var box := Rect2()
	var first := true
	for letter in _placed(layout):
		for shape in letter.shapes:
			for ring in shape:
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


## The visor polygon (layout units, relative to the bounds' top-left).
static func visor(layout: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var origin := bounds(layout).position
	for letter in _placed(layout):
		if letter.has("visor"):
			for p in letter.visor:
				out.append(p - origin)
	return out


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


## The logo as an SVG document. part: "all", "top" or "bottom" (the stencil
## halves, for the slide animation). `with_face` adds the visor and the eyes
## for `state` (exports); live drawing adds them itself.
static func svg(layout := "lockup", palette := "dark", part := "all", with_face := false, state := "crew") -> String:
	var box := bounds(layout)
	var colors: Array = PALETTES.get(palette, PALETTES.dark)
	var body := ""
	for entry in _cut(layout):
		if part != "all" and entry.part != part:
			continue
		body += "<path fill='%s' fill-rule='evenodd' d='%s'/>" % [colors[entry.color], _path(entry.rings, box.position)]
	if with_face:
		var face := visor(layout)
		if not face.is_empty():
			body += "<path fill='#%s' d='%s'/>" % [VISOR.to_html(false), _path([face], Vector2.ZERO)]
			for poly in face_shapes(face)[0 if state == "crew" else 1]:
				body += "<path fill='#%s' d='%s'/>" % [(EYES if state == "crew" else V_RED).to_html(false), _path([poly], Vector2.ZERO)]
	return ("<svg xmlns='http://www.w3.org/2000/svg' width='%.3f' height='%.3f' viewBox='0 0 %.3f %.3f'>" %
		[box.size.x, box.size.y, box.size.x, box.size.y]) + "<title>Drift Station</title>" + body + "</svg>"


## Eye shapes inside a visor polygon: [crew eyes, infiltrator V], each an
## Array of polygons in the visor's space.
static func face_shapes(face: PackedVector2Array) -> Array:
	var box := Rect2(face[0], Vector2.ZERO)
	for p in face:
		box = box.expand(p)
	var w := box.size.x
	var h := box.size.y
	var c := box.get_center() + Vector2(0, h * 0.04)
	var eye := Vector2(w * 0.15, h * 0.4)
	var eyes := []
	for side in [-1.0, 1.0]:
		var at: Vector2 = c + Vector2(side * w * 0.21, 0)
		eyes.append(_crect(at.x - eye.x * 0.5, at.y - eye.y * 0.5, at.x + eye.x * 0.5, at.y + eye.y * 0.5,
			eye.x * 0.3, eye.x * 0.3, eye.x * 0.3, eye.x * 0.3))
	# The V: two slashes meeting low in the middle (the infiltrator's visor).
	var v := []
	var t := h * 0.17
	var top_y := c.y - h * 0.24
	var low_y := c.y + h * 0.2
	for side in [-1.0, 1.0]:
		var outer := Vector2(c.x + side * w * 0.4, top_y)
		var inner := Vector2(c.x, low_y)
		v.append(PackedVector2Array([outer, inner, inner + Vector2(0, t), outer + Vector2(0, t)]))
	return [eyes, v]


## Rasterised logo `px` tall (cached). part: "all", "top", "bottom".
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
## state_blend: 0 = crew eyes, 1 = infiltrator V (in between it glitches).
## reveal: 0..1 left-to-right wipe with a scan bar on the edge.
## slide: offset of the stencil halves (cap heights; 0 = locked together).
static func draw(canvas: CanvasItem, layout: String, pos: Vector2, height: float, palette := "dark",
		alpha := 1.0, reveal := 1.0, slide := 0.0, state_blend := 0.0, time := 0.0) -> Vector2:
	var px := int(ceil(height))
	var top := texture(layout, px, palette, "top")
	var bottom := texture(layout, px, palette, "bottom")
	if top == null or bottom == null:
		return Vector2.ZERO
	var size := Vector2(height * aspect(layout), height)
	var units := height / bounds(layout).size.y
	var k := clampf(reveal, 0.0, 1.0)
	if k <= 0.0:
		return size
	var tint := Color(1, 1, 1, alpha)
	var tex_size := Vector2(top.get_width(), top.get_height())
	var src := Rect2(Vector2.ZERO, Vector2(tex_size.x * k, tex_size.y))
	var dst := Rect2(pos, Vector2(size.x * k, size.y))
	var shift := Vector2(slide * CAP * units, 0)
	# Visor first, so the hull's anti-aliased edge sits on top of it.
	var face := visor(layout)
	if not face.is_empty():
		var placed := PackedVector2Array()
		for p in face:
			placed.append(pos + p * units)
		if placed[0].x < pos.x + size.x * k:
			canvas.draw_colored_polygon(placed, Color(VISOR.r, VISOR.g, VISOR.b, 0.96 * alpha))
			_draw_eyes(canvas, placed, state_blend, alpha, time)
	canvas.draw_texture_rect_region(top, Rect2(dst.position + shift, dst.size), src, tint)
	canvas.draw_texture_rect_region(bottom, Rect2(dst.position - shift, dst.size), src, tint)
	if k < 1.0:
		var x := pos.x + size.x * k
		var accent := Color(PALETTES.dark[1]) if palette != "light" else Color(PALETTES.light[1])
		canvas.draw_rect(Rect2(x - 1.5, pos.y - height * 0.08, 3.0, height * 1.16), Color(accent.r, accent.g, accent.b, 0.9 * alpha))
		canvas.draw_rect(Rect2(x - 10.0, pos.y - height * 0.08, 10.0, height * 1.16), Color(accent.r, accent.g, accent.b, 0.18 * alpha))
	return size


static func _draw_eyes(canvas: CanvasItem, face: PackedVector2Array, blend: float, alpha: float, time: float) -> void:
	var shapes := face_shapes(face)
	var b := clampf(blend, 0.0, 1.0)
	# The flip is a snap with two glitch frames, not a dissolve.
	var glitch := b > 0.0 and b < 1.0
	var jolt := Vector2.ZERO
	if glitch:
		var box_w := 0.0
		for p in face:
			box_w = maxf(box_w, p.x - face[0].x)
		jolt = Vector2((UiType.hash01(9, int(time * 60.0)) - 0.5) * box_w * 0.18, 0)
	var show_v := b >= 0.5
	var polys: Array = shapes[1] if show_v else shapes[0]
	var color := V_RED if show_v else EYES
	for poly in polys:
		var moved := PackedVector2Array()
		var grown := PackedVector2Array()
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= float(poly.size())
		for p in poly:
			moved.append(p + jolt)
			grown.append(center + (p - center) * 1.5 + jolt)
		canvas.draw_colored_polygon(grown, Color(color.r, color.g, color.b, 0.22 * alpha))
		canvas.draw_colored_polygon(moved, Color(color.r, color.g, color.b, alpha))


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
		file.store_string(svg(spec[0], spec[1], "all", true, "crew") + "\n")
		file.close()
		written += 1
	return written


## A Control that shows the logo fitted to its size (keeps the aspect, aligns
## left or centre). `set_state("infiltrator")` flips the visor; animate
## `reveal` and `slide` for an intro, or call `play_intro()`.
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
	var state_blend := 0.0:
		set(value):
			state_blend = value
			set_process(value > 0.0 and value < 1.0)
			queue_redraw()
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		set_process(false)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	## "crew" or "infiltrator"; blend 0..1 for in-between (glitch) frames.
	func set_state(state_name: String, blend := 1.0) -> void:
		state_blend = clampf(blend, 0.0, 1.0) if state_name == "infiltrator" else 1.0 - clampf(blend, 0.0, 1.0)

	func _get_minimum_size() -> Vector2:
		return Vector2(logo_height * UiLogo.aspect(layout), logo_height)

	func _draw() -> void:
		var h := minf(logo_height, size.y)
		var w := h * UiLogo.aspect(layout)
		if w > size.x and size.x > 0.0:
			w = size.x
			h = w / UiLogo.aspect(layout)
		var x := (size.x - w) * 0.5 if center else 0.0
		UiLogo.draw(self, layout, Vector2(x, (size.y - h) * 0.5), h, palette, 1.0, reveal, slide, state_blend, _time)

	## Intro: the stencil halves slide together as the logo wipes in.
	func play_intro(delay := 0.0) -> Tween:
		reveal = 0.0
		slide = 0.6
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(self, "reveal", 1.0, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "slide", 0.0, 0.9).set_delay(0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		return tween
