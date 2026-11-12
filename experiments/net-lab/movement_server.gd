extends "res://server.gd"
const World = preload("res://movement_world.gd")
var world: Node3D
var actors := {}
var generation := 0
var tick := 0
var delay_ms := 0
var loss_percent := 0.0
var random := RandomNumberGenerator.new()
var inbound := []
var outbound := []
var rejections := {}
var counters := {"input_received": 0, "input_dropped": 0, "snapshot_sent": 0, "snapshot_dropped": 0, "queue_peak": 0}

func allowed_options() -> Array:
	return super.allowed_options() + ["--rtt-ms", "--loss-percent", "--seed"]

func start() -> void:
	var options := Common.options()
	var rtt := int(options.get("--rtt-ms", "0"))
	loss_percent = float(options.get("--loss-percent", "0"))
	if rtt < 0 or rtt > 1000 or not is_finite(loss_percent) or loss_percent < 0 or loss_percent > 100:
		fail("invalid_motion_network_options")
		return
	delay_ms = int(rtt / 2)
	random.seed = int(options.get("--seed", "20261112"))
	compatibility = JSON.parse_string(FileAccess.get_file_as_string("res://movement-compatibility.json"))
	super.start()
	if api != null:
		world = World.build(root, false)
		Common.event({"event": "motion_ready", "simulation_hz": 30, "snapshot_hz": 15, "simulated_rtt_ms": rtt, "simulated_loss_percent": loss_percent})

func on_connected(id: int) -> void:
	super.on_connected(id)
	if not connected.has(id):
		return
	generation += 1
	actors[id] = {"body": World.body(world, World.spawn_for(sessions[id])), "axis": Vector2.ZERO,
		"sprint": false, "seq": 0, "last_msec": Time.get_ticks_msec(), "generation": generation,
		"rate_at": Time.get_ticks_msec(), "rate_count": 0, "leaving": false}

func on_packet(id: int, data: PackedByteArray) -> void:
	if not actors.has(id) or stopping:
		return
	var packet := Common.decode(data, 512)
	if packet.get("kind") == "leave":
		if Common.exact_keys(packet, ["kind"]):
			actors[id]["leaving"] = true
		super.on_packet(id, data)
		return
	var state: Dictionary = actors[id]
	var now := Time.get_ticks_msec()
	if now - int(state["rate_at"]) >= 1000:
		state["rate_at"] = now
		state["rate_count"] = 0
	state["rate_count"] += 1
	if state["rate_count"] > 90:
		deny("rate_limit")
		return
	counters["input_received"] += 1
	if random.randf() * 100.0 < loss_percent:
		counters["input_dropped"] += 1
		return
	if inbound.size() >= 256:
		deny("queue_limit")
		return
	inbound.append({"id": id, "generation": state["generation"], "due": now + delay_ms, "packet": packet})
	counters["queue_peak"] = maxi(counters["queue_peak"], inbound.size() + outbound.size())

func apply_input(id: int, packet: Dictionary) -> void:
	if not Common.exact_keys(packet, ["kind", "room_epoch", "seq", "move_x", "move_z", "sprint"]) or packet.get("kind") != "input":
		deny("input_shape")
		return
	if packet["room_epoch"] != epoch:
		deny("input_epoch")
		return
	if not Common.integer(packet["seq"]) or packet["seq"] < 1 or packet["seq"] > 2147483647:
		deny("input_sequence")
		return
	var state: Dictionary = actors[id]
	var sequence := int(packet["seq"])
	if sequence <= int(state["seq"]):
		deny("stale_sequence")
		return
	if sequence > int(state["seq"]) + 1024:
		deny("sequence_jump")
		return
	for key in ["move_x", "move_z"]:
		var value: Variant = packet[key]
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 1.0:
			deny("input_axis")
			return
	if not packet["sprint"] is bool:
		deny("input_sprint")
		return
	state["axis"] = Vector2(packet["move_x"], packet["move_z"]).limit_length(1.0)
	state["sprint"] = packet["sprint"]
	state["seq"] = sequence
	state["last_msec"] = Time.get_ticks_msec()

func deny(reason: String) -> void:
	rejections[reason] = int(rejections.get(reason, 0)) + 1
	if rejections[reason] == 1:
		Common.event({"event": "input_rejected", "reason": reason})

func _physics_process(delta: float) -> bool:
	if world == null or stopping:
		return false
	var now := Time.get_ticks_msec()
	while not inbound.is_empty() and int(inbound[0]["due"]) <= now:
		var message: Dictionary = inbound.pop_front()
		var id := int(message["id"])
		if actors.has(id) and not actors[id]["leaving"] and actors[id]["generation"] == message["generation"]:
			apply_input(id, message["packet"])
	for id in actors:
		var state: Dictionary = actors[id]
		if state["leaving"]:
			continue
		var axis: Vector2 = state["axis"]
		if now - int(state["last_msec"]) > World.INPUT_TIMEOUT_MS:
			axis = Vector2.ZERO
		World.advance(state["body"], axis, state["sprint"], delta)
	tick += 1
	var poses := []
	for id in actors:
		var state: Dictionary = actors[id]
		if state["leaving"]:
			continue
		var body: CharacterBody3D = state["body"]
		poses.append({"id": sessions[id], "p": vector(body.position), "v": vector(body.velocity), "ack": state["seq"]})
	if tick % 2 == 0:
		var data := Common.encode({"kind": "snapshot", "room_epoch": epoch, "tick": tick, "players": poses})
		if data.size() > 1200:
			fail("snapshot_budget_exceeded")
			return false
		for id in actors:
			if actors[id]["leaving"]:
				continue
			if random.randf() * 100.0 < loss_percent:
				counters["snapshot_dropped"] += 1
			elif outbound.size() < 256:
				outbound.append({"id": id, "generation": actors[id]["generation"], "due": now + delay_ms, "data": data})
				counters["queue_peak"] = maxi(counters["queue_peak"], inbound.size() + outbound.size())
	while not outbound.is_empty() and int(outbound[0]["due"]) <= now:
		var message: Dictionary = outbound.pop_front()
		var id := int(message["id"])
		if actors.has(id) and connected.has(id) and not actors[id]["leaving"] and actors[id]["generation"] == message["generation"]:
			api.send_bytes(message["data"], id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
			counters["snapshot_sent"] += 1
	if tick % 2 == 0:
		Common.event({"event": "motion_sample", "tick": tick, "players": poses, "counters": counters, "rejections": rejections})
	return false

func release(id: int, reason: String) -> void:
	if actors.has(id):
		actors[id]["body"].queue_free()
		actors.erase(id)
	super.release(id, reason)

func vector(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
