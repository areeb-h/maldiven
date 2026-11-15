class_name NetBody
extends RigidBody3D
## A replicated physics body: a loose item or a pushable prop.
##
## Host: a real dynamic RigidBody3D (continuous collision, sleeping on).
## Client: a frozen kinematic replica placed every rendered frame from a 100 ms
## interpolation buffer of host samples (props stay solid for the local player).

signal impact(at: Vector3, strength: float)

const INTERP_DELAY := 0.1  # s of buffering on clients
const MAX_SAMPLES := 12
const MAX_EXTRAPOLATE := 0.08  # s: bridge a lost packet, never more
const SNAP_DISTANCE := 4.0  # m between consecutive samples = a teleport
## Jolt has no rolling resistance: without some spin damping a cell or barrel
## on its side would roll across the deck forever.
const ROLL_DAMP := 1.1

var net_id := 0
var kind := ""
var item_id := ""  # "" for props
var is_prop := false
var authority := false
var epoch := -1  # host: the rules epoch this body was activated for; client: accepted epoch
var spec := {}
var home := Transform3D.IDENTITY  # props: where they respawn
var push_resist := 0.0  # 0..1 how much the prop slows a player pushing it
var bound_radius := 0.4

# Host bookkeeping.
var prev_velocity := Vector3.ZERO
var settle_sends := 0  # stream packets that still carry this body after it slept / teleported
var teleported := false
var dirty := true  # changed since the last reliable keyframe
var spaced_until := -1.0  # host physics time when an ejected prop respawns
var idle_time := 0.0  # seconds asleep somewhere unreachable
var clearing := Vector3.ZERO  # keep-clear slide direction while it rests in a doorway / on an approach point
var was_sleeping := true
var hot_by := 0  # thrower peer while an item is dangerous
var _exceptions := []  # [body, until]

# Client interpolation.
var _samples: Array = []  # [t, pos, rot, flags]
var _render_vel := Vector3.ZERO
var _render_prev := Vector3.ZERO
var _render_ready := false
var _impact_cooldown := 0.0


func configure(p_net_id: int, desc: Dictionary, p_authority: bool) -> void:
	net_id = p_net_id
	spec = desc
	kind = desc.kind
	authority = p_authority
	mass = desc.mass
	bound_radius = desc.get("radius", 0.4)
	push_resist = desc.get("push", 0.0)
	var surface := PhysicsMaterial.new()
	surface.friction = desc.friction
	surface.bounce = desc.bounce
	surface.rough = false
	physics_material_override = surface
	continuous_cd = true
	can_sleep = true
	linear_damp = desc.get("damp", 0.05)
	angular_damp = desc.get("spin_damp", ROLL_DAMP)
	for entry in desc.shapes:
		var cs := CollisionShape3D.new()
		cs.shape = entry[0]
		cs.transform = entry[1]
		add_child(cs)
	if desc.has("mesh"):
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = desc.mesh
		add_child(mi)
	if not authority:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		can_sleep = false
		continuous_cd = false
	_apply_layers(false)


## Collision setup by role and state.
func _apply_layers(hot: bool) -> void:
	if is_prop:
		collision_layer = PhysicsLayers.PROP
		collision_mask = PhysicsLayers.PROP_MASK if authority else 0
	else:
		# Client item replicas are visual only (the local player walks through items).
		collision_layer = PhysicsLayers.ITEM if authority else 0
		collision_mask = (PhysicsLayers.ITEM_HOT_MASK if hot else PhysicsLayers.ITEM_MASK) if authority else 0


func set_hot(by: int) -> void:
	hot_by = by
	_apply_layers(by != 0)


## Host: an ejected body flies straight through the airlock door (the door's
## collider always spans the opening) and drifts away weightless.
func eject(velocity: Vector3, spin: Vector3) -> void:
	collision_layer = 0
	collision_mask = 0
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.0
	sleeping = false
	linear_velocity = velocity
	angular_velocity = spin


## Host: back to normal collision after a respawn.
func restore() -> void:
	gravity_scale = 1.0
	linear_damp = spec.get("damp", 0.05)
	angular_damp = spec.get("spin_damp", ROLL_DAMP)
	spaced_until = -1.0
	_apply_layers(hot_by != 0)


func is_ejected() -> bool:
	return authority and collision_mask == 0 and collision_layer == 0 and gravity_scale == 0.0


## Host: teleport (respawn, activation) without streaking interpolation.
func place(xform: Transform3D, velocity := Vector3.ZERO) -> void:
	global_transform = xform
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	prev_velocity = velocity
	_render_vel = velocity
	_render_ready = false
	sleeping = velocity.length_squared() < 0.0001
	teleported = true
	settle_sends = 6
	dirty = true
	idle_time = 0.0


## Host: ignore collisions with `other` for `seconds` (a thrower's own proxy).
func ignore_for(other: PhysicsBody3D, seconds: float, now: float) -> void:
	add_collision_exception_with(other)
	_exceptions.append([other, now + seconds])


func tick_exceptions(now: float) -> void:
	for i in range(_exceptions.size() - 1, -1, -1):
		if now >= float(_exceptions[i][1]):
			var other = _exceptions[i][0]
			if is_instance_valid(other):
				remove_collision_exception_with(other)
			_exceptions.remove_at(i)


# --- client replica ----------------------------------------------------------------------

## A host sample. flags: bit0 asleep, bit1 teleport.
func push_sample(t: float, pos: Vector3, rot: Quaternion, flags: int) -> void:
	var teleport := (flags & 2) != 0
	if not _samples.is_empty():
		var last: Array = _samples[_samples.size() - 1]
		if t <= float(last[0]):
			return  # duplicate or stale (settle bursts repeat samples)
		if (last[1] as Vector3).distance_to(pos) > SNAP_DISTANCE:
			teleport = true
	if teleport:
		_samples.clear()
		_render_ready = false
	_samples.append([t, pos, rot, flags])
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


func clear_samples() -> void:
	_samples.clear()
	_render_ready = false


func has_samples() -> bool:
	return not _samples.is_empty()


func last_sample_time() -> float:
	return float(_samples[_samples.size() - 1][0]) if not _samples.is_empty() else -INF


## The interpolated host transform at host time `t`.
func sample_at(t: float) -> Transform3D:
	var count := _samples.size()
	if count == 0:
		return global_transform
	var first: Array = _samples[0]
	if t <= float(first[0]):
		return Transform3D(Basis(first[2]), first[1])
	for i in range(count - 1):
		var a: Array = _samples[i]
		var b: Array = _samples[i + 1]
		if t < float(b[0]):
			var span := maxf(float(b[0]) - float(a[0]), 0.0001)
			var k := clampf((t - float(a[0])) / span, 0.0, 1.0)
			var rot: Quaternion = (a[2] as Quaternion).slerp(b[2], k)
			return Transform3D(Basis(rot), (a[1] as Vector3).lerp(b[1], k))
	var last: Array = _samples[count - 1]
	var pos: Vector3 = last[1]
	if (int(last[3]) & 1) == 0 and count >= 2:
		# Still moving and the next packet is late: extrapolate a hair.
		var prev: Array = _samples[count - 2]
		var dt := maxf(float(last[0]) - float(prev[0]), 0.001)
		var vel := ((last[1] as Vector3) - (prev[1] as Vector3)) / dt
		pos += vel * clampf(t - float(last[0]), 0.0, MAX_EXTRAPOLATE)
	return Transform3D(Basis(last[2]), pos)


## Client: place the replica for this frame. Returns the transform used.
func render(host_time: float, delta: float) -> void:
	if _samples.is_empty():
		return
	var xform := sample_at(host_time - INTERP_DELAY)
	if _render_ready and delta > 0.0:
		var vel := (xform.origin - _render_prev) / delta
		_detect_impact(vel, delta)
		_render_vel = vel
	_render_prev = xform.origin
	_render_ready = true
	global_transform = xform


## Host and client: a sharp drop in speed is an impact (sound / dust).
func _detect_impact(vel: Vector3, delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	var change := (_render_vel - vel).length()
	if change > 2.6 and _impact_cooldown <= 0.0 and _render_vel.length() > 1.8:
		_impact_cooldown = 0.18
		impact.emit(global_position, clampf(change / 8.0, 0.0, 1.0))


## Host: same impact detection from the simulated velocity.
func host_track(delta: float) -> void:
	if _render_ready:
		_detect_impact(linear_velocity, delta)
	_render_vel = linear_velocity
	_render_ready = true
