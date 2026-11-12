class_name PhoneLabClient
extends "res://movement_client.gd"
const Wire = preload("res://voice_wire.gd")
const NativeAudio = preload("res://voice_audio.gd")
const TouchControls = preload("res://phone_controls.gd")
var interactive := false
var invite := {}
var ui_options := {}
var menu_layer: CanvasLayer
var invite_text: TextEdit
var menu_message: Label
var touch: Control
var audio: Node
var microphone_allowed := false
var talk_held := false
var voice_granted := false
var voice_burst := 0
var voice_sequence := 0
var voice_channel := 0
var voice_muted := false
var mic_button: Button
var channel_button: Button
var mute_button: Button

func start() -> void:
	interactive = not Common.options().has("--ticket-file")
	if interactive:
		on_request_permissions_result.connect(permission_result)
		show_join_menu("Start the PC server, then paste one private invite.\nUse headphones for this voice test. Same Wi-Fi required.")
	else:
		super.start()

func mode_compatibility() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://phone-compatibility.json"))

func client_options() -> Dictionary:
	return ui_options if interactive else super.client_options()

func load_credential() -> Dictionary:
	return invite["credential"] if interactive else super.load_credential()

func server_address() -> String:
	return str(invite.get("host", "")) if interactive else str(args.get("--host", "127.0.0.1"))

func configure_transport(transport: ENetMultiplayerPeer) -> Error:
	var certificate := X509Certificate.new()
	var error: Error
	if interactive:
		error = certificate.load_from_string(invite["certificate"])
	else:
		error = certificate.load(str(args.get("--certificate", "")))
	if error != OK:
		return error
	return transport.host.dtls_client_setup("maldiven.local", TLSOptions.client(certificate, "maldiven.local"))

func show_join_menu(message: String) -> void:
	menu_layer = CanvasLayer.new()
	root.add_child(menu_layer)
	var background := ColorRect.new()
	background.color = Color("091722")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 40)
	menu_layer.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	margin.add_child(stack)
	var title := Label.new()
	title.text = "MALDIVEN  /  FRIENDS LAB"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("8fe0df"))
	stack.add_child(title)
	menu_message = Label.new()
	menu_message.text = message
	menu_message.add_theme_font_size_override("font_size", 20)
	stack.add_child(menu_message)
	invite_text = TextEdit.new()
	invite_text.placeholder_text = "Paste MDV1. invite here"
	invite_text.custom_minimum_size = Vector2(0, 140)
	invite_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	invite_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	stack.add_child(invite_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	stack.add_child(row)
	var paste := make_button("Paste invite")
	paste.pressed.connect(func(): invite_text.text = DisplayServer.clipboard_get().strip_edges())
	row.add_child(paste)
	var connect_button := make_button("Connect to PC")
	connect_button.pressed.connect(connect_invite)
	row.add_child(connect_button)
	var note := Label.new()
	note.text = "Invites expire after 10 minutes and can be used once. Keep them private.\nPrototype: movement + nearby/radio push-to-talk. No weapons or missions yet."
	note.add_theme_font_size_override("font_size", 17)
	stack.add_child(note)

func make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 58)
	button.add_theme_font_size_override("font_size", 20)
	return button

func parse_invite(text: String) -> Dictionary:
	if not text.begins_with("MDV1.") or text.length() > 18000:
		return {}
	var encoded := text.substr(5)
	if encoded.length() % 4 != 0 or encoded.is_empty():
		return {}
	for character in encoded:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=":
			return {}
	var padding := 2 if encoded.ends_with("==") else (1 if encoded.ends_with("=") else 0)
	if "=" in encoded.substr(0, encoded.length() - padding):
		return {}
	var parsed := Common.decode(Marshalls.base64_to_raw(encoded), 12000)
	if not Common.exact_keys(parsed, ["host", "port", "certificate", "credential"]) or not parsed["host"] is String or not parsed["host"].is_valid_ip_address() or not Common.integer(parsed["port"]) or parsed["port"] < 1 or parsed["port"] > 65535 or not parsed["certificate"] is String or parsed["certificate"].length() > 8000 or not parsed["credential"] is Dictionary:
		return {}
	return parsed

func connect_invite() -> void:
	invite = parse_invite(invite_text.text.strip_edges())
	if invite.is_empty():
		menu_message.text = "Invalid invite. Copy the complete MDV1. text from the PC invite page."
		return
	ui_options = {"--ticket-file": "invite-in-memory", "--port": str(int(invite["port"])), "--hold-seconds": "86400", "--timeout": "12"}
	menu_layer.queue_free()
	menu_layer = null
	super.start()

func build_interface() -> void:
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 12, 18)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var top := HBoxContainer.new()
	top.position = Vector2(28, 24)
	top.add_theme_constant_override("separation", 18)
	layer.add_child(top)
	var labels := VBoxContainer.new()
	labels.custom_minimum_size = Vector2(360, 0)
	top.add_child(labels)
	var title := Label.new()
	title.text = "MALDIVEN / FRIENDS LAB"
	title.add_theme_font_size_override("font_size", 23)
	labels.add_child(title)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 17)
	labels.add_child(status_label)
	channel_button = make_button("Nearby · 8 m")
	channel_button.pressed.connect(func():
		stop_talking()
		voice_channel = 1 - voice_channel
		channel_button.text = "Radio · room" if voice_channel == 1 else "Nearby · 8 m")
	top.add_child(channel_button)
	mic_button = make_button("Enable mic")
	mic_button.pressed.connect(enable_microphone)
	top.add_child(mic_button)
	mute_button = make_button("Mute sound")
	mute_button.pressed.connect(func():
		voice_muted = not voice_muted
		audio.muted = voice_muted
		audio.clear_playback()
		stop_talking()
		mute_button.text = "Unmute sound" if voice_muted else "Mute sound")
	top.add_child(mute_button)
	var leave := make_button("Leave")
	leave.custom_minimum_size.x = 95
	leave.pressed.connect(request_leave)
	top.add_child(leave)
	touch = TouchControls.new()
	layer.add_child(touch)
	touch.talk_changed.connect(talk_changed)
	ensure_audio()

func ensure_audio() -> void:
	if audio == null:
		audio = NativeAudio.new()
		root.add_child(audio)
		audio.frame_ready.connect(send_voice)

func enable_microphone() -> void:
	if OS.get_name() == "Android":
		if "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
			microphone_allowed = true
		else:
			OS.request_permission("android.permission.RECORD_AUDIO")
	else:
		microphone_allowed = true
	if mic_button != null:
		mic_button.text = "Mic ready" if microphone_allowed else "Allow mic / retry"

func permission_result(permission: String, granted: bool) -> void:
	if permission == "android.permission.RECORD_AUDIO":
		microphone_allowed = granted
		if mic_button != null:
			mic_button.text = "Mic ready" if granted else "Mic denied / retry"
		if not granted:
			stop_talking()

func talk_changed(held: bool) -> void:
	if not held:
		stop_talking()
		return
	if OS.get_name() == "Android" and "android.permission.RECORD_AUDIO" not in OS.get_granted_permissions():
		microphone_allowed = false
	if not focused or not microphone_allowed or voice_muted or admitted_msec < 0 or leaving or finished:
		return
	talk_held = true
	voice_burst += 1
	voice_sequence = 0
	voice_granted = false
	api.send_bytes(Common.encode({"kind": "voice_control", "enabled": true, "channel": voice_channel, "burst": voice_burst}), 1)

func stop_talking() -> void:
	var was_held := talk_held
	talk_held = false
	voice_granted = false
	if audio != null:
		audio.stop_capture()
	if was_held and admitted_msec >= 0 and not leaving and not finished and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		api.send_bytes(Common.encode({"kind": "voice_control", "enabled": false, "channel": voice_channel, "burst": voice_burst}), 1)

func send_voice(samples: PackedFloat32Array) -> void:
	if not talk_held or not voice_granted or not focused or leaving or finished:
		return
	voice_sequence += 1
	api.send_bytes(Wire.frame(join["room_epoch"], voice_channel, voice_burst, voice_sequence, samples), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)

func granted(_burst: int) -> void:
	ensure_audio()
	audio.start_capture()

func on_packet(id: int, data: PackedByteArray) -> void:
	if Wire.is_voice(data):
		if id != 1 or admitted_msec < 0 or not Wire.valid(data, join["room_epoch"]) or data[12] > 5 or data[12] == int(str(credential["player_id"]).trim_prefix("player-")) - 1:
			finish("invalid_voice", 2)
			return
		if not leaving and not finished and focused and not voice_muted:
			ensure_audio()
			audio.receive(data)
		return
	var packet := Common.decode(data, 4096)
	if packet.get("kind") == "voice_granted":
		if id == 1 and Common.exact_keys(packet, ["kind", "burst"]) and packet["burst"] == voice_burst and talk_held and focused and not leaving and not finished:
			voice_granted = true
			granted(voice_burst)
		return
	super.on_packet(id, data)

func _physics_process(delta: float) -> bool:
	if touch != null and not args.has("--control-file"):
		if touch.move_pointer >= 0:
			control = {"axis": [touch.axis.x, touch.axis.y]}
		else:
			control = {}
	return super._physics_process(delta)

func _process(delta: float) -> bool:
	super._process(delta)
	if touch != null:
		touch.talk_status = "TALKING" if talk_held and voice_granted else ("ALLOW MIC FIRST" if not microphone_allowed else "HOLD TO TALK")
		touch.queue_redraw()
	if status_label != null:
		status_label.text = "%d CREW · %s\nMove left · hold talk right" % [models.size(), "CONNECTED" if admitted_msec >= 0 else "CONNECTING…"]
		if admitted_msec >= 0 and Time.get_ticks_msec() - snapshot_at > 750:
			status_label.text = "WAITING FOR SERVER"
			stop_talking()
	return false

func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_APPLICATION_RESUMED:
		focused = true
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and OS.get_name() == "Android":
		microphone_allowed = "android.permission.RECORD_AUDIO" in OS.get_granted_permissions()
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_WM_GO_BACK_REQUEST]:
		focused = false
		stop_talking()
		if touch != null:
			touch.reset()
		if audio != null:
			audio.clear_playback()
		if what == Node.NOTIFICATION_WM_GO_BACK_REQUEST:
			request_leave()

func request_leave() -> void:
	stop_talking()
	if touch != null:
		touch.reset()
	super.request_leave()

func finish(status: String, code: int, reason := "") -> void:
	stop_talking()
	if audio != null:
		audio.clear_playback()
	if interactive:
		if finished:
			return
		finished = true
		call_deferred("return_to_menu", status, reason)
	else:
		super.finish(status, code, reason)

func return_to_menu(status: String, reason: String) -> void:
	if peer != null:
		peer.close()
	set_multiplayer(SceneMultiplayer.new())
	for child in root.get_children():
		child.queue_free()
	await process_frame
	world = null
	local_body = null
	camera = null
	status_label = null
	touch = null
	audio = null
	mic_button = null
	channel_button = null
	mute_button = null
	models.clear()
	remote.clear()
	poses.clear()
	sent_times.clear()
	control.clear()
	sequence = 0
	snapshot_tick = -1
	snapshot_at = -1
	snapshot_count = 0
	latest_ack = 0
	started_msec = -1
	admitted_msec = -1
	leaving = false
	finished = false
	voice_burst = 0
	voice_sequence = 0
	voice_muted = false
	focused = true
	invite.clear()
	credential.clear()
	join.clear()
	show_join_menu("%s %s\nFor a retry, use the next invite for your crew slot or restart the PC server." % [status.replace("_", " "), reason.replace("_", " ")])
