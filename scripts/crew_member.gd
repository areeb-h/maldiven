class_name CrewMember
extends CharacterBody3D

signal footstep(at: Vector3)

## A crew avatar. The local one reads input and owns a camera; remote ones are
## smoothed puppets driven by host pose broadcasts but still block movement.

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2

var peer_id := 0
var is_local := false
var display_name := ""
var color := Color.WHITE
var speed_factor := 1.0
var stunned := false

var move_input := Vector2.ZERO
var run_toggle := true
var yaw := 0.0
var pitch := -0.55
var jump_pending := false
var _jump_buffer := 0.0
var _coyote := 0.0
var _spawn := Vector3.ZERO

var visual: Node3D
var pivot: Node3D
var camera: Camera3D
var name_tag: Label3D
var carry_point: Node3D
var flashlight: SpotLight3D
var _limbs: Array[Node3D] = []
var _stride := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _remote_moving := 0.0
var _facing := 0.0


func setup(id: int, local: bool, player_name: String, suit: Color, spawn_at: Vector3) -> void:
	peer_id = id
	is_local = local
	display_name = player_name
	color = suit
	_spawn = spawn_at
	name = "Crew%d" % id


func _ready() -> void:
	floor_snap_length = 0.35
	collision_layer = 2 if not is_local else 4
	collision_mask = 1 | 2
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	visual = Props.make_crew_visual(color)
	visual.rotation.y = PI
	add_child(visual)
	for limb_name in ["LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
		var limb := visual.find_child(limb_name, true, false) as Node3D
		if limb != null:
			_limbs.append(limb)
	carry_point = Node3D.new()
	carry_point.position = Vector3(0, 0.95, 0.55)
	add_child(carry_point)
	name_tag = Label3D.new()
	name_tag.text = display_name
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = false
	name_tag.font_size = 44
	name_tag.outline_size = 10
	name_tag.modulate = color.lightened(0.35)
	name_tag.position.y = 2.25
	name_tag.pixel_size = 0.006
	name_tag.visible = not is_local
	add_child(name_tag)
	flashlight = Props.make_flashlight()
	flashlight.position = Vector3(0, 1.45, 0.3)
	flashlight.visible = false
	add_child(flashlight)
	position = _spawn
	_target_pos = _spawn
	if is_local:
		pivot = Node3D.new()
		pivot.position.y = 1.6
		add_child(pivot)
		var arm := SpringArm3D.new()
		arm.spring_length = 6.5
		arm.margin = 0.25
		var camera_shape := SphereShape3D.new()
		camera_shape.radius = 0.25
		arm.shape = camera_shape
		arm.collision_mask = 1
		arm.add_excluded_object(get_rid())
		pivot.add_child(arm)
		camera = Camera3D.new()
		camera.current = true
		camera.fov = 70
		camera.far = 1500.0
		arm.add_child(camera)


func look(delta: Vector2) -> void:
	yaw -= delta.x * 0.005
	pitch = clampf(pitch - delta.y * 0.004, -1.25, 0.15)


func clear_input() -> void:
	move_input = Vector2.ZERO
	jump_pending = false
	_jump_buffer = 0.0


## Remote puppets: latest host pose.
func set_remote_pose(pos: Vector3, facing: float, moving: float) -> void:
	if is_local:
		return
	if pos.distance_to(_target_pos) > 6.0:
		position = pos  # teleport/respawn: snap instead of sliding through walls
	_target_pos = pos
	_target_yaw = facing
	_remote_moving = moving


func knockback(direction: Vector3) -> void:
	if is_local:
		velocity = direction.normalized() * 9.5 + Vector3(0, 3.5, 0)


func facing_yaw() -> float:
	return _facing


func moving_amount() -> float:
	return Vector2(velocity.x, velocity.z).length() if is_local else _remote_moving


func respawn() -> void:
	position = _spawn
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if is_local:
		_local_physics(delta)
	else:
		position = position.lerp(_target_pos, minf(1.0, delta * 12.0))
		_facing = lerp_angle(_facing, _target_yaw, minf(1.0, delta * 12.0))
		visual.rotation.y = _facing + PI
	_animate(delta, moving_amount())


func _local_physics(delta: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	var keyboard := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var axis := move_input if move_input.length() > 0.05 else keyboard.limit_length()
	if stunned:
		axis = Vector2.ZERO
	var direction := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	var running := axis.length() > 0.8 or Input.is_physical_key_pressed(KEY_SHIFT)
	if keyboard.length() > 0.05 and not Input.is_physical_key_pressed(KEY_SHIFT):
		running = false
	var speed := (RUN_SPEED if running else WALK_SPEED) * speed_factor
	var accel := 6.0 if stunned else 24.0
	velocity.x = move_toward(velocity.x, direction.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, accel * delta)
	_coyote = 0.12 if is_on_floor() else maxf(0.0, _coyote - delta)
	_jump_buffer = 0.14 if jump_pending else maxf(0.0, _jump_buffer - delta)
	jump_pending = false
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and not stunned:
		velocity.y = 6.5
		_jump_buffer = 0.0
		_coyote = 0.0
	move_and_slide()
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > 0.2 and not stunned:
		_facing = lerp_angle(_facing, atan2(velocity.x, velocity.z), minf(1.0, delta * 12.0))
	visual.rotation.y = _facing + PI
	if position.y < -6.0 or not StationLayout.is_walkable(position) and position.y < -0.5:
		respawn()


func _animate(delta: float, horizontal_speed: float) -> void:
	var before := sin(_stride)
	_stride += horizontal_speed * delta * 2.4
	if horizontal_speed > 1.0 and signf(before) != signf(sin(_stride)):
		footstep.emit(global_position)
	var amount := minf(horizontal_speed / RUN_SPEED, 1.0)
	var swing := sin(_stride) * amount * 0.55
	for index in range(_limbs.size()):
		var limb := _limbs[index]
		if not is_instance_valid(limb):
			continue
		var target := swing if index in [0, 3] else -swing
		# Arms reach forward while carrying.
		if index >= 2 and carry_point.get_child_count() > 0:
			target = -1.2
		if stunned:
			target = 0.9 if index >= 2 else 0.0
		limb.rotation.x = lerpf(limb.rotation.x, target, minf(1.0, delta * 14.0))
