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
const CARRY_SPEED := {"cell": 0.8, "core": 0.72, "gun": 1.0, "body": 0.62}
# Week 2: the gun question, downed/drag/medbay, airlock, throwing.
const GUN_AMMO := 3
const GUN_RANGE := 18.0
const GUN_CONE := 0.38  # radians either side of facing (aim assist)
const GUN_COOLDOWN := 0.8
const DOWN_SECONDS := 25.0
const THROW_DISTANCE := 7.5
const THROW_SECONDS := 0.55
const THROW_STUN := 1.6
const THROW_HIT_RADIUS := 0.95
const AIRLOCK_WARNING := 3.5
const AIRLOCK_COOLDOWN := 20.0
const GHOST_SPEED := 1.35

const CREW := "crew"
const INFILTRATOR := "infiltrator"
const OK := "ok"
const DOWNED := "downed"
const DEAD := "dead"

var phase: int = Phase.BRIEFING
var elapsed := 0.0
## peer id -> {name, color, role (host only), pos, yaw, holding, body, carried_by,
##             state, down_until, shove_ready, stunned_until}
var players := {}
## item id -> {kind, holder (peer id or 0), pos: Vector3, socket: String, ammo, flight}
var items := {}
## socket id -> item id or ""
var socket_items := {}
var shuttle_left := -1.0
var pod_left := -1.0
var blackout_until := -1.0
var blackout_ready := BLACKOUT_FIRST_DELAY
var airlock_state := "idle"  # idle / warning / cooldown
var airlock_left := 0.0
var gun_ready := 0.0
var winner := ""
var reason := ""
var infiltrator_name := ""
var timeline: Array = []
## Drained by the network layer: public alerts and effects.
var events: Array = []
## Host only, optional: func(from: Vector3, to: Vector3) -> Vector3 that pulls a
## dragged body's position back out of walls. Unset in tests and on clients.
var wall_clamp := Callable()


func setup(roster: Dictionary, rng: RandomNumberGenerator) -> void:
	players.clear()
	timeline.clear()
	events.clear()
	winner = ""
	reason = ""
	shuttle_left = -1.0
	pod_left = -1.0
	blackout_until = -1.0
	blackout_ready = BLACKOUT_FIRST_DELAY
	airlock_state = "idle"
	airlock_left = 0.0
	gun_ready = 0.0
	var ids := roster.keys()
	ids.sort()
	# A solo walkaround has no infiltrator.
	var infiltrator: int = ids[rng.randi_range(0, ids.size() - 1)] if ids.size() > 1 else -1
	for index in range(ids.size()):
		var id: int = ids[index]
		var entry: Dictionary = roster[id]
		players[id] = _new_player(str(entry.get("name", "Crew")), entry.get("color", Color.WHITE),
			INFILTRATOR if id == infiltrator else CREW, StationLayout.spawn_point(index, ids.size()))
	infiltrator_name = players[infiltrator].name if players.has(infiltrator) else "nobody"
	items.clear()
	socket_items.clear()
	for socket_id in StationLayout.SOCKETS:
		socket_items[socket_id] = ""
	for item_id in StationLayout.ITEMS:
		items[item_id] = {"kind": StationLayout.ITEMS[item_id].kind, "holder": 0, "pos": Vector3.ZERO,
			"socket": "", "ammo": GUN_AMMO if StationLayout.ITEMS[item_id].kind == "gun" else 0, "flight": {}}
		_respawn_item(item_id)
	phase = Phase.BRIEFING
	elapsed = 0.0
	_log("Round started with %d crew aboard." % ids.size())


func _new_player(player_name: String, color: Color, role: String, pos: Vector3) -> Dictionary:
	return {"name": player_name, "color": color, "role": role, "pos": pos, "yaw": 0.0,
		"holding": "", "body": 0, "carried_by": 0, "state": OK, "down_until": 0.0,
		"shove_ready": 0.0, "stunned_until": 0.0}


func _respawn_item(item_id: String) -> void:
	var spec: Dictionary = StationLayout.ITEMS[item_id]
	var item: Dictionary = items[item_id]
	if item.socket != "":
		socket_items[item.socket] = ""
	item.holder = 0
	item.socket = ""
	item.flight = {}
	if spec.has("socket"):
		_seat(item_id, item, spec.socket)
	else:
		item.pos = StationLayout.to_world(spec.pos, 0.0)


# --- Queries -----------------------------------------------------------------

func role_of(id: int) -> String:
	return players[id].role if players.has(id) else ""


func state_of(id: int) -> String:
	return players[id].state if players.has(id) else DEAD


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


func _active(id: int) -> bool:
	return players.has(id) and players[id].state == OK and players[id].stunned_until <= elapsed


func speed_factor(id: int) -> float:
	if not players.has(id):
		return 1.0
	var player: Dictionary = players[id]
	if player.state == DEAD:
		return GHOST_SPEED
	if player.state == DOWNED or player.stunned_until > elapsed:
		return 0.0
	if player.body != 0:
		return CARRY_SPEED.body
	if player.holding != "":
		return CARRY_SPEED.get(items[player.holding].kind, 1.0)
	return 1.0


func set_pose(id: int, pos: Vector3, yaw: float) -> void:
	if not players.has(id):
		return
	var player: Dictionary = players[id]
	if player.state == DOWNED:
		return  # the host places downed bodies
	player.pos = pos
	player.yaw = yaw
	if player.body != 0 and players.has(player.body):
		players[player.body].pos = _body_position(pos, yaw)


## Where a dragged body sits: in front of the carrier, never inside a wall.
func _body_position(carrier_pos: Vector3, yaw: float) -> Vector3:
	var target := carrier_pos + _forward(yaw) * 0.7
	if wall_clamp.is_valid():
		target = wall_clamp.call(carrier_pos, target)
	return target


## Names stay hidden during a blackout, in prompts and alerts as well as tags.
func _visible_name(id: int) -> String:
	if is_blackout() or not players.has(id):
		return "someone"
	return str(players[id].name)


func _forward(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))


func item_position(item_id: String) -> Vector3:
	var item: Dictionary = items[item_id]
	if not item.flight.is_empty():
		return _flight_position(item.flight)
	if item.holder != 0 and players.has(item.holder):
		return players[item.holder].pos + Vector3(0, 1.1, 0)
	return item.pos


func _flight_position(flight: Dictionary) -> Vector3:
	var t := clampf((elapsed - float(flight.start)) / float(flight.dur), 0.0, 1.0)
	var from: Vector3 = flight.from
	var to: Vector3 = flight.to
	var point := from.lerp(to, t)
	point.y += sin(t * PI) * 1.6
	return point


func _socket_pos(socket_id: String) -> Vector3:
	return StationLayout.to_world(StationLayout.SOCKETS[socket_id].pos)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func socket_locked(socket_id: String) -> bool:
	var kind: String = StationLayout.SOCKETS[socket_id].kind
	if kind == "vault" or kind == "armory":
		return phase < Phase.EXTRACTION
	if kind == "reactor":
		return socket_items[socket_id] != ""  # seated cells stay seated
	return false


func airlock_ready() -> bool:
	return airlock_state == "idle" and (phase == Phase.STABILISE or phase == Phase.EXTRACTION)


func in_airlock(pos: Vector3) -> bool:
	return StationLayout.room_rect("airlock").has_point(Vector2(pos.x, pos.z))


# --- Interact ----------------------------------------------------------------

## What pressing Interact would do right now for this player.
## Returns {} when nothing, else {action, item, socket, target, label}.
func available_action(id: int) -> Dictionary:
	if not players.has(id) or phase == Phase.RESULT or phase == Phase.BRIEFING:
		return {}
	if not _active(id):
		return {}
	var player: Dictionary = players[id]
	var pos: Vector3 = player.pos
	if player.body != 0:
		var body_name: String = _visible_name(player.body)
		if _flat_distance(pos, _socket_pos("medbay")) < INTERACT_RANGE:
			return {"action": "revive", "target": player.body, "label": "Revive " + body_name}
		return {"action": "drop_body", "target": player.body, "label": "Drop " + body_name}
	if player.holding != "":
		var held: Dictionary = items[player.holding]
		var best_socket := ""
		var best_distance := INTERACT_RANGE
		for socket_id in StationLayout.SOCKETS:
			var spec: Dictionary = StationLayout.SOCKETS[socket_id]
			if spec.accepts != held.kind or socket_items[socket_id] != "":
				continue
			if spec.kind in ["vault", "armory"]:
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
	var best := {}
	var best_distance := INTERACT_RANGE
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item.holder != 0 or not item.flight.is_empty():
			continue
		if item.socket != "" and socket_locked(item.socket):
			continue
		var distance := _flat_distance(pos, item_position(item_id))
		if distance < best_distance:
			best_distance = distance
			var label: String = {"core": "Pick up core", "cell": "Pick up cell", "gun": "Take gun"}.get(item.kind, "Pick up")
			if item.socket != "" and item.kind == "core":
				label = "Pull core out"
			best = {"action": "pickup", "item": item_id, "socket": item.socket, "label": label}
	for other_id in players:
		var other: Dictionary = players[other_id]
		if other_id == id or other.state != DOWNED or other.carried_by != 0:
			continue
		var distance := _flat_distance(pos, other.pos)
		if distance < best_distance:
			best_distance = distance
			best = {"action": "drag", "target": other_id, "label": "Drag " + _visible_name(other_id)}
	if airlock_ready():
		var distance := _flat_distance(pos, _socket_pos("airlock_console"))
		if distance < best_distance:
			best = {"action": "airlock", "socket": "airlock_console", "label": "Cycle airlock"}
	return best


## Host only. Applies the interaction; returns true on success.
func request_interact(id: int) -> bool:
	var plan := available_action(id)
	if plan.is_empty() or plan.action == "none":
		return false
	var player: Dictionary = players[id]
	match plan.action:
		"pickup":
			var item_id: String = plan.item
			var item: Dictionary = items[item_id]
			var from_socket: String = item.socket
			if from_socket != "":
				socket_items[from_socket] = ""
				item.socket = ""
				_on_removed(from_socket, item, player.name)
			item.holder = id
			player.holding = item_id
			_log("%s picked up the %s." % [player.name, _item_name(item)])
			events.append({"type": "fx", "kind": "pickup", "at": item_position(item_id)})
		"drop":
			var item: Dictionary = items[plan.item]
			_drop(id)
			_log("%s dropped the %s." % [player.name, _item_name(item)])
		"insert":
			var item_id: String = plan.item
			var item: Dictionary = items[item_id]
			player.holding = ""
			item.holder = 0
			_seat(item_id, item, plan.socket)
			_on_inserted(plan.socket, player.name)
		"drag":
			var target: int = plan.target
			player.body = target
			players[target].carried_by = id
			players[target].pos = _body_position(player.pos, player.yaw)
			_log("%s started dragging %s." % [player.name, players[target].name])
		"drop_body":
			_release_body(id)
		"revive":
			var target: int = plan.target
			_release_body(id)
			_revive(target, StationLayout.to_world(StationLayout.SOCKETS.medbay.pos) + _forward(StationLayout.SOCKETS.medbay.facing) * 1.2)
			_log("%s revived %s at the medbay." % [player.name, players[target].name])
			_alert("%s is back on their feet" % players[target].name, "info")
		"airlock":
			airlock_state = "warning"
			airlock_left = AIRLOCK_WARNING
			_log("%s cycled the airlock." % player.name)
			_alert("AIRLOCK CYCLING — clear the chamber", "airlock")
			events.append({"type": "airlock", "state": "warning"})
	return true


func _item_name(item: Dictionary) -> String:
	return {"core": "core", "cell": "power cell", "gun": "gun"}.get(item.kind, "item")


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


func _release_body(id: int) -> void:
	var player: Dictionary = players[id]
	if player.body == 0:
		return
	if players.has(player.body):
		var body: Dictionary = players[player.body]
		body.carried_by = 0
		body.pos = Vector3(body.pos.x, 0.0, body.pos.z)
	player.body = 0


func _revive(id: int, at: Vector3) -> void:
	var player: Dictionary = players[id]
	if player.carried_by != 0 and players.has(player.carried_by):
		players[player.carried_by].body = 0
	player.carried_by = 0
	player.state = OK
	player.pos = at
	player.stunned_until = elapsed + 0.4
	events.append({"type": "revived", "target": id, "at": at})


func _on_inserted(socket_id: String, who: String) -> void:
	var kind: String = StationLayout.SOCKETS[socket_id].kind
	match kind:
		"reactor":
			var cells := powered_cells()
			_log("%s inserted a power cell (%d/%d)." % [who, cells, reactor_socket_count()])
			_alert("Power cell %d/%d online" % [cells, reactor_socket_count()], "info")
			events.append({"type": "fx", "kind": "insert_cell", "at": _socket_pos(socket_id)})
			if cells >= reactor_socket_count() and phase == Phase.STABILISE:
				phase = Phase.EXTRACTION
				_log("Power restored. The vault and the armory opened.")
				_alert("POWER RESTORED — vault and armory open", "power")
		"shuttle":
			shuttle_left = SHUTTLE_SECONDS
			_log("%s loaded the core into the shuttle." % who)
			_alert("Shuttle launch sequence started", "shuttle")
		"pod":
			pod_left = POD_SECONDS
			_log("%s armed the cargo pod." % who)
			_alert("WARNING: cargo pod armed in Cargo", "pod")


func _on_removed(socket_id: String, item: Dictionary, who: String) -> void:
	var kind: String = StationLayout.SOCKETS[socket_id].kind
	match kind:
		"vault":
			_log("%s took the core from the vault." % who)
			_alert("The core has left the vault", "info")
		"armory":
			_log("%s took the gun from the armory." % who)
			_alert("Someone took the gun", "gun")
		"shuttle":
			shuttle_left = -1.0
			_log("%s pulled the core out of the shuttle." % who)
			_alert("Shuttle launch aborted", "abort")
		"pod":
			pod_left = -1.0
			_log("%s pulled the core out of the cargo pod." % who)
			_alert("Cargo pod disarmed", "abort")


# --- Shove / throw -----------------------------------------------------------

## Host only. Shoving while holding an item throws it instead.
## Returns the shoved peer id, or 0. `has_los` (optional) checks walls.
func request_shove(id: int, has_los := Callable()) -> int:
	if phase == Phase.RESULT or phase == Phase.BRIEFING or not _active(id):
		return 0
	var player: Dictionary = players[id]
	if player.shove_ready > elapsed:
		return 0
	player.shove_ready = elapsed + SHOVE_COOLDOWN
	var forward := _forward(player.yaw)
	if player.holding != "":
		_throw(id, has_los)
		return 0
	var target := 0
	var best := SHOVE_RANGE
	for other_id in players:
		if other_id == id or players[other_id].state != OK:
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
	if target == 0:
		return 0
	var victim: Dictionary = players[target]
	victim.stunned_until = elapsed + STUN_SECONDS
	var dropped: String = victim.holding
	if dropped != "":
		_drop(target)
		_log("%s shoved %s, who dropped the %s." % [player.name, victim.name, _item_name(items[dropped])])
	elif victim.body != 0:
		_log("%s shoved %s, who dropped %s." % [player.name, victim.name, players[victim.body].name])
		_release_body(target)
	else:
		_log("%s shoved %s." % [player.name, victim.name])
	var push: Vector3 = victim.pos - player.pos
	push.y = 0
	if push.length() < 0.01:
		push = forward
	events.append({"type": "shoved", "target": target, "by": id, "dir": push.normalized()})
	return target


func _throw(id: int, has_los: Callable) -> void:
	var player: Dictionary = players[id]
	var item_id: String = player.holding
	var item: Dictionary = items[item_id]
	var forward := _forward(player.yaw)
	var start: Vector3 = player.pos + Vector3(0, 1.1, 0)
	var landing: Vector3 = player.pos
	var distance := THROW_DISTANCE
	while distance > 0.4:
		var candidate: Vector3 = player.pos + forward * distance
		var clear := StationLayout.is_walkable(candidate)
		if clear and has_los.is_valid():
			clear = has_los.call(start, candidate + Vector3(0, 1.0, 0))
		if clear:
			landing = candidate
			break
		distance -= 0.5
	landing.y = 0.0
	player.holding = ""
	item.holder = 0
	item.pos = landing
	item.flight = {"from": start, "to": landing, "start": elapsed, "dur": THROW_SECONDS, "by": id}
	_log("%s threw the %s." % [player.name, _item_name(item)])
	events.append({"type": "thrown", "item": item_id, "by": id})


func _tick_flights() -> void:
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item.flight.is_empty():
			continue
		var flight: Dictionary = item.flight
		var at := _flight_position(flight)
		for other_id in players:
			var other: Dictionary = players[other_id]
			if other_id == flight.by or other.state != OK:
				continue
			if _flat_distance(at, other.pos) < THROW_HIT_RADIUS:
				other.stunned_until = elapsed + THROW_STUN
				if other.holding != "":
					_drop(other_id)
				_release_body(other_id)
				item.pos = Vector3(at.x, 0.0, at.z)
				item.flight = {}
				var thrower: String = players[flight.by].name if players.has(flight.by) else "Someone"
				_log("%s hit %s with the %s." % [thrower, other.name, _item_name(item)])
				events.append({"type": "shoved", "target": other_id, "by": flight.by,
					"dir": (Vector3(flight.to) - Vector3(flight.from)).normalized()})
				break
		if not item.flight.is_empty() and elapsed >= float(flight.start) + float(flight.dur):
			item.flight = {}
			events.append({"type": "fx", "kind": "drop", "at": item.pos})


# --- Gun ---------------------------------------------------------------------

func holds_gun(id: int) -> bool:
	return players.has(id) and players[id].holding != "" and items[players[id].holding].kind == "gun"


func gun_ammo() -> int:
	for item_id in items:
		if items[item_id].kind == "gun":
			return int(items[item_id].ammo)
	return 0


## Host only. Aim-assisted shot along the shooter's facing. Returns the hit peer
## id, 0 for a miss, -1 when the shot wasn't allowed.
func request_shoot(id: int, has_los := Callable()) -> int:
	if phase == Phase.RESULT or not _active(id) or not holds_gun(id):
		return -1
	var gun: Dictionary = items[players[id].holding]
	if int(gun.ammo) <= 0 or gun_ready > elapsed:
		return -1
	var shooter: Dictionary = players[id]
	var forward := _forward(shooter.yaw)
	var eye: Vector3 = shooter.pos + Vector3(0, 1.3, 0)
	var target := 0
	var best_score := INF
	for other_id in players:
		var other: Dictionary = players[other_id]
		if other_id == id or other.state != OK:
			continue
		var offset: Vector3 = other.pos - shooter.pos
		offset.y = 0
		var distance := offset.length()
		if distance > GUN_RANGE or distance < 0.01:
			continue
		var angle := forward.angle_to(offset.normalized())
		if angle > GUN_CONE:
			continue
		if has_los.is_valid() and not has_los.call(eye, other.pos + Vector3(0, 1.2, 0)):
			continue
		var score := angle * 10.0 + distance * 0.1
		if score < best_score:
			best_score = score
			target = other_id
	gun.ammo = int(gun.ammo) - 1
	gun_ready = elapsed + GUN_COOLDOWN
	var end: Vector3 = eye + forward * GUN_RANGE
	if target != 0:
		end = players[target].pos + Vector3(0, 1.2, 0)
		_log("%s shot %s." % [shooter.name, players[target].name])
		_down(target)
	else:
		_log("%s fired and missed." % shooter.name)
	events.append({"type": "shot", "by": id, "from": eye, "to": end, "target": target})
	return target


func _down(id: int) -> void:
	var player: Dictionary = players[id]
	if player.holding != "":
		_drop(id)
	_release_body(id)
	player.state = DOWNED
	player.down_until = elapsed + DOWN_SECONDS
	player.pos = Vector3(player.pos.x, 0.0, player.pos.z)
	_alert("Someone is down" if is_blackout() else "%s is down" % player.name, "down")
	events.append({"type": "downed", "target": id, "at": player.pos})


# --- Airlock -----------------------------------------------------------------

func _tick_airlock(delta: float) -> void:
	if airlock_state == "idle":
		return
	airlock_left -= delta
	if airlock_left > 0.0:
		return
	if airlock_state == "warning":
		_vent()
		airlock_state = "cooldown"
		airlock_left = AIRLOCK_COOLDOWN
	else:
		airlock_state = "idle"
		airlock_left = 0.0
		events.append({"type": "airlock", "state": "idle"})


func _vent() -> void:
	events.append({"type": "airlock", "state": "venting"})
	var spaced := []
	for id in players:
		if players[id].state != DEAD and in_airlock(players[id].pos):
			spaced.append(id)
	for id in spaced:
		_kill(id)
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item.holder == 0 and item.socket == "" and in_airlock(item.pos):
			_respawn_item(item_id)
			_log("The %s was blown into space and drifted back to its dock." % _item_name(item))
	if spaced.is_empty():
		_log("The airlock vented an empty chamber.")
		_alert("Airlock vented — chamber was empty", "airlock")
	_check_survivors()


func _kill(id: int) -> void:
	var player: Dictionary = players[id]
	if player.holding != "":
		var item_id: String = player.holding
		_drop(id)
		_respawn_item(item_id)
	_release_body(id)
	if player.carried_by != 0 and players.has(player.carried_by):
		players[player.carried_by].body = 0
	player.carried_by = 0
	player.state = DEAD
	_log("%s was spaced." % player.name)
	_alert("%s WAS SPACED" % player.name.to_upper(), "spaced")
	events.append({"type": "spaced", "target": id, "at": player.pos})


func _check_survivors() -> void:
	if phase == Phase.RESULT:
		return
	var infiltrator := infiltrator_id()
	if infiltrator != 0 and players[infiltrator].state == DEAD:
		_finish(CREW, "The infiltrator was spaced.")
		return
	var crew_alive := 0
	for id in players:
		if players[id].role == CREW and players[id].state != DEAD:
			crew_alive += 1
	if crew_alive == 0:
		_finish(INFILTRATOR if infiltrator != 0 else "none", "No crew left aboard.")


# --- Sabotage / lifecycle ----------------------------------------------------

## Host only. Infiltrator-only blackout.
func request_sabotage(id: int) -> bool:
	if role_of(id) != INFILTRATOR or phase == Phase.RESULT or phase == Phase.BRIEFING:
		return false
	if state_of(id) != OK or blackout_ready > elapsed:
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
	var leaver_name: String = players[id].name
	_drop(id)
	_release_body(id)
	var carrier: int = players[id].carried_by
	if carrier != 0 and players.has(carrier):
		players[carrier].body = 0
	var was_infiltrator: bool = players[id].role == INFILTRATOR
	players.erase(id)
	_log("%s disconnected." % leaver_name)
	if phase == Phase.RESULT:
		return
	if was_infiltrator:
		_finish("none", "The infiltrator disconnected — round interrupted.")
	elif players.size() < 2 and infiltrator_id() != 0:
		_finish("none", "Not enough crew left — round interrupted.")
	else:
		_check_survivors()


func tick(delta: float) -> void:
	if phase == Phase.RESULT:
		return
	elapsed += delta
	if phase == Phase.BRIEFING and elapsed >= BRIEFING_SECONDS:
		phase = Phase.STABILISE
		_alert("Restore power: bring 3 cells to the Reactor", "info")
	_tick_flights()
	_tick_airlock(delta)
	if phase == Phase.RESULT:
		return
	for id in players:
		var player: Dictionary = players[id]
		if player.state == DOWNED and elapsed >= player.down_until:
			_revive(id, player.pos)
			_log("%s got back up." % player.name)
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


# --- Snapshots ---------------------------------------------------------------

## Everything every client may know. Roles, the timeline and the infiltrator's
## name are withheld until the round ends.
func public_snapshot() -> Dictionary:
	var public_players := {}
	for id in players:
		var p: Dictionary = players[id]
		public_players[id] = {"name": p.name, "color": p.color, "holding": p.holding,
			"stunned": maxf(0.0, p.stunned_until - elapsed), "state": p.state,
			"down_left": maxf(0.0, p.down_until - elapsed), "body": p.body, "carried_by": p.carried_by,
			"shove_in": maxf(0.0, p.shove_ready - elapsed),
			"pos": p.pos}
	var public_items := {}
	for item_id in items:
		var item: Dictionary = items[item_id]
		var flight := {}
		if not item.flight.is_empty():
			flight = {"from": item.flight.from, "to": item.flight.to,
				"age": elapsed - float(item.flight.start), "dur": item.flight.dur, "by": item.flight.by}
		public_items[item_id] = {"kind": item.kind, "holder": item.holder, "pos": item.pos,
			"socket": item.socket, "ammo": item.ammo, "flight": flight}
	var snap := {
		"phase": phase, "elapsed": elapsed, "players": public_players, "items": public_items,
		"shuttle_left": shuttle_left, "pod_left": pod_left,
		"blackout_left": maxf(0.0, blackout_until - elapsed),
		"blackout_ready_in": maxf(0.0, blackout_ready - elapsed),
		"airlock_state": airlock_state, "airlock_left": airlock_left,
		"gun_ready_in": maxf(0.0, gun_ready - elapsed),
	}
	if phase == Phase.RESULT:
		snap["winner"] = winner
		snap["reason"] = reason
		snap["infiltrator"] = infiltrator_name
		snap["timeline"] = timeline.duplicate()
	return snap


## Client mirror: rebuild from a host snapshot. Keeps locally known poses for
## standing players; downed bodies take the host position.
func apply_snapshot(snap: Dictionary, own_id: int, own_role: String) -> void:
	phase = snap.phase
	elapsed = snap.elapsed
	shuttle_left = snap.shuttle_left
	pod_left = snap.pod_left
	blackout_until = elapsed + snap.blackout_left
	blackout_ready = elapsed + snap.blackout_ready_in
	airlock_state = snap.get("airlock_state", "idle")
	airlock_left = snap.get("airlock_left", 0.0)
	gun_ready = elapsed + float(snap.get("gun_ready_in", 0.0))
	var next_players := {}
	for key in snap.players:
		var id := int(key)
		var p: Dictionary = snap.players[key]
		var previous: Dictionary = players.get(id, {})
		var entry := _new_player(p.name, p.color, own_role if id == own_id else "", previous.get("pos", p.pos))
		entry.yaw = previous.get("yaw", 0.0)
		entry.holding = p.holding
		entry.state = p.state
		entry.down_until = elapsed + float(p.down_left)
		entry.body = int(p.body)
		entry.carried_by = int(p.carried_by)
		entry.shove_ready = elapsed + float(p.get("shove_in", 0.0))
		entry.stunned_until = elapsed + float(p.stunned)
		if p.state == DOWNED or not previous.has("pos"):
			entry.pos = p.pos
		next_players[id] = entry
	players = next_players
	items = {}
	for item_id in snap.items:
		var item: Dictionary = snap.items[item_id]
		var flight := {}
		if not item.flight.is_empty():
			flight = {"from": item.flight.from, "to": item.flight.to,
				"start": elapsed - float(item.flight.age), "dur": item.flight.dur, "by": int(item.flight.by)}
		items[item_id] = {"kind": item.kind, "holder": int(item.holder), "pos": item.pos,
			"socket": item.socket, "ammo": int(item.ammo), "flight": flight}
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
