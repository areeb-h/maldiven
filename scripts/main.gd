extends Node
## Entry point: home screen (host / nearby stations / join by IP), lobby, and the
## in-round World. A live 3D flyover of the station sits behind the menus.
## Also starts the headless bot driver for automated tests.
##
## Layout: 8 px grid, UiStyle type scale, safe-area margins. Anchored so it
## holds at 1280×720, 1600×900 and 20:9 phones (1600×720 logical).

const SETTINGS_PATH := "user://settings.cfg"
const VERSION := "0.4.0"
const BotDriver = preload("res://scripts/dev/bot_driver.gd")
const PLAY_WIDTH := 480.0
const LOBBY_WIDTH := 640.0
const GUIDE_WIDTH := 456.0

var _ui: Control
var _safe: Control
var _home: Control
var _lobby: Control
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _rooms_box: VBoxContainer
var _scan: Control
var _banner: PanelContainer
var _banner_box: StyleBoxFlat
var _banner_icon: UiIcon
var _banner_title: Label
var _banner_body: Label
var _banner_action: Button
var _banner_spinner: Control
var _lobby_title: Label
var _lobby_share: HBoxContainer
var _lobby_hint: Label
var _lobby_count: Label
var _lobby_slots: Control
var _lobby_grid: GridContainer
var _lobby_waiting: HBoxContainer
var _start_button: Button
var _start_note: Label
var _bot_row: HBoxContainer  # host only: add / remove bot players (scripts/bots/)
var _add_bot_button: Button
var _remove_bot_button: Button
var _seen_ids := {}
var _world: StationWorld
var _backdrop: Node3D
var _orbit_camera: Camera3D
var _orbit_angle := 0.6
var _bot: Node
var _bot_args := {}
var _fader: ColorRect
var _fade_tween: Tween
var _time := 0.0
var _connecting := false
var _logo: UiLogo.View
var _logo_flip := 6.0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--dedicated"):
		set_process(false)  # headless PC server: no menus; scripts/server/ runs the session
		add_child(load("res://scripts/server/dedicated_server.gd").new())
		return
	_bot_args = _parse_bot_args()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiStyle.make_theme()
	_ui.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	_build_overlay()
	_safe = Control.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_safe)
	_build_home()
	_build_lobby()
	_ui.resized.connect(_update_safe_area)
	_update_safe_area()
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)
	_fader = ColorRect.new()
	_fader.color = Color(0.0, 0.0, 0.02, 1.0)
	_fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fader)
	Net.roster_changed.connect(_on_roster_changed)
	Net.session_ended.connect(_on_session_ended)
	Net.round_began.connect(_on_round_began)
	Net.returned_to_lobby.connect(_on_returned_to_lobby)
	Net.rooms_changed.connect(_refresh_rooms)
	_show_home("")
	_fade_in(0.8)
	if not _bot_args.is_empty():
		_bot = BotDriver.new()
		_bot.args = _bot_args
		_bot.main = self
		add_child(_bot)


func _parse_bot_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			out[parts[0]] = parts[1] if parts.size() > 1 else "1"
	return out


func _update_safe_area() -> void:
	var margin := UiStyle.safe_margins(_ui)
	_safe.offset_left = margin.position.x
	_safe.offset_top = margin.position.y
	_safe.offset_right = -margin.size.x
	_safe.offset_bottom = -margin.size.y


# --- Backdrop ----------------------------------------------------------------

func _ensure_backdrop() -> void:
	if _backdrop != null or DisplayServer.get_name() == "headless":
		return
	_backdrop = Node3D.new()
	_backdrop.name = "MenuBackdrop"
	add_child(_backdrop)
	var station := StationBuilder.build(_backdrop)
	StationBuilder.set_power_state(station, "restored")
	_orbit_camera = Camera3D.new()
	_orbit_camera.fov = 50
	_orbit_camera.far = 2000.0
	_backdrop.add_child(_orbit_camera)
	_orbit_camera.current = true
	_update_orbit(0.0)


func _free_backdrop() -> void:
	if _backdrop != null:
		_backdrop.queue_free()
	_backdrop = null
	_orbit_camera = null


func _update_orbit(delta: float) -> void:
	if _orbit_camera == null:
		return
	_orbit_angle += delta * 0.035
	var center := Vector3(31, 0, 0)
	var offset := Vector3(cos(_orbit_angle) * 58.0, 34.0 + sin(_orbit_angle * 0.7) * 4.0, sin(_orbit_angle) * 44.0)
	_orbit_camera.position = center + offset
	_orbit_camera.look_at(center + Vector3(-6, 0, 0), Vector3.UP)


func _process(delta: float) -> void:
	_time += delta
	_update_orbit(delta)
	if _home.visible:
		_scan.queue_redraw()
		# The tell: now and then the helmet's eyes snap to the red V for a beat.
		_logo_flip -= delta
		if _logo_flip <= 0.0:
			_logo_flip = 7.0 + randf() * 5.0
			var tween := _logo.create_tween()
			tween.tween_method(func(b: float): _logo.state_blend = b, 0.0, 0.5, 0.06)
			tween.tween_callback(func(): _logo.state_blend = 1.0)
			tween.tween_interval(0.9)
			tween.tween_method(func(b: float): _logo.state_blend = b, 0.5, 0.49, 0.06)
			tween.tween_callback(func(): _logo.state_blend = 0.0)
		if _banner_spinner.visible:
			_banner_spinner.queue_redraw()
	if _lobby.visible and _lobby_waiting.visible:
		_lobby_waiting.get_child(0).queue_redraw()


func _build_overlay() -> void:
	# Fallback colour when there's no 3D backdrop (headless or while loading).
	var base := ColorRect.new()
	base.name = "Base"
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.color = UiStyle.BG
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(base)
	# Left-to-right darkening so text reads over the flyover.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.01, 0.02, 0.05, 0.94))
	gradient.set_color(1, Color(0.01, 0.02, 0.05, 0.25))
	gradient.add_point(0.5, Color(0.01, 0.02, 0.05, 0.62))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	var shade := TextureRect.new()
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)


func _set_backdrop_visible(on: bool) -> void:
	var base := _ui.get_node_or_null("Base") as ColorRect
	if on:
		_ensure_backdrop()
	if base != null:
		base.visible = _backdrop == null


# --- Layout helpers ----------------------------------------------------------

func _screen(parent: Control) -> Control:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(screen)
	return screen


## A vertically centred column pinned to the left or right edge of the safe area.
func _column(screen: Control, width: float, right := false, inset := 48.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0 if right else 0.0
	box.anchor_right = box.anchor_left
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -inset - width if right else inset
	box.offset_right = -inset if right else inset + width
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(box)
	return box


func _spacer(box: Container, height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)


func _field(placeholder: String, text := "") -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = text
	edit.custom_minimum_size = Vector2(0, 56)
	edit.add_theme_font_size_override("font_size", 26)
	edit.add_theme_font_override("font", UiStyle.font("bold"))
	edit.select_all_on_focus = true
	return edit


## A pulsing dot (waiting / scanning indicator).
func _pulse_dot(color: Color) -> Control:
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(16, 16)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.draw.connect(func():
		var t := fmod(_time * 0.8, 1.0)
		dot.draw_circle(Vector2(8, 8), 4.0 + 6.0 * t, UiStyle.with_alpha(color, 0.35 * (1.0 - t)))
		dot.draw_circle(Vector2(8, 8), 4.0, color))
	return dot


# --- Home --------------------------------------------------------------------

func _build_home() -> void:
	_home = _screen(_safe)
	# Left: branding.
	var brand := _column(_home, 620.0)
	brand.add_theme_constant_override("separation", UiStyle.S2)
	var tag := UiStyle.chip("WEEK 1 BUILD  ·  v%s" % VERSION, UiStyle.ACCENT, "", false)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.add_child(tag)
	# The logo lockup (UiLogo): DRIFT over STATION, the O a crew helmet. Every
	# so often its visor glitches to the infiltrator's red V and back.
	_logo = UiStyle.logo(176.0, "crew")
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.add_child(_logo)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(lines)
	lines.add_child(UiStyle.label("Restore the power. Save the core.", "light", 30, UiStyle.MUTED))
	lines.add_child(UiStyle.label("Trust no one.", "bold", 30, UiStyle.AMBER))
	_spacer(brand, UiStyle.S1)
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", UiStyle.S1)
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(facts)
	for fact in [["users", "2–8 friends"], ["mask", "1 infiltrator"], ["clock", "10 min rounds"]]:
		facts.add_child(UiStyle.chip(fact[1].to_upper(), UiStyle.TEXT, fact[0], false))
	# Right: play panel.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.84, 24, 14))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PLAY_WIDTH - 32.0
	panel.offset_right = -32.0
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_home.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiStyle.S1)
	panel.add_child(box)
	box.add_child(UiStyle.caption("CALLSIGN", UiStyle.MUTED, "user"))
	_name_edit = _field("Your name", _load_setting("name"))
	_name_edit.custom_minimum_size.y = 72
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(_text): _save_setting("name", _name_edit.text.strip_edges()))
	box.add_child(_name_edit)
	_spacer(box, UiStyle.S1)
	var host_button := UiStyle.button("HOST A STATION", true, UiStyle.ACCENT, "play", 80)
	host_button.pressed.connect(_on_host)
	box.add_child(host_button)
	_spacer(box, UiStyle.S2)
	var nearby := HBoxContainer.new()
	nearby.add_theme_constant_override("separation", UiStyle.S1)
	box.add_child(nearby)
	var nearby_caption := UiStyle.caption("NEARBY STATIONS", UiStyle.MUTED, "wifi")
	nearby_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nearby.add_child(nearby_caption)
	_scan = Control.new()
	_scan.custom_minimum_size = Vector2(56, 20)
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan.draw.connect(_draw_scan)
	nearby.add_child(_scan)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 120)
	box.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", UiStyle.S1)
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rooms_box)
	_spacer(box, UiStyle.S1)
	box.add_child(UiStyle.caption("JOIN BY IP", UiStyle.MUTED, "signal"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.S2)
	box.add_child(row)
	_ip_edit = _field("192.168.1.20  or  name.playit.gg:12345", _load_setting("last_address"))
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_ip_edit.text_submitted.connect(func(text): _join(text))
	row.add_child(_ip_edit)
	_ip_edit.custom_minimum_size.y = 80
	var join_button := UiStyle.button("JOIN", false, UiStyle.ACCENT, "chevron", 80)
	join_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	join_button.custom_minimum_size.x = 128
	join_button.pressed.connect(func(): _join(_ip_edit.text))
	row.add_child(join_button)
	_build_banner(box)


func _draw_scan() -> void:
	# Three dots that light in turn while we listen for stations.
	for i in range(3):
		var t := fmod(_time * 1.6 - i * 0.22, 1.0)
		var a := 0.25 + 0.75 * maxf(0.0, sin(t * PI))
		_scan.draw_circle(Vector2(_scan.size.x - 40 + i * 16, _scan.size.y * 0.5), 3.5, UiStyle.with_alpha(UiStyle.GOOD, a))


## Inline message under the join row: an icon, a short title, one sentence and
## (optionally) one action. Errors are plain and specific.
func _build_banner(box: VBoxContainer) -> void:
	_banner = PanelContainer.new()
	_banner_box = UiStyle.inset_box(0.45, 10, 12)
	_banner_box.border_width_left = 4
	_banner.add_theme_stylebox_override("panel", _banner_box)
	box.add_child(_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_banner.add_child(row)
	_banner_icon = UiIcon.make("warning", UiStyle.DANGER, 28)
	_banner_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_banner_icon)
	_banner_spinner = Control.new()
	_banner_spinner.custom_minimum_size = Vector2(28, 28)
	_banner_spinner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_banner_spinner.draw.connect(func():
		var start := _time * 5.0
		_banner_spinner.draw_arc(Vector2(14, 14), 10.0, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 3.0, true)
		_banner_spinner.draw_arc(Vector2(14, 14), 10.0, start, start + 1.8, 24, UiStyle.ACCENT, 3.0, true))
	row.add_child(_banner_spinner)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	_banner_title = UiStyle.label("", "bold", 22, UiStyle.TEXT)
	words.add_child(_banner_title)
	_banner_body = UiStyle.label("", "body", UiStyle.LABEL, UiStyle.MUTED)
	_banner_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(_banner_body)
	_banner_action = Button.new()
	_banner_action.flat = true
	_banner_action.focus_mode = Control.FOCUS_NONE
	_banner_action.icon = UiIcons.texture("close")
	_banner_action.add_theme_constant_override("icon_max_width", 20)
	_banner_action.custom_minimum_size = Vector2(80, 80)
	_banner_action.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_banner_action.add_theme_color_override("icon_normal_color", UiStyle.MUTED)
	_banner_action.add_theme_color_override("icon_hover_color", UiStyle.TEXT)
	_banner_action.add_theme_color_override("icon_pressed_color", UiStyle.TEXT)
	_banner_action.add_theme_color_override("font_color", UiStyle.ACCENT)
	_banner_action.add_theme_color_override("font_hover_color", UiStyle.TEXT)
	_banner_action.add_theme_font_override("font", UiStyle.font("bold"))
	_banner_action.add_theme_font_size_override("font_size", UiStyle.LABEL)
	_banner_action.pressed.connect(_on_banner_action)
	UiMotion.attach_press(_banner_action)
	row.add_child(_banner_action)
	_banner.hide()


## kind: "error" or "busy". Empty title hides the banner.
func _show_banner(kind: String, title: String, body := "") -> void:
	if title == "":
		if _banner.visible:
			var tween := UiMotion.fade(_banner, 0.0, UiMotion.EXIT)
			tween.tween_callback(_banner.hide)
		return
	var color := UiStyle.ACCENT if kind == "busy" else UiStyle.DANGER
	_banner_box.border_color = color
	_banner_icon.visible = kind != "busy"
	_banner_icon.color = color
	_banner_spinner.visible = kind == "busy"
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color.lightened(0.2) if kind != "busy" else UiStyle.TEXT)
	_banner_body.text = body
	_banner_body.visible = body != ""
	_banner_action.text = "CANCEL" if kind == "busy" else ""
	_banner_action.icon = null if kind == "busy" else UiIcons.texture("close")
	_banner_action.custom_minimum_size = Vector2(112 if kind == "busy" else 80, 80)
	_banner.show()
	_banner.modulate.a = 0.0
	UiMotion.fade(_banner, 1.0, 0.2)
	if kind == "error":
		# A short shake says "that didn't work" without a modal.
		var tween := _banner.create_tween()
		for i in range(4):
			tween.tween_property(_banner, "position:x", 6.0 * (1 if i % 2 == 0 else -1), 0.04)
		tween.tween_property(_banner, "position:x", 0.0, 0.05)


func _on_banner_action() -> void:
	if _connecting:
		_connecting = false
		Net.leave()
	_show_banner("", "")


# --- Lobby -------------------------------------------------------------------

func _build_lobby() -> void:
	_lobby = _screen(_safe)
	var box := _column(_lobby, LOBBY_WIDTH)
	box.add_theme_constant_override("separation", UiStyle.S1)
	box.add_child(UiStyle.caption("STATION LOBBY", UiStyle.ACCENT, "users"))
	_lobby_title = UiStyle.label("", "head", UiStyle.H2, UiStyle.TEXT)
	_lobby_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lobby_title.custom_minimum_size = Vector2(LOBBY_WIDTH, 0)
	box.add_child(_lobby_title)
	# Host: the address as chips with copy buttons. Guest: a waiting line.
	_lobby_share = HBoxContainer.new()
	_lobby_share.add_theme_constant_override("separation", UiStyle.S1)
	box.add_child(_lobby_share)
	_lobby_hint = UiStyle.label("", "body", UiStyle.LABEL, UiStyle.MUTED)
	_lobby_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lobby_hint)
	_lobby_waiting = HBoxContainer.new()
	_lobby_waiting.add_theme_constant_override("separation", 12)
	_lobby_waiting.add_child(_pulse_dot(UiStyle.ACCENT))
	_lobby_waiting.add_child(UiStyle.label("Waiting for the host to start the round…", "body", 22, UiStyle.TEXT))
	box.add_child(_lobby_waiting)
	_spacer(box, UiStyle.S1)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.8, 20, 14))
	box.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", UiStyle.S2)
	panel.add_child(inner)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiStyle.S1)
	inner.add_child(head)
	var head_caption := UiStyle.caption("CREW ABOARD", UiStyle.MUTED)
	head.add_child(head_caption)
	_lobby_count = UiStyle.label("", "head", UiStyle.LABEL, UiStyle.ACCENT)
	_lobby_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_lobby_count)
	_lobby_slots = Control.new()
	_lobby_slots.custom_minimum_size = Vector2(8 * 14, 20)
	_lobby_slots.draw.connect(func():
		for i in range(Net.MAX_PLAYERS):
			var filled := i < Net.roster.size()
			var at := Vector2(5 + i * 14, 10)
			if filled:
				_lobby_slots.draw_circle(at, 5.0, UiStyle.ACCENT)
			else:
				_lobby_slots.draw_arc(at, 4.5, 0.0, TAU, 16, Color(1, 1, 1, 0.25), 1.5, true))
	head.add_child(_lobby_slots)
	# Host: fill seats with bot players (they play the round like anyone else).
	_bot_row = HBoxContainer.new()
	_bot_row.add_theme_constant_override("separation", UiStyle.S1)
	head.add_child(_bot_row)
	_add_bot_button = UiStyle.button("ADD BOT", false, UiStyle.ACCENT, "gear", 80)
	_add_bot_button.add_theme_font_size_override("font_size", 22)
	_add_bot_button.pressed.connect(func(): Net.add_bot())
	_bot_row.add_child(_add_bot_button)
	_remove_bot_button = UiStyle.button("REMOVE", false, UiStyle.MUTED, "close", 80)
	_remove_bot_button.add_theme_font_size_override("font_size", 22)
	_remove_bot_button.pressed.connect(func(): Net.remove_bot())
	_bot_row.add_child(_remove_bot_button)
	_lobby_grid = GridContainer.new()
	_lobby_grid.columns = 2
	_lobby_grid.add_theme_constant_override("h_separation", UiStyle.S1)
	_lobby_grid.add_theme_constant_override("v_separation", UiStyle.S1)
	inner.add_child(_lobby_grid)
	_spacer(box, UiStyle.S1)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", UiStyle.S2)
	box.add_child(buttons)
	_start_button = UiStyle.button("START ROUND", true, UiStyle.ACCENT, "play", 80)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(func(): Net.start_round())
	buttons.add_child(_start_button)
	var leave := UiStyle.button("LEAVE", false, UiStyle.ACCENT, "leave", 80)
	leave.custom_minimum_size.x = 176
	leave.pressed.connect(func():
		Net.leave()
		_show_home(""))
	buttons.add_child(leave)
	_start_note = UiStyle.label("", "body", UiStyle.CAPTION, UiStyle.MUTED)
	box.add_child(_start_note)
	# How-to card on the right.
	var guide := PanelContainer.new()
	guide.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.AMBER, 0.8, 24, 14))
	guide.anchor_left = 1.0
	guide.anchor_right = 1.0
	guide.anchor_top = 0.5
	guide.anchor_bottom = 0.5
	guide.offset_left = -GUIDE_WIDTH - 32.0
	guide.offset_right = -32.0
	guide.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lobby.add_child(guide)
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", UiStyle.S2)
	guide.add_child(steps)
	steps.add_child(UiStyle.label("HOW A ROUND WORKS", "head", 20, UiStyle.AMBER))
	for line in [
		["cell", UiStyle.AMBER, "Power is out. Carry 3 cells to the Reactor."],
		["vault", UiStyle.ACCENT, "Power returns and the core vault in Command opens."],
		["shuttle", UiStyle.CREW, "Crew win by loading the core into the shuttle in Docking."],
		["mask", UiStyle.INFILTRATOR, "One of you is the infiltrator, racing for the cargo pod."],
		["shove", UiStyle.TEXT, "Shove carriers to make them drop. Watch for blackouts."],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiStyle.S2)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiStyle.pill_box(line[1], 0.14, 8, 8))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(UiIcon.make(line[0], line[1], 24))
		row.add_child(chip)
		var text := UiStyle.label(line[2], "body", 22, UiStyle.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text)
		steps.add_child(UiMotion.slide(row))
	_lobby.set_meta("steps", steps)
	var mark := UiStyle.logo(36.0, "crew", "wordmark")
	mark.anchor_left = 1.0
	mark.anchor_right = 1.0
	mark.offset_left = -32.0 - 36.0 * UiLogo.aspect("wordmark")
	mark.offset_right = -32.0
	mark.offset_top = 8.0
	mark.offset_bottom = 44.0
	_lobby.add_child(mark)


## One crew card: suit swatch, LED face in the suit colour, name, HOST/YOU chips.
func _player_card(entry: Dictionary, host: bool, me: bool) -> Control:
	var card := PanelContainer.new()
	var box := UiStyle.inset_box(0.42, 10, 8)
	box.border_width_left = 4
	box.border_color = entry.color
	if me:
		box.border_width_top = 1
		box.border_width_right = 1
		box.border_width_bottom = 1
		box.border_color = entry.color
		box.bg_color = Color(entry.color.r * 0.12, entry.color.g * 0.12, entry.color.b * 0.12, 0.55)
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size = Vector2(0, 60)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var face := Control.new()
	face.custom_minimum_size = Vector2(44, 44)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var color: Color = entry.color
	face.draw.connect(func():
		var plate := UiStyle.pill_box(color, 0.18)
		plate.set_corner_radius_all(12)
		face.draw_style_box(plate, Rect2(Vector2.ZERO, face.size))
		UiIcons.draw(face, "face", face.size * 0.5, 34.0, color))
	row.add_child(face)
	var name_label := UiStyle.label(str(entry.name), "bold", 24, UiStyle.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)
	if bool(entry.get("bot", false)):
		row.add_child(UiStyle.chip("BOT", UiStyle.MUTED, "gear", false))
	if host:
		row.add_child(UiStyle.chip("HOST", UiStyle.AMBER, "crown", false))
	if me:
		row.add_child(UiStyle.chip("YOU", UiStyle.ACCENT))
	card.set_meta("face", face)
	return card


func _empty_card() -> Control:
	var card := PanelContainer.new()
	var box := UiStyle.inset_box(0.16, 10, 8)
	box.border_color = Color(1, 1, 1, 0.08)
	box.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size = Vector2(0, 60)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := UiStyle.label("Open seat", "body", UiStyle.LABEL, UiStyle.FAINT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(text)
	return card


## The host's address as a chip with a copy button ("Copied" for 600 ms).
func _address_chip(address: String) -> Control:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.text = address
	button.icon = UiIcons.texture("copy")
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.add_theme_constant_override("icon_max_width", 20)
	button.add_theme_constant_override("h_separation", 12)
	var normal := UiStyle.tag_box(UiStyle.ACCENT, 16, 6)
	var hover := UiStyle.tag_box(UiStyle.ACCENT.lightened(0.2), 16, 6)
	hover.bg_color = UiStyle.with_alpha(UiStyle.ACCENT, 0.26)
	for state in ["normal", "focus"]:
		button.add_theme_stylebox_override(state, normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, hover)
	button.add_theme_font_override("font", UiStyle.font("head"))
	button.add_theme_font_size_override("font_size", UiStyle.LABEL)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, UiStyle.ACCENT.lightened(0.2))
	button.custom_minimum_size = Vector2(0, 80)
	button.tooltip_text = "Copy the address"
	UiMotion.attach_press(button)
	button.pressed.connect(func():
		DisplayServer.clipboard_set(address)
		button.text = "COPIED"
		button.icon = UiIcons.texture("check")
		get_tree().create_timer(0.9).timeout.connect(func():
			if is_instance_valid(button):
				button.text = address
				button.icon = UiIcons.texture("copy")))
	return button


# --- Settings ----------------------------------------------------------------

func _load_setting(key: String) -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return str(config.get_value("player", key, ""))
	return ""


func _save_setting(key: String, value: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep the other keys
	config.set_value("player", key, value)
	config.save(SETTINGS_PATH)


# --- Flow --------------------------------------------------------------------

func _on_host() -> void:
	_save_setting("name", _name_edit.text.strip_edges())
	var error := Net.host(_name_edit.text)
	if error != OK:
		_show_banner("error", "Couldn't host a station",
			"Port %d is busy. Close any other copy of Drift Station on this device and try again." % Net.PORT)
		return
	_show_lobby()


func _join(address: String) -> void:
	var clean := address.strip_edges()
	if clean.is_empty():
		_show_banner("error", "Type the host's IP address", "It's on the host's lobby screen, like 192.168.1.20.")
		return
	var parsed := NetAddress.parse(clean, Net.PORT)
	if not parsed.ok:
		_show_banner("error", "That address doesn't look right", NetAddress.explain(parsed.error))
		return
	_save_setting("name", _name_edit.text.strip_edges())
	_save_setting("last_address", clean)
	var result := Net.join(clean, _name_edit.text)
	if result == ERR_CANT_RESOLVE:
		_show_banner("error", "Couldn't find %s" % parsed.host, "Check the spelling, and that this phone has internet (or Tailscale) on.")
		return
	if result != OK:
		_show_banner("error", "Couldn't start joining", "Check the address and try again.")
		return
	_connecting = true
	_show_banner("busy", "Connecting to %s…" % clean)


## Turn Net's messages into a short title and one plain sentence.
func _friendly(message: String) -> Array:
	var lower := message.to_lower()
	if lower.contains("could not reach"):
		return ["Couldn't reach that station", "Check the address. On Wi-Fi, both devices need the same network; over Tailscale, both need Tailscale on; with a tunnel, include the :port."]
	if lower.contains("shut down the server"):
		return ["The station server shut down", "The host stopped the server. Ask them to start it again."]
	if lower.contains("closed the station"):
		return ["The station closed", "The host left or closed the game."]
	if lower.contains("round is in progress"):
		return ["A round is in progress", "Try again when it ends. It's never more than 10 minutes."]
	if lower.contains("full"):
		return ["That station is full", "All %d seats are taken." % Net.MAX_PLAYERS]
	if lower.contains("version"):
		return ["Different game versions", "Update Drift Station on every device, then try again."]
	return ["Something went wrong", message]


func _show_home(message: String) -> void:
	_free_world()
	_connecting = false
	_set_backdrop_visible(true)
	Sfx.set_music("lobby")
	_ui.show()
	_switch_to(_home)
	_logo.play_intro(0.15)
	if message != "":
		var words := _friendly(message)
		_show_banner("error", words[0], words[1])
	else:
		_show_banner("", "")
	Net.start_listening()
	_refresh_rooms()


func _show_lobby() -> void:
	_free_world()
	_connecting = false
	_banner.hide()
	_set_backdrop_visible(true)
	Net.stop_listening()
	_ui.show()
	_seen_ids.clear()
	Sfx.set_music("lobby")
	_switch_to(_lobby)
	_on_roster_changed()
	var delay := 0.12
	for slot in (_lobby.get_meta("steps") as VBoxContainer).get_children():
		if slot is UiMotion.Slide:
			slot.play_in(delay, Vector2(24, 0))
			delay += UiMotion.STAGGER


## Screen change: the old screen leaves (180 ms) as the new one enters (280 ms).
func _switch_to(screen: Control) -> void:
	for other: Control in [_home, _lobby]:
		if other != screen and other.visible:
			var tween := other.create_tween().set_parallel()
			tween.tween_property(other, "modulate:a", 0.0, UiMotion.EXIT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tween.tween_property(other, "position:y", -12.0, UiMotion.EXIT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tween.chain().tween_callback(other.hide)
	screen.show()
	screen.modulate.a = 0.0
	screen.position.y = 24.0
	var tween := screen.create_tween().set_parallel()
	tween.tween_property(screen, "modulate:a", 1.0, UiMotion.ENTER).set_delay(0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(screen, "position:y", 0.0, UiMotion.ENTER + 0.06).set_delay(0.06).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func _refresh_rooms() -> void:
	if _rooms_box == null:
		return
	for child in _rooms_box.get_children():
		child.queue_free()
	if Net.rooms.is_empty():
		var empty := HBoxContainer.new()
		empty.add_theme_constant_override("separation", 12)
		empty.custom_minimum_size = Vector2(0, 56)
		var radar := UiIcon.make("wifi", UiStyle.FAINT, 24)
		empty.add_child(radar)
		var words := UiStyle.label("Looking for stations on your Wi-Fi…", "body", 22, UiStyle.FAINT)
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		empty.add_child(words)
		_rooms_box.add_child(empty)
		return
	var index := 0
	for ip in Net.rooms:
		var room: Dictionary = Net.rooms[ip]
		var slot := UiMotion.slide(_room_card(ip, room))
		_rooms_box.add_child(slot)
		slot.play_in(index * UiMotion.STAGGER, Vector2(0, 12), 0.22)
		index += 1


func _room_card(ip: String, room: Dictionary) -> Control:
	var playing: bool = room.state == "playing"
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 80)
	button.disabled = playing
	var color := UiStyle.MUTED if playing else UiStyle.GOOD
	var normal := UiStyle.inset_box(0.4, 10, 0)
	normal.border_width_left = 4
	normal.border_color = color
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UiStyle.with_alpha(UiStyle.GOOD, 0.14)
	for state in ["normal", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, normal)
	for state in ["hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, hover)
	button.pressed.connect(func(): _join(ip))
	UiMotion.attach_press(button, 1.01, 0.97)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -12
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var name_label := UiStyle.label(str(room.name), "bold", 24, UiStyle.TEXT if not playing else UiStyle.FAINT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)
	if playing:
		row.add_child(UiStyle.chip("IN A ROUND", UiStyle.MUTED, "clock", false))
	row.add_child(UiStyle.chip("%d/%d" % [room.players, Net.MAX_PLAYERS], color, "users", false))
	if not playing:
		row.add_child(UiIcon.make("chevron", UiStyle.GOOD, 20))
	return button


func _on_roster_changed() -> void:
	if Net.is_online() and not Net.in_round and not _lobby.visible and _world == null:
		_show_lobby()
		return
	if not _lobby.visible:
		return
	_lobby_title.text = (Net.room_name if Net.room_name != "" else "Station").to_upper()
	var host := Net.is_host()
	for child in _lobby_share.get_children():
		child.queue_free()
	_lobby_share.visible = host
	_lobby_waiting.visible = not host
	if host:
		var addresses := Net.local_addresses()
		for address in addresses.slice(0, 2):
			_lobby_share.add_child(_address_chip(address))
		_lobby_hint.text = "Friends on the same Wi-Fi see this station automatically, or can join by IP." if not addresses.is_empty() \
			else "Friends on the same Wi-Fi see this station automatically."
	_lobby_hint.visible = host
	_lobby_count.text = "%d / %d" % [Net.roster.size(), Net.MAX_PLAYERS]
	_lobby_slots.queue_redraw()
	for child in _lobby_grid.get_children():
		child.queue_free()
	var ids := Net.roster.keys()
	ids.sort()
	var slots := maxi(4, ids.size() + (ids.size() % 2))
	for index in range(slots):
		if index >= ids.size():
			_lobby_grid.add_child(_empty_card())
			continue
		var id: int = ids[index]
		var card := _player_card(Net.roster[id], id == 1, id == Net.my_id())
		var slot := UiMotion.slide(card)
		_lobby_grid.add_child(slot)
		if not _seen_ids.has(id):
			# Someone joined: their card slides in and their face pops.
			_seen_ids[id] = true
			slot.play_in(0.04 * index if _seen_ids.size() <= ids.size() else 0.0, Vector2(-24, 0))
			var face: Control = card.get_meta("face")
			face.pivot_offset = face.custom_minimum_size * 0.5
			UiMotion.pop(face, 0.12 + 0.04 * index, 0.4, 0.34)
	_start_button.visible = host
	_start_note.visible = host
	_bot_row.visible = host
	_lobby_slots.visible = not host
	_add_bot_button.disabled = Net.roster.size() >= Net.max_players
	_remove_bot_button.disabled = Net.bot_ids().is_empty()
	if host:
		var solo := Net.roster.size() < 2
		_start_button.text = "START SOLO WALKAROUND" if solo else "START ROUND"
		_start_note.text = "Roles are dealt with 2 or more crew. Solo is a walkaround." if solo \
			else "One of the %d crew will secretly be the infiltrator." % Net.roster.size()


func _on_session_ended(message: String) -> void:
	_show_home(message)


func _on_round_began() -> void:
	_free_world()
	_free_backdrop()
	var seed := int(_bot_args.get("bot-seed", "-1"))
	_world = StationWorld.new(seed)
	_world.leave_requested.connect(func():
		Net.leave()
		_show_home(""))
	add_child(_world)
	_ui.hide()
	_fade_in(0.6)


func _on_returned_to_lobby() -> void:
	_show_lobby()
	_fade_in(0.4)


func _free_world() -> void:
	if _world != null:
		_world.queue_free()
		if Net.world == _world:
			Net.world = null
		_world = null


## Fade in from black: every screen change goes through this, so nothing cuts.
func _fade_in(seconds := 0.35) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fader.modulate.a = 1.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fader, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func current_world() -> StationWorld:
	return _world
