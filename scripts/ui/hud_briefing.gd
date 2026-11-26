class_name HudBriefing
extends Control
## Private role reveal, shot like a title sequence (~6 s, the briefing phase).
## Choreography (identical timing, sound and haptic for both roles, because
## phones in one room are audible):
##   0.00  the world dims, letterbox bars close in, viewfinder brackets
##   0.30  an identity scan line sweeps the frame; "EYES ONLY · YOUR ROLE"
##         types on
##   0.90  STING: the role word decodes letter by letter (scramble, tracking
##         collapse) over a role-colour wash and a giant emblem watermark
##   1.25  a rule draws out under the word; the tagline rises
##   1.85  three objective chips stagger in (140 ms apart)
##   2.60  "ROUND STARTS IN n" with a draining bar, digits pulse each second
##   end   fly_to(): everything fades as the emblem flies into the role chip,
##         teaching where the role lives.
## Fully drawn (no containers), so it lays out for any aspect: landscape
## phones, tablets and the vertical trailer frame.

const BARS := 0.1
const STING_AT := 0.9
const FLY_TIME := 0.48

var leaving := false

var _role := ""
var _lines: Array = []
var _t := 0.0
var _left := 6.0
var _total := 6.0
var _fly := -1.0
var _fly_target := Vector2.ZERO
var _fly_done: Callable
var _stung := false
var _second := -1
var _beat := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)


func set_role(role: String) -> void:
	_role = role
	var infiltrator := role == StationRules.INFILTRATOR
	_lines = [
		["cell", UiStyle.AMBER, "Help restore power so the vault in Command opens."],
		["pod", UiStyle.INFILTRATOR, "Steal the core. Arm the cargo pod in Cargo."],
		["blackout", UiStyle.AMBER, "Blend in. Kill the lights when it helps."],
	] if infiltrator else [
		["cell", UiStyle.AMBER, "Bring 3 power cells to the Reactor."],
		["vault", UiStyle.ACCENT, "When the vault in Command opens, take the core."],
		["shuttle", UiStyle.CREW, "Load it into the shuttle in Docking."],
	]
	queue_redraw()


func role_word() -> String:
	return "INFILTRATOR" if _role == StationRules.INFILTRATOR else "CREW"


func tagline() -> String:
	return "Get the core off the station in the cargo pod. Nobody can know." if _role == StationRules.INFILTRATOR \
		else "Get the core off the station. One of you is lying."


func set_seconds_left(left: float, total: float) -> void:
	_left = maxf(left, 0.0)
	_total = maxf(total, 0.01)
	var whole := int(ceil(_left))
	if whole != _second:
		_second = whole
		_beat = 0.0


func play_in() -> void:
	leaving = false
	_fly = -1.0
	_t = 0.0
	_stung = false
	_second = -1
	modulate.a = 1.0
	show()
	set_process(true)
	UiMotion.haptic(18)


## Seek the reveal to `t` seconds (frame renderers and captures).
func seek(t: float) -> void:
	_t = t
	queue_redraw()


## Everything fades while the emblem flies into the role chip, then hide.
func fly_to(target: Vector2, done: Callable) -> void:
	if leaving or not visible:
		return
	leaving = true
	_fly = 0.0
	_fly_target = target - global_position
	_fly_done = done


func _process(delta: float) -> void:
	_t += delta
	_beat += delta
	if not _stung and _t >= STING_AT:
		_stung = true
		UiMotion.sound(self, "insert_cell", -2.0, 0.62)
		UiMotion.haptic(30)
	if _fly >= 0.0:
		_fly += delta / FLY_TIME
		if _fly >= 1.0:
			hide()
			set_process(false)
			leaving = false
			_fly = -1.0
			if _fly_done.is_valid():
				_fly_done.call()
			return
	queue_redraw()


func _base() -> float:
	if size.x >= size.y:
		return minf(size.x / 1280.0, size.y / 720.0)
	return size.x / 760.0


func _c(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(a, 0.0, 1.0))


func _draw() -> void:
	if _role == "" or size.x <= 0.0:
		return
	var b := _base()
	var t := _t
	var fly := UiType.ease_in_out(_fly) if _fly >= 0.0 else 0.0
	var fade := clampf(1.0 - fly * 1.6, 0.0, 1.0)
	var color := UiStyle.role_color(_role)
	var portrait := size.x < size.y
	# Dim and letterbox.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.03, 0.76 * UiType.ease_out(t / 0.35) * (1.0 - fly)))
	var bar := size.y * BARS * UiType.ease_out(t / 0.4) * (1.0 - fly)
	draw_rect(Rect2(0, 0, size.x, bar), Color.BLACK)
	draw_rect(Rect2(0, size.y - bar, size.x, bar), Color.BLACK)
	var frame := Rect2(Vector2(36, 36) * b + Vector2(0, bar), size - Vector2(72, 72) * b - Vector2(0, bar * 2.0))
	UiType.draw_brackets(self, frame, 34.0 * b, _c(color, 0.45 * UiType.ease_out((t - 0.2) / 0.4) * fade), maxf(2.0, 2.0 * b))
	var cy := size.y * (0.36 if portrait else 0.41)
	var cx := size.x * 0.5
	# Identity scan: one sweep down the frame.
	var scan := (t - 0.3) / 0.55
	if scan > 0.0 and scan < 1.0:
		var y := lerpf(frame.position.y, frame.end.y, UiType.ease_in_out(scan))
		draw_rect(Rect2(0, y - 40.0 * b, size.x, 40.0 * b), _c(color, 0.06 * fade))
		draw_rect(Rect2(0, y - 1.0, size.x, 2.0), _c(color.lightened(0.4), 0.8 * fade))
	# Wash band and watermark emblem behind the word.
	var wash := UiType.ease_out((t - STING_AT + 0.05) / 0.4)
	if wash > 0.0:
		var band := 320.0 * b * wash
		UiType.draw_wash(self, Rect2(0, cy - band * 0.5, size.x, band), _c(color, 0.22 * fade), true)
		var mark := 360.0 * b * (1.08 - 0.08 * wash)
		UiIcons.draw(self, UiStyle.role_icon(_role), Vector2(cx, cy), mark, _c(color, 0.08 * wash * fade))
	# Kicker.
	var word := role_word()
	var head := UiStyle.font("title")
	var word_size := UiType.fit_size(head, word, int(132 * b), size.x * 0.84, 10.0 * b)
	UiType.draw_type_on(self, UiStyle.font("caps"), "EYES ONLY  ·  YOUR ROLE", Vector2(cx, cy - word_size * 0.74),
		int(20 * b), _c(UiStyle.MUTED, fade), t - 0.32, 46.0, "center", 4.0 * b)
	# The word.
	var word_width := UiType.draw_build(self, head, word, Vector2(cx, cy + word_size * 0.36), word_size, color,
		t - STING_AT, {"align": "center", "tracking": 10.0 * b, "spread": word_size * 0.45, "total": 0.46, "dur": 0.3,
		"scramble": true, "seed": 3, "alpha": fade, "glow": _c(color, 0.22), "outline": maxi(2, int(4 * b)),
		"outline_color": Color(0, 0, 0, 0.5)})
	if fly > 0.0:
		# The emblem travels to the role chip.
		var from := Vector2(cx, cy)
		var at := from.lerp(_fly_target, fly)
		var side := lerpf(150.0 * b, 30.0, fly)
		draw_circle(at, side * 0.62, _c(color, 0.22 * (1.0 - fly * 0.5)))
		UiIcons.draw(self, UiStyle.role_icon(_role), at, side, color)
	var rule_y := cy + word_size * 0.36 + 26.0 * b
	UiType.draw_rule(self, Vector2(cx, rule_y), word_width * 0.8, _c(color, 0.9 * fade), (t - 1.25) / 0.45, maxf(2.0, 3.0 * b))
	# Tagline.
	var body := UiStyle.font("light")
	var tag := tagline()
	var tag_size := UiType.fit_size(body, tag, int(30 * b), size.x * 0.86)
	var tag_k := UiType.ease_out((t - 1.5) / 0.45)
	var tag_width := body.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size).x
	draw_string(body, Vector2(cx - tag_width * 0.5, rule_y + 22.0 * b + tag_size * 0.9 + (1.0 - tag_k) * 10.0 * b), tag,
		HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size, _c(UiStyle.TEXT.darkened(0.08), tag_k * fade))
	# Objective chips.
	var top := rule_y + 40.0 * b + tag_size * 1.6
	_draw_objectives(b, top, portrait, fade)
	# Footer countdown.
	var foot := UiType.ease_out((t - 2.6) / 0.4) * fade
	if foot > 0.0:
		var fy := size.y - bar - 64.0 * b
		var caps := UiStyle.font("caps")
		var label := "ROUND STARTS IN"
		var label_size := int(18 * b)
		var digit := str(maxi(_second, 0))
		var digit_size := int(34 * b * (1.0 + 0.25 * (1.0 - UiType.ease_out(_beat / 0.3))))
		var label_width := UiType.tracked_width(caps, label, label_size, 3.0 * b)
		var digit_width := head.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size).x
		var lx := cx - (label_width + 16.0 * b + digit_width) * 0.5
		UiType.draw_type_on(self, caps, label, Vector2(lx, fy), label_size, _c(UiStyle.MUTED, foot), 9.0, 99.0, "left", 3.0 * b, 0.0)
		draw_string(head, Vector2(lx + label_width + 16.0 * b, fy + (digit_size - label_size) * 0.25), digit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size, _c(color.lightened(0.3), foot))
		var bar_width := 360.0 * b
		var track := Rect2(cx - bar_width * 0.5, fy + 18.0 * b, bar_width, maxf(3.0, 4.0 * b))
		draw_rect(track, _c(Color.WHITE, 0.1 * foot))
		draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(_left / _total, 0.0, 1.0), track.size.y)), _c(color, foot))


func _draw_objectives(b: float, top: float, portrait: bool, fade: float) -> void:
	var count := _lines.size()
	if count == 0:
		return
	var body := UiStyle.font("body")
	var text_size := int(22 * b)
	var disc := 46.0 * b
	var gap := 18.0 * b
	var column := minf(340.0 * b, (size.x * 0.88 - gap * float(count - 1)) / float(count))
	if portrait:
		column = size.x * 0.8
	var start_x := (size.x - (column * count + gap * (count - 1))) * 0.5 if not portrait else (size.x - column) * 0.5
	for i in range(count):
		var line: Array = _lines[i]
		var k := UiType.ease_out((_t - 1.85 - 0.14 * i) / 0.4) * fade
		if k <= 0.0:
			continue
		var x := start_x + (column + gap) * i if not portrait else start_x
		var y := top + (1.0 - k) * 16.0 * b + (i * (disc + 22.0 * b) if portrait else 0.0)
		var tint: Color = line[1]
		var plate := Rect2(x, y, column, disc + 16.0 * b)
		var box := UiStyle.inset_box(0.42 * k, int(10 * b), 0)
		box.border_width_left = maxi(2, int(3 * b))
		box.border_color = _c(tint, 0.8 * k)
		draw_style_box(box, plate)
		var disc_center := Vector2(x + 14.0 * b + disc * 0.5, y + plate.size.y * 0.5)
		draw_circle(disc_center, disc * 0.5, _c(tint, 0.16 * k))
		UiIcons.draw(self, str(line[0]), disc_center, disc * 0.62, _c(tint, k))
		var text_x := disc_center.x + disc * 0.5 + 12.0 * b
		var width := plate.end.x - text_x - 12.0 * b
		var text_height := body.get_multiline_string_size(str(line[2]), HORIZONTAL_ALIGNMENT_LEFT, width, text_size, 2).y
		UiType.draw_wrapped(self, body, str(line[2]), Vector2(text_x, plate.get_center().y - text_height * 0.5), width, text_size,
			_c(UiStyle.TEXT, k), HORIZONTAL_ALIGNMENT_LEFT, 2)
