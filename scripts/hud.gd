class_name StationHud
extends Control
## In-round HUD: multi-touch controls (raw touch indices so stick, camera and
## buttons work together), role chip, objective with progress, timer, queued
## alerts, centre countdown, off-screen markers, role briefing and results.
## Actions emitted: interact, shove (throws when carrying), shoot, sabotage.
##
## Layout follows docs/look-and-feel.md §3: thumb-zone button positions from
## the bottom-right safe corner, ≥ 88 px hit targets, safe-area margins, a
## floating stick, critical info in the centre and the rest at the edges.

signal action_pressed(action: String)  # interact / shove / shoot / sabotage
signal leave_pressed
signal lobby_pressed

const STICK_TRAVEL := 72.0
const STICK_RING := 80.0
const STICK_DEAD := 0.12
const STICK_RUN := 0.8
const STICK_LINGER := 1.5  # the stick stays where it was last used
const HOLD_TO_FIRE := 0.3  # BLACKOUT is hold-to-fire so one stray tap can't expose you
const EDGE_GUARD := 24.0  # Android back-gesture strip on both sides
## id -> [offset from the bottom-right safe corner, visual radius, hit radius, colour]
const BUTTONS := {
	"interact": [Vector2(200, 150), 72.0, 82.0, Color("5fd4ff")],
	"shove": [Vector2(110, 270), 52.0, 64.0, Color("ffe14d")],
	"jump": [Vector2(90, 80), 44.0, 56.0, Color("e8f1ff")],
	"shoot": [Vector2(340, 190), 54.0, 64.0, Color("ff8a4a")],
	"sabotage": [Vector2(330, 320), 50.0, 62.0, Color("ff4d5e")],
}
## USE verbs -> icon, from StationRules.available_action labels.
const USE_ICONS := {"Pick up cell": "cell", "Insert cell": "cell", "Pick up core": "core", "Pull core out": "core",
	"Take gun": "gun", "Load shuttle": "shuttle", "Arm pod": "pod", "Pod locked": "lock", "Drop": "drop",
	"Cycle airlock": "airlock"}

var crew: CrewMember
var role := ""
var is_host := false
## The camera markers project through. Falls back to the viewport's camera.
var camera: Camera3D

# Layout
var _margin := Rect2(24, 16, 24, 20)  # left, top / right, bottom (logical px)
var _safe_root: Control
var _touch := true

# Pointers
var _move_finger := -1
var _look_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_point := Vector2.ZERO
var _stick_center := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _stick_alpha := 0.45
var _stick_idle := 99.0
var _pressed := {}  # button id -> finger

# Button state
var _vis := {}  # id -> 0..1 shown
var _spring := {}  # id -> Vector2(scale, velocity)
var _flash := {}  # id -> 0..1 ready flash
var _was_ready := {}
var _hold := 0.0  # BLACKOUT hold progress 0..1
var _deny := {}  # id -> 0..1 "can't" wiggle
var _intro := 0.0

# Round state mirrored from update_state
var _phase := -1
var _life := "ok"
var _interact_label := ""
var _interact_enabled := false
var _use_from := ["hand", "USE"]
var _use_to := ["hand", "USE"]
var _use_fade := 1.0
var _use_on := 0.0
var _carrying := false
var _shove_ready := 1.0
var _shove_left := 0.0
var _has_gun := false
var _ammo := 0
var _gun_ready := 1.0
var _sabotage_ready := 1.0
var _sabotage_cooldown := 0.0
var _danger := 0.0
var _cold := 0.0
var _pulse := 0.0
var _auto_markers := true
var _seconds_shown := -1
var _timer_beat := 1.0
var _timer_heat := 0.0
var _cells_shown := -1

# Nodes
var _vignette: TextureRect
var _markers: HudMarkers
var _top_panel: PanelContainer
var _role_chip: Control
var _role_word: PanelContainer
var _role_word_label: Label
var _role_word_tween: Tween
var _phase_icon: UiIcon
var _phase_label: Label
var _pips: Control
var _progress: Label
var _objective_icon: UiIcon
var _objective: Label
var _core_row: HBoxContainer
var _core_label: Label
var _timer_pill: PanelContainer
var _timer_box: StyleBoxFlat
var _timer_icon: UiIcon
var _timer: Label
var _menu_button: Button
var _alerts: HudAlerts
var _countdown: HudCountdown
var _status: PanelContainer
var _status_icon: UiIcon
var _status_title: Label
var _status_detail: Label
var _status_bar: Control
var _status_fraction := 0.0
var _hint: Label
var _controls: Control
var _dim: ColorRect
var _dim_tween: Tween
var _menu: PanelContainer
var _menu_open := false
var _menu_tween: Tween
var _briefing: HudBriefing
var _result: HudResult


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	theme = UiStyle.make_theme()
	_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch-ui")
	for id in BUTTONS:
		_vis[id] = 0.0
		_spring[id] = Vector2(1, 0)
		_flash[id] = 0.0
		_deny[id] = 0.0
		_was_ready[id] = true
	_build_vignette()
	_markers = HudMarkers.new()
	add_child(_markers)
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_root = Control.new()
	_safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe_root)
	_safe_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top_left()
	_build_top_center()
	_build_menu_button()
	_countdown = HudCountdown.new()
	add_child(_countdown)
	_anchor(_countdown, 0.5, 0.3, Rect2(-200, -(HudCountdown.RADIUS + 18.0), 400, 260))
	_build_status()
	_hint = UiStyle.outlined(UiStyle.label("", "body", UiStyle.LABEL, Color(1, 1, 1, 0.6)), 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_safe_root.add_child(_hint)
	_anchor(_hint, 0.5, 1.0, Rect2(-460, -32, 920, 30))
	if _touch:
		_hint.text = "Drag on the left to move  ·  drag on the right to look"
	_controls = Control.new()
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_controls)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls.draw.connect(_draw_controls)
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.05, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_menu()
	_briefing = HudBriefing.new()
	add_child(_briefing)
	_center(_briefing)
	_briefing.hide()
	_result = HudResult.new()
	_result.again_pressed.connect(func(): lobby_pressed.emit())
	_result.leave_pressed.connect(func(): leave_pressed.emit())
	add_child(_result)
	_center(_result, 632.0)
	_result.hide()
	resized.connect(_update_safe_area)
	_update_safe_area()
	_stick_center = _stick_home()
	_stick_knob = _stick_center
	_play_intro()


## Pin a control to an anchor point (fractions of the parent) with an offset rect.
func _anchor(control: Control, ax: float, ay: float, rect: Rect2) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _center(card: Control, height := 0.0) -> void:
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.set_meta("fit_height", height)
	var width := card.custom_minimum_size.x
	_anchor(card, 0.5, 0.5, Rect2(-width / 2.0, -height / 2.0, width, height))


## Controls never shrink on their own once text re-wraps, so cards are refit
## to their minimum size every frame (centred on their anchor, plus `y`).
func _fit(card: Control, y := 0.0, bottom_anchored := false) -> void:
	if not card.visible:
		return
	var need := card.get_combined_minimum_size()
	var width := maxf(need.x, card.custom_minimum_size.x)
	var height := maxf(need.y, float(card.get_meta("fit_height", 0.0)))
	height = minf(height, size.y - _margin.position.y - _margin.size.y) if not bottom_anchored else height
	card.offset_left = -width * 0.5
	card.offset_right = width * 0.5
	card.offset_top = y - (height if bottom_anchored else height * 0.5)
	card.offset_bottom = y + (0.0 if bottom_anchored else height * 0.5)
	card.pivot_offset = Vector2(width, height) * 0.5


## Safe-area margins in logical px: max(inset, 24) at the sides, 16 top, 20 bottom.
func _update_safe_area() -> void:
	_margin = UiStyle.safe_margins(self)
	_safe_root.offset_left = _margin.position.x
	_safe_root.offset_top = _margin.position.y
	_safe_root.offset_right = -_margin.size.x
	_safe_root.offset_bottom = -_margin.size.y
	_markers.insets = _margin
	_controls.queue_redraw()


func _build_vignette() -> void:
	var gradient := Gradient.new()
	# White ramp: the colour comes from modulate (black calm, red alarm, blue-black blackout).
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 0.55))
	gradient.add_point(0.62, Color(1, 1, 1, 0.0))
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
	_vignette.modulate = Color(0, 0, 0, 0.85)
	add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _glass(radius := 12, alpha := 0.62) -> StyleBoxFlat:
	var box := UiStyle.panel_box(UiStyle.ACCENT, alpha, 12, radius)
	box.border_width_top = 1
	box.border_color = Color(1, 1, 1, 0.1)
	box.shadow_size = 10
	return box


func _build_top_left() -> void:
	_top_panel = PanelContainer.new()
	var box := _glass(14)
	box.content_margin_left = 12
	box.content_margin_right = 20
	_top_panel.add_theme_stylebox_override("panel", box)
	_top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_root.add_child(_top_panel)
	_anchor(_top_panel, 0.0, 0.0, Rect2(0, 0, 0, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_panel.add_child(row)
	# Role chip: icon only, so a glance over your shoulder gives little away.
	# Tap it to show the word for a moment.
	_role_chip = Control.new()
	_role_chip.custom_minimum_size = Vector2(52, 52)
	_role_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_role_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_role_chip.draw.connect(func():
		var color := UiStyle.role_color(role) if role != "" else UiStyle.MUTED
		var mid := _role_chip.size * 0.5
		_role_chip.draw_circle(mid, 25.0, UiStyle.with_alpha(color, 0.18))
		_role_chip.draw_arc(mid, 24.0, 0.0, TAU, 48, color, 2.0, true)
		if role != "":
			UiIcons.draw(_role_chip, UiStyle.role_icon(role), mid, 30.0, color))
	_role_chip.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_reveal_role())
	row.add_child(_role_chip)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(lines)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiStyle.S1)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(head)
	_phase_icon = UiIcon.make("cell", UiStyle.AMBER, 18)
	head.add_child(_phase_icon)
	_phase_label = UiStyle.label("BRIEFING", "caps", UiStyle.CAPTION, UiStyle.AMBER)
	_phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_phase_label)
	_pips = Control.new()
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.set_meta("filled", 0)
	_pips.set_meta("total", 3)
	_pips.set_meta("pop", 0.0)
	_pips.draw.connect(_draw_pips)
	head.add_child(_pips)
	_progress = UiStyle.label("", "head", UiStyle.CAPTION, UiStyle.AMBER)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_progress)
	var objective := HBoxContainer.new()
	objective.add_theme_constant_override("separation", UiStyle.S1)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(objective)
	_objective_icon = UiIcon.make("cell", UiStyle.TEXT, 22)
	objective.add_child(_objective_icon)
	_objective = UiStyle.label("Get ready", "bold", 23, UiStyle.TEXT)
	_objective.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	objective.add_child(_objective)
	_core_row = HBoxContainer.new()
	_core_row.add_theme_constant_override("separation", UiStyle.S1)
	_core_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_core_row.add_child(UiIcon.make("core", UiStyle.ACCENT, 18))
	_core_label = UiStyle.label("", "body", UiStyle.LABEL, UiStyle.MUTED)
	_core_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_core_row.add_child(_core_label)
	_core_row.hide()
	lines.add_child(_core_row)
	# The role word, revealed under the chip on tap.
	_role_word = UiStyle.chip("CREW", UiStyle.CREW, "shield")
	_role_word_label = _role_word.get_child(0).get_child(1)
	_role_word.modulate.a = 0.0
	_safe_root.add_child(_role_word)
	_anchor(_role_word, 0.0, 0.0, Rect2(6, 92, 0, 0))


func _draw_pips() -> void:
	var total: int = _pips.get_meta("total")
	var filled: int = _pips.get_meta("filled")
	var pop: float = _pips.get_meta("pop")
	for i in range(total):
		var center := Vector2(10 + i * 22, 11)
		var on := i < filled
		var grow := 1.0 + (0.35 * pop if on and i == filled - 1 else 0.0)
		if on:
			_pips.draw_circle(center, 10.0 * grow, UiStyle.with_alpha(UiStyle.AMBER, 0.18))
		UiIcons.draw(_pips, "cell", center, 20.0 * grow, UiStyle.AMBER if on else Color(1, 1, 1, 0.22))


func _build_top_center() -> void:
	_timer_pill = PanelContainer.new()
	_timer_box = _glass(999)
	_timer_box.content_margin_left = 20
	_timer_box.content_margin_right = 24
	_timer_box.content_margin_top = 8
	_timer_box.content_margin_bottom = 8
	_timer_box.set_border_width_all(1)
	_timer_pill.add_theme_stylebox_override("panel", _timer_box)
	_timer_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_root.add_child(_timer_pill)
	_anchor(_timer_pill, 0.5, 0.0, Rect2(-84, 0, 168, 56))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_pill.add_child(row)
	_timer_icon = UiIcon.make("clock", UiStyle.MUTED, 22)
	row.add_child(_timer_icon)
	_timer = UiStyle.label("10:00", "head", 28, UiStyle.TEXT)
	_timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_timer)
	_alerts = HudAlerts.new()
	_safe_root.add_child(_alerts)
	_anchor(_alerts, 0.5, 0.0, Rect2(-300, 72, 600, 200))


func _build_menu_button() -> void:
	_menu_button = Button.new()
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.icon = UiIcons.texture("menu")
	_menu_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_button.add_theme_constant_override("icon_max_width", 28)
	var normal := _glass(14)
	var hover := _glass(14, 0.75)
	hover.border_color = UiStyle.with_alpha(UiStyle.ACCENT, 0.5)
	var pressed := _glass(14, 0.85)
	pressed.border_color = UiStyle.ACCENT
	_menu_button.add_theme_stylebox_override("normal", normal)
	_menu_button.add_theme_stylebox_override("hover", hover)
	_menu_button.add_theme_stylebox_override("pressed", pressed)
	_menu_button.add_theme_stylebox_override("hover_pressed", pressed)
	_menu_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		_menu_button.add_theme_color_override(state, UiStyle.TEXT)
	_menu_button.pressed.connect(func(): _set_menu(not _menu_open))
	UiMotion.attach_press(_menu_button)
	_safe_root.add_child(_menu_button)
	_anchor(_menu_button, 1.0, 0.0, Rect2(-80, 0, 80, 56))


func _build_status() -> void:
	_status = PanelContainer.new()
	var box := _glass(14, 0.78)
	box.content_margin_left = 16
	box.content_margin_right = 24
	_status.add_theme_stylebox_override("panel", box)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_safe_root.add_child(_status)
	_anchor(_status, 0.5, 1.0, Rect2(0, -150, 0, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.S2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_child(row)
	_status_icon = UiIcon.make("downed", UiStyle.AMBER, 44)
	row.add_child(_status_icon)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	_status_title = UiStyle.label("", "head", UiStyle.H3, UiStyle.AMBER)
	words.add_child(_status_title)
	_status_detail = UiStyle.label("", "body", 22, UiStyle.TEXT)
	words.add_child(_status_detail)
	_status_bar = Control.new()
	_status_bar.custom_minimum_size = Vector2(0, 4)
	_status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.draw.connect(func():
		_status_bar.draw_rect(Rect2(Vector2.ZERO, _status_bar.size), Color(1, 1, 1, 0.1))
		_status_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(_status_bar.size.x * _status_fraction, _status_bar.size.y)), UiStyle.AMBER))
	words.add_child(_status_bar)
	_status.modulate.a = 0.0
	_status.hide()


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.95, 32, 14))
	_menu.custom_minimum_size = Vector2(440, 0)
	add_child(_menu)
	_center(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiStyle.S2)
	_menu.add_child(box)
	box.add_child(UiStyle.label("MENU", "head", UiStyle.H3, UiStyle.TEXT))
	# Multiplayer can't pause: say so, so nobody thinks the round is frozen.
	var note := UiStyle.label("The round keeps running while this is open.", "body", UiStyle.LABEL, UiStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var resume := UiStyle.button("RESUME", true, UiStyle.ACCENT, "play", 64)
	resume.pressed.connect(func(): _set_menu(false))
	box.add_child(resume)
	var leave := UiStyle.button("LEAVE STATION", false, UiStyle.DANGER, "leave", 64)
	leave.pressed.connect(func(): leave_pressed.emit())
	box.add_child(leave)
	_menu.hide()


func _play_intro() -> void:
	# Top panels slide down 16 px, buttons rise 24 px, staggered 0/60/120 ms.
	var delay := 0.0
	for control: Control in [_top_panel, _timer_pill, _menu_button]:
		var target: float = control.offset_top
		control.offset_top = target - 16.0
		control.offset_bottom -= 16.0
		control.modulate.a = 0.0
		var tween := control.create_tween().set_parallel()
		tween.tween_property(control, "offset_top", target, UiMotion.ENTER).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(control, "offset_bottom", control.offset_bottom + 16.0, UiMotion.ENTER).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(control, "modulate:a", 1.0, 0.22).set_delay(delay)
		delay += 0.06
	create_tween().tween_property(self, "_intro", 1.0, 0.35).set_delay(0.12).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


# --- State updates from the world -------------------------------------------

func set_role(next_role: String) -> void:
	role = next_role
	var infiltrator := role == StationRules.INFILTRATOR
	var color := UiStyle.role_color(role)
	_briefing.set_role(role)
	_role_chip.queue_redraw()
	_role_word.add_theme_stylebox_override("panel", UiStyle.pill_box(color, 0.92, 12, 2))
	(_role_word.get_child(0).get_child(0) as UiIcon).icon = UiStyle.role_icon(role)
	_role_word_label.text = "INFILTRATOR" if infiltrator else "CREW"
	if not _touch:
		_hint.text = "WASD move  ·  Shift run  ·  RMB look  ·  E use  ·  F shove/throw  ·  R shoot%s  ·  Space jump" % ("  ·  Q blackout" if infiltrator else "")
	_controls.queue_redraw()


func update_state(rules: StationRules, action: Dictionary, my_id: int) -> void:
	var phase := rules.phase
	var briefing := phase == StationRules.Phase.BRIEFING and role != ""
	if briefing and not _briefing.visible:
		_center(_briefing)
		_briefing.play_in()
	if briefing:
		_briefing.set_seconds_left(StationRules.BRIEFING_SECONDS - rules.elapsed, StationRules.BRIEFING_SECONDS)
	elif _briefing.visible and not _briefing.leaving:
		_briefing.fly_to(_role_chip.get_global_rect().get_center(), func():
			UiMotion.pop(_role_chip, 0.0, 1.35, 0.3)
			_reveal_role())
	_update_timer(rules)
	_update_objective(rules, my_id)
	if _touch and phase == StationRules.Phase.STABILISE and rules.elapsed > StationRules.BRIEFING_SECONDS + 10.0:
		_first_touch()  # the hint has done its job; never leave it on screen
	_update_countdown(rules)
	_phase = phase
	_interact_label = action.get("label", "")
	_interact_enabled = not action.is_empty() and action.get("action") != "none"
	_set_use(_use_icon(action), _interact_label.to_upper() if _interact_label != "" else "USE")
	var me: Dictionary = rules.players.get(my_id, {})
	_carrying = str(me.get("holding", "")) != ""
	_shove_left = maxf(0.0, float(me.get("shove_ready", 0.0)) - rules.elapsed)
	_shove_ready = 1.0 - clampf(_shove_left / StationRules.SHOVE_COOLDOWN, 0.0, 1.0)
	_has_gun = rules.holds_gun(my_id)
	_ammo = rules.gun_ammo()
	_gun_ready = 1.0 - clampf((rules.gun_ready - rules.elapsed) / StationRules.GUN_COOLDOWN, 0.0, 1.0)
	_sabotage_cooldown = rules.sabotage_cooldown()
	_sabotage_ready = 1.0 - clampf(_sabotage_cooldown / StationRules.BLACKOUT_COOLDOWN, 0.0, 1.0)
	if phase == StationRules.Phase.BRIEFING:
		_sabotage_ready = 1.0  # don't show a 75 s sweep before the round has even started
		_sabotage_cooldown = 0.0
	if _auto_markers:
		_markers.set_markers(markers_for(rules, my_id))
	if phase == StationRules.Phase.RESULT and not _result.visible:
		_show_result(rules)
	_set_dim(_result.visible or _menu_open or briefing)


func _update_timer(rules: StationRules) -> void:
	var left := rules.time_left()
	var seconds := int(ceil(left))
	if seconds != _seconds_shown:
		_seconds_shown = seconds
		_timer.text = "%d:%02d" % [seconds / 60, seconds % 60]
		_timer_beat = 0.0


func _update_objective(rules: StationRules, my_id: int) -> void:
	var me: Dictionary = rules.players.get(my_id, {})
	var holding := str(me.get("holding", ""))
	var held_kind: String = rules.items[holding].kind if holding != "" and rules.items.has(holding) else ""
	var infiltrator := role == StationRules.INFILTRATOR
	match rules.phase:
		StationRules.Phase.BRIEFING:
			_set_phase("users", "BRIEFING", UiStyle.MUTED, -1)
			_set_objective("clock", "Find your role", UiStyle.TEXT)
			_core_row.hide()
		StationRules.Phase.STABILISE:
			_set_phase("bolt", "RESTORE POWER", UiStyle.AMBER, rules.powered_cells(), rules.reactor_socket_count())
			if held_kind == "cell":
				_set_objective("cell", "Take the cell to the Reactor", UiStyle.AMBER)
			else:
				_set_objective("cell", "Bring cells to the Reactor", UiStyle.AMBER)
			_core_row.hide()
		StationRules.Phase.EXTRACTION:
			_set_phase("bolt", "POWER ONLINE", UiStyle.GOOD, -1)
			if infiltrator:
				_set_objective("pod", "Core to the cargo pod  ·  Cargo", UiStyle.INFILTRATOR)
			else:
				_set_objective("shuttle", "Core to the shuttle  ·  Docking", UiStyle.CREW)
			_core_label.text = core_status(rules)
			_core_row.show()
		_:
			_core_row.hide()


func _set_phase(icon_name: String, text: String, color: Color, filled: int, total := 3) -> void:
	_phase_icon.icon = icon_name
	_phase_icon.color = color
	if _phase_label.text != text:
		# Theme overrides re-layout the panel, so only touch them on change.
		_phase_label.text = text
		_phase_label.add_theme_color_override("font_color", color)
		_progress.add_theme_color_override("font_color", color)
	var show_pips := filled >= 0
	_pips.visible = show_pips
	_progress.visible = show_pips
	if show_pips:
		_pips.custom_minimum_size = Vector2(total * 22 - 2, 22)
		_pips.set_meta("total", total)
		_progress.text = "%d/%d" % [filled, total]
		if filled != _cells_shown:
			if _cells_shown >= 0 and filled > _cells_shown:
				_pips.set_meta("pop", 1.0)
				# Amber flash on the panel when progress lands.
				var flash := _top_panel.create_tween()
				_top_panel.modulate = Color(1.5, 1.4, 1.0)
				flash.tween_property(_top_panel, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_cells_shown = filled
			_pips.set_meta("filled", filled)
		_pips.queue_redraw()


func _set_objective(icon_name: String, text: String, color: Color) -> void:
	_objective_icon.icon = icon_name
	_objective_icon.color = color
	if _objective.text != text:
		_objective.text = text
		_objective.modulate.a = 0.0
		UiMotion.fade(_objective, 1.0, 0.2)


## Where the core is, in words (names hidden during a blackout).
static func core_status(rules: StationRules) -> String:
	if not rules.items.has("core"):
		return ""
	var core: Dictionary = rules.items.core
	if not core.flight.is_empty():
		return "Core in the air"
	if int(core.holder) != 0:
		var holder := int(core.holder)
		var who: String = rules.players[holder].name if rules.players.has(holder) and not rules.is_blackout() else "someone"
		return "Core carried by %s" % who
	match str(core.socket):
		"vault":
			return "Core in the vault  ·  Command"
		"shuttle":
			return "Core loaded in the shuttle"
		"pod":
			return "Core in the cargo pod"
	var room := StationLayout.room_at(rules.item_position("core"))
	return "Core on the floor  ·  %s" % (StationLayout.ROOMS[room].name if room != "" else "corridor")


func _update_countdown(rules: StationRules) -> void:
	var active := rules.phase != StationRules.Phase.RESULT
	_cold = 0.0
	if rules.airlock_state == "warning" and active:
		_countdown.set_countdown("airlock", "AIRLOCK VENTING", rules.airlock_left, StationRules.AIRLOCK_WARNING)
		_danger = 0.8
	elif rules.pod_left >= 0.0 and active:
		_countdown.set_countdown("pod", "CARGO POD LAUNCH", rules.pod_left, StationRules.POD_SECONDS)
		_danger = 1.0
	elif rules.shuttle_left >= 0.0 and active:
		_countdown.set_countdown("shuttle", "SHUTTLE LAUNCH", rules.shuttle_left, StationRules.SHUTTLE_SECONDS)
		_danger = 0.0
	else:
		_countdown.set_countdown("", "", 0.0, 1.0)
		_danger = 0.0
		_cold = 1.0 if rules.is_blackout() and active else 0.0
	# One banner at a time while a P0 countdown owns the upper third.
	_alerts.max_visible = 1 if _countdown.kind != "" else HudAlerts.MAX_VISIBLE


func _use_icon(action: Dictionary) -> String:
	var label := str(action.get("label", ""))
	if USE_ICONS.has(label):
		return USE_ICONS[label]
	match str(action.get("action", "")):
		"revive":
			return "medbay"
		"drag":
			return "hand"
		"drop_body":
			return "drop"
		"airlock":
			return "airlock"
	return "hand"


## The USE button morphs: cross-fade icon and words over 120 ms on change.
func _set_use(icon_name: String, text: String) -> void:
	if icon_name == _use_to[0] and text == _use_to[1]:
		return
	_use_from = _use_to if _use_fade >= 0.5 else _use_from
	_use_to = [icon_name, text]
	_use_fade = 0.0


func mark_shove_used(rules: StationRules, my_id: int) -> void:
	if rules.players.has(my_id):
		rules.players[my_id].shove_ready = rules.elapsed + StationRules.SHOVE_COOLDOWN


## Markers for the world to draw (see set_world_markers): the core while it's
## loose during Extraction, the shuttle or pod during their countdowns, and
## downed crewmates for everyone.
static func markers_for(rules: StationRules, my_id: int) -> Array:
	var out := []
	if rules.phase == StationRules.Phase.RESULT or rules.phase == StationRules.Phase.BRIEFING:
		return out
	if rules.phase == StationRules.Phase.EXTRACTION and rules.items.has("core"):
		var core: Dictionary = rules.items.core
		if int(core.holder) == 0 and str(core.socket) == "" and core.flight.is_empty():
			out.append({"pos": rules.item_position("core") + Vector3(0, 0.8, 0), "kind": "core", "label": "Core"})
	if rules.shuttle_left >= 0.0:
		out.append({"pos": StationLayout.to_world(StationLayout.SOCKETS.shuttle.pos, 2.2), "kind": "shuttle", "label": "Shuttle"})
	if rules.pod_left >= 0.0:
		out.append({"pos": StationLayout.to_world(StationLayout.SOCKETS.pod.pos, 2.0), "kind": "pod", "label": "Cargo pod"})
	for id in rules.players:
		var player: Dictionary = rules.players[id]
		if id == my_id or player.state != StationRules.DOWNED or int(player.carried_by) != 0:
			continue
		var who: String = "Crewmate" if rules.is_blackout() else str(player.name)
		out.append({"pos": player.pos + Vector3(0, 0.9, 0), "kind": "downed", "label": who})
	return out


## World hook: replaces the HUD's own markers with the world's list.
## markers: Array of {pos: Vector3, kind: String, label: String}.
func set_world_markers(markers: Array) -> void:
	_auto_markers = false
	_markers.set_markers(markers)


func _set_dim(on: bool) -> void:
	var target := 1.0 if on else 0.0
	if is_equal_approx(_dim.get_meta("target", -1.0), target):
		return
	_dim.set_meta("target", target)
	if _dim_tween != null:
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_property(_dim, "modulate:a", target, 0.3 if on else 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_menu(open: bool) -> void:
	if open == _menu_open:
		return
	_menu_open = open
	reset_pointers()
	if crew != null:
		crew.input_enabled = not open
	if _menu_tween != null:
		_menu_tween.kill()
	if open:
		_menu.show()
		_menu.reset_size()
		_center(_menu)
		_menu_tween = UiMotion.card_in(_menu)
	else:
		_menu.pivot_offset = _menu.size * 0.5
		_menu_tween = create_tween().set_parallel()
		_menu_tween.tween_property(_menu, "modulate:a", 0.0, UiMotion.EXIT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_menu_tween.tween_property(_menu, "scale", Vector2(0.97, 0.97), UiMotion.EXIT)
		_menu_tween.chain().tween_callback(_menu.hide)
	_set_dim(open or _result.visible or _briefing.visible)


func _show_result(rules: StationRules) -> void:
	_set_menu(false)
	reset_pointers()
	if crew != null:
		crew.input_enabled = false
	_briefing.hide()
	_alerts.clear()
	_hint.hide()
	_center(_result, 632.0)
	_result.show_result(rules, role, is_host)


func _reveal_role() -> void:
	if role == "":
		return
	if _role_word_tween != null:
		_role_word_tween.kill()
	_role_word.reset_size()
	# Just under the objective panel, whatever its height right now.
	_role_word.offset_top = _top_panel.size.y + UiStyle.S1
	_role_word.offset_bottom = _role_word.offset_top
	_role_word_tween = _role_word.create_tween()
	_role_word_tween.tween_property(_role_word, "modulate:a", 1.0, 0.15)
	_role_word_tween.tween_interval(2.0)
	_role_word_tween.tween_property(_role_word, "modulate:a", 0.0, 0.25)


func flash_alert(text: String, kind: String) -> void:
	_alerts.push(text, kind)


## "ok", "downed" or "dead", with seconds until a downed player gets up.
func set_life_state(state: String, down_left: float) -> void:
	var changed := state != _life
	if changed:
		_life = state
		reset_pointers()
		if state == "ok":
			var tween := _status.create_tween()
			tween.tween_property(_status, "modulate:a", 0.0, UiMotion.EXIT)
			tween.tween_callback(_status.hide)
		else:
			_status.show()
			UiMotion.card_in(_status)
	match state:
		"downed":
			if changed:
				_status_icon.icon = "downed"
				_status_icon.color = UiStyle.AMBER
				_status_title.text = "YOU'RE DOWN"
				_status_title.add_theme_color_override("font_color", UiStyle.AMBER)
			_status_detail.text = "A crewmate can drag you to Medical  ·  up in %ds" % int(ceil(maxf(down_left, 0.0)))
			_status_fraction = clampf(down_left / StationRules.DOWN_SECONDS, 0.0, 1.0)
			_status_bar.visible = true
			_status_bar.queue_redraw()
		"dead":
			if not changed:
				return
			_status_icon.icon = "ghost"
			_status_icon.color = UiStyle.GHOST
			_status_title.text = "YOU WERE SPACED"
			_status_title.add_theme_color_override("font_color", UiStyle.GHOST)
			_status_detail.text = "You're a ghost now. Drift through walls and watch."
			_status_bar.visible = false


func _process(delta: float) -> void:
	_pulse += delta
	_markers.camera = camera
	if crew != null and is_instance_valid(crew):
		_markers.origin = crew.global_position
	# Vignette: red pulse for alarms (~1.6 Hz), cold tint in a blackout.
	var red := _danger * (0.55 + 0.45 * sin(_pulse * 10.0))
	var target := Color(0, 0, 0, 0.85)
	target = target.lerp(Color(0.01, 0.03, 0.09, 1.0), _cold)
	target = target.lerp(Color(0.75, 0.02, 0.06, 1.0), red * 0.85)
	_vignette.modulate = _vignette.modulate.lerp(target, 1.0 - exp(-delta * 8.0))
	_update_timer_look(delta)
	if _role_word.modulate.a > 0.0:
		_role_word.offset_top = _top_panel.size.y + UiStyle.S1
		_role_word.offset_bottom = _role_word.offset_top
	_fit(_menu)
	_fit(_result)
	_fit(_status, -112.0, true)
	if not _briefing.leaving:
		_fit(_briefing)
	if _pips.get_meta("pop") > 0.0:
		_pips.set_meta("pop", maxf(0.0, _pips.get_meta("pop") - delta / 0.35))
		_pips.queue_redraw()
	_update_controls(delta)


func _update_timer_look(delta: float) -> void:
	_timer_beat += delta
	var hot := 1.0 if _seconds_shown >= 0 and _seconds_shown < 60 else 0.0
	var heat := move_toward(_timer_heat, hot, delta / 0.4)
	if heat != _timer_heat or _seconds_shown < 0:
		_timer_heat = heat
		_timer.add_theme_color_override("font_color", UiStyle.TEXT.lerp(UiStyle.DANGER, _timer_heat))
		_timer_icon.color = UiStyle.MUTED.lerp(UiStyle.DANGER, _timer_heat)
		_timer_box.border_color = Color(1, 1, 1, 0.1).lerp(UiStyle.with_alpha(UiStyle.DANGER, 0.7), _timer_heat)
	# Below 60 s: a once-a-second pulse, bigger below 30 s.
	var amount := 0.0
	if _seconds_shown >= 0 and _seconds_shown < 60:
		amount = 0.06 if _seconds_shown < 30 else 0.03
	var beat := clampf(_timer_beat / 0.3, 0.0, 1.0)
	_timer_pill.pivot_offset = _timer_pill.size * 0.5
	_timer_pill.scale = Vector2.ONE * (1.0 + amount * (1.0 - beat) * (1.0 - beat))


# --- Touch controls: state -----------------------------------------------------

func _corner() -> Vector2:
	return Vector2(size.x - maxf(_margin.size.x - 24.0, 0.0), size.y - maxf(_margin.size.y - 20.0, 0.0))


func _stick_home() -> Vector2:
	return Vector2(_margin.position.x + 136.0, size.y - _margin.size.y - 136.0)


## Buttons that should exist right now.
func _wanted(id: String) -> bool:
	if _life != "ok" or _phase == StationRules.Phase.RESULT:
		return false
	match id:
		"sabotage":
			return role == StationRules.INFILTRATOR
		"shoot":
			return _has_gun
	return true


func _button_pos(id: String) -> Vector2:
	return _corner() - (BUTTONS[id][0] as Vector2)


func _hit_button(point: Vector2) -> String:
	var best := ""
	var best_distance := INF
	for id in BUTTONS:
		if _vis[id] < 0.5:
			continue
		var distance := point.distance_to(_button_pos(id))
		if distance <= float(BUTTONS[id][2]) and distance < best_distance:
			best = id
			best_distance = distance
	return best


func _ready_fraction(id: String) -> float:
	match id:
		"shove":
			return _shove_ready
		"shoot":
			return _gun_ready if _ammo > 0 else 0.0
		"sabotage":
			return _sabotage_ready
	return 1.0


func _update_controls(delta: float) -> void:
	if crew == null or not _touch:
		return
	for id in BUTTONS:
		var target := 1.0 if _wanted(id) else 0.0
		_vis[id] = move_toward(_vis[id], target, delta / (0.22 if target > 0.0 else 0.16))
		# Spring for press squash and ready pop (slight overshoot).
		# Substepped so a slow frame can't blow the spring up.
		var spring: Vector2 = _spring[id]
		var rest := 0.92 if _pressed.has(id) else 1.0
		var left := minf(delta, 0.1)
		while left > 0.0:
			var step := minf(left, 1.0 / 240.0)
			spring.y += ((rest - spring.x) * 900.0 - spring.y * 30.0) * step
			spring.x += spring.y * step
			left -= step
		spring.x = clampf(spring.x, 0.7, 1.3)
		_spring[id] = spring
		_flash[id] = maxf(0.0, _flash[id] - delta / 0.35)
		_deny[id] = maxf(0.0, _deny[id] - delta / 0.3)
		var ready := _ready_fraction(id) >= 1.0
		if ready and not _was_ready[id] and _vis[id] > 0.5 and id != "shoot":
			_flash[id] = 1.0
			_spring[id] = Vector2(_spring[id].x, _spring[id].y + 4.0)
			UiMotion.haptic(10)
		_was_ready[id] = ready
	# BLACKOUT: hold to fire.
	if _pressed.has("sabotage") and _sabotage_cooldown <= 0.0:
		_hold = minf(1.0, _hold + delta / HOLD_TO_FIRE)
		if _hold >= 1.0:
			_pressed.erase("sabotage")
			_hold = 0.0
			_flash["sabotage"] = 1.0
			UiMotion.haptic(25)
			action_pressed.emit("sabotage")
	else:
		_hold = move_toward(_hold, 0.0, delta / 0.15)
	_use_fade = minf(1.0, _use_fade + delta / 0.12)
	_use_on = move_toward(_use_on, 1.0 if _interact_enabled else 0.0, delta / 0.12)
	# Stick: follows the thumb, lingers, then drifts home and fades.
	if _move_finger >= 0:
		_stick_idle = 0.0
		_stick_center = _stick_origin
		_stick_knob = _stick_point
		_stick_alpha = move_toward(_stick_alpha, 1.0, delta / 0.08)
	else:
		_stick_idle += delta
		var blend := 1.0 - exp(-delta * 22.0)
		_stick_knob = _stick_knob.lerp(_stick_center, blend)
		if _stick_idle > STICK_LINGER:
			_stick_center = _stick_center.lerp(_stick_home(), 1.0 - exp(-delta * 8.0))
			_stick_knob = _stick_knob.lerp(_stick_center, blend)
		_stick_alpha = move_toward(_stick_alpha, 0.45, delta / 0.3)
	_controls.queue_redraw()


# --- Touch and keyboard input ------------------------------------------------

func _press(button_id: String) -> void:
	match button_id:
		"jump":
			crew.jump_pending = true
		"sabotage":
			if _sabotage_cooldown > 0.0:
				_deny[button_id] = 1.0
				return
			_hold = 0.0  # fires in _update_controls after HOLD_TO_FIRE
			UiMotion.haptic(10)
			return
		"interact":
			if not _interact_enabled:
				_deny[button_id] = 1.0
			action_pressed.emit(button_id)
		"shoot":
			if _ammo <= 0:
				_deny[button_id] = 1.0
			action_pressed.emit(button_id)
		_:
			if button_id == "shove" and _shove_ready < 1.0:
				_deny[button_id] = 1.0
			action_pressed.emit(button_id)
	UiMotion.haptic(12)


func reset_pointers() -> void:
	_move_finger = -1
	_look_finger = -1
	_pressed.clear()
	_hold = 0.0
	if crew != null:
		crew.clear_input()
	if _controls != null:
		_controls.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_pointers()


func _first_touch() -> void:
	if _hint.text != "" and _touch and not _hint.has_meta("fading"):
		_hint.set_meta("fading", true)
		var tween := _hint.create_tween()
		tween.tween_property(_hint, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func(): _hint.text = "")


func _input(event: InputEvent) -> void:
	if crew == null or _result.visible or _menu_open:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _result.visible:
			_set_menu(not _menu_open)
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
				if role == StationRules.INFILTRATOR and _sabotage_cooldown <= 0.0:
					action_pressed.emit("sabotage")
			KEY_R:
				if _has_gun:
					action_pressed.emit("shoot")
			KEY_TAB:
				_reveal_role()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		crew.look(event.relative)
	if event is InputEventScreenTouch:
		_touch = true
		if event.pressed:
			_first_touch()
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _move_finger:
			var offset: Vector2 = (event.position - _stick_origin).limit_length(STICK_TRAVEL)
			_stick_point = _stick_origin + offset
			var amount := offset.length() / STICK_TRAVEL
			# Dead zone, rescaled so the run threshold still sits at full tilt.
			var live := 0.0 if amount < STICK_DEAD else (amount - STICK_DEAD) / (1.0 - STICK_DEAD)
			crew.move_input = offset.normalized() * live if amount > 0.0 else Vector2.ZERO
		elif event.index == _look_finger:
			crew.look(event.relative * 1.2)


func _touch_down(index: int, point: Vector2) -> void:
	if _menu_button.get_global_rect().grow(8).has_point(point):
		return  # the Button handles it (touch is emulated as mouse)
	if _role_chip.get_global_rect().grow(8).has_point(point):
		_reveal_role()
		return
	var hit := _hit_button(point)
	if hit != "":
		_pressed[hit] = index
		_spring[hit] = Vector2(_spring[hit].x, -2.5)  # immediate squash on touch-down
		_press(hit)
		return
	if point.x < EDGE_GUARD or point.x > size.x - EDGE_GUARD:
		return
	if point.x < size.x * 0.42 and point.y > size.y * 0.35 and _move_finger == -1:
		_move_finger = index
		# Spawn where the thumb lands, nudged so the ring stays on screen.
		var low := Vector2(_margin.position.x + STICK_RING * 0.6, size.y * 0.35)
		var high := Vector2(size.x * 0.42, size.y - _margin.size.y - STICK_RING * 0.6)
		_stick_origin = point.clamp(low, high)
		_stick_point = point
		var offset := (point - _stick_origin).limit_length(STICK_TRAVEL)
		_stick_point = _stick_origin + offset
	elif _look_finger == -1:
		_look_finger = index


func _touch_up(index: int) -> void:
	if index == _move_finger:
		_move_finger = -1
		crew.move_input = Vector2.ZERO
	if index == _look_finger:
		_look_finger = -1
	for id in _pressed.keys():
		if _pressed[id] == index:
			_pressed.erase(id)


## Desktop shooting: a left click that no HUD button consumed.
func _unhandled_input(event: InputEvent) -> void:
	if crew == null or _result.visible or _menu_open or _touch or not _has_gun:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		action_pressed.emit("shoot")
		get_viewport().set_input_as_handled()


# --- Touch controls: drawing ---------------------------------------------------

func _draw_controls() -> void:
	if crew == null or _result.visible or not _touch:
		return
	var c := _controls
	var rise := (1.0 - _intro) * 24.0
	c.draw_set_transform(Vector2(0, rise), 0.0, Vector2.ONE)
	if _life != "downed":
		_draw_stick(c, _intro)
	for id in BUTTONS:
		if _vis[id] > 0.0:
			_draw_button(c, id)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stick(c: CanvasItem, intro: float) -> void:
	var alpha := _stick_alpha * intro
	var center := _stick_center
	var offset := _stick_knob - center
	var amount := clampf(offset.length() / STICK_TRAVEL, 0.0, 1.0)
	var running := _move_finger >= 0 and amount >= STICK_RUN
	var accent := UiStyle.ACCENT
	c.draw_circle(center, STICK_RING, Color(0.02, 0.04, 0.08, 0.38 * alpha))
	c.draw_arc(center, STICK_RING, 0.0, TAU, 72, Color(1, 1, 1, 0.16 * alpha), 2.0, true)
	for i in range(4):
		var angle := i * PI / 2.0
		c.draw_circle(center + Vector2.from_angle(angle) * (STICK_RING - 12.0), 2.5, Color(1, 1, 1, 0.3 * alpha))
	if amount > 0.05:
		# Direction arc on the ring; brighter and wider when running.
		var angle := offset.angle()
		var spread := 0.5 + 0.25 * amount
		c.draw_arc(center, STICK_RING, angle - spread, angle + spread, 24,
			UiStyle.with_alpha(accent, (0.5 + 0.5 * amount) * alpha), 4.0 if running else 3.0, true)
		if running:
			UiIcons.draw(c, "dart", center + Vector2.from_angle(angle) * (STICK_RING + 16.0), 18.0,
				UiStyle.with_alpha(accent, alpha), angle)
	c.draw_circle(_stick_knob, 34.0, UiStyle.with_alpha(accent, (0.22 + 0.18 * amount) * alpha))
	c.draw_circle(_stick_knob, 30.0, Color(0.02, 0.05, 0.1, 0.35 * alpha))
	c.draw_arc(_stick_knob, 32.0, 0.0, TAU, 48, UiStyle.with_alpha(accent, 0.9 * alpha), 2.5, true)


func _button_look(id: String) -> Dictionary:
	var color: Color = BUTTONS[id][3]
	var out := {"color": color, "icon": "hand", "text": "", "enabled": true, "count": ""}
	match id:
		"interact":
			out.enabled = _interact_enabled
		"shove":
			out.icon = "throw" if _carrying else "shove"
			out.text = "THROW" if _carrying else "SHOVE"
			if _shove_left > 1.5:
				out.count = str(int(ceil(_shove_left)))
		"jump":
			out.icon = "jump"
			out.text = "JUMP"
		"shoot":
			out.icon = "crosshair"
			out.text = "SHOOT" if _ammo > 0 else "EMPTY"
			out.enabled = _ammo > 0
		"sabotage":
			out.icon = "blackout"
			out.text = "BLACKOUT"
			if _sabotage_cooldown > 1.5:
				out.count = str(int(ceil(_sabotage_cooldown)))
			elif _sabotage_cooldown > 0.0:
				out.enabled = false
			if _pressed.has("sabotage") and out.count == "":
				out.text = "HOLD"
	return out


func _draw_button(c: CanvasItem, id: String) -> void:
	var spec: Array = BUTTONS[id]
	var look := _button_look(id)
	var color: Color = look.color
	var vis := _ease_out(_vis[id]) * _intro
	var pos := _button_pos(id)
	if _deny[id] > 0.0:
		pos.x += sin(_deny[id] * 28.0) * 6.0 * _deny[id]
	var pressed := _pressed.has(id)
	var radius: float = spec[1] * _spring[id].x * (0.7 + 0.3 * vis)
	var fraction := _ready_fraction(id)
	var cooling := fraction < 1.0
	var enabled: bool = look.enabled
	var lit := 1.0
	if id == "interact":
		lit = 0.45 + 0.55 * _use_on
	elif not enabled:
		lit = 0.5
	var alpha := vis
	# Body: soft shadow, glass, colour tint when it matters.
	c.draw_circle(pos + Vector2(0, 3), radius + 2.0, Color(0, 0, 0, 0.22 * alpha))
	var fill := Color(0.03, 0.06, 0.11, 0.46)
	if id == "interact":
		fill = fill.lerp(Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, 0.6), _use_on)
	if pressed:
		fill = fill.lightened(0.25)
	c.draw_circle(pos, radius, UiStyle.with_alpha(fill, fill.a * alpha))
	c.draw_arc(pos, radius - 1.0, 0.0, TAU, 72, Color(1, 1, 1, 0.12 * alpha), 2.0, true)
	# Cooldown: clockwise sweep from 12 o'clock.
	var ring_alpha := (0.9 if enabled else 0.4) * lit * alpha
	if fraction > 0.001:
		c.draw_arc(pos, radius - 1.0, -PI / 2.0, -PI / 2.0 + TAU * fraction, 72,
			UiStyle.with_alpha(color, ring_alpha if not cooling else 0.55 * alpha), 4.0, true)
	if _flash[id] > 0.0:
		var f: float = _flash[id]
		c.draw_arc(pos, radius + 4.0 + (1.0 - f) * 10.0, 0.0, TAU, 72, UiStyle.with_alpha(color, f * 0.8 * alpha), 3.0, true)
	if id == "sabotage" and _hold > 0.0:
		c.draw_circle(pos, radius * _ease_out(_hold), UiStyle.with_alpha(color, 0.3 * alpha))
		c.draw_arc(pos, radius + 6.0, -PI / 2.0, -PI / 2.0 + TAU * _hold, 72, UiStyle.with_alpha(Color.WHITE, 0.9 * alpha), 3.0, true)
	# Content.
	var content_alpha := alpha * lit
	if look.count != "":
		var font := UiStyle.font("head")
		var size_px := int(radius * 0.52)
		var width := font.get_string_size(look.count, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		UiIcons.draw(c, look.icon, pos, radius * 1.1, UiStyle.with_alpha(color, 0.12 * alpha))
		c.draw_string(font, pos + Vector2(-width * 0.5, size_px * 0.36), look.count, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px,
			UiStyle.with_alpha(UiStyle.TEXT, 0.85 * alpha))
	elif id == "interact":
		var t := _ease_out(_use_fade)
		if t < 1.0:
			_draw_content(c, pos, radius * (1.0 - 0.12 * t), _use_from[0], _use_from[1], UiStyle.with_alpha(UiStyle.TEXT, content_alpha * (1.0 - t)), UiStyle.with_alpha(color, content_alpha * (1.0 - t)))
		_draw_content(c, pos, radius * (0.88 + 0.12 * t), _use_to[0], _use_to[1], UiStyle.with_alpha(UiStyle.TEXT, content_alpha * t), UiStyle.with_alpha(color.lightened(0.3), content_alpha * t))
	else:
		_draw_content(c, pos, radius, look.icon, look.text, UiStyle.with_alpha(UiStyle.TEXT, content_alpha * 0.95), UiStyle.with_alpha(color, content_alpha))
	if id == "shoot":
		for pip in range(StationRules.GUN_AMMO):
			# One round = one bullet pip (rounded tip on a short body).
			var at := pos + Vector2((pip - (StationRules.GUN_AMMO - 1) / 2.0) * 13.0, radius + 15.0)
			var tint := UiStyle.with_alpha(color, alpha) if pip < _ammo else Color(1, 1, 1, 0.22 * alpha)
			c.draw_rect(Rect2(at + Vector2(-3.5, -3.0), Vector2(7.0, 9.0)), tint)
			c.draw_circle(at + Vector2(0, -3.0), 3.5, tint)


## Icon above a short label, fitted inside the circle (two lines when needed).
func _draw_content(c: CanvasItem, pos: Vector2, radius: float, icon_name: String, text: String, text_color: Color, icon_color: Color) -> void:
	if text_color.a <= 0.003 and icon_color.a <= 0.003:
		return
	var font := UiStyle.font("bold")
	var font_size := 20 if radius > 60.0 else 18
	var max_width := radius * 1.62
	var lines := PackedStringArray([text])
	if text != "" and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		font_size = 18
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			lines = _split_two(text)
	var icon_size := radius * (0.6 if lines.size() == 1 else 0.46)
	var icon_y := -radius * (0.16 if lines.size() == 1 else 0.3)
	if text == "":
		icon_size = radius * 0.7
		icon_y = 0.0
	UiIcons.draw(c, icon_name, pos + Vector2(0, icon_y), icon_size, icon_color)
	var line_height := font_size * 1.0
	var first_baseline := radius * (0.5 if lines.size() == 1 else 0.3)
	for i in range(lines.size()):
		var line := lines[i]
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := pos + Vector2(-width * 0.5, first_baseline + i * line_height)
		c.draw_string_outline(font, baseline, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.35 * text_color.a))
		c.draw_string(font, baseline, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _split_two(text: String) -> PackedStringArray:
	var best := -1
	for i in range(text.length()):
		if text[i] == " " and (best < 0 or absi(i - text.length() / 2) < absi(best - text.length() / 2)):
			best = i
	if best < 0:
		return PackedStringArray([text])
	return PackedStringArray([text.substr(0, best), text.substr(best + 1)])


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
