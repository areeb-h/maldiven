extends Node
## Entry point: home screen (host / nearby stations / join by IP), lobby, and the
## in-round World. A live 3D flyover of the station sits behind the menus.
## Also starts the headless bot driver for automated tests.

const SETTINGS_PATH := "user://settings.cfg"
const VERSION := "0.4.0"
const BotDriver = preload("res://scripts/dev/bot_driver.gd")

var _ui: Control
var _home: Control
var _lobby: Control
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _rooms_box: VBoxContainer
var _lobby_title: Label
var _lobby_hint: Label
var _lobby_count: Label
var _lobby_players: VBoxContainer
var _start_button: Button
var _world: StationWorld
var _backdrop: Node3D
var _orbit_camera: Camera3D
var _orbit_angle := 0.6
var _bot: Node
var _bot_args := {}
var _fader: ColorRect
var _fade_tween: Tween


func _ready() -> void:
	_bot_args = _parse_bot_args()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UiStyle.make_theme()
	layer.add_child(_ui)
	_build_overlay()
	_build_home()
	_build_lobby()
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
	_update_orbit(delta)


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
	gradient.set_color(1, Color(0.01, 0.02, 0.05, 0.0))
	gradient.add_point(0.45, Color(0.01, 0.02, 0.05, 0.72))
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


func _left_column(screen: Control, width: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 72
	scroll.offset_right = 72 + width
	scroll.offset_top = 40
	scroll.offset_bottom = -32
	screen.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width - 16, 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box


func _caption(box: Container, text: String, color := UiStyle.ACCENT) -> Label:
	var caption := UiStyle.label(text, "bold", 20, color)
	box.add_child(caption)
	return caption


func _spacer(box: Container, height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	box.add_child(gap)


# --- Home --------------------------------------------------------------------

func _build_home() -> void:
	_home = _screen(_ui)
	# Left: branding.
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 6)
	brand.anchor_top = 0.5
	brand.anchor_bottom = 0.5
	brand.offset_left = 72
	brand.offset_right = 700
	brand.offset_top = -190
	brand.offset_bottom = 190
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(brand)
	_caption(brand, "WEEK 1 BUILD  ·  v%s" % VERSION)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -22)
	brand.add_child(title)
	title.add_child(UiStyle.label("DRIFT", "title", 96, UiStyle.TEXT))
	title.add_child(UiStyle.label("STATION", "title", 96, UiStyle.ACCENT))
	_spacer(brand, 8)
	brand.add_child(UiStyle.label("Restore the power. Save the core.", "light", 30, UiStyle.MUTED))
	brand.add_child(UiStyle.label("Trust no one.", "bold", 30, UiStyle.AMBER))
	# Right: play panel.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.8, 28))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560
	panel.offset_right = -56
	panel.offset_top = -300
	panel.offset_bottom = 300
	_home.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_caption(box, "CALLSIGN", UiStyle.MUTED)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = 16
	_name_edit.text = _load_name()
	_name_edit.add_theme_font_size_override("font_size", 28)
	box.add_child(_name_edit)
	var host_button := Button.new()
	host_button.text = "HOST A STATION"
	UiStyle.style_button(host_button, true)
	host_button.custom_minimum_size = Vector2(0, 66)
	host_button.pressed.connect(_on_host)
	box.add_child(host_button)
	_spacer(box, 6)
	_caption(box, "NEARBY STATIONS", UiStyle.MUTED)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 8)
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rooms_box)
	_caption(box, "JOIN BY IP", UiStyle.MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.20"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip_edit)
	var join_button := Button.new()
	join_button.text = "JOIN"
	UiStyle.style_button(join_button)
	join_button.pressed.connect(func(): _join(_ip_edit.text))
	row.add_child(join_button)
	_status = UiStyle.label("", "bold", 22, UiStyle.DANGER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


# --- Lobby -------------------------------------------------------------------

func _build_lobby() -> void:
	_lobby = _screen(_ui)
	var box := _left_column(_lobby, 620)
	_caption(box, "STATION LOBBY")
	_lobby_title = UiStyle.label("", "head", 46, UiStyle.TEXT)
	_lobby_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lobby_title)
	_lobby_hint = UiStyle.label("", "body", 24, UiStyle.MUTED)
	_lobby_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lobby_hint)
	_spacer(box, 6)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.ACCENT, 0.78, 22))
	box.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)
	_lobby_count = UiStyle.label("", "bold", 22, UiStyle.ACCENT)
	inner.add_child(_lobby_count)
	_lobby_players = VBoxContainer.new()
	_lobby_players.add_theme_constant_override("separation", 8)
	inner.add_child(_lobby_players)
	_spacer(box, 4)
	_start_button = Button.new()
	_start_button.text = "START ROUND"
	UiStyle.style_button(_start_button, true)
	_start_button.custom_minimum_size = Vector2(0, 68)
	_start_button.pressed.connect(func(): Net.start_round())
	box.add_child(_start_button)
	var leave := Button.new()
	leave.text = "LEAVE"
	UiStyle.style_button(leave)
	leave.pressed.connect(func():
		Net.leave()
		_show_home(""))
	box.add_child(leave)
	# How-to card on the right.
	var guide := PanelContainer.new()
	guide.add_theme_stylebox_override("panel", UiStyle.panel_box(UiStyle.AMBER, 0.72, 24))
	guide.anchor_left = 1.0
	guide.anchor_right = 1.0
	guide.anchor_top = 0.5
	guide.anchor_bottom = 0.5
	guide.offset_left = -500
	guide.offset_right = -56
	guide.offset_top = -210
	guide.offset_bottom = 210
	_lobby.add_child(guide)
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", 10)
	guide.add_child(steps)
	steps.add_child(UiStyle.label("HOW A ROUND WORKS", "head", 22, UiStyle.AMBER))
	for line in [
		["01", "Power is out. Carry 3 cells to the Reactor."],
		["02", "Power returns and the core vault in Command opens."],
		["03", "Crew: load the core into the shuttle in Docking."],
		["04", "One of you is the infiltrator, racing for the cargo pod."],
		["05", "Shove to make carriers drop. Watch for blackouts."],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.add_child(UiStyle.label(line[0], "head", 20, UiStyle.AMBER))
		var text := UiStyle.label(line[1], "body", 22, UiStyle.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		steps.add_child(row)


func _player_row(entry: Dictionary, tags: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var swatch := ColorRect.new()
	swatch.color = entry.color
	swatch.custom_minimum_size = Vector2(8, 38)
	row.add_child(swatch)
	var name_label := UiStyle.label(entry.name, "bold", 28, UiStyle.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	for tag in tags:
		var chip := Label.new()
		chip.text = tag
		chip.add_theme_font_override("font", UiStyle.font("bold"))
		chip.add_theme_font_size_override("font_size", 18)
		chip.add_theme_color_override("font_color", Color("04121c"))
		chip.add_theme_stylebox_override("normal", UiStyle.pill_box(UiStyle.ACCENT if tag == "YOU" else UiStyle.AMBER))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
	return row


# --- Settings ----------------------------------------------------------------

func _load_name() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return str(config.get_value("player", "name", ""))
	return ""


func _save_name(player_name: String) -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.save(SETTINGS_PATH)


# --- Flow --------------------------------------------------------------------

func _on_host() -> void:
	_save_name(_name_edit.text)
	var error := Net.host(_name_edit.text)
	if error != OK:
		_status.text = "Couldn't host (is port %d already in use?)" % Net.PORT
		return
	_show_lobby()


func _join(address: String) -> void:
	if address.strip_edges().is_empty():
		_status.text = "Type the host's IP. It's shown on their lobby screen."
		return
	_save_name(_name_edit.text)
	if Net.join(address, _name_edit.text) != OK:
		_status.text = "That address doesn't look right."
		return
	_status.add_theme_color_override("font_color", UiStyle.ACCENT)
	_status.text = "Connecting…"


func _show_home(message: String) -> void:
	_free_world()
	_set_backdrop_visible(true)
	_ui.show()
	_home.show()
	_lobby.hide()
	_enter(_home)
	_status.add_theme_color_override("font_color", UiStyle.DANGER)
	_status.text = message
	Net.start_listening()
	_refresh_rooms()


func _show_lobby() -> void:
	_free_world()
	_set_backdrop_visible(true)
	Net.stop_listening()
	_ui.show()
	_home.hide()
	_lobby.show()
	_enter(_lobby)
	_on_roster_changed()


func _refresh_rooms() -> void:
	if _rooms_box == null:
		return
	for child in _rooms_box.get_children():
		child.queue_free()
	if Net.rooms.is_empty():
		_rooms_box.add_child(UiStyle.label("Scanning your Wi-Fi…", "body", 22, Color(1, 1, 1, 0.38)))
		return
	for ip in Net.rooms:
		var room: Dictionary = Net.rooms[ip]
		var button := Button.new()
		var playing: bool = room.state == "playing"
		button.text = "%s     %d/8 CREW%s" % [room.name.to_upper(), room.players, "  ·  IN A ROUND" if playing else ""]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiStyle.style_button(button, false, UiStyle.GOOD if not playing else UiStyle.MUTED)
		button.add_theme_font_size_override("font_size", 24)
		button.disabled = playing
		button.pressed.connect(func(): _join(ip))
		_rooms_box.add_child(button)


func _on_roster_changed() -> void:
	if Net.is_online() and not Net.in_round and not _lobby.visible and _world == null:
		_show_lobby()
		return
	if not _lobby.visible:
		return
	_lobby_title.text = (Net.room_name if Net.room_name != "" else "Station").to_upper()
	if Net.is_host():
		var addresses := Net.local_addresses()
		_lobby_hint.text = "Friends on the same Wi-Fi will see this station. Or they can join by IP:  %s" % ("  /  ".join(addresses) if not addresses.is_empty() else "your local IP")
	else:
		_lobby_hint.text = "Waiting for the host to start the round…"
	_lobby_count.text = "CREW ABOARD  %d / %d" % [Net.roster.size(), Net.MAX_PLAYERS]
	for child in _lobby_players.get_children():
		child.queue_free()
	var ids := Net.roster.keys()
	ids.sort()
	for id in ids:
		var tags := []
		if id == 1:
			tags.append("HOST")
		if id == Net.my_id():
			tags.append("YOU")
		_lobby_players.add_child(_player_row(Net.roster[id], tags))
	_start_button.visible = Net.is_host()
	_start_button.text = "START ROUND" if Net.roster.size() >= 2 else "START SOLO WALKAROUND"


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


## Slide and fade a screen's content in with a slight upward motion.
func _enter(screen: Control) -> void:
	screen.modulate.a = 0.0
	screen.position.y = 18.0
	var tween := create_tween().set_parallel()
	tween.tween_property(screen, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(screen, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func current_world() -> StationWorld:
	return _world
