class_name CrewModel
extends Node3D
## Hero crew member: procedural EVA suit on a Node3D pivot rig, GPU-skinned in a
## single draw call (plus the visor), with fully procedural animation.
##
## Origin at the feet, forward = +Z, character's left = +X. No extra rotation needed.
## Gameplay calls set_motion() every frame; overlays and states are optional.

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
const ANKLE_H := 0.09

var color := Color.WHITE
## Where a carried object sits (between the hands, ~0.95 m up, ~0.45 m forward).
var carry_anchor: Node3D
## Child of the right hand at the palm. +Z = barrel direction when aiming, +Y = up.
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

# Animation state.
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
var _lamp := 0.3
var _lamp_target := 0.3
var _last_params := {}
var _front := 0.8  # share of the stance spent ahead of the hip (x reach)
var _comp := 0.0  # mid-stance compression (running)


static func build(p_color: Color) -> CrewModel:
	var m := CrewModel.new()
	m._setup(p_color)
	return m


func _setup(p_color: Color) -> void:
	color = p_color
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
	body.mesh = CrewBody.body_mesh()
	body.material_override = _suit_mat
	body.custom_aabb = AABB(Vector3(-1.1, -0.3, -1.1), Vector3(2.2, 2.5, 2.2))
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
	hand_anchor.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.006, -0.055, 0.008))
	bones[CrewBody.R_HAND].add_child(hand_anchor)
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
		if _shove_t > 0.35:
			_shove_t = -1.0
	if _hit_t >= 0.0:
		_hit_t += delta
		if _hit_t > 0.7:
			_hit_t = -1.0
	var g := _gait(_speed)
	if _speed > 0.02:
		_phase = fposmod(_phase + _speed / g.z * delta, 1.0)
	_pose(g)
	_upload()


func play_shove() -> void:
	_shove_t = 0.0


func play_hit() -> void:
	_hit_t = 0.0
	_hit_side = -1.0 if randf() < 0.5 else 1.0


func set_flashlight_on(on: bool) -> void:
	_lamp_target = 7.0 if on else 0.3


func set_downed(on: bool) -> void:
	_down = on
	if not on:
		_carried = false


func set_carried(on: bool) -> void:
	_carried = on
	if on:
		_down = true
		_down_t = 0.4


func set_ghost(on: bool) -> void:
	_ghost = on
	if on and _ghost_mat == null:
		_ghost_mat = CrewMaterials.instance("ghost", color)
		_ghost_visor_mat = CrewMaterials.instance("ghost_visor", color)
	body.material_override = _ghost_mat if on else _suit_mat
	visor.material_override = _ghost_visor_mat if on else _visor_mat
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.cast_shadow = shadow
	visor.cast_shadow = shadow
	_last_params.clear()


func set_aiming(on: bool) -> void:
	_aiming = on


func is_ghost() -> bool:
	return _ghost


func _process(delta: float) -> void:
	_lamp = move_toward(_lamp, _lamp_target, delta * 30.0)
	var flash := 0.0
	if _hit_t >= 0.0:
		flash = clampf(1.0 - _hit_t / 0.22, 0.0, 1.0)
	_set_param("lamp_energy", _lamp)
	_set_param("hit_flash", flash * flash)
	_set_param("distress", _down_w)
	if _visor_mat != null:
		var glitch := maxf(_stun_w, flash * 0.8)
		if _last_params.get("glitch", -1.0) != glitch:
			_last_params["glitch"] = glitch
			_visor_mat.set_shader_parameter("glitch", glitch)
	if not _driven:
		_upload()  # legacy callers swing the limb pivots directly
	_driven = false


func _set_param(key: String, value: float) -> void:
	if is_equal_approx(_last_params.get(key, -999.0), value):
		return
	_last_params[key] = value
	_suit_mat.set_shader_parameter(key, value)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter(key, value)


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


# --- animation ----------------------------------------------------------------------

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


## Foot path for a local phase p: (z offset, height, pitch(+ = toes down), unused).
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

	# Overlay envelopes.
	var hit := 0.0
	if _hit_t >= 0.0:
		hit = _hit_t / 0.05 if _hit_t < 0.05 else exp(-(_hit_t - 0.05) * 6.0)
	var shove := 0.0
	var thrust := 0.0
	if _shove_t >= 0.0:
		shove = smoothstep(0.0, 0.05, _shove_t) * (1.0 - smoothstep(0.22, 0.35, _shove_t))
		thrust = smoothstep(0.07, 0.15, _shove_t)

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
	hips_pos.z += 0.04 * thrust * shove - 0.07 * hit
	hips_pos.y -= 0.05 * hit + 0.06 * stun * (0.6 + 0.4 * sin(t * 4.1))
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
	var lean := 0.05 * mw + 0.2 * rw + 0.06 * _carry_w * (1.0 - _aim_w) + 0.22 * thrust * shove - 0.35 * hit
	var counter := yaw_amp * 1.55 * cos(cyc)
	var aim_twist := 0.18 * _aim_w
	B[CrewBody.SPINE].basis = Basis.from_euler(Vector3(lean * 0.5 + stun * 0.15 * sin(t * 3.0), counter * 0.45 + aim_twist * 0.4, -hips_rot.z * 0.6 + stun * 0.1 * sin(t * 2.7)))
	B[CrewBody.CHEST].basis = Basis.from_euler(Vector3(lean * 0.5 + 0.018 * breath * (1.0 - mw) - 0.15 * hit + stun * 0.1 * sin(t * 3.4 + 1.0),
		counter * 0.55 + aim_twist * 0.6 + 0.2 * hit * _hit_side, -hips_rot.z * 0.3 + 0.18 * hit * _hit_side))

	# --- head stabilisation (keeps the visor level and facing forward) ---
	var neck_xf := _root_xf(CrewBody.CHEST) * B[CrewBody.NECK].transform
	var look := Basis.from_euler(Vector3(-0.05 * rw + 0.06 * _carry_w - 0.45 * hit, -aim_twist * 0.2, 0.0))
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

	# --- arms: FK swing, blended with IK for carry / aim / shove ---
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
		fk_up = Basis.from_euler(Vector3(-0.35 * _air_w - 0.5 * hit, 0.0, s * (0.55 * _air_w + 0.35 * hit))) * fk_up
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
		var aim_t := Vector3(-0.055, 1.36, 0.5) if side == 1 else Vector3(-0.015, 1.315, 0.43)
		var shove_t := Vector3(s * 0.13, 1.24, 0.16).lerp(Vector3(s * 0.15, 1.28, 0.56), thrust)
		var cw := _carry_w
		var aw := _aim_w
		var sw := shove * 4.0
		var total := cw + aw + sw
		var ik_w := clampf(maxf(cw, maxf(aw, shove)), 0.0, 1.0) * (1.0 - stun) * (1.0 - _ghost_w)
		var up_b := fk_up
		var fore_b := fk_fore
		var hand_b := Basis.from_euler(Vector3(-0.1 - 0.15 * mw, 0.0, 0.0))
		if ik_w > 0.001 and total > 0.0:
			var target2 := (carry_t * cw + aim_t * aw + shove_t * sw) / total
			var lt := chest_xf.affine_inverse() * target2
			var pole2 := chest_xf.basis.inverse() * Vector3(s * 0.8, -0.6, -0.5)
			var ik2 := _two_bone(B[up].position, lt, pole2, 0.295, 0.27, -1.0)
			up_b = Basis(fk_up.get_rotation_quaternion().slerp(ik2[0].get_rotation_quaternion(), ik_w))
			fore_b = Basis(fk_fore.get_rotation_quaternion().slerp(ik2[1].get_rotation_quaternion(), ik_w))
			var wrist := Basis.from_euler(Vector3(-1.1 * thrust * shove / maxf(ik_w, 0.01), 0.0, s * 0.15 * cw))
			hand_b = Basis(hand_b.get_rotation_quaternion().slerp(wrist.get_rotation_quaternion(), ik_w))
		B[up].basis = up_b
		B[fore].basis = fore_b
		B[hand].basis = hand_b
		B[up].position.y += 0.004 * breath * (1.0 - mw)

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
	out[CrewBody.HIPS] = Transform3D(Basis.from_euler(Vector3(-PI * 0.5 + 0.06, 0.0, 0.0)) * Basis(Vector3.UP, 0.42), Vector3(0.0, 0.12, -0.12))
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
