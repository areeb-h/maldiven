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
const DOWN_SLUMP := 0.4  # m a downed body ends up along its fall
# Throws are physical: the item leaves the thrower's hands with this velocity
# (about 7 m on flat floor before it bounces). Heavier items fly a little shorter.
const THROW_SPEED := 8.4
const THROW_LIFT := 3.4
const THROW_SPEED_SCALE := {"cell": 1.0, "core": 0.9, "gun": 1.12}
const THROW_HOT_MAX := 2.5  # s: a thrown item stops being dangerous after this
const THROW_HIT_SPEED := 3.0  # m/s: anything slower doesn't stun
const THROW_STUN := 1.6
const THROW_HIT_RADIUS := 0.95  # rules-only fallback (no physics attached)
const GRAVITY := 9.8
const HAND_REACH := 0.45  # m in front of the body where held items sit
const HAND_HEIGHT := 0.75  # item origin (its bottom) when held at the hands
const VENT_DRIFT_SECONDS := 3.0  # vented items drift this long, then return to their dock
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
## item id -> {kind, holder (peer id or 0), pos: Vector3, rot: Quaternion, vel: Vector3,
##             socket: String, ammo, flight ({} or {by, start}: thrown and dangerous),
##             moving (physics awake), lost (elapsed time it returns after venting, or -1),
##             epoch (bumped whenever it becomes loose or teleports)}
## A loose item (holder 0, no socket) is a physics body on the host; the host
## writes its pose back into pos/rot/vel/moving every physics tick.
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
## Host only: true when StationPhysics simulates loose items (and reports hits,
## cooling and positions). False in pure rule tests: thrown items then follow a
## simple ballistic arc with a distance hit test.
var physics_driven := false


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
			"rot": Quaternion.IDENTITY, "vel": Vector3.ZERO, "socket": "",
			"ammo": GUN_AMMO if StationLayout.ITEMS[item_id].kind == "gun" else 0, "flight": {},
			"moving": false, "lost": -1.0, "epoch": 0}
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
	item.lost = -1.0
	item.vel = Vector3.ZERO
	item.rot = Quaternion.IDENTITY
	item.moving = false
	item.epoch = int(item.epoch) + 1
	if spec.has("socket"):
		_seat(item_id, item, spec.socket)
	else:
		item.pos = StationLayout.to_world(spec.pos, 0.0)


## Host physics: an item fell out of the world or came to rest out of reach.
func respawn_item(item_id: String) -> void:
	if not items.has(item_id) or int(items[item_id].holder) != 0 or items[item_id].socket != "":
		return
	_respawn_item(item_id)
	_log("The %s rolled out of reach; a drone returned it to its dock." % _item_name(items[item_id]))


## The item becomes a loose physics body at `at`, moving with `vel`.
func _make_loose(item_id: String, at: Vector3, rot: Quaternion, vel: Vector3) -> void:
	var item: Dictionary = items[item_id]
	item.holder = 0
	item.socket = ""
	item.flight = {}
	item.rot = rot
	item.epoch = int(item.epoch) + 1
	if physics_driven:
		item.pos = at
		item.vel = vel
		item.moving = true
	else:
		# No simulation: it lands straight under the hands.
		item.pos = Vector3(at.x, 0.0, at.z)
		item.vel = Vector3.ZERO
		item.moving = false


## Where a carried item sits in front of a player (kept out of walls).
func _hands_position(id: int) -> Vector3:
	var player: Dictionary = players[id]
	var target: Vector3 = player.pos + _forward(player.yaw) * HAND_REACH + Vector3(0, HAND_HEIGHT, 0)
	if wall_clamp.is_valid():
		target = wall_clamp.call(player.pos, target)
	return target


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
	if item.holder != 0 and players.has(item.holder):
		return players[item.holder].pos + Vector3(0, 1.1, 0)
	return item.pos


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
		if item.holder != 0 or not item.flight.is_empty() or float(item.lost) >= 0.0:
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


## The held item leaves the player's hands as a loose body. `vel` throws it
## (knocked loose by a shove, a hit or a fall); zero just lets it go.
func _drop(id: int, vel := Vector3.ZERO) -> void:
	var player: Dictionary = players[id]
	if player.holding == "":
		return
	var item_id: String = player.holding
	var gentle := vel if not vel.is_zero_approx() else _forward(player.yaw) * 0.6
	_make_loose(item_id, _hands_position(id), Quaternion(Vector3.UP, float(player.yaw)), gentle)
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
		_throw(id)
		return 0
	# The swing itself: the physics layer knocks props and loose items in front.
	events.append({"type": "swing", "by": id, "at": player.pos, "dir": forward})
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
		# Never through a wall.
		if has_los.is_valid() and not has_los.call(player.pos + Vector3(0, 1.2, 0), players[other_id].pos + Vector3(0, 1.2, 0)):
			continue
		best = distance
		target = other_id
	if target == 0:
		return 0
	var victim: Dictionary = players[target]
	victim.stunned_until = elapsed + STUN_SECONDS
	var dropped: String = victim.holding
	var push: Vector3 = victim.pos - player.pos
	push.y = 0
	if push.length() < 0.01:
		push = forward
	push = push.normalized()
	if dropped != "":
		# Knocked out of their hands: it pops forward and up, in the push direction.
		_drop(target, push * 3.0 + Vector3.UP * 2.6)
		_log("%s shoved %s, who dropped the %s." % [player.name, victim.name, _item_name(items[dropped])])
	elif victim.body != 0:
		_log("%s shoved %s, who dropped %s." % [player.name, victim.name, players[victim.body].name])
		_release_body(target)
	else:
		_log("%s shoved %s." % [player.name, victim.name])
	events.append({"type": "shoved", "target": target, "by": id, "dir": push})
	return target


func _throw(id: int) -> void:
	var player: Dictionary = players[id]
	var item_id: String = player.holding
	var item: Dictionary = items[item_id]
	var scale: float = THROW_SPEED_SCALE.get(item.kind, 1.0)
	var vel := (_forward(player.yaw) * THROW_SPEED + Vector3.UP * THROW_LIFT) * scale
	_make_loose(item_id, _hands_position(id), Quaternion(Vector3.UP, float(player.yaw)), vel)
	player.holding = ""
	item.flight = {"by": id, "start": elapsed}
	if not physics_driven:
		item.pos = _hands_position(id)  # the fallback arc starts at the hands too
		item.vel = vel
		item.moving = true
	_log("%s threw the %s." % [player.name, _item_name(item)])
	events.append({"type": "thrown", "item": item_id, "by": id, "vel": vel})


## Host physics: a thrown item hit a standing player. Same stun and drop as a
## shove (longer stun), at most one victim per throw. Returns true if it counted.
func item_hit(item_id: String, target: int, direction: Vector3) -> bool:
	if not items.has(item_id) or not players.has(target):
		return false
	var item: Dictionary = items[item_id]
	if item.flight.is_empty() or int(item.flight.by) == target or players[target].state != OK:
		return false
	var flight: Dictionary = item.flight
	item.flight = {}
	var victim: Dictionary = players[target]
	victim.stunned_until = maxf(float(victim.stunned_until), elapsed + THROW_STUN)
	var dir := Vector3(direction.x, 0.0, direction.z)
	dir = dir.normalized() if dir.length() > 0.01 else _forward(float(victim.yaw))
	if victim.holding != "":
		_drop(target, dir * 2.0 + Vector3.UP * 2.2)
	_release_body(target)
	var thrower: String = players[flight.by].name if players.has(flight.by) else "Someone"
	_log("%s hit %s with the %s." % [thrower, victim.name, _item_name(item)])
	events.append({"type": "shoved", "target": target, "by": flight.by, "dir": dir, "item": true})
	return true


## Host physics: a thrown item slowed down and is harmless again.
func cool_item(item_id: String) -> void:
	if items.has(item_id):
		items[item_id].flight = {}


func _tick_flights(delta: float) -> void:
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item.flight.is_empty():
			continue
		if not physics_driven:
			_fallback_flight(item_id, item, delta)
		if not item.flight.is_empty() and elapsed - float(item.flight.start) > THROW_HOT_MAX:
			item.flight = {}


## Rules-only throws (tests, or no physics attached): a ballistic arc that stops
## at walls and the floor, with a simple distance hit test.
func _fallback_flight(item_id: String, item: Dictionary, delta: float) -> void:
	var vel: Vector3 = item.vel
	vel.y -= GRAVITY * delta
	var next: Vector3 = item.pos + vel * delta
	if not StationLayout.is_walkable(next):
		next = Vector3(item.pos.x, next.y, item.pos.z)
		vel = Vector3(0.0, minf(vel.y, 0.0), 0.0)
	var landed := next.y <= 0.0
	if landed:
		next.y = 0.0
		vel = Vector3.ZERO
	item.pos = next
	item.vel = vel
	for other_id in players:
		var other: Dictionary = players[other_id]
		if other_id == item.flight.by or other.state != OK:
			continue
		if _flat_distance(next, other.pos) < THROW_HIT_RADIUS and next.y < 2.0:
			if item_hit(item_id, other_id, item.vel if item.vel.length() > 0.1 else next - other.pos):
				item.pos = Vector3(next.x, 0.0, next.z)
				item.vel = Vector3.ZERO
				item.moving = false
				return
	if landed:
		item.flight = {}
		item.moving = false
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
		_down(target, players[target].pos - shooter.pos)
	else:
		_log("%s fired and missed." % shooter.name)
	events.append({"type": "shot", "by": id, "from": eye, "to": end, "target": target})
	return target


## Knocked down, falling along `fall` (away from the shooter). The body lies
## where it lands: a little along the fall, head pointing the way it fell.
func _down(id: int, fall := Vector3.ZERO) -> void:
	var player: Dictionary = players[id]
	var dir := Vector3(fall.x, 0.0, fall.z)
	dir = dir.normalized() if dir.length() > 0.01 else -_forward(float(player.yaw))
	if player.holding != "":
		_drop(id, dir * 1.4 + Vector3.UP * 1.6)
	_release_body(id)
	player.state = DOWNED
	player.down_until = elapsed + DOWN_SECONDS
	var feet := Vector3(player.pos.x, 0.0, player.pos.z)
	var lie := feet + dir * DOWN_SLUMP
	if wall_clamp.is_valid():
		lie = wall_clamp.call(feet, lie)
	player.pos = Vector3(lie.x, 0.0, lie.z)
	player.yaw = atan2(dir.x, dir.z) + PI  # the model lies head-first along -Z
	_alert("Someone is down" if is_blackout() else "%s is down" % player.name, "down")
	events.append({"type": "downed", "target": id, "at": player.pos, "dir": dir, "yaw": player.yaw})


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
		if item.holder == 0 and item.socket == "" and float(item.lost) < 0.0 and in_airlock(item.pos):
			item.lost = elapsed + VENT_DRIFT_SECONDS
			item.flight = {}
			_log("The %s was blown into space; a drone will bring it back to its dock." % _item_name(item))
	if spaced.is_empty():
		_log("The airlock vented an empty chamber.")
		_alert("Airlock vented — chamber was empty", "airlock")
	_check_survivors()


func _kill(id: int) -> void:
	var player: Dictionary = players[id]
	if player.holding != "":
		_drop(id)  # loose in the chamber: the vent blows it out with everything else
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
	_tick_flights(delta)
	_tick_airlock(delta)
	for item_id in items:
		var item: Dictionary = items[item_id]
		if float(item.lost) >= 0.0 and elapsed >= float(item.lost):
			_respawn_item(item_id)
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
			flight = {"age": elapsed - float(item.flight.start), "by": item.flight.by}
		public_items[item_id] = {"kind": item.kind, "holder": item.holder, "pos": item.pos,
			"rot": item.rot, "socket": item.socket, "ammo": item.ammo, "flight": flight,
			"moving": item.moving, "lost": float(item.lost) >= 0.0, "epoch": item.epoch}
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
			flight = {"start": elapsed - float(item.flight.age), "by": int(item.flight.by)}
		items[item_id] = {"kind": item.kind, "holder": int(item.holder), "pos": item.pos,
			"rot": item.get("rot", Quaternion.IDENTITY), "vel": Vector3.ZERO, "socket": item.socket,
			"ammo": int(item.ammo), "flight": flight, "moving": bool(item.get("moving", false)),
			"lost": elapsed if item.get("lost", false) else -1.0, "epoch": int(item.get("epoch", 0))}
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
