class_name CrewModel
extends Node3D
## Hero crew member: procedural EVA suit on a Node3D pivot rig, GPU-skinned in a
## single draw call (plus the LED-face visor), with fully procedural animation.
##
## Origin at the feet, forward = +Z, character's left = +X. No extra rotation needed.
## Gameplay calls set_motion() every frame; overlays and states are optional.

## Emitted when a foot plants (0 = left, 1 = right), for footstep audio / dust.
signal footstep(side: int)

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
const ANKLE_H := 0.09

var color := Color.WHITE
var variant := 0
var number := 0
## Where a carried object sits (between the hands, ~0.95 m up, ~0.46 m forward).
var carry_anchor: Node3D
## Child of the right hand at the grip. +Z = barrel direction when aiming, +Y = up.
var hand_anchor: Node3D
var body: MeshInstance3D
var visor: MeshInstance3D
var bones: Array[Node3D] = []

var _suit_mat: ShaderMaterial
var _ghost_mat: ShaderMaterial
var _visor_mat: ShaderMaterial
var _ghost_visor_mat: ShaderMaterial
var _bind_inv: Array[Transform3D] = []
var _palette: Array = []
var _xf: Array[Transform3D] = []

# Locomotion and state weights.
var _driven := false
var _time := 0.0
var _phase := 0.0
var _speed := 0.0
var _accel := 0.0
var _move_w := 0.0
var _run_w := 0.0
var _air_w := 0.0
var _carry_w := 0.0
var _stun_w := 0.0
var _aim_w := 0.0
var _down_w := 0.0
var _carried_w := 0.0
var _ghost_w := 0.0
var _down := false
var _carried := false
var _ghost := false
var _aiming := false
var _down_t := 0.0
var _shove_t := -1.0
var _hit_t := -1.0
var _hit_side := 1.0
var _front := 0.8  # share of the stance spent ahead of the hip (x reach)
var _comp := 0.0  # mid-stance compression (running)

# Face.
var _expr := 0
var _expr_prev := 0
var _expr_mix := 1.0
var _expr_hold := 0.0
var _expr_base := 0
var _blink := 0.0
var _blink_t := -1.0
var _blink_timer := 3.0
var _look := Vector2.ZERO
var _saccade := Vector2.ZERO
var _saccade_timer := 1.5
var _last_yaw := 0.0
var _yaw_rate := 0.0

# Secondary motion and life support.
var _ant := Vector2.ZERO
var _ant_v := Vector2.ZERO
var _pack := 0.0
var _pack_v := 0.0
var _head_p := Vector3.ZERO
var _head_v := Vector3.ZERO
var _chest_p := Vector3.ZERO
var _chest_v := Vector3.ZERO
var _springs_ready := false
var _sole := Vector2.ZERO
var _vent := 0.0
var _oxygen := 1.0
var _fidget_timer := 7.0
var _fidget_t := -1.0
var _fidget_kind := 0
var _lamp := 0.3
var _lamp_target := 0.3
var _last_params := {}


## `variant` 0..3 picks the helmet top and backpack style; `number` 1..8 is the
## player number painted on the pauldrons and glowing on the pack (0 = crew emblem).
static func build(p_color: Color, p_variant := 0, p_number := 0) -> CrewModel:
	var m := CrewModel.new()
	m._setup(p_color, p_variant, p_number)
	return m


func _setup(p_color: Color, p_variant: int, p_number: int) -> void:
	color = p_color
	variant = posmod(p_variant, CrewBody.VARIANTS)
	name = "CrewModel"
	var J := CrewBody.JOINTS
	for i in CrewBody.BONE_NAMES.size():
		var b := Node3D.new()
		b.name = CrewBody.BONE_NAMES[i]
		var parent_index := CrewBody.PARENTS[i]
		b.position = J[i] - (J[parent_index] if parent_index >= 0 else Vector3.ZERO)
		(bones[parent_index] if parent_index >= 0 else self as Node3D).add_child(b)
		bones.append(b)
		_bind_inv.append(Transform3D(Basis.IDENTITY, -J[i]))
		_palette.append(Projection())
		_xf.append(Transform3D.IDENTITY)
	_suit_mat = CrewMaterials.instance("suit", color)
	_visor_mat = CrewMaterials.instance("visor", color)
	body = MeshInstance3D.new()
	body.name = "Suit"
	body.mesh = CrewBody.body_mesh(variant)
	body.material_override = _suit_mat
	body.custom_aabb = AABB(Vector3(-1.1, -0.3, -1.1), Vector3(2.2, 2.6, 2.2))
	add_child(body)
	visor = MeshInstance3D.new()
	visor.name = "Visor"
	visor.mesh = CrewBody.visor_mesh()
	visor.material_override = _visor_mat
	bones[CrewBody.HEAD].add_child(visor)
	carry_anchor = Node3D.new()
	carry_anchor.name = "CarryAnchor"
	carry_anchor.position = Vector3(0, 0.95, 0.46)
	add_child(carry_anchor)
	hand_anchor = Node3D.new()
	hand_anchor.name = "HandAnchor"
	hand_anchor.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.03, -0.06, 0.01))
	bones[CrewBody.R_HAND].add_child(hand_anchor)
	set_number(p_number)
	_blink_timer = randf_range(2.0, 4.5)
	_fidget_timer = randf_range(6.0, 10.0)
	_upload()


# --- public API ---------------------------------------------------------------------

func set_motion(speed: float, on_floor: bool, carrying: bool, stunned: bool, delta: float) -> void:
	_driven = true
	delta = clampf(delta, 0.0, 0.1)
	_time += delta
	var prev := _speed
	_speed = lerpf(_speed, maxf(speed, 0.0), 1.0 - exp(-delta * 10.0))
	_accel = lerpf(_accel, (_speed - prev) / maxf(delta, 0.001), 1.0 - exp(-delta * 6.0))
	_move_w = smoothstep(0.08, 1.1, _speed)
	_run_w = smoothstep(WALK_SPEED + 0.2, RUN_SPEED - 0.2, _speed)
	_air_w = move_toward(_air_w, 0.0 if on_floor else 1.0, delta * (7.0 if on_floor else 4.0))
	_carry_w = move_toward(_carry_w, 1.0 if carrying else 0.0, delta * 5.0)
	_stun_w = move_toward(_stun_w, 1.0 if stunned else 0.0, delta * 6.0)
	_aim_w = move_toward(_aim_w, 1.0 if _aiming else 0.0, delta * 7.0)
	_carried_w = move_toward(_carried_w, 1.0 if _carried else 0.0, delta * 4.0)
	_ghost_w = move_toward(_ghost_w, 1.0 if _ghost else 0.0, delta * 2.0)
	if _down:
		_down_t = minf(_down_t + delta, 0.4)
	else:
		_down_t = maxf(_down_t - delta * 0.6, 0.0)
	_down_w = _down_t / 0.4
	_down_w = _down_w * _down_w if _down else smoothstep(0.0, 1.0, _down_w)
	if _shove_t >= 0.0:
		_shove_t += delta
		if _shove_t > 0.42:
			_shove_t = -1.0
	if _hit_t >= 0.0:
		_hit_t += delta
		if _hit_t > 0.8:
			_hit_t = -1.0
	_update_fidget(delta)
	var g := _gait(_speed)
	var before := _phase
	if _speed > 0.02:
		_phase = fposmod(_phase + _speed / g.z * delta, 1.0)
		# Footsteps: a foot plants when its local phase wraps through 0.
		if _move_w > 0.3 and _air_w < 0.5:
			if _phase < before:
				_plant(0)
			if fposmod(before + 0.5, 1.0) > 0.5 and fposmod(_phase + 0.5, 1.0) < 0.5:
				_plant(1)
	_sole = _sole.move_toward(Vector2.ZERO, delta * 3.5)
	_vent = _run_w * pow(0.5 + 0.5 * cos(TAU * _phase * 2.0), 4.0) + 0.25 * _move_w
	_oxygen = move_toward(_oxygen, 0.55 if carrying else 1.0, delta * (0.04 if carrying else 0.12))
	_pose(g)
	_springs(delta)
	_upload()


func play_shove() -> void:
	_shove_t = 0.0


## A strong flinch that reads as being shot: snap back, arms jerk up, red rim flash.
func play_hit() -> void:
	_hit_t = 0.0
	_hit_side = -1.0 if randf() < 0.5 else 1.0


func set_flashlight_on(on: bool) -> void:
	_lamp_target = 7.0 if on else 0.3


func set_downed(on: bool) -> void:
	_down = on
	if not on:
		_carried = false
	_auto_expression()


func set_carried(on: bool) -> void:
	_carried = on
	if on:
		_down = true
		_down_t = 0.4
	_auto_expression()


func set_ghost(on: bool) -> void:
	_ghost = on
	if on and _ghost_mat == null:
		_ghost_mat = CrewMaterials.instance("ghost", color)
		_ghost_visor_mat = CrewMaterials.instance("ghost_visor", color)
		_ghost_mat.set_shader_parameter("decal_number", number)
	body.material_override = _ghost_mat if on else _suit_mat
	visor.material_override = _ghost_visor_mat if on else _visor_mat
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.cast_shadow = shadow
	visor.cast_shadow = shadow
	_last_params.clear()
	_auto_expression()


func set_aiming(on: bool) -> void:
	_aiming = on


func is_ghost() -> bool:
	return _ghost


## LED face: "neutral" (blinks), "happy", "shocked", "angry", "suspicious", "hurt",
## "downed", "ghost". With hold > 0 it returns to the base face after `hold` seconds.
func set_expression(expression: String, hold := 0.0) -> void:
	var id := CrewMaterials.EXPRESSIONS.find(expression)
	if id < 0:
		push_warning("CrewModel: unknown expression " + expression)
		return
	if hold > 0.0:
		_expr_hold = hold
	else:
		_expr_base = id
		_expr_hold = 0.0
	_show_expression(id)


func get_expression() -> String:
	return CrewMaterials.EXPRESSIONS[_expr]


## Player number 1..8 on the pauldrons, back plate and name plate (0 = crew emblem).
func set_number(n: int) -> void:
	number = clampi(n, 0, 9)
	_suit_mat.set_shader_parameter("decal_number", number)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter("decal_number", number)


func _show_expression(id: int) -> void:
	if id == _expr:
		return
	_expr_prev = _expr
	_expr = id
	_expr_mix = 0.0


func _auto_expression() -> void:
	if _ghost:
		_expr_base = 7
	elif _down:
		_expr_base = 6
	elif _expr_base == 6 or _expr_base == 7:
		_expr_base = 0
	if _expr_hold <= 0.0:
		_show_expression(_expr_base)


func _plant(side: int) -> void:
	_sole[side] = 1.0
	footstep.emit(side)


func _process(delta: float) -> void:
	_lamp = move_toward(_lamp, _lamp_target, delta * 30.0)
	var flash := 0.0
	if _hit_t >= 0.0:
		flash = clampf(1.0 - _hit_t / 0.22, 0.0, 1.0)
	_set_param("lamp_energy", _lamp)
	_set_param("hit_flash", flash * flash)
	_set_param("distress", _down_w)
	_set_param("vent_puff", snappedf(_vent, 0.01))
	_set_param("oxygen", snappedf(_oxygen, 0.005))
	_set_vec("sole_pulse", Vector2(snappedf(_sole.x, 0.01), snappedf(_sole.y, 0.01)))
	_face(delta, flash)
	if not _driven:
		_upload()  # legacy callers swing the limb pivots directly
	_driven = false


func _face(delta: float, flash: float) -> void:
	if _expr_hold > 0.0:
		_expr_hold -= delta
		if _expr_hold <= 0.0:
			_show_expression(_expr_base)
	_expr_mix = minf(_expr_mix + delta / 0.12, 1.0)
	# Blink every 3-5 s (neutral and suspicious faces).
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_t = 0.0
		_blink_timer = randf_range(3.0, 5.0)
	if _blink_t >= 0.0:
		_blink_t += delta
		_blink = clampf(1.0 - absf(_blink_t / 0.07 - 1.0), 0.0, 1.0)
		if _blink_t > 0.14:
			_blink_t = -1.0
			_blink = 0.0
	# Eyes glance toward turns, wander a little when idle, look down at the wrist.
	var yaw := global_transform.basis.z.signed_angle_to(Vector3.BACK, Vector3.UP) if is_inside_tree() else 0.0
	var rate := wrapf(_last_yaw - yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = yaw
	_yaw_rate = lerpf(_yaw_rate, rate, 1.0 - exp(-delta * 8.0))
	_saccade_timer -= delta
	if _saccade_timer <= 0.0:
		_saccade_timer = randf_range(1.2, 3.5)
		_saccade = Vector2(randf_range(-0.012, 0.012), randf_range(-0.005, 0.006)) * (1.0 - _move_w)
	var target := Vector2(clampf(_yaw_rate * 0.012, -0.024, 0.024), -0.004 * _move_w) + _saccade
	if _expr == 4:
		target.x = -0.016
	if _fidget_t >= 0.0:
		var fe := _fidget_env()
		match _fidget_kind:
			0:
				target.x = 0.022 * sin(_fidget_t / 2.2 * TAU) * fe
			2:
				target = target.lerp(Vector2(0.012, -0.018), fe)
	if _stun_w > 0.0:
		target += Vector2(sin(_time * 9.0), cos(_time * 7.0)) * 0.01 * _stun_w
	_look = _look.lerp(target, 1.0 - exp(-delta * 18.0))
	var vm := _ghost_visor_mat if _ghost else _visor_mat
	vm.set_shader_parameter("expr_a", _expr_prev)
	vm.set_shader_parameter("expr_b", _expr)
	vm.set_shader_parameter("expr_mix", _expr_mix)
	vm.set_shader_parameter("blink", _blink if _expr == 0 or _expr == 4 else 0.0)
	vm.set_shader_parameter("look", _look)
	vm.set_shader_parameter("glitch", maxf(_stun_w, flash * 0.8))


func _set_param(key: String, value: float) -> void:
	if is_equal_approx(_last_params.get(key, -999.0), value):
		return
	_last_params[key] = value
	_suit_mat.set_shader_parameter(key, value)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter(key, value)


func _set_vec(key: String, value: Vector2) -> void:
	if _last_params.get(key, Vector2(-9, -9)) == value:
		return
	_last_params[key] = value
	_suit_mat.set_shader_parameter(key, value)


# --- skinning -----------------------------------------------------------------------

func _root_xf(i: int) -> Transform3D:
	var p := CrewBody.PARENTS[i]
	return (_root_xf(p) if p >= 0 else Transform3D.IDENTITY) * bones[i].transform


func _upload() -> void:
	for i in bones.size():
		var p := CrewBody.PARENTS[i]
		_xf[i] = (_xf[p] if p >= 0 else Transform3D.IDENTITY) * bones[i].transform
		_palette[i] = Projection(_xf[i] * _bind_inv[i])
	_suit_mat.set_shader_parameter("bones", _palette)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter("bones", _palette)


# --- secondary motion ---------------------------------------------------------------

## Antenna wobble and backpack bounce: damped springs driven by how the head and
## chest accelerate in the world.
func _springs(delta: float) -> void:
	if delta <= 0.0:
		return
	var gx := global_transform if is_inside_tree() else Transform3D.IDENTITY
	var head_xf := gx * _root_xf(CrewBody.HEAD)
	var chest_xf := gx * _root_xf(CrewBody.CHEST)
	var hv := (head_xf.origin - _head_p) / delta
	var cv := (chest_xf.origin - _chest_p) / delta
	var ha := (hv - _head_v) / delta if _springs_ready else Vector3.ZERO
	var ca := (cv - _chest_v) / delta if _springs_ready else Vector3.ZERO
	_head_p = head_xf.origin
	_chest_p = chest_xf.origin
	_head_v = hv
	_chest_v = cv
	_springs_ready = true
	var la := (head_xf.basis.inverse() * ha).limit_length(60.0)
	var lc := (chest_xf.basis.inverse() * ca).limit_length(60.0)
	var steps := 2
	var h := delta / steps
	for i in steps:
		var acc := -140.0 * _ant - 7.0 * _ant_v + Vector2(la.z, -la.x) * 0.012
		_ant_v += acc * h
		_ant += _ant_v * h
		var pacc := -260.0 * _pack - 13.0 * _pack_v - lc.y * 0.0035
		_pack_v += pacc * h
		_pack += _pack_v * h
	_ant = _ant.limit_length(0.35)
	_pack = clampf(_pack, -0.025, 0.025)
	var still := 1.0 - _down_w
	bones[CrewBody.ANTENNA].basis = Basis.from_euler(Vector3(_ant.x, 0.0, _ant.y) * still)
	var pk := bones[CrewBody.PACK]
	pk.position.y += _pack * still
	pk.basis = Basis(Vector3.RIGHT, -_pack * 2.5 * still) * pk.basis


func _update_fidget(delta: float) -> void:
	var idle := _move_w < 0.05 and _carry_w < 0.05 and _aim_w < 0.05 and _stun_w < 0.05 and _down_w < 0.05 and _ghost_w < 0.05 and _air_w < 0.05 and _shove_t < 0.0
	if _fidget_t >= 0.0:
		_fidget_t += delta
		if _fidget_t > _fidget_dur() or not idle:
			_fidget_t = -1.0
			_fidget_timer = randf_range(6.0, 10.0)
		return
	if idle:
		_fidget_timer -= delta
		if _fidget_timer <= 0.0:
			_fidget_t = 0.0
			_fidget_kind = randi() % 3


func _fidget_dur() -> float:
	return [2.2, 1.6, 2.4][_fidget_kind]


func _fidget_env() -> float:
	if _fidget_t < 0.0:
		return 0.0
	var d := _fidget_dur()
	return smoothstep(0.0, 0.35, _fidget_t) * (1.0 - smoothstep(d - 0.45, d, _fidget_t))


## Test / tooling hook: start an idle fidget now (0 look around, 1 tap helmet, 2 check wrist).
func play_fidget(kind: int) -> void:
	_fidget_kind = posmod(kind, 3)
	_fidget_t = 0.0


# --- locomotion ---------------------------------------------------------------------

## Returns (half stance length R, stance fraction beta, stride length per cycle).
## Slow walk -> brisk jog at WALK_SPEED (short flight phase) -> run at RUN_SPEED.
func _gait(v: float) -> Vector3:
	var reach := minf(0.36, 0.12 + 0.2 * v)
	var beta := 0.64
	if v > 1.5:
		beta = lerpf(0.64, 0.42, smoothstep(1.5, WALK_SPEED, v))
	if v > WALK_SPEED:
		var t := clampf((v - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
		reach = lerpf(0.36, 0.46, t)
		beta = lerpf(0.42, 0.3, t)
	return Vector3(reach, beta, 2.0 * reach / beta)


## Foot path for a local phase p: (z offset, height, pitch (+ = toes down)).
func _foot_path(p: float, reach: float, beta: float, lift: float) -> Vector3:
	if p < beta:
		var t := p / beta
		var z := _front * reach - 2.0 * reach * t
		var pitch := -0.32 * (1.0 - smoothstep(0.0, 0.2, t)) + 0.75 * smoothstep(0.62, 1.0, t)
		var y := 0.0
		if pitch > 0.0:
			y = 0.14 * sin(pitch)
			z += 0.14 * (1.0 - cos(pitch))
		else:
			y = 0.07 * sin(-pitch)
		return Vector3(z, y, pitch)
	var q := (p - beta) / (1.0 - beta)
	var e := q * q * (3.0 - 2.0 * q)
	var z2 := (_front - 2.0) * reach + 2.0 * reach * e
	var y2 := lift * sin(PI * pow(q, 0.7)) + 0.14 * sin(0.75) * (1.0 - smoothstep(0.0, 0.25, q))
	var pitch2 := lerpf(0.75, -0.32, smoothstep(0.0, 0.85, q)) + 0.25 * sin(PI * q)
	return Vector3(z2, y2, pitch2)


func _stance_hip(p: float, reach: float, beta: float, lift: float, leg_len: float) -> float:
	var fp := _foot_path(p, reach, beta, lift)
	return ANKLE_H + fp.y + sqrt(maxf(leg_len * leg_len - fp.x * fp.x, 0.05)) - _comp * sin(PI * clampf(p / beta, 0.0, 1.0))


func _reset_pose() -> void:
	var J := CrewBody.JOINTS
	for i in bones.size():
		var p := CrewBody.PARENTS[i]
		bones[i].transform = Transform3D(Basis.IDENTITY, J[i] - (J[p] if p >= 0 else Vector3.ZERO))


func _pose(g: Vector3) -> void:
	_reset_pose()
	var reach := g.x
	var beta := g.y
	var t := _time
	var mw := _move_w
	var rw := _run_w
	var cyc := TAU * _phase
	var stun := _stun_w
	var B := bones
	var J := CrewBody.JOINTS

	# Overlay envelopes. Hit: a sharp snap then a damped recoil.
	var hit := 0.0
	if _hit_t >= 0.0:
		hit = _hit_t / 0.04 if _hit_t < 0.04 else exp(-(_hit_t - 0.04) * 5.0) * cos((_hit_t - 0.04) * 9.0)
	# Shove: anticipation (wind-up, lean back) -> fast thrust with overshoot -> settle.
	var shove := 0.0
	var thrust := 0.0
	var wind := 0.0
	if _shove_t >= 0.0:
		var st := _shove_t
		shove = smoothstep(0.0, 0.06, st) * (1.0 - smoothstep(0.28, 0.42, st))
		wind = smoothstep(0.0, 0.09, st) * (1.0 - smoothstep(0.1, 0.15, st))
		thrust = smoothstep(0.1, 0.16, st) + 0.18 * sin(clampf((st - 0.14) / 0.14, 0.0, 1.0) * PI)
	var fid := _fidget_env()

	# --- hips ---
	var yaw_amp := lerpf(0.13, 0.2, rw) * mw
	_front = lerpf(0.8, 0.55, rw)
	var lift := lerpf(0.1, 0.17, smoothstep(1.5, WALK_SPEED, _speed)) + 0.13 * rw
	# Vaulting: the hip height follows the planted leg(s) so knees never lock or crouch.
	var leg_len := 0.84 * lerpf(lerpf(0.99, 0.975, smoothstep(1.5, WALK_SPEED, _speed)), 0.97, rw)
	_comp = 0.025 * smoothstep(1.5, WALK_SPEED, _speed) + 0.04 * rw
	var hip_h := 9.0
	for side in 2:
		var lp := fposmod(_phase + 0.5 * side, 1.0)
		if lp < beta:
			hip_h = minf(hip_h, _stance_hip(lp, reach, beta, lift, leg_len))
	if hip_h > 8.0:
		# Flight: ballistic arc from toe-off of one foot to touchdown of the other.
		for side in 2:
			var lp2 := fposmod(_phase + 0.5 * side, 1.0)
			if lp2 >= beta and lp2 < 0.5:
				var u := (lp2 - beta) / maxf(0.5 - beta, 0.001)
				var tf := (0.5 - beta) * g.z / maxf(_speed, 0.05)
				hip_h = lerpf(_stance_hip(beta - 0.0001, reach, beta, lift, leg_len), _stance_hip(0.0, reach, beta, lift, leg_len), u) + 9.8 * tf * tf * 0.5 * u * (1.0 - u)
		if hip_h > 8.0:
			hip_h = J[CrewBody.L_LEG].y
	var hips_pos := J[CrewBody.HIPS]
	hips_pos.y += -0.022 + (minf(hip_h, J[CrewBody.L_LEG].y - 0.012) - J[CrewBody.L_LEG].y + 0.022) * mw
	hips_pos.x += 0.016 * cos(cyc - PI * beta * 0.8) * mw * (1.0 - rw * 0.6) + 0.01 * sin(t * 0.6) * (1.0 - mw)
	hips_pos.z += (0.05 * thrust - 0.035 * wind) * shove - 0.06 * hit
	hips_pos.y -= 0.04 * absf(hit) + 0.06 * stun * (0.6 + 0.4 * sin(t * 4.1)) + 0.02 * wind * shove
	hips_pos.x += stun * 0.04 * sin(t * 2.3)
	hips_pos.z += stun * 0.035 * cos(t * 1.9)
	var ghost_float := _ghost_w * (0.14 + 0.06 * sin(t * 1.6))
	hips_pos.y += ghost_float
	var hips_rot := Vector3(0.04 * mw + 0.08 * rw + clampf(_accel * 0.012, -0.08, 0.1), -yaw_amp * cos(cyc), 0.035 * sin(cyc) * mw)
	hips_rot.z += stun * 0.12 * sin(t * 2.3 + 0.5)
	B[CrewBody.HIPS].position = hips_pos
	B[CrewBody.HIPS].basis = Basis.from_euler(hips_rot)

	# --- spine / chest ---
	var breath := sin(t * TAU * 0.27)
	var lean := 0.05 * mw + 0.2 * rw + 0.06 * _carry_w * (1.0 - _aim_w) + (0.26 * thrust - 0.18 * wind) * shove - 0.45 * hit
	var counter := yaw_amp * 1.55 * cos(cyc)
	var aim_twist := 0.18 * _aim_w
	var fid_twist := 0.12 * sin(_fidget_t / 2.2 * TAU) * fid if _fidget_kind == 0 else 0.0
	B[CrewBody.SPINE].basis = Basis.from_euler(Vector3(lean * 0.5 + stun * 0.15 * sin(t * 3.0), counter * 0.45 + aim_twist * 0.4 + fid_twist * 0.4, -hips_rot.z * 0.6 + stun * 0.1 * sin(t * 2.7)))
	B[CrewBody.CHEST].basis = Basis.from_euler(Vector3(lean * 0.5 + 0.018 * breath * (1.0 - mw) - 0.2 * hit + stun * 0.1 * sin(t * 3.4 + 1.0),
		counter * 0.55 + aim_twist * 0.6 + fid_twist * 0.6 + 0.25 * hit * _hit_side, -hips_rot.z * 0.3 + 0.22 * hit * _hit_side))

	# --- head stabilisation (keeps the visor level and facing forward) + looks ---
	var neck_xf := _root_xf(CrewBody.CHEST) * B[CrewBody.NECK].transform
	var head_pitch := -0.05 * rw + 0.06 * _carry_w - 0.5 * hit
	var head_yaw := -aim_twist * 0.2
	var head_roll := 0.0
	match _fidget_kind:
		0:
			head_yaw += 0.6 * sin(_fidget_t / 2.2 * TAU) * fid
		1:
			head_roll += 0.18 * fid
			head_yaw -= 0.15 * fid
		2:
			head_pitch += 0.42 * fid
			head_yaw += 0.35 * fid
	var look := Basis.from_euler(Vector3(head_pitch, head_yaw, head_roll))
	var loll := Basis.from_euler(Vector3(0.35 * sin(t * 2.1), 0.45 * sin(t * 1.3), 0.4 * cos(t * 1.7))) if stun > 0.0 else Basis.IDENTITY
	var head_world := Basis(look.get_rotation_quaternion().slerp(loll.get_rotation_quaternion(), stun))
	var head_local := neck_xf.basis.inverse() * head_world
	var hq := head_local.get_rotation_quaternion()
	B[CrewBody.NECK].basis = Basis(Quaternion.IDENTITY.slerp(hq, 0.4))
	B[CrewBody.HEAD].basis = Basis(Quaternion.IDENTITY.slerp(hq, 0.4).inverse() * hq)

	# --- legs (IK to procedural foot paths) ---
	var hips_xf := _root_xf(CrewBody.HIPS)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var thigh := CrewBody.L_LEG if side == 0 else CrewBody.R_LEG
		var shin := thigh + 1
		var foot := thigh + 2
		var lp := fposmod(_phase + 0.5 * side, 1.0)
		var path := _foot_path(lp, reach, beta, lift)
		var idle := Vector3(s * 0.112, ANKLE_H, s * 0.025)
		var walk := Vector3(s * lerpf(0.1, 0.085, rw), ANKLE_H + path.y, path.x + 0.02)
		var target := idle.lerp(walk, mw)
		var pitch := lerpf(0.0, path.z, mw)
		# Airborne: tuck the legs.
		var tuck := Vector3(s * 0.11, 0.42 if side == 0 else 0.3, 0.14 if side == 0 else -0.04)
		target = target.lerp(Vector3(tuck.x, hips_pos.y - 0.93 + tuck.y, tuck.z), _air_w)
		pitch = lerpf(pitch, 0.35, _air_w)
		# Stunned: wobbly knees.
		target += Vector3(s * 0.03 * sin(t * 3.3 + s), 0.0, 0.05 * sin(t * 2.2 + s * 1.3)) * stun
		# Ghost: legs dangle, toes point down.
		target.y += ghost_float - _ghost_w * 0.06
		pitch = lerpf(pitch, 0.6, _ghost_w)
		var local_target := hips_xf.affine_inverse() * target
		var pole := hips_xf.basis.inverse() * Vector3(s * 0.12, 0.0, 1.0)
		var ik := _two_bone(B[thigh].position, local_target, pole, 0.425, 0.415, 1.0)
		B[thigh].basis = ik[0]
		B[shin].basis = ik[1]
		var shin_basis := hips_xf.basis * B[thigh].basis * B[shin].basis
		var want := Basis(Vector3.UP, s * 0.06) * Basis(Vector3.RIGHT, pitch)
		B[foot].basis = shin_basis.inverse() * want

	# --- arms: FK swing, blended with IK for carry / aim / shove / fidgets ---
	var chest_xf := _root_xf(CrewBody.CHEST)
	var swing_amp := lerpf(0.42, 0.75, rw) * mw * (1.0 - 0.7 * _carry_w)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var up := CrewBody.L_ARM if side == 0 else CrewBody.R_ARM
		var fore := up + 1
		var hand := up + 2
		var swing := swing_amp * cos(cyc) * s
		var fwd := maxf(0.0, -swing)
		var fk_up := Basis.from_euler(Vector3(swing + 0.04 * (1.0 - mw), 0.0, s * (0.11 + 0.05 * rw + 0.012 * breath * (1.0 - mw))))
		var fk_fore := Basis.from_euler(Vector3(-(0.22 + 0.2 * mw + 0.95 * rw + fwd * 0.5), 0.0, 0.0))
		# Air: arms out for balance. Hit: arms jerk up. Stun: flail.
		fk_up = Basis.from_euler(Vector3(-0.35 * _air_w - 0.6 * hit, 0.0, s * (0.55 * _air_w + 0.45 * absf(hit)))) * fk_up
		fk_fore = Basis.from_euler(Vector3(-0.6 * absf(hit), 0.0, 0.0)) * fk_fore
		if stun > 0.0:
			var flail := Basis.from_euler(Vector3(0.9 * sin(t * 5.2 + s * 1.7) - 0.4, 0.0, s * (0.9 + 0.5 * sin(t * 4.3 + s))))
			fk_up = Basis(fk_up.get_rotation_quaternion().slerp(flail.get_rotation_quaternion(), stun))
			fk_fore = Basis(fk_fore.get_rotation_quaternion().slerp(Quaternion(Vector3.RIGHT, -0.9 - 0.6 * sin(t * 6.1 + s)), stun))
		# Ghost: arms drift outward, weightless.
		if _ghost_w > 0.0:
			var drift := Basis.from_euler(Vector3(-0.25 + 0.1 * sin(t * 1.1 + s), 0.0, s * (0.45 + 0.08 * sin(t * 1.3))))
			fk_up = Basis(fk_up.get_rotation_quaternion().slerp(drift.get_rotation_quaternion(), _ghost_w))
		# IK targets in root space.
		var carry_t := carry_anchor.position + Vector3(s * 0.15, 0.06, -0.1)
		var aim_t := Vector3(-0.07, 1.42, 0.5) if side == 1 else Vector3(-0.025, 1.38, 0.44)
		var shove_t := Vector3(s * 0.14, 1.25, 0.08).lerp(Vector3(s * 0.15, 1.28, 0.56), clampf(thrust, 0.0, 1.2))
		var fid_t := Vector3.ZERO
		var fw := 0.0
		if fid > 0.0 and _fidget_kind == 1 and side == 1:
			var tap := 0.02 * absf(sin(_fidget_t * 13.0)) * smoothstep(0.4, 0.6, _fidget_t)
			fid_t = Vector3(-0.2 - tap, 1.68, 0.05)
			fw = fid
		elif fid > 0.0 and _fidget_kind == 2 and side == 0:
			fid_t = Vector3(0.05, 1.2, 0.3)
			fw = fid
		var cw := _carry_w
		var aw := _aim_w
		var sw := shove * 4.0
		var total := cw + aw + sw + fw
		var ik_w := clampf(maxf(maxf(cw, fw), maxf(aw, shove)), 0.0, 1.0) * (1.0 - stun) * (1.0 - _ghost_w)
		var up_b := fk_up
		var fore_b := fk_fore
		var hand_b := Basis.from_euler(Vector3(-0.1 - 0.15 * mw, 0.0, 0.0))
		if ik_w > 0.001 and total > 0.0:
			var target2 := (carry_t * cw + aim_t * aw + shove_t * sw + fid_t * fw) / total
			var lt := chest_xf.affine_inverse() * target2
			var pole2 := chest_xf.basis.inverse() * Vector3(s * 0.8, -0.6, -0.5).lerp(Vector3(s * 0.35, -1.0, 0.0), aw / maxf(total, 0.001))
			var ik2 := _two_bone(B[up].position, lt, pole2, 0.295, 0.27, -1.0)
			up_b = Basis(fk_up.get_rotation_quaternion().slerp(ik2[0].get_rotation_quaternion(), ik_w))
			fore_b = Basis(fk_fore.get_rotation_quaternion().slerp(ik2[1].get_rotation_quaternion(), ik_w))
			var push := clampf(thrust, 0.0, 1.0) * shove
			var wrist := Basis.from_euler(Vector3(-1.1 * push / maxf(ik_w, 0.01), 0.0, s * 0.15 * cw))
			if fw > 0.0 and _fidget_kind == 2:
				wrist = Basis.from_euler(Vector3(0.0, 0.0, 0.0)) * Basis(Vector3.UP, -1.2)
			hand_b = Basis(hand_b.get_rotation_quaternion().slerp(wrist.get_rotation_quaternion(), ik_w))
		B[up].basis = up_b
		B[fore].basis = fore_b
		if side == 1 and _aim_w > 0.001:
			# Level the gun: barrel along the chest's horizontal forward, top up.
			var fwd_h := Vector3(chest_xf.basis.z.x, 0.0, chest_xf.basis.z.z).normalized()
			var yb := -fwd_h
			var level := Basis(yb.cross(Vector3.UP), yb, Vector3.UP)
			var fore_root := chest_xf.basis * up_b * fore_b
			var want_hand := (fore_root.inverse() * level).orthonormalized()
			hand_b = Basis(hand_b.get_rotation_quaternion().slerp(want_hand.get_rotation_quaternion(), _aim_w * ik_w))
		B[hand].basis = hand_b
		B[up].position.y += 0.004 * breath * (1.0 - mw)
		# Fingers: relaxed curl, wrap round carried items and the grip, flat for a shove.
		var curl := lerpf(0.35, 0.6, rw)
		curl = lerpf(curl, 0.75, _carry_w)
		if side == 1:
			curl = lerpf(curl, 1.35, _aim_w)
		else:
			curl = lerpf(curl, 0.9, _aim_w)
		curl = lerpf(curl, -0.05, clampf(thrust, 0.0, 1.0) * shove)
		curl = lerpf(curl, 1.1, absf(hit) * 0.7)
		curl = lerpf(curl, 0.5 + 0.45 * sin(t * 7.0 + s), stun)
		curl = lerpf(curl, 0.15, _ghost_w)
		if fid > 0.0 and _fidget_kind == 1 and side == 1:
			curl = lerpf(curl, 1.2, fid)
		var fingers := CrewBody.L_FINGERS if side == 0 else CrewBody.R_FINGERS
		B[fingers].basis = Basis(Vector3.BACK, -s * curl)
		B[fingers + 1].basis = Basis.from_euler(Vector3(-curl * 0.45, 0.0, -s * curl * 0.55))

	# --- full-body states: downed / carried ---
	if _down_w > 0.001:
		var target_pose := _downed_pose(t)
		if _carried_w > 0.001:
			var carried_pose := _carried_pose(t)
			for i in target_pose.size():
				target_pose[i] = target_pose[i].interpolate_with(carried_pose[i], _carried_w)
		for i in bones.size():
			B[i].transform = B[i].transform.interpolate_with(target_pose[i], _down_w)


## Lying on the back, rolled slightly onto the side, one arm limp.
func _downed_pose(t: float) -> Array[Transform3D]:
	var out := _rest_pose()
	var breathe := 0.012 * sin(t * 1.4)
	out[CrewBody.HIPS] = Transform3D(Basis.from_euler(Vector3(-PI * 0.5 + 0.06, 0.0, 0.0)) * Basis(Vector3.UP, 0.42), Vector3(0.0, 0.2, -0.12))
	out[CrewBody.SPINE].basis = Basis.from_euler(Vector3(-0.05, -0.08, 0.04))
	out[CrewBody.CHEST].basis = Basis.from_euler(Vector3(-0.06 + breathe, -0.1, 0.05))
	out[CrewBody.NECK].basis = Basis.from_euler(Vector3(0.1, 0.3, 0.1))
	out[CrewBody.HEAD].basis = Basis.from_euler(Vector3(0.05, 0.45, 0.15))
	# Left arm flung out and limp on the floor; right arm bent over the belly.
	out[CrewBody.L_ARM].basis = Basis.from_euler(Vector3(0.0, 0.0, 1.25))
	out[CrewBody.L_FORE].basis = Basis.from_euler(Vector3(-0.35, 0.0, 0.0))
	out[CrewBody.L_HAND].basis = Basis.from_euler(Vector3(-0.2, 0.0, 0.25))
	out[CrewBody.R_ARM].basis = Basis.from_euler(Vector3(-0.35, 0.0, -0.32))
	out[CrewBody.R_FORE].basis = Basis.from_euler(Vector3(-1.45, 0.0, 0.0)) * Basis(Vector3.UP, 0.9)
	out[CrewBody.R_HAND].basis = Basis.from_euler(Vector3(0.2, 0.0, 0.0))
	for f in [CrewBody.L_FINGERS, CrewBody.R_FINGERS]:
		out[f].basis = Basis(Vector3.BACK, (-0.3 if f == CrewBody.L_FINGERS else 0.3))
	# Left leg straight, right knee bent and fallen outward.
	out[CrewBody.L_LEG].basis = Basis.from_euler(Vector3(-0.12, 0.0, 0.12))
	out[CrewBody.L_SHIN].basis = Basis.from_euler(Vector3(0.18, 0.0, 0.0))
	out[CrewBody.L_FOOT].basis = Basis.from_euler(Vector3(0.6, 0.15, 0.0))
	out[CrewBody.R_LEG].basis = Basis.from_euler(Vector3(-0.85, 0.0, -0.55))
	out[CrewBody.R_SHIN].basis = Basis.from_euler(Vector3(1.35, 0.0, 0.0))
	out[CrewBody.R_FOOT].basis = Basis.from_euler(Vector3(0.45, -0.2, 0.0))
	return out


## Held across the carrier's arms (bridal carry): pelvis at the model origin,
## head toward +X, face up, legs hanging over the carrier's forearm.
func _carried_pose(t: float) -> Array[Transform3D]:
	var out := _rest_pose()
	var sway := 0.05 * sin(t * 3.0)
	var lay := Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
	out[CrewBody.HIPS] = Transform3D(lay * Basis.from_euler(Vector3(0.25, 0.0, 0.0)), Vector3(-0.06, 0.02, 0.0))
	out[CrewBody.SPINE].basis = Basis.from_euler(Vector3(-0.32 + sway * 0.3, 0.0, 0.0))
	out[CrewBody.CHEST].basis = Basis.from_euler(Vector3(-0.22, 0.0, 0.0))
	out[CrewBody.NECK].basis = Basis.from_euler(Vector3(-0.35, 0.0, 0.0))
	out[CrewBody.HEAD].basis = Basis.from_euler(Vector3(-0.4 + sway, 0.2, 0.0))
	# One arm dangles toward the floor, the other lies on the chest.
	out[CrewBody.L_ARM].basis = Basis.from_euler(Vector3(1.45 + sway, 0.0, 0.1))
	out[CrewBody.L_FORE].basis = Basis.from_euler(Vector3(-0.15, 0.0, 0.0))
	out[CrewBody.R_ARM].basis = Basis.from_euler(Vector3(-0.3, 0.0, -0.2))
	out[CrewBody.R_FORE].basis = Basis.from_euler(Vector3(-1.5, 0.0, 0.0)) * Basis(Vector3.UP, -0.9)
	for leg in [CrewBody.L_LEG, CrewBody.R_LEG]:
		var s := 1.0 if leg == CrewBody.L_LEG else -1.0
		out[leg].basis = Basis.from_euler(Vector3(-1.3 + 0.08 * s, 0.0, s * 0.1))
		out[leg + 1].basis = Basis.from_euler(Vector3(1.45 - sway * s, 0.0, 0.0))
		out[leg + 2].basis = Basis.from_euler(Vector3(0.5, 0.0, 0.0))
	return out


func _rest_pose() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var J := CrewBody.JOINTS
	for i in bones.size():
		var p := CrewBody.PARENTS[i]
		out.append(Transform3D(Basis.IDENTITY, J[i] - (J[p] if p >= 0 else Vector3.ZERO)))
	return out


## Analytic two-bone IK in the parent's space. Bones point down -Y at rest and the
## lower bone hinges on its local X. bend_sign: +1 knees (bend backward), -1 elbows.
static func _two_bone(root: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float, bend_sign: float) -> Array[Basis]:
	var to := target - root
	var dist := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.9995)
	var dir := to.normalized() if to.length_squared() > 1e-8 else Vector3.DOWN
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-8:
		pp = Vector3.FORWARD.cross(dir)
	pp = pp.normalized()
	var alpha := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var gamma := acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	var u := dir * cos(alpha) + pp * sin(alpha)
	var k := pp.cross(dir).normalized() * bend_sign
	var y := -u
	var z := k.cross(y).normalized()
	var upper := Basis(k, y, z).orthonormalized()
	var lower := Basis(Vector3.RIGHT, bend_sign * (PI - gamma))
	return [upper, lower]
