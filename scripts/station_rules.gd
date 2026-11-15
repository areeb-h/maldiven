class_name StationRules
extends RefCounted
## Pure round rules for Drift Station. No nodes, no networking: the host runs the
## authoritative copy; clients keep a mirror filled from public snapshots so the
## HUD can show the same interaction prompts the host will accept.

enum Phase { BRIEFING, STABILISE, EXTRACTION, RESULT }

const ROUND_SECONDS := 600.0
const BRIEFING_SECONDS := 6.0
const SHUTTLE_SECONDS := 30.0
const POD_SECONDS := 20.0
const INTERACT_RANGE := 2.4
const SHOVE_RANGE := 2.2
const SHOVE_COOLDOWN := 3.0
const STUN_SECONDS := 1.1
const BLACKOUT_SECONDS := 25.0
const BLACKOUT_COOLDOWN := 75.0
const BLACKOUT_FIRST_DELAY := 20.0
const CARRY_SPEED := {"cell": 0.8, "core": 0.72}

const CREW := "crew"
const INFILTRATOR := "infiltrator"

var phase: int = Phase.BRIEFING
var elapsed := 0.0
## peer id -> {name, color, role (host only), pos, yaw, holding, shove_ready, stunned_until}
var players := {}
## item id -> {kind, holder (peer id or 0), pos: Vector3, socket: String}
var items := {}
## socket id -> item id or ""
var socket_items := {}
var shuttle_left := -1.0
var pod_left := -1.0
var blackout_until := -1.0
var blackout_ready := BLACKOUT_FIRST_DELAY
var winner := ""
var reason := ""
var infiltrator_name := ""
var timeline: Array = []
## Drained by the network layer: public alerts and private effects.
var events: Array = []
var is_mirror := false


func setup(roster: Dictionary, rng: RandomNumberGenerator) -> void:
	players.clear()
	var ids := roster.keys()
	ids.sort()
	# A solo walkaround has no infiltrator.
	var infiltrator: int = ids[rng.randi_range(0, ids.size() - 1)] if ids.size() > 1 else -1
	for index in range(ids.size()):
		var id: int = ids[index]
		var entry: Dictionary = roster[id]
		players[id] = {
			"name": str(entry.get("name", "Crew")),
			"color": entry.get("color", Color.WHITE),
			"role": INFILTRATOR if id == infiltrator else CREW,
			"pos": StationLayout.spawn_point(index, ids.size()),
			"yaw": 0.0,
			"holding": "",
			"shove_ready": 0.0,
			"stunned_until": 0.0,
		}
	infiltrator_name = players[infiltrator].name if players.has(infiltrator) else "nobody"
	items.clear()
	socket_items.clear()
	for socket_id in StationLayout.SOCKETS:
		socket_items[socket_id] = ""
	for item_id in StationLayout.ITEMS:
		var spec: Dictionary = StationLayout.ITEMS[item_id]
		var item := {"kind": spec.kind, "holder": 0, "pos": Vector3.ZERO, "socket": ""}
		if spec.has("socket"):
			_seat(item_id, item, spec.socket)
		else:
			item.pos = StationLayout.to_world(spec.pos, 0.0)
		items[item_id] = item
	phase = Phase.BRIEFING
	elapsed = 0.0
	_log("Round started with %d crew aboard." % ids.size())


func role_of(id: int) -> String:
	return players[id].role if players.has(id) else ""


func infiltrator_id() -> int:
	for id in players:
		if players[id].role == INFILTRATOR:
			return id
	return 0


func time_left() -> float:
	return maxf(0.0, ROUND_SECONDS - elapsed)


func powered_cells() -> int:
	var count := 0
	for socket_id in socket_items:
		if StationLayout.SOCKETS[socket_id].kind == "reactor" and socket_items[socket_id] != "":
			count += 1
	return count


func reactor_socket_count() -> int:
	var count := 0
	for socket_id in StationLayout.SOCKETS:
		if StationLayout.SOCKETS[socket_id].kind == "reactor":
			count += 1
	return count


func is_blackout() -> bool:
	return blackout_until > elapsed


func speed_factor(id: int) -> float:
	if not players.has(id):
		return 1.0
	var player: Dictionary = players[id]
	if player.stunned_until > elapsed:
		return 0.0
	if player.holding != "":
		return CARRY_SPEED.get(items[player.holding].kind, 1.0)
	return 1.0


func set_pose(id: int, pos: Vector3, yaw: float) -> void:
	if players.has(id):
		players[id].pos = pos
		players[id].yaw = yaw


func item_position(item_id: String) -> Vector3:
	var item: Dictionary = items[item_id]
	if item.holder != 0 and players.has(item.holder):
		return players[item.holder].pos + Vector3(0, 1.1, 0)
	return item.pos


func _socket_pos(socket_id: String) -> Vector3:
	return StationLayout.to_world(StationLayout.SOCKETS[socket_id].pos)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func socket_locked(socket_id: String) -> bool:
	var kind: String = StationLayout.SOCKETS[socket_id].kind
	if kind == "vault":
		return phase < Phase.EXTRACTION
	if kind == "reactor":
		return socket_items[socket_id] != ""  # seated cells stay seated
	return false


## What pressing Interact would do right now for this player.
## Returns {} when nothing, else {action, item, socket, label}.
func available_action(id: int) -> Dictionary:
	if not players.has(id) or phase == Phase.RESULT or phase == Phase.BRIEFING:
		return {}
	var player: Dictionary = players[id]
	if player.stunned_until > elapsed:
		return {}
	var pos: Vector3 = player.pos
	if player.holding != "":
		var held: Dictionary = items[player.holding]
		var best_socket := ""
		var best_distance := INTERACT_RANGE
		for socket_id in StationLayout.SOCKETS:
			var spec: Dictionary = StationLayout.SOCKETS[socket_id]
			if spec.accepts != held.kind or socket_items[socket_id] != "":
				continue
			if spec.kind == "vault":
				continue
			var distance := _flat_distance(pos, _socket_pos(socket_id))
			if distance < best_distance:
				best_distance = distance
				best_socket = socket_id
		if best_socket != "":
			var kind: String = StationLayout.SOCKETS[best_socket].kind
			if kind == "pod" and role_of(id) != INFILTRATOR:
				return {"action": "none", "item": player.holding, "socket": best_socket, "label": "Pod locked"}
			var labels := {"reactor": "Insert cell", "shuttle": "Load shuttle", "pod": "Arm pod"}
			return {"action": "insert", "item": player.holding, "socket": best_socket, "label": labels.get(kind, "Insert")}
		return {"action": "drop", "item": player.holding, "socket": "", "label": "Drop"}
	var best_item := ""
	var best := INTERACT_RANGE
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item.holder != 0:
			continue
		if item.socket != "" and socket_locked(item.socket):
			continue
		var distance := _flat_distance(pos, item_position(item_id))
		if distance < best:
			best = distance
			best_item = item_id
	if best_item == "":
		return {}
	var item: Dictionary = items[best_item]
	var label := "Pick up core" if item.kind == "core" else "Pick up cell"
	if item.socket != "":
		label = "Pull core out"
	return {"action": "pickup", "item": best_item, "socket": item.socket, "label": label}


## Host only. Applies the interaction; returns true on success.
func request_interact(id: int) -> bool:
	var plan := available_action(id)
	if plan.is_empty() or plan.action == "none":
		return false
	var player: Dictionary = players[id]
	var item_id: String = plan.item
	var item: Dictionary = items[item_id]
	match plan.action:
		"pickup":
			var from_socket: String = item.socket
			if from_socket != "":
				socket_items[from_socket] = ""
				item.socket = ""
				_on_core_removed(from_socket, player.name)
			item.holder = id
			player.holding = item_id
			_log("%s picked up the %s." % [player.name, _item_name(item)])
		"drop":
			_drop(id)
			_log("%s dropped the %s." % [player.name, _item_name(item)])
		"insert":
			player.holding = ""
			item.holder = 0
			_seat(item_id, item, plan.socket)
			_on_inserted(plan.socket, player.name)
	return true


func _item_name(item: Dictionary) -> String:
	return "core" if item.kind == "core" else "power cell"


func _seat(item_id: String, item: Dictionary, socket_id: String) -> void:
	item.socket = socket_id
	item.pos = _socket_pos(socket_id)
	socket_items[socket_id] = item_id


func _drop(id: int) -> void:
	var player: Dictionary = players[id]
	if player.holding == "":
		return
	var item: Dictionary = items[player.holding]
	item.holder = 0
	item.pos = Vector3(player.pos.x, 0.0, player.pos.z)
	player.holding = ""


func _on_inserted(socket_id: String, who: String) -> void:
	var kind: String = StationLayout.SOCKETS[socket_id].kind
	match kind:
		"reactor":
			var cells := powered_cells()
			_log("%s inserted a power cell (%d/%d)." % [who, cells, reactor_socket_count()])
			_alert("Power cell %d/%d online" % [cells, reactor_socket_count()], "info")
			if cells >= reactor_socket_count() and phase == Phase.STABILISE:
				phase = Phase.EXTRACTION
				_log("Power restored. The core vault opened.")
				_alert("POWER RESTORED — core vault open in Command", "power")
		"shuttle":
			shuttle_left = SHUTTLE_SECONDS
			_log("%s loaded the core into the shuttle." % who)
			_alert("Shuttle launch sequence started", "shuttle")
		"pod":
			pod_left = POD_SECONDS
			_log("%s armed the cargo pod." % who)
			_alert("WARNING: cargo pod armed in Cargo", "pod")


func _on_core_removed(socket_id: String, who: String) -> void:
	var kind: String = StationLayout.SOCKETS[socket_id].kind
	match kind:
		"vault":
			_log("%s took the core from the vault." % who)
			_alert("The core has left the vault", "info")
		"shuttle":
			shuttle_left = -1.0
			_log("%s pulled the core out of the shuttle." % who)
			_alert("Shuttle launch aborted", "abort")
		"pod":
			pod_left = -1.0
			_log("%s pulled the core out of the cargo pod." % who)
			_alert("Cargo pod disarmed", "abort")


## Host only. Returns the shoved peer id, or 0.
func request_shove(id: int) -> int:
	if not players.has(id) or phase == Phase.RESULT or phase == Phase.BRIEFING:
		return 0
	var player: Dictionary = players[id]
	if player.shove_ready > elapsed or player.stunned_until > elapsed:
		return 0
	var forward := Vector3(sin(player.yaw), 0, cos(player.yaw))
	var target := 0
	var best := SHOVE_RANGE
	for other_id in players:
		if other_id == id:
			continue
		var offset: Vector3 = players[other_id].pos - player.pos
		offset.y = 0
		var distance := offset.length()
		if distance > best:
			continue
		# Generous cone: anyone roughly in front, or practically touching.
		if distance > 0.6 and forward.dot(offset.normalized()) < 0.2:
			continue
		best = distance
		target = other_id
	player.shove_ready = elapsed + SHOVE_COOLDOWN
	if target == 0:
		return 0
	var victim: Dictionary = players[target]
	victim.stunned_until = elapsed + STUN_SECONDS
	var dropped: String = victim.holding
	if dropped != "":
		_drop(target)
		_log("%s shoved %s, who dropped the %s." % [player.name, victim.name, _item_name(items[dropped])])
	else:
		_log("%s shoved %s." % [player.name, victim.name])
	var push: Vector3 = victim.pos - player.pos
	push.y = 0
	if push.length() < 0.01:
		push = forward
	events.append({"type": "shoved", "target": target, "by": id, "dir": push.normalized()})
	return target


## Host only. Infiltrator-only blackout.
func request_sabotage(id: int) -> bool:
	if role_of(id) != INFILTRATOR or phase == Phase.RESULT or phase == Phase.BRIEFING:
		return false
	if blackout_ready > elapsed:
		return false
	blackout_until = elapsed + BLACKOUT_SECONDS
	blackout_ready = elapsed + BLACKOUT_COOLDOWN
	_log("%s triggered a blackout." % players[id].name)
	_alert("BLACKOUT — main lights failed", "blackout")
	return true


func sabotage_cooldown() -> float:
	return maxf(0.0, blackout_ready - elapsed)


func remove_player(id: int) -> void:
	if not players.has(id):
		return
	var name: String = players[id].name
	_drop(id)
	var was_infiltrator: bool = players[id].role == INFILTRATOR
	players.erase(id)
	_log("%s disconnected." % name)
	if phase == Phase.RESULT:
		return
	if was_infiltrator:
		_finish("none", "The infiltrator disconnected — round interrupted.")
	elif players.size() < 2:
		_finish("none", "Not enough crew left — round interrupted.")


func tick(delta: float) -> void:
	if phase == Phase.RESULT:
		return
	elapsed += delta
	if phase == Phase.BRIEFING and elapsed >= BRIEFING_SECONDS:
		phase = Phase.STABILISE
		_alert("Restore power: bring 3 cells to the Reactor", "info")
	if shuttle_left >= 0.0:
		shuttle_left -= delta
		if shuttle_left <= 0.0:
			shuttle_left = 0.0
			_finish(CREW, "The shuttle escaped with the core.")
			return
	if pod_left >= 0.0:
		pod_left -= delta
		if pod_left <= 0.0:
			pod_left = 0.0
			_finish(INFILTRATOR, "The cargo pod launched with the core.")
			return
	if elapsed >= ROUND_SECONDS:
		_finish("none", "Time ran out. The station was lost.")


func _finish(who: String, why: String) -> void:
	if phase == Phase.RESULT:
		return
	phase = Phase.RESULT
	winner = who
	reason = why
	blackout_until = -1.0
	_log(why)
	events.append({"type": "result"})


func _log(text: String) -> void:
	var seconds := int(elapsed)
	timeline.append("%d:%02d  %s" % [seconds / 60, seconds % 60, text])


func _alert(text: String, kind: String) -> void:
	events.append({"type": "alert", "text": text, "kind": kind})


func drain_events() -> Array:
	var out := events
	events = []
	return out


## Everything every client may know. Roles, the timeline and the infiltrator's
## name are withheld until the round ends.
func public_snapshot() -> Dictionary:
	var public_players := {}
	for id in players:
		var p: Dictionary = players[id]
		public_players[id] = {"name": p.name, "color": p.color, "holding": p.holding,
			"stunned": maxf(0.0, p.stunned_until - elapsed)}
	var public_items := {}
	for item_id in items:
		var item: Dictionary = items[item_id]
		public_items[item_id] = {"kind": item.kind, "holder": item.holder, "pos": item.pos, "socket": item.socket}
	var snap := {
		"phase": phase, "elapsed": elapsed, "players": public_players, "items": public_items,
		"shuttle_left": shuttle_left, "pod_left": pod_left,
		"blackout_left": maxf(0.0, blackout_until - elapsed),
		"blackout_ready_in": maxf(0.0, blackout_ready - elapsed),
	}
	if phase == Phase.RESULT:
		snap["winner"] = winner
		snap["reason"] = reason
		snap["infiltrator"] = infiltrator_name
		snap["timeline"] = timeline.duplicate()
	return snap


## Client mirror: rebuild from a host snapshot. Keeps locally known poses.
func apply_snapshot(snap: Dictionary, own_id: int, own_role: String) -> void:
	is_mirror = true
	phase = snap.phase
	elapsed = snap.elapsed
	shuttle_left = snap.shuttle_left
	pod_left = snap.pod_left
	blackout_until = elapsed + snap.blackout_left
	blackout_ready = elapsed + snap.blackout_ready_in
	var next_players := {}
	for key in snap.players:
		var id := int(key)
		var p: Dictionary = snap.players[key]
		var previous: Dictionary = players.get(id, {})
		next_players[id] = {
			"name": p.name, "color": p.color, "holding": p.holding,
			"role": own_role if id == own_id else "",
			"pos": previous.get("pos", Vector3.ZERO), "yaw": previous.get("yaw", 0.0),
			"shove_ready": previous.get("shove_ready", 0.0),
			"stunned_until": elapsed + float(p.stunned),
		}
	players = next_players
	items = {}
	for item_id in snap.items:
		var item: Dictionary = snap.items[item_id]
		items[item_id] = {"kind": item.kind, "holder": int(item.holder), "pos": item.pos, "socket": item.socket}
	socket_items = {}
	for socket_id in StationLayout.SOCKETS:
		socket_items[socket_id] = ""
	for item_id in items:
		if items[item_id].socket != "":
			socket_items[items[item_id].socket] = item_id
	if snap.has("winner"):
		winner = snap.winner
		reason = snap.reason
		infiltrator_name = snap.infiltrator
		timeline = snap.timeline
