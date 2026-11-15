class_name PlayerProxy
extends AnimatableBody3D
## Host only: a kinematic stand-in for one player in the host's physics world.
## It pushes props (and catches thrown items) with the player's real velocity, so
## the host's simulation is what every client sees.
##
## Remote players are led by their measured round trip + the clients'
## interpolation delay: the host pushes a prop where the player will be by the
## time they see the result, so pushing feels immediate on the client.

const RADIUS := 0.42  # a hair bigger than the player capsule: props move before the capsule touches
const HEIGHT := 1.8
const LYING_RADIUS := 0.3
const MAX_LEAD := 0.28
const TELEPORT := 1.6  # m: a jump bigger than this is a teleport, never a push
const FOLLOW_RATE := 14.0

var peer_id := 0
var mode := "standing"  # standing / lying / off
var _shape: CollisionShape3D
var _standing := CapsuleShape3D.new()
var _lying := CapsuleShape3D.new()
var _pose_pos := Vector3.ZERO
var _pose_vel := Vector3.ZERO
var _pose_age := 0.0
var _ghost_until_clear := true  # collision off until the proxy no longer overlaps a body
var _ready_to_push := false


func _init() -> void:
	_standing.radius = RADIUS
	_standing.height = HEIGHT
	_lying.radius = LYING_RADIUS
	_lying.height = 1.7
	sync_to_physics = true
	collision_layer = 0
	collision_mask = 0
	_shape = CollisionShape3D.new()
	_shape.shape = _standing
	_shape.position.y = HEIGHT * 0.5
	add_child(_shape)


## Latest pose report for this player (host time is implicit: now).
func report(pos: Vector3, vel: Vector3) -> void:
	_pose_pos = pos
	_pose_vel = vel
	_pose_age = 0.0


## Called once per physics tick. lead: seconds to extrapolate ahead.
func step(delta: float, lead: float, yaw: float, space: PhysicsDirectSpaceState3D) -> void:
	_pose_age += delta
	if mode == "off":
		collision_layer = 0
		return
	var ahead := clampf(lead + _pose_age, 0.0, MAX_LEAD + 0.1)
	var flat_vel := Vector3(_pose_vel.x, 0.0, _pose_vel.z)
	var target := _pose_pos + flat_vel * ahead if mode == "standing" else _pose_pos
	var gap := target.distance_to(global_position)
	if gap > TELEPORT or not _ready_to_push:
		collision_layer = 0
		global_position = target
		_ghost_until_clear = true
		_ready_to_push = true
	else:
		# Feed-forward the reported velocity, then ease out the remaining error:
		# no steady-state lag, no velocity spikes when a late pose lands.
		var predicted := global_position + (flat_vel * delta if mode == "standing" else Vector3.ZERO)
		global_position = predicted.lerp(target, 1.0 - exp(-delta * FOLLOW_RATE))
	if mode == "lying":
		global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI / 2.0)
		_shape.position = Vector3(0, LYING_RADIUS, 0)
	else:
		global_basis = Basis.IDENTITY
		_shape.position = Vector3(0, HEIGHT * 0.5, 0)
	if _ghost_until_clear:
		if _overlaps(space):
			collision_layer = 0
			return
		_ghost_until_clear = false
	collision_layer = PhysicsLayers.PROXY


func set_mode(next: String) -> void:
	if next == mode:
		return
	mode = next
	_shape.shape = _lying if next == "lying" else _standing
	# A new stance can start inside something: re-enable only once clear.
	_ghost_until_clear = true


func capsule_segment() -> Array:
	## [bottom, top, radius] of the capsule's inner segment in world space.
	if mode == "lying":
		var along := global_basis.y * (_lying.height * 0.5 - LYING_RADIUS)
		var centre := global_position + Vector3(0, LYING_RADIUS, 0)
		return [centre - along, centre + along, LYING_RADIUS]
	return [global_position + Vector3(0, RADIUS, 0), global_position + Vector3(0, HEIGHT - RADIUS, 0), RADIUS]


func _overlaps(space: PhysicsDirectSpaceState3D) -> bool:
	if space == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape.shape
	query.transform = global_transform * _shape.transform
	query.collision_mask = PhysicsLayers.PROP
	query.margin = 0.02
	return not space.intersect_shape(query, 1).is_empty()
