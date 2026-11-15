class_name CrewMember
extends CharacterBody3D
## A crew avatar. The local one reads input and owns a camera; remote ones are
## smoothed puppets driven by host pose broadcasts but still block movement.
## Uses the procedural CrewModel when present, else the Props fallback figure.

signal footstep(at: Vector3)
signal landed(at: Vector3, impact: float)

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
const CREW_MODEL_PATH := "res://scripts/art/crew_model.gd"

var peer_id := 0
var is_local := false
var display_name := ""
var color := Color.WHITE
var speed_factor := 1.0
var stunned := false
var aiming := false
var carrying_body := false
var life_state := "ok"
var number := 0  # 1..8, shown on the suit
var variant := 0  # cosmetic helmet/backpack style
var carried := false
var input_enabled := true  # false while a menu covers the screen
var forced_position = null  # Vector3 set by the host for downed bodies, else null
# Render-rate smoothing: physics runs at a fixed 60 Hz, screens may run at
# 90/120 Hz. The visual and camera are drawn between the last two physics
# positions so motion stays smooth at any refresh rate.
var _physics_prev := Vector3.ZERO
var _physics_now := Vector3.ZERO
var _visual_base := Vector3.ZERO

var move_input := Vector2.ZERO
var yaw := 0.0
var pitch := -0.42
var jump_pending := false
var _jump_buffer := 0.0
var _coyote := 0.0
var _spawn := Vector3.ZERO

var visual: Node3D
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var name_tag: Label3D
var carry_point: Node3D
var hand_point: Node3D
var flashlight: SpotLight3D
var _model_api := false  # true when visual is a CrewModel with set_motion()
var _visual_yaw_offset := PI
var _limbs: Array[Node3D] = []
var _stride := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _remote_moving := 0.0
var _facing := 0.0
var _shake := 0.0
var _fov_kick := 0.0
var _bob := 0.0
var _last_look_ms := 0
var _prev_facing := 0.0
var _lean := 0.0
var _was_on_floor := true
var _fall_speed := 0.0


func setup(id: int, local: bool, player_name: String, suit: Color, spawn_at: Vector3) -> void:
	peer_id = id
	is_local = local
	display_name = player_name
	color = suit
	_spawn = spawn_at
	name = "Crew%d" % id


func _ready() -> void:
	floor_snap_length = 0.35
	collision_layer = 4 if is_local else 2
	collision_mask = 1 | 2
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	_build_visual()
	name_tag = Label3D.new()
	name_tag.text = display_name
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.font = UiStyle.font("bold")
	name_tag.font_size = 52
	name_tag.outline_size = 12
	name_tag.modulate = color.lightened(0.35)
	name_tag.position.y = 2.3
	name_tag.pixel_size = 0.005
	name_tag.visible = not is_local
	add_child(name_tag)
	flashlight = Props.make_flashlight()
	flashlight.position = Vector3(0, 1.55, 0.25)
	flashlight.visible = false
	add_child(flashlight)
	position = _spawn
	_target_pos = _spawn
	if is_local:
		# The camera rig follows smoothly in world space instead of being rigidly
		# parented: removes step jitter and gives a slight cinematic lag.
		pivot = Node3D.new()
		pivot.top_level = true
		add_child(pivot)
		pivot.global_position = global_position + Vector3(0, 1.6, 0)
		arm = SpringArm3D.new()
		arm.spring_length = 5.0
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


func _build_visual() -> void:
	if ResourceLoader.exists(CREW_MODEL_PATH):
		var script: Script = load(CREW_MODEL_PATH)
		var built: Variant = script.call("build", color, variant, number) if script != null else null
		if built is Node3D:
			visual = built
			_model_api = visual.has_method("set_motion")
			_visual_yaw_offset = 0.0  # CrewModel faces +Z
	if visual == null:
		visual = Props.make_crew_visual(color)
		_visual_yaw_offset = PI  # explorer.glb faces -Z
	add_child(visual)
	visual.rotation.y = _visual_yaw_offset
	if not _model_api:
		for limb_name in ["LeftLeg", "RightLeg", "LeftArm", "RightArm"]:
			var limb := visual.find_child(limb_name, true, false) as Node3D
			if limb != null:
				_limbs.append(limb)
	var anchor: Variant = visual.get("carry_anchor")
	if anchor is Node3D:
		carry_point = anchor
	else:
		carry_point = Node3D.new()
		carry_point.position = Vector3(0, 0.95, 0.55)
		add_child(carry_point)
	var hand: Variant = visual.get("hand_anchor")
	hand_point = hand if hand is Node3D else carry_point


func look(delta: Vector2) -> void:
	_last_look_ms = Time.get_ticks_msec()
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
		snap_smoothing()
	_target_pos = pos
	_target_yaw = facing
	_remote_moving = moving


func knockback(direction: Vector3) -> void:
	if is_local and life_state == "ok":
		velocity = direction.normalized() * 9.5 + Vector3(0, 3.5, 0)


## Camera juice: shake plus FOV punch, 0..1 strength.
func camera_kick(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))
	_fov_kick = maxf(_fov_kick, 7.0 * strength)
	if is_local and OS.has_feature("mobile"):
		Input.vibrate_handheld(int(40 + 80 * strength))


func express(face: String, hold := 0.8) -> void:
	if visual.has_method("set_expression"):
		visual.set_expression(face, hold)


func set_carried(on: bool) -> void:
	if on != carried:
		carried = on
		if visual.has_method("set_carried"):
			visual.set_carried(on)


## "ok", "downed" or "dead" (ghost).
func set_life_state(state: String) -> void:
	life_state = state
	var ghost := state == "dead"
	if visual.has_method("set_downed"):
		visual.set_downed(state == "downed")
	if visual.has_method("set_ghost"):
		visual.set_ghost(ghost)
	elif ghost:
		_set_transparency(visual, 0.65)
	else:
		_set_transparency(visual, 0.0)
	if not _model_api:
		visual.rotation.x = -PI / 2.0 if state == "downed" else 0.0
		_visual_base = Vector3(0, 0.25 if state == "downed" else 0.0, 0)
	var standing := state == "ok"
	collision_layer = (4 if is_local else 2) if standing else 0
	collision_mask = 0 if ghost else (1 | 2 if standing else 1)
	name_tag.modulate.a = 0.5 if ghost else 1.0
	if ghost and is_local:
		velocity = Vector3.ZERO
		position.y = 0.6


func _set_transparency(node: Node, amount: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = amount
	for child in node.get_children():
		_set_transparency(child, amount)


func facing_yaw() -> float:
	return _facing


func moving_amount() -> float:
	return Vector2(velocity.x, velocity.z).length() if is_local else _remote_moving


func respawn() -> void:
	position = _spawn
	velocity = Vector3.ZERO
	snap_smoothing()


## Call after any teleport so the render smoothing doesn't streak across it.
func snap_smoothing() -> void:
	_physics_prev = global_position
	_physics_now = global_position


func _physics_process(delta: float) -> void:
	if is_local:
		_physics_prev = _physics_now
		if life_state == "dead":
			_ghost_physics(delta)
		elif life_state == "downed":
			velocity = Vector3.ZERO
			if forced_position != null:
				position = forced_position
		else:
			_local_physics(delta)
		_physics_now = global_position
		if _physics_prev.distance_to(_physics_now) > 3.0:
			_physics_prev = _physics_now  # teleported: don't interpolate across it
	_animate(delta, moving_amount())


func _process(delta: float) -> void:
	if is_local:
		var smoothed := _physics_prev.lerp(_physics_now, Engine.get_physics_interpolation_fraction())
		visual.position = _visual_base + (smoothed - global_position)
		_camera_fx(delta, smoothed)
	else:
		# Remote players: ease toward the latest network pose every rendered frame.
		var blend := 1.0 - exp(-delta * 14.0)
		position = position.lerp(_target_pos, blend)
		_facing = lerp_angle(_facing, _target_yaw, blend)
		visual.position = _visual_base
	visual.rotation.y = _facing + _visual_yaw_offset


func _input_axis() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	var keyboard := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	return move_input if move_input.length() > 0.05 else keyboard.limit_length()


func _local_physics(delta: float) -> void:
	var axis := _input_axis()
	if stunned:
		axis = Vector2.ZERO
	var direction := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	var shift := input_enabled and Input.is_physical_key_pressed(KEY_SHIFT)
	var running := shift or (move_input.length() > 0.8)
	var speed := (RUN_SPEED if running else WALK_SPEED) * speed_factor
	# Snappy start, firm stop, limited air control; stuns slide.
	var accel := 30.0 if axis.length() > 0.05 else 36.0
	if not is_on_floor():
		accel = 10.0
	if stunned:
		accel = 6.0
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
	if aiming:
		_facing = lerp_angle(_facing, yaw + PI, minf(1.0, delta * 16.0))  # face where the camera looks
	elif horizontal.length() > 0.2 and not stunned:
		var turn_rate := 15.0 if horizontal.length() > WALK_SPEED + 0.5 else 11.0
		_facing = lerp_angle(_facing, atan2(velocity.x, velocity.z), minf(1.0, delta * turn_rate))
	if position.y < -6.0:
		respawn()
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and _fall_speed > 4.0:
		landed.emit(global_position, _fall_speed)
		camera_kick(clampf((_fall_speed - 4.0) / 10.0, 0.08, 0.35))
	_was_on_floor = on_floor
	_fall_speed = maxf(0.0, -velocity.y)
	_auto_recenter(delta, horizontal.length())


func _ghost_physics(delta: float) -> void:
	var axis := _input_axis()
	var direction := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	var speed := RUN_SPEED * speed_factor
	velocity = velocity.lerp(direction * speed, minf(1.0, delta * 6.0))
	_bob += delta
	position += velocity * delta
	position.y = 0.6 + sin(_bob * 1.7) * 0.15
	if velocity.length() > 0.3:
		_facing = lerp_angle(_facing, atan2(velocity.x, velocity.z), minf(1.0, delta * 6.0))


## Touch players: when moving without touching the camera for a moment, ease
## the camera back behind the character (common mobile third-person pattern).
func _auto_recenter(delta: float, speed: float) -> void:
	if aiming or move_input.length() < 0.2 or speed < 1.5:
		return
	if Time.get_ticks_msec() - _last_look_ms < 1400:
		return
	var target := _facing - PI
	var difference := wrapf(target - yaw, -PI, PI)
	if absf(difference) > 2.4:
		return  # running towards the camera: don't spin around
	yaw += difference * minf(1.0, delta * 1.4 * clampf(speed / RUN_SPEED, 0.3, 1.0))


func _camera_fx(delta: float, smoothed: Vector3) -> void:
	if camera == null:
		return
	pivot.rotation = Vector3(pitch, yaw, 0)
	# Smooth follow, over-the-shoulder when aiming, pulled back when carrying.
	var shoulder := Basis(Vector3.UP, yaw) * Vector3(0.75, 0.0, 0.0) if aiming else Vector3.ZERO
	var follow_target := smoothed + Vector3(0, 1.6 if life_state != "downed" else 0.9, 0) + shoulder
	pivot.global_position = pivot.global_position.lerp(follow_target, 1.0 - exp(-delta * 14.0))
	var length := 3.4 if aiming else (5.8 if carrying_body or carry_point.get_child_count() > 0 else 5.0)
	arm.spring_length = lerpf(arm.spring_length, length, minf(1.0, delta * 6.0))
	_shake = maxf(0.0, _shake - delta * 2.2)
	_fov_kick = maxf(0.0, _fov_kick - delta * 20.0)
	var trauma := _shake * _shake
	var t := Time.get_ticks_msec() / 1000.0
	camera.h_offset = sin(t * 47.0) * 0.18 * trauma
	camera.v_offset = cos(t * 39.0) * 0.14 * trauma
	var running := Vector2(velocity.x, velocity.z).length() > WALK_SPEED + 0.5
	var target_fov := (72.0 if running else 66.0) + _fov_kick
	if aiming:
		target_fov = 60.0 + _fov_kick
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 8.0))


## Lean into turns (body rolls toward the inside of the curve).
func _apply_lean(delta: float, horizontal_speed: float) -> void:
	var turn := wrapf(_facing - _prev_facing, -PI, PI) / maxf(delta, 0.0001)
	_prev_facing = _facing
	var speed_amount := clampf(horizontal_speed / RUN_SPEED, 0.0, 1.0)
	var target := clampf(-turn * 0.055 * speed_amount, -0.24, 0.24)
	if life_state != "ok":
		target = 0.0
	_lean = lerpf(_lean, target, minf(1.0, delta * 8.0))
	var sign_fix := 1.0 if _visual_yaw_offset == 0.0 else -1.0
	if _model_api or life_state == "ok":
		visual.rotation.z = _lean * sign_fix


func _animate(delta: float, horizontal_speed: float) -> void:
	_apply_lean(delta, horizontal_speed)
	var before := sin(_stride)
	_stride += horizontal_speed * delta * 2.4
	if horizontal_speed > 1.0 and life_state == "ok" and signf(before) != signf(sin(_stride)):
		footstep.emit(global_position)
	var holding := carry_point.get_child_count() > 0 or carrying_body
	if _model_api:
		visual.set_motion(horizontal_speed, is_on_floor() or not is_local, holding, stunned, delta)
		if visual.has_method("set_aiming"):
			visual.set_aiming(aiming)
		if visual.has_method("set_flashlight_on"):
			visual.set_flashlight_on(flashlight.visible)
		return
	if life_state != "ok":
		return
	var amount := minf(horizontal_speed / RUN_SPEED, 1.0)
	var swing := sin(_stride) * amount * 0.55
	for index in range(_limbs.size()):
		var limb := _limbs[index]
		if not is_instance_valid(limb):
			continue
		var target := swing if index in [0, 3] else -swing
		if index >= 2 and holding:
			target = -1.2  # arms reach forward while carrying
		if stunned:
			target = 0.9 if index >= 2 else 0.0
		limb.rotation.x = lerpf(limb.rotation.x, target, minf(1.0, delta * 14.0))
