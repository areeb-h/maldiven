class_name StationHud
extends Control
## In-round HUD: multi-touch controls (raw touch indices so stick, camera and
## buttons work together), role card, objective, alerts, countdowns, results.
## Actions emitted: interact, shove (throws when carrying), shoot, sabotage.

signal action_pressed(action: String)  # interact / shove / shoot / sabotage
signal leave_pressed
signal lobby_pressed

var crew: CrewMember
var role := ""
var is_host := false

var _move_finger := -1
var _look_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_point := Vector2.ZERO
var _pressed := {}  # button id -> finger
var _interact_label := ""
var _interact_enabled := false
var _shove_ready := 1.0
var _sabotage_ready := 1.0
var _sabotage_cooldown := 0.0
var _danger := 0.0  # 0..1 red vignette pulse strength
var _pulse := 0.0

var _role_chip: Label
var _objective: Label
var _progress: Label
var _timer: Label
var _alert_panel: PanelContainer
var _alert: Label
var _alert_box: StyleBoxFlat
var _countdown_box: VBoxContainer
var _countdown_caption: Label
var _countdown: Label
var _vignette: TextureRect
var _dim: ColorRect
var _briefing: PanelContainer
var _briefing_title: Label
var _briefing_body: Label
var _briefing_footer: Label
var _result: PanelContainer
var _result_caption: Label
var _result_title: Label
var _result_body: Label
var _timeline: RichTextLabel
var _lobby_button: Button
var _menu: PanelContainer
var _hint: Label
var _alert_time := 0.0
var _touch := true
var _life := "ok"
var _has_gun := false
var _ammo := 0
var _gun_ready := 1.0
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.make_theme()
	_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch-ui")
	_build_vignette()
	_build_top_left()
	_build_top_center()
	_build_countdown()
	var menu_button := Button.new()
	menu_button.text = "II"
	UiStyle.style_button(menu_button)
	menu_button.add_theme_font_override("font", UiStyle.font("head"))
	menu_button.add_theme_font_size_override("font_size", 22)
	menu_button.pressed.connect(func(): _set_menu(not _menu.visible))
	add_child(menu_button)
	_anchor(menu_button, 1.0, 0.0, Rect2(-104, 18, 80, 56))
	_hint = UiStyle.outlined(UiStyle.label("", "body", 20, Color(1, 1, 1, 0.55)), 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_anchor(_hint, 0.5, 1.0, Rect2(-420, -44, 840, 30))
	_status = UiStyle.outlined(UiStyle.label("", "head", 26, UiStyle.TEXT), 10)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_anchor(_status, 0.5, 1.0, Rect2(-420, -190, 840, 90))
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.05, 0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.hide()
	_build_menu()
	_build_briefing()
	_build_result()


## Pin a control to an anchor point (fractions of the screen) with an offset rect.
func _anchor(control: Control, ax: float, ay: float, rect: Rect2) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _build_vignette() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.55))
	gradient.add_point(0.62, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.05, 1.05)
	texture.width = 256
	texture.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = texture
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_top_left() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.62, 16))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_anchor(panel, 0.0, 0.0, Rect2(20, 18, 0, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_role_chip = Label.new()
	_role_chip.add_theme_font_override("font", UiStyle.font("head"))
	_role_chip.add_theme_font_size_override("font_size", 18)
	_role_chip.add_theme_color_override("font_color", Color("04121c"))
	_role_chip.add_theme_stylebox_override("normal", UiStyle.pill_box(UiStyle.MUTED))
	_role_chip.text = "…"
	row.add_child(_role_chip)
	_progress = UiStyle.label("", "head", 18, UiStyle.AMBER)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_progress)
	_objective = UiStyle.label("", "bold", 23, UiStyle.TEXT)
	box.add_child(_objective)


func _build_top_center() -> void:
	var pill := PanelContainer.new()
	var box := UiStyle.panel_box(UiStyle.ACCENT, 0.62, 10)
	box.set_corner_radius_all(999)
	box.border_width_top = 1
	box.content_margin_left = 26
	box.content_margin_right = 26
	pill.add_theme_stylebox_override("panel", box)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pill)
	_anchor(pill, 0.5, 0.0, Rect2(-90, 18, 180, 58))
	_timer = UiStyle.label("10:00", "head", 30, UiStyle.TEXT)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(_timer)
	_alert_panel = PanelContainer.new()
	_alert_box = UiStyle.panel_box(UiStyle.ACCENT, 0.8, 14)
	_alert_box.border_width_top = 0
	_alert_box.border_width_left = 6
	_alert_panel.add_theme_stylebox_override("panel", _alert_box)
	_alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alert_panel)
	_anchor(_alert_panel, 0.5, 0.0, Rect2(-250, 92, 500, 0))
	_alert = UiStyle.label("", "head", 19, UiStyle.TEXT)
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_panel.add_child(_alert)
	_alert_panel.modulate.a = 0.0


func _build_countdown() -> void:
	_countdown_box = VBoxContainer.new()
	_countdown_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_box.add_theme_constant_override("separation", -10)
	add_child(_countdown_box)
	_anchor(_countdown_box, 0.5, 0.0, Rect2(-300, 168, 600, 150))  # below the alert banner
	_countdown_caption = UiStyle.outlined(UiStyle.label("", "head", 22, UiStyle.TEXT), 8)
	_countdown_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_box.add_child(_countdown_caption)
	_countdown = UiStyle.outlined(UiStyle.label("", "title", 84, UiStyle.TEXT), 12)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_box.add_child(_countdown)


func _card(width: float, height: float, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(accent, 0.94, 34))
	add_child(panel)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_anchor(panel, 0.5, 0.5, Rect2(-width / 2.0, -height / 2.0, width, height))
	return panel


func _build_menu() -> void:
	_menu = _card(440, 250, UiStyle.ACCENT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_menu.add_child(box)
	# Multiplayer can't pause: the round keeps running behind this menu.
	box.add_child(UiStyle.label("MENU", "head", 26, UiStyle.ACCENT))
	var resume := Button.new()
	resume.text = "RESUME"
	UiStyle.style_button(resume, true)
	resume.pressed.connect(func(): _set_menu(false))
	box.add_child(resume)
	var leave := Button.new()
	leave.text = "LEAVE STATION"
	UiStyle.style_button(leave, false, UiStyle.DANGER)
	leave.pressed.connect(func(): leave_pressed.emit())
	box.add_child(leave)
	_menu.hide()


func _build_briefing() -> void:
	_briefing = _card(760, 340, UiStyle.ACCENT)
	_briefing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_briefing.add_child(box)
	var caption := UiStyle.label("YOUR ROLE", "bold", 22, UiStyle.MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	_briefing_title = UiStyle.label("", "title", 64, UiStyle.TEXT)
	_briefing_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_briefing_title)
	_briefing_body = UiStyle.label("", "body", 26, UiStyle.TEXT)
	_briefing_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_briefing_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_briefing_body.custom_minimum_size = Vector2(680, 0)
	box.add_child(_briefing_body)
	_briefing_footer = UiStyle.label("", "bold", 22, UiStyle.MUTED)
	_briefing_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_briefing_footer)
	_briefing.hide()


func _build_result() -> void:
	_result = _card(900, 620, UiStyle.ACCENT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_result.add_child(box)
	_result_caption = UiStyle.label("ROUND OVER", "bold", 22, UiStyle.MUTED)
	_result_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_caption)
	_result_title = UiStyle.label("", "title", 58, UiStyle.TEXT)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_body = UiStyle.label("", "body", 26, UiStyle.TEXT)
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_result_body)
	var timeline_panel := PanelContainer.new()
	var inset := StyleBoxFlat.new()
	inset.bg_color = Color(0, 0, 0, 0.3)
	inset.set_corner_radius_all(6)
	inset.set_content_margin_all(16)
	timeline_panel.add_theme_stylebox_override("panel", inset)
	timeline_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(timeline_panel)
	_timeline = RichTextLabel.new()
	_timeline.bbcode_enabled = true
	_timeline.custom_minimum_size = Vector2(800, 260)
	_timeline.add_theme_font_size_override("normal_font_size", 22)
	_timeline.add_theme_font_size_override("bold_font_size", 22)
	timeline_panel.add_child(_timeline)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_lobby_button = Button.new()
	_lobby_button.text = "PLAY AGAIN"
	UiStyle.style_button(_lobby_button, true)
	_lobby_button.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(_lobby_button)
	var leave := Button.new()
	leave.text = "LEAVE"
	UiStyle.style_button(leave)
	leave.pressed.connect(func(): leave_pressed.emit())
	row.add_child(leave)
	_result.hide()


# --- State updates from the world -------------------------------------------

func set_role(next_role: String) -> void:
	role = next_role
	var infiltrator := role == StationRules.INFILTRATOR
	var color := UiStyle.INFILTRATOR if infiltrator else UiStyle.CREW
	_role_chip.text = "INFILTRATOR" if infiltrator else "CREW"
	_role_chip.add_theme_stylebox_override("normal", UiStyle.pill_box(color))
	_briefing_title.text = _role_chip.text
	_briefing_title.add_theme_color_override("font_color", color)
	_briefing.add_theme_stylebox_override("panel", UiStyle.panel_box(color, 0.94, 34))
	if infiltrator:
		_briefing_body.text = "Help restore power so the vault opens. Then steal the core and launch it in the cargo pod in Cargo. Blend in. Kill the lights when it helps."
	else:
		_briefing_body.text = "Bring 3 power cells to the Reactor. When the vault in Command opens, load the core into the shuttle in Docking. One of you is lying."
	if not _touch:
		_hint.text = "WASD move  ·  Shift run  ·  RMB look  ·  E use  ·  F shove/throw  ·  LMB/R shoot%s  ·  Space jump" % ("  ·  Q blackout" if infiltrator else "")
	queue_redraw()


func update_state(rules: StationRules, action: Dictionary, my_id: int) -> void:
	var phase := rules.phase
	var briefing := phase == StationRules.Phase.BRIEFING and role != ""
	_briefing.visible = briefing
	if briefing:
		_briefing_footer.text = "Round starts in %d" % int(ceil(StationRules.BRIEFING_SECONDS - rules.elapsed))
	var seconds := int(ceil(rules.time_left()))
	_timer.text = "%d:%02d" % [seconds / 60, seconds % 60]
	_timer.add_theme_color_override("font_color", UiStyle.DANGER if seconds < 60 else UiStyle.TEXT)
	_progress.text = ""
	match phase:
		StationRules.Phase.BRIEFING:
			_objective.text = "Briefing…"
		StationRules.Phase.STABILISE:
			_progress.add_theme_color_override("font_color", UiStyle.AMBER)
			_progress.text = "POWER %d/%d" % [rules.powered_cells(), rules.reactor_socket_count()]
			_objective.text = "Bring cells to the Reactor"
		StationRules.Phase.EXTRACTION:
			_progress.add_theme_color_override("font_color", UiStyle.GOOD)
			_progress.text = "POWER ONLINE"
			_objective.text = "Core  →  shuttle in Docking" if role != StationRules.INFILTRATOR \
				else "Core  →  cargo pod in Cargo"
		_:
			_objective.text = ""
	var countdown_active := phase != StationRules.Phase.RESULT
	if rules.airlock_state == "warning" and countdown_active:
		_countdown_caption.text = "AIRLOCK VENTING"
		_countdown.text = "%d" % int(ceil(rules.airlock_left))
		_countdown.add_theme_color_override("font_color", UiStyle.AMBER)
		_danger = 0.8
	elif rules.pod_left >= 0.0 and countdown_active:
		_countdown_caption.text = "CARGO POD LAUNCH"
		_countdown.text = "%d" % int(ceil(rules.pod_left))
		_countdown.add_theme_color_override("font_color", UiStyle.INFILTRATOR)
		_danger = 1.0
	elif rules.shuttle_left >= 0.0 and countdown_active:
		_countdown_caption.text = "SHUTTLE LAUNCH"
		_countdown.text = "%d" % int(ceil(rules.shuttle_left))
		_countdown.add_theme_color_override("font_color", UiStyle.CREW)
		_danger = 0.0
	else:
		_countdown_caption.text = ""
		_countdown.text = ""
		_danger = 0.5 if rules.is_blackout() else 0.0
	_interact_label = action.get("label", "")
	_interact_enabled = not action.is_empty() and action.get("action") != "none"
	var me: Dictionary = rules.players.get(my_id, {})
	_shove_ready = 1.0 - clampf((float(me.get("shove_ready", 0.0)) - rules.elapsed) / StationRules.SHOVE_COOLDOWN, 0.0, 1.0)
	_has_gun = rules.holds_gun(my_id)
	_ammo = rules.gun_ammo()
	_gun_ready = 1.0 - clampf((rules.gun_ready - rules.elapsed) / StationRules.GUN_COOLDOWN, 0.0, 1.0)
	_sabotage_cooldown = rules.sabotage_cooldown()
	_sabotage_ready = 1.0 - clampf(_sabotage_cooldown / StationRules.BLACKOUT_COOLDOWN, 0.0, 1.0)
	if phase == StationRules.Phase.RESULT and not _result.visible:
		_show_result(rules)
	_dim.visible = _result.visible or _menu.visible or briefing
	queue_redraw()


func mark_shove_used(rules: StationRules, my_id: int) -> void:
	if rules.players.has(my_id):
		rules.players[my_id].shove_ready = rules.elapsed + StationRules.SHOVE_COOLDOWN


func _set_menu(open: bool) -> void:
	_menu.visible = open
	reset_pointers()
	if crew != null:
		crew.input_enabled = not open


func _show_result(rules: StationRules) -> void:
	_set_menu(false)
	reset_pointers()
	if crew != null:
		crew.input_enabled = false
	_briefing.hide()
	var title := "STATION LOST"
	var color := UiStyle.MUTED
	if rules.winner == StationRules.CREW:
		title = "CREW ESCAPED"
		color = UiStyle.CREW
	elif rules.winner == StationRules.INFILTRATOR:
		title = "INFILTRATOR WINS"
		color = UiStyle.INFILTRATOR
	var won := rules.winner != "" and rules.winner == role
	var nobody := rules.winner == "none" or rules.winner == ""
	_result_caption.text = "ROUND OVER  ·  " + ("YOU WON" if won else ("NOBODY WON" if nobody else "YOU LOST"))
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", color)
	_result.add_theme_stylebox_override("panel", UiStyle.panel_box(color, 0.95, 34))
	_result_body.text = "%s  The infiltrator was %s." % [rules.reason, rules.infiltrator_name]
	_timeline.clear()
	_timeline.append_text("[b][color=#%s]WHAT HAPPENED[/color][/b]\n" % UiStyle.AMBER.to_html(false))
	for line in rules.timeline:
		var text := str(line)
		var split := text.find("  ")
		if split > 0:
			_timeline.append_text("[color=#%s]%s[/color]   %s\n" % [UiStyle.ACCENT.to_html(false), text.substr(0, split), text.substr(split + 2)])
		else:
			_timeline.append_text(text + "\n")
	_lobby_button.visible = is_host
	_result.show()


func flash_alert(text: String, kind: String) -> void:
	var colors := {"power": UiStyle.GOOD, "pod": UiStyle.INFILTRATOR, "blackout": UiStyle.AMBER,
		"shuttle": UiStyle.CREW, "abort": Color("ffd23f")}
	var color: Color = colors.get(kind, UiStyle.ACCENT)
	_alert.text = text.to_upper()
	_alert_box.border_color = color
	_alert.add_theme_color_override("font_color", color.lightened(0.3))
	_alert_panel.modulate.a = 1.0
	_alert_time = 4.5


func _process(delta: float) -> void:
	if _alert_time > 0.0:
		_alert_time -= delta
		_alert_panel.modulate.a = clampf(_alert_time / 0.6, 0.0, 1.0)
	_pulse += delta
	var red := _danger * (0.55 + 0.45 * sin(_pulse * 6.0))
	_vignette.modulate = Color(1.0, 1.0 - red * 0.85, 1.0 - red * 0.85, 0.85 + red * 0.15)
	if _danger > 0.0 and not _countdown.text.is_empty():
		_countdown.pivot_offset = _countdown.size / 2.0
		_countdown.scale = Vector2.ONE * (1.0 + 0.04 * maxf(0.0, sin(_pulse * 6.0)))


# --- Touch and keyboard input ------------------------------------------------

## "ok", "downed" or "dead", with seconds until a downed player gets up.
func set_life_state(state: String, down_left: float) -> void:
	if state != _life:
		_life = state
		reset_pointers()
	match state:
		"downed":
			_status.text = "YOU'RE DOWN\nA crewmate can drag you to Medical  ·  up in %ds" % int(ceil(maxf(down_left, 0.0)))
			_status.add_theme_color_override("font_color", UiStyle.AMBER)
		"dead":
			_status.text = "YOU WERE SPACED\nDrift through the station and watch"
			_status.add_theme_color_override("font_color", Color("b9c8ff"))
		_:
			_status.text = ""


func _buttons() -> Dictionary:
	if _life == "downed":
		return {}
	if _life == "dead":
		return {}
	var out := {
		"jump": {"pos": Vector2(size.x - 96, size.y - 96), "radius": 52.0},
		"interact": {"pos": Vector2(size.x - 244, size.y - 124), "radius": 70.0},
		"shove": {"pos": Vector2(size.x - 112, size.y - 246), "radius": 52.0},
	}
	if role == StationRules.INFILTRATOR:
		out["sabotage"] = {"pos": Vector2(size.x - 278, size.y - 300), "radius": 46.0}
	if _has_gun:
		out["shoot"] = {"pos": Vector2(size.x - 120, size.y - 372), "radius": 56.0}
	return out


func _hit_button(point: Vector2) -> String:
	var buttons := _buttons()
	for id in buttons:
		if point.distance_to(buttons[id].pos) <= buttons[id].radius + 12.0:
			return id
	return ""


func _press(button_id: String) -> void:
	if button_id == "jump":
		crew.jump_pending = true
	elif button_id == "sabotage" and _sabotage_cooldown > 0.0:
		return
	else:
		action_pressed.emit(button_id)


func reset_pointers() -> void:
	_move_finger = -1
	_look_finger = -1
	_pressed.clear()
	if crew != null:
		crew.clear_input()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_pointers()


func _input(event: InputEvent) -> void:
	if crew == null or _result.visible or _menu.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _result.visible:
			_set_menu(not _menu.visible)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_set_menu(true)
			KEY_SPACE:
				crew.jump_pending = true
			KEY_E:
				action_pressed.emit("interact")
			KEY_F:
				action_pressed.emit("shove")
			KEY_Q:
				if role == StationRules.INFILTRATOR:
					_press("sabotage")
			KEY_R:
				if _has_gun:
					action_pressed.emit("shoot")

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		crew.look(event.relative)
	if event is InputEventScreenTouch:
		_touch = true
		_hint.text = ""
		if not event.pressed:
			if event.index == _move_finger:
				_move_finger = -1
				crew.move_input = Vector2.ZERO
			if event.index == _look_finger:
				_look_finger = -1
			for id in _pressed.keys():
				if _pressed[id] == event.index:
					_pressed.erase(id)
		elif event.position.y < 90 and event.position.x > size.x - 130:
			pass  # pause button
		else:
			var hit := _hit_button(event.position)
			if hit != "":
				_pressed[hit] = event.index
				_press(hit)
			elif event.position.x < size.x * 0.42 and _move_finger == -1:
				_move_finger = event.index
				_stick_origin = event.position
				_stick_point = event.position
			elif event.position.x >= size.x * 0.42 and _look_finger == -1:
				_look_finger = event.index
	if event is InputEventScreenDrag:
		if event.index == _move_finger:
			var offset: Vector2 = (event.position - _stick_origin).limit_length(72)
			_stick_point = _stick_origin + offset
			crew.move_input = offset / 72.0
		elif event.index == _look_finger:
			crew.look(event.relative * 1.2)
	queue_redraw()


## Desktop shooting: a left click that no HUD button consumed.
func _unhandled_input(event: InputEvent) -> void:
	if crew == null or _result.visible or _menu.visible or _touch or not _has_gun:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		action_pressed.emit("shoot")
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if crew == null or _result.visible or not _touch:
		return
	var glass := Color(0.03, 0.06, 0.11, 0.5)
	var edge := Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.55)
	var center := _stick_origin if _move_finger >= 0 else Vector2(140, size.y - 140)
	draw_circle(center, 78, glass)
	draw_arc(center, 78, 0, TAU, 64, edge, 2.0, true)
	for i in range(4):
		var angle := i * PI / 2.0
		draw_circle(center + Vector2(cos(angle), sin(angle)) * 64, 3, edge)
	var knob := _stick_point if _move_finger >= 0 else center
	draw_circle(knob, 32, Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.35))
	draw_arc(knob, 32, 0, TAU, 48, UiStyle.ACCENT, 2.5, true)
	var font := UiStyle.font("bold")
	var buttons := _buttons()
	for id in buttons:
		var spec: Dictionary = buttons[id]
		var pos: Vector2 = spec.pos
		var radius: float = spec.radius
		var fill := glass
		var ring := edge
		var text := ""
		var fraction := 1.0
		var text_color := UiStyle.TEXT
		match id:
			"jump":
				text = "JUMP"
			"interact":
				text = _interact_label.to_upper() if _interact_label != "" else "USE"
				if _interact_enabled:
					fill = Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.42)
					ring = UiStyle.ACCENT
				else:
					text_color = Color(1, 1, 1, 0.45)
			"shove":
				text = "SHOVE"
				fraction = _shove_ready
				ring = UiStyle.AMBER if _shove_ready >= 1.0 else Color(1, 1, 1, 0.3)
			"shoot":
				text = "SHOOT"
				fill = Color(0.5, 0.12, 0.06, 0.5)
				ring = Color("ff8a4a") if _ammo > 0 else Color(1, 1, 1, 0.25)
				fraction = _gun_ready
				for pip in range(StationRules.GUN_AMMO):
					var pip_at := pos + Vector2((pip - 1) * 16.0, radius + 12.0)
					draw_circle(pip_at, 5.0, Color("ff8a4a") if pip < _ammo else Color(1, 1, 1, 0.2))
			"sabotage":
				text = "BLACKOUT" if _sabotage_cooldown <= 0.0 else "%ds" % int(ceil(_sabotage_cooldown))
				fill = Color(0.45, 0.05, 0.1, 0.45)
				ring = UiStyle.INFILTRATOR
				fraction = _sabotage_ready
		if _pressed.has(id):
			fill = fill.lightened(0.25)
			radius *= 0.94
		draw_circle(pos, radius, fill)
		draw_arc(pos, radius, 0, TAU, 64, Color(1, 1, 1, 0.12), 2.0, true)
		draw_arc(pos, radius, -PI / 2, -PI / 2 + TAU * fraction, 64, ring, 4.0, true)
		var font_size := 18 if text.length() > 9 else (20 if text.length() > 6 else 24)
		var lines := text.split(" ", false, 1) if text.length() > 9 else PackedStringArray([text])
		for line_index in range(lines.size()):
			var line := lines[line_index]
			var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var y := font_size * 0.35 + (line_index - (lines.size() - 1) / 2.0) * font_size * 1.05
			draw_string(font, pos + Vector2(-width / 2.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
