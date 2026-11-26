class_name HudResult
extends Control
## End-of-round screen with a staged reveal (production plan U2):
##   0.0  the outcome snaps in ("CREW ESCAPED"), with the verdict chip
##   0.6  "THE INFILTRATOR WAS" and a slot that cycles every player's helmet
##        and name at 12 a second
##   1.4  the slot lands, a hard stop: their helmet, their name in their suit
##        colour, one white frame behind it
##   1.8  the timeline cascades in, 60 ms a row. Rows that were anonymous
##        during the round ("Someone triggered a blackout") flip to the name,
##        with a small red marker. The row where it went wrong gets a chip
##        ("ZARA WAS CREW").
##   2.2  the buttons arrive (a stray tap can't skip the reveal); PLAY AGAIN
##        pulses once a second.
## Standalone: `present(data)` takes plain data (see from_rules() for the
## keys); time runs in real time, or from `set_progress(t)` / `step(delta)`
## (manual, for the trailer). layout "full" (the game) or "reveal" (the slot
## and a few rows, full frame).

signal again_pressed
signal leave_pressed

const BUTTON_GUARD := 2.2
const BARS := 0.07
const REVEAL_AT := 0.6
const LAND_AT := 1.4
const ROWS_AT := 1.8
const ROW_STAGGER := 0.06
const FLIP_DELAY := 0.35
const SLOT_RATE := 12.0
## Timeline kinds that become markers on the story track and get a highlight.
const KEY_KINDS := ["power", "blackout", "crosshair", "spaced", "shuttle", "pod", "downed", "clock", "abort"]

var data := {}
var manual := false

var _t := 0.0
var _rows_data: Array = []
var _row_nodes: Array = []  # {slot: Control, label: RichTextLabel, flipped}
var _end_seconds := 1.0
var _last_slot := -1
var _landed := false

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
	_list.add_theme_stylebox_override("panel", UiStyle.inset_box(0.4, 12, 10))
	add_child(_list)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
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


# --- Data ------------------------------------------------------------------------

## Plain data for present() from a finished round.
static func from_rules(rules: StationRules, role: String, is_host: bool) -> Dictionary:
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
		title = "CORE STOLEN" if rules.reason.contains("pod") else "INFILTRATOR WINS"
		color = UiStyle.INFILTRATOR
		icon_name = "pod" if rules.reason.contains("pod") else "mask"
	elif rules.reason.contains("No crew"):
		icon_name = "downed"
	var won := rules.winner != "" and rules.winner == role
	var nobody := rules.winner == "none" or rules.winner == ""
	var players := []
	var colors := {}
	for id in rules.players:
		players.append({"name": str(rules.players[id].name), "color": rules.players[id].color})
		colors[str(rules.players[id].name)] = rules.players[id].color
	var infiltrator := rules.infiltrator_name if rules.infiltrator_name != "nobody" else ""
	return {
		"title": title, "color": color if not nobody else UiStyle.TEXT, "icon": icon_name, "reason": rules.reason,
		"verdict": "YOU WON" if won else ("NOBODY WON" if nobody else "YOU LOST"),
		"verdict_color": UiStyle.GOOD if won else (UiStyle.MUTED if nobody else UiStyle.INFILTRATOR),
		"infiltrator": {"name": infiltrator, "color": colors.get(infiltrator, UiStyle.INFILTRATOR)},
		"players": players, "rows": story_rows(rules.timeline, infiltrator, colors.keys()), "host": is_host,
	}


## Timeline lines ("m:ss  text") -> rows with the live anonymity and the
## turning-point tags worked out: [{time, text, anon, tag, tag_color}].
static func story_rows(timeline: Array, infiltrator: String, names: Array) -> Array:
	var rows := []
	var dark_until := -1.0
	for line in timeline:
		var text := str(line)
		var cut := text.find("  ")
		var seconds := stamp_seconds(text.substr(0, cut)) if cut > 0 else 0.0
		var body := text.substr(cut + 2) if cut > 0 else text
		var row := {"time": seconds, "text": body, "anon": "", "tag": "", "tag_color": UiStyle.INFILTRATOR}
		var actor := ""
		for player_name in names:
			if body.begins_with(str(player_name) + " "):
				actor = str(player_name)
		var lower := body.to_lower()
		if lower.contains("triggered a blackout"):
			dark_until = seconds + StationRules.BLACKOUT_SECONDS
			row.anon = actor
		elif actor != "" and seconds <= dark_until and not lower.contains("disconnected"):
			row.anon = actor  # it happened in the dark: nobody saw who
		if lower.ends_with("was spaced."):
			for player_name in names:
				if body.begins_with(str(player_name) + " "):
					var crew := str(player_name) != infiltrator
					row.tag = ("%s WAS CREW" if crew else "%s WAS THE INFILTRATOR") % str(player_name).to_upper()
					row.tag_color = UiStyle.INFILTRATOR if crew else UiStyle.GOOD
		rows.append(row)
	return rows


static func stamp_seconds(stamp: String) -> float:
	var parts := stamp.strip_edges().split(":")
	if parts.size() != 2:
		return 0.0
	return float(parts[0].to_int() * 60 + parts[1].to_int())


static func stamp(seconds: float) -> String:
	var s := int(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


func show_result(rules: StationRules, role: String, is_host: bool) -> void:
	present(from_rules(rules, role, is_host))


func present(next: Dictionary) -> void:
	data = next
	_t = 0.0
	_landed = false
	_last_slot = -1
	_rows_data = data.get("rows", [])
	_end_seconds = 1.0
	for row in _rows_data:
		_end_seconds = maxf(_end_seconds, float(row.time))
	for child in _rows.get_children():
		child.queue_free()
	for entry in _row_nodes:
		if is_instance_valid(entry.slot) and (entry.slot as Node).get_parent() == self:
			(entry.slot as Node).queue_free()
	_row_nodes.clear()
	var colors := _colors()
	for row in _rows_data:
		var kind := timeline_kind(str(row.text))
		var key: bool = kind in KEY_KINDS or str(row.tag) != ""
		var shown := _anon_text(row) if str(row.anon) != "" else str(row.text)
		var node := make_row(float(row.time), row_icon(kind), colorize_names(shown, colors), 22, key, kind_tint(kind), false)
		if str(row.tag) != "":
			var chip := UiStyle.chip(str(row.tag), row.tag_color, "mask" if row.tag_color == UiStyle.GOOD else "warning")
			chip.set_meta("tag", true)
			node.get_child(0).add_child(chip)
		var slot := UiMotion.slide(node)
		if str(data.get("layout", "full")) == "full":
			(node.get_meta("words") as RichTextLabel).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_rows.add_child(slot)
		else:
			add_child(slot)
		_row_nodes.append({"slot": slot, "label": node.get_meta("words"), "flipped": false, "row": row})
	var host: bool = data.get("host", true)
	_again.visible = host
	_waiting.visible = not host
	_buttons.visible = bool(data.get("buttons", true))
	_list.visible = str(data.get("layout", "full")) == "full"
	show()
	_layout()
	set_process(true)
	_apply(0.0)


func set_progress(t: float) -> void:
	manual = true
	_t = t
	_apply(t)


func step(delta: float) -> void:
	manual = true
	_t += delta
	_apply(_t)


func seek(t: float) -> void:
	set_progress(t)


func _process(delta: float) -> void:
	if not manual:
		_t += delta
		_apply(_t)
	if _waiting.visible:
		_waiting_dot.queue_redraw()


func _colors() -> Dictionary:
	var colors := {}
	for player in data.get("players", []):
		colors[str(player.name)] = player.color
	return colors


func _anon_text(row: Dictionary) -> String:
	var actor := str(row.anon)
	return "Someone" + str(row.text).substr(actor.length())


## Everything that depends on time: rows, flips, buttons, sounds.
func _apply(t: float) -> void:
	var colors := _colors()
	for i in range(_row_nodes.size()):
		var entry: Dictionary = _row_nodes[i]
		var slot: UiMotion.Slide = entry.slot
		var at := float(data.get("rows_at", ROWS_AT)) + i * ROW_STAGGER
		var k := UiType.ease_out((t - at) / 0.24) if i < 16 else (1.0 if t > at else 0.0)
		slot.modulate.a = k
		slot.shift = Vector2(-16.0 * (1.0 - k), 0)
		var row: Dictionary = entry.row
		if str(row.anon) != "":
			var flip := t >= at + FLIP_DELAY
			if flip != bool(entry.flipped):
				entry.flipped = flip
				var label: RichTextLabel = entry.label
				label.text = (_marker() + colorize_names(str(row.text), colors)) if flip else colorize_names(_anon_text(row), colors)
				if flip and not manual:
					UiMotion.haptic(15)
		for child in (slot.get_child(0).get_child(0) as Control).get_children():
			if child.has_meta("tag"):
				var pop := UiType.ease_back((t - at - 0.25) / 0.25)
				(child as Control).pivot_offset = (child as Control).size * 0.5
				(child as Control).scale = Vector2.ONE * maxf(0.01, pop)
				(child as Control).modulate.a = clampf(pop, 0.0, 1.0)
	if str(data.get("layout", "full")) == "reveal":
		# Rows centred under the slot (the trailer's S31).
		var y := size.y * 0.66
		for i in range(_row_nodes.size()):
			var slot: Control = _row_nodes[i].slot
			slot.visible = i < 3
			slot.reset_size()
			slot.position = Vector2((size.x - slot.size.x) * 0.5, y)
			y += slot.size.y + 10.0
	# Buttons after the guard; PLAY AGAIN pulses once a second.
	var ready := t >= BUTTON_GUARD
	_buttons.modulate.a = UiType.ease_out((t - BUTTON_GUARD) / 0.25)
	for child in _buttons.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not ready
	var beat := fmod(maxf(t - BUTTON_GUARD, 0.0), 1.0)
	var swell := exp(-beat * 7.0) if ready else 0.0
	_again.pivot_offset = _again.size * 0.5
	_again.scale = Vector2.ONE * (1.0 + 0.05 * swell)
	_again.modulate = Color(1.0 + 0.2 * swell, 1.0 + 0.2 * swell, 1.0 + 0.2 * swell)
	# Slot sounds (game only; the trailer mixes its own cue sheet).
	var players: Array = data.get("players", [])
	if not manual and not players.is_empty():
		var index := int(floor((t - REVEAL_AT) * SLOT_RATE))
		if t >= REVEAL_AT and t < LAND_AT and index != _last_slot:
			_last_slot = index
			UiMotion.sound(self, "slot_tick" if ResourceLoader.exists("res://assets/audio/slot_tick.wav") else "ui_click", -12.0, 1.3)
		if t >= LAND_AT and not _landed:
			_landed = true
			UiMotion.sound(self, "slot_stop" if ResourceLoader.exists("res://assets/audio/slot_stop.wav") else "insert_cell", -4.0, 0.55)
			UiMotion.haptic(30)
	queue_redraw()


static func _marker() -> String:
	return "[color=#%s][b]»[/b][/color] " % UiStyle.INFILTRATOR.to_html(false)


# --- Layout ----------------------------------------------------------------------

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
	var top := bar + 30.0 * b
	var bottom := size.y - bar - 20.0 * b
	var button_h := 80.0
	if _portrait():
		var w := size.x * 0.86
		var x := size.x * 0.07
		_left_rect = Rect2(x, top, w, size.y * 0.4)
		_right_rect = Rect2(x, _left_rect.end.y + 24.0 * b, w, bottom - _left_rect.end.y - 24.0 * b)
	else:
		_left_rect = Rect2(size.x * 0.055, top, size.x * 0.41, bottom - top)
		_right_rect = Rect2(size.x * 0.5, top, size.x * 0.445, bottom - top)
	_track_rect = Rect2(_right_rect.position + Vector2(0, 36.0 * b), Vector2(_right_rect.size.x, 60.0 * b))
	var list_top := _track_rect.end.y + 12.0 * b
	var list_bottom := _right_rect.end.y - (button_h + 14.0 if _buttons.visible else 0.0)
	_list.position = Vector2(_right_rect.position.x, list_top)
	_list.size = Vector2(_right_rect.size.x, maxf(80.0, list_bottom - list_top))
	_buttons.position = Vector2(_right_rect.position.x, _right_rect.end.y - button_h)
	_buttons.size = Vector2(_right_rect.size.x, button_h)
	if str(data.get("layout", "full")) != "full":
		return
	for entry in _row_nodes:
		var label: RichTextLabel = entry.label
		label.custom_minimum_size.x = maxf(120.0, _list.size.x - 24.0 - 140.0)


# --- Drawing ---------------------------------------------------------------------

func _c(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(a, 0.0, 1.0))


func _draw() -> void:
	if size.x <= 0.0 or data.is_empty():
		return
	var b := _base()
	var t := _t
	var color: Color = data.get("color", UiStyle.CREW)
	var snap := clampf(t / 0.1, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.01, 0.03, 0.82 * snap))
	var clear := _c(color, 0.0)
	if _portrait():
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y * 0.5), Vector2(0, size.y * 0.5)]),
			PackedColorArray([_c(color, 0.18 * snap), _c(color, 0.18 * snap), clear, clear]))
	else:
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x * 0.55, 0), Vector2(size.x * 0.55, size.y), Vector2(0, size.y)]),
			PackedColorArray([_c(color, 0.2 * snap), clear, clear, _c(color, 0.2 * snap)]))
	var bar := size.y * BARS
	draw_rect(Rect2(0, 0, size.x, bar), Color.BLACK)
	draw_rect(Rect2(0, size.y - bar, size.x, bar), Color.BLACK)
	if str(data.get("layout", "full")) == "reveal":
		var area := Rect2(size.x * 0.08, bar, size.x * 0.84, size.y - bar * 2.0)
		_draw_slot(b * 1.5, Vector2(area.get_center().x, area.position.y + area.size.y * 0.42), true)
		return
	# Logo, small, top of the left column.
	var logo_h := 30.0 * b
	UiLogo.draw(self, "wordmark", _left_rect.position, logo_h, "dark", 0.85 * snap)
	var y := _draw_outcome(b, _left_rect.position.y + logo_h + 26.0 * b)
	_draw_slot(b, Vector2(_left_rect.position.x, y + 30.0 * b), false)
	_draw_story(b)


func _draw_outcome(b: float, top: float) -> float:
	var t := _t
	var snap := clampf(t / 0.1, 0.0, 1.0)
	var x := _left_rect.position.x
	var color: Color = data.get("color", UiStyle.CREW)
	var caps := UiStyle.font("caps")
	var kicker_size := int(20 * b)
	draw_string(caps, Vector2(x, top + kicker_size), "ROUND OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, kicker_size, _c(UiStyle.MUTED, snap))
	var kicker_width := caps.get_string_size("ROUND OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, kicker_size).x
	var verdict := str(data.get("verdict", ""))
	if verdict != "":
		var bold := UiStyle.font("bold")
		var chip_size := int(18 * b)
		var verdict_color: Color = data.get("verdict_color", UiStyle.GOOD)
		var text_width := bold.get_string_size(verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x
		var chip := Rect2(x + kicker_width + 16.0 * b, top - 2.0 * b, text_width + 46.0 * b, kicker_size + 12.0 * b)
		var pop := UiType.ease_back((t - 0.2) / 0.25)
		if pop > 0.0:
			var center := chip.get_center()
			var scaled := Rect2(center - chip.size * 0.5 * pop, chip.size * pop)
			draw_style_box(UiStyle.pill_box(verdict_color, 0.95 * clampf(pop, 0.0, 1.0)), scaled)
			if pop > 0.8:
				var icon_name := "check" if verdict == "YOU WON" else ("abort" if verdict == "NOBODY WON" else "close")
				UiIcons.draw(self, icon_name, Vector2(chip.position.x + 16.0 * b, center.y), 16.0 * b, UiStyle.INK)
				draw_string(bold, Vector2(chip.position.x + 30.0 * b, center.y + chip_size * 0.36), verdict,
					HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size, UiStyle.INK)
	# The outcome in two big lines, snapped in.
	var title := str(data.get("title", ""))
	var split := title.find(" ")
	var lines := [title.substr(0, split), title.substr(split + 1)] if split > 0 else [title]
	var head := UiStyle.font("title")
	var size_title := int(84 * b)
	for line in lines:
		size_title = mini(size_title, UiType.fit_size(head, str(line), int(84 * b), _left_rect.size.x, 3.0 * b))
	var line_y := top + kicker_size + 20.0 * b + size_title * 0.8
	var grow := 1.0 + 0.04 * (1.0 - snap)
	for line in lines:
		draw_set_transform(Vector2(x, line_y), 0.0, Vector2.ONE * grow)
		draw_string_outline(head, Vector2.ZERO, str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, size_title, maxi(4, int(size_title * 0.3)),
			_c(color, 0.16 * snap))
		draw_string(head, Vector2.ZERO, str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, size_title, _c(color, snap))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		line_y += size_title * 0.98
	var reason_k := UiType.ease_out((t - 0.25) / 0.3)
	var used := UiType.draw_wrapped(self, UiStyle.font("body"), str(data.get("reason", "")),
		Vector2(x, line_y - size_title * 0.62 + 14.0 * b), _left_rect.size.x, int(24 * b), _c(UiStyle.MUTED.lightened(0.2), reason_k),
		HORIZONTAL_ALIGNMENT_LEFT, 2)
	return line_y - size_title * 0.62 + 14.0 * b + used


## THE INFILTRATOR WAS + the slot. `at` is the top-left (or the centre when
## `centered`).
func _draw_slot(b: float, at: Vector2, centered: bool) -> void:
	var infiltrator: Dictionary = data.get("infiltrator", {})
	var players: Array = data.get("players", [])
	if str(infiltrator.get("name", "")) == "" or players.is_empty():
		return
	var t := _t - REVEAL_AT
	if t < 0.0:
		return
	var caps := UiStyle.font("caps")
	var kicker := "THE INFILTRATOR WAS"
	var kicker_size := int(20 * b)
	var tile := 112.0 * b
	var head := UiStyle.font("title")
	var name_size := int(52 * b)
	var landed := _t >= LAND_AT
	var who: Dictionary = infiltrator
	if not landed:
		var index := int(floor(t * SLOT_RATE))
		# Start the cycle away from the answer.
		who = players[(index + 1 + players.size() / 2) % players.size()]
	var shown_name := str(who.get("name", "")).to_upper()
	var suit: Color = who.get("color", UiStyle.INFILTRATOR)
	var kicker_width := UiType.tracked_width(caps, kicker, kicker_size, 3.0 * b)
	var name_width := head.get_string_size(shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	var origin := at
	if centered:
		var block_width := maxf(kicker_width, tile + 24.0 * b + maxf(name_width, 300.0 * b))
		origin = at - Vector2(block_width * 0.5, (kicker_size + 16.0 * b + tile) * 0.5)
	UiType.draw_type_on(self, caps, kicker, origin + Vector2(0, kicker_size), kicker_size, UiStyle.INFILTRATOR.lightened(0.15),
		t, 60.0, "left", 3.0 * b, 0.0)
	var tile_rect := Rect2(origin + Vector2(0, kicker_size + 16.0 * b), Vector2(tile, tile))
	# One white frame behind the landed slot.
	var since := _t - LAND_AT
	if landed and since < 1.0 / 30.0:
		draw_rect(Rect2(tile_rect.position - Vector2(24, 24) * b, Vector2(tile + 48.0 * b + 24.0 * b + name_width + 24.0 * b, tile + 48.0 * b)), Color.WHITE)
	var plate := UiStyle.pill_box(suit, 1.0)
	plate.set_corner_radius_all(int(tile * 0.22))
	draw_style_box(plate, tile_rect)
	UiIcons.draw(self, "face", tile_rect.get_center(), tile * 0.74, Color(0.02, 0.04, 0.08, 0.88))
	if not landed:
		# Slot-machine blur: the tile's edges streak.
		draw_rect(Rect2(tile_rect.position + Vector2(0, -6.0 * b), Vector2(tile, 4.0 * b)), _c(suit, 0.4))
		draw_rect(Rect2(tile_rect.position + Vector2(0, tile + 2.0 * b), Vector2(tile, 4.0 * b)), _c(suit, 0.4))
	else:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(maxi(2, int(3 * b)))
		ring.border_color = _c(suit.lightened(0.45), 1.0 - clampf(since / 0.6, 0.0, 0.7))
		ring.set_corner_radius_all(int(tile * 0.26))
		ring.anti_aliasing = true
		draw_style_box(ring, tile_rect.grow(6.0 * b))
	var shown := suit.lightened(0.25) if suit.get_luminance() < 0.42 else suit
	var name_at := Vector2(tile_rect.end.x + 24.0 * b, tile_rect.get_center().y + name_size * 0.2)
	draw_string_outline(head, name_at, shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, maxi(4, int(name_size * 0.28)),
		_c(shown, 0.18 if landed else 0.0))
	draw_string(head, name_at, shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, shown if landed else _c(shown, 0.75))
	if landed:
		var chip_k := UiType.ease_out((since - 0.15) / 0.2)
		if chip_k > 0.0:
			var bold := UiStyle.font("bold")
			var chip_size := int(18 * b)
			var label := "INFILTRATOR"
			var w := bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x + 44.0 * b
			var chip := Rect2(name_at + Vector2(0, 16.0 * b), Vector2(w, chip_size + 14.0 * b))
			var box := UiStyle.tag_box(UiStyle.INFILTRATOR, 12, 2)
			box.bg_color = _c(UiStyle.INFILTRATOR, 0.18 * chip_k)
			box.border_color = _c(UiStyle.INFILTRATOR, 0.8 * chip_k)
			draw_style_box(box, chip)
			UiIcons.draw(self, "mask", Vector2(chip.position.x + 16.0 * b, chip.get_center().y), 18.0 * b, _c(UiStyle.INFILTRATOR, chip_k))
			draw_string(bold, Vector2(chip.position.x + 30.0 * b, chip.get_center().y + chip_size * 0.36), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size, _c(UiStyle.INFILTRATOR.lightened(0.2), chip_k))


func _draw_story(b: float) -> void:
	var t := _t
	var caps := UiStyle.font("caps")
	var cap_size := int(20 * b)
	var k := UiType.ease_out((t - ROWS_AT + 0.3) / 0.2)
	if k <= 0.0:
		return
	var color: Color = data.get("color", UiStyle.CREW)
	var head_pos := _right_rect.position + Vector2(0, cap_size)
	UiIcons.draw(self, "clock", head_pos + Vector2(10.0 * b, -cap_size * 0.36), 20.0 * b, _c(UiStyle.AMBER, k))
	draw_string(caps, head_pos + Vector2(28.0 * b, 0), "HOW IT HAPPENED", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size, _c(UiStyle.AMBER, k))
	var total := stamp(_end_seconds)
	var bold := UiStyle.font("bold")
	var total_width := bold.get_string_size(total, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size).x
	draw_string(bold, Vector2(_right_rect.end.x - total_width, head_pos.y), total, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size,
		_c(UiStyle.FAINT, k))
	# The story track: the round as a line, key moments as markers, filled by
	# a playhead as the rows cascade.
	var line_y := _track_rect.position.y + _track_rect.size.y * 0.66
	var x0 := _track_rect.position.x + 8.0 * b
	var x1 := _track_rect.end.x - 8.0 * b
	draw_rect(Rect2(x0, line_y - 1.5, x1 - x0, 3.0), _c(Color.WHITE, 0.16 * k))
	var cascade := ROW_STAGGER * maxf(1.0, float(_row_nodes.size()))
	var head := clampf((t - ROWS_AT) / maxf(0.6, cascade), 0.0, 1.0)
	var head_x := lerpf(x0, x1, UiType.ease_in_out(head))
	if head > 0.0:
		draw_rect(Rect2(x0, line_y - 1.5, head_x - x0, 3.0), _c(color, 0.9))
	var last_x := -1000.0
	var lift := 0
	for row in _rows_data:
		var kind := timeline_kind(str(row.text))
		if not kind in KEY_KINDS:
			continue
		var ex := lerpf(x0, x1, clampf(float(row.time) / _end_seconds, 0.0, 1.0))
		lift = (lift + 1) % 2 if ex - last_x < 26.0 * b else 0
		last_x = ex
		var lit := head_x >= ex - 0.5 and head > 0.0
		var tint := kind_tint(kind)
		var icon_y := line_y - 22.0 * b - lift * 20.0 * b
		var a := (1.0 if lit else 0.35) * k
		draw_circle(Vector2(ex, line_y), (5.0 if lit else 3.5) * b, _c(tint, a))
		draw_rect(Rect2(ex - 0.75, icon_y + 10.0 * b, 1.5, line_y - icon_y - 10.0 * b), _c(tint, 0.35 * a))
		UiIcons.draw(self, row_icon(kind), Vector2(ex, icon_y), 20.0 * b, _c(tint, a))
	var small := int(16 * b)
	draw_string(bold, Vector2(x0, line_y + 20.0 * b), "0:00", HORIZONTAL_ALIGNMENT_LEFT, -1, small, _c(UiStyle.FAINT, k))
	var end_width := bold.get_string_size(total, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(bold, Vector2(x1 - end_width, line_y + 20.0 * b), total, HORIZONTAL_ALIGNMENT_LEFT, -1, small, _c(UiStyle.FAINT, k))


# --- Rows ------------------------------------------------------------------------

## One timeline row (the result screen's and the live ticker's): time in
## amber, a kind icon, the sentence with names in suit colour. Returns a
## PanelContainer; its RichTextLabel is in meta "words".
static func make_row(time_s: float, icon: String, bbcode: String, font_size := 22, key := false,
		tint := UiStyle.TEXT, backing := false) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(tint.r, tint.g, tint.b, 0.13) if key else (Color(0.0, 0.01, 0.03, 0.55) if backing else Color(0, 0, 0, 0))
	box.border_width_left = 3 if key else 0
	box.border_color = tint
	box.set_corner_radius_all(int(font_size * 0.3))
	box.content_margin_left = font_size * 0.4
	box.content_margin_right = font_size * 0.6
	box.content_margin_top = font_size * 0.15
	box.content_margin_bottom = font_size * 0.15
	panel.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(font_size * 0.5))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var time_label := UiStyle.label(stamp(time_s), "bold", int(font_size * 0.92), UiStyle.AMBER)
	time_label.custom_minimum_size = Vector2(font_size * 2.2, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if backing:
		UiStyle.outlined(time_label, int(font_size * 0.25))
	row.add_child(time_label)
	row.add_child(UiIcon.make(icon, tint, font_size * 1.05))
	var words := RichTextLabel.new()
	words.bbcode_enabled = true
	words.fit_content = true
	words.scroll_active = false
	words.autowrap_mode = TextServer.AUTOWRAP_OFF
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_font_override("normal_font", UiStyle.font("body"))
	words.add_theme_font_override("bold_font", UiStyle.font("bold"))
	words.add_theme_font_size_override("normal_font_size", font_size)
	words.add_theme_font_size_override("bold_font_size", font_size)
	words.add_theme_color_override("default_color", Color(0.93, 0.96, 1.0))
	if backing:
		words.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		words.add_theme_constant_override("outline_size", int(font_size * 0.25))
	words.text = ("[b]%s[/b]" if key else "%s") % bbcode
	words.custom_minimum_size = Vector2(UiStyle.font("bold").get_string_size(_strip(bbcode), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0, 0)
	row.add_child(words)
	panel.set_meta("words", words)
	return panel


static func _strip(bbcode: String) -> String:
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	return re.sub(bbcode, "", true)


static func row_icon(kind: String) -> String:
	return UiStyle.kind_icon(kind) if kind in ["power", "blackout", "spaced", "downed", "abort"] else kind


static func kind_tint(kind: String) -> Color:
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
	if t.contains("revived") or t.contains("got back up") or t.contains("back on their feet"):
		return "medbay"
	if t.contains("dragging"):
		return "hand"
	if t.contains("airlock") or t.contains("into space"):
		return "airlock"
	if t.contains("blackout") or t.contains("lights out") or t.contains("lights went out"):
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
	if t.contains("no crew left") or t.contains(" is down"):
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
