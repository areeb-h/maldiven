extends Node
## Dedicated PC server. main.gd adds this node instead of the menus when the
## game starts with user args:
##   godot --headless --path . -- --dedicated [--room-name=NAME] [--max-players=8]
##         [--control-port=PORT --control-token=TOKEN] [--auto-lobby=45]
##
## The PC hosts the session (ENet peer 1, UDP 24600, LAN beacon on 24601) but is
## not a player: the roster holds only the phones, the server has no avatar,
## role, camera or HUD, and rounds run with the connected phones. The
## authoritative rules, timers and physics run here in a normal StationWorld, so
## phones behave exactly as they do with a phone host.
##
## tools/host_station.py drives it through ControlChannel (localhost TCP) and
## serves the web control panel. Without --control-port it runs standalone and
## logs to stdout; start rounds from the panel or stop it with Ctrl+C.

const ControlChannel = preload("res://scripts/server/control_channel.gd")
const StationStatus = preload("res://scripts/server/station_status.gd")

const STATUS_INTERVAL := 0.5
const MIN_PLAYERS := 2
const DEFAULT_ROOM := "Drift Station"
const CONTROLLER_FIRST_WAIT := 90.0  # s for the launcher to connect before we give up
const CONTROLLER_GRACE := 20.0  # s without the launcher before the server shuts down
const SHUTDOWN_MESSAGE := "The host shut down the server."
const KICK_MESSAGE := "You were removed from the station by the host."

var args := {}
var max_players := 8
var auto_lobby := 45.0  # s after a result before everyone returns to the lobby (0: never)
var status := StationStatus.new()
var _control: ControlChannel
var _world: StationWorld
var _status_timer := 0.0
var _started_ms := 0
var _result_ms := -1
var _stopping := false
var _kicked := {}
var _version := ""


func _ready() -> void:
	name = "DedicatedServer"
	Engine.max_fps = 60  # headless runs uncapped otherwise and burns a whole core
	_started_ms = Time.get_ticks_msec()
	_version = str(ProjectSettings.get_setting("application/config/version", "dev"))
	args = parse_args(OS.get_cmdline_user_args())
	max_players = clampi(int(args.get("max-players", "8")), MIN_PLAYERS, Net.MAX_PLAYERS)
	auto_lobby = maxf(0.0, float(args.get("auto-lobby", "45")))
	if not Net.has_method("host_dedicated"):
		_fail("this build's scripts/net.gd has no host_dedicated() (dedicated-server hook missing)")
		return
	var error: int = Net.call("host_dedicated", clean_room_name(args.get("room-name", "")), max_players)
	if error != OK:
		_fail("UDP port %d is busy: is another Drift Station server or game already running on this PC?" % Net.PORT
			if error == ERR_CANT_CREATE or error == ERR_ALREADY_IN_USE else "could not open UDP port %d (error %d)" % [Net.PORT, error])
		return
	Net.roster_changed.connect(_on_roster_changed)
	Net.round_began.connect(_on_round_began)
	Net.returned_to_lobby.connect(_on_returned_to_lobby)
	if args.has("control-port"):
		_control = ControlChannel.new()
		var listen := _control.listen(int(args["control-port"]), str(args.get("control-token", "")))
		if listen != OK:
			_fail("could not open the control port 127.0.0.1:%s" % args["control-port"])
			return
	status.log_line("Station online: %s, UDP %d" % [Net.room_name, Net.PORT], "round")
	print("SERVER_READY port=%d discovery=%d control=%s version=%s" % [Net.PORT, Net.DISCOVERY_PORT,
		args.get("control-port", "none"), _version])
	_on_roster_changed()


static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in user_args:
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			out[parts[0]] = parts[1] if parts.size() > 1 else "1"
	return out


## One line, no control characters, at most 32 characters (the beacon limit).
static func clean_room_name(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		var code := text.unicode_at(i)
		out += " " if code < 32 or code == 127 else text[i]
	while out.contains("  "):
		out = out.replace("  ", " ")
	out = out.strip_edges().substr(0, 32).strip_edges()
	return out if not out.is_empty() else DEFAULT_ROOM


func _fail(message: String) -> void:
	printerr("SERVER_ERROR ", message)
	print("SERVER_ERROR ", message)
	get_tree().quit(3)


# --- Session -----------------------------------------------------------------

func _on_roster_changed() -> void:
	status.roster_changed(Net.roster, _kicked)
	_kicked.clear()
	# Everyone left mid-round: nothing to play for, reset for the next group.
	if Net.in_round and Net.roster.is_empty():
		Net.back_to_lobby()
	_status_timer = 0.0


func _on_round_began() -> void:
	_free_world()
	_world = StationWorld.new()
	add_child(_world)
	_result_ms = -1
	status.round_started(_world.rules.players.size())
	_status_timer = 0.0


func _on_returned_to_lobby() -> void:
	_free_world()
	_result_ms = -1
	status.log_line("Back in the lobby", "info")
	_status_timer = 0.0


func _free_world() -> void:
	if _world != null:
		_world.queue_free()
		if Net.world == _world:
			Net.world = null
		_world = null


func start_round() -> String:
	if Net.in_round:
		return "A round is already running."
	if Net.roster.size() < MIN_PLAYERS:
		return "Needs at least %d players (%d connected)." % [MIN_PLAYERS, Net.roster.size()]
	Net.start_round()
	return ""


func back_to_lobby() -> String:
	if not Net.in_round:
		return "Already in the lobby."
	Net.back_to_lobby()
	return ""


func kick(id: int) -> String:
	if not Net.roster.has(id):
		return "No player with id %d." % id
	_kicked[id] = true
	if Net.has_method("kick"):
		Net.call("kick", id, KICK_MESSAGE)
	else:
		Net._refuse(id, KICK_MESSAGE)
	return ""


func set_room_name(text: String) -> String:
	var next := clean_room_name(text)
	if next == Net.room_name:
		return ""
	if Net.has_method("rename_room"):
		Net.call("rename_room", next)
	else:
		Net.room_name = next
	status.log_line("Station renamed to “%s”" % next, "info")
	return ""


## Tells every phone the server is closing (they land on the home screen with
## the message), then quits.
func stop(exit_code := 0) -> void:
	if _stopping:
		return
	_stopping = true
	status.log_line("Shutting down", "info")
	for id in Net.roster.keys():
		if Net.has_method("kick"):
			Net.call("kick", id, SHUTDOWN_MESSAGE)
		else:
			Net._refuse(id, SHUTDOWN_MESSAGE)
	_publish()
	await get_tree().create_timer(0.8 if not Net.roster.is_empty() else 0.1).timeout
	_publish()
	print("SERVER_STOPPED")
	if _control != null:
		_control.close()
	Net.leave()
	get_tree().quit(exit_code)


# --- Control and status --------------------------------------------------------

func _process(delta: float) -> void:
	if _control != null:
		for command in _control.poll():
			_handle(command)
		_watchdog()
	if Net.in_round and _world != null and _world.rules.phase == StationRules.Phase.RESULT:
		if _result_ms < 0:
			_result_ms = Time.get_ticks_msec()
		elif auto_lobby > 0.0 and _lobby_in() <= 0.0 and not _stopping:
			Net.back_to_lobby()
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = STATUS_INTERVAL
		_publish()


func _lobby_in() -> float:
	if _result_ms < 0 or auto_lobby <= 0.0:
		return -1.0
	return maxf(0.0, auto_lobby - (Time.get_ticks_msec() - _result_ms) / 1000.0)


func _publish() -> void:
	var rules: StationRules = _world.rules if _world != null and Net.in_round else null
	if rules != null:
		status.observe_round(rules.public_snapshot())
	if _control == null or not _control.connected():
		return
	_control.send(status.build(rules, {"version": _version, "max_players": max_players,
		"min_players": MIN_PLAYERS, "uptime": (Time.get_ticks_msec() - _started_ms) / 1000.0,
		"stopping": _stopping, "lobby_in": snapped(_lobby_in(), 0.1)}))


func _handle(command: Dictionary) -> void:
	var cmd := str(command.get("cmd", ""))
	var params: Dictionary = command.get("args", {}) if typeof(command.get("args")) == TYPE_DICTIONARY else {}
	var error := ""
	if _stopping and cmd != "status":
		error = "The server is shutting down."
	else:
		match cmd:
			"start_round":
				error = start_round()
			"back_to_lobby":
				error = back_to_lobby()
			"kick":
				error = kick(int(params.get("id", 0)))
			"set_room_name":
				error = set_room_name(str(params.get("name", "")))
			"status":
				pass
			"stop":
				_control.reply(command, true)
				stop()
				return
			_:
				error = "Unknown command “%s”." % cmd
	_control.reply(command, error.is_empty(), error)
	_status_timer = 0.0  # publish the effect right away


## The launcher owns this process: if it never connects, or goes away and
## doesn't come back, close the station cleanly instead of lingering.
func _watchdog() -> void:
	if _stopping:
		return
	var seconds := Time.get_ticks_msec() / 1000.0
	if not _control.had_controller and seconds - _started_ms / 1000.0 > CONTROLLER_FIRST_WAIT:
		printerr("SERVER_ERROR the launcher never connected; shutting down")
		stop(4)
	elif _control.lost_ms >= 0 and not _control.connected() \
			and (Time.get_ticks_msec() - _control.lost_ms) / 1000.0 > CONTROLLER_GRACE:
		printerr("SERVER_ERROR lost the launcher; shutting down")
		stop(4)
