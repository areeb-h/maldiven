class_name UiType
extends RefCounted
## Typographic motion for hero moments: the same letter-build, type-on and
## tracking rules drive the role reveal, the result unmasking, the countdowns
## and the trailer's title cards (TitleCard), so the trailer shows the game's
## own type. Every helper is a pure function of a time `t` (seconds since the
## element started), so a frame renderer can seek to any moment.
##
## Draw helpers take a CanvasItem and draw immediately (call them from _draw).

## Glyphs a scrambled letter cycles through before it locks.
const SCRAMBLE := "ABCDEFHKLMNPRSTVXZ0123456789#/<>"


static func ease_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


static func ease_in_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


static func ease_back(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)


## Width of `text` set with extra `tracking` px between letters.
static func tracked_width(font: Font, text: String, size: int, tracking := 0.0) -> float:
	if text.is_empty():
		return 0.0
	var width := 0.0
	for i in range(text.length()):
		width += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return width + tracking * float(text.length() - 1)


## Largest font size <= `size` at which `text` fits in `max_width`.
static func fit_size(font: Font, text: String, size: int, max_width: float, tracking := 0.0) -> int:
	var width := tracked_width(font, text, size, tracking)
	if width <= max_width or width <= 0.0:
		return size
	return maxi(8, int(floor(float(size) * max_width / width)))


## A deterministic pseudo-random 0..1 for (seed, a, b).
static func hash01(seed: int, a: int, b := 0) -> float:
	var h := (seed * 73856093) ^ (a * 19349663) ^ (b * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Letter build: each letter drops in (fade, slight rise, scale), tracking
## collapses from wide to final, and (optionally) letters decode through
## random glyphs before locking. `origin` is the baseline point; `align`
## "left" | "center" | "right" places the final word around it.
## opts: tracking (px), spread (extra px of tracking at t=0), stagger (s per
## letter), dur (s per letter), scramble (bool), outline (px), outline_color,
## glow (Color, drawn as a soft wide outline), seed (int), rise (share of size),
## total (s: if set, stagger is chosen so the build always takes this long,
## whatever the word length), alpha (0..1).
static func draw_build(canvas: CanvasItem, font: Font, text: String, origin: Vector2, size: int, color: Color,
		t: float, opts := {}) -> float:
	var n := text.length()
	if n == 0:
		return 0.0
	var tracking: float = opts.get("tracking", 0.0)
	var spread: float = opts.get("spread", size * 0.35)
	var dur: float = opts.get("dur", 0.32)
	var stagger: float = opts.get("stagger", 0.05)
	if opts.has("total"):
		stagger = maxf(0.0, (float(opts.total) - dur) / maxf(1.0, float(n - 1)))
	var whole := ease_out(t / maxf(0.001, stagger * float(n - 1) + dur))
	var track := tracking + spread * (1.0 - whole)
	var width := tracked_width(font, text, size, track)
	var x := origin.x
	match str(opts.get("align", "left")):
		"center":
			x -= width * 0.5
		"right":
			x -= width
	var alpha_all: float = opts.get("alpha", 1.0)
	var scramble: bool = opts.get("scramble", false)
	var seed: int = opts.get("seed", 7)
	var rise: float = opts.get("rise", 0.22)
	var outline: int = opts.get("outline", 0)
	var outline_color: Color = opts.get("outline_color", Color(0, 0, 0, 0.6))
	var glow: Color = opts.get("glow", Color(0, 0, 0, 0))
	for i in range(n):
		var ch := text[i]
		var advance := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var local := (t - float(i) * stagger) / dur
		if local > 0.0 and ch != " ":
			var e := ease_out(local)
			var shown := ch
			if scramble and local < 0.7:
				var tick := int(floor(t * 24.0))
				shown = SCRAMBLE[int(hash01(seed, i, tick) * (SCRAMBLE.length() - 1))]
			var shown_width := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var at := Vector2(x + (advance - shown_width) * 0.5, origin.y + (1.0 - e) * size * rise)
			var a := e * alpha_all
			var tint := color
			if scramble and local < 0.7:
				tint = color.lightened(0.45)
				a *= 0.75
			if glow.a > 0.0:
				canvas.draw_string_outline(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(4, int(size * 0.28)),
					Color(glow.r, glow.g, glow.b, glow.a * a))
			if outline > 0:
				canvas.draw_string_outline(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline,
					Color(outline_color.r, outline_color.g, outline_color.b, outline_color.a * a))
			canvas.draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(tint.r, tint.g, tint.b, tint.a * a))
		x += advance + track
	return width


## Type-on: characters appear at `cps` per second behind a block caret that
## blinks once the line is complete (and disappears after `caret_hold` s).
## Returns the drawn width.
static func draw_type_on(canvas: CanvasItem, font: Font, text: String, origin: Vector2, size: int, color: Color,
		t: float, cps := 32.0, align := "left", tracking := 0.0, caret_hold := 0.8) -> float:
	if t <= 0.0 or text.is_empty():
		return 0.0
	var count := clampi(int(floor(t * cps)), 0, text.length())
	var full := tracked_width(font, text, size, tracking)
	var x := origin.x
	match align:
		"center":
			x -= full * 0.5
		"right":
			x -= full
	var shown := text.substr(0, count)
	var width := tracked_width(font, shown, size, tracking)
	var cx := x
	for i in range(shown.length()):
		canvas.draw_string(font, Vector2(cx, origin.y), shown[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		cx += font.get_string_size(shown[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + tracking
	var done_at := float(text.length()) / cps
	var blink := count < text.length() or (t - done_at < caret_hold and fmod(t - done_at, 0.36) < 0.2)
	if blink:
		var caret := Rect2(x + width + (tracking if count > 0 else 0.0), origin.y - size * 0.78, size * 0.5, size * 0.86)
		canvas.draw_rect(caret, Color(color.r, color.g, color.b, color.a * 0.85))
	return full


## A rule that draws outward from its centre, with small end ticks.
static func draw_rule(canvas: CanvasItem, center: Vector2, width: float, color: Color, t: float, thickness := 2.0) -> void:
	var k := ease_out(t)
	if k <= 0.0:
		return
	var half := width * 0.5 * k
	canvas.draw_rect(Rect2(center.x - half, center.y - thickness * 0.5, half * 2.0, thickness), color)
	var tick := Color(color.r, color.g, color.b, color.a * k)
	for side in [-1.0, 1.0]:
		var x: float = center.x + side * half
		canvas.draw_rect(Rect2(x - 1.0, center.y - thickness * 3.0, 2.0, thickness * 6.0), tick)


## Corner brackets around a rect (viewfinder framing for hero cards).
static func draw_brackets(canvas: CanvasItem, rect: Rect2, length: float, color: Color, thickness := 2.0) -> void:
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var left: bool = corner.x <= rect.get_center().x
		var top: bool = corner.y <= rect.get_center().y
		canvas.draw_rect(Rect2(corner.x if left else corner.x - length, corner.y if top else corner.y - thickness,
			length, thickness), color)
		canvas.draw_rect(Rect2(corner.x if left else corner.x - thickness, corner.y if top else corner.y - length,
			thickness, length), color)


## Horizontal colour wash: transparent at both ends, `color` in the middle.
static func draw_wash(canvas: CanvasItem, rect: Rect2, color: Color, vertical := false) -> void:
	var clear := Color(color.r, color.g, color.b, 0.0)
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y) if not vertical else Vector2(rect.position.x, rect.end.y)
	var mid_a := a.lerp(b, 0.5)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y) if not vertical else Vector2(rect.end.x, rect.position.y)
	var mid_c := d.lerp(c, 0.5)
	if not vertical:
		canvas.draw_polygon(PackedVector2Array([a, mid_a, mid_c, d]), PackedColorArray([clear, color, color, clear]))
		canvas.draw_polygon(PackedVector2Array([mid_a, b, c, mid_c]), PackedColorArray([color, clear, clear, color]))
	else:
		canvas.draw_polygon(PackedVector2Array([a, d, mid_c, mid_a]), PackedColorArray([clear, clear, color, color]))
		canvas.draw_polygon(PackedVector2Array([mid_a, mid_c, c, b]), PackedColorArray([color, color, clear, clear]))


## Text block that wraps to `width` (draw_multiline_string), returns its height.
static func draw_wrapped(canvas: CanvasItem, font: Font, text: String, top_left: Vector2, width: float, size: int,
		color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, max_lines := -1) -> float:
	var ascent := font.get_ascent(size)
	canvas.draw_multiline_string(font, top_left + Vector2(0, ascent), text, align, width, size, max_lines, color)
	return font.get_multiline_string_size(text, align, width, size, max_lines).y
