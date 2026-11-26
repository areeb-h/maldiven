class_name HudBriefing
extends Control
## The private role card (production plan U3). The hero block is a large
## helmet (crew: LED eyes in your suit colour; infiltrator: the red V), the
## words YOU ARE CREW / YOU ARE THE INFILTRATOR and one line beneath. It comes
## in over 0.3 s (fade and a 6 % scale settle), holds, and goes out in 0.2 s.
##
## Two styles, one component:
##   "full"  the game's ~6 s briefing: the world dims, letterbox bars close,
##           an identity scan sweeps, the card lands with a sting at 0.6 s,
##           the three objectives stagger in, "ROUND STARTS IN n" drains, then
##           fly_to() sends the helmet into the HUD's role chip. Identical
##           timing, sound and haptic for both roles (phones in one room are
##           audible).
##   "flash" the cinematic variant for the trailer: only the hero block, no
##           chrome, placed at `y` (share of the frame; default the upper
##           third), out at `hold` seconds.
## Standalone: `present({role, name, color, style, line, y, hold})`; time from
## _process, or `set_progress(t)` / `step(delta)` (manual). Lays out for any
## aspect from the frame size.

const BARS := 0.1
const CARD_AT := 0.6  # the hero block lands (full style)
const IN_TIME := 0.3
const OUT_TIME := 0.2
const FLY_TIME := 0.48

var leaving := false
var manual := false

var _role := ""
var _name := ""
var _suit := Color.WHITE
var _style := "full"
var _line_override := ""
var _y_share := -1.0
var _hold := 0.0
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


## Plain-data entry point. Keys: role ("crew" | "infiltrator"), name, color
## (suit), style ("full" | "flash"), line (overrides the line beneath),
## y (flash: centre of the block, share of the height), hold (flash: s).
func present(data: Dictionary) -> void:
	set_role(str(data.get("role", StationRules.CREW)))
	_name = str(data.get("name", ""))
	_suit = data.get("color", UiStyle.role_color(_role))
	_style = str(data.get("style", "full"))
	_line_override = str(data.get("line", ""))
	_y_share = float(data.get("y", -1.0))
	_hold = float(data.get("hold", 1.2 if _style == "flash" else 0.0))
	play_in()


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


## Seat the local player's name and suit colour (the HUD calls this).
func set_player(player_name: String, suit: Color) -> void:
	_name = player_name
	_suit = suit


func role_words() -> Array:
	return ["YOU ARE ", "THE INFILTRATOR"] if _role == StationRules.INFILTRATOR else ["YOU ARE ", "CREW"]


func line() -> String:
	if _line_override != "":
		return _line_override
	return "Get the core off in the cargo pod. Nobody can know." if _role == StationRules.INFILTRATOR \
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
	show()
	set_process(true)
	if not manual:
		UiMotion.haptic(18)


func set_progress(t: float) -> void:
	manual = true
	_t = t
	queue_redraw()


func step(delta: float) -> void:
	manual = true
	_t += delta
	_beat += delta
	queue_redraw()


## Alias kept for captures.
func seek(t: float) -> void:
	set_progress(t)


## Everything fades while the helmet flies into the role chip, then hide.
func fly_to(target: Vector2, done: Callable) -> void:
	if leaving or not visible:
		return
	leaving = true
	_fly = 0.0
	_fly_target = target - global_position
	_fly_done = done


func _process(delta: float) -> void:
	if not manual:
		_t += delta
		_beat += delta
		if not _stung and _style == "full" and _t >= CARD_AT:
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


## 0..1 presence of the hero block: in over 0.3 s, out over 0.2 s (flash).
func _card_alpha(local: float) -> float:
	var k := clampf(local / IN_TIME, 0.0, 1.0)
	if _style == "flash" and _hold > 0.0:
		k *= 1.0 - clampf((local - _hold) / OUT_TIME, 0.0, 1.0)
	return k


func _draw() -> void:
	if _role == "" or size.x <= 0.0:
		return
	if _style == "flash":
		var cy := size.y * (_y_share if _y_share >= 0.0 else 0.3)
		_draw_hero(_base(), cy, _t, 1.0)
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
	var cy := size.y * (0.34 if portrait else 0.37)
	# Identity scan: one sweep down the frame before the card lands.
	var scan := (t - 0.1) / 0.5
	if scan > 0.0 and scan < 1.0:
		var y := lerpf(frame.position.y, frame.end.y, UiType.ease_in_out(scan))
		draw_rect(Rect2(0, y - 40.0 * b, size.x, 40.0 * b), _c(color, 0.06 * fade))
		draw_rect(Rect2(0, y - 1.0, size.x, 2.0), _c(color.lightened(0.4), 0.8 * fade))
	# Kicker: whose eyes only.
	var caps := UiStyle.font("caps")
	var kicker := "EYES ONLY" + ("  ·  %s" % _name.to_upper() if _name != "" else "")
	var kicker_size := int(20 * b)
	var kicker_width := UiType.draw_type_on(self, caps, kicker, Vector2(size.x * 0.5, frame.position.y + 44.0 * b), kicker_size,
		_c(UiStyle.MUTED, fade), t - 0.15, 46.0, "center", 4.0 * b, 0.0)
	if _name != "" and t > 0.15:
		draw_circle(Vector2(size.x * 0.5 - kicker_width * 0.5 - 16.0 * b, frame.position.y + 44.0 * b - kicker_size * 0.36),
			6.0 * b, _c(_suit, fade))
	if fly <= 0.0:
		_draw_hero(b, cy, t - CARD_AT, fade)
	else:
		var from := Vector2(size.x * 0.5, cy - 70.0 * b)
		var at := from.lerp(_fly_target, fly)
		var side := lerpf(150.0 * b, 30.0, fly)
		draw_circle(at, side * 0.62, _c(color, 0.22 * (1.0 - fly * 0.5)))
		UiIcons.draw(self, UiStyle.role_icon(_role), at, side, color)
	# Objectives.
	_draw_objectives(b, cy + 150.0 * b, portrait, fade)
	# Footer countdown.
	var foot := UiType.ease_out((t - 2.2) / 0.3) * fade
	if foot > 0.0:
		var head := UiStyle.font("title")
		var fy := size.y - bar - 64.0 * b
		var label := "ROUND STARTS IN"
		var label_size := int(18 * b)
		var digit := str(maxi(_second, 0))
		var digit_size := int(34 * b * (1.0 + 0.25 * (1.0 - UiType.ease_out(_beat / 0.3))))
		var label_width := UiType.tracked_width(caps, label, label_size, 3.0 * b)
		var digit_width := head.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size).x
		var lx := size.x * 0.5 - (label_width + 16.0 * b + digit_width) * 0.5
		UiType.draw_type_on(self, caps, label, Vector2(lx, fy), label_size, _c(UiStyle.MUTED, foot), 9.0, 99.0, "left", 3.0 * b, 0.0)
		draw_string(head, Vector2(lx + label_width + 16.0 * b, fy + (digit_size - label_size) * 0.25), digit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size, _c(color.lightened(0.3), foot))
		var bar_width := 360.0 * b
		var track := Rect2(size.x * 0.5 - bar_width * 0.5, fy + 18.0 * b, bar_width, maxf(3.0, 4.0 * b))
		draw_rect(track, _c(Color.WHITE, 0.1 * foot))
		draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(_left / _total, 0.0, 1.0), track.size.y)), _c(color, foot))


## The hero block centred on (centre x, cy): helmet, YOU ARE …, the line.
## `local` is the time since the block started landing.
func _draw_hero(b: float, cy: float, local: float, fade: float) -> void:
	var k := _card_alpha(local) * fade
	if k <= 0.0:
		return
	var color := UiStyle.role_color(_role)
	var infiltrator := _role == StationRules.INFILTRATOR
	var grow := 1.0 + 0.06 * (1.0 - UiType.ease_out(clampf(local / IN_TIME, 0.0, 1.0)))
	var cx := size.x * 0.5
	draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE * grow)
	# Helmet: the infiltrator's red V, or the crew's LED eyes in the suit colour.
	var helmet := 132.0 * b
	var helmet_y := -helmet * 0.62
	draw_circle(Vector2(0, helmet_y), helmet * 0.62, _c(color, 0.16 * k))
	draw_arc(Vector2(0, helmet_y), helmet * 0.62, 0.0, TAU, 64, _c(color, 0.5 * k), maxf(2.0, 2.0 * b), true)
	if infiltrator:
		UiIcons.draw(self, "mask", Vector2(0, helmet_y), helmet * 0.9, _c(Color.WHITE, k), 0.0, "color")
	else:
		UiIcons.draw(self, "face", Vector2(0, helmet_y), helmet * 0.9, _c(_suit if _suit != Color.WHITE else color, k))
	# YOU ARE + the role, one line fitted to the frame.
	var words := role_words()
	var head := UiStyle.font("title")
	var text_size := UiType.fit_size(head, words[0] + words[1], int(72 * b), size.x * 0.86, 3.0 * b)
	var w0 := UiType.tracked_width(head, words[0], text_size, 3.0 * b)
	var w1 := UiType.tracked_width(head, words[1], text_size, 3.0 * b)
	var x := -(w0 + w1) * 0.5
	var baseline := helmet * 0.12 + text_size * 0.72
	for part in [[words[0], UiStyle.TEXT, w0], [words[1], color, w1]]:
		var px := x
		for i in range(str(part[0]).length()):
			var ch := str(part[0])[i]
			if part[1] == color:
				draw_string_outline(head, Vector2(px, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, maxi(4, int(text_size * 0.3)),
					_c(color, 0.18 * k))
			draw_string(head, Vector2(px, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, _c(part[1], k))
			px += head.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x + 3.0 * b
		x += float(part[2]) + 3.0 * b
	UiType.draw_rule(self, Vector2(0, baseline + 22.0 * b), (w0 + w1) * 0.6, _c(color, 0.9 * k), (local - 0.1) / 0.3, maxf(2.0, 3.0 * b))
	var body := UiStyle.font("light")
	var text := line()
	var line_size := UiType.fit_size(body, text, int(30 * b), size.x * 0.86)
	var line_k := k * clampf((local - 0.15) / IN_TIME, 0.0, 1.0)
	var line_width := body.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x
	draw_string(body, Vector2(-line_width * 0.5, baseline + 30.0 * b + line_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		line_size, _c(UiStyle.TEXT.darkened(0.06), line_k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
		var entry: Array = _lines[i]
		var k := UiType.ease_out((_t - 1.4 - 0.14 * i) / 0.3) * fade
		if k <= 0.0:
			continue
		var x := start_x + (column + gap) * i if not portrait else start_x
		var y := top + (1.0 - k) * 16.0 * b + (i * (disc + 22.0 * b) if portrait else 0.0)
		var tint: Color = entry[1]
		var plate := Rect2(x, y, column, disc + 16.0 * b)
		var box := UiStyle.inset_box(0.42 * k, int(10 * b), 0)
		box.border_width_left = maxi(2, int(3 * b))
		box.border_color = _c(tint, 0.8 * k)
		draw_style_box(box, plate)
		var disc_center := Vector2(x + 14.0 * b + disc * 0.5, y + plate.size.y * 0.5)
		draw_circle(disc_center, disc * 0.5, _c(tint, 0.16 * k))
		UiIcons.draw(self, str(entry[0]), disc_center, disc * 0.62, _c(tint, k))
		var text_x := disc_center.x + disc * 0.5 + 12.0 * b
		var width := plate.end.x - text_x - 12.0 * b
		var text_height := body.get_multiline_string_size(str(entry[2]), HORIZONTAL_ALIGNMENT_LEFT, width, text_size, 2).y
		UiType.draw_wrapped(self, body, str(entry[2]), Vector2(text_x, plate.get_center().y - text_height * 0.5), width, text_size,
			_c(UiStyle.TEXT, k), HORIZONTAL_ALIGNMENT_LEFT, 2)
