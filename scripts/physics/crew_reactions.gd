class_name CrewReactions
extends RefCounted
## Physical reactions layered on top of a CrewModel's procedural animation,
## driven from outside the model (it only reads and writes the rig's bone nodes
## and re-uploads the skinning palette):
##
## - stagger(): a shove or a hit. Damped angular springs whip the spine, chest
##   and head and make the arms flail, while the feet take quick catch-balance
##   steps (planted in the world, re-placed by two-bone IK) as the body slides.
## - collapse(): shot / downed. A Jolt ragdoll (CrewRagdoll) falls, settles, then
##   blends into the model's own downed pose.
## - set_dangle(): carried. Arms, legs and head hang and swing (verlet chains)
##   on top of the carried pose; the torso stays animated.
## - space_out(): vented. A copy of the body is ejected as a weightless ragdoll,
##   tumbling, and fades away as a ghost.
##
## Everything here is cosmetic and local to each peer.

const B := preload("res://scripts/art/crew_body.gd")
const RAGDOLL_RANGE := 34.0
const MAX_RAGDOLLS := 4
const ANKLE := 0.09
const STEP_TIME := 0.16
const DANGLE_STEP := 1.0 / 120.0
const GRAVITY := Vector3(0, -9.8, 0)

## bone -> [stiffness, damping, max angle]
const SPRINGS := {
	B.SPINE: [140.0, 9.0, 0.5], B.CHEST: [140.0, 9.0, 0.55], B.NECK: [105.0, 6.0, 0.75],
	B.L_ARM: [55.0, 4.5, 1.25], B.R_ARM: [55.0, 4.5, 1.25], B.L_FORE: [70.0, 5.0, 0.95], B.R_FORE: [70.0, 5.0, 0.95],
}

var avatar: Node3D  # CrewMember
var model: Node3D  # CrewModel
var ragdoll: CrewRagdoll
var hide_body_until := 0  # ms: the avatar stays hidden while its spaced corpse flies

var _root_prev := Vector3.ZERO
var _root_vel := Vector3.ZERO
var _root_ready := false

var _blend_from: Array[Transform3D] = []
var _blend_t := -1.0
var _blend_dur := 0.8

var _st_t := -1.0
var _st_dur := 0.9
var _st_strength := 1.0
var _spring := {}  # bone -> [theta: Vector3, omega: Vector3]
var _st_axis := Vector3.RIGHT
var _st_seed := 0.0
var _feet := []  # [{planted, from, to, t}]
var _floor_y := 0.0

var _dangle := false
var _dangle_ready := false
var _dangle_accum := 0.0
var _anim_pose: Array[Transform3D] = []
var _chains := []  # [{upper, lower, l1, l2, mid, tip, mid_prev, tip_prev}]
var _head := {}


func _init(p_avatar: Node3D, p_model: Node3D) -> void:
	avatar = p_avatar
	model = p_model


func is_ragdolling() -> bool:
	return ragdoll != null and is_instance_valid(ragdoll)


func is_dangling() -> bool:
	return _dangle


func body_hidden() -> bool:
	return Time.get_ticks_msec() < hide_body_until


# --- triggers ----------------------------------------------------------------------------

## Pushed along world `dir`. strength 1 = a shove, ~0.5 = a thrown item.
func stagger(dir: Vector3, strength := 1.0) -> void:
	if is_ragdolling() or _dangle or model == null:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	var local := (model.global_basis.orthonormalized().inverse() * flat.normalized())
	local.y = 0.0
	local = local.normalized()
	_st_axis = Vector3.UP.cross(local).normalized()
	_st_strength = clampf(strength, 0.2, 1.4)
	_st_dur = lerpf(0.55, 0.95, clampf(strength, 0.0, 1.0))
	_st_t = 0.0
	_st_seed = randf() * TAU
	var s := _st_strength
	var kicks := {
		B.SPINE: _st_axis * 5.5 * s,
		B.CHEST: _st_axis * 7.5 * s,
		B.NECK: -_st_axis * 9.0 * s,
		B.L_ARM: (-_st_axis * 5.0 + Vector3(0, 0, 4.5)) * s,
		B.R_ARM: (-_st_axis * 5.0 + Vector3(0, 0, -4.5)) * s,
		B.L_FORE: Vector3(-6.0, 0, 0) * s,
		B.R_FORE: Vector3(-6.0, 0, 0) * s,
	}
	for bone in SPRINGS:
		var current: Array = _spring.get(bone, [Vector3.ZERO, Vector3.ZERO])
		_spring[bone] = [current[0], current[1] + kicks[bone]]
	_floor_y = avatar.global_position.y
	_feet = []
	var xf := _model_xf()
	for side in 2:
		var foot := B.L_FOOT if side == 0 else B.R_FOOT
		var at: Vector3 = model.global_transform * xf[foot].origin
		at.y = _floor_y + ANKLE
		_feet.append({"planted": at, "from": at, "to": at, "t": -1.0})


## Shot / downed: ragdoll collapse along `dir`, landing near `at` (the downed
## position) with the model's downed pose facing `yaw`.
func collapse(dir: Vector3, at: Vector3, yaw: float) -> void:
	if model == null or is_ragdolling() or _dangle or not _in_range():
		return
	_st_t = -1.0
	ragdoll = CrewRagdoll.spawn(model, avatar.get_parent(), _root_vel, true, MAX_RAGDOLLS)
	if ragdoll == null:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else -model.global_basis.z
	ragdoll.impulse(B.CHEST, d * 40.0 + Vector3.UP * 4.0)
	ragdoll.impulse(B.HEAD, d * 4.0)
	ragdoll.impulse(B.HIPS, -d * 7.0)
	ragdoll.impulse(B.L_SHIN, -d * 4.0)
	ragdoll.impulse(B.R_SHIN, -d * 4.0)
	ragdoll.tether = at + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.12)
	ragdoll.tether_strength = 70.0


## Spaced: an ejected, tumbling copy of the body that fades into a ghost.
func space_out(dir: Vector3) -> void:
	if model == null or not model.is_inside_tree():
		return
	end_ragdoll(false)
	set_dangle(false)
	var parent := avatar.get_parent()
	var script: Script = model.get_script()
	var corpse: Node3D = script.call("build", avatar.color, avatar.variant, avatar.number)
	parent.add_child(corpse)
	corpse.global_transform = model.global_transform
	for i in range(model.bones.size()):
		corpse.bones[i].transform = model.bones[i].transform
	if corpse.has_method("set_expression"):
		corpse.set_expression("shocked")
	var rd := CrewRagdoll.spawn(corpse, parent, _root_vel, false, MAX_RAGDOLLS + 4)
	if rd == null:
		corpse.queue_free()
		return
	rd.autonomous = true
	rd.follow_root = true
	rd.weightless()
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.LEFT
	for bone in rd.parts:
		(rd.parts[bone] as RigidBody3D).linear_velocity = d * 10.5 + Vector3.UP * 0.6
	rd.spin(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(3.0, 5.0))
	rd.impulse(B.HEAD, d * 3.0)
	hide_body_until = Time.get_ticks_msec() + 1500
	var fade := corpse.create_tween()
	fade.tween_interval(1.25)
	fade.tween_callback(func():
		if corpse.has_method("set_ghost"):
			corpse.set_ghost(true))
	fade.tween_method(func(a: float):
		var mat := (corpse.get("body") as GeometryInstance3D).material_override as ShaderMaterial if corpse.get("body") is GeometryInstance3D else null
		if mat != null:
			mat.set_shader_parameter("ghost_alpha", a)
		var visor: Variant = corpse.get("visor")
		if visor is GeometryInstance3D:
			(visor as GeometryInstance3D).transparency = 1.0 - a, 1.0, 0.0, 1.4)
	fade.tween_callback(func():
		if is_instance_valid(rd):
			rd.queue_free()
		corpse.queue_free())


func set_dangle(on: bool) -> void:
	if on == _dangle:
		return
	if on:
		end_ragdoll(false)
		_st_t = -1.0
		_dangle = true
		_dangle_ready = false
		_anim_pose.clear()
	else:
		_dangle = false
		_start_blend(0.35)


## Stop a ragdoll; `blend` eases from its last pose back into the animation.
func end_ragdoll(blend: bool) -> void:
	if not is_ragdolling():
		ragdoll = null
		return
	if blend and not ragdoll.is_broken():
		ragdoll.apply_pose()
		_blend_from = ragdoll.capture()
		_blend_t = 0.0
		_blend_dur = 0.9
	ragdoll.queue_free()
	ragdoll = null


func _start_blend(seconds: float) -> void:
	_blend_from.clear()
	for bone in model.bones:
		_blend_from.append(bone.transform)
	_blend_t = 0.0
	_blend_dur = seconds


func _in_range() -> bool:
	if not avatar.is_inside_tree() or not avatar.is_visible_in_tree():
		return false
	if Engine.has_singleton("Net") or avatar.get_tree().root.has_node("Net"):
		var net := avatar.get_tree().root.get_node_or_null("Net")
		if net != null and bool(net.get("dedicated")):
			return false  # a dedicated server shows nothing: skip cosmetic ragdolls
	var camera := avatar.get_viewport().get_camera_3d()
	return camera == null or camera.global_position.distance_to(avatar.global_position) <= RAGDOLL_RANGE


# --- per-frame ---------------------------------------------------------------------------

## Physics rate, right after the model's set_motion(): override bones and upload.
func post_animate(delta: float) -> void:
	if model == null or delta <= 0.0:
		return
	_track_root(delta)
	if ragdoll != null:
		if not is_instance_valid(ragdoll) or ragdoll.is_broken():
			if is_instance_valid(ragdoll):
				ragdoll.queue_free()
			ragdoll = null
		else:
			ragdoll.apply_pose()
			if ragdoll.settled or ragdoll.age > 2.8:
				end_ragdoll(true)
			return
	if _dangle:
		# Remember the fresh animated pose: the render pass layers on top of it.
		_anim_pose.clear()
		for bone in model.bones:
			_anim_pose.append(bone.transform)
		return
	var touched := false
	if _blend_t >= 0.0:
		_apply_blend(delta)
		touched = true
	if _st_t >= 0.0:
		_apply_stagger(delta)
		touched = true
	if touched:
		model._upload()


## Render rate, after the avatar placed its visual: the dangling limbs.
func post_render(delta: float) -> void:
	if not _dangle or model == null or _anim_pose.size() != model.bones.size():
		return
	for i in range(_anim_pose.size()):
		model.bones[i].transform = _anim_pose[i]
	_simulate_dangle(clampf(delta, 0.0, 0.05))
	model._upload()


func _track_root(delta: float) -> void:
	var pos := model.global_position
	if _root_ready:
		var vel := (pos - _root_prev) / delta
		if vel.length() < 40.0:
			_root_vel = _root_vel.lerp(vel, 1.0 - exp(-delta * 18.0))
	_root_prev = pos
	_root_ready = true


func _model_xf() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var bones: Array = model.bones
	for i in range(bones.size()):
		var p: int = B.PARENTS[i]
		out.append((out[p] if p >= 0 else Transform3D.IDENTITY) * bones[i].transform)
	return out


func _apply_blend(delta: float) -> void:
	_blend_t += delta
	var w := smoothstep(0.0, 1.0, clampf(_blend_t / maxf(_blend_dur, 0.01), 0.0, 1.0))
	var bones: Array = model.bones
	if _blend_from.size() == bones.size():
		for i in range(bones.size()):
			bones[i].transform = _blend_from[i].interpolate_with(bones[i].transform, w)
	if _blend_t >= _blend_dur:
		_blend_t = -1.0


func _apply_stagger(delta: float) -> void:
	_st_t += delta
	var t := _st_t
	var w := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(_st_dur - 0.3, _st_dur, t))
	# Springs (two substeps), with a decaying flail torque on the arms.
	var h := delta * 0.5
	var flail := 70.0 * _st_strength * maxf(0.0, 1.0 - t / 0.7)
	for step in 2:
		for bone in _spring:
			var cfg: Array = SPRINGS[bone]
			var state: Array = _spring[bone]
			var theta: Vector3 = state[0]
			var omega: Vector3 = state[1]
			var torque := -theta * float(cfg[0]) - omega * float(cfg[1])
			if bone in [B.L_ARM, B.R_ARM]:
				var side := 1.0 if bone == B.L_ARM else -1.0
				var tt := t + float(step) * h
				torque += (_st_axis * sin(tt * 17.0 + _st_seed + side) + Vector3(0, 0, side) * cos(tt * 13.0 + _st_seed * 2.0)) * flail
			omega += torque * h
			theta += omega * h
			if theta.length() > float(cfg[2]):
				theta = theta.limit_length(float(cfg[2]))
				omega *= 0.5
			_spring[bone] = [theta, omega]
	var xf := _model_xf()
	var bones: Array = model.bones
	for bone in [B.SPINE, B.CHEST, B.NECK, B.L_ARM, B.L_FORE, B.R_ARM, B.R_FORE]:
		var theta: Vector3 = _spring[bone][0] * w
		if theta.length() < 0.0001:
			continue
		var parent_basis: Basis = xf[B.PARENTS[bone]].basis.orthonormalized()
		var turn := Basis(theta.normalized(), theta.length())
		bones[bone].basis = (parent_basis.inverse() * turn * parent_basis * bones[bone].basis).orthonormalized()
	_apply_steps(delta, w)
	if t >= _st_dur:
		_st_t = -1.0
		_spring.clear()


## Catch-balance steps: feet stay planted in the world while the body slides,
## and step (one at a time) when they fall too far behind.
func _apply_steps(delta: float, w: float) -> void:
	if w <= 0.001 or _feet.size() != 2:
		return
	var root: Transform3D = model.global_transform
	var airborne: bool = avatar.global_position.y > _floor_y + 0.12
	var xf := _model_xf()
	var bones: Array = model.bones
	var vel := Vector3(_root_vel.x, 0.0, _root_vel.z).limit_length(7.0)
	var hips: Transform3D = xf[B.HIPS]
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var f: Dictionary = _feet[side]
		var other: Dictionary = _feet[1 - side]
		var neutral: Vector3 = root * Vector3(s * 0.11, ANKLE, 0.02)
		neutral.y = _floor_y + ANKLE
		var goal := neutral + vel * 0.16
		if airborne:
			f.planted = neutral
			f.t = -1.0
			continue
		if f.t < 0.0:
			var behind := Vector2(f.planted.x - goal.x, f.planted.z - goal.z).length()
			if behind > 0.26 and float(other.t) < 0.0:
				f.from = f.planted
				f.to = goal + vel * 0.08
				f.t = 0.0
		else:
			f.t = float(f.t) + delta / STEP_TIME
			f.to = (f.to as Vector3).lerp(goal + vel * 0.08, 0.35)
			if f.t >= 1.0:
				f.planted = f.to
				f.t = -1.0
				if avatar.has_signal("footstep") and vel.length() > 0.8:
					avatar.emit_signal("footstep", f.planted)
		var pos: Vector3 = f.planted
		if f.t >= 0.0:
			var k: float = smoothstep(0.0, 1.0, float(f.t))
			pos = (f.from as Vector3).lerp(f.to, k) + Vector3.UP * 0.13 * sin(PI * float(f.t))
		var thigh := B.L_LEG if side == 0 else B.R_LEG
		var shin := thigh + 1
		var foot := thigh + 2
		var target_model: Vector3 = root.affine_inverse() * pos
		var local_target := hips.affine_inverse() * target_model
		var pole := hips.basis.inverse() * Vector3(s * 0.12, 0.0, 1.0)
		var ik: Array = _two_bone(bones[thigh].position, local_target, pole, 0.425, 0.415, 1.0)
		bones[thigh].basis = Basis(bones[thigh].basis.get_rotation_quaternion().slerp((ik[0] as Basis).get_rotation_quaternion(), w))
		bones[shin].basis = Basis(bones[shin].basis.get_rotation_quaternion().slerp((ik[1] as Basis).get_rotation_quaternion(), w))
		var shin_basis: Basis = hips.basis * bones[thigh].basis * bones[shin].basis
		var flat := shin_basis.inverse() * Basis(Vector3.UP, s * 0.06)
		bones[foot].basis = Basis(bones[foot].basis.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(), w))


# --- dangling (carried) ------------------------------------------------------------------

func _chain_defs() -> Array:
	return [
		[B.L_ARM, B.L_FORE, B.L_HAND, 0.13],
		[B.R_ARM, B.R_FORE, B.R_HAND, 0.13],
		[B.L_LEG, B.L_SHIN, B.L_FOOT, 0.0],
		[B.R_LEG, B.R_SHIN, B.R_FOOT, 0.0],
	]


func _simulate_dangle(delta: float) -> void:
	var root: Transform3D = model.global_transform
	var xf := _model_xf()
	var anim := {}
	for def in _chain_defs():
		var upper: int = def[0]
		var lower: int = def[1]
		var end: int = def[2]
		var root_p: Vector3 = root * xf[upper].origin
		var mid_p: Vector3 = root * xf[lower].origin
		var tip_p: Vector3 = root * xf[end].origin
		if float(def[3]) > 0.0:
			tip_p += (tip_p - mid_p).normalized() * float(def[3])
		anim[upper] = [root_p, mid_p, tip_p]
	var neck: Vector3 = root * xf[B.NECK].origin
	var head_tip: Vector3 = root * (xf[B.HEAD] * Vector3(0, 0.14, 0.02))
	if not _dangle_ready:
		_chains.clear()
		for def in _chain_defs():
			var a: Array = anim[def[0]]
			_chains.append({"upper": def[0], "lower": def[1], "l1": a[0].distance_to(a[1]), "l2": a[1].distance_to(a[2]),
				"mid": a[1], "tip": a[2], "mid_prev": a[1], "tip_prev": a[2]})
		_head = {"tip": head_tip, "prev": head_tip, "len": neck.distance_to(head_tip)}
		_dangle_ready = true
		_dangle_accum = 0.0
	var floor_y: float = avatar.global_position.y
	var carrier: Variant = avatar.get("carrier")
	var axis := Vector3.INF
	if carrier is Node3D and is_instance_valid(carrier):
		axis = (carrier as Node3D).global_position
	_dangle_accum = minf(_dangle_accum + delta, DANGLE_STEP * 6.0)
	while _dangle_accum >= DANGLE_STEP:
		_dangle_accum -= DANGLE_STEP
		for chain in _chains:
			var a: Array = anim[chain.upper]
			var mid: Vector3 = chain.mid
			var tip: Vector3 = chain.tip
			var mid_v: Vector3 = (mid - chain.mid_prev) * 0.985
			var tip_v: Vector3 = (tip - chain.tip_prev) * 0.985
			chain.mid_prev = mid
			chain.tip_prev = tip
			mid += mid_v + GRAVITY * DANGLE_STEP * DANGLE_STEP
			tip += tip_v + GRAVITY * DANGLE_STEP * DANGLE_STEP
			# A little residual tone: drift back towards the carried pose.
			mid = mid.lerp(a[1], 0.03)
			tip = tip.lerp(a[2], 0.015)
			for iteration in 3:
				mid = a[0] + (mid - a[0]).normalized() * float(chain.l1)
				var span := tip - mid
				tip = mid + span.normalized() * float(chain.l2)
				for p in [0, 1]:
					var q: Vector3 = mid if p == 0 else tip
					q.y = maxf(q.y, floor_y + 0.07)
					if axis.is_finite() and q.y < axis.y + 1.5:
						var flat := Vector2(q.x - axis.x, q.z - axis.z)
						if flat.length() < 0.3:
							flat = flat.normalized() * 0.3 if flat.length() > 0.001 else Vector2(0.3, 0)
							q.x = axis.x + flat.x
							q.z = axis.z + flat.y
					if p == 0:
						mid = q
					else:
						tip = q
			chain.mid = mid
			chain.tip = tip
		# The head lolls: a stiffer pendulum around the neck.
		var tip_h: Vector3 = _head.tip
		var vel_h: Vector3 = (tip_h - _head.prev) * 0.96
		_head.prev = tip_h
		tip_h += vel_h + GRAVITY * DANGLE_STEP * DANGLE_STEP
		tip_h = tip_h.lerp(head_tip, 0.08)
		tip_h = neck + (tip_h - neck).normalized() * float(_head.len)
		_head.tip = tip_h
	_pose_dangle(root, xf, anim, neck, head_tip)


func _pose_dangle(root: Transform3D, xf: Array[Transform3D], anim: Dictionary, neck: Vector3, head_anim: Vector3) -> void:
	var bones: Array = model.bones
	var root_basis := root.basis.orthonormalized()
	for chain in _chains:
		var upper: int = chain.upper
		var lower: int = chain.lower
		var a: Array = anim[upper]
		var parent_world: Basis = root_basis * xf[B.PARENTS[upper]].basis
		var upper_world: Basis = root_basis * xf[upper].basis
		var turn := _arc((a[1] - a[0]), (chain.mid as Vector3) - a[0])
		var new_upper := (turn * upper_world).orthonormalized()
		bones[upper].basis = (parent_world.inverse() * new_upper).orthonormalized()
		var lower_world: Basis = new_upper * bones[lower].basis
		var anim_lower_dir: Vector3 = turn * (a[2] - a[1])
		var turn2 := _arc(anim_lower_dir, (chain.tip as Vector3) - (chain.mid as Vector3))
		bones[lower].basis = (new_upper.inverse() * (turn2 * lower_world)).orthonormalized()
	var turn_h := _arc(head_anim - neck, (_head.tip as Vector3) - neck)
	var half := Basis(Quaternion.IDENTITY.slerp(turn_h.get_rotation_quaternion(), 0.5))
	var chest_world: Basis = root_basis * xf[B.CHEST].basis
	var neck_world: Basis = root_basis * xf[B.NECK].basis
	var new_neck := (half * neck_world).orthonormalized()
	bones[B.NECK].basis = (chest_world.inverse() * new_neck).orthonormalized()
	var head_world: Basis = root_basis * xf[B.HEAD].basis
	bones[B.HEAD].basis = (new_neck.inverse() * (turn_h * head_world)).orthonormalized()


## Shortest rotation taking direction `from` to direction `to`.
static func _arc(from: Vector3, to: Vector3) -> Basis:
	if from.length_squared() < 1e-8 or to.length_squared() < 1e-8:
		return Basis.IDENTITY
	var a := from.normalized()
	var b := to.normalized()
	var axis := a.cross(b)
	var d := clampf(a.dot(b), -1.0, 1.0)
	if axis.length_squared() < 1e-10:
		return Basis.IDENTITY if d > 0.0 else Basis(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT, PI)
	return Basis(axis.normalized(), acos(d))


## Analytic two-bone IK in the parent's space (same convention as the rig:
## bones point down -Y at rest, the lower bone hinges on its local X;
## bend_sign +1 for knees). Kept here so this layer never depends on the
## model script's internals.
static func _two_bone(root: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float, bend_sign: float) -> Array:
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
	return [Basis(k, y, z).orthonormalized(), Basis(Vector3.RIGHT, bend_sign * (PI - gamma))]
