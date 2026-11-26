class_name HudCountdown
extends Control
## P0 centre countdown (upper third, never under a thumb): big digits inside a
## ring that drains clockwise, one tick per second of the total around it, a
## kind caption pill and a one-line instruction under it. Two shapes as well as
## two colours: the shuttle gets rising chevrons, the cargo pod a rotating
## hazard frame, the airlock a three-stage cycle strip (SEAL, PURGE, VENT).
## Each whole second pulses; the last five show tenths, turn white and buzz.
## When a countdown completes, a white ring bursts (look-and-feel §5 #11).

const RADIUS := 66.0

var kind := ""  # "shuttle", "pod", "airlock" or "" (hidden)
var caption := ""
var sub := ""
var left := 0.0
var total := 1.0

var _shown := 0.0
var _shown_kind := ""
var _shown_caption := ""
var _shown_sub := ""
var _last_second := -1
var _last_left := 99.0
var _beat := 1.0  # seconds since the last whole-second tick
var _time := 0.0
var _burst := 0.0  # 1 -> 0 after a countdown reaches zero


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func set_countdown(next_kind: String, next_caption: String, seconds_left: float, seconds_total: float, next_sub := "") -> void:
	if next_kind == "" and kind != "" and _last_left < 0.6:
		_burst = 1.0  # it ran out (launch / vent), rather than being cancelled
	kind = next_kind
	if kind != "":
		_shown_kind = kind
		_shown_caption = next_caption
		_shown_sub = next_sub
		left = maxf(seconds_left, 0.0)
		_last_left = left
		total = maxf(seconds_total, 0.01)
		var whole := int(ceil(left))
		if whole != _last_second:
			_last_second = whole
			_beat = 0.0
			if whole <= 5 and _shown > 0.5:
				UiMotion.haptic(20)
	else:
		_last_second = -1
		_last_left = 99.0


func _process(delta: float) -> void:
	_time += delta
	_beat += delta
	_burst = maxf(0.0, _burst - delta / 0.5)
	var target := 1.0 if kind != "" else 0.0
	_shown = move_toward(_shown, target, delta / (0.24 if target > _shown else 0.18))
	if _shown > 0.0 or target > 0.0 or _burst > 0.0:
		queue_redraw()


func _color() -> Color:
	match _shown_kind:
		"pod":
			return UiStyle.INFILTRATOR
		"airlock":
			return UiStyle.AMBER
	return UiStyle.CREW


func _draw() -> void:
	var center := Vector2(size.x * 0.5, RADIUS + 22.0)
	if _burst > 0.0:
		var k := 1.0 - _burst
		draw_arc(center, RADIUS + 10.0 + k * 90.0, 0.0, TAU, 96, Color(1, 1, 1, 0.6 * _burst), 6.0 * _burst + 1.0, true)
		draw_circle(center, RADIUS + 10.0, Color(1, 1, 1, 0.25 * _burst * _burst))
	if _shown <= 0.0:
		return
	var appear := 1.0 - pow(1.0 - _shown, 3.0)
	var color := _color()
	var urgent := ceilf(left) <= 5.0
	# Pulse: 1.18 -> 1.0 with a back ease over 260 ms on each whole second.
	var beat := clampf(_beat / 0.26, 0.0, 1.0)
	var pulse := 1.0 + (0.18 if urgent else 0.08) * (1.0 - UiType.ease_back(beat))
	var scale_all := 0.85 + 0.15 * appear
	draw_set_transform(center, 0.0, Vector2.ONE * scale_all)
	var alpha := appear
	draw_circle(Vector2.ZERO, RADIUS + 14.0, Color(0.02, 0.04, 0.08, 0.66 * alpha))
	if urgent:
		draw_circle(Vector2.ZERO, RADIUS + 14.0, UiStyle.with_alpha(color, 0.18 * alpha * (1.0 - beat)))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 96, Color(1, 1, 1, 0.1 * alpha), 7.0, true)
	var fraction := clampf(left / total, 0.0, 1.0)
	var ring := color.lightened(0.15) if urgent else color
	if fraction > 0.001:
		draw_arc(Vector2.ZERO, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * fraction, 96, UiStyle.with_alpha(ring, alpha), 7.0, true)
		var head := Vector2.from_angle(-PI / 2.0 + TAU * fraction) * RADIUS
		draw_circle(head, 6.0, UiStyle.with_alpha(ring.lightened(0.45), alpha))
	# One tick per whole second of the total; spent ones dim.
	var seconds := int(round(total))
	if seconds <= 40:
		for i in range(seconds):
			var angle := -PI / 2.0 + TAU * float(i) / float(seconds)
			var live := float(i) / float(seconds) < fraction
			var inner := RADIUS + 9.0
			var outer := inner + (6.0 if i % 5 == 0 else 3.5)
			draw_line(Vector2.from_angle(angle) * inner, Vector2.from_angle(angle) * outer,
				UiStyle.with_alpha(color if live else Color.WHITE, (0.85 if live else 0.14) * alpha), 2.0, true)
	if _shown_kind == "shuttle":
		# Rising chevrons above the digits.
		for i in range(3):
			var phase := fmod(_time * 0.9 + i / 3.0, 1.0)
			var y := -RADIUS * 0.52 - phase * 12.0
			var a := alpha * sin(phase * PI) * 0.9
			draw_polyline(PackedVector2Array([Vector2(-8, y + 5), Vector2(0, y - 2), Vector2(8, y + 5)]),
				UiStyle.with_alpha(color, a), 2.5, true)
	else:
		# Hazard frame: rotating dashes outside the ticks.
		var dashes := 18
		var spin := 0.6 if _shown_kind == "pod" else -0.9
		for i in range(dashes):
			var start := _time * spin + TAU * i / dashes
			draw_arc(Vector2.ZERO, RADIUS + 22.0, start, start + TAU / dashes * 0.5, 6,
				UiStyle.with_alpha(color, 0.75 * alpha), 4.0, true)
	draw_set_transform(center, 0.0, Vector2.ONE * scale_all * pulse)
	var font := UiStyle.font("title")
	var digit_color := Color.WHITE if urgent else color.lightened(0.4)
	var whole := str(int(ceil(left)))
	var font_size := 64 if whole.length() < 2 else 58
	if urgent and left > 0.0:
		# Tenths in the last five seconds: "4.6".
		whole = str(int(floor(left)))
		var tenth := ".%d" % (int(floor(left * 10.0)) % 10)
		var small := 30
		var width := font.get_string_size(whole, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var tenth_width := font.get_string_size(tenth, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		var x := -(width + tenth_width) * 0.5
		var baseline := font_size * 0.33
		draw_string_outline(font, Vector2(x, baseline), whole, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, Color(0, 0, 0, 0.55 * alpha))
		draw_string(font, Vector2(x, baseline), whole, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiStyle.with_alpha(digit_color, alpha))
		draw_string_outline(font, Vector2(x + width, baseline), tenth, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 6, Color(0, 0, 0, 0.55 * alpha))
		draw_string(font, Vector2(x + width, baseline), tenth, HORIZONTAL_ALIGNMENT_LEFT, -1, small, UiStyle.with_alpha(color.lightened(0.5), alpha))
	else:
		var width := font.get_string_size(whole, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := Vector2(-width * 0.5, font_size * 0.33)
		draw_string_outline(font, baseline, whole, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, Color(0, 0, 0, 0.55 * alpha))
		draw_string(font, baseline, whole, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiStyle.with_alpha(digit_color, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Caption pill: icon + words, under the ring.
	var head_font := UiStyle.font("head")
	var text := _shown_caption
	var text_size := 20
	var text_width := head_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var pill_width := text_width + 28.0 + 12.0 + 32.0
	var pill_top := center.y + (RADIUS + 32.0) * scale_all
	var pill := Rect2(size.x * 0.5 - pill_width * 0.5, pill_top, pill_width, 40.0)
	var box := UiStyle.pill_box(Color(0.02, 0.04, 0.08), 0.78 * alpha)
	box.border_color = UiStyle.with_alpha(color, 0.85 * alpha)
	box.set_border_width_all(1)
	draw_style_box(box, pill)
	var icon_name: String = {"shuttle": "shuttle", "pod": "warning", "airlock": "airlock"}.get(_shown_kind, "clock")
	UiIcons.draw(self, icon_name, Vector2(pill.position.x + 16.0 + 14.0, pill.get_center().y), 24.0, UiStyle.with_alpha(color, alpha))
	draw_string(head_font, Vector2(pill.position.x + 16.0 + 28.0 + 12.0, pill.get_center().y + text_size * 0.36),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, UiStyle.with_alpha(UiStyle.TEXT, alpha))
	var y := pill.end.y + 8.0
	if _shown_kind == "airlock":
		y = _draw_cycle(y, color, alpha)
	if _shown_sub != "":
		var body := UiStyle.font("bold")
		var sub_size := 20
		var sub_width := body.get_string_size(_shown_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		var at := Vector2(size.x * 0.5 - sub_width * 0.5, y + sub_size)
		draw_string_outline(body, at, _shown_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, 6, Color(0, 0, 0, 0.6 * alpha))
		draw_string(body, at, _shown_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, UiStyle.with_alpha(UiStyle.TEXT, 0.92 * alpha))


## Airlock cycle strip: SEAL -> PURGE -> VENT, the live stage blinking.
func _draw_cycle(y: float, color: Color, alpha: float) -> float:
	var stages := ["SEAL", "PURGE", "VENT"]
	var fraction := clampf(left / total, 0.0, 1.0)
	var live := 0 if fraction > 0.66 else (1 if fraction > 0.33 else 2)
	var font := UiStyle.font("caps")
	var text_size := 18
	var cell := 92.0
	var gap := 6.0
	var x := size.x * 0.5 - (cell * 3.0 + gap * 2.0) * 0.5
	for i in range(3):
		var rect := Rect2(x + (cell + gap) * i, y, cell, 26.0)
		var done := i < live
		var on := i == live
		var blink := 0.65 + 0.35 * sin(_time * 14.0) if on else 1.0
		var fill := UiStyle.with_alpha(color, (0.9 * blink if on else (0.35 if done else 0.08)) * alpha)
		var box := UiStyle.pill_box(fill, fill.a, 6, 2)
		box.set_corner_radius_all(4)
		box.skew = Vector2(-0.2, 0)
		draw_style_box(box, rect)
		var word: String = stages[i]
		var width := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		draw_string(font, Vector2(rect.get_center().x - width * 0.5, rect.get_center().y + text_size * 0.36), word,
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, UiStyle.with_alpha(UiStyle.INK if on else UiStyle.TEXT, (1.0 if on or done else 0.45) * alpha))
	return y + 32.0
