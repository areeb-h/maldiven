class_name HudAlerts
extends Control
## Alert banners under the timer. New alerts slide down on top; at most
## MAX_VISIBLE show at once (the least important leaves early), each
## auto-dismisses. Every banner has a kind-coloured left stripe, a kind icon
## and words, so colour is never the only cue. Repeated text refreshes instead
## of stacking. Story beats (pod, blackout, power, spaced …) get the big
## banner: a kicker line, a heavier title, a sheen sweep and, for hazards, an
## animated striped edge.
##
## Standalone (production plan U4): `HudAlerts.create()` then
## `present("LIGHTS OUT", "danger", "blackout")`. Time runs on an internal
## clock: _process, or `step(delta)` / `set_progress(t)` (manual). With
## `fit_height` > 0 the banner scales to that share of the frame height.

const MAX_VISIBLE := 2
const HOLD := 3.2
const GAP := 8.0
const MAX_WIDTH := 560.0
const ENTER := 0.22
const LEAVE := 0.25
## Higher stays longer when the stack is full (docs/look-and-feel.md §3).
const PRIORITY := {"pod": 5, "danger": 5, "spaced": 4, "abort": 4, "power": 3, "shuttle": 3, "blackout": 2,
	"down": 2, "airlock": 2, "gun": 1, "info": 0}
const MAJOR := {"pod": "PRIORITY ALERT", "spaced": "AIRLOCK", "power": "STATION SYSTEMS", "shuttle": "DOCKING",
	"blackout": "POWER FAILURE", "danger": "POWER FAILURE", "abort": "LAUNCH CONTROL", "airlock": "AIRLOCK"}
const HAZARD := ["pod", "blackout", "danger", "airlock", "spaced"]

## Lowered to 1 while a centre countdown owns the upper third.
var max_visible := MAX_VISIBLE:
	set(value):
		max_visible = value
		_trim()
var manual := false
## Standalone: scale banners to this share of the frame height (0 = 1:1).
var fit_height := 0.0
## Standalone: hold time (s) before a banner leaves (<= 0 keeps it).
var hold := HOLD

var _clock := 0.0
var _items: Array = []  # {node, box, text, kind, born, until, leave_at, y, target, refresh}


static func create(opts := {}) -> HudAlerts:
	var out := HudAlerts.new()
	for key in opts:
		out.set(key, opts[key])
	return out


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Standalone entry point: show one banner (kind e.g. "danger", "pod",
## "power"; icon overrides the kind's icon).
func present(text: String, kind := "info", icon := "") -> void:
	push(text, kind, icon)


func push(text: String, kind: String, icon := "") -> void:
	for item in _items:
		if item.text == text and item.leave_at < 0.0:
			item.until = _clock + hold
			item.refresh = _clock
			return
	var item := _build(text, kind, icon)
	_items.push_front(item)
	_trim()
	_layout()


func set_progress(t: float) -> void:
	manual = true
	_advance(t - _clock)


func step(delta: float) -> void:
	manual = true
	_advance(delta)


## Over the limit: the least important, oldest banner leaves early.
func _trim() -> void:
	var live := _items.filter(func(entry): return entry.leave_at < 0.0)
	while live.size() > max_visible and live.size() > 1:
		var victim: Dictionary = {}
		for entry in live.slice(1):
			if victim.is_empty() or PRIORITY.get(entry.kind, 0) <= PRIORITY.get(victim.kind, 0):
				victim = entry
		victim.leave_at = _clock - (LEAVE - UiMotion.EXIT)
		live.erase(victim)
	_layout()


func clear() -> void:
	for item in _items:
		item.node.queue_free()
	_items.clear()


func _build(text: String, kind: String, icon := "") -> Dictionary:
	var color := UiStyle.kind_color(kind)
	var box := UiStyle.panel_box(color, 0.84, 0.0, 10)
	box.border_color = color
	box.set_border_width_all(0)
	box.content_margin_left = 16
	box.content_margin_right = 20
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_size = 12
	var major := MAJOR.has(kind)
	if major:
		box.content_margin_left = 20
		box.content_margin_bottom = 12
		box.bg_color = Color(color.r * 0.08, color.g * 0.08, color.b * 0.1, 0.9)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14 if major else 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon_name := icon if icon != "" else UiStyle.kind_icon(_icon_kind(text, kind))
	row.add_child(UiIcon.make(icon_name, color, 40 if major else 28))
	# "TITLE — detail" or "Title: detail" reads as a coloured title and a plain detail.
	var title := text
	var detail := ""
	for separator in [" — ", ": "]:
		var at := text.find(separator)
		if at > 0:
			title = text.substr(0, at)
			detail = text.substr(at + separator.length())
			break
	var words := RichTextLabel.new()
	words.bbcode_enabled = true
	words.fit_content = true
	words.autowrap_mode = TextServer.AUTOWRAP_OFF
	words.scroll_active = false
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_font_override("normal_font", UiStyle.font("body"))
	words.add_theme_font_override("bold_font", UiStyle.font("head") if major else UiStyle.font("bold"))
	words.add_theme_font_size_override("normal_font_size", 22)
	words.add_theme_font_size_override("bold_font_size", 22)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bb := "[b][color=#%s]%s[/color][/b]" % [color.lightened(0.25).to_html(false), _escape(title.to_upper())]
	if detail != "":
		bb += "  [color=#%s]%s[/color]" % [UiStyle.TEXT.to_html(false), _escape(detail.left(1).to_upper() + detail.substr(1))]
	words.text = bb
	var plain := title.to_upper() + "  " + detail
	var width := (UiStyle.font("head") if major else UiStyle.font("bold")).get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 8.0
	if width > MAX_WIDTH - 80.0:
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		width = MAX_WIDTH - 80.0
	words.custom_minimum_size = Vector2(width, 0)
	if major:
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var kicker := UiStyle.label(MAJOR[kind], "caps", 16, color.lightened(0.1))
		kicker.modulate.a = 0.8
		stack.add_child(kicker)
		stack.add_child(words)
		row.add_child(stack)
	else:
		row.add_child(words)
	add_child(panel)
	var item := {"node": panel, "box": box, "text": text, "kind": kind, "born": _clock,
		"until": _clock + hold + (0.8 if major else 0.0) if hold > 0.0 else INF,
		"leave_at": -1.0, "y": -16.0, "target": 0.0, "refresh": -99.0, "major": major}
	# Drawn over the panel's background, under its icon and words.
	panel.draw.connect(_draw_fx.bind(item))
	panel.reset_size()
	panel.modulate.a = 0.0
	return item


## Entry sheen (all banners) and hazard stripes on the left edge (hazards).
func _draw_fx(item: Dictionary) -> void:
	var panel: Control = item.node
	var age := _clock - float(item.born)
	var rect := Rect2(Vector2.ZERO, panel.size)
	var major: bool = item.major
	var sweep := clampf((age - 0.12) / (0.55 if major else 0.4), 0.0, 1.0)
	if sweep > 0.0 and sweep < 1.0:
		var x := lerpf(-60.0, rect.size.x + 60.0, sweep)
		var a := 0.22 if major else 0.12
		panel.draw_polygon(PackedVector2Array([Vector2(x - 30, 0), Vector2(x + 10, 0), Vector2(x - 10, rect.size.y), Vector2(x - 50, rect.size.y)]),
			PackedColorArray([Color(1, 1, 1, a), Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, a)]))
	if major and str(item.kind) in HAZARD:
		var step_px := 10.0
		var y := -step_px + fmod(age * 30.0, step_px * 2.0)
		var stripe := float((item.box as StyleBoxFlat).border_width_left)
		while y < rect.size.y:
			panel.draw_colored_polygon(PackedVector2Array([Vector2(0, y), Vector2(stripe, y - stripe), Vector2(stripe, y - stripe + step_px * 0.5),
				Vector2(0, y + step_px * 0.5)]), Color(0.05, 0.02, 0.02, 0.9))
			y += step_px * 2.0


func _icon_kind(text: String, kind: String) -> String:
	if kind == "info":
		var lower := text.to_lower()
		if lower.contains("cell") or lower.contains("restore power"):
			return "cell"
		if lower.contains("core"):
			return "core"
		if lower.contains("back on their feet"):
			return "medbay"
	return kind


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _layout() -> void:
	var y := 0.0
	for item in _items:
		if item.leave_at >= 0.0:
			continue
		item.target = y
		y += (item.node as Control).size.y + GAP


func _process(delta: float) -> void:
	if not manual:
		_advance(delta)


func _advance(delta: float) -> void:
	_clock += delta
	var blend := 1.0 - exp(-delta * 14.0) if not manual else 1.0
	var scale_all := 1.0
	if fit_height > 0.0 and get_viewport() != null:
		scale_all = get_viewport_rect().size.y * fit_height / 64.0
	for item in _items.duplicate():
		var node: Control = item.node
		var box: StyleBoxFlat = item.box
		var age := _clock - float(item.born)
		if item.leave_at < 0.0 and _clock >= float(item.until):
			item.leave_at = _clock
			_layout()
		var enter := UiType.ease_out(age / ENTER)
		var alpha := enter
		var shift := 0.0
		if item.leave_at >= 0.0:
			var gone := (_clock - float(item.leave_at)) / LEAVE
			if gone >= 1.0:
				_items.erase(item)
				node.queue_free()
				_layout()
				continue
			alpha *= 1.0 - UiType.ease_in_out(gone)
			shift = 12.0 * gone
		node.modulate.a = alpha
		var stripe := int(round(6.0 * UiType.ease_out((age - 0.06) / 0.26)))
		if box.border_width_left != stripe:
			box.border_width_left = stripe
		var pop := 1.0 + 0.06 * (1.0 - clampf((_clock - float(item.refresh)) / 0.18, 0.0, 1.0))
		node.scale = Vector2.ONE * scale_all * pop
		node.pivot_offset = Vector2(node.size.x * 0.5, 0)
		item.y = lerpf(float(item.y), float(item.target) * scale_all, blend) if item.leave_at < 0.0 else item.y
		node.position = Vector2((size.x - node.size.x) * 0.5 + shift, item.y - 16.0 * (1.0 - enter))
		if age < 1.6:
			node.queue_redraw()
