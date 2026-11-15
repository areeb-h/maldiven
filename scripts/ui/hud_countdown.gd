class_name HudCountdown
extends Control
## P0 centre countdown: digits inside a ring that drains clockwise, a kind
## caption with an icon underneath. Two shapes as well as two colours: the
## shuttle gets upward chevrons, the cargo pod and airlock a hazard frame.
## Pulses on every whole second; brighter and bigger in the last five.

const RADIUS := 60.0

var kind := ""  # "shuttle", "pod", "airlock" or "" (hidden)
var caption := ""
var left := 0.0
var total := 1.0

var _shown := 0.0
var _shown_kind := ""
var _shown_caption := ""
var _last_second := -1
var _beat := 1.0  # seconds since the last whole-second tick
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func set_countdown(next_kind: String, next_caption: String, seconds_left: float, seconds_total: float) -> void:
	kind = next_kind
	if kind != "":
		_shown_kind = kind
		_shown_caption = next_caption
		left = maxf(seconds_left, 0.0)
		total = maxf(seconds_total, 0.01)
		var whole := int(ceil(left))
		if whole != _last_second:
			_last_second = whole
			_beat = 0.0
			if whole <= 5 and _shown > 0.5:
				UiMotion.haptic(20)
	else:
		_last_second = -1


func _process(delta: float) -> void:
	_time += delta
	_beat += delta
	var target := 1.0 if kind != "" else 0.0
	_shown = move_toward(_shown, target, delta / (0.24 if target > _shown else 0.18))
	if _shown > 0.0 or target > 0.0:
		queue_redraw()


func _color() -> Color:
	match _shown_kind:
		"pod":
			return UiStyle.INFILTRATOR
		"airlock":
			return UiStyle.AMBER
	return UiStyle.CREW


func _draw() -> void:
	if _shown <= 0.0:
		return
	var appear := 1.0 - pow(1.0 - _shown, 3.0)
	var color := _color()
	var urgent := ceilf(left) <= 5.0
	var center := Vector2(size.x * 0.5, RADIUS + 18.0)
	# Pulse: 1.18 -> 1.0 with a back ease over 260 ms on each whole second.
	var beat := clampf(_beat / 0.26, 0.0, 1.0)
	var pulse := 1.0 + (0.18 if urgent else 0.08) * (1.0 - _ease_back(beat))
	var scale_all := 0.85 + 0.15 * appear
	draw_set_transform(center, 0.0, Vector2.ONE * scale_all)
	var alpha := appear
	draw_circle(Vector2.ZERO, RADIUS + 10.0, Color(0.02, 0.04, 0.08, 0.6 * alpha))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 96, Color(1, 1, 1, 0.1 * alpha), 6.0, true)
	var fraction := clampf(left / total, 0.0, 1.0)
	var ring := color.lightened(0.15) if urgent else color
	if fraction > 0.001:
		draw_arc(Vector2.ZERO, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * fraction, 96, UiStyle.with_alpha(ring, alpha), 6.0, true)
		var head := Vector2.from_angle(-PI / 2.0 + TAU * fraction) * RADIUS
		draw_circle(head, 5.5, UiStyle.with_alpha(ring.lightened(0.4), alpha))
	if _shown_kind == "shuttle":
		# Upward chevrons riding above the ring.
		for i in range(3):
			var phase := fmod(_time * 0.9 + i / 3.0, 1.0)
			var y := -RADIUS - 14.0 - phase * 18.0
			var a := alpha * sin(phase * PI) * 0.9
			draw_polyline(PackedVector2Array([Vector2(-9, y + 6), Vector2(0, y - 2), Vector2(9, y + 6)]),
				UiStyle.with_alpha(color, a), 3.0, true)
	else:
		# Hazard frame: rotating dashes around the ring.
		var dashes := 16
		for i in range(dashes):
			var start := _time * 0.6 + TAU * i / dashes
			draw_arc(Vector2.ZERO, RADIUS + 12.0, start, start + TAU / dashes * 0.5, 6,
				UiStyle.with_alpha(color, 0.7 * alpha), 4.0, true)
	draw_set_transform(center, 0.0, Vector2.ONE * scale_all * pulse)
	var digits := str(int(ceil(left)))
	var font := UiStyle.font("title")
	var font_size := 56
	var digit_color := Color.WHITE if urgent else color.lightened(0.35)
	var width := font.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := Vector2(-width * 0.5, font_size * 0.36)
	draw_string_outline(font, baseline, digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, Color(0, 0, 0, 0.55 * alpha))
	draw_string(font, baseline, digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiStyle.with_alpha(digit_color, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Caption pill: icon + words, under the ring.
	var head_font := UiStyle.font("head")
	var text := _shown_caption
	var text_size := 20
	var text_width := head_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var pill_width := text_width + 28.0 + 12.0 + 32.0
	var pill_top := center.y + (RADIUS + 22.0) * scale_all
	var pill := Rect2(size.x * 0.5 - pill_width * 0.5, pill_top, pill_width, 38.0)
	var box := UiStyle.pill_box(Color(0.02, 0.04, 0.08), 0.7 * alpha)
	box.border_color = UiStyle.with_alpha(color, 0.8 * alpha)
	box.set_border_width_all(1)
	draw_style_box(box, pill)
	var icon_name: String = {"shuttle": "shuttle", "pod": "warning", "airlock": "airlock"}.get(_shown_kind, "clock")
	UiIcons.draw(self, icon_name, Vector2(pill.position.x + 16.0 + 14.0, pill.get_center().y), 24.0, UiStyle.with_alpha(color, alpha))
	draw_string(head_font, Vector2(pill.position.x + 16.0 + 28.0 + 12.0, pill.get_center().y + text_size * 0.36),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, UiStyle.with_alpha(UiStyle.TEXT, alpha))


func _ease_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
