extends SceneTree
## Headless probe client, not the mobile player UI.
const Common = preload("res://common.gd")
var api: SceneMultiplayer
var peer: ENetMultiplayerPeer
var args := {}
var credential := {}
var join := {}
var started_msec := -1
var admitted_msec := -1
var hold_msec := 250
var leaving := false
var leave_msec := -1
var finished := false

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	args = Common.options()
	if not args.has("--ticket-file") or not args.has("--port"):
		finish("invalid_options", 2)
		return
	credential = Common.decode(FileAccess.get_file_as_bytes(args["--ticket-file"]), 4096)
	if not credential.get("join") is Dictionary or not credential.get("player_id") is String:
		finish("invalid_ticket_file", 2)
		return
	join = credential["join"]
	hold_msec = int(float(args.get("--hold-seconds", "0.25")) * 1000.0)
	peer = ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", int(args["--port"])) != OK:
		finish("connect_failed", 2)
		return
	api = get_multiplayer() as SceneMultiplayer
	api.allow_object_decoding = false
	api.auth_callback = on_auth
	api.auth_timeout = 4.0
	api.peer_authenticating.connect(on_authenticating)
	api.peer_authentication_failed.connect(on_auth_failed)
	api.connection_failed.connect(func(): finish("connect_failed", 2))
	api.server_disconnected.connect(on_disconnected)
	api.peer_packet.connect(on_packet)
	api.multiplayer_peer = peer
	started_msec = Time.get_ticks_msec()

func on_authenticating(id: int) -> void:
	if id != 1:
		finish("unexpected_peer", 2)
		return
	if args.get("--behaviour", "normal") == "silent":
		return
	var data := FileAccess.get_file_as_bytes(args["--raw-file"]) if args.has("--raw-file") else Common.encode(join)
	if api.send_auth(id, data) != OK:
		finish("send_failed", 2)

func on_auth(id: int, data: PackedByteArray) -> void:
	if id != 1:
		finish("unexpected_peer", 2)
		return
	var message := Common.decode(data, Common.MAX_AUTH_BYTES)
	if message.get("kind") == "rejected":
		finish("rejected", 3, str(message.get("reason", "join_failed")))
		return
	if not valid_server_message(message, "accepted"):
		finish("invalid_server_message", 2)
		return
	if args.get("--behaviour", "normal") != "stall":
		api.complete_auth(1)

func valid_server_message(message: Dictionary, kind: String) -> bool:
	if not Common.exact_keys(message, ["kind", "protocol_major", "protocol_minor", "content_id", "rules_id", "room_id", "room_epoch", "player_id"]):
		return false
	if message["kind"] != kind or message["player_id"] != credential["player_id"]:
		return false
	for key in ["protocol_major", "protocol_minor", "content_id", "rules_id", "room_id", "room_epoch"]:
		if message[key] != join.get(key):
			return false
	return true

func on_packet(id: int, data: PackedByteArray) -> void:
	if id != 1 or admitted_msec >= 0:
		finish("unexpected_packet", 2)
		return
	var welcome := Common.decode(data, Common.MAX_AUTH_BYTES)
	if not valid_server_message(welcome, "welcome"):
		finish("invalid_welcome", 2)
		return
	admitted_msec = Time.get_ticks_msec()
	Common.event({"event": "client_admitted", "player_id": welcome["player_id"], "room_epoch": welcome["room_epoch"]})
	if args.has("--app-file"):
		api.send_bytes(FileAccess.get_file_as_bytes(args["--app-file"]), 1)

func _process(_delta: float) -> bool:
	if finished or started_msec < 0:
		return false
	var now := Time.get_ticks_msec()
	if admitted_msec >= 0 and not leaving:
		var requested := args.has("--leave-file") and FileAccess.file_exists(args["--leave-file"])
		if requested or now - admitted_msec >= hold_msec:
			leaving = true
			leave_msec = now
			api.send_bytes(Common.encode({"kind": "leave"}), 1)
	if admitted_msec < 0 and now - started_msec > int(float(args.get("--timeout", "6")) * 1000.0):
		finish("timeout", 2)
	if leaving and now - leave_msec > 2000:
		finish("leave_timeout", 2)
	return false

func on_auth_failed(_id: int) -> void:
	finish("auth_failed", 3)

func on_disconnected() -> void:
	finish("left" if leaving else "disconnected", 0 if leaving else 2)

func finish(status: String, code: int, reason := "") -> void:
	if finished:
		return
	finished = true
	Common.event({"event": "client_finished", "status": status, "reason": reason})
	# Authentication/disconnect signals can run inside the multiplayer poll.
	# Release the peer after that callback returns, not reentrantly within it.
	call_deferred("close_and_quit", code)

func close_and_quit(code: int) -> void:
	if peer != null:
		peer.close()
	quit(code)
