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
	var ids := Net.roster.keys()
	ids.sort()
	for index in range(ids.size()):
		var id: int = ids[index]
		var entry: Dictionary = Net.roster[id]
		var avatar := CrewMember.new()
		avatar.setup(id, id == my_id, entry.name, entry.color, StationLayout.spawn_point(index, ids.size()))
		add_child(avatar)
		avatars[id] = avatar
		avatar.footstep.connect(func(at: Vector3):
			sfx.play("footstep_%d" % (randi() % 3 + 1), at, -10.0 if id == my_id else -6.0))
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
	if action == "shove":
		hud.mark_shove_used(rules, my_id)
	Net.request(action)


# --- Host side ---------------------------------------------------------------

func host_pose(id: int, pos: Vector3, yaw: float, moving: float) -> void:
	rules.set_pose(id, pos, yaw)
	_moving[id] = moving


func host_request(id: int, action: String) -> void:
	match action:
		"interact":
			_dirty = rules.request_interact(id) or _dirty
		"shove":
			rules.request_shove(id)
			_dirty = true
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
		if event.type == "result":
			_dirty = true
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
				"pod":
					sfx.start_alarm()
				"abort":
					sfx.stop_alarm()
					sfx.play("abort")
				"shuttle":
					sfx.play("shuttle_launch_start")
				"info":
					if str(event.text).begins_with("Power cell"):
						sfx.play("insert_cell")
		"shoved":
			var target := int(event.target)
			if avatars.has(target):
				sfx.play("shove", avatars[target].global_position)
			if target == my_id and local != null:
				local.knockback(event.dir)


func _remove_avatar(id: int) -> void:
	if avatars.has(id):
		var avatar: CrewMember = avatars[id]
		for item_id in item_nodes:
			var node: Node3D = item_nodes[item_id]
			if node.get_parent() == avatar.carry_point:
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
	if local != null:
		local.speed_factor = rules.speed_factor(my_id)
		var me: Dictionary = rules.players.get(my_id, {})
		local.stunned = float(me.get("stunned_until", 0.0)) > rules.elapsed
		if not host:
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
	hud.update_state(rules, rules.available_action(my_id), my_id)


func _update_audio() -> void:
	for item_id in rules.items:
		var holder: int = rules.items[item_id].holder
		var before: int = _holders.get(item_id, 0)
		if holder != before:
			if holder != 0:
				sfx.play("pickup", rules.item_position(item_id))
			elif rules.items[item_id].socket == "":
				sfx.play("drop", rules.items[item_id].pos)
			_holders[item_id] = holder
	var left := rules.pod_left if rules.pod_left >= 0.0 else rules.shuttle_left
	if left >= 0.0 and left <= 10.0 and rules.phase != StationRules.Phase.RESULT:
		var tick := int(ceil(left))
		if tick != _last_tick:
			_last_tick = tick
			sfx.play("countdown_tick", null, -4.0)
	else:
		_last_tick = -1
	if rules.pod_left < 0.0:
		sfx.stop_alarm()
	if rules.phase == StationRules.Phase.RESULT and not _result_played:
		_result_played = true
		sfx.stop_alarm()
		if rules.winner == StationRules.CREW:
			sfx.play("win_crew")
		elif rules.winner == StationRules.INFILTRATOR:
			sfx.play("win_infiltrator")
		else:
			sfx.play("power_down")


func _update_items() -> void:
	for item_id in rules.items:
		if not item_nodes.has(item_id):
			continue
		var node: Node3D = item_nodes[item_id]
		var item: Dictionary = rules.items[item_id]
		var holder: int = item.holder
		if holder != 0 and avatars.has(holder):
			var point: Node3D = avatars[holder].carry_point
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


func _update_sockets() -> void:
	for socket_id in socket_nodes:
		var kind: String = StationLayout.SOCKETS[socket_id].kind
		var filled: bool = rules.socket_items.get(socket_id, "") != ""
		var locked := kind == "vault" and rules.phase < StationRules.Phase.EXTRACTION
		var active := (kind == "shuttle" and rules.shuttle_left >= 0.0 and filled) \
			or (kind == "pod" and rules.pod_left >= 0.0 and filled)
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
	elif state == "blackout":
		sfx.play("power_down")
	_power_state = state
	StationBuilder.set_power_state(station, state)
	sfx.set_ambience(state)
	for id in avatars:
		var avatar: CrewMember = avatars[id]
		avatar.flashlight.visible = state != "restored"
		avatar.name_tag.visible = state != "blackout" and not avatar.is_local
