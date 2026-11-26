class_name HudResult
extends Control
## End-of-round screen, staged as the round's last scene:
##   0.00  dim, letterbox, outcome-colour wash; "ROUND OVER" types on and the
##         verdict chip (YOU WON / YOU LOST) pops
##   0.25  the outcome builds in two big lines ("CREW" / "ESCAPED")
##   1.30  THE UNMASKING: "THE INFILTRATOR WAS", a red masked portrait pops in,
##         glitches and wipes away to show their suit colour and helmet, and
##         their name decodes letter by letter in that colour
##   0.60  right side: the story track (the round as a line with its key
##         moments: power, blackout, shots, spacing, launch) fills with a
##         playhead, and the event log staggers in with key rows highlighted
##   1.50  buttons arrive (a stray tap can't skip the reveal)
## The hero parts are drawn; the log is a ScrollContainer so long rounds
## scroll. Landscape puts the reveal left and the story right; portrait
## stacks them.

signal again_pressed
signal leave_pressed

const BUTTON_GUARD := 1.5
const BARS := 0.07
const UNMASK_AT := 1.3
## Timeline kinds that become markers on the story track.
const KEY_KINDS := ["power", "blackout", "crosshair", "spaced", "shuttle", "pod", "downed", "clock", "abort"]

var _t := 0.0
var _title := ["", ""]
var _color := UiStyle.CREW
var _icon := "trophy"
var _reason := ""
var _verdict := ""
var _verdict_color := UiStyle.GOOD
var _verdict_icon := "check"
var _infiltrator := ""
var _infiltrator_color := UiStyle.INFILTRATOR
var _events: Array = []  # [{seconds, kind, key}]
var _end_seconds := 1.0
var _unmasked := false

var _list: PanelContainer
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _buttons: HBoxContainer
var _again: Button
var _leave: Button
var _waiting: HBoxContainer
var _waiting_dot: Control
var _left_rect := Rect2()
var _right_rect := Rect2()
var _track_rect := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_list = PanelContainer.new()
	_list.add_theme_stylebox_override("panel", UiStyle.inset_box(0.4, 12, 12))
	add_child(_list)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", UiStyle.S2)
	add_child(_buttons)
	_waiting = HBoxContainer.new()
	_waiting.add_theme_constant_override("separation", 10)
	_waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting_dot = Control.new()
	_waiting_dot.custom_minimum_size = Vector2(14, 14)
	_waiting_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_waiting_dot.draw.connect(func():
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		_waiting_dot.draw_circle(Vector2(7, 7), 4.0 + 3.0 * pulse, UiStyle.with_alpha(UiStyle.ACCENT, 0.25 * (1.0 - pulse)))
		_waiting_dot.draw_circle(Vector2(7, 7), 4.0, UiStyle.ACCENT))
	_waiting.add_child(_waiting_dot)
	var waiting_label := UiStyle.label("Waiting for the host…", "body", 22, UiStyle.MUTED)
	waiting_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_waiting.add_child(waiting_label)
	_buttons.add_child(_waiting)
	_leave = UiStyle.button("LEAVE", false, UiStyle.ACCENT, "leave", 80)
	_leave.custom_minimum_size.x = 176
	_leave.pressed.connect(func(): leave_pressed.emit())
	_buttons.add_child(_leave)
	_again = UiStyle.button("PLAY AGAIN", true, UiStyle.ACCENT, "play", 80)
	_again.custom_minimum_size.x = 256
	_again.pressed.connect(func(): again_pressed.emit())
	_buttons.add_child(_again)
	resized.connect(_layout)
	set_process(false)


func _base() -> float:
	if size.x >= size.y:
		return minf(size.x / 1280.0, size.y / 720.0)
	return size.x / 760.0


func _portrait() -> bool:
	return size.x < size.y


func _layout() -> void:
	if size.x <= 0.0:
		return
	var b := _base()
	var bar := size.y * BARS
	var top := bar + 36.0 * b
	var bottom := size.y - bar - 24.0 * b
	var button_h := 80.0
	if _portrait():
		var w := size.x * 0.86
		var x := size.x * 0.07
		_left_rect = Rect2(x, top, w, size.y * 0.36)
		_right_rect = Rect2(x, _left_rect.end.y + 24.0 * b, w, bottom - _left_rect.end.y - 24.0 * b)
	else:
		_left_rect = Rect2(size.x * 0.06, top, size.x * 0.40, bottom - top)
		_right_rect = Rect2(size.x * 0.50, top, size.x * 0.44, bottom - top)
	_track_rect = Rect2(_right_rect.position + Vector2(0, 40.0 * b), Vector2(_right_rect.size.x, 64.0 * b))
	var list_top := _track_rect.end.y + 14.0 * b
	var list_bottom := _right_rect.end.y - button_h - 16.0
	_list.position = Vector2(_right_rect.position.x, list_top)
	_list.size = Vector2(_right_rect.size.x, maxf(80.0, list_bottom - list_top))
	_buttons.position = Vector2(_right_rect.position.x, _right_rect.end.y - button_h)
	_buttons.size = Vector2(_right_rect.size.x, button_h)
	for row in _rows.get_children():
		var slot := row as Control
		if slot != null and slot.get_child_count() > 0:
			var words := slot.get_child(0).get_meta("words", null) as Control
			if words != null:
				words.custom_minimum_size.x = maxf(120.0, _list.size.x - 24.0 - 140.0)


func _process(delta: float) -> void:
	_t += delta
	if not _unmasked and _infiltrator != "" and _t >= UNMASK_AT + 0.6:
		_unmasked = true
		UiMotion.sound(self, "insert_cell", -6.0, 0.5)
		UiMotion.haptic(24)
	if _waiting.visible:
		_waiting_dot.queue_redraw()
	queue_redraw()


## Seek the staging to `t` seconds (captures and frame renderers).
func seek(t: float) -> void:
	_t = t
	queue_redraw()


func show_result(rules: StationRules, role: String, is_host: bool) -> void:
	var title := "STATION LOST"
	var color := UiStyle.MUTED
	var icon_name := "clock"
	if rules.winner == StationRules.CREW:
		title = "CREW ESCAPED"
		color = UiStyle.CREW
		icon_name = "shuttle"
		if rules.reason.contains("spaced"):
			title = "INFILTRATOR SPACED"
			icon_name = "airlock"
	elif rules.winner == StationRules.INFILTRATOR:
		title = "INFILTRATOR WINS"
		color = UiStyle.INFILTRATOR
		icon_name = "pod" if rules.reason.contains("pod") else "mask"
	elif rules.reason.contains("No crew"):
		icon_name = "downed"
	var split := title.find(" ")
	_title = [title.substr(0, split), title.substr(split + 1)] if split > 0 else [title, ""]
	var won := rules.winner != "" and rules.winner == role
	var nobody := rules.winner == "none" or rules.winner == ""
	_color = color if not nobody else UiStyle.TEXT
	_icon = icon_name
	_reason = rules.reason
	_verdict = "YOU WON" if won else ("NOBODY WON" if nobody else "YOU LOST")
	_verdict_color = UiStyle.GOOD if won else (UiStyle.MUTED if nobody else UiStyle.INFILTRATOR)
	_verdict_icon = "check" if won else ("abort" if nobody else "close")
	# The infiltrator's suit colour comes from the roster by name.
	var colors := {}
	for id in rules.players:
		colors[str(rules.players[id].name)] = rules.players[id].color
	_infiltrator = rules.infiltrator_name if rules.infiltrator_name != "nobody" else ""
	_infiltrator_color = colors.get(_infiltrator, UiStyle.INFILTRATOR)
	_unmasked = false
	# Story: events with times, key ones become track markers.
	_events.clear()
	_end_seconds = 1.0
	for line in rules.timeline:
		var text := str(line)
		var cut := text.find("  ")
		var stamp := text.substr(0, cut) if cut > 0 else ""
		var seconds := _stamp_seconds(stamp)
		var kind := timeline_kind(text.substr(cut + 2) if cut > 0 else text)
		_events.append({"seconds": seconds, "kind": kind, "key": kind in KEY_KINDS})
		_end_seconds = maxf(_end_seconds, seconds)
	for child in _rows.get_children():
		child.queue_free()
	var index := 0
	for line in rules.timeline:
		var row := _timeline_row(str(line), colors)
		var slot := UiMotion.slide(row)
		_rows.add_child(slot)
		if index < 14:
			slot.play_in(0.9 + index * 0.06, Vector2(-16, 0), 0.24)
		index += 1
	_again.visible = is_host
	_waiting.visible = not is_host
	_t = 0.0
	show()
	_layout()
	set_process(true)
	_list.modulate.a = 0.0
	UiMotion.fade(_list, 1.0, 0.3, 0.7)
	_buttons.modulate.a = 0.0
	for child in _buttons.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = true
	var guard := create_tween()
	guard.tween_interval(BUTTON_GUARD)
	guard.tween_callback(func():
		for child in _buttons.get_children():
			if child is BaseButton:
				(child as BaseButton).disabled = false)
	guard.tween_property(_buttons, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func _stamp_seconds(stamp: String) -> float:
	var parts := stamp.split(":")
	if parts.size() != 2:
		return 0.0
	return float(parts[0].to_int() * 60 + parts[1].to_int())


func _c(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(a, 0.0, 1.0))


func _draw() -> void:
	if size.x <= 0.0:
		return
	var b := _base()
	var t := _t
	var bar := size.y * BARS * UiType.ease_out(t / 0.4)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.03, 0.8 * UiType.ease_out(t / 0.3)))
	# Outcome wash from the left (top in portrait).
	var wash := UiType.ease_out(t / 0.6)
	var clear := _c(_color, 0.0)
	if _portrait():
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y * 0.5), Vector2(0, size.y * 0.5)]),
			PackedColorArray([_c(_color, 0.2 * wash), _c(_color, 0.2 * wash), clear, clear]))
	else:
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x * 0.55, 0), Vector2(size.x * 0.55, size.y), Vector2(0, size.y)]),
			PackedColorArray([_c(_color, 0.22 * wash), clear, clear, _c(_color, 0.22 * wash)]))
	UiIcons.draw(self, _icon, _left_rect.position + Vector2(_left_rect.size.x * 0.72, _left_rect.size.y * 0.22),
		260.0 * b, _c(_color, 0.07 * wash))
	draw_rect(Rect2(0, 0, size.x, bar), Color.BLACK)
	draw_rect(Rect2(0, size.y - bar, size.x, bar), Color.BLACK)
	_draw_outcome(b)
	_draw_unmask(b)
	_draw_story(b)


func _draw_outcome(b: float) -> void:
	var t := _t
	var x := _left_rect.position.x
	var y := _left_rect.position.y
	var caps := UiStyle.font("caps")
	var kicker_size := int(20 * b)
	var kicker_width := UiType.draw_type_on(self, caps, "ROUND OVER", Vector2(x, y + kicker_size), kicker_size,
		UiStyle.MUTED, t - 0.1, 40.0, "left", 3.0 * b, 0.0)
	# Verdict chip.
	var pop := UiType.ease_back((t - 0.45) / 0.3)
	if pop > 0.0:
		var bold := UiStyle.font("bold")
		var chip_size := int(18 * b)
		var text_width := bold.get_string_size(_verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x
		var chip := Rect2(x + kicker_width + 16.0 * b, y - 2.0 * b, text_width + 46.0 * b, kicker_size + 12.0 * b)
		var center := chip.get_center()
		chip = Rect2(center - chip.size * 0.5 * pop, chip.size * pop)
		draw_style_box(UiStyle.pill_box(_verdict_color, 0.95 * clampf(pop, 0.0, 1.0)), chip)
		if pop > 0.8:
			UiIcons.draw(self, _verdict_icon, Vector2(chip.position.x + 16.0 * b, center.y), 16.0 * b, UiStyle.INK)
			draw_string(bold, Vector2(chip.position.x + 30.0 * b, center.y + chip_size * 0.36), _verdict,
				HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size, UiStyle.INK)
	# Two-line outcome.
	var head := UiStyle.font("title")
	var limit := _left_rect.size.x
	var size_title := mini(UiType.fit_size(head, _title[0], int(84 * b), limit, 4.0 * b),
		UiType.fit_size(head, _title[1], int(84 * b), limit, 4.0 * b))
	var line_y := y + kicker_size + 24.0 * b + size_title * 0.82
	for i in range(2):
		if _title[i] == "":
			continue
		UiType.draw_build(self, head, _title[i], Vector2(x, line_y), size_title, _color, t - 0.25 - 0.2 * i,
			{"tracking": 4.0 * b, "spread": size_title * 0.4, "total": 0.4, "dur": 0.3, "scramble": i == 1,
			"seed": 11 + i, "glow": _c(_color, 0.18), "outline": maxi(2, int(4 * b))})
		line_y += size_title * 0.98
	var body := UiStyle.font("body")
	var reason_k := UiType.ease_out((t - 0.9) / 0.4)
	var reason_size := int(24 * b)
	var reason_top := line_y - size_title * 0.62 + 18.0 * b
	var used := UiType.draw_wrapped(self, body, _reason, Vector2(x, reason_top + (1.0 - reason_k) * 8.0),
		limit, reason_size, _c(UiStyle.MUTED.lightened(0.2), reason_k), HORIZONTAL_ALIGNMENT_LEFT, 2)
	set_meta("unmask_top", reason_top + used + 28.0 * b)


func _draw_unmask(b: float) -> void:
	if _infiltrator == "":
		return
	var t := _t - UNMASK_AT
	if t <= 0.0:
		return
	var x := _left_rect.position.x
	var y: float = get_meta("unmask_top", _left_rect.position.y + 300.0)
	var caps := UiStyle.font("caps")
	var kicker_size := int(20 * b)
	UiType.draw_type_on(self, caps, "THE INFILTRATOR WAS", Vector2(x, y + kicker_size), kicker_size,
		UiStyle.INFILTRATOR.lightened(0.15), t, 44.0, "left", 3.0 * b, 0.4)
	var tile := minf(132.0 * b, _left_rect.end.y - y - kicker_size - 20.0 * b)
	tile = maxf(tile, 72.0)
	var tile_pos := Vector2(x, y + kicker_size + 16.0 * b)
	var pop := UiType.ease_back((t - 0.15) / 0.35)
	if pop <= 0.0:
		return
	var center := tile_pos + Vector2(tile, tile) * 0.5
	var side := tile * clampf(pop, 0.0, 1.2)
	var rect := Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))
	var suit := _infiltrator_color
	var plate := UiStyle.pill_box(suit, 1.0)
	plate.set_corner_radius_all(int(side * 0.22))
	draw_style_box(plate, rect)
	UiIcons.draw(self, "face", center, side * 0.74, Color(0.02, 0.04, 0.08, 0.88))
	# The mask: a red plate that glitches and wipes down off the face.
	var wipe := UiType.ease_in_out((t - 0.6) / 0.45)
	if wipe < 1.0:
		var cover := Rect2(rect.position + Vector2(0, rect.size.y * wipe), Vector2(rect.size.x, rect.size.y * (1.0 - wipe)))
		var glitching := t > 0.45 and t < 0.75
		var slices := 6
		for i in range(slices):
			var band := Rect2(cover.position.x, cover.position.y + cover.size.y * i / slices, cover.size.x, cover.size.y / slices + 0.5)
			var jitter := 0.0
			if glitching:
				jitter = (UiType.hash01(5, i, int(t * 30.0)) - 0.5) * side * 0.24
			draw_rect(Rect2(band.position + Vector2(jitter, 0), band.size), Color(0.32, 0.03, 0.07, 0.97))
		var mask_center := Vector2(center.x, rect.position.y + rect.size.y * 0.5)
		if cover.has_point(mask_center):
			UiIcons.draw(self, "mask", mask_center, side * 0.7, UiStyle.INFILTRATOR)
		draw_rect(Rect2(cover.position.x - 4.0, cover.position.y - 1.5, cover.size.x + 8.0, 3.0), _c(UiStyle.INFILTRATOR.lightened(0.4), 0.9))
	var flash := 1.0 - clampf((t - 1.05) / 0.35, 0.0, 1.0)
	if t > 1.05 and flash > 0.0:
		draw_style_box(_ring(suit, flash), rect.grow(4.0 + 10.0 * (1.0 - flash)))
	# The name in their suit colour.
	var shown := suit.lightened(0.25) if suit.get_luminance() < 0.42 else suit
	var head := UiStyle.font("title")
	var name_x := tile_pos.x + tile + 22.0 * b
	var name_size := UiType.fit_size(head, _infiltrator.to_upper(), int(56 * b), _left_rect.end.x - name_x, 2.0 * b)
	var name_y := tile_pos.y + tile * 0.5 + name_size * 0.2
	UiType.draw_build(self, head, _infiltrator.to_upper(), Vector2(name_x, name_y), name_size, shown, t - 0.85,
		{"tracking": 2.0 * b, "spread": name_size * 0.3, "total": 0.45, "dur": 0.3, "scramble": true,
		"seed": _infiltrator.hash(), "outline": maxi(2, int(4 * b)), "glow": _c(shown, 0.2)})
	var chip_k := UiType.ease_out((t - 1.4) / 0.3)
	if chip_k > 0.0:
		var bold := UiStyle.font("bold")
		var chip_size := int(18 * b)
		var label := "INFILTRATOR"
		var w := bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x + 44.0 * b
		var chip := Rect2(name_x, name_y + 18.0 * b, w, chip_size + 14.0 * b)
		var box := UiStyle.tag_box(UiStyle.INFILTRATOR, 12, 2)
		box.bg_color = _c(UiStyle.INFILTRATOR, 0.18 * chip_k)
		box.border_color = _c(UiStyle.INFILTRATOR, 0.8 * chip_k)
		draw_style_box(box, chip)
		UiIcons.draw(self, "mask", Vector2(chip.position.x + 16.0 * b, chip.get_center().y), 18.0 * b, _c(UiStyle.INFILTRATOR, chip_k))
		draw_string(bold, Vector2(chip.position.x + 30.0 * b, chip.get_center().y + chip_size * 0.36), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size, _c(UiStyle.INFILTRATOR.lightened(0.2), chip_k))


func _ring(color: Color, a: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(3)
	box.border_color = _c(color.lightened(0.4), a)
	box.set_corner_radius_all(24)
	box.anti_aliasing = true
	return box


func _draw_story(b: float) -> void:
	var t := _t
	var caps := UiStyle.font("caps")
	var cap_size := int(20 * b)
	var k := UiType.ease_out((t - 0.5) / 0.3)
	if k <= 0.0:
		return
	var head_pos := _right_rect.position + Vector2(0, cap_size)
	UiIcons.draw(self, "clock", head_pos + Vector2(10.0 * b, -cap_size * 0.36), 20.0 * b, _c(UiStyle.AMBER, k))
	UiType.draw_type_on(self, caps, "HOW IT HAPPENED", head_pos + Vector2(28.0 * b, 0), cap_size, _c(UiStyle.AMBER, k),
		t - 0.5, 40.0, "left", 3.0 * b, 0.0)
	var total := "%d:%02d" % [int(_end_seconds) / 60, int(_end_seconds) % 60]
	var bold := UiStyle.font("bold")
	var total_width := bold.get_string_size(total, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size).x
	draw_string(bold, Vector2(_right_rect.end.x - total_width, head_pos.y), total, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size,
		_c(UiStyle.FAINT, k))
	# The story track: the round as a line, key moments as markers.
	var line_y := _track_rect.position.y + _track_rect.size.y * 0.62
	var x0 := _track_rect.position.x + 8.0 * b
	var x1 := _track_rect.end.x - 8.0 * b
	var draw_k := UiType.ease_out((t - 0.6) / 0.5)
	draw_rect(Rect2(x0, line_y - 1.5, (x1 - x0) * draw_k, 3.0), _c(Color.WHITE, 0.16))
	var head := clampf((t - 0.8) / 1.4, 0.0, 1.0)
	var head_x := lerpf(x0, x1, UiType.ease_in_out(head))
	if head > 0.0:
		draw_rect(Rect2(x0, line_y - 1.5, head_x - x0, 3.0), _c(_color, 0.9))
	var last_x := -1000.0
	var row := 0
	for event in _events:
		if not event.key:
			continue
		var ex := lerpf(x0, x1, clampf(float(event.seconds) / _end_seconds, 0.0, 1.0))
		row = (row + 1) % 2 if ex - last_x < 30.0 * b else 0
		last_x = ex
		var lit := head_x >= ex - 0.5 and head > 0.0
		var tint := _kind_tint(str(event.kind))
		var icon_y := line_y - 24.0 * b - row * 22.0 * b
		var a := 1.0 if lit else 0.35
		draw_circle(Vector2(ex, line_y), (5.0 if lit else 3.5) * b, _c(tint, a * draw_k))
		draw_rect(Rect2(ex - 0.75, icon_y + 10.0 * b, 1.5, line_y - icon_y - 10.0 * b), _c(tint, 0.35 * a * draw_k))
		var icon_name := UiStyle.kind_icon(str(event.kind)) if event.kind in ["power", "blackout", "spaced", "downed", "abort"] else str(event.kind)
		UiIcons.draw(self, icon_name, Vector2(ex, icon_y), 20.0 * b, _c(tint, a * draw_k))
	if head > 0.0 and head < 1.0:
		draw_circle(Vector2(head_x, line_y), 6.0 * b, _c(_color.lightened(0.5), 1.0))
	var start_label := "0:00"
	var small := int(16 * b)
	draw_string(bold, Vector2(x0, line_y + 22.0 * b), start_label, HORIZONTAL_ALIGNMENT_LEFT, -1, small, _c(UiStyle.FAINT, draw_k))
	var end_width := bold.get_string_size(total, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(bold, Vector2(x1 - end_width, line_y + 22.0 * b), total, HORIZONTAL_ALIGNMENT_LEFT, -1, small, _c(UiStyle.FAINT, draw_k))


func _timeline_row(text: String, colors: Dictionary) -> Control:
	var stamp := ""
	var body := text
	var split := text.find("  ")
	if split > 0:
		stamp = text.substr(0, split)
		body = text.substr(split + 2)
	var kind := timeline_kind(body)
	var key := kind in KEY_KINDS
	var tint := _kind_tint(kind)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = _c(tint, 0.13) if key else Color(0, 0, 0, 0)
	box.border_width_left = 3 if key else 0
	box.border_color = tint
	box.set_corner_radius_all(6)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var time_label := UiStyle.label(stamp, "bold", UiStyle.LABEL, UiStyle.FAINT if not key else tint.lightened(0.2))
	time_label.custom_minimum_size = Vector2(48, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(time_label)
	var icon_name := UiStyle.kind_icon(kind) if kind in ["power", "blackout", "spaced"] else kind
	row.add_child(UiIcon.make(icon_name, tint, 22))
	var words := RichTextLabel.new()
	words.bbcode_enabled = true
	words.fit_content = true
	words.scroll_active = false
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.custom_minimum_size = Vector2(maxf(120.0, _list.size.x - 24.0 - 140.0), 0)
	words.mouse_filter = Control.MOUSE_FILTER_PASS
	words.add_theme_font_size_override("normal_font_size", 22)
	words.add_theme_font_size_override("bold_font_size", 22)
	words.text = ("[b]%s[/b]" if key else "%s") % colorize_names(body, colors)
	row.add_child(words)
	panel.set_meta("words", words)
	return panel


func _kind_tint(kind: String) -> Color:
	match kind:
		"shove", "throw":
			return UiStyle.TEXT
		"crosshair", "downed":
			return UiStyle.AMBER
		"medbay":
			return UiStyle.GOOD
		"flag", "leave", "hand":
			return UiStyle.MUTED
	return UiStyle.kind_color(kind)


## Map a timeline sentence to an icon kind (ordered: the verb wins over objects).
static func timeline_kind(text: String) -> String:
	var t := text.to_lower()
	if t.begins_with("round started"):
		return "flag"
	if t.contains("shoved"):
		return "shove"
	if t.contains("threw") or (t.contains(" hit ") and t.contains(" with the ")):
		return "throw"
	if t.contains(" shot ") or t.contains("fired"):
		return "crosshair"
	if t.contains("spaced"):
		return "spaced"
	if t.contains("revived") or t.contains("got back up"):
		return "medbay"
	if t.contains("dragging"):
		return "hand"
	if t.contains("airlock") or t.contains("into space"):
		return "airlock"
	if t.contains("blackout"):
		return "blackout"
	if t.contains("power restored"):
		return "power"
	if t.contains("shuttle"):
		return "shuttle"
	if t.contains("cargo pod"):
		return "pod"
	if t.contains("disconnected"):
		return "leave"
	if t.contains("time ran out"):
		return "clock"
	if t.contains("no crew left"):
		return "downed"
	if t.contains("gun"):
		return "gun"
	if t.contains("core"):
		return "core"
	if t.contains("cell"):
		return "cell"
	return "info"


## Bold, suit-coloured player names inside a sentence (whole words only).
static func colorize_names(text: String, colors: Dictionary) -> String:
	var escaped := text.replace("[", "[lb]")
	var names := colors.keys()
	names.sort_custom(func(a, b): return str(a).length() > str(b).length())
	var spans := []  # [start, end, name]
	for player_name in names:
		var needle := str(player_name)
		if needle.is_empty():
			continue
		var from := 0
		while true:
			var at := escaped.find(needle, from)
			if at < 0:
				break
			var end := at + needle.length()
			var before_ok := at == 0 or not _is_word_char(escaped[at - 1])
			var after_ok := end >= escaped.length() or not _is_word_char(escaped[end])
			var overlaps := false
			for span in spans:
				if at < span[1] and end > span[0]:
					overlaps = true
			if before_ok and after_ok and not overlaps:
				spans.append([at, end, needle])
			from = end
	spans.sort_custom(func(a, b): return a[0] > b[0])
	for span in spans:
		var color: Color = colors[span[2]]
		var shown := color.lightened(0.2) if color.get_luminance() < 0.45 else color
		escaped = escaped.substr(0, span[0]) + "[b][color=#%s]%s[/color][/b]" % [shown.to_html(false), span[2]] + escaped.substr(span[1])
	return escaped


static func _is_word_char(character: String) -> bool:
	var code := character.unicode_at(0)
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code > 127
