class_name StationWorld
extends Node3D
## One round on the station. The host runs the authoritative StationRules; every
## peer (host included) renders from a rules object: the host's real one, or a
## client mirror rebuilt from public snapshots.

signal leave_requested

const POSE_INTERVAL := 0.05
const SNAPSHOT_INTERVAL := 0.2

var rules := StationRules.new()
var role := ""
var my_id := 0
var local: CrewMember
var avatars := {}  # peer id -> CrewMember
var item_nodes := {}
var socket_nodes := {}
var station: Node3D
var hud: StationHud
var _power_state := ""
var _pose_timer := 0.0
var _snapshot_timer := 0.0
var _dirty := false
var _moving := {}
var _has_snapshot := false
var _seed := -1
var sfx: Sfx
var _holders := {}
var _last_tick := -1
var _result_played := false
var vfx: Node  # optional Vfx module (scripts/vfx.gd), called dynamically
var _states := {}
var _highlighted: Node3D
var _flying := {}
var _alarm_beat := 0
var _alarm_on := false


func _init(round_seed := -1) -> void:
	_seed = round_seed


func _ready() -> void:
	name = "World"
	Net.world = self
	my_id = Net.my_id()
	station = StationBuilder.build(self)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	if ResourceLoader.exists("res://scripts/vfx.gd"):
		vfx = load("res://scripts/vfx.gd").new()
		vfx.name = "Vfx"
		add_child(vfx)
		_fx("ambient_station", [station])
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		var node: Node3D = Props.make_socket(spec.kind)
		node.name = "Socket_" + socket_id
		node.position = StationLayout.to_world(spec.pos)
		node.rotation.y = spec.facing
		add_child(node)
		socket_nodes[socket_id] = node
	for item_id in StationLayout.ITEMS:
		var node: Node3D = Props.make_item(StationLayout.ITEMS[item_id].kind)
		node.name = "Item_" + item_id
		add_child(node)
		item_nodes[item_id] = node
		var kind: String = StationLayout.ITEMS[item_id].kind
		if kind in ["cell", "core"]:
			_fx("attach_item_fx", [node, kind])
	var ids := Net.roster.keys()
	ids.sort()
	for index in range(ids.size()):
		var id: int = ids[index]
		var entry: Dictionary = Net.roster[id]
		var avatar := CrewMember.new()
		avatar.setup(id, id == my_id, entry.name, entry.color, StationLayout.spawn_point(index, ids.size()))
		avatar.number = index + 1
		avatar.variant = index % 4
		add_child(avatar)
		avatars[id] = avatar
		avatar.footstep.connect(func(at: Vector3):
			sfx.play("footstep_%d" % (randi() % 3 + 1), at, -10.0 if id == my_id else -6.0))
		avatar.landed.connect(func(at: Vector3, impact: float):
			sfx.play("footstep_%d" % (randi() % 3 + 1), at, -2.0)
			_fx("burst", ["footstep_dust", at]))
		if id == my_id:
			local = avatar
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = StationHud.new()
	hud.crew = local
	hud.is_host = Net.is_host()
	layer.add_child(hud)
	hud.action_pressed.connect(_on_action)
	hud.leave_pressed.connect(func(): leave_requested.emit())
	hud.lobby_pressed.connect(func(): Net.back_to_lobby())
	if Net.is_host():
		var rng := RandomNumberGenerator.new()
		if _seed >= 0:
			rng.seed = _seed
		else:
			rng.randomize()
		rules.setup(Net.roster, rng)
		rules.wall_clamp = _clamp_to_walls
		if OS.get_cmdline_user_args().has("--bot-host-infiltrator") and rules.players.size() > 1:
			for id in rules.players:  # dev/screenshot option: host plays the infiltrator
				rules.players[id].role = StationRules.INFILTRATOR if id == 1 else StationRules.CREW
			rules.infiltrator_name = rules.players[1].name
		_has_snapshot = true
		for id in rules.players:
			if id == my_id:
				client_role(rules.role_of(id))
			else:
				Net.send_role(id, rules.role_of(id))
		_broadcast_snapshot()
	_apply_power_state()


func _exit_tree() -> void:
	if Net.world == self:
		Net.world = null


func _on_action(action: String) -> void:
	if action == "shove" and not Net.is_host():
		hud.mark_shove_used(rules, my_id)  # optimistic; the next snapshot corrects it
	Net.request(action, local.position, local.facing_yaw())


## Call an optional Vfx method if the module provides it.
func _fx(method: String, args: Array) -> void:
	if vfx != null and vfx.has_method(method):
		vfx.callv(method, args)


## Call an optional static StationBuilder function if it exists.
func _builder(method: String, args: Array) -> void:
	var script: Script = load("res://scripts/station_builder.gd")
	for entry in script.get_script_method_list():
		if entry.name == method:
			script.callv(method, args)
			return


## Host-side: keep a point carried in front of a player out of walls by
## stopping it 0.45 m short of any wall between the carrier and the point.
func _clamp_to_walls(carrier: Vector3, target: Vector3) -> Vector3:
	var chest := Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(carrier + chest, target + chest, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target
	var direction := (target - carrier).normalized()
	var stop: Vector3 = hit.position - chest - direction * 0.45
	return Vector3(stop.x, target.y, stop.z)


## Host-side wall check for shots and throws (world geometry is layer 1).
func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Host side ---------------------------------------------------------------

func host_pose(id: int, pos: Vector3, yaw: float, moving: float) -> void:
	rules.set_pose(id, pos, yaw)
	_moving[id] = moving


func host_request(id: int, action: String, pos: Vector3, yaw: float) -> void:
	rules.set_pose(id, pos, yaw)
	match action:
		"interact":
			_dirty = rules.request_interact(id) or _dirty
		"shove":
			rules.request_shove(id, _line_of_sight)
			_dirty = true
		"shoot":
			_dirty = rules.request_shoot(id, _line_of_sight) >= 0 or _dirty
		"sabotage":
			_dirty = rules.request_sabotage(id) or _dirty
	_flush_events()


func host_player_left(id: int) -> void:
	rules.remove_player(id)
	_remove_avatar(id)
	_dirty = true
	_flush_events()


func _flush_events() -> void:
	for event in rules.drain_events():
		_dirty = true
		if event.type == "result":
			continue
		Net.broadcast_event(event)
		client_event(event)


func _broadcast_snapshot() -> void:
	Net.broadcast_snapshot(rules.public_snapshot())
	_dirty = false
	_snapshot_timer = SNAPSHOT_INTERVAL


# --- Client side (also runs on the host for its own view) --------------------

func client_role(next_role: String) -> void:
	role = next_role
	if rules.players.has(my_id):
		rules.players[my_id].role = role
	hud.set_role(role)


func client_snapshot(snapshot: Dictionary) -> void:
	rules.apply_snapshot(snapshot, my_id, role)
	_has_snapshot = true
	for id in avatars.keys():
		if not rules.players.has(id):
			_remove_avatar(id)


func client_poses(poses: Dictionary) -> void:
	for key in poses:
		var id := int(key)
		var pose: Array = poses[key]
		if id != my_id and avatars.has(id):
			avatars[id].set_remote_pose(pose[0], pose[1], pose[2])
		if not Net.is_host():
			rules.set_pose(id, pose[0], pose[1])


func client_event(event: Dictionary) -> void:
	match event.type:
		"alert":
			hud.flash_alert(event.text, event.kind)
			match event.kind:
				"abort":
					sfx.play("abort")
				"shuttle":
					sfx.play("shuttle_launch_start")
				"info":
					if str(event.text).begins_with("Power cell"):
						sfx.play("insert_cell")
		"shoved":
			var target := int(event.target)
			if avatars.has(target):
				var at: Vector3 = avatars[target].global_position + Vector3(0, 1.1, 0)
				sfx.play("shove", at)
				_fx("burst", ["shove_impact", at, Vector3(event.dir)])
				if avatars[target].visual.has_method("play_hit"):
					avatars[target].visual.play_hit()
				avatars[target].express("hurt")
			if avatars.has(int(event.by)) and avatars[int(event.by)].visual.has_method("play_shove"):
				avatars[int(event.by)].visual.play_shove()
			if target == my_id and local != null:
				local.knockback(event.dir)
				local.camera_kick(0.5)
		"shot":
			var from: Vector3 = event.from
			var to: Vector3 = event.to
			sfx.play("gunshot", from)
			_fx("burst", ["muzzle_flash", from, (to - from).normalized()])
			_fx("tracer", [from, to])
			if avatars.has(int(event.target)):
				avatars[int(event.target)].express("shocked", 1.0)
			if int(event.target) == my_id and local != null:
				local.camera_kick(1.0)
		"downed":
			sfx.play("downed", event.at)
			_fx("burst", ["downed", event.at])
		"revived":
			if int(event.target) == my_id and local != null:
				local.position = event.at
				local.velocity = Vector3.ZERO
				local.snap_smoothing()
			sfx.play("revive", event.at)
			_fx("burst", ["revive", event.at])
		"spaced":
			_fx("burst", ["spaced", event.at])
		"thrown":
			sfx.play("throw", rules.item_position(event.item))
			if item_nodes.has(event.item):
				var trail_color := Color(0.28, 0.92, 1.0) if rules.items[event.item].kind == "core" else Color(1.0, 0.6, 0.14)
				_fx("attach_trail", [item_nodes[event.item], trail_color])
				_flying[event.item] = true
		"fx":
			_fx("burst", [event.kind, event.at])
			if event.kind == "drop":
				sfx.play("drop", event.at)
		"airlock":
			_builder("set_airlock_state", [station, event.state])
			match event.state:
				"warning":
					sfx.play("airlock_warning")
				"venting":
					sfx.play("airlock_vent")
					var room: Dictionary = StationLayout.ROOMS.airlock
					_fx("burst", ["airlock_vent", StationLayout.to_world(room.center, 1.0), Vector3.LEFT])
					if local != null and StationLayout.room_at(local.position) in ["airlock", "commons"]:
						local.camera_kick(0.8)


func _remove_avatar(id: int) -> void:
	if avatars.has(id):
		var avatar: CrewMember = avatars[id]
		for item_id in item_nodes:
			var node: Node3D = item_nodes[item_id]
			if avatar.is_ancestor_of(node):
				node.reparent(self)
		avatar.queue_free()
		avatars.erase(id)


# --- Frame update ------------------------------------------------------------

func _process(delta: float) -> void:
	if not _has_snapshot:
		return
	var host := Net.is_host()
	if host:
		rules.tick(delta)
		_flush_events()
		_snapshot_timer -= delta
		if _dirty or _snapshot_timer <= 0.0:
			_broadcast_snapshot()
	elif rules.phase != StationRules.Phase.RESULT:
		rules.elapsed += delta
		if rules.shuttle_left >= 0.0:
			rules.shuttle_left = maxf(0.0, rules.shuttle_left - delta)
		if rules.pod_left >= 0.0:
			rules.pod_left = maxf(0.0, rules.pod_left - delta)
	_update_player_states()
	if local != null:
		local.speed_factor = rules.speed_factor(my_id)
		var me: Dictionary = rules.players.get(my_id, {})
		local.stunned = float(me.get("stunned_until", 0.0)) > rules.elapsed
		local.aiming = rules.holds_gun(my_id)
		var downed: bool = me.get("state", StationRules.OK) == StationRules.DOWNED
		local.forced_position = me.pos if downed else null  # the host places downed bodies
		if not downed and not host:
			rules.set_pose(my_id, local.position, local.facing_yaw())
		_pose_timer -= delta
		if _pose_timer <= 0.0:
			_pose_timer = POSE_INTERVAL
			Net.send_pose(local.position, local.facing_yaw(), local.moving_amount())
			if host:
				var poses := {}
				for id in rules.players:
					var p: Dictionary = rules.players[id]
					poses[id] = [p.pos, p.yaw, _moving.get(id, 0.0)]
				Net.broadcast_poses(poses)
				client_poses(poses)
	_update_items()
	_update_sockets()
	_apply_power_state()
	_update_audio()
	var action := rules.available_action(my_id)
	_update_highlight(action)
	hud.update_state(rules, action, my_id)


## Outline whatever the Interact button would act on.
func _update_highlight(action: Dictionary) -> void:
	var target: Node3D = null
	match action.get("action", ""):
		"pickup":
			target = item_nodes.get(action.item)
		"insert":
			target = socket_nodes.get(action.socket)
		"airlock":
			target = socket_nodes.get("airlock_console")
		"revive":
			target = socket_nodes.get("medbay")
		"drag":
			if avatars.has(action.target):
				target = avatars[action.target].visual
	if target == _highlighted:
		return
	if _highlighted != null and is_instance_valid(_highlighted):
		_fx("set_interact_highlight", [_highlighted, false])
	_highlighted = target
	if target != null:
		_fx("set_interact_highlight", [target, true])


func _update_audio() -> void:
	for item_id in rules.items:
		var holder: int = rules.items[item_id].holder
		var before: int = _holders.get(item_id, 0)
		if holder != before:
			if holder != 0:
				sfx.play("pickup", rules.item_position(item_id))
			elif rules.items[item_id].socket == "" and rules.items[item_id].flight.is_empty():
				sfx.play("drop", rules.items[item_id].pos)
			_holders[item_id] = holder
	var left := rules.pod_left if rules.pod_left >= 0.0 else rules.shuttle_left
	if left >= 0.0 and left <= 10.0 and rules.phase != StationRules.Phase.RESULT:
		var tick := int(ceil(left))
		if tick != _last_tick:
			_last_tick = tick
			sfx.play("countdown_tick", null, -4.0)
			var pod := rules.pod_left >= 0.0
			var socket_at := StationLayout.to_world(StationLayout.SOCKETS["pod" if pod else "shuttle"].pos)
			_fx("countdown_pulse", [socket_at, Color(1.0, 0.3, 0.3) if pod else Color(0.4, 0.75, 1.0)])
			if pod:
				_alarm_beat += 1
				if _alarm_beat % 2 == 0:
					_fx("burst", ["alarm_strobe", socket_at + Vector3(0, 2.8, 0)])
	else:
		_last_tick = -1
	var alarm_wanted := rules.phase != StationRules.Phase.RESULT \
		and (rules.pod_left >= 0.0 or rules.airlock_state == "warning")
	if alarm_wanted != _alarm_on:
		_alarm_on = alarm_wanted
		if alarm_wanted:
			sfx.start_alarm()
		else:
			sfx.stop_alarm()
	if rules.phase == StationRules.Phase.RESULT and not _result_played:
		_result_played = true
		_builder("set_airlock_state", [station, "idle"])
		if rules.winner == StationRules.CREW:
			sfx.play("win_crew")
			if rules.reason.contains("shuttle"):
				_fx("burst", ["launch", StationLayout.to_world(StationLayout.SOCKETS.shuttle.pos), Vector3.UP])
		elif rules.winner == StationRules.INFILTRATOR:
			sfx.play("win_infiltrator")
			if rules.reason.contains("pod"):
				_fx("burst", ["launch", StationLayout.to_world(StationLayout.SOCKETS.pod.pos), Vector3.UP])
		else:
			sfx.play("power_down")


## Downed / ghost presentation for every avatar.
func _update_player_states() -> void:
	var i_am_dead := rules.state_of(my_id) == StationRules.DEAD
	for id in avatars:
		var avatar: CrewMember = avatars[id]
		var state := rules.state_of(id)
		if _states.get(id, StationRules.OK) != state:
			_states[id] = state
			avatar.set_life_state(state)
			if id == my_id:
				sfx.set_ghost_mode(state == StationRules.DEAD)
		# Ghosts are only visible to other ghosts.
		avatar.visible = state != StationRules.DEAD or i_am_dead
		var body: int = rules.players[id].body if rules.players.has(id) else 0
		avatar.carrying_body = body != 0
		avatar.set_carried(rules.players.has(id) and int(rules.players[id].carried_by) != 0)
	hud.set_life_state(rules.state_of(my_id), float(rules.players.get(my_id, {}).get("down_until", 0.0)) - rules.elapsed)


func _update_items() -> void:
	for item_id in rules.items:
		if not item_nodes.has(item_id):
			continue
		var node: Node3D = item_nodes[item_id]
		var item: Dictionary = rules.items[item_id]
		var holder: int = item.holder
		if item.flight.is_empty() and _flying.has(item_id):
			_flying.erase(item_id)
			_fx("detach_trail", [node])
		if not item.flight.is_empty():
			if node.get_parent() != self:
				node.reparent(self, false)
			node.transform = Transform3D(Basis(Vector3.UP, rules.elapsed * 9.0), rules.item_position(item_id))
		elif holder != 0 and avatars.has(holder):
			var point: Node3D = avatars[holder].hand_point if item.kind == "gun" else avatars[holder].carry_point
			if node.get_parent() != point:
				node.reparent(point, false)
			node.transform = Transform3D.IDENTITY
		elif item.socket != "" and socket_nodes.has(item.socket):
			var socket: Node3D = socket_nodes[item.socket]
			if node.get_parent() != socket:
				node.reparent(socket, false)
			node.transform = socket.get_seat_transform()
		else:
			if node.get_parent() != self:
				node.reparent(self, false)
			node.transform = Transform3D(Basis.IDENTITY, item.pos)
		if item.kind == "gun" and node.has_method("set_ammo"):
			node.set_ammo(int(item.ammo))


func _update_sockets() -> void:
	for socket_id in socket_nodes:
		var kind: String = StationLayout.SOCKETS[socket_id].kind
		var filled: bool = rules.socket_items.get(socket_id, "") != ""
		var locked := kind in ["vault", "armory"] and rules.phase < StationRules.Phase.EXTRACTION
		var active := (kind == "shuttle" and rules.shuttle_left >= 0.0 and filled) \
			or (kind == "pod" and rules.pod_left >= 0.0 and filled) \
			or (kind == "airlock_console" and rules.airlock_state == "warning")
		socket_nodes[socket_id].set_state(filled, locked, active)


func _apply_power_state() -> void:
	var state := "emergency"
	if rules.is_blackout():
		state = "blackout"
	elif rules.phase >= StationRules.Phase.EXTRACTION:
		state = "restored"
	if state == _power_state:
		return
	if _power_state == "emergency" and state == "restored":
		sfx.play("power_up")
		_fx("burst", ["power_wave", StationLayout.to_world(StationLayout.ROOMS.reactor.center)])
	elif state == "blackout":
		sfx.play("power_down")
		if local != null:
			var room := StationLayout.room_at(local.position)
			var at := StationLayout.to_world(StationLayout.ROOMS[room].center) if room != "" else local.position
			_fx("burst", ["blackout_flicker", at])
	_power_state = state
	StationBuilder.set_power_state(station, state)
	sfx.set_ambience(state)
	for id in avatars:
		var avatar: CrewMember = avatars[id]
		avatar.flashlight.visible = state != "restored"
		avatar.name_tag.visible = state != "blackout" and not avatar.is_local
