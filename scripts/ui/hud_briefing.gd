class_name HudBriefing
extends PanelContainer
## Private role card shown during the ~6 s briefing.
## Choreography (docs/look-and-feel.md §4): card fades in, "YOUR ROLE" caption,
## the emblem and title flip in with a back ease, objective lines stagger in
## 120 ms apart, then the card flies into the role chip to teach where the
## role lives. Identical timing for both roles.

const WIDTH := 720.0

var _caption: Label
var _emblem: Control
var _title: Label
var _lines: VBoxContainer
var _footer: Label
var _bar: Control
var _fraction := 1.0
var _role := ""
var _tween: Tween
var leaving := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.92, 32, 14))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiStyle.S2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_caption = UiStyle.label("YOUR ROLE", "caps", UiStyle.LABEL, UiStyle.MUTED)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_caption)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", UiStyle.S3)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	_emblem = UiStyle.emblem("shield", UiStyle.CREW, 88)
	head.add_child(_emblem)
	_title = UiStyle.label("", "title", 56, UiStyle.CREW)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 10)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_lines)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", UiStyle.S1)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(footer)
	_footer = UiStyle.label("", "bold", UiStyle.LABEL, UiStyle.MUTED)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(_footer)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(func():
		var full := Rect2(Vector2.ZERO, _bar.size)
		_bar.draw_rect(full, Color(1, 1, 1, 0.08))
		var color := UiStyle.role_color(_role)
		_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(_bar.size.x * _fraction, _bar.size.y)), color))
	footer.add_child(_bar)
	custom_minimum_size = Vector2(WIDTH, 0)


func set_role(role: String) -> void:
	_role = role
	var infiltrator := role == StationRules.INFILTRATOR
	var color := UiStyle.role_color(role)
	add_theme_stylebox_override("panel", UiStyle.panel_box(color, 0.92, 32, 14))
	UiStyle.set_emblem(_emblem, UiStyle.role_icon(role), color)
	_title.text = "INFILTRATOR" if infiltrator else "CREW"
	_title.add_theme_color_override("font_color", color)
	for child in _lines.get_children():
		child.queue_free()
	var lines := [
		["cell", UiStyle.AMBER, "Help restore power so the vault in Command opens."],
		["pod", UiStyle.INFILTRATOR, "Steal the core and arm the cargo pod in Cargo."],
		["blackout", UiStyle.AMBER, "Blend in. Kill the lights when it helps."],
	] if infiltrator else [
		["cell", UiStyle.AMBER, "Bring 3 power cells to the Reactor."],
		["vault", UiStyle.ACCENT, "When the vault in Command opens, take the core."],
		["shuttle", UiStyle.CREW, "Load it into the shuttle in Docking. One of you is lying."],
	]
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiStyle.S2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiStyle.pill_box(line[1], 0.14, 6, 6))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(UiIcon.make(line[0], line[1], 26))
		row.add_child(chip)
		var text := UiStyle.label(line[2], "body", UiStyle.BODY, UiStyle.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(WIDTH - 64.0 - 42.0 - 16.0, 0)
		row.add_child(text)
		_lines.add_child(UiMotion.slide(row))


func set_seconds_left(left: float, total: float) -> void:
	_footer.text = "Round starts in %d" % int(ceil(maxf(left, 0.0)))
	_fraction = clampf(left / maxf(total, 0.01), 0.0, 1.0)
	_bar.queue_redraw()


func play_in() -> void:
	leaving = false
	show()
	reset_size()
	if _tween != null:
		_tween.kill()
	pivot_offset = size * 0.5
	scale = Vector2(0.96, 0.96)
	modulate.a = 0.0
	_caption.modulate.a = 0.0
	_emblem.pivot_offset = _emblem.custom_minimum_size * 0.5
	_emblem.scale = Vector2(0.0, 1.0)
	_title.modulate.a = 0.0
	_footer.modulate.a = 0.0
	_bar.modulate.a = 0.0
	for slot in _lines.get_children():
		(slot as Control).modulate.a = 0.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_caption, "modulate:a", 1.0, 0.25).set_delay(0.3)
	_tween.tween_property(_emblem, "scale", Vector2.ONE, 0.32).set_delay(0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_title, "modulate:a", 1.0, 0.25).set_delay(0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var delay := 1.0
	for slot in _lines.get_children():
		(slot as UiMotion.Slide).play_in(delay, Vector2(0, 16))
		delay += 0.12
	_tween.tween_property(_footer, "modulate:a", 1.0, 0.25).set_delay(delay)
	_tween.tween_property(_bar, "modulate:a", 1.0, 0.25).set_delay(delay)


## Shrink into the role chip (400 ms, quint in-out), then hide.
func fly_to(target: Vector2, done: Callable) -> void:
	if leaving or not visible:
		return
	leaving = true
	if _tween != null:
		_tween.kill()
	pivot_offset = size * 0.5
	var travel := target - (global_position + size * 0.5)
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "position", position + travel, 0.42).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", Vector2(0.07, 0.07), 0.42).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(0.24)
	_tween.chain().tween_callback(func():
		hide()
		leaving = false
		done.call())
