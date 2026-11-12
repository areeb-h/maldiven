extends "res://movement_server.gd"
const Wire = preload("res://voice_wire.gd")
var voices := {}
var voice_denials := {}
var voice_serial := 0

func mode_compatibility() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://phone-compatibility.json"))

func allowed_options() -> Array:
	return super.allowed_options() + ["--bind", "--certificate", "--private-key", "--diagnostics"]

func sample_motion() -> bool:
	return Common.options().get("--diagnostics", "false") == "true"

func bind_address() -> String:
	return str(Common.options().get("--bind", "127.0.0.1"))

func maximum_ticket_ttl() -> float:
	return 600.0

func configure_transport(transport: ENetMultiplayerPeer) -> Error:
	var options := Common.options()
	if not options.has("--certificate") or not options.has("--private-key"):
		return ERR_INVALID_PARAMETER
	var certificate := X509Certificate.new()
	var key := CryptoKey.new()
	if certificate.load(options["--certificate"]) != OK or key.load(options["--private-key"]) != OK:
		return ERR_INVALID_DATA
	return transport.host.dtls_server_setup(TLSOptions.server(key, certificate))

func on_connected(id: int) -> void:
	super.on_connected(id)
	if connected.has(id):
		voices[id] = {"enabled": false, "channel": 0, "burst": 0, "wire_burst": 0, "seq": 0, "at": Time.get_ticks_msec(), "count": 0, "controls_at": 0, "controls": 0}

func on_packet(id: int, data: PackedByteArray) -> void:
	if not voices.has(id) or not actors.has(id) or actors[id]["leaving"] or stopping:
		return
	if Wire.is_voice(data):
		route_voice(id, data)
		return
	var packet := Common.decode(data, 512)
	if packet.get("kind") == "voice_control":
		voice_control(id, packet)
		return
	if packet.get("kind") == "leave":
		voices[id]["enabled"] = false
	super.on_packet(id, data)

func voice_deny(reason: String) -> void:
	voice_denials[reason] = int(voice_denials.get(reason, 0)) + 1
	if voice_denials[reason] == 1:
		Common.event({"event": "voice_rejected", "reason": reason})

func voice_control(id: int, packet: Dictionary) -> void:
	var state: Dictionary = voices[id]
	var now := Time.get_ticks_msec()
	if now - int(state["controls_at"]) >= 1000:
		state["controls_at"] = now
		state["controls"] = 0
	state["controls"] += 1
	# Always allow a well-formed stop to close the microphone's current grant.
	if not Common.exact_keys(packet, ["kind", "enabled", "channel", "burst"]) or not packet["enabled"] is bool or not Common.integer(packet["channel"]) or int(packet["channel"]) not in [0, 1] or not Common.integer(packet["burst"]) or packet["burst"] < 1 or packet["burst"] > 2147483647:
		voice_deny("control_shape")
		return
	if not packet["enabled"]:
		if int(packet["burst"]) == int(state["burst"]):
			state["enabled"] = false
		return
	if state["controls"] > 12 or int(packet["burst"]) <= int(state["burst"]):
		voice_deny("control_rate_or_replay")
		return
	state["enabled"] = true
	state["channel"] = int(packet["channel"])
	state["burst"] = int(packet["burst"])
	voice_serial += 1
	state["wire_burst"] = voice_serial # Monotonic across leave/rejoin of the same crew slot.
	state["seq"] = 0
	api.send_bytes(Common.encode({"kind": "voice_granted", "burst": state["burst"]}), id)

func route_voice(id: int, data: PackedByteArray) -> void:
	var state: Dictionary = voices[id]
	if not Wire.valid(data, epoch) or data[12] != 255:
		voice_deny("frame_shape_or_identity")
		return
	if not state["enabled"] or data[13] != state["channel"] or data.decode_u32(14) != state["burst"]:
		voice_deny("no_current_grant")
		return
	var seq := int(data.decode_u32(18))
	if seq <= int(state["seq"]) or seq > int(state["seq"]) + 100:
		voice_deny("frame_sequence")
		return
	var now := Time.get_ticks_msec()
	if now - int(state["at"]) >= 1000:
		state["at"] = now
		state["count"] = 0
	state["count"] += 1
	if state["count"] > 60:
		voice_deny("frame_rate")
		return
	state["seq"] = seq
	var outgoing := data.duplicate()
	outgoing[12] = int(str(sessions[id]).trim_prefix("player-")) - 1
	outgoing.encode_u32(14, state["wire_burst"])
	var listeners := 0
	for listener in actors:
		if listener == id or not connected.has(listener) or actors[listener]["leaving"]:
			continue
		var distance: float = actors[id]["body"].position.distance_to(actors[listener]["body"].position)
		if data[13] == 0 and distance > 8.0:
			continue
		api.send_bytes(outgoing, listener, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)
		listeners += 1
	# Metadata only, rate-limited diagnostic. No samples, tickets or recordings.
	if seq == 1 or seq % 50 == 0:
		Common.event({"event": "voice_routed", "player_id": sessions[id], "channel": data[13], "listeners": listeners, "sequence": seq})

func release(id: int, reason: String) -> void:
	voices.erase(id)
	super.release(id, reason)
