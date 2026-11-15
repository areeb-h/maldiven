extends CharacterBody3D
## Camera-relative movement shared by keyboard and independent touch pointers.
var move_input := Vector2.ZERO
var yaw := 0.0
var pitch := -0.25
var jump_pending := false
var jump_buffer := 0.0
var coyote := 0.0
var spawn := Vector3(0, 2, 16)
var pivot: Node3D
var arm: SpringArm3D
var visual: Node3D
var stride_phase := 0.0
var limbs: Array[Node3D] = []

func _ready() -> void:
	floor_snap_length = 0.35
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	var character: PackedScene = preload("res://assets/models/explorer.glb")
	visual = character.instantiate()
	visual.rotation.y = PI
	add_child(visual)
	for limb_name in ["LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
		limbs.append(visual.find_child(limb_name, true, false) as Node3D)
	pivot = Node3D.new()
	pivot.position.y = 1.5
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 5.5
	arm.margin = 0.2
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.2
	arm.shape = camera_shape
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 68
	arm.add_child(camera)
	position = spawn

func look(delta: Vector2) -> void:
	yaw -= delta.x * 0.004
	pitch = clampf(pitch - delta.y * 0.004, -1.1, 0.3)

func _physics_process(delta: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	var keyboard := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var axis := move_input if move_input.length() > 0.05 else keyboard.limit_length()
	var direction := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	var speed := 6.0 if axis.length() > 0.8 else 3.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed = 6.0
	velocity.x = move_toward(velocity.x, direction.x * speed, 22.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 22.0 * delta)
	coyote = 0.12 if is_on_floor() else maxf(0, coyote - delta)
	jump_buffer = 0.14 if jump_pending else maxf(0, jump_buffer - delta)
	jump_pending = false
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if jump_buffer > 0 and coyote > 0:
		velocity.y = 7.0
		jump_buffer = 0
		coyote = 0
	move_and_slide()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(velocity.x, velocity.z), minf(1.0, delta * 12.0))
	stride_phase += horizontal_speed * delta * 2.4
	var swing := sin(stride_phase) * minf(horizontal_speed / 6.0, 1.0) * 0.5 if is_on_floor() else 0.0
	for index in range(limbs.size()):
		if is_instance_valid(limbs[index]):
			var target := swing if index in [0, 3] else -swing
			limbs[index].rotation.x = lerpf(limbs[index].rotation.x, target, minf(1.0, delta * 18.0))
	if position.y < -5 or Vector2(position.x, position.z).length() > 49:
		position = spawn
		velocity = Vector3.ZERO

func clear_input() -> void:
	move_input = Vector2.ZERO
	jump_pending = false
	jump_buffer = 0
