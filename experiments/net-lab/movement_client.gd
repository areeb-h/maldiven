extends "res://client.gd"
const World = preload("res://movement_world.gd")
var world: Node3D
var local_body: CharacterBody3D
var models := {}
var remote := {}
var poses := []
var camera: Camera3D
var status_label: Label
var sequence := 0
var snapshot_tick := -1
var snapshot_at := -1
var snapshot_count := 0
var last_control_at := 0
var control := {}
var sent_times := {}
var latest_ack := 0
var acknowledgement_ms := []
var correction_errors := []
var last_injection := ""
var last_teleport := ""
var focused := true
var captured := false
var max_history := 128

func start() -> void:
	super.start()
	if not finished:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://movement-compatibility.json"))
		for key in expected:
			if join.get(key) != expected[key]:
				finish("unsupported_client_compatibility", 2)
	if not finished:
		world = World.build(root, DisplayServer.get_name() != "headless")
		if DisplayServer.get_name() != "headless":
			build_interface()

func on_packet(id: int, data: PackedByteArray) -> void:
	var packet := Common.decode(data, 4096)
	if packet.get("kind") == "welcome":
		super.on_packet(id, data)
		return
	# Reliable welcome and unreliable snapshots are independent streams.
	if id == 1 and admitted_msec < 0 and packet.get("kind") == "snapshot":
		return
	if id != 1 or admitted_msec < 0 or not valid_snapshot(packet):
		finish("invalid_snapshot", 2)
		return
	if packet["room_epoch"] != join["room_epoch"] or int(packet["tick"]) <= snapshot_tick:
		return
	var now := Time.get_ticks_msec()
	var interval := clampf(float(int(packet["tick"]) - snapshot_tick) / 30.0, 0.033, 0.25)
	snapshot_tick = int(packet["tick"])
	snapshot_at = now
	snapshot_count += 1
	poses = packet["players"]
	var present := []
	for pose in poses:
		var identity: String = pose["id"]
		present.append(identity)
		var at := Vector3(pose["p"][0], pose["p"][1], pose["p"][2])
		if not models.has(identity):
			models[identity] = World.avatar(world, identity, identity == credential["player_id"])
			models[identity].position = at
		if identity == credential["player_id"]:
			if local_body == null:
				local_body = World.body(world, at)
			var error := local_body.position.distance_to(at)
			correction_errors.append(snappedf(error, 0.001))
			if correction_errors.size() > 256:
				correction_errors.pop_front()
			local_body.position = at if error > 1.5 else local_body.position.lerp(at, 0.35)
			local_body.velocity = Vector3(pose["v"][0], pose["v"][1], pose["v"][2])
			if error > 2:
				Common.event({"event": "prediction_corrected", "before_error": error, "after": pose["p"]})
			var ack := int(pose["ack"])
			if ack > latest_ack and sent_times.has(ack):
				acknowledgement_ms.append(now - int(sent_times[ack]))
				if acknowledgement_ms.size() > 256:
					acknowledgement_ms.pop_front()
			latest_ack = maxi(latest_ack, ack)
		else:
			remote[identity] = {"from": models[identity].position, "to": at, "at": now, "interval": interval * 1000.0}
	for identity in models.keys():
		if identity not in present:
			models[identity].queue_free()
			models.erase(identity)
			remote.erase(identity)
	if snapshot_count % 6 == 0:
		Common.event({"event": "view_sample", "tick": snapshot_tick, "players": poses, "visible": models.keys(), "snapshot_count": snapshot_count,
			"acknowledgement_ms": acknowledgement_ms, "prediction_error_m": correction_errors,
			"local_p": vector(local_body.position) if local_body != null else []})

func valid_snapshot(packet: Dictionary) -> bool:
	if not Common.exact_keys(packet, ["kind", "room_epoch", "tick", "players"]) or packet.get("kind") != "snapshot" or not Common.integer(packet["tick"]) or packet["tick"] < 0 or not packet["players"] is Array or packet["players"].size() > 6:
		return false
	var identities := []
	for pose in packet["players"]:
		if not pose is Dictionary or not Common.exact_keys(pose, ["id", "p", "v", "ack"]) or pose["id"] not in ["player-1", "player-2", "player-3", "player-4", "player-5", "player-6"] or pose["id"] in identities or not Common.integer(pose["ack"]) or pose["ack"] < 0:
			return false
		identities.append(pose["id"])
		for key in ["p", "v"]:
			if not pose[key] is Array or pose[key].size() != 3:
				return false
			for number in pose[key]:
				if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number)) > 100:
					return false
	return credential["player_id"] in identities

func _physics_process(delta: float) -> bool:
	if admitted_msec < 0 or leaving or finished:
		return false
	var now := Time.get_ticks_msec()
	if now - last_control_at >= 75:
		last_control_at = now
		if args.has("--control-file"):
			control = Common.decode(FileAccess.get_file_as_bytes(args["--control-file"]), 4096)
	var stale := now - (snapshot_at if snapshot_at >= 0 else admitted_msec) > 750
	var axis := Vector2.ZERO
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)
	if focused and not stale and bool(control.get("focused", true)):
		axis = Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if control.get("axis") is Array and control["axis"].size() == 2:
			axis = Vector2(float(control["axis"][0]), float(control["axis"][1]))
		sprint = control.get("sprint", sprint)
	axis = axis.limit_length(1.0)
	if not control.get("suspend_input", false):
		send_axis(axis, sprint)
	if local_body != null:
		World.advance(local_body, Vector2.ZERO if control.get("suspend_input", false) else axis, sprint, delta)
	if str(control.get("injection_id", "")) != last_injection:
		last_injection = str(control.get("injection_id", ""))
		if control.get("raw_input") is Dictionary:
			var injected: Dictionary = control["raw_input"].duplicate()
			if not injected.has("room_epoch"):
				injected["room_epoch"] = join["room_epoch"]
			api.send_bytes(Common.encode(injected), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
		if control.get("burst", 0) > 0:
			for count in range(mini(int(control["burst"]), 180)):
				send_axis(axis, sprint)
	if local_body != null and str(control.get("teleport_id", "")) != last_teleport:
		last_teleport = str(control.get("teleport_id", ""))
		local_body.position = Vector3(90, 5, 90) # Diagnostic local-only tamper; never sent as input.
	return false

func send_axis(axis: Vector2, sprint: bool) -> void:
	sequence += 1
	sent_times[sequence] = Time.get_ticks_msec()
	while sent_times.size() > max_history:
		sent_times.erase(sent_times.keys()[0])
	api.send_bytes(Common.encode({"kind": "input", "room_epoch": join["room_epoch"], "seq": sequence, "move_x": axis.x, "move_z": axis.y, "sprint": sprint}), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)

func _process(delta: float) -> bool:
	super._process(delta)
	if admitted_msec < 0 or finished:
		return false
	var now := Time.get_ticks_msec()
	for identity in remote:
		var entry: Dictionary = remote[identity]
		models[identity].position = entry["from"].lerp(entry["to"], clampf(float(now - int(entry["at"])) / float(entry["interval"]), 0, 1))
	if local_body != null:
		models[credential["player_id"]].position = local_body.position
		if camera != null:
			camera.position = camera.position.lerp(local_body.position + Vector3(0, 7.5, 10), 1.0 - exp(-delta * 6))
			camera.look_at(local_body.position + Vector3(0, 0.2, -1))
	if status_label != null:
		status_label.text = "CONNECTED  /  %d CREW\nWASD or arrows to move  ·  Shift to run" % models.size()
		if now - snapshot_at > 750:
			status_label.text = "WAITING FOR SERVER UPDATES"
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		request_leave()
	if args.has("--capture-file") and not captured and now - admitted_msec > 2200 and camera != null and models.size() >= 2 and now - snapshot_at < 250 and not leaving:
		captured = true
		call_deferred("capture_frame")
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		for key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT]:
			var release := InputEventKey.new()
			release.physical_keycode = key
			release.keycode = key
			release.pressed = false
			Input.parse_input_event(release)
		if admitted_msec >= 0 and not leaving and not finished:
			send_axis(Vector2.ZERO, false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func build_interface() -> void:
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 12, 18)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.10, 0.92)
	style.set_content_margin_all(18)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)
	var heading := Label.new()
	heading.text = "DRIFT STATION  /  MOVEMENT LAB"
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", Color("8fe0df"))
	stack.add_child(heading)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 17)
	stack.add_child(status_label)
	var leave := Button.new()
	leave.text = "Leave room"
	leave.pressed.connect(request_leave)
	stack.add_child(leave)

func capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.save_png(args["--capture-file"]) == OK:
		Common.event({"event": "frame_saved"})

func vector(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
