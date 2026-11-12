extends SceneTree
## NET-001 local admission experiment. Bind address is deliberately loopback only.
const Common = preload("res://common.gd")
var api: SceneMultiplayer
var peer: ENetMultiplayerPeer
var compatibility := Common.compatibility()
var epoch := ""
var state_dir := ""
var tickets := {}
var sessions := {} # Includes identities reserved during unfinished authentication.
var connected := {}
var blocked := {}
var max_clients := 6
var stopping := false
var stop_msec := 0

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	var args := Common.options()
	if not args.has("--state-dir"):
		fail("state_directory_required")
		return
	for key in args:
		if key not in ["--state-dir", "--port", "--max-clients", "--ticket-ttl", "--auth-timeout"]:
			fail("unknown_option")
			return
	state_dir = str(args["--state-dir"])
	max_clients = int(args.get("--max-clients", "6"))
	var ttl := float(args.get("--ticket-ttl", "60"))
	var auth_timeout := float(args.get("--auth-timeout", "2"))
	var port := int(args.get("--port", "0"))
	if not state_dir.is_absolute_path() or max_clients < 1 or max_clients > 6 or not is_finite(ttl) or ttl < 0.2 or ttl > 120.0 or not is_finite(auth_timeout) or auth_timeout < 0.5 or auth_timeout > 5.0 or port < 0 or port > 65535:
		fail("invalid_options")
		return
	if DirAccess.make_dir_recursive_absolute(state_dir) != OK:
		fail("state_directory_unavailable")
		return
	if OS.get_name() == "Linux" and FileAccess.set_unix_permissions(state_dir, 448) != OK: # 0700
		fail("state_directory_permissions")
		return
	# Reusing a stopped lab directory must not inherit the previous stop/ready state.
	for filename in ["stop", "ready.json"]:
		var path := state_dir.path_join(filename)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			fail("stale_state_unavailable")
			return
	var crypto := Crypto.new()
	var epoch_bytes := crypto.generate_random_bytes(16)
	if epoch_bytes.size() != 16:
		fail("random_source_unavailable")
		return
	epoch = compatibility["room_id"] + "." + epoch_bytes.hex_encode()
	var credential_records := []
	var expiry_msec := Time.get_ticks_msec() + int(ttl * 1000.0)
	for player_index in range(1, 7):
		for issuance in range(2):
			var token_bytes := crypto.generate_random_bytes(32)
			if token_bytes.size() != 32 or tickets.has(token_bytes.hex_encode()):
				fail("random_source_unavailable")
				return
			var token := token_bytes.hex_encode()
			var player_id := "player-%d" % player_index
			tickets[token] = {"player_id": player_id, "expiry_msec": expiry_msec, "used": false}
			var join := compatibility.duplicate()
			join.merge({"kind": "join", "room_epoch": epoch, "ticket": token})
			credential_records.append({"player_id": player_id, "issuance": issuance, "join": join})
	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	if peer.create_server(port, 12) != OK:
		fail("bind_failed")
		return
	api = get_multiplayer() as SceneMultiplayer
	api.allow_object_decoding = false
	api.server_relay = false
	api.auth_timeout = auth_timeout
	api.auth_callback = on_auth
	api.peer_connected.connect(on_connected)
	api.peer_disconnected.connect(on_disconnected)
	api.peer_authentication_failed.connect(on_auth_failed)
	api.peer_packet.connect(on_packet)
	api.multiplayer_peer = peer
	var ready := compatibility.duplicate()
	ready.merge({"event": "server_ready", "room_epoch": epoch, "host": "127.0.0.1", "port": peer.host.get_local_port()})
	var private_state := {"credentials": credential_records, "ready": ready}
	if Common.write_private(state_dir.path_join("admissions.json"), private_state) != OK or Common.write_private(state_dir.path_join("ready.json"), ready) != OK:
		fail("state_write_failed")
		return
	Common.event(ready)

func _process(_delta: float) -> bool:
	if api == null:
		return false
	if not stopping and FileAccess.file_exists(state_dir.path_join("stop")):
		stopping = true
		stop_msec = Time.get_ticks_msec()
		Common.event({"event": "server_stopping", "active": connected.size(), "reserved": sessions.size()})
		api.refuse_new_connections = true
		for id in api.get_peers():
			peer.get_peer(id).peer_disconnect_later()
		for id in api.get_authenticating_peers():
			api.disconnect_peer(id)
	if stopping and ((api.get_peers().is_empty() and api.get_authenticating_peers().is_empty()) or Time.get_ticks_msec() - stop_msec >= 1000):
		peer.close()
		sessions.clear()
		connected.clear()
		blocked.clear()
		Common.event({"event": "server_stopped", "active": 0, "reserved": 0})
		quit()
	return false

func on_auth(id: int, data: PackedByteArray) -> void:
	if blocked.has(id) or sessions.has(id):
		return
	if stopping:
		reject(id, "server_stopping")
		return
	var join := Common.decode(data, Common.MAX_AUTH_BYTES)
	if not Common.exact_keys(join, ["kind", "protocol_major", "protocol_minor", "content_id", "rules_id", "room_id", "room_epoch", "ticket"]) or join.get("kind") != "join":
		reject(id, "malformed")
		return
	for field in ["protocol_major", "protocol_minor"]:
		if not Common.integer(join[field]) or join[field] != compatibility[field]:
			reject(id, "version_mismatch")
			return
	for field in ["content_id", "rules_id", "room_id"]:
		if not join[field] is String or join[field] != compatibility[field]:
			reject(id, field + "_mismatch")
			return
	if not join["room_epoch"] is String or join["room_epoch"] != epoch:
		reject(id, "stale_epoch")
		return
	if not Common.hex_token(join["ticket"]) or not tickets.has(join["ticket"]):
		reject(id, "invalid_ticket")
		return
	var record: Dictionary = tickets[join["ticket"]]
	if Time.get_ticks_msec() >= int(record["expiry_msec"]):
		reject(id, "expired_ticket")
		return
	if record["used"]:
		reject(id, "ticket_replay")
		return
	var player_id: String = record["player_id"]
	if player_id in sessions.values():
		reject(id, "identity_in_use")
		return
	if sessions.size() >= max_clients:
		reject(id, "room_full")
		return
	# Consume and reserve before completing either side of authentication.
	record["used"] = true
	sessions[id] = player_id
	Common.event({"event": "authentication_reserved", "player_id": player_id, "active": connected.size(), "reserved": sessions.size()})
	var response := compatibility.duplicate()
	response.merge({"kind": "accepted", "room_epoch": epoch, "player_id": player_id})
	if api.send_auth(id, Common.encode(response)) != OK or api.complete_auth(id) != OK:
		release(id, "authentication_error")
		api.disconnect_peer(id)

func reject(id: int, reason: String) -> void:
	blocked[id] = true
	Common.event({"event": "rejected", "reason": reason, "active": connected.size(), "reserved": sessions.size()})
	# Honest clients close on this response; silent clients are bounded by auth_timeout.
	api.send_auth(id, Common.encode({"kind": "rejected", "reason": reason}))

func on_connected(id: int) -> void:
	if stopping or not sessions.has(id):
		api.disconnect_peer(id)
		return
	connected[id] = true
	var welcome := compatibility.duplicate()
	welcome.merge({"kind": "welcome", "room_epoch": epoch, "player_id": sessions[id]})
	api.send_bytes(Common.encode(welcome), id)
	Common.event({"event": "admitted", "player_id": sessions[id], "active": connected.size(), "reserved": sessions.size()})

func on_packet(id: int, data: PackedByteArray) -> void:
	if not connected.has(id):
		return
	var packet := Common.decode(data, Common.MAX_APP_BYTES)
	if Common.exact_keys(packet, ["kind"]) and packet["kind"] == "leave":
		peer.get_peer(id).peer_disconnect_later()
	else:
		Common.event({"event": "message_rejected", "player_id": sessions[id]})

func on_auth_failed(id: int) -> void:
	release(id, "auth_failed")

func on_disconnected(id: int) -> void:
	release(id, "disconnected")

func release(id: int, reason: String) -> void:
	var identity: String = sessions.get(id, "")
	sessions.erase(id)
	connected.erase(id)
	blocked.erase(id)
	Common.event({"event": reason, "player_id": identity, "active": connected.size(), "reserved": sessions.size()})

func fail(reason: String) -> void:
	Common.event({"event": "server_failed", "reason": reason})
	if peer != null:
		peer.close()
	quit(2)
