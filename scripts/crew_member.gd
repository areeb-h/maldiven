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
const STEP_HEIGHT := 0.25  # ledges up to this climb without a jump
const FLOOR_MAX_ANGLE := deg_to_rad(46.0)
const KNOCKBACK_SPEED := 9.5
const KNOCKBACK_LIFT := 3.5
const WALL_BOUNCE := 0.42  # share of an into-wall knockback speed that bounces back
const BOUNCE_MIN_SPEED := 3.5
const CARRY_LIFT_SECONDS := 0.3

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
## Host-simulated bot (scripts/bots/): physics like a local player, driven by a
## BotBrain through move_input / yaw / jump_pending; no camera, HUD or keys.
var bot_driven := false
var forced_position = null  # Vector3 set by the host for downed bodies, else null
## Velocity bias from the environment (airlock decompression), set by the world.
var external_push := Vector3.ZERO
## The avatar carrying this (downed) body, so the visual can ride in its arms.
var carrier: CrewMember = null
## Physical reactions layered on the CrewModel rig (stagger, ragdoll, dangle).
var reactions: CrewReactions
var _push_load := 0.0  # 0..1: how much the prop being pushed slows us
var _knock_time := 0.0  # s of reduced control after a knock
var _step_offset := 0.0  # visual height lag after a step-up (eases to 0)
var _carry_blend := 0.0
var _held_kind := ""
var _carry_from := Transform3D.IDENTITY
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

## Every live avatar on this peer, so remote puppets can keep personal space.
static var registry: Array[CrewMember] = []

var visual: Node3D
var pivot: Node3D
var _collider: CollisionShape3D
var _standing_shape: CapsuleShape3D
var _lying_shape: CapsuleShape3D
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
	floor_max_angle = FLOOR_MAX_ANGLE
	floor_constant_speed = true
	max_slides = 6
	collision_layer = 4 if is_local else 2
	collision_mask = _standing_mask()
	_standing_shape = CapsuleShape3D.new()
	_standing_shape.radius = 0.38
	_standing_shape.height = 1.8
	# Downed bodies are solid too: a capsule lying along the body.
	_lying_shape = CapsuleShape3D.new()
	_lying_shape.radius = 0.3
	_lying_shape.height = 1.7
	_collider = CollisionShape3D.new()
	_collider.shape = _standing_shape
	_collider.position.y = 0.9
	add_child(_collider)
	registry.append(self)
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
	if _model_api and visual.get("bones") is Array:
		reactions = CrewReactions.new(self, visual)
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
	if _simulated():
		return
	if pos.distance_to(_target_pos) > 6.0:
		position = pos  # teleport/respawn: snap instead of sliding through walls
		snap_smoothing()
	_target_pos = pos
	_target_yaw = facing
	_remote_moving = moving


## Launch this (local) player along `direction`. strength 1 = a full shove;
## walls stop it (move_and_slide) and bounce a share of it back.
func knockback(direction: Vector3, strength := 1.0) -> void:
	if not _simulated() or life_state != "ok":
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return
	velocity = flat.normalized() * KNOCKBACK_SPEED * strength + Vector3(0, KNOCKBACK_LIFT * minf(strength, 1.0), 0)
	_knock_time = 0.25 + 0.2 * strength


## What this crew member holds ("cell", "core", "gun" or ""): the gloves grip it.
func set_held_kind(kind: String) -> void:
	if kind == _held_kind:
		return
	_held_kind = kind
	if visual.has_method("set_held_item"):
		visual.set_held_item(kind)


## Turn the body to a yaw at once (downed bodies lie along the fall).
func snap_facing(next_yaw: float) -> void:
	_facing = next_yaw
	_target_yaw = next_yaw


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
		if reactions != null:
			reactions.set_dangle(on)
		_carry_from = visual.global_transform if visual.is_inside_tree() else Transform3D.IDENTITY
		_carry_blend = 0.0
		_apply_collision()


func _exit_tree() -> void:
	registry.erase(self)


## Collision by state: standing capsule; a lying capsule while downed (still
## solid so nobody walks through a body); nothing while carried (it moves with
## its carrier) or as a ghost.
func _apply_collision() -> void:
	var own_layer := 4 if is_local else 2
	match life_state:
		"ok":
			_collider.shape = _standing_shape
			_collider.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0))
			collision_layer = own_layer
			collision_mask = _standing_mask()
		"downed":
			_collider.shape = _lying_shape
			_orient_lying_collider()
			collision_layer = 0 if carried else own_layer
			collision_mask = 1
		_:
			collision_layer = 0
			collision_mask = 0


## The local player collides with the world, other players and prop replicas
## (props are pushed by the host's proxy of this player, which runs a little
## ahead, so the replica usually moves before the capsule reaches it).
func _standing_mask() -> int:
	if bot_driven:
		return 1 | 2 | 4 | PhysicsLayers.PROP  # host bots also bump into the host's own player
	return 1 | 2 | (PhysicsLayers.PROP if is_local else 0)


func _orient_lying_collider() -> void:
	var along := Basis(Vector3.UP, _facing) * Basis(Vector3.RIGHT, PI / 2.0)
	_collider.transform = Transform3D(along, Vector3(0, 0.3, 0))


## "ok", "downed" or "dead" (ghost).
func set_life_state(state: String) -> void:
	if reactions != null and state != "downed" and reactions.is_ragdolling():
		reactions.end_ragdoll(true)  # revived mid-fall: ease out of it
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
	_apply_collision()
	name_tag.modulate.a = 0.5 if ghost else 1.0
	if ghost and _simulated():
		velocity = Vector3.ZERO
		position.y = 0.6


func _set_transparency(node: Node, amount: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = amount
	for child in node.get_children():
		_set_transparency(child, amount)


func facing_yaw() -> float:
	return _facing


## This peer simulates the body (its own player, or a bot on the host).
func _simulated() -> bool:
	return is_local or bot_driven


func moving_amount() -> float:
	return Vector2(velocity.x, velocity.z).length() if _simulated() else _remote_moving


func respawn() -> void:
	position = _spawn
	velocity = Vector3.ZERO
	snap_smoothing()


## Call after any teleport so the render smoothing doesn't streak across it.
func snap_smoothing() -> void:
	_physics_prev = global_position
	_physics_now = global_position


func _physics_process(delta: float) -> void:
	if _simulated():
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
	_step_offset = move_toward(_step_offset, 0.0, delta * 2.6)
	if _simulated():
		var smoothed := _physics_prev.lerp(_physics_now, Engine.get_physics_interpolation_fraction())
		visual.position = _visual_base + (smoothed - global_position) + Vector3(0, _step_offset, 0)
		_camera_fx(delta, smoothed + Vector3(0, _step_offset, 0))
	else:
		# Remote players: ease toward the latest network pose every rendered frame.
		var blend := 1.0 - exp(-delta * 14.0)
		position = position.lerp(_target_pos, blend)
		_facing = lerp_angle(_facing, _target_yaw, blend)
		_keep_personal_space()
		visual.position = _visual_base
		if life_state == "downed" and not carried:
			_orient_lying_collider()
	visual.rotation.y = _facing + _visual_yaw_offset
	if carried:
		_ride_carrier(delta)
	if reactions != null:
		reactions.post_render(delta)


## A carried body rides across its carrier's arms (the rules keep its logical
## position on the floor in front of them). Eases up from the floor when lifted.
func _ride_carrier(delta: float) -> void:
	if carrier == null or not is_instance_valid(carrier) or carrier.carry_point == null:
		return
	var carrier_basis := Basis(Vector3.UP, carrier.visual.global_rotation.y)
	var anchor := carrier.carry_point.global_position
	var target := Transform3D(carrier_basis, anchor + carrier_basis * Vector3(0.0, 0.02, 0.06))
	_carry_blend = minf(1.0, _carry_blend + delta / CARRY_LIFT_SECONDS)
	var k := smoothstep(0.0, 1.0, _carry_blend)
	visual.global_transform = _carry_from.interpolate_with(target, k) if k < 1.0 else target


func _input_axis() -> Vector2:
	if bot_driven:
		return move_input.limit_length()
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
	var shift := input_enabled and not bot_driven and Input.is_physical_key_pressed(KEY_SHIFT)
	var running := shift or (move_input.length() > 0.8)
	# Pushing a heavy prop slows you down (barrel ~40 %, crate ~30 %, a chair barely).
	var speed := (RUN_SPEED if running else WALK_SPEED) * speed_factor * (1.0 - _push_load)
	# Snappy start, firm stop, limited air control; stuns and knocks slide.
	var accel := 30.0 if axis.length() > 0.05 else 36.0
	if not is_on_floor():
		accel = 10.0
	if _knock_time > 0.0:
		accel = 8.0
		_knock_time -= delta
	if stunned:
		accel = 6.0
	# Decompression drags the target velocity towards the outer door: walking
	# out is possible but slow; standing still slides you in.
	var want := direction * speed + external_push
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)
	_coyote = 0.12 if is_on_floor() else maxf(0.0, _coyote - delta)
	_jump_buffer = 0.14 if jump_pending else maxf(0.0, _jump_buffer - delta)
	jump_pending = false
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and not stunned:
		velocity.y = 6.5
		_jump_buffer = 0.0
		_coyote = 0.0
	velocity = velocity.limit_length(24.0)
	_try_step_up(delta)
	var before := velocity
	move_and_slide()
	_after_slide(before, delta)
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


## Small ledges (platform edges, a fallen toolbox) are climbed without a jump:
## if the way ahead is blocked by something vertical but clear 0.25 m higher,
## and there's walkable floor on top, pop up onto it. The visual eases up.
func _try_step_up(delta: float) -> void:
	if not is_on_floor() or stunned or velocity.y > 0.5:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.0005:
		return
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit):
		return
	if absf(hit.get_normal().y) > 0.3:
		return  # a slope: floor_max_angle handles those
	var up := Vector3(0, STEP_HEIGHT + 0.02, 0)
	if test_move(global_transform, up):
		return  # no headroom
	var raised := global_transform.translated(up)
	var ahead := motion.normalized() * maxf(motion.length(), 0.08)
	if test_move(raised, ahead):
		return  # still blocked higher up: a real wall
	var probe := raised.translated(ahead)
	var down := KinematicCollision3D.new()
	if not test_move(probe, -up, down):
		return  # nothing to stand on
	if down.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	var rise := up.y - down.get_travel().length()
	if rise <= 0.02 or rise > STEP_HEIGHT:
		return
	global_position.y += rise
	_physics_prev.y += rise  # the visual eases up instead of popping
	_step_offset -= rise


## After moving: knockback bounces off walls, and pushing a prop costs speed.
func _after_slide(before: Vector3, delta: float) -> void:
	var load := 0.0
	var bounce := Vector3.ZERO
	for i in range(get_slide_collision_count()):
		var hit := get_slide_collision(i)
		var other := hit.get_collider()
		if other is NetBody and (other as NetBody).is_prop:
			load = maxf(load, (other as NetBody).push_resist)
		var normal := hit.get_normal()
		if absf(normal.y) < 0.5 and (_knock_time > 0.0 or stunned):
			var into := before.dot(normal)
			if into < -BOUNCE_MIN_SPEED and absf(into) > absf(bounce.dot(normal)):
				bounce = -into * WALL_BOUNCE * Vector3(normal.x, 0.0, normal.z).normalized()
	if bounce != Vector3.ZERO:
		velocity += bounce
		camera_kick(clampf(bounce.length() / 8.0, 0.15, 0.4))
		landed.emit(global_position + Vector3(0, 0.9, 0), bounce.length())
	# The host pushes props a little ahead of us, so also feel a prop just in front.
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if load == 0.0 and flat.length() > 0.3:
		var probe := KinematicCollision3D.new()
		if test_move(global_transform, flat.normalized() * 0.3, probe) and probe.get_collider() is NetBody:
			var body := probe.get_collider() as NetBody
			if body.is_prop:
				load = body.push_resist
	_push_load = move_toward(_push_load, load, delta * (4.0 if load > _push_load else 2.0))


## Touch players: when moving without touching the camera for a moment, ease
## the camera back behind the character (common mobile third-person pattern).
func _auto_recenter(delta: float, speed: float) -> void:
	if bot_driven or aiming or move_input.length() < 0.2 or speed < 1.5:
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


## Remote puppets follow network poses, which can briefly overlap another
## player's capsule. Push this puppet out so bodies never visibly interpenetrate.
func _keep_personal_space() -> void:
	if life_state != "ok":
		return
	const MIN_GAP := 0.78  # two capsule radii plus a hair
	for other in registry:
		if other == self or other.life_state != "ok" or not other.is_inside_tree():
			continue
		var offset := Vector2(position.x - other.position.x, position.z - other.position.z)
		var distance := offset.length()
		if distance >= MIN_GAP:
			continue
		var push := (MIN_GAP - distance) * (1.0 if other._simulated() else 0.5)
		var away := offset.normalized() if distance > 0.001 else Vector2(1, 0)
		position += Vector3(away.x, 0, away.y) * push


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
		visual.set_motion(horizontal_speed, is_on_floor() or not _simulated(), holding, stunned, delta)
		if visual.has_method("set_aiming"):
			visual.set_aiming(aiming)
		if visual.has_method("set_flashlight_on"):
			visual.set_flashlight_on(flashlight.visible)
		if reactions != null:
			reactions.post_animate(delta)
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
