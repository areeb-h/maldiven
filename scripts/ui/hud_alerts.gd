class_name HudAlerts
extends Control
## Queued alert banners under the timer. New alerts slide down on top; at most
## MAX_VISIBLE show at once (the oldest leaves early), each auto-dismisses.
## Every banner has a kind-coloured left stripe, a kind icon and words, so
## colour is never the only cue. Repeated text refreshes instead of stacking.

const MAX_VISIBLE := 2
const HOLD := 3.2
const GAP := 8.0
const MAX_WIDTH := 560.0
## Higher stays longer when the stack is full (docs/look-and-feel.md §3).
const PRIORITY := {"pod": 5, "spaced": 4, "abort": 4, "power": 3, "shuttle": 3, "blackout": 2,
	"down": 2, "airlock": 2, "gun": 1, "info": 0}

var _items: Array = []  # {node, stripe, text, kind, life, y, leaving}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push(text: String, kind: String) -> void:
	for item in _items:
		if item.text == text and not item.leaving:
			item.life = HOLD
			UiMotion.pop(item.node, 0.0, 1.06, 0.18)
			return
	var item := _build(text, kind)
	_items.push_front(item)
	var visible_items := _items.filter(func(entry): return not entry.leaving)
	if visible_items.size() > MAX_VISIBLE:
		# Drop the least important, oldest banner.
		var victim: Dictionary = {}
		for entry in visible_items.slice(1):
			if victim.is_empty() or PRIORITY.get(entry.kind, 0) <= PRIORITY.get(victim.kind, 0):
				victim = entry
		_leave(victim, UiMotion.EXIT)
	_layout(true)


func clear() -> void:
	for item in _items:
		item.node.queue_free()
	_items.clear()


func _build(text: String, kind: String) -> Dictionary:
	var color := UiStyle.kind_color(kind)
	var box := UiStyle.panel_box(color, 0.84, 0.0, 10)
	box.border_color = color
	box.set_border_width_all(0)
	box.border_width_left = 0
	box.content_margin_left = 16
	box.content_margin_right = 20
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_size = 12
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	row.add_child(UiIcon.make(UiStyle.kind_icon(_icon_kind(text, kind)), color, 28))
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
	words.add_theme_font_override("bold_font", UiStyle.font("bold"))
	words.add_theme_font_size_override("normal_font_size", 22)
	words.add_theme_font_size_override("bold_font_size", 22)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bb := "[b][color=#%s]%s[/color][/b]" % [color.lightened(0.25).to_html(false), _escape(title.to_upper())]
	if detail != "":
		bb += "  [color=#%s]%s[/color]" % [UiStyle.TEXT.to_html(false), _escape(detail.left(1).to_upper() + detail.substr(1))]
	words.text = bb
	var plain := title.to_upper() + "  " + detail
	var width := UiStyle.font("bold").get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 8.0
	if width > MAX_WIDTH - 80.0:
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		width = MAX_WIDTH - 80.0
	words.custom_minimum_size = Vector2(width, 0)
	row.add_child(words)
	add_child(panel)
	panel.reset_size()
	panel.modulate.a = 0.0
	var item := {"node": panel, "stripe": box, "text": text, "kind": kind, "life": HOLD, "y": -16.0, "leaving": false}
	# Enter: slide down 16 px, fade in, stripe grows 0 -> 6 px.
	var tween := panel.create_tween().set_parallel()
	tween.tween_property(panel, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "border_width_left", 6, 0.26).set_delay(0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return item


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


func _leave(item: Dictionary, seconds := 0.25) -> void:
	if item.leaving:
		return
	item.leaving = true
	var node: Control = item.node
	var tween := node.create_tween().set_parallel()
	tween.tween_property(node, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "position:x", node.position.x + 12.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		_items.erase(item)
		node.queue_free()
		_layout(false))


func _layout(_snap_new: bool) -> void:
	var y := 0.0
	for item in _items:
		if item.leaving:
			continue
		item.target = y
		y += (item.node as Control).size.y + GAP


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-delta * 14.0)
	for item in _items.duplicate():
		var node: Control = item.node
		node.position.x = (size.x - node.size.x) * 0.5 if not item.leaving else node.position.x
		if not item.leaving:
			item.y = lerpf(item.y, item.get("target", 0.0), blend)
			node.position.y = item.y
			item.life -= delta
			if item.life <= 0.0:
				_leave(item)
