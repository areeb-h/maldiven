extends Node
## Autoload "Net": listen-server sessions, LAN discovery and every gameplay RPC.
## All RPCs live on this always-present node so they never target a missing
## scene. The host (peer 1) is a player too and is authoritative over the round.

signal roster_changed
signal session_ended(message: String)
signal round_began
signal returned_to_lobby
signal rooms_changed

const PORT := 24600
const DISCOVERY_PORT := 24601
const PROTOCOL := 6  # 6: accuse request, accusations + accuse_in in snapshots, gesture events
const MAX_PLAYERS := 8
const GAME_ID := "drift-station"
const PALETTE := [Color("ff5a5a"), Color("4da3ff"), Color("ffd23f"), Color("53d769"),
	Color("c77dff"), Color("ff9f40"), Color("3fe0d0"), Color("f2f2f2")]
## Bot players (scripts/bots/): roster entries {name, color, bot: true, skill}
## with ids from BOT_ID_BASE, simulated in-process by the host. They are never
## sent an RPC; they count toward max_players.
const BOT_ID_BASE := 10001
const BOT_NAMES := ["Bot Nova", "Bot Pixel", "Bot Juno", "Bot Rivet", "Bot Comet", "Bot Echo",
	"Bot Vega", "Bot Sprocket", "Bot Orbit", "Bot Tango"]
const BOT_SKILLS := ["easy", "normal", "hard"]

var roster := {}  # peer id -> {name, color} (bots also: bot = true, skill)
var in_round := false
var room_name := ""
var dedicated := false  # PC dedicated server: peer 1 hosts but is not a player (scripts/server/)
var max_players := MAX_PLAYERS  # seats; a dedicated server may lower it
var server_dedicated := false  # client: the host is a PC server, not a player
var world: Node = null  # current World node, registers itself
var rooms := {}  # ip -> {name, players, state, seen}
var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_timer := 0.0
var _local_name := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 0


## True for a bot player's id (host and clients both know from the roster).
func is_bot(id: int) -> bool:
	return roster.has(id) and bool(roster[id].get("bot", false))


func human_count() -> int:
	var count := 0
	for id in roster:
		if not is_bot(id):
			count += 1
	return count


func bot_ids() -> Array:
	var out := []
	for id in roster:
		if is_bot(id):
			out.append(id)
	out.sort()
	return out


## Host, lobby only: add a bot player. Returns its id, or 0 when that isn't
## possible (not hosting, a round is running, or every seat is taken).
func add_bot(skill := "normal") -> int:
	if not is_host() or in_round or roster.size() >= max_players:
		return 0
	var id := BOT_ID_BASE
	while roster.has(id) or multiplayer.get_peers().has(id):
		id += 1
	var taken := []
	for entry in roster.values():
		taken.append(entry.name)
	var bot_name := ""
	for candidate in BOT_NAMES:
		if not taken.has(candidate):
			bot_name = candidate
			break
	if bot_name.is_empty():
		bot_name = _unique_name("Bot")
	roster[id] = {"name": bot_name, "color": _free_color(), "bot": true,
		"skill": skill if BOT_SKILLS.has(skill) else "normal"}
	_send_to_roster("_roster", [roster])
	roster_changed.emit()
	return id


## Host, lobby only: remove a bot (id 0: the most recently added). Returns false
## if there was none to remove.
func remove_bot(id := 0) -> bool:
	if not is_host() or in_round:
		return false
	if id == 0:
		var bots := bot_ids()
		if bots.is_empty():
			return false
		id = bots.back()
	if not is_bot(id):
		return false
	roster.erase(id)
	_send_to_roster("_roster", [roster])
	roster_changed.emit()
	return true


func _free_color() -> Color:
	var used := []
	for entry in roster.values():
		used.append(entry.color)
	for candidate in PALETTE:
		if not used.has(candidate):
			return candidate
	return PALETTE[roster.size() % PALETTE.size()]


func _unique_name(wanted: String) -> String:
	var unique := _clean_name(wanted)
	var taken := []
	for entry in roster.values():
		taken.append(entry.name)
	var suffix := 2
	var base := unique
	while taken.has(unique):
		unique = "%s %d" % [base.substr(0, 13), suffix]
		suffix += 1
	return unique


# --- Session lifecycle -------------------------------------------------------

func host(player_name: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_local_name = _clean_name(player_name)
	room_name = "%s's station" % _local_name
	roster = {1: {"name": _local_name, "color": PALETTE[0]}}
	in_round = false
	_start_beacon()
	roster_changed.emit()
	return OK


## Dedicated server (scripts/server/dedicated_server.gd): host with an empty
## roster; peer 1 runs the round but has no avatar, role, camera or HUD.
func host_dedicated(name_of_room: String, seats := MAX_PLAYERS) -> Error:
	var error := host("Server")
	if error != OK:
		return error
	dedicated = true
	max_players = clampi(seats, 2, MAX_PLAYERS)
	room_name = name_of_room
	roster = {}
	roster_changed.emit()
	return OK


## Host: remove a client; they see the message on their home screen.
func kick(id: int, message: String) -> void:
	if is_bot(id):
		remove_bot(id)
	elif is_host() and id != 1:
		_refuse(id, message)


## Host: rename the room (beacon + every admitted client's lobby title).
func rename_room(next: String) -> void:
	if not is_host():
		return
	room_name = next
	_send_to_roster("_welcome", [room_name])
	_send_to_roster("_roster", [roster])  # clients refresh the lobby title
	roster_changed.emit()


## Join a station by address: "192.168.1.20", a Tailscale IP or MagicDNS name,
## or a public tunnel such as "abc.playit.gg:12345" (see NetAddress).
## Returns ERR_INVALID_PARAMETER for unparseable text, ERR_CANT_RESOLVE when a
## hostname doesn't resolve.
func join(address: String, player_name: String) -> Error:
	var target := NetAddress.parse(address, PORT)
	if not target.ok:
		return ERR_INVALID_PARAMETER
	var host: String = target.host
	if not host.is_valid_ip_address():
		host = IP.resolve_hostname(host, IP.TYPE_ANY)
		if host.is_empty():
			return ERR_CANT_RESOLVE
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host, int(target.port))
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	_local_name = _clean_name(player_name)
	roster = {}
	in_round = false
	return OK


func leave() -> void:
	_stop_beacon()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null and enet.host != null:
			enet.host.flush()  # send pending reliable messages (a kick or refusal) before closing
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster = {}
	in_round = false
	room_name = ""
	dedicated = false
	max_players = MAX_PLAYERS
	server_dedicated = false


func _clean_name(text: String) -> String:
	var cleaned := text.strip_edges().replace("\n", " ")
	if cleaned.is_empty():
		cleaned = "Crew %d" % (randi() % 90 + 10)
	return cleaned.substr(0, 16)


func _on_connected() -> void:
	_relax_timeout(1)
	_register.rpc_id(1, _local_name, PROTOCOL)


## Loading a round (or a slow phone) can stall a frame for seconds; ENet's
## default 5 s minimum timeout would drop the connection mid-load.
func _relax_timeout(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var packet_peer := enet.get_peer(id)
	if packet_peer != null:
		packet_peer.set_timeout(64, 20000, 60000)


func _on_connection_failed() -> void:
	leave()
	session_ended.emit("Could not reach that station. Check the IP and that you're on the same Wi-Fi.")


func _on_server_disconnected() -> void:
	leave()
	session_ended.emit("The host closed the station.")


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_relax_timeout(id)
	# Wait for _register before listing them.


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not roster.has(id):
		return
	roster.erase(id)
	if world != null and in_round:
		world.host_player_left(id)
	_send_to_roster("_roster", [roster])
	roster_changed.emit()


## Host only: send an RPC to every registered client (never to peers that are
## connected but not yet admitted, or were refused, and never to bots).
func _send_to_roster(method: StringName, args: Array) -> void:
	for id in roster:
		if id != 1 and not is_bot(id):
			callv("rpc_id", [id, method] + args)


@rpc("any_peer", "reliable")
func _register(player_name: String, protocol: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_refuse(id, "Version mismatch: update the app on every phone.")
		return
	var round_over: bool = world != null and world.rules.phase == StationRules.Phase.RESULT
	if in_round and not round_over:
		_refuse(id, "A round is in progress. Try again when it ends.")
		return
	if roster.size() >= max_players and not in_round and not bot_ids().is_empty():
		roster.erase(bot_ids().back())  # in the lobby, a bot gives its seat up for a person
	if roster.size() >= max_players:
		_refuse(id, "The station is full.")
		return
	if is_bot(id):
		_refuse(id, "The station is busy. Try joining again.")  # (astronomically rare id clash)
		return
	roster[id] = {"name": _unique_name(player_name), "color": _free_color()}
	_welcome.rpc_id(id, room_name)
	if dedicated:
		_server_is_dedicated.rpc_id(id)
	_send_to_roster("_roster", [roster])
	roster_changed.emit()


func _refuse(id: int, message: String) -> void:
	_refused.rpc_id(id, message)
	get_tree().create_timer(0.5).timeout.connect(func():
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.get_peers().has(id):
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))


@rpc("authority", "reliable")
func _refused(message: String) -> void:
	leave()
	session_ended.emit(message)


@rpc("authority", "reliable")
func _server_is_dedicated() -> void:
	server_dedicated = true


@rpc("authority", "reliable")
func _welcome(name_of_room: String) -> void:
	room_name = name_of_room


@rpc("authority", "reliable")
func _roster(next: Dictionary) -> void:
	roster = next
	roster_changed.emit()


# --- Round lifecycle ---------------------------------------------------------

func start_round() -> void:
	if is_host() and not in_round:
		_send_to_roster("_begin_round", [])
		_begin_round()


@rpc("authority", "reliable")
func _begin_round() -> void:
	in_round = true
	round_began.emit()


func back_to_lobby() -> void:
	if is_host():
		_send_to_roster("_back_to_lobby", [])
		_back_to_lobby()


@rpc("authority", "reliable")
func _back_to_lobby() -> void:
	in_round = false
	returned_to_lobby.emit()


# --- Gameplay traffic --------------------------------------------------------

## Host -> one client: its private role. Never broadcast.
func send_role(id: int, role: String) -> void:
	if is_bot(id):
		return  # a bot's brain reads its role from the host rules
	_role.rpc_id(id, role)


@rpc("authority", "reliable")
func _role(role: String) -> void:
	if world != null:
		world.client_role(role)


func broadcast_snapshot(snapshot: Dictionary) -> void:
	_send_to_roster("_snapshot", [snapshot])


@rpc("authority", "reliable")
func _snapshot(snapshot: Dictionary) -> void:
	if world != null:
		world.client_snapshot(snapshot)


func broadcast_event(event: Dictionary) -> void:
	_send_to_roster("_event", [event])


## Host -> one registered client (never a bot or the host itself): an event only
## some peers may see, e.g. a gesture seen by the players in sight of it.
func send_event(id: int, event: Dictionary) -> void:
	if is_host() and id != 1 and roster.has(id) and not is_bot(id):
		_event.rpc_id(id, event)


@rpc("authority", "reliable")
func _event(event: Dictionary) -> void:
	if world != null:
		world.client_event(event)


## Client -> host: own pose and velocity, ~20 Hz. The velocity lets the host
## lead this player's physics proxy (see scripts/physics/player_proxy.gd).
func send_pose(pos: Vector3, yaw: float, vel: Vector3) -> void:
	if is_host():
		if world != null:
			world.host_pose(1, pos, yaw, vel)
	else:
		_pose.rpc_id(1, pos, yaw, vel)


@rpc("any_peer", "unreliable_ordered")
func _pose(pos: Vector3, yaw: float, vel: Vector3) -> void:
	if multiplayer.is_server() and world != null:
		world.host_pose(multiplayer.get_remote_sender_id(), pos, yaw, vel.limit_length(30.0))


## Host -> everyone: all poses in one packet.
func broadcast_poses(poses: Dictionary) -> void:
	_send_to_roster("_poses", [poses])


@rpc("authority", "unreliable_ordered")
func _poses(poses: Dictionary) -> void:
	if world != null:
		world.client_poses(poses)


## Host -> clients: loose item and prop states (scripts/physics/net_codec.gd).
## The stream is unreliable_ordered on its own channel (so it never drops or
## delays poses); keyframes (everything changed since the last one, or the full
## state for a client that just loaded) are reliable. to_peer 0 = every client.
func send_physics(data: PackedByteArray, reliable: bool, to_peer: int) -> void:
	if not is_host():
		return
	if to_peer != 0:
		if to_peer != 1 and roster.has(to_peer) and not is_bot(to_peer):
			_physics_keyframe.rpc_id(to_peer, data)
	elif reliable:
		_send_to_roster("_physics_keyframe", [data])
	else:
		_send_to_roster("_physics", [data])


@rpc("authority", "unreliable_ordered", "call_remote", 1)
func _physics(data: PackedByteArray) -> void:
	if world != null:
		world.client_physics(data, false)


@rpc("authority", "reliable")
func _physics_keyframe(data: PackedByteArray) -> void:
	if world != null:
		world.client_physics(data, true)


## Client -> host: my world is ready, send me every body's state.
func request_physics_sync() -> void:
	if is_online() and not is_host():
		_physics_sync.rpc_id(1)


@rpc("any_peer", "reliable")
func _physics_sync() -> void:
	if multiplayer.is_server() and world != null:
		world.host_physics_sync(multiplayer.get_remote_sender_id())


## Host: smoothed round-trip time to a client, in seconds (0 if unknown).
func peer_rtt(id: int) -> float:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or id == 1 or not is_online() or is_bot(id) or not multiplayer.get_peers().has(id):
		return 0.0  # the host itself, a bot, or someone who already left
	var packet_peer := enet.get_peer(id)
	if packet_peer == null:
		return 0.0
	return packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0


## Client -> host: "interact", "shove", "shoot" or "sabotage". The sender's
## current pose rides along so the host judges the action where the player
## actually is, not where the last (unreliable, 20 Hz) pose update put them.
func request(action: String, pos: Vector3, yaw: float) -> void:
	if is_host():
		if world != null:
			world.host_request(1, action, pos, yaw)
	else:
		_request.rpc_id(1, action, pos, yaw)


@rpc("any_peer", "reliable")
func _request(action: String, pos: Vector3, yaw: float) -> void:
	if multiplayer.is_server() and world != null and action in ["interact", "shove", "sabotage", "shoot"]:
		world.host_request(multiplayer.get_remote_sender_id(), action, pos, yaw)


## Client -> host: accuse `target` (the HUD's pick; 0 = whoever is in the aim
## cone). `yaw` is the aim (towards the target); the host validates range, cone,
## line of sight and cooldown from this pose.
func request_accuse(target: int, pos: Vector3, yaw: float) -> void:
	if is_host():
		if world != null:
			world.host_accuse(1, target, pos, yaw)
	else:
		_accuse.rpc_id(1, target, pos, yaw)


@rpc("any_peer", "reliable")
func _accuse(target: int, pos: Vector3, yaw: float) -> void:
	if multiplayer.is_server() and world != null:
		world.host_accuse(multiplayer.get_remote_sender_id(), target, pos, yaw)


# --- LAN discovery -----------------------------------------------------------

func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or _is_172_private(address):
			out.append(address)
	return out


func _is_172_private(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var parts := address.split(".")
	return parts.size() == 4 and int(parts[1]) >= 16 and int(parts[1]) <= 31


func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon_timer = 0.0


func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null


func start_listening() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT, "*") != OK:
		_listener = null  # Another app/instance owns the port; manual IP still works.


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	rooms.clear()


func _process(delta: float) -> void:
	if _beacon != null and is_host():
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = 1.0
			var payload := JSON.stringify({"game": GAME_ID, "v": PROTOCOL, "name": room_name,
				"players": roster.size(), "state": "playing" if in_round else "lobby"}).to_utf8_buffer()
			var targets := ["255.255.255.255"]
			for address in local_addresses():
				var parts := address.split(".")
				targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
			for target in targets:
				_beacon.set_dest_address(target, DISCOVERY_PORT)
				_beacon.put_packet(payload)
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var packet := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var data = JSON.parse_string(packet.get_string_from_utf8())
			if typeof(data) == TYPE_DICTIONARY and data.get("game") == GAME_ID and int(data.get("v", 0)) == PROTOCOL:
				rooms[ip] = {"name": str(data.get("name", "Station")).substr(0, 32),
					"players": int(data.get("players", 0)), "state": str(data.get("state", "lobby")),
					"seen": Time.get_ticks_msec()}
				changed = true
		for ip in rooms.keys():
			if Time.get_ticks_msec() - rooms[ip].seen > 4000:
				rooms.erase(ip)
				changed = true
		if changed:
			rooms_changed.emit()
