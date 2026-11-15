class_name HudResult
extends PanelContainer
## End-of-round card: outcome banner with an icon, the infiltrator reveal with
## their suit colour, the round's timeline (icons + colour-coded names) and the
## rematch buttons. Buttons arrive after 1.5 s so a stray tap can't skip it.

signal again_pressed
signal leave_pressed

const WIDTH := 920.0
const BUTTON_GUARD := 1.5

var _emblem: Control
var _verdict: PanelContainer
var _verdict_icon: UiIcon
var _verdict_label: Label
var _title: Label
var _reason: Label
var _reveal: PanelContainer
var _reveal_face: Control
var _reveal_name: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _buttons: HBoxContainer
var _again: Button
var _waiting: HBoxContainer
var _waiting_dot: Control
var _time := 0.0


func _init() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.95, 28, 14))
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiStyle.S2)
	add_child(box)
	# Banner: emblem + verdict chip, title and reason.
	var banner := HBoxContainer.new()
	banner.add_theme_constant_override("separation", UiStyle.S3)
	box.add_child(banner)
	_emblem = UiStyle.emblem("trophy", UiStyle.CREW, 96)
	banner.add_child(_emblem)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(words)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", UiStyle.S2)
	words.add_child(top)
	top.add_child(UiStyle.label("ROUND OVER", "caps", UiStyle.LABEL, UiStyle.MUTED))
	_verdict = PanelContainer.new()
	_verdict.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var verdict_row := HBoxContainer.new()
	verdict_row.add_theme_constant_override("separation", 6)
	_verdict.add_child(verdict_row)
	_verdict_icon = UiIcon.make("check", UiStyle.INK, 16)
	verdict_row.add_child(_verdict_icon)
	_verdict_label = UiStyle.label("", "bold", UiStyle.CAPTION, UiStyle.INK)
	verdict_row.add_child(_verdict_label)
	top.add_child(_verdict)
	_title = UiStyle.label("", "title", 52, UiStyle.TEXT)
	words.add_child(_title)
	_reason = UiStyle.label("", "body", 22, UiStyle.MUTED)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_reason)
	# Infiltrator reveal.
	_reveal = PanelContainer.new()
	_reveal.add_theme_stylebox_override("panel", UiStyle.inset_box(0.34, 10, 12))
	box.add_child(_reveal)
	var reveal_row := HBoxContainer.new()
	reveal_row.add_theme_constant_override("separation", UiStyle.S2)
	_reveal.add_child(reveal_row)
	reveal_row.add_child(UiIcon.make("mask", UiStyle.INFILTRATOR, 28))
	var reveal_caption := UiStyle.label("THE INFILTRATOR WAS", "caps", UiStyle.LABEL, UiStyle.MUTED)
	reveal_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reveal_row.add_child(reveal_caption)
	_reveal_face = _face_swatch(Color.WHITE, 40)
	reveal_row.add_child(_reveal_face)
	_reveal_name = UiStyle.label("", "bold", 30, UiStyle.TEXT)
	_reveal_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reveal_row.add_child(_reveal_name)
	# Timeline.
	box.add_child(UiStyle.caption("WHAT HAPPENED", UiStyle.AMBER, "clock"))
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", UiStyle.inset_box(0.3, 10, 12))
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(inset)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	# Buttons (or a waiting note for non-hosts).
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", UiStyle.S2)
	box.add_child(_buttons)
	_waiting = HBoxContainer.new()
	_waiting.add_theme_constant_override("separation", 10)
	_waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting_dot = Control.new()
	_waiting_dot.custom_minimum_size = Vector2(14, 14)
	_waiting_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_waiting_dot.draw.connect(func():
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		_waiting_dot.draw_circle(Vector2(7, 7), 4.0 + 3.0 * pulse, UiStyle.with_alpha(UiStyle.ACCENT, 0.25 * (1.0 - pulse)))
		_waiting_dot.draw_circle(Vector2(7, 7), 4.0, UiStyle.ACCENT))
	_waiting.add_child(_waiting_dot)
	var waiting_label := UiStyle.label("Waiting for the host to start a rematch…", "body", 22, UiStyle.MUTED)
	waiting_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_waiting.add_child(waiting_label)
	_buttons.add_child(_waiting)
	var leave := UiStyle.button("LEAVE", false, UiStyle.ACCENT, "leave", 64)
	leave.custom_minimum_size.x = 176
	leave.pressed.connect(func(): leave_pressed.emit())
	_buttons.add_child(leave)
	_again = UiStyle.button("PLAY AGAIN", true, UiStyle.ACCENT, "play", 64)
	_again.custom_minimum_size.x = 256
	_again.pressed.connect(func(): again_pressed.emit())
	_buttons.add_child(_again)


func _process(delta: float) -> void:
	_time += delta
	if _waiting.visible:
		_waiting_dot.queue_redraw()


## A rounded suit-colour swatch with the LED face on it.
func _face_swatch(color: Color, side: float) -> Control:
	var out := Control.new()
	out.custom_minimum_size = Vector2(side, side)
	out.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	out.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	out.set_meta("color", color)
	out.draw.connect(func():
		var c: Color = out.get_meta("color")
		var box := UiStyle.pill_box(c, 1.0)
		box.set_corner_radius_all(int(side * 0.3))
		out.draw_style_box(box, Rect2(Vector2.ZERO, out.size))
		UiIcons.draw(out, "face", out.size * 0.5, side * 0.72, Color(0.02, 0.04, 0.08, 0.85)))
	return out


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
	var won := rules.winner != "" and rules.winner == role
	var nobody := rules.winner == "none" or rules.winner == ""
	add_theme_stylebox_override("panel", UiStyle.panel_box(color, 0.95, 28, 14))
	UiStyle.set_emblem(_emblem, icon_name, color if not nobody else UiStyle.TEXT)
	var verdict_color := UiStyle.GOOD if won else (UiStyle.MUTED if nobody else UiStyle.INFILTRATOR)
	_verdict.add_theme_stylebox_override("panel", UiStyle.pill_box(verdict_color, 0.95, 12, 2))
	_verdict_icon.icon = "check" if won else ("abort" if nobody else "close")
	_verdict_label.text = "YOU WON" if won else ("NOBODY WON" if nobody else "YOU LOST")
	_title.text = title
	_title.add_theme_color_override("font_color", color if not nobody else UiStyle.TEXT)
	_reason.text = rules.reason
	# Reveal: the infiltrator's suit colour comes from the roster by name.
	var colors := {}
	for id in rules.players:
		colors[str(rules.players[id].name)] = rules.players[id].color
	var infiltrator := rules.infiltrator_name
	_reveal.visible = infiltrator != "" and infiltrator != "nobody"
	_reveal_name.text = infiltrator
	_reveal_face.set_meta("color", colors.get(infiltrator, UiStyle.INFILTRATOR))
	_reveal_face.queue_redraw()
	# Timeline rows.
	for child in _rows.get_children():
		child.queue_free()
	var index := 0
	for line in rules.timeline:
		var row := _timeline_row(str(line), colors)
		var slot := UiMotion.slide(row)
		_rows.add_child(slot)
		if index < 12:
			slot.play_in(0.75 + index * 0.06, Vector2(-16, 0), 0.24)
		index += 1
	_again.visible = is_host
	_waiting.visible = not is_host
	# Choreography: card, title stamp, reveal (300 ms later), rows, buttons last.
	show()
	reset_size()
	UiMotion.card_in(self)
	_emblem.pivot_offset = _emblem.custom_minimum_size * 0.5
	UiMotion.pop(_emblem, 0.12, 0.6, 0.36)
	_title.pivot_offset = Vector2(0, _title.size.y * 0.5)
	UiMotion.pop(_title, 0.2, 1.25, 0.3)
	_reveal.modulate.a = 0.0
	UiMotion.fade(_reveal, 1.0, 0.3, 0.5)
	_buttons.modulate.a = 0.0
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _timeline_row(text: String, colors: Dictionary) -> Control:
	var stamp := ""
	var body := text
	var split := text.find("  ")
	if split > 0:
		stamp = text.substr(0, split)
		body = text.substr(split + 2)
	var kind := timeline_kind(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var time_label := UiStyle.label(stamp, "bold", UiStyle.LABEL, UiStyle.FAINT)
	time_label.custom_minimum_size = Vector2(48, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(time_label)
	var icon_name := UiStyle.kind_icon(kind) if kind in ["power", "blackout", "spaced"] else kind
	row.add_child(UiIcon.make(icon_name, _kind_tint(kind), 22))
	var words := RichTextLabel.new()
	words.bbcode_enabled = true
	words.fit_content = true
	words.scroll_active = false
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_PASS
	words.add_theme_font_size_override("normal_font_size", 22)
	words.add_theme_font_size_override("bold_font_size", 22)
	words.text = colorize_names(body, colors)
	row.add_child(words)
	return row


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
