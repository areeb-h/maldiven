class_name StationPhysics
extends Node3D
## The physical layer of a round: loose items, pushable props, player proxies,
## airlock decompression and replication. One per StationWorld.
##
## Authority: the host simulates every body and writes loose item poses into the
## rules (so pickup ranges and snapshots stay right). Clients only render the
## host's results from a 100 ms interpolation buffer; nothing a client simulates
## locally ever reaches gameplay state. See scripts/physics/README.md.

const STREAM_HZ := 25.0
const KEYFRAME_INTERVAL := 3.0
const MAX_BODIES_PER_PACKET := 40
const COOL_SPEED := 1.6  # a thrown item below this stops being dangerous
const HIT_MARGIN := 0.12  # m of slack on the item vs capsule hit test
const ITEM_HIT_RADIUS := 0.2
const BUMP_MOMENTUM := 45.0  # kg m/s of a prop that knocks a player back
const KICK_SPEED := 0.9  # m/s a walking player nudges a resting item with
const SHOVE_REACH := 2.5
const SHOVE_SPEED := 3.4  # m/s a shove gives a prop right in front
const AIRLOCK_PULL := 9.5  # m/s^2 on bodies at full strength
const PLAYER_PULL := 2.8  # m/s of drift a player has to fight at full strength
const VENT_SPEED := 13.0
const PROP_DRIFT := 2.6  # s an ejected prop drifts before it respawns
const UNREACHABLE_SECONDS := 4.0
const KEEP_CLEAR_INTERVAL := 0.25
const INTERP_LEAD := NetBody.INTERP_DELAY + 0.025  # client buffer + half a pose interval

var world: Node  # StationWorld (duck-typed so tests can use a stub)
var rules: StationRules
var authority := false
var bodies: Array[NetBody] = []  # index = net id
var item_bodies := {}  # item id -> NetBody
var props: Array[NetBody] = []
var proxies := {}  # peer id -> PlayerProxy
var clock := 0.0  # host physics time (seconds since the round node started)
var _validated := false
var _send_accum := 0.0
var _keyframe_timer := KEYFRAME_INTERVAL
var _keep_clear_timer := 0.0
var _clock_offset := 0.0
var _clock_ready := false
var _bump_cooldown := {}  # "net:peer" -> clock time
var _activated_at := {}  # item id -> clock
var _space: PhysicsDirectSpaceState3D
## Optional host hooks (StationWorld wires these): func(event: Dictionary).
var emit_event := Callable()
## Optional: func(peer_id: int) -> float round trip seconds.
var peer_rtt := Callable()
## Optional: func(bytes: PackedByteArray, reliable: bool, to_peer: int) (0 = everyone).
var send_stream := Callable()


## `item_visuals`: item id -> the item's visual node, so colliders fit the art.
func setup(p_world: Node, p_rules: StationRules, p_authority: bool, item_visuals := {}) -> void:
	name = "Physics"
	world = p_world
	rules = p_rules
	authority = p_authority
	for item_id in StationLayout.ITEMS:
		var kind: String = StationLayout.ITEMS[item_id].kind
		var desc: Dictionary = PropFactory.ITEM_SPECS.get(kind, PropFactory.ITEM_SPECS.cell).duplicate()
		desc["kind"] = kind
		var bounds := visual_aabb(item_visuals[item_id]) if item_visuals.has(item_id) else AABB()
		desc["shapes"] = PropFactory.item_shapes(kind, bounds)
		var body := NetBody.new()
		body.name = "Loose_" + item_id
		body.item_id = item_id
		body.configure(bodies.size(), desc, authority)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(body)
		item_bodies[item_id] = body
		bodies.append(body)
	for index in range(PropLayout.PROPS.size()):
		var entry: Array = PropLayout.PROPS[index]
		var body := NetBody.new()
		body.is_prop = true
		body.name = "Prop%02d_%s" % [index, entry[0]]
		body.configure(bodies.size(), PropFactory.describe(entry[0], PropLayout.accent(entry[3])), authority)
		body.home = Transform3D(Basis(Vector3.UP, entry[2]), StationLayout.to_world(entry[1], 0.004))
		add_child(body)
		body.global_transform = body.home
		body.sleeping = true
		body.impact.connect(_on_impact.bind(body))
		props.append(body)
		bodies.append(body)
	for body in item_bodies.values():
		body.impact.connect(_on_impact.bind(body))


## Local-space bounds of a visual's meshes (skipping VFX attachments).
static func visual_aabb(node: Node3D, xform := Transform3D.IDENTITY) -> AABB:
	var out := AABB()
	var first := true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out = xform * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for child in node.get_children():
		if not child is Node3D or child.has_meta("vfx_skip"):
			continue
		var sub := visual_aabb(child, xform * (child as Node3D).transform)
		if sub.size == Vector3.ZERO:
			continue
		out = sub if first else out.merge(sub)
		first = false
	return out


func _ready() -> void:
	_space = get_world_3d().direct_space_state if is_inside_tree() else null


# --- shared queries ----------------------------------------------------------------------

## 0..1 decompression strength right now (grows through the warning).
func airlock_strength() -> float:
	if rules == null or rules.airlock_state != "warning":
		return 0.0
	var s := clampf(1.0 - rules.airlock_left / StationRules.AIRLOCK_WARNING, 0.0, 1.0)
	return s * s * (3.0 - 2.0 * s) * 0.35 + s * s * 0.65


## Where the decompression pulls: the outer hull door.
static func airlock_door() -> Vector3:
	var r := StationLayout.room_rect("airlock")
	return Vector3(r.position.x - 0.3, 1.1, r.get_center().y)


## 0..1 falloff of the decompression field at `pos` (chamber, corridor, then a
## shrinking cone into Commons in front of the corridor).
static func airlock_falloff(pos: Vector3) -> float:
	var flat := Vector2(pos.x, pos.z)
	if StationLayout.room_rect("airlock").grow(0.05).has_point(flat):
		return 1.0
	if StationLayout.corridor_rect("commons-airlock").grow(0.05).has_point(flat):
		return 0.78
	var mouth := StationLayout.corridor_rect("commons-airlock").end.x
	var reach := 3.6
	var into := pos.x - mouth
	if into < 0.0 or into > reach or absf(pos.z - StationLayout.corridor_rect("commons-airlock").get_center().y) > 3.0:
		return 0.0
	var side := 1.0 - absf(pos.z) / 3.0
	return 0.5 * (1.0 - into / reach) * side


## Flat unit direction of the pull at `pos`.
static func airlock_dir(pos: Vector3) -> Vector3:
	var door := airlock_door()
	var to := Vector3(door.x - pos.x, 0.0, (door.z - pos.z) * 0.6)
	return to.normalized() if to.length() > 0.01 else Vector3.LEFT


## Velocity bias for a player at `pos` (their own client applies it).
func airlock_push(pos: Vector3) -> Vector3:
	var s := airlock_strength()
	if s <= 0.0:
		return Vector3.ZERO
	return airlock_dir(pos) * PLAYER_PULL * s * airlock_falloff(pos)


# --- host --------------------------------------------------------------------------------

func on_pose(peer_id: int, pos: Vector3, vel: Vector3) -> void:
	if proxies.has(peer_id):
		proxies[peer_id].report(pos, vel)


## Rules events the physics reacts to (host).
func on_event(event: Dictionary) -> void:
	if not authority:
		return
	match event.get("type", ""):
		"swing":
			_shove_bodies(event.at, event.dir)
		"airlock":
			if event.state == "venting":
				_vent()


func _physics_process(delta: float) -> void:
	if world == null or rules == null:
		return
	_space = get_world_3d().direct_space_state
	if not _validated:
		_validated = true
		_validate_props()
	if not authority:
		return
	clock += delta
	_sync_items()
	_step_proxies(delta)
	_tick_bodies(delta)
	_send_accum += delta
	if _send_accum >= 1.0 / STREAM_HZ:
		_send_accum = fmod(_send_accum, 1.0 / STREAM_HZ)
		_send_stream(false, 0)
	_keyframe_timer -= delta
	if _keyframe_timer <= 0.0:
		_keyframe_timer = KEYFRAME_INTERVAL
		_send_stream(true, 0, true)


## Props that land inside static geometry (if the station layout changes) are
## nudged to the nearest clear spot, or left out. Deterministic on every peer.
func _validate_props() -> void:
	for body in props:
		var spot: Variant = _clear_spot(body, body.home)
		if spot == null:
			push_warning("StationPhysics: no clear spot for %s, leaving it out" % body.name)
			body.process_mode = Node.PROCESS_MODE_DISABLED
			body.visible = false
			continue
		body.home = spot
		body.global_transform = spot
		body.sleeping = true


func _clear_spot(body: NetBody, xform: Transform3D) -> Variant:
	if _space == null:
		return xform
	for ring in range(7):
		var steps := 1 if ring == 0 else 8
		for k in range(steps):
			var ang := TAU * float(k) / float(steps)
			var offset := Vector3(cos(ang), 0.0, sin(ang)) * 0.25 * float(ring)
			var candidate := Transform3D(xform.basis, xform.origin + offset)
			if not _overlaps_world(body, candidate):
				return candidate
	return null


## True if the body's shapes at `xform` (lifted 3 cm, so resting on the floor
## doesn't count) overlap static geometry.
func _overlaps_world(body: NetBody, xform: Transform3D) -> bool:
	var lifted := xform.translated(Vector3(0, 0.03, 0))
	for child in body.get_children():
		if not child is CollisionShape3D:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = (child as CollisionShape3D).shape
		query.transform = lifted * (child as CollisionShape3D).transform
		query.collision_mask = PhysicsLayers.WORLD
		query.margin = 0.0
		if not _space.intersect_shape(query, 1).is_empty():
			return true
	return false


func _sync_items() -> void:
	for item_id in rules.items:
		if not item_bodies.has(item_id):
			continue
		var item: Dictionary = rules.items[item_id]
		var body: NetBody = item_bodies[item_id]
		var loose: bool = int(item.holder) == 0 and item.socket == ""
		if loose:
			if body.process_mode == Node.PROCESS_MODE_DISABLED or body.epoch != int(item.epoch):
				_activate_item(item_id, body, item)
		elif body.process_mode != Node.PROCESS_MODE_DISABLED:
			body.process_mode = Node.PROCESS_MODE_DISABLED
			body.set_hot(0)


func _activate_item(item_id: String, body: NetBody, item: Dictionary) -> void:
	body.process_mode = Node.PROCESS_MODE_INHERIT
	body.restore()
	body.epoch = int(item.epoch)
	var flight: Dictionary = item.flight
	var thrower := int(flight.get("by", 0)) if not flight.is_empty() else 0
	body.set_hot(thrower)
	body.place(Transform3D(Basis(item.rot), item.pos), item.vel)
	if not item.vel.is_zero_approx():
		# Spin: thrown items tumble end over end, dropped ones wobble.
		var side: Vector3 = Vector3(item.vel.x, 0, item.vel.z).cross(Vector3.UP)
		body.angular_velocity = side.normalized() * (-5.0 if thrower != 0 else -1.5) if side.length() > 0.01 else Vector3.ZERO
	if thrower != 0 and proxies.has(thrower):
		body.ignore_for(proxies[thrower], 0.3, clock)
	_activated_at[item_id] = clock


func _step_proxies(delta: float) -> void:
	for id in proxies.keys():
		if not rules.players.has(id):
			proxies[id].queue_free()
			proxies.erase(id)
	for id in rules.players:
		var p: Dictionary = rules.players[id]
		if not proxies.has(id):
			var proxy := PlayerProxy.new()
			proxy.name = "Proxy%d" % id
			proxy.peer_id = id
			add_child(proxy)
			proxy.global_position = p.pos
			proxy.report(p.pos, Vector3.ZERO)
			proxies[id] = proxy
		var proxy: PlayerProxy = proxies[id]
		var mode := "off"
		if int(p.carried_by) == 0:
			if p.state == StationRules.OK:
				mode = "standing"
			elif p.state == StationRules.DOWNED:
				mode = "lying"
		proxy.set_mode(mode)
		var lead := 0.0
		var me: Variant = world.get("my_id")
		var local: Variant = world.get("local")
		if me != null and int(me) == id and local is Node3D:
			proxy.report((local as Node3D).global_position, (local as CharacterBody3D).velocity if local is CharacterBody3D else Vector3.ZERO)
		else:
			lead = INTERP_LEAD + (peer_rtt.call(id) if peer_rtt.is_valid() else 0.0)
		if mode == "lying":
			proxy.report(p.pos, Vector3.ZERO)
		proxy.step(delta, minf(lead, PlayerProxy.MAX_LEAD), float(p.yaw), _space)


func _tick_bodies(delta: float) -> void:
	_keep_clear_timer -= delta
	var keep_clear := _keep_clear_timer <= 0.0
	if keep_clear:
		_keep_clear_timer = KEEP_CLEAR_INTERVAL
	var pull := airlock_strength()
	for body in bodies:
		if body.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		body.tick_exceptions(clock)
		body.host_track(delta)
		var asleep := body.sleeping
		if asleep and not body.was_sleeping:
			body.settle_sends = 6  # make sure the rest pose reaches every client
		if not asleep:
			body.dirty = true
		body.was_sleeping = asleep
		var pos := body.global_position
		if body.is_ejected():
			if body.is_prop and body.spaced_until >= 0.0 and clock >= body.spaced_until:
				body.restore()
				body.place(body.home)
		else:
			if pull > 0.0:
				var falloff := airlock_falloff(pos)
				if falloff > 0.0:
					body.sleeping = false
					body.apply_central_force(airlock_dir(pos) * body.mass * AIRLOCK_PULL * pull * falloff + Vector3.UP * body.mass * 1.2 * pull * falloff)
			_check_lost(body, delta)
			if body.is_prop:
				_check_bump(body)
				if keep_clear and (asleep or body.linear_velocity.length() < 0.3):
					_keep_clear(body)
			else:
				_tick_item(body)
		body.prev_velocity = body.linear_velocity
		if not body.is_prop and rules.items.has(body.item_id):
			var item: Dictionary = rules.items[body.item_id]
			item.pos = body.global_position
			item.rot = body.global_basis.get_rotation_quaternion()
			item.vel = body.linear_velocity
			item.moving = not body.sleeping


func _tick_item(body: NetBody) -> void:
	var item: Dictionary = rules.items[body.item_id]
	if item.flight.is_empty():
		if body.hot_by != 0:
			body.set_hot(0)
		_kick_resting_item(body)
		return
	var speed := body.prev_velocity.length()
	var age: float = clock - float(_activated_at.get(body.item_id, clock))
	if age > 0.2 and body.linear_velocity.length() < COOL_SPEED:
		rules.cool_item(body.item_id)
		body.set_hot(0)
		return
	if speed < StationRules.THROW_HIT_SPEED:
		return
	var centre := body.global_transform * Vector3(0, 0.3, 0)
	for id in proxies:
		var proxy: PlayerProxy = proxies[id]
		if proxy.mode != "standing" or id == body.hot_by:
			continue
		var seg := proxy.capsule_segment()
		var closest := Geometry3D.get_closest_point_to_segment(centre, seg[0], seg[1])
		var gap := centre.distance_to(closest) - float(seg[2]) - ITEM_HIT_RADIUS
		if gap > HIT_MARGIN or body.prev_velocity.dot(closest - centre) <= 0.0:
			continue
		if rules.item_hit(body.item_id, id, body.prev_velocity):
			body.set_hot(0)
			return


## A player walking into a resting item nudges it along instead of launching it.
func _kick_resting_item(body: NetBody) -> void:
	var centre := body.global_position + Vector3(0, 0.25, 0)
	for id in proxies:
		var proxy: PlayerProxy = proxies[id]
		if proxy.mode != "standing" or proxy.collision_layer == 0:
			continue
		var offset := Vector3(centre.x - proxy.global_position.x, 0.0, centre.z - proxy.global_position.z)
		var reach := PlayerProxy.RADIUS + 0.2
		if offset.length() >= reach or centre.y > proxy.global_position.y + 1.9:
			continue
		var dir := offset.normalized() if offset.length() > 0.01 else Vector3.FORWARD
		var along := body.linear_velocity.dot(dir)
		var want := KICK_SPEED * (1.0 - offset.length() / reach) + 0.35
		if along < want:
			body.sleeping = false
			body.apply_central_impulse((dir * (want - along) + Vector3.UP * 0.25) * body.mass)


## A fast, heavy prop that slams into a player knocks them back (host decides,
## the target's client applies it).
func _check_bump(body: NetBody) -> void:
	var speed := body.prev_velocity.length()
	if speed * body.mass < BUMP_MOMENTUM or speed < 3.0:
		return
	var centre := body.global_position + Vector3(0, 0.4, 0)
	for id in proxies:
		var proxy: PlayerProxy = proxies[id]
		if proxy.mode != "standing":
			continue
		var seg := proxy.capsule_segment()
		var closest := Geometry3D.get_closest_point_to_segment(centre, seg[0], seg[1])
		if centre.distance_to(closest) > float(seg[2]) + body.bound_radius + 0.1:
			continue
		var key := "%d:%d" % [body.net_id, id]
		if clock < float(_bump_cooldown.get(key, -1.0)):
			continue
		_bump_cooldown[key] = clock + 0.8
		var dir := Vector3(body.prev_velocity.x, 0, body.prev_velocity.z).normalized()
		var strength := clampf(speed * body.mass / 140.0, 0.25, 0.8)
		if emit_event.is_valid():
			emit_event.call({"type": "bumped", "target": id, "dir": dir, "strength": strength})


## Props at rest never block a doorway or a socket's approach point.
func _keep_clear(body: NetBody) -> void:
	var hit := PropLayout.intrusion(Vector2(body.global_position.x, body.global_position.z), body.bound_radius * 0.8, true)
	if hit.is_empty() or float(hit.depth) < 0.03:
		return
	var dir := Vector3(hit.dir.x, 0.0, hit.dir.y)
	body.sleeping = false
	body.apply_central_impulse(dir * body.mass * minf(0.7, 0.3 + float(hit.depth)))


## Fell out of the world, or came to rest somewhere nobody can reach: return it.
func _check_lost(body: NetBody, delta: float) -> void:
	var pos := body.global_position
	var out := pos.y < -4.0 or pos.y > 12.0 or pos.x < -40.0 or pos.x > 100.0 or absf(pos.z) > 50.0
	if not out and body.sleeping:
		var reachable := StationLayout.is_walkable(pos) and pos.y < 2.4
		body.idle_time = 0.0 if reachable else body.idle_time + delta
		out = body.idle_time > UNREACHABLE_SECONDS
	if not out:
		return
	if body.is_prop:
		body.restore()
		body.place(body.home)
	elif rules.items.has(body.item_id) and rules.items[body.item_id].lost < 0.0:
		rules.respawn_item(body.item_id)


## Shoves knock props and loose items around in a cone in front of the shover.
func _shove_bodies(at: Vector3, dir: Vector3) -> void:
	var forward := Vector3(dir.x, 0, dir.z).normalized()
	for body in bodies:
		if body.process_mode == Node.PROCESS_MODE_DISABLED or body.is_ejected():
			continue
		var offset := body.global_position - at
		offset.y = 0.0
		var distance := offset.length()
		if distance > SHOVE_REACH + body.bound_radius * 0.5:
			continue
		if distance > 0.5 and forward.dot(offset.normalized()) < 0.4:
			continue
		var falloff := clampf(1.0 - distance / (SHOVE_REACH + 0.6), 0.2, 1.0)
		var push := (forward * 0.8 + offset.normalized() * 0.2).normalized() if distance > 0.05 else forward
		body.sleeping = false
		# Above the centre of mass: tall props topple, low ones skid and spin.
		var lever := Vector3(0, float(body.spec.get("height", 0.4)) * 0.7, 0)
		body.apply_impulse((push * SHOVE_SPEED * falloff + Vector3.UP * 1.1 * falloff) * body.mass, lever)


## The outer door opens: everything in the chamber is blown into space.
func _vent() -> void:
	var door := airlock_door()
	var chamber := StationLayout.room_rect("airlock").grow(0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(clock * 1000.0)
	for body in bodies:
		if body.process_mode == Node.PROCESS_MODE_DISABLED or body.is_ejected():
			continue
		var pos := body.global_position
		if not chamber.has_point(Vector2(pos.x, pos.z)):
			continue
		var aim := Vector3(door.x - 3.0, door.y + rng.randf_range(-0.2, 0.6), door.z + rng.randf_range(-0.5, 0.5)) - pos
		var spin := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(5.0, 10.0)
		body.eject(aim.normalized() * VENT_SPEED * rng.randf_range(0.9, 1.1), spin)
		body.spaced_until = clock + PROP_DRIFT
		body.dirty = true


func _on_impact(at: Vector3, strength: float, body: NetBody) -> void:
	if world != null and world.has_method("physics_impact"):
		world.physics_impact(at, strength, body.is_prop, body.kind)


# --- replication -------------------------------------------------------------------------

## Host: stream awake bodies (unreliable) or a keyframe of everything changed
## since the last one (reliable). `everything` sends every active body.
func _send_stream(reliable: bool, to_peer: int, keyframe := false, everything := false) -> void:
	if not send_stream.is_valid():
		return
	var chosen: Array[NetBody] = []
	for body in bodies:
		if body.process_mode == Node.PROCESS_MODE_DISABLED or not body.visible:
			continue
		if everything:
			chosen.append(body)
		elif keyframe:
			if body.dirty and body.sleeping:
				chosen.append(body)
		elif not body.sleeping or body.settle_sends > 0 or body.teleported:
			chosen.append(body)
	var index := 0
	while index < chosen.size():
		var count := mini(MAX_BODIES_PER_PACKET, chosen.size() - index)
		var packet := NetCodec.begin(clock, count)
		for k in range(count):
			var body := chosen[index + k]
			var flags := 0
			if body.sleeping:
				flags |= NetCodec.FLAG_ASLEEP
			if body.teleported and not reliable:
				flags |= NetCodec.FLAG_TELEPORT
			NetCodec.write_body(packet, k, body.net_id, flags, maxi(body.epoch, 0), body.global_position, body.global_basis.get_rotation_quaternion())
			if reliable:
				body.dirty = false
			else:
				body.teleported = false
				if body.sleeping:
					body.settle_sends = maxi(0, body.settle_sends - 1)
		send_stream.call(packet, reliable, to_peer)
		index += count


## Host: a client's world is ready; send it every body's current state.
func send_full_state(to_peer: int) -> void:
	_send_stream(true, to_peer, true, true)


## Client: a stream or keyframe packet from the host.
func receive(data: PackedByteArray, reliable: bool) -> void:
	if authority:
		return
	var packet := NetCodec.read(data)
	if packet.is_empty():
		return
	var host_time: float = packet.time
	if not reliable:
		var offset := host_time - _local_time()
		if not _clock_ready or offset > _clock_offset:
			_clock_offset = offset
			_clock_ready = true
		else:
			_clock_offset -= 0.0004  # drift down slowly; any faster packet resets it
	for entry in packet.bodies:
		var net_id: int = entry[0]
		if net_id < 0 or net_id >= bodies.size():
			continue
		var body := bodies[net_id]
		if body.has_samples() and host_time <= body.last_sample_time():
			continue
		var flags: int = entry[1]
		var packet_epoch: int = entry[2]
		if body.epoch < 0 or packet_epoch != body.epoch % 32:
			body.epoch = _expand_epoch(body, packet_epoch)
			body.clear_samples()
			flags |= NetCodec.FLAG_TELEPORT
		body.push_sample(host_time, entry[3], entry[4], flags)
	if not _clock_ready and reliable:
		_clock_offset = host_time - _local_time()
		_clock_ready = true


func _expand_epoch(body: NetBody, small: int) -> int:
	if not body.is_prop and rules.items.has(body.item_id):
		var full := int(rules.items[body.item_id].get("epoch", 0))
		# The snapshot may be a little behind or ahead of the stream.
		for candidate in [full, full + 1, full - 1, full + 2]:
			if posmod(candidate, 32) == small:
				return candidate
	return small


func _local_time() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func host_time_now() -> float:
	return clock if authority else _local_time() + _clock_offset


## Client: activate/deactivate item replicas from the rules mirror and place
## every replica for this frame. Loose item positions go back into the mirror so
## the HUD's pickup prompts match what's on screen.
func _process(delta: float) -> void:
	if authority or rules == null:
		return
	var now := host_time_now()
	for item_id in item_bodies:
		var body: NetBody = item_bodies[item_id]
		var item: Dictionary = rules.items.get(item_id, {})
		var loose: bool = not item.is_empty() and int(item.holder) == 0 and item.socket == ""
		if not loose:
			if body.process_mode != Node.PROCESS_MODE_DISABLED:
				body.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		if body.process_mode == Node.PROCESS_MODE_DISABLED or body.epoch != int(item.epoch):
			body.process_mode = Node.PROCESS_MODE_INHERIT
			if body.epoch != int(item.epoch):
				# New loose period: start from where the host dropped it and drop
				# samples of the previous one.
				var keep := body.has_samples() and body.epoch % 32 == int(item.epoch) % 32
				body.epoch = int(item.epoch)
				if not keep:
					body.clear_samples()
					body.global_transform = Transform3D(Basis(item.rot), item.pos)
		if body.has_samples() and _clock_ready:
			body.render(now, delta)
		else:
			body.global_transform = Transform3D(Basis(item.rot), item.pos)
		item.pos = body.global_position
		item.rot = body.global_basis.get_rotation_quaternion()
	if not _clock_ready:
		return
	for body in props:
		if body.process_mode != Node.PROCESS_MODE_DISABLED and body.has_samples():
			body.render(now, delta)


## Host or client: the node that should parent a loose item's visual.
func item_body(item_id: String) -> NetBody:
	return item_bodies.get(item_id)


## Tests and tools: total awake simulated bodies.
func awake_count() -> int:
	var n := 0
	for body in bodies:
		if body.process_mode != Node.PROCESS_MODE_DISABLED and not body.sleeping:
			n += 1
	return n
