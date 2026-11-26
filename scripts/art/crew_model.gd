class_name CrewModel
extends Node3D
## Hero crew member: procedural EVA suit on a Node3D pivot rig, GPU-skinned in a
## single draw call (plus the LED-face visor), with fully procedural animation.
##
## Origin at the feet, forward = +Z, character's left = +X. No extra rotation needed.
## Gameplay calls set_motion() every frame; overlays and states are optional.
##
## Acting API (all blendable, deterministic under set_motion(..., delta); see
## docs/trailer/production-plan.md section 1):
##   set_expression(name, hold, blend, glitch)  LED face + body language + visor mood
##   set_look_target(target, head_weight)       head and eyes (eyes lead), chest follows
##   play_head("nod" | "shake", strength)
##   set_reach(side, target, weight, glove, palm)  fingertip (or palm) onto a world point
##   set_gesture(name, weight, target) / play_gesture(name, target)  (GESTURES)
##   set_performance(name, blend)               one held gesture, the others released
##   play_hit(source), play_stagger(source, strength), play_draw(), play_get_up()
##   set_aiming(on, height), set_trigger(amount), on_shot()
##   set_tension(amount), set_lights(visor, trim, lamp), set_visor_glint(...),
##   set_frost(amount), set_wear(amount), take_root_motion()

## Emitted when a foot plants (0 = left, 1 = right), for footstep audio / dust.
signal footstep(side: int)
## Emitted on each contact of a gesture (helmet_tap: index 0 at 0.30 s, 1 at 0.52 s).
signal gesture_beat(gesture: String, index: int)

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
const ANKLE_H := 0.09
## Gun recoil kick duration (s) and the shove wrist extension (rad).
const RECOIL_TIME := 0.16
const SHOVE_WRIST := -0.75
## Where the gun grip sits while aiming (root space) and the support hand offset
## from it (gun space).
const AIM_GRIP := Vector3(-0.075, 1.36, 0.47)
const AIM_SUPPORT := Vector3(0.055, -0.035, -0.035)
## Low ready (set_aiming height 0): grip lower and closer, muzzle at the floor ahead.
const LOW_GRIP := Vector3(-0.1, 1.08, 0.36)
const LOW_PITCH := 0.95
## Held gestures (set_gesture / set_performance). They layer over set_motion's
## locomotion (point, surrender, reach, lunge_reach, brace can walk or run) and
## combine with any expression.
const HELD_GESTURES: Array[String] = ["surrender", "point", "pound", "press_glass", "reach", "lunge_reach", "brace",
	"dragged", "ghost_drift", "victory", "defeat", "slump"]
## One-shot gestures (play_gesture) and their lengths (s).
const ONE_SHOTS := {"wave": 2.0, "thumbs_up": 1.3, "helmet_tap": 0.9, "step_back": 0.9}
## Every gesture name.
const GESTURES: Array[String] = ["surrender", "point", "pound", "press_glass", "reach", "lunge_reach", "brace",
	"dragged", "ghost_drift", "victory", "defeat", "slump", "wave", "thumbs_up", "helmet_tap", "step_back"]
## Older name for the held gestures (set_performance).
const PERFORMANCES := HELD_GESTURES
## One-shot timings (s).
const DRAW_TIME := 0.5
const STAGGER_TIME := 1.2
const GET_UP_TIME := 1.2
const TEAR_TIME := 0.1
## helmet_tap contacts (s from the start).
const TAP_BEATS: Array[float] = [0.3, 0.52]
## step_back length (m, backward): kept as root motion until take_root_motion().
const STEP_BACK := 0.32
## Arm length shoulder -> wrist (m).
const ARM_LEN := 0.565
## Where a dragged body's raised right wrist is held (root space, "dragged" pose).
const DRAG_HANDLE := Vector3(-0.12, 0.72, 0.9)
## Body language per expression, so moods read in silhouette at 4-8 m: head
## (pitch + = down, yaw + = toward the character's left, roll) and chest offsets (rad),
## shoulder shrug and crouch (m), hips lean (m, + = forward), an arm set, glove pose,
## eye offset on the visor (m, + = character's left) and tremble. Head and chest tells
## stay (at half strength) while walking; arm sets and crouch fade out when moving,
## carrying or aiming.
const _BODY := {
	"happy": {"head": Vector3(-0.14, 0.0, 0.16), "chest": Vector3(-0.07, 0.0, 0.0), "arms_out": 0.1, "bounce": 1.0, "gloves": "open"},
	"shocked": {"head": Vector3(-0.2, 0.0, 0.0), "chest": Vector3(-0.16, 0.0, 0.0), "lean": -0.04, "crouch": 0.03, "shrug": 0.02, "arms": "startle"},
	"angry": {"head": Vector3(0.22, 0.0, 0.0), "chest": Vector3(0.14, 0.0, 0.0), "lean": 0.03, "crouch": 0.02, "shrug": 0.03, "arms": "fists"},
	"suspicious": {"head": Vector3(0.12, 0.34, 0.2), "chest": Vector3(0.02, -0.14, 0.0), "arms": "cross", "look": Vector2(-0.045, 0.0)},
	"hurt": {"head": Vector3(0.28, 0.0, 0.12), "chest": Vector3(0.26, 0.1, 0.1), "crouch": 0.05, "arms": "clutch"},
	"scared": {"head": Vector3(0.12, 0.0, 0.0), "chest": Vector3(0.06, 0.0, 0.0), "crouch": 0.06, "shrug": 0.04, "lean": -0.03, "arms": "cower", "tremble": 1.0},
	"sad": {"head": Vector3(0.42, 0.0, 0.06), "chest": Vector3(0.2, 0.0, 0.0), "crouch": 0.02, "shrug": -0.02, "arms_fwd": 0.12, "gloves": "limp"},
	"smug": {"head": Vector3(-0.06, -0.2, -0.16), "chest": Vector3(-0.04, 0.12, 0.0), "arms": "akimbo", "look": Vector2(0.03, 0.0)},
	"pleading": {"head": Vector3(0.04, 0.0, 0.14), "chest": Vector3(0.06, 0.0, 0.0), "shrug": 0.03, "arms": "plead", "tremble": 0.4},
}
## Goal spaces and priorities (see _layers).
enum { SPACE_ROOT, SPACE_CHEST, SPACE_HEAD }
enum { PRI_BODY, PRI_GESTURE, PRI_REACH }

var color := Color.WHITE
var variant := 0
var number := 0
## Where a carried object sits (between the hands, ~0.95 m up, ~0.46 m forward).
var carry_anchor: Node3D
## The right glove's gun grip node: parent the gun here with an identity transform.
## +Z = barrel (canted 14 degrees from the fingers, levelled while aiming), +Y = up.
var hand_anchor: Node3D
## Gloves (CrewHand) on the LeftHand / RightHand bones: [left, right].
var hands: Array[CrewHand] = []
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
var _rng := RandomNumberGenerator.new()

# Locomotion and state weights.
var _driven := false
var _time := 0.0
var _dt := 1.0 / 60.0
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
var _aim_height := 1.0
var _aim_h := 1.0
var _down_t := 0.0
var _shove_t := -1.0
var _hit_t := -1.0
var _hit_side := 1.0
var _hit_push := Vector3(0, 0, -1)
var _front := 0.8  # share of the stance spent ahead of the hip (x reach)
var _comp := 0.0  # mid-stance compression (running)
var _breath_ph := 0.0

# Face.
var _expr := 0
var _expr_prev := 0
var _expr_mix := 1.0
var _expr_blend := 0.12
var _expr_hold := 0.0
var _expr_base := 0
var _tear_t := -1.0
var _tear_id := 0
var _tear_hold := 0.0
var _blink := 0.0
var _blink_t := -1.0
var _blink_timer := 3.0
var _look := Vector2.ZERO
var _saccade := Vector2.ZERO
var _saccade_timer := 1.5
var _last_yaw := 0.0
var _yaw_rate := 0.0
# Visor mood: LED tint (a = amount), brightness gain, glass wash, sweep, dimmers.
var _tint := Color(1, 1, 1, 0)
var _gain := 1.0
var _wash := 0.0
var _sweep_t := -1.0
var _light_visor := 1.0
var _light_trim := 1.0
var _light_lamp := 1.0
var _glint_pos := PackedVector4Array([Vector4.ZERO, Vector4.ZERO])
var _glint_col := PackedVector4Array([Vector4.ZERO, Vector4.ZERO])

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
var _dangle := PackedFloat32Array([0, 0, 0, 0, 0, 0])  # head, arm, legs (+ velocities)
var _sole := Vector2.ZERO
var _vent := 0.0
var _oxygen := 1.0
var _fidget_timer := 7.0
var _fidget_t := -1.0
var _fidget_kind := 0
var _lamp := 0.3
var _lamp_target := 0.3
var _held := ""
var _recoil_t := -1.0
var _hand_pose: Array[String] = ["", ""]
var _last_params := {}

# Acting.
var _att_w := PackedFloat32Array()  # body-language weight per expression
var _gest_w := {}  # held gesture -> eased weight
var _gest_goal := {}  # held gesture -> requested weight
var _gest_t := {}  # held gesture -> seconds since raised
var _gest_target := {}  # gesture -> world target (Vector3 or Node3D)
var _gest_rate := 6.0
var _shots := {}  # one-shot gesture -> elapsed seconds
var _reach: Array[Dictionary] = [{}, {}]
var _look_target: Variant = null
var _look_hw := 1.0
var _look_w := 0.0
var _look_want := Vector2.ZERO
var _head_s := Vector2.ZERO
var _eye_s := Vector2.ZERO
var _nod_t := -1.0
var _nod_k := 1.0
var _shake_t := -1.0
var _shake_k := 1.0
var _tension := 0.0
var _tension_s := 0.0
var _draw_t := -1.0
var _stagger_t := -1.0
var _stagger_push := Vector3(0, 0, -1)  # local direction the body is pushed
var _stagger_k := 1.0
var _getup_t := -1.0
var _root_motion := Vector3.ZERO
var _tremble := 0.0
var _glove_votes: Array[Dictionary] = [{}, {}]


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
	# Seeded per suit, so blinks, glances and fidgets repeat frame for frame in renders.
	_rng.seed = hash("%s:%d:%d" % [p_color.to_html(), variant, p_number])
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
	for side in [-1, 1]:
		var glove := CrewHand.build(color, side)
		glove.name = "LeftGlove" if side < 0 else "RightGlove"
		bones[CrewBody.L_HAND if side < 0 else CrewBody.R_HAND].add_child(glove)
		hands.append(glove)
	hand_anchor = hands[1].grip_node("gun")
	set_number(p_number)
	_att_w.resize(CrewMaterials.EXPRESSIONS.size())
	_att_w[0] = 1.0
	_blink_timer = _rng.randf_range(2.0, 4.5)
	_fidget_timer = _rng.randf_range(6.0, 10.0)
	_upload()


# --- public API ---------------------------------------------------------------------

func set_motion(speed: float, on_floor: bool, carrying: bool, stunned: bool, delta: float) -> void:
	_driven = true
	delta = clampf(delta, 0.0, 0.1)
	_dt = delta
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
	_aim_h = move_toward(_aim_h, _aim_height, delta * 4.0)
	_carried_w = move_toward(_carried_w, 1.0 if _carried else 0.0, delta * 4.0)
	_ghost_w = move_toward(_ghost_w, 1.0 if _ghost else 0.0, delta * 2.0)
	if _getup_t >= 0.0:
		_getup_t += delta
		_down_w = 1.0 - smoothstep(0.08, 0.7, _getup_t)
		_down_t = 0.4 * _down_w
		if _getup_t > GET_UP_TIME:
			_getup_t = -1.0
	else:
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
	if _recoil_t >= 0.0:
		_recoil_t += delta
		if _recoil_t > RECOIL_TIME:
			_recoil_t = -1.0
	if _draw_t >= 0.0:
		_draw_t += delta
		if _draw_t > DRAW_TIME:
			_draw_t = -1.0
	if _stagger_t >= 0.0:
		_stagger_t += delta
		if _stagger_t > STAGGER_TIME:
			_stagger_t = -1.0
	_step_acting(delta)
	_update_fidget(delta)
	var g := _gait(_speed)
	if _held == "body":
		g = Vector3(g.x * 0.78, g.y, g.z * 0.78)  # short, heavy stride under a body
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
	_breath_ph = fposmod(_breath_ph + TAU * lerpf(0.27, 0.7, _tension_s) * delta, TAU * 100.0)
	_pose(g)
	_springs(delta)
	_update_hands(delta)
	_upload()


func play_shove() -> void:
	_shove_t = 0.0


## A strong flinch that reads as being shot: snap back, arms jerk up, red rim flash.
## Pass the shooter's (or impact's) world position to snap away from it; without it
## the body snaps backward and twists to a random (seeded) side.
func play_hit(source := Vector3.INF) -> void:
	_hit_t = 0.0
	_hit_side = -1.0 if _rng.randf() < 0.5 else 1.0
	_hit_push = _push_from(source)
	if source.is_finite() and absf(_hit_push.x) > 0.2:
		_hit_side = signf(_hit_push.x)


## Knocked off balance (shove, blast, being barged): the torso reels away from
## `source` (world point; omitted = from the front), arms windmill, the knees buckle
## and the foot on the falling side takes a catch step, then the body recovers over
## STAGGER_TIME. `strength` 0.2 .. 1.6 scales it.
func play_stagger(source := Vector3.INF, strength := 1.0) -> void:
	_stagger_t = 0.0
	_stagger_push = _push_from(source)
	_stagger_k = clampf(strength, 0.2, 1.6)


## Draw the gun from the right-thigh holster up into the aim (DRAW_TIME s); leaves the
## model aiming (set_aiming(false) lowers it). Parent the gun to hand_anchor first.
func play_draw() -> void:
	_draw_t = 0.0
	_aiming = true
	_held = "gun"


## From downed to standing in GET_UP_TIME s: onto one knee with a hand pushing off
## the floor, then up. The visor flickers back to life over the last second.
func play_get_up() -> void:
	_down = false
	_carried = false
	_getup_t = 0.0


func set_flashlight_on(on: bool) -> void:
	_lamp_target = 7.0 if on else 0.3


func set_downed(on: bool) -> void:
	_down = on
	if on:
		_getup_t = -1.0
	else:
		_carried = false
	_auto_expression()


func set_carried(on: bool) -> void:
	_carried = on
	if on:
		_down = true
		_down_t = 0.4
		_getup_t = -1.0
	_auto_expression()


func set_ghost(on: bool) -> void:
	_ghost = on
	if on and _ghost_mat == null:
		_ghost_mat = CrewMaterials.instance("ghost", color)
		_ghost_visor_mat = CrewMaterials.instance("ghost_visor", color)
		_ghost_mat.set_shader_parameter("decal_number", number)
		_ghost_mat.set_shader_parameter("accent_energy", 3.2 * _light_trim)
		_apply_visor_uniforms(_ghost_visor_mat)
	body.material_override = _ghost_mat if on else _suit_mat
	visor.material_override = _ghost_visor_mat if on else _visor_mat
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.cast_shadow = shadow
	visor.cast_shadow = shadow
	for glove in hands:
		glove.mesh_instance.cast_shadow = shadow
	_last_params.clear()
	_auto_expression()


## Aim the held gun. `height` 1 = levelled at the look target (or straight ahead),
## 0 = low ready (muzzle at the floor ahead); it eases over 0.25 s.
func set_aiming(on: bool, height := 1.0) -> void:
	_aiming = on
	_aim_height = clampf(height, 0.0, 1.0)


## Held trigger squeeze on the right glove, 0 (resting) .. 1 (pulled): animate it over
## a few frames before on_shot() for a visible squeeze.
func set_trigger(amount: float) -> void:
	hands[1].set_trigger(amount)


## What the character holds: "" (nothing), "cell", "core", "gun" or "body". Carried
## items ("cell" / "core") are gripped by their handles at carry_anchor while
## set_motion's `carrying` is true (an unspecified carry grips like "cell"); "gun" sits
## in the right glove at hand_anchor; "body" carries a crewmate (set_carried) across
## both forearms, leaning back on a short, heavy stride.
func set_held_item(kind: String) -> void:
	_held = kind


## Call on every shot: trigger squeeze on the right glove and a recoil kick.
func on_shot() -> void:
	hands[1].trigger_pull()
	_recoil_t = 0.0


func is_ghost() -> bool:
	return _ghost


## LED face (CrewMaterials.EXPRESSIONS): "neutral" (blinks), "happy", "shocked",
## "angry", "suspicious", "hurt", "downed", "ghost", "scared", "sad", "smug",
## "pleading". Each also sets the visor's mood colour and the body language. With
## hold > 0 it returns to the base face after `hold` seconds. `blend` is the face
## cross-fade time; `glitch` tears the visor into static for TEAR_TIME (three
## frames at 30 fps) and then cuts to the new face.
func set_expression(expression: String, hold := 0.0, blend := 0.12, glitch := false) -> void:
	var id := CrewMaterials.EXPRESSIONS.find(expression)
	if id < 0:
		push_warning("CrewModel: unknown expression " + expression)
		return
	if hold <= 0.0:
		_expr_base = id
	if glitch:
		_tear_t = 0.0
		_tear_id = id
		_tear_hold = hold
		return
	_expr_blend = maxf(blend, 0.0)
	if hold > 0.0:
		_expr_hold = hold
	else:
		_expr_hold = 0.0
	_show_expression(id)


func get_expression() -> String:
	return CrewMaterials.EXPRESSIONS[_tear_id if _tear_t >= 0.0 else _expr]


## Player number 1..8 on the pauldrons, back plate and name plate (0 = crew emblem).
func set_number(n: int) -> void:
	number = clampi(n, 0, 9)
	_suit_mat.set_shader_parameter("decal_number", number)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter("decal_number", number)


## Head and eyes follow `target` (a world Vector3, or a Node3D tracked every frame;
## a CrewModel is looked at in the visor); null returns to idle. Head yaw up to 70
## and pitch up to 30 degrees, eased; past 45 degrees the chest turns a third of the
## way. The eyes lead the head (about three frames) and overshoot by 10%. While
## aiming, the gun follows the look target too.
func set_look_target(target: Variant, head_weight := 1.0) -> void:
	if target is Vector3 or target is Node3D:
		_look_target = target
		_look_hw = clampf(head_weight, 0.0, 1.0)
	else:
		_look_target = null


## Older name: set_look_target(world_point).
func set_focus(world_point: Vector3) -> void:
	set_look_target(world_point)


func clear_focus() -> void:
	set_look_target(null)


## "nod": one dip of 14 degrees over 0.5 s; "shake": three swings of 18 degrees over
## 0.9 s. `strength` scales the angle.
func play_head(kind: String, strength := 1.0) -> void:
	match kind:
		"nod":
			_nod_t = 0.0
			_nod_k = strength
		"shake":
			_shake_t = 0.0
			_shake_k = strength
		_:
			push_warning("CrewModel: unknown head gesture " + kind)


## Arm reach: put the middle fingertip of glove `side` (0 left, 1 right) on the world
## point `target` (with `palm`, a world direction the palm should face, the palm
## centre lands there instead, e.g. pressing a cell home). Overrides carry, aim and
## gestures on that arm by `weight` (0 releases; animate it for a smooth move).
## `glove` is the glove pose to ease into (above weight 0.5), "" keeps the current.
## Beyond arm's length the chest leans up to 12 degrees and the shoulder reaches.
func set_reach(side: int, target: Vector3, weight: float, glove := "", palm := Vector3.ZERO) -> void:
	var i := clampi(side, 0, 1)
	_reach[i] = {"target": target, "w": clampf(weight, 0.0, 1.0), "glove": glove, "palm": palm}


## World position of glove `side`'s middle fingertip (for checks and placement).
func get_fingertip(side: int) -> Vector3:
	var h := hands[clampi(side, 0, 1)]
	var tip := h.get_fingertip(2)
	return h.global_transform * tip if h.is_inside_tree() else _root_xf(CrewBody.L_HAND if side == 0 else CrewBody.R_HAND) * tip


## Held gesture (HELD_GESTURES) to `weight` (eased over ~0.17 s; 0 releases), with an
## optional world target (Vector3 or Node3D) for point, pound, press_glass, reach and
## lunge_reach (otherwise the look target, otherwise straight ahead). A one-shot name
## plays it (weight > 0).
func set_gesture(gesture: String, weight := 1.0, target: Variant = null) -> void:
	if ONE_SHOTS.has(gesture):
		if weight > 0.0:
			play_gesture(gesture, target)
		return
	if not HELD_GESTURES.has(gesture):
		push_warning("CrewModel: unknown gesture " + gesture)
		return
	if not _gest_w.has(gesture) or float(_gest_goal.get(gesture, 0.0)) <= 0.0:
		_gest_t[gesture] = 0.0
	_gest_goal[gesture] = clampf(weight, 0.0, 1.0)
	if not _gest_w.has(gesture):
		_gest_w[gesture] = 0.0
	if target is Vector3 or target is Node3D:
		_gest_target[gesture] = target
	_gest_rate = 6.0


## Play a one-shot gesture (ONE_SHOTS: wave, thumbs_up, helmet_tap, step_back), or
## raise a held one to full weight. helmet_tap emits gesture_beat on its two contacts;
## step_back leaves the body STEP_BACK m behind its origin (take_root_motion()).
func play_gesture(gesture: String, target: Variant = null) -> void:
	if ONE_SHOTS.has(gesture):
		_shots[gesture] = 0.0
		if target is Vector3 or target is Node3D:
			_gest_target[gesture] = target
	else:
		set_gesture(gesture, 1.0, target)


func get_gesture_weight(gesture: String) -> float:
	if _shots.has(gesture):
		return 1.0
	return float(_gest_w.get(gesture, 0.0))


## Hold one gesture from HELD_GESTURES ("" = none) and release every other, blended
## over `blend` seconds (0 snaps).
func set_performance(perf_name: String, blend := 0.3) -> void:
	if perf_name != "" and not HELD_GESTURES.has(perf_name):
		push_warning("CrewModel: unknown performance " + perf_name)
		return
	for key: String in _gest_goal:
		_gest_goal[key] = 0.0
	if perf_name != "":
		set_gesture(perf_name, 1.0)
	_gest_rate = 1.0 / blend if blend > 0.0 else 1000.0
	if blend <= 0.0:
		for key: String in _gest_goal:
			_gest_w[key] = _gest_goal[key]


func get_performance() -> String:
	var best := ""
	var best_w := 0.0
	for key: String in _gest_goal:
		if float(_gest_goal[key]) > best_w:
			best = key
			best_w = _gest_goal[key]
	return best


## The local offset (m) the body has walked away from its origin with step_back.
## Returns it and resets it: move the node by `basis * offset` in the same frame.
func take_root_motion() -> Vector3:
	var m := _root_motion
	_root_motion = Vector3.ZERO
	return m


## 0 calm .. 1 frightened stiff: faster, deeper breathing, raised shoulders,
## half-closed gloves and a fine head tremor.
func set_tension(amount: float) -> void:
	_tension = clampf(amount, 0.0, 1.0)


## Dimmers (0..1, 1 = normal) for the LED face, the suit's glowing trim (accents,
## status lights, pack number, soles) and the helmet lamp. All 0 = a dark silhouette.
func set_lights(visor_level := 1.0, trim := 1.0, lamp := 1.0) -> void:
	_light_visor = maxf(visor_level, 0.0)
	_light_trim = maxf(trim, 0.0)
	_light_lamp = maxf(lamp, 0.0)
	var energy := 3.2 * _light_trim
	_suit_mat.set_shader_parameter("accent_energy", energy)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter("accent_energy", energy)
	for glove in hands:
		glove.set_suit_param("accent_energy", energy)
	_apply_visor_uniforms(_visor_mat)
	if _ghost_visor_mat != null:
		_apply_visor_uniforms(_ghost_visor_mat)


## A soft highlight on the visor where a light at `world_pos` would reflect (index 0
## or 1), in `color` (alpha = strength, 0 turns it off); `size` ~0.05 (pin-point) ..
## 0.3 (broad). For off-screen lights: the core's cyan, a strobe, a muzzle flash.
func set_visor_glint(index: int, world_pos: Vector3, glint_color: Color, size := 0.12) -> void:
	var i := clampi(index, 0, 1)
	_glint_pos[i] = Vector4(world_pos.x, world_pos.y, world_pos.z, size)
	_glint_col[i] = Vector4(glint_color.r, glint_color.g, glint_color.b, glint_color.a)
	_apply_visor_uniforms(_visor_mat)
	if _ghost_visor_mat != null:
		_apply_visor_uniforms(_ghost_visor_mat)


## A bright streak sweeps across the visor (also plays on angry, suspicious, smug and
## shocked faces).
func play_visor_sweep() -> void:
	_sweep_t = 0.0


## Frost creeping in from the visor rim, 0..1 (after the airlock).
func set_frost(amount: float) -> void:
	var v := clampf(amount, 0.0, 1.0)
	_visor_mat.set_shader_parameter("frost", v)
	if _ghost_visor_mat == null:
		_ghost_visor_mat = CrewMaterials.instance("ghost_visor", color)
		_apply_visor_uniforms(_ghost_visor_mat)
	_ghost_visor_mat.set_shader_parameter("frost", v)


## Wear level: 0 = factory fresh, 1 = default scuffs and chipped edges, up to 2 for a
## battered suit late in a round.
func set_wear(amount: float) -> void:
	var v := clampf(amount, 0.0, 2.0)
	_suit_mat.set_shader_parameter("scuff_amount", v)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter("scuff_amount", v)
	for glove in hands:
		glove.set_suit_param("scuff_amount", v)


## World position of the raised right wrist in the "dragged" pose: put the dragger's
## grip here, or place the body so this meets the dragger's hand.
func get_drag_handle() -> Vector3:
	return bones[CrewBody.R_HAND].global_position if is_inside_tree() else _root_xf(CrewBody.R_HAND).origin


func _apply_visor_uniforms(m: ShaderMaterial) -> void:
	m.set_shader_parameter("visor_light", _light_visor)
	m.set_shader_parameter("glint_pos", _glint_pos)
	m.set_shader_parameter("glint_col", _glint_col)


## Local, horizontal direction pointing away from `source` (default: pushed back).
func _push_from(source: Vector3) -> Vector3:
	if not source.is_finite() or not is_inside_tree():
		return Vector3(0, 0, -1)
	var d := to_local(source)
	d.y = 0.0
	if d.length_squared() < 1e-6:
		return Vector3(0, 0, -1)
	return -d.normalized()


func _show_expression(id: int) -> void:
	if id == _expr:
		return
	_expr_prev = _expr
	_expr = id
	_expr_mix = 0.0 if _expr_blend > 0.0 else 1.0
	_gain += 0.35  # the LEDs ping brighter on a change of mood
	if id in [2, 3, 4, 10]:
		_sweep_t = 0.0


func _auto_expression() -> void:
	if _ghost:
		_expr_base = 7
	elif _down:
		_expr_base = 6
	elif _expr_base == 6 or _expr_base == 7:
		_expr_base = 0
	if _expr_hold <= 0.0 and _tear_t < 0.0:
		_show_expression(_expr_base)


func _plant(side: int) -> void:
	_sole[side] = 1.0
	footstep.emit(side)


func _process(delta: float) -> void:
	_lamp = move_toward(_lamp, _lamp_target, delta * 30.0)
	var flash := 0.0
	if _hit_t >= 0.0:
		flash = clampf(1.0 - _hit_t / 0.22, 0.0, 1.0)
	_set_param("lamp_energy", _lamp * _light_lamp)
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
	# Glitch cut: static for TEAR_TIME, then the new face at once.
	var tear := 0.0
	if _tear_t >= 0.0:
		_tear_t += delta
		tear = 1.0
		if _tear_t >= TEAR_TIME:
			_tear_t = -1.0
			_expr_blend = 0.0
			_expr_hold = _tear_hold if _tear_hold > 0.0 else 0.0
			_show_expression(_tear_id)
	# Getting up: the downed face flickers back to life over the last second.
	if _getup_t >= 0.0:
		var u := _getup_t
		if u > GET_UP_TIME - 1.0:
			var k := fposmod(sin(floor(u * 24.0) * 12.9898) * 43758.5453, 1.0)
			tear = maxf(tear, (1.0 if k < 0.45 else 0.0) * (1.0 - smoothstep(0.75, GET_UP_TIME, u)))
		if u > 0.62 and (_expr == 6 or _expr_base == 6):
			_expr_base = 0 if _expr_base == 6 else _expr_base
			_expr_blend = 0.0
			_show_expression(_expr_base)
	if _expr_hold > 0.0:
		_expr_hold -= delta
		if _expr_hold <= 0.0:
			_expr_blend = 0.12
			_show_expression(_expr_base)
	_expr_mix = minf(_expr_mix + delta / maxf(_expr_blend, 0.001), 1.0)
	# Blink every 3-5 s (neutral and suspicious faces).
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_t = 0.0
		_blink_timer = _rng.randf_range(3.0, 5.0)
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
		_saccade_timer = _rng.randf_range(1.2, 3.5)
		_saccade = Vector2(_rng.randf_range(-0.012, 0.012), _rng.randf_range(-0.005, 0.006)) * (1.0 - _move_w) * (1.0 - _look_w)
	var target := Vector2(clampf(_yaw_rate * 0.012, -0.024, 0.024), -0.004 * _move_w) + _saccade
	# Expression glances (the suspicious side-eye, the smug look).
	for i in _att_w.size():
		if _att_w[i] > 0.001:
			var spec: Dictionary = _BODY.get(CrewMaterials.EXPRESSIONS[i], {})
			target += (spec.get("look", Vector2.ZERO) as Vector2) * _att_w[i]
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
	# Mood colour, brightness and glass wash ease to the face's style.
	var style: Array = CrewMaterials.EXPRESSION_STYLE.get(CrewMaterials.EXPRESSIONS[_expr], [Color.WHITE, 0.0, 1.0, 0.0])
	var tc: Color = style[0]
	tc.a = float(style[1])
	var k2 := 1.0 - exp(-delta * 9.0)
	_tint = _tint.lerp(tc, k2)
	_gain = lerpf(_gain, float(style[2]), 1.0 - exp(-delta * 5.0))
	_wash = lerpf(_wash, float(style[3]), k2)
	if _sweep_t >= 0.0:
		_sweep_t += delta / 0.55
		if _sweep_t > 1.0:
			_sweep_t = -1.0
	var vm := _ghost_visor_mat if _ghost else _visor_mat
	vm.set_shader_parameter("expr_tint", Vector4(_tint.r, _tint.g, _tint.b, _tint.a))
	vm.set_shader_parameter("eye_gain", _gain)
	vm.set_shader_parameter("wash", _wash)
	vm.set_shader_parameter("glint", _sweep_t)
	vm.set_shader_parameter("tremble", _tremble)
	vm.set_shader_parameter("expr_a", _expr_prev)
	vm.set_shader_parameter("expr_b", _expr)
	vm.set_shader_parameter("expr_mix", _expr_mix)
	vm.set_shader_parameter("blink", _blink if _expr == 0 else 0.0)
	vm.set_shader_parameter("look", _look + _eye_s)
	vm.set_shader_parameter("glitch", maxf(maxf(_stun_w, flash * 0.8), tear))


func _set_param(key: String, value: float) -> void:
	if is_equal_approx(_last_params.get(key, -999.0), value):
		return
	_last_params[key] = value
	_suit_mat.set_shader_parameter(key, value)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter(key, value)
	if key == "hit_flash" or key == "distress":
		for glove in hands:
			glove.set_suit_param(key, value)


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


# --- gloves ---------------------------------------------------------------------------

## Picks each glove's pose from the character state and steps its finger motion.
func _update_hands(delta: float) -> void:
	for side in 2:
		var pose := _glove_pose(side)
		if pose != _hand_pose[side]:
			_hand_pose[side] = pose
			if pose == "half":
				hands[side].set_curl(0.5)
			else:
				hands[side].set_pose(pose, 0.06 if pose == "push" or pose == "brace" else 0.15)
		hands[side].set_tremble(_tremble)
		hands[side].set_motion(_speed, delta)


## side 0 = left glove, 1 = right glove.
func _glove_pose(side: int) -> String:
	if _ghost:
		return "ghost"
	if _down or _down_w > 0.5:
		return "limp"
	var reach: Dictionary = _reach[side]
	if float(reach.get("w", 0.0)) > 0.5 and String(reach.get("glove", "")) != "":
		return reach.glove
	if _stun_w > 0.3 or (_hit_t >= 0.0 and _hit_t < 0.45):
		return "brace"
	if _shove_t >= 0.0 and _shove_t < 0.3:
		return "push"
	var voted := _voted_glove(side)
	if voted != "":
		return voted
	if _draw_t >= 0.0 and _draw_t < DRAW_TIME * 0.7:
		return "grip_gun" if side == 1 else "relaxed"
	if _aiming:
		return "grip_gun_trigger" if side == 1 else "grip_large"
	if _carry_w > 0.5:
		return "grip_core" if _held == "core" else "grip_large"
	if side == 1 and _held == "gun":
		return "grip_gun"
	if _fidget_t >= 0.0 and _fidget_kind == 1 and side == 1:
		return "fist"
	if _tension_s > 0.5:
		return "half"
	return "relaxed"


## Glove pose with the most acting weight (gestures or body language) above 0.5.
func _voted_glove(side: int) -> String:
	var best := ""
	var best_w := 0.5
	for pose_name: String in _glove_votes[side]:
		var w: float = _glove_votes[side][pose_name]
		if w > best_w:
			best = pose_name
			best_w = w
	return best


## Wrist transform (root space) that puts this glove's grip anchor on `item_xf`.
func _wrist_for(side: int, kind: String, item_xf: Transform3D) -> Transform3D:
	return item_xf * hands[side].get_grip_anchor(kind).affine_inverse()


# --- secondary motion ---------------------------------------------------------------

## Antenna wobble and backpack bounce: damped springs driven by how the head and
## chest accelerate in the world. A carried body's head, lower arm and legs dangle on
## springs from the same acceleration (the legs a half beat behind).
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
	var wa := (gx.basis.inverse() * ca).limit_length(40.0)
	var steps := 2
	var h := delta / steps
	for i in steps:
		var acc := -140.0 * _ant - 7.0 * _ant_v + Vector2(la.z, -la.x) * 0.012
		_ant_v += acc * h
		_ant += _ant_v * h
		var pacc := -260.0 * _pack - 13.0 * _pack_v - lc.y * 0.0035
		_pack_v += pacc * h
		_pack += _pack_v * h
		if _carried_w > 0.001:
			# Dangle: vertical bob and forward surges swing the head, arm and legs.
			var drive: Array[float] = [wa.y * 0.012 + wa.z * 0.006, wa.z * 0.02 - wa.y * 0.006, wa.z * 0.012 + wa.y * 0.008]
			var omega: Array[float] = [TAU * 1.9, TAU * 1.5, TAU * 1.1]
			for j in 3:
				var a2 := -omega[j] * omega[j] * _dangle[j] - 2.0 * 0.22 * omega[j] * _dangle[3 + j] + drive[j] * omega[j] * omega[j] * 0.05
				_dangle[3 + j] += a2 * h
				_dangle[j] += _dangle[3 + j] * h
	for j in 3:
		_dangle[j] = clampf(_dangle[j], -0.5, 0.5)
	_ant = _ant.limit_length(0.35)
	_pack = clampf(_pack, -0.025, 0.025)
	var still := 1.0 - _down_w
	bones[CrewBody.ANTENNA].basis = Basis.from_euler(Vector3(_ant.x, 0.0, _ant.y) * still)
	var pk := bones[CrewBody.PACK]
	pk.position.y += _pack * still
	pk.basis = Basis(Vector3.RIGHT, -_pack * 2.5 * still) * pk.basis


func _update_fidget(delta: float) -> void:
	var idle := _move_w < 0.05 and _carry_w < 0.05 and _aim_w < 0.05 and _stun_w < 0.05 and _down_w < 0.05 and _ghost_w < 0.05 and _air_w < 0.05 and _shove_t < 0.0
	idle = idle and _shots.is_empty() and _acting_busy() < 0.05
	if _fidget_t >= 0.0:
		_fidget_t += delta
		if _fidget_t > _fidget_dur() or not idle:
			_fidget_t = -1.0
			_fidget_timer = _rng.randf_range(6.0, 10.0)
		return
	if idle:
		_fidget_timer -= delta
		if _fidget_timer <= 0.0:
			_fidget_t = 0.0
			# Never the helmet tap (1): that is the infiltrator's tell, played on purpose.
			_fidget_kind = 0 if _rng.randf() < 0.5 else 2


func _fidget_dur() -> float:
	return [2.2, 1.6, 2.4][_fidget_kind]


func _fidget_env() -> float:
	if _fidget_t < 0.0:
		return 0.0
	var d := _fidget_dur()
	return smoothstep(0.0, 0.35, _fidget_t) * (1.0 - smoothstep(d - 0.45, d, _fidget_t))


## Test / tooling hook: start an idle fidget now (0 look around, 1 tap helmet, 2 check
## wrist). Random fidgets only pick 0 and 2; use play_gesture("helmet_tap") for the tell.
func play_fidget(kind: int) -> void:
	_fidget_kind = posmod(kind, 3)
	_fidget_t = 0.0


# --- acting state ---------------------------------------------------------------------

func _step_acting(delta: float) -> void:
	for key: String in _gest_w:
		_gest_w[key] = move_toward(float(_gest_w[key]), float(_gest_goal.get(key, 0.0)), delta * _gest_rate)
		_gest_t[key] = float(_gest_t.get(key, 0.0)) + delta
	for key: String in _shots.keys():
		var before: float = _shots[key]
		var now := before + delta
		if key == "helmet_tap":
			for i in TAP_BEATS.size():
				if before < TAP_BEATS[i] and now >= TAP_BEATS[i]:
					gesture_beat.emit(key, i)
		if now > float(ONE_SHOTS[key]):
			_shots.erase(key)
			if key == "step_back":
				_root_motion += Vector3(0.0, 0.0, -STEP_BACK)
		else:
			_shots[key] = now
	_look_w = move_toward(_look_w, _look_hw if _look_target != null else 0.0, delta * 4.0)
	_tension_s = move_toward(_tension_s, _tension, delta * 1.5)
	if _nod_t >= 0.0:
		_nod_t += delta
		if _nod_t > 0.5:
			_nod_t = -1.0
	if _shake_t >= 0.0:
		_shake_t += delta
		if _shake_t > 0.9:
			_shake_t = -1.0
	for i in _att_w.size():
		var goal := 1.0 if i == _expr else 0.0
		_att_w[i] = move_toward(_att_w[i], goal, delta * 4.5)


## How much a gesture or reach is using the body (keeps idle fidgets away).
func _acting_busy() -> float:
	var b := 0.0
	for key: String in _gest_w:
		b = maxf(b, float(_gest_w[key]))
	for r: Dictionary in _reach:
		b = maxf(b, float(r.get("w", 0.0)))
	return b


## A gesture's target in root space: its own, else the look target, else `fallback`.
func _target_root(gesture: String, fallback: Vector3) -> Vector3:
	var t: Variant = _gest_target.get(gesture, _look_target)
	if t == null:
		return fallback
	var world := _world_point(t)
	return global_transform.affine_inverse() * world if is_inside_tree() else world


static func _world_point(t: Variant) -> Vector3:
	if t is Node3D:
		var n := t as Node3D
		if n is CrewModel and n.is_inside_tree():
			return (n as CrewModel).bones[CrewBody.HEAD].global_position + Vector3(0.0, 0.08, 0.0)
		return n.global_position if n.is_inside_tree() else n.position
	return t as Vector3


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
	var recoil := 0.0
	if _recoil_t >= 0.0:
		recoil = sin(clampf(_recoil_t / RECOIL_TIME, 0.0, 1.0) * PI)
	# Acting layers: expression body language, gestures, reaches, stagger, get-up.
	var L := _layers(t)
	var ten := _tension_s
	_tremble = clampf(float(L.tremble) + 0.25 * ten, 0.0, 1.0)
	var body_carry := _carry_w if _held == "body" else 0.0

	# --- hips ---
	var yaw_amp := lerpf(0.13, 0.2, rw) * mw
	_front = lerpf(0.8, 0.55, rw)
	var lift := lerpf(0.1, 0.17, smoothstep(1.5, WALK_SPEED, _speed)) + 0.13 * rw
	# Vaulting: the hip height follows the planted leg(s) so knees never lock or crouch.
	var leg_len := 0.84 * lerpf(lerpf(0.99, 0.975, smoothstep(1.5, WALK_SPEED, _speed)), 0.97, rw)
	_comp = 0.025 * smoothstep(1.5, WALK_SPEED, _speed) + 0.04 * rw + 0.02 * body_carry
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
	hips_pos.z += (0.05 * thrust - 0.035 * wind) * shove
	hips_pos += Vector3(_hit_push.x, 0.0, _hit_push.z) * 0.06 * hit
	hips_pos.y -= 0.04 * absf(hit) + 0.06 * stun * (0.6 + 0.4 * sin(t * 4.1)) + 0.02 * wind * shove
	hips_pos.x += stun * 0.04 * sin(t * 2.3)
	hips_pos.z += stun * 0.035 * cos(t * 1.9)
	var ghost_float := _ghost_w * (0.14 + 0.06 * sin(t * 1.6))
	hips_pos.y += ghost_float
	var hips_rot := Vector3(0.04 * mw + 0.08 * rw + clampf(_accel * 0.012, -0.08, 0.1), -yaw_amp * cos(cyc), 0.035 * sin(cyc) * mw)
	hips_rot.z += stun * 0.12 * sin(t * 2.3 + 0.5)
	hips_pos += (L.hips as Vector3) + _root_motion
	hips_rot += L.hips_rot as Vector3
	B[CrewBody.HIPS].position = hips_pos
	B[CrewBody.HIPS].basis = Basis.from_euler(hips_rot)

	# Look target: desired head angles (root space), eased; the eyes lead.
	_update_look(hips_pos)
	var chest_follow := _head_s.x / 3.0 * smoothstep(0.6, 0.9, absf(_head_s.x))

	# --- spine / chest ---
	var breath := sin(_breath_ph)
	var lean := 0.05 * mw + 0.2 * rw + 0.06 * _carry_w * (1.0 - _aim_w) + (0.26 * thrust - 0.18 * wind) * shove + 0.45 * hit * _hit_push.z - 0.07 * recoil * _aim_w
	lean -= 0.14 * body_carry  # leaning back to balance a carried body
	var counter := yaw_amp * 1.55 * cos(cyc)
	var aim_twist := 0.18 * _aim_w
	var fid_twist: float = 0.12 * sin(_fidget_t / 2.2 * TAU) * fid if _fidget_kind == 0 else 0.0
	var lc: Vector3 = L.chest
	var lsp: Vector3 = L.spine
	var breath_amp := lerpf(0.018, 0.045, ten)
	B[CrewBody.SPINE].basis = Basis.from_euler(Vector3(lean * 0.5 + stun * 0.15 * sin(t * 3.0), counter * 0.45 + aim_twist * 0.4 + fid_twist * 0.4, -hips_rot.z * 0.6 + stun * 0.1 * sin(t * 2.7))
		+ lc * 0.45 + lsp + Vector3(0.0, chest_follow * 0.4, 0.0))
	B[CrewBody.CHEST].basis = Basis.from_euler(Vector3(lean * 0.5 + breath_amp * breath * (1.0 - mw) + 0.2 * hit * _hit_push.z + stun * 0.1 * sin(t * 3.4 + 1.0),
		counter * 0.55 + aim_twist * 0.6 + fid_twist * 0.6 + 0.25 * hit * _hit_side, -hips_rot.z * 0.3 + 0.22 * hit * _hit_side)
		+ lc * 0.55 + Vector3(0.0, chest_follow * 0.6, 0.0))

	# --- head stabilisation (keeps the visor level and facing forward) + looks ---
	var neck_xf := _root_xf(CrewBody.CHEST) * B[CrewBody.NECK].transform
	var lh: Vector3 = L.head
	var head_pitch := -0.05 * rw + 0.06 * _carry_w + 0.5 * hit * _hit_push.z - 0.1 * recoil + lh.x + _head_s.y
	var head_yaw := -aim_twist * 0.2 * (1.0 - _look_w) + lh.y + _head_s.x
	var head_roll := lh.z
	if _nod_t >= 0.0:
		head_pitch += 0.244 * _nod_k * pow(sin(PI * _nod_t / 0.5), 2.0)
	if _shake_t >= 0.0:
		var su := _shake_t / 0.9
		head_yaw += 0.314 * _shake_k * sin(3.0 * PI * su) * smoothstep(0.0, 0.12, su) * (1.0 - 0.35 * su)
	head_pitch += 0.0087 * ten * sin(t * 9.0)
	head_yaw += 0.006 * ten * sin(t * 7.3 + 1.0)
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
		# Acting: stances, catch steps, kneeling, trailing legs; root motion.
		target += ((L.feet as Array)[side] as Vector3) + _root_motion
		pitch += float((L.foot_pitch as Array)[side])
		var local_target := hips_xf.affine_inverse() * target
		var pole := hips_xf.basis.inverse() * Vector3(s * 0.12, 0.0, 1.0)
		var ik := _two_bone(B[thigh].position, local_target, pole, 0.425, 0.415, 1.0)
		B[thigh].basis = ik[0]
		B[shin].basis = ik[1]
		var shin_basis := hips_xf.basis * B[thigh].basis * B[shin].basis
		var want := Basis(Vector3.UP, s * 0.06) * Basis(Vector3.RIGHT, pitch)
		B[foot].basis = shin_basis.inverse() * want

	# --- arms: FK swing, blended with IK for carry / aim / shove / fidgets / acting ---
	var chest_xf := _root_xf(CrewBody.CHEST)
	var head_xf := _root_xf(CrewBody.HEAD)
	var swing_amp := lerpf(0.42, 0.75, rw) * mw * (1.0 - 0.7 * _carry_w)
	var busy := clampf(float(L.busy), 0.0, 1.0)
	var drawing := _draw_t >= 0.0
	var draw_u := clampf(_draw_t / DRAW_TIME, 0.0, 1.0)
	# One-handed gun run: the gun arm tucked, muzzle down and forward.
	var gun_run := mw * (1.0 - _aim_w) * (1.0 if _held == "gun" else 0.0) * (1.0 - busy)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var up := CrewBody.L_ARM if side == 0 else CrewBody.R_ARM
		var fore := up + 1
		var hand := up + 2
		B[up].position.y += float(L.shrug) + 0.025 * ten
		B[up].position.z += float((L.shoulder as Array)[side])
		var tuck_w := gun_run if side == 1 else 0.0
		var swing := swing_amp * cos(cyc) * s * (1.0 - 0.75 * tuck_w)
		var fwd := maxf(0.0, -swing)
		var fk_up := Basis.from_euler(Vector3(swing + 0.04 * (1.0 - mw) + float(L.swing) - 0.25 * tuck_w, 0.0, s * (0.235 - 0.05 * mw + 0.04 * rw + 0.012 * breath * (1.0 - mw) + float(L.spread))))
		var fk_fore := Basis.from_euler(Vector3(-(0.22 + 0.2 * mw + 0.95 * rw + fwd * 0.5 + float(L.elbow) + 1.0 * tuck_w), 0.0, 0.0))
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
			fk_up = Basis(fk_up.get_rotation_quaternion().slerp(drift.get_rotation_quaternion(), _ghost_w * (1.0 - busy)))
		# IK targets (root space). Carry and aim place the wrist so the glove's grip
		# anchor lands on the item; shove and fidgets only place the wrist.
		var carry_kind := "core" if _held == "core" else "cell"
		var carry_wrist := _wrist_for(side, carry_kind, carry_anchor.transform)
		if body_carry > 0.0:
			# A crewmate across the forearms: left under the back, right under the knees.
			var under := carry_anchor.position + Vector3(s * 0.22, -0.07, -0.03)
			carry_wrist = Transform3D(_hand_basis(side, Vector3.UP, Vector3(-s * 0.3, 0.0, 1.0)), under - Vector3(0, 0.0, 0.06))
		var gun_xf := _aim_xf(chest_xf, recoil)
		var aim_wrist := _wrist_for(1, "gun", gun_xf)
		if side == 0:
			aim_wrist = Transform3D(aim_wrist.basis, gun_xf * AIM_SUPPORT)
		var aw := _aim_w
		if drawing:
			if side == 1:
				aim_wrist = _draw_wrist(draw_u, aim_wrist)
				aw = 1.0
			else:
				aw *= smoothstep(0.65, 1.0, draw_u)
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
		# Acting goals, by priority: reach > gesture > body language > the rest.
		var goals: Array = (L.goals as Array)[side]
		var top: Array[float] = [0.0, 0.0, 0.0]
		for goal: Dictionary in goals:
			top[int(goal.pri)] = maxf(top[int(goal.pri)], float(goal.w))
		var keep: float = (1.0 - top[PRI_REACH]) * (1.0 - top[PRI_GESTURE]) * (1.0 - busy * (1.0 - top[PRI_GESTURE]))
		var cw := _carry_w * keep
		aw *= keep
		var sw := shove * 4.0 * keep
		fw *= keep
		var gw := 0.0
		var g_pos := Vector3.ZERO
		var g_pole := Vector3.ZERO
		var g_sum := 0.0
		var g_basis := Basis.IDENTITY
		var g_basis_w := 0.0
		for goal: Dictionary in goals:
			var pri: int = goal.pri
			var w: float = goal.w
			if pri == PRI_GESTURE:
				w *= 1.0 - top[PRI_REACH]
			elif pri == PRI_BODY:
				w *= (1.0 - top[PRI_REACH]) * (1.0 - top[PRI_GESTURE])
			if w <= 0.0001:
				continue
			var space: int = goal.space
			var frame := Transform3D.IDENTITY
			if space == SPACE_CHEST:
				frame = chest_xf
			elif space == SPACE_HEAD:
				frame = head_xf
			var gp: Vector3 = frame * (goal.pos as Vector3)
			var palm: Vector3 = frame.basis * (goal.palm as Vector3)
			var fingers: Vector3 = frame.basis * (goal.fingers as Vector3)
			var basis := Basis.IDENTITY
			var has_basis := palm != Vector3.ZERO
			if has_basis:
				basis = _hand_basis(side, palm, fingers)
				# Contact solve: put a point of the glove (fingertip / palm / fist) on gp.
				if goal.has("contact"):
					var contact: Vector3 = goal.contact
					if String(goal.contact_kind) == "tip":
						contact = hands[side].get_fingertip(2)
					gp -= basis * contact
			g_pos += gp * w
			g_pole += (goal.pole as Vector3) * w
			g_sum += w
			gw = maxf(gw, w)
			if has_basis and w > g_basis_w:
				g_basis = basis
				g_basis_w = w
		gw = minf(gw, 1.0)
		if g_sum > 0.0:
			g_pos /= g_sum
			g_pole /= g_sum
		var total := cw + aw + sw + fw + gw
		var ik_w := clampf(maxf(maxf(maxf(cw, fw), maxf(aw, shove * keep)), gw), 0.0, 1.0) * (1.0 - stun * (1.0 - top[PRI_REACH])) * (1.0 - _ghost_w * (1.0 - maxf(busy, gw)))
		var up_b := fk_up
		var fore_b := fk_fore
		var hand_b := Basis.from_euler(Vector3(-0.1 - 0.15 * mw + 0.7 * tuck_w, 0.0, 0.0))
		if ik_w > 0.001 and total > 0.0:
			var target2 := (carry_wrist.origin * cw + aim_wrist.origin * aw + shove_t * sw + fid_t * fw + g_pos * gw) / total
			var lt := chest_xf.affine_inverse() * target2
			var pole2 := chest_xf.basis.inverse() * Vector3(s * 0.8, -0.6, -0.5).lerp(Vector3(s * 0.35, -1.0, 0.0), aw / maxf(total, 0.001))
			if gw > 0.0:
				pole2 = pole2.lerp(g_pole.normalized(), gw / total)
			var ik2 := _two_bone(B[up].position, lt, pole2, 0.295, 0.27, -1.0)
			up_b = Basis(fk_up.get_rotation_quaternion().slerp(ik2[0].get_rotation_quaternion(), ik_w))
			fore_b = Basis(fk_fore.get_rotation_quaternion().slerp(ik2[1].get_rotation_quaternion(), ik_w))
			var push := clampf(thrust, 0.0, 1.0) * shove
			var wrist := Basis.from_euler(Vector3(SHOVE_WRIST * push / maxf(ik_w, 0.01), 0.0, 0.0))
			if fw > 0.0 and _fidget_kind == 2:
				wrist = Basis(Vector3.UP, -1.2)
			hand_b = Basis(hand_b.get_rotation_quaternion().slerp(wrist.get_rotation_quaternion(), ik_w))
			# Carry / aim: orient the glove so the grip anchor matches the item.
			var held_w := (cw + aw) / total * ik_w
			if held_w > 0.001:
				var want_world := carry_wrist.basis.slerp(aim_wrist.basis, aw / maxf(cw + aw, 0.001))
				var fore_root := chest_xf.basis * up_b * fore_b
				var want_hand := (fore_root.inverse() * want_world).orthonormalized()
				hand_b = Basis(hand_b.get_rotation_quaternion().slerp(want_hand.get_rotation_quaternion(), held_w))
			if g_basis_w > 0.0:
				var g_hand := ((chest_xf.basis * up_b * fore_b).inverse() * g_basis).orthonormalized()
				hand_b = Basis(hand_b.get_rotation_quaternion().slerp(g_hand.get_rotation_quaternion(), gw / total * ik_w))
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
	# --- full-body gesture: dragged ---
	var dragged_w: float = _gest_w.get("dragged", 0.0)
	if dragged_w > 0.001:
		var dp := _dragged_pose(t)
		for i in bones.size():
			B[i].transform = B[i].transform.interpolate_with(dp[i], dragged_w)


## Gun transform while aiming (root space): levelled at the look target (or ahead),
## sunk toward low ready by the aim height, with the recoil kick.
func _aim_xf(chest_xf: Transform3D, recoil: float) -> Transform3D:
	var fwd_h := Vector3(chest_xf.basis.z.x, 0.0, chest_xf.basis.z.z).normalized()
	var gun_xf := Transform3D(Basis(Vector3.UP.cross(fwd_h), Vector3.UP, fwd_h), AIM_GRIP)
	if _look_w > 0.001 and _look_target != null:
		var to := _target_root("", AIM_GRIP + Vector3(0, 0, 3)) - AIM_GRIP
		var yaw_f := clampf(atan2(to.x, to.z), -0.9, 0.9)
		var pitch_f := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.6, 0.5)
		var dir := Vector3(sin(yaw_f) * cos(pitch_f), sin(pitch_f), cos(yaw_f) * cos(pitch_f))
		var x_axis := Vector3.UP.cross(dir).normalized()
		var aimed := Transform3D(Basis(x_axis, dir.cross(x_axis), dir), Basis(Vector3.UP, yaw_f * 0.6) * AIM_GRIP)
		gun_xf = gun_xf.interpolate_with(aimed, _look_w)
	if _aim_h < 0.999:
		var low := Transform3D(gun_xf.basis.rotated(gun_xf.basis.x.normalized(), LOW_PITCH), LOW_GRIP + (gun_xf.origin - AIM_GRIP) * 0.5)
		gun_xf = low.interpolate_with(gun_xf, smoothstep(0.0, 1.0, _aim_h))
	return gun_xf.rotated_local(Vector3.RIGHT, -0.35 * recoil).translated_local(Vector3(0, 0, -0.03 * recoil))


## Eases the head toward the look target and lets the eyes lead (root space angles).
func _update_look(hips_pos: Vector3) -> void:
	if _look_target != null:
		var tr := _target_root("", Vector3(0, 1.6, 3))
		var d := tr - Vector3(0.0, hips_pos.y + 0.62, 0.0)
		_look_want = Vector2(atan2(d.x, d.z), clampf(-atan2(d.y, Vector2(d.x, d.z).length()), -1.0, 1.0))
	var want := _look_want * _look_w
	var chest_part := want.x / 3.0 * smoothstep(0.6, 0.9, absf(want.x))
	var head_target := Vector2(chest_part + clampf(want.x - chest_part, -1.22, 1.22), clampf(want.y, -0.52, 0.52))
	_head_s = _head_s.lerp(head_target, 1.0 - exp(-_dt * 7.0))
	var residual := (want - _head_s) * 1.1
	var eye_target := Vector2(clampf(residual.x * 0.08, -0.06, 0.06), clampf(-residual.y * 0.05, -0.03, 0.03))
	_eye_s = _eye_s.lerp(eye_target, 1.0 - exp(-_dt * 30.0))


# --- acting layers -----------------------------------------------------------------

## Body language (from the expressions' blend weights), held gestures, one-shots,
## reaches, stagger and get-up, summed by weight. Arm goals are wrist targets in root,
## chest or head space; `contact` (hand space) makes the solver put that point of the
## glove on the target instead of the wrist ("tip" = the middle fingertip). Poles are
## in chest space; palm / fingers (optional) orient the glove in the goal's space.
func _layers(t: float) -> Dictionary:
	var L := {"head": Vector3.ZERO, "chest": Vector3.ZERO, "spine": Vector3.ZERO, "hips": Vector3.ZERO, "hips_rot": Vector3.ZERO,
		"shrug": 0.0, "swing": 0.0, "spread": 0.0, "elbow": 0.0, "feet": [Vector3.ZERO, Vector3.ZERO], "foot_pitch": [0.0, 0.0],
		"shoulder": [0.0, 0.0], "tremble": 0.0, "goals": [[], []], "busy": 0.0}
	_glove_votes = [{}, {}]
	var calm := 1.0 - _down_w
	# Gestures can be triggered on any avatar at any time: downed, carried or ghost
	# bodies simply don't show the arm gestures (except the ghost's own drift and the
	# dragged pose).
	var able := calm * (1.0 - _ghost_w)
	for key: String in _gest_w:
		var gw: float = _gest_w[key]
		if gw > 0.001:
			var gate := 1.0 if key == "dragged" else (calm if key == "ghost_drift" else able)
			_gesture_layer(L, key, gw * gate, float(_gest_t.get(key, 0.0)), t)
	if able > 0.001:
		for key: String in _shots:
			_one_shot_layer(L, key, float(_shots[key]), t, able)
	_reach_layer(L)
	if _stagger_t >= 0.0:
		_stagger_layer(L, t)
	if _getup_t >= 0.0:
		_get_up_layer(L)
	var still := (1.0 - 0.5 * _move_w) * calm * (1.0 - _ghost_w * 0.5)
	var free_arms := 1.0 - clampf(float(L.busy), 0.0, 1.0)
	var arm_gate := (1.0 - _move_w) * (1.0 - _carry_w) * (1.0 - _aim_w) * calm * (1.0 - _ghost_w) * (1.0 - _stun_w) * free_arms
	var legs_gate := (1.0 - _move_w) * calm * (1.0 - _ghost_w) * (1.0 - _air_w)
	for i in _att_w.size():
		var w := _att_w[i]
		if w < 0.001:
			continue
		var spec: Dictionary = _BODY.get(CrewMaterials.EXPRESSIONS[i], {})
		if spec.is_empty():
			continue
		L.head += (spec.get("head", Vector3.ZERO) as Vector3) * w * still
		L.chest += (spec.get("chest", Vector3.ZERO) as Vector3) * w * still
		L.shrug += float(spec.get("shrug", 0.0)) * w * still
		L.hips += Vector3(0.0, -float(spec.get("crouch", 0.0)), float(spec.get("lean", 0.0))) * w * legs_gate
		L.tremble += float(spec.get("tremble", 0.0)) * w
		L.spread += float(spec.get("arms_out", 0.0)) * w * arm_gate
		L.swing -= float(spec.get("arms_fwd", 0.0)) * w * arm_gate
		if spec.has("bounce"):
			L.hips += Vector3(0.0, absf(sin(t * TAU * 1.1)) * 0.012, 0.0) * w * legs_gate
		var aw := w * arm_gate
		if aw > 0.001:
			_expression_arms(L, String(spec.get("arms", "")), aw)
			var g: String = spec.get("gloves", "")
			if g != "":
				_vote(0, g, aw)
				_vote(1, g, aw)
	return L


func _goal(L: Dictionary, side: int, pos: Vector3, w: float, pole: Vector3, space := SPACE_CHEST, palm := Vector3.ZERO, fingers := Vector3.ZERO, pri := PRI_GESTURE) -> Dictionary:
	var goal := {"pos": pos, "w": w, "pole": pole, "space": space, "palm": palm, "fingers": fingers, "pri": pri}
	(L.goals[side] as Array).append(goal)
	return goal


func _vote(side: int, pose_name: String, w: float) -> void:
	var votes := _glove_votes[side]
	votes[pose_name] = float(votes.get(pose_name, 0.0)) + w


## Arm sets of the expression body language (chest-space wrist goals; side 0 = left).
func _expression_arms(L: Dictionary, kind: String, w: float) -> void:
	match kind:
		"cross":
			_goal(L, 0, Vector3(-0.075, -0.05, 0.19), w, Vector3(1.0, -0.4, -0.3), SPACE_CHEST, Vector3.ZERO, Vector3.ZERO, PRI_BODY)
			_goal(L, 1, Vector3(0.085, 0.01, 0.215), w, Vector3(-1.0, -0.4, -0.3), SPACE_CHEST, Vector3.ZERO, Vector3.ZERO, PRI_BODY)
		"clutch":
			_goal(L, 0, Vector3(-0.1, -0.14, 0.14), w, Vector3(1.0, -0.6, -0.4), SPACE_CHEST, Vector3.ZERO, Vector3.ZERO, PRI_BODY)
			_vote(0, "brace", w)
			L.spread += 0.05 * w
		"cower":
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				_goal(L, side, Vector3(s * 0.11, 0.12, 0.22), w, Vector3(s * 0.5, -1.0, -0.1), SPACE_CHEST, Vector3(0, 0.2, 1), Vector3(s * 0.2, 1, 0), PRI_BODY)
				_vote(side, "brace", w)
		"akimbo":
			_goal(L, 1, Vector3(-0.175, -0.23, 0.0), w, Vector3(-1.0, 0.15, -0.8), SPACE_CHEST, Vector3.ZERO, Vector3.ZERO, PRI_BODY)
			_vote(1, "fist", w)
		"startle":
			for side in 2:
				var s2 := 1.0 if side == 0 else -1.0
				_goal(L, side, Vector3(s2 * 0.36, -0.1, 0.2), w, Vector3(s2, -0.8, -0.3), SPACE_CHEST, Vector3(s2 * 0.3, 0.0, 1.0), Vector3(s2 * 0.4, 1.0, 0.0), PRI_BODY)
				_vote(side, "brace", w)
		"fists":
			for side in 2:
				var s3 := 1.0 if side == 0 else -1.0
				_goal(L, side, Vector3(s3 * 0.29, -0.3, 0.09), w, Vector3(s3, -0.5, -0.6), SPACE_CHEST, Vector3.ZERO, Vector3.ZERO, PRI_BODY)
				_vote(side, "fist", w)
		"plead":
			for side in 2:
				var s4 := 1.0 if side == 0 else -1.0
				_goal(L, side, Vector3(s4 * 0.13, -0.15, 0.3), w, Vector3(s4, -0.8, -0.3), SPACE_CHEST, Vector3(0, 1, 0.2), Vector3(-s4 * 0.2, 0.15, 1), PRI_BODY)
				_vote(side, "open", w)


## A straight arm from the shoulder toward a root-space point (pointing, lunging):
## the wrist is placed past arm's length so the elbow straightens.
func _straight_goal(L: Dictionary, side: int, at: Vector3, w: float, glove: String, palm: Vector3) -> Vector3:
	var s := 1.0 if side == 0 else -1.0
	var shoulder := Vector3(s * 0.235, 1.43, 0.0) + (L.hips as Vector3)
	var dir := (at - shoulder).normalized()
	_goal(L, side, shoulder + dir * ARM_LEN * 1.04, w, Vector3(s, -0.6, 0.0), SPACE_ROOT, palm, dir)
	_vote(side, glove, w)
	return dir


func _gesture_layer(L: Dictionary, key: String, w: float, held: float, t: float) -> void:
	match key:
		"reach":
			# Cautious reach into the dark: weight back, low, the right hand probing
			# ahead with spread fingers, the left fist held close.
			var shoulder := Vector3(-0.2, 1.33, 0.02)
			var aim := _target_root(key, shoulder + Vector3(0.08, 0.0, 1.0))
			var dir := (aim - shoulder).normalized()
			var probe := Vector3(0.015 * sin(t * 1.3), 0.012 * sin(t * 1.7 + 1.0), 0.04 * sin(t * 0.8))
			_goal(L, 1, shoulder + dir * 0.5 + probe, w, Vector3(-1.0, -0.6, 0.0), SPACE_ROOT, Vector3(0.0, -1.0, 0.3), dir)
			_goal(L, 0, Vector3(0.07, -0.05, 0.18), w, Vector3(1.0, -0.6, -0.3))
			_vote(1, "spread", w)
			_vote(0, "fist", w)
			L.hips += Vector3(0.0, -0.08, -0.03) * w
			L.chest += Vector3(0.2, -0.08, 0.0) * w
			L.feet[1] += Vector3(0.0, 0.0, 0.16) * w
			L.feet[0] += Vector3(0.02, 0.0, -0.08) * w
			L.tremble += 0.45 * w
			L.busy += w
		"point":
			# Arm straight at the target, point glove, chest turned up to 20 degrees.
			var at := _target_root(key, Vector3(-0.4, 1.5, 3.0))
			var dir2 := _straight_goal(L, 1, at, w, "point", Vector3(0.4, -1.0, 0.0))
			L.chest += Vector3(0.06, clampf(atan2(dir2.x, dir2.z) * 0.6, -0.35, 0.35), 0.0) * w
			L.feet[1] += Vector3(0.0, 0.0, 0.07) * w
			_vote(0, "fist", w)
			L.busy += w
		"surrender":
			# Hands up, open palms turned out; the elbows sag over a few seconds.
			var sag := smoothstep(0.0, 4.0, held)
			var tr := 0.006 * sin(t * 23.0)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				_goal(L, side, Vector3(s * (0.31 + 0.04 * sag), 0.53 - 0.11 * sag + tr * s, 0.06), w, Vector3(s, -0.5 - 0.5 * sag, -0.1), SPACE_CHEST,
					Vector3(s * 0.35 * (0.4 + sag), 0.0, 1.0), Vector3(s * 0.15, 1, 0))
				_vote(side, "open", w)
			L.chest += Vector3(-0.07, 0.0, 0.0) * w
			L.head += Vector3(0.06, 0.0, 0.0) * w
			L.hips += Vector3(0.0, -0.02, -0.01) * w
			L.tremble += 0.5 * w
			L.busy += w
		"pound":
			# Both fists on the target, alternating at ~3 Hz, the chest rocking in.
			var at2 := _target_root(key, Vector3(0.0, 1.3, 0.52))
			var rock := 0.0
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				var u := fposmod(t * 3.0 + 0.5 * side, 1.0)
				var back: float = smoothstep(0.0, 0.65, u) if u < 0.65 else 1.0 - pow((u - 0.65) / 0.35, 2.0)
				rock += (1.0 - smoothstep(0.0, 0.15, u)) * s
				var aim2 := at2 + Vector3(s * 0.09, 0.0, 0.0)
				var shoulder2 := Vector3(s * 0.235, 1.43, 0.0)
				var dir3 := (aim2 - shoulder2).normalized()
				var g := _goal(L, side, aim2 - dir3 * 0.16 * back + Vector3(0, 0.05 * back, 0), w, Vector3(s, -0.7, -0.2), SPACE_ROOT, Vector3(-s * 0.6, -0.4, 0.0), dir3)
				g["contact"] = Vector3(0.0, -0.085, 0.0)
				g["contact_kind"] = "fist"
				_vote(side, "fist", w)
			L.chest += Vector3(0.12 + 0.03 * absf(rock), 0.08 * rock, 0.0) * w
			L.hips += Vector3(0.0, -0.03, 0.03) * w
			L.busy += w
		"press_glass":
			# Palms flat on a window (the target sets its depth), leaning on it.
			var glass_z := clampf(_target_root(key, Vector3(0, 0, 0.52)).z, 0.3, 0.8)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				var sag2 := 0.03 * sin(t * 0.6 + side)
				var g2 := _goal(L, side, Vector3(s * 0.21, 1.55 + sag2, glass_z), w, Vector3(s, -0.6, -0.3), SPACE_ROOT, Vector3(0, 0, 1), Vector3(s * 0.25, 1, 0))
				g2["contact"] = Vector3(0.022 * (1.0 if side == 1 else -1.0), -0.055, 0.0)
				g2["contact_kind"] = "palm"
				_vote(side, "press", w)
			L.chest += Vector3(0.12, 0.0, 0.0) * w
			L.head += Vector3(0.08, 0.0, 0.0) * w
			L.hips += Vector3(0.0, -0.03, 0.07) * w
			L.tremble += 0.35 * w
			L.busy += w
		"lunge_reach":
			# Stumbling run, one arm stretched at the target, the other back for balance.
			var at3 := _target_root(key, Vector3(-0.1, 1.3, 3.0))
			_straight_goal(L, 1, at3, w, "open", Vector3(0.0, -1.0, 0.2))
			L.chest += Vector3(0.3, 0.0, 0.0) * w
			L.head += Vector3(-0.2, 0.0, 0.0) * w
			L.swing += 0.45 * w
			L.spread += 0.2 * w
			L.busy += w
		"brace":
			# Blind: shoulders up, arms half out feeling ahead, knees bent.
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				_goal(L, side, Vector3(s * 0.3, -0.12, 0.28), w, Vector3(s, -0.7, -0.2), SPACE_CHEST, Vector3(s * 0.4, -1.0, 0.4), Vector3(s * 0.3, 0.0, 1.0))
				_vote(side, "spread", w)
			L.shrug += 0.035 * w
			L.hips += Vector3(0.0, -0.08, -0.02) * w
			L.chest += Vector3(0.08, 0.0, 0.0) * w
			L.tremble += 0.3 * w
			L.busy += w
		"dragged":
			# Full-body pose (see _dragged_pose); gloves hang.
			_vote(0, "limp", w)
			_vote(1, "limp", w)
			L.busy += w
		"ghost_drift":
			# Weightless drift: lean into the glide, arms and legs trailing, slow sway.
			L.hips += Vector3(0.0, 0.24 + 0.05 * sin(t * 1.4), 0.0) * w
			L.hips_rot += Vector3(0.55 + 0.06 * sin(t * 0.9), 0.0, 0.08 * sin(t * 0.7)) * w
			L.head += Vector3(-0.45, 0.0, 0.0) * w
			L.swing += (0.55 + 0.12 * sin(t * 1.1)) * w
			L.spread += 0.35 * w
			L.elbow += 0.25 * w
			L.feet[0] += Vector3(0.0, 0.42 + 0.05 * sin(t * 1.2), -0.4) * w
			L.feet[1] += Vector3(0.0, 0.32 + 0.05 * sin(t * 1.2 + 1.5), -0.3) * w
			L.foot_pitch[0] += 0.9 * w
			L.foot_pitch[1] += 0.9 * w
			_vote(0, "open", w)
			_vote(1, "open", w)
			L.busy += w
		"victory":
			# Both fists punched up in a V, chest out, bouncing on the knees.
			var pump := 0.035 * sin(t * TAU * 1.6)
			for side in 2:
				var s := 1.0 if side == 0 else -1.0
				_goal(L, side, Vector3(s * 0.42, 0.66 + pump, 0.06), w, Vector3(s, -0.2, -0.4), SPACE_CHEST, Vector3(0, 0, 1), Vector3(s * 0.25, 1, 0))
				_vote(side, "fist", w)
			L.chest += Vector3(-0.14, 0.0, 0.0) * w
			L.head += Vector3(-0.32, 0.0, 0.0) * w
			L.hips += Vector3(0.0, -0.035 * absf(sin(t * PI * 1.6)), 0.0) * w
			L.busy += w
		"defeat":
			# On the knees, head bowed, arms hanging, slow heavy breaths.
			var heave := 0.03 * sin(t * 2.2)
			_kneel(L, w, 2)
			L.chest += Vector3(0.38 + heave, 0.0, 0.0) * w
			L.head += Vector3(0.55, 0.0, 0.08) * w
			L.shrug -= 0.02 * w
			L.swing -= 0.06 * w
			_vote(0, "limp", w)
			_vote(1, "limp", w)
			L.busy += w
		"slump":
			# Standing defeat: shoulders dropped, chest caved, head hung.
			var heave2 := 0.025 * sin(t * 1.9)
			L.hips += Vector3(0.0, -0.04, -0.02) * w
			L.chest += Vector3(0.3 + heave2, 0.0, 0.0) * w
			L.head += Vector3(0.5, 0.0, 0.06) * w
			L.shrug -= 0.025 * w
			L.swing -= 0.1 * w
			_vote(0, "limp", w)
			_vote(1, "limp", w)
			L.busy += w


## Kneeling: hips down, `knees` 2 = both knees down, 1 = right knee down and the left
## foot planted forward (getting up).
func _kneel(L: Dictionary, w: float, knees: int) -> void:
	L.hips += Vector3(0.0, -0.44 if knees == 2 else -0.4, -0.05) * w
	L.feet[1] += Vector3(0.0, -0.01, -0.36) * w
	L.foot_pitch[1] += 2.9 * w
	if knees == 2:
		L.feet[0] += Vector3(0.0, -0.01, -0.36) * w
		L.foot_pitch[0] += 2.9 * w
	else:
		L.feet[0] += Vector3(0.03, 0.0, 0.24) * w


func _one_shot_layer(L: Dictionary, key: String, st: float, _t: float, able: float) -> void:
	var dur: float = ONE_SHOTS[key]
	var env := smoothstep(0.0, 0.22, st) * (1.0 - smoothstep(dur - 0.3, dur, st)) * able
	match key:
		"wave":
			var wag := 0.06 * sin(st * TAU * 1.7)
			_goal(L, 1, Vector3(-0.36 + wag, 0.5, 0.1), env, Vector3(-1.0, -0.3, -0.2), SPACE_CHEST, Vector3(-0.2, 0.0, 1.0), Vector3(-0.25, 1.0, 0.0))
			_vote(1, "wave", env)
			L.head += Vector3(-0.04, 0.0, -0.08) * env
			L.chest += Vector3(-0.03, 0.05, 0.04) * env
		"thumbs_up":
			var punch := 0.06 * exp(-pow((st - 0.32) * 9.0, 2.0))
			_goal(L, 1, Vector3(-0.13, 0.02, 0.28 + punch), env, Vector3(-1.0, -0.6, -0.2), SPACE_CHEST, Vector3(1, 0, 0), Vector3(0, 0, 1))
			_vote(1, "thumbs_up", env)
			L.chest += Vector3(-0.04, 0.06, 0.0) * env
			L.head += Vector3(-0.05, 0.0, 0.08) * env
		"helmet_tap":
			# The tell: elbow thrown wide, index on the right ear pod, two taps.
			var tap_env := smoothstep(0.0, 0.18, st) * (1.0 - smoothstep(0.62, dur, st)) * able
			var off := 0.0
			if st < 0.22:
				off = lerpf(0.2, 0.03, smoothstep(0.0, 0.22, st))
			elif st < 0.3:
				off = lerpf(0.03, 0.0, smoothstep(0.22, 0.3, st))
			elif st < 0.41:
				off = 0.03 * sin(PI * (st - 0.3) / 0.22)
			elif st < 0.52:
				off = lerpf(0.03, 0.0, smoothstep(0.41, 0.52, st))
			else:
				off = 0.2 * smoothstep(0.52, dur, st)
			var fingers := Vector3(1.0, 0.15, 0.25).normalized()
			var contact := Vector3(-0.212, 0.095, 0.015)
			var g := _goal(L, 1, contact - fingers * off, tap_env, Vector3(-1.0, 0.6, -0.15), SPACE_HEAD, Vector3(0.0, -0.4, 1.0), fingers)
			g["contact"] = Vector3.ZERO
			g["contact_kind"] = "tip"
			_vote(1, "point", tap_env)
			L.head += Vector3(0.0, -0.08, 0.1) * tap_env
			L.busy += tap_env * 0.5
		"step_back":
			# One retreating step (right foot, then the left catches up), arms out a touch.
			var a := smoothstep(0.0, 0.45, st)
			var b := smoothstep(0.35, 0.85, st)
			L.feet[1] += Vector3(0.0, 0.07 * sin(PI * clampf(st / 0.45, 0.0, 1.0)), -STEP_BACK * a)
			L.feet[0] += Vector3(0.0, 0.06 * sin(PI * clampf((st - 0.35) / 0.5, 0.0, 1.0)), -STEP_BACK * b)
			L.hips += Vector3(0.0, -0.025 * sin(PI * clampf(st / dur, 0.0, 1.0)), -STEP_BACK * smoothstep(0.05, 0.8, st))
			L.chest += Vector3(-0.08 * sin(PI * clampf(st / 0.6, 0.0, 1.0)), 0.0, 0.0)
			L.spread += 0.12 * env


## set_reach: the fingertip (or palm) on a world target, top priority on that arm;
## beyond arm's length the chest leans (up to 12 degrees) and the shoulder reaches.
func _reach_layer(L: Dictionary) -> void:
	for side in 2:
		var r: Dictionary = _reach[side]
		var w: float = r.get("w", 0.0)
		if w <= 0.001:
			continue
		var s := 1.0 if side == 0 else -1.0
		var target: Vector3 = r.target
		var tr: Vector3 = global_transform.affine_inverse() * target if is_inside_tree() else target
		var palm_w: Vector3 = r.palm
		var shoulder := Vector3(s * 0.235, 1.43, 0.0)
		var dir := (tr - shoulder).normalized()
		var palm := Vector3.ZERO
		var fingers := dir
		var g: Dictionary
		if palm_w != Vector3.ZERO:
			palm = (global_transform.basis.inverse() * palm_w if is_inside_tree() else palm_w).normalized()
			var up_hint := Vector3.UP if absf(palm.dot(Vector3.UP)) < 0.9 else Vector3.BACK
			fingers = (up_hint - palm * up_hint.dot(palm)).normalized()
			g = _goal(L, side, tr, w, Vector3(s, -0.6, -0.2), SPACE_ROOT, palm, fingers, PRI_REACH)
			g["contact"] = Vector3(0.022 * (-s), -0.055, 0.0)
			g["contact_kind"] = "palm"
		else:
			palm = Vector3(0.0, -1.0, 0.0) if absf(dir.y) < 0.8 else Vector3(0.0, 0.0, -1.0)
			g = _goal(L, side, tr, w, Vector3(s, -0.6, -0.2), SPACE_ROOT, palm, fingers, PRI_REACH)
			g["contact"] = Vector3.ZERO
			g["contact_kind"] = "tip"
		# Beyond reach: lean the chest toward it and push the shoulder forward.
		var excess := tr.distance_to(shoulder) - (ARM_LEN + 0.13) * 0.93
		if excess > 0.0:
			var k := clampf(excess / 0.18, 0.0, 1.0) * w
			L.chest += Vector3(0.21 * k * clampf(dir.z + 0.3, 0.0, 1.0), clampf(atan2(dir.x, dir.z), -0.5, 0.5) * 0.3 * k, 0.0)
			L.shoulder[side] += 0.04 * k
		if String(r.get("glove", "")) != "":
			_vote(side, r.glove, w)


## Stagger: the torso reels along the push, arms windmill, the knees buckle and the
## foot on the push side takes a catch step; everything settles by STAGGER_TIME.
func _stagger_layer(L: Dictionary, t: float) -> void:
	var st := _stagger_t
	var k := _stagger_k
	var env := smoothstep(0.0, 0.07, st) * (1.0 - smoothstep(0.45, STAGGER_TIME, st))
	var wob := sin(st * 11.0) * exp(-st * 3.0)
	var push := _stagger_push
	var local_push := Vector3(push.x, 0.0, push.z)
	L.hips += (local_push * 0.09 + Vector3(0.0, -0.07, 0.0)) * env * k
	L.hips_rot += Vector3(-0.12 * push.z, 0.0, 0.18 * push.x) * env * k
	L.chest += Vector3(0.45 * push.z + 0.12 * wob, 0.25 * wob, -0.3 * push.x) * env * k
	L.head += Vector3(0.35 * push.z + 0.25 * wob, 0.0, -0.25 * push.x + 0.2 * wob) * env * k
	L.swing += 0.8 * sin(t * 9.0) * env * k
	L.spread += 0.75 * env * k
	L.elbow += 0.5 * env * k
	var lead: int = 0 if push.x > 0.0 else 1
	var step := smoothstep(0.06, 0.28, st) * (1.0 - smoothstep(0.7, STAGGER_TIME, st))
	var lift := sin(PI * clampf((st - 0.06) / 0.22, 0.0, 1.0)) * 0.08
	L.feet[lead] += (local_push * 0.24 * step + Vector3(0.0, lift, 0.0)) * k
	var step2 := smoothstep(0.32, 0.5, st) * (1.0 - smoothstep(0.75, STAGGER_TIME, st))
	L.feet[1 - lead] += local_push * 0.1 * step2 * k
	_vote(0, "brace", env)
	_vote(1, "brace", env)
	L.busy += env


## Get-up: from the downed pose onto one knee with the right hand pushing off the
## floor and the left on the knee, then up.
func _get_up_layer(L: Dictionary) -> void:
	var u := _getup_t
	var w := smoothstep(0.05, 0.45, u) * (1.0 - smoothstep(0.62, GET_UP_TIME, u))
	_kneel(L, w, 1)
	L.chest += Vector3(0.55, 0.15, 0.0) * w
	L.head += Vector3(0.35, 0.0, 0.0) * w
	var push := 1.0 - smoothstep(0.55, 0.85, u)
	_goal(L, 1, Vector3(-0.24, 0.07, 0.16), w * push, Vector3(-1.0, 0.2, -0.3), SPACE_ROOT, Vector3(0.0, -1.0, 0.0), Vector3(0.0, 0.0, 1.0))
	_goal(L, 0, Vector3(0.1, 0.56, 0.3), w, Vector3(1.0, -0.4, -0.3), SPACE_ROOT, Vector3(0.0, -1.0, 0.0), Vector3(0.0, -0.3, 1.0))
	_vote(1, "open", w * push)
	_vote(0, "relaxed", w)
	L.busy += w


## Root-space wrist path of play_draw(): down to the holster grip on the right thigh,
## then a rising arc into the aim. `aim` is the aiming wrist transform.
func _draw_wrist(u: float, aim: Transform3D) -> Transform3D:
	var hang := Vector3(-0.235, 0.87, 0.0)
	var holster := Vector3(-0.17, 0.85, -0.085)
	if u < 0.28:
		return Transform3D(Basis.IDENTITY, hang.lerp(holster, smoothstep(0.0, 1.0, u / 0.28)))
	var v := smoothstep(0.0, 1.0, (u - 0.28) / 0.72)
	var ctrl := Vector3(-0.3, 1.12, 0.18)
	var p := holster.lerp(ctrl, v).lerp(ctrl.lerp(aim.origin, v), v)
	return Transform3D(Basis.IDENTITY.slerp(aim.basis, v), p)


## Root-space glove basis with the palm facing `palm` and the fingers along `fingers`
## (side 0 = left glove, 1 = right). The glove's palm normal is +X for the right hand
## and -X for the left; the fingers run along -Y.
static func _hand_basis(side: int, palm: Vector3, fingers: Vector3) -> Basis:
	var f := fingers.normalized()
	var pn := (palm - f * palm.dot(f))
	if pn.length_squared() < 1e-6:
		pn = f.cross(Vector3.UP) if absf(f.dot(Vector3.UP)) < 0.9 else f.cross(Vector3.RIGHT)
	pn = pn.normalized()
	var x := pn * (1.0 if side == 1 else -1.0)
	var y := -f
	return Basis(x, y, x.cross(y)).orthonormalized()


# --- full-body poses ------------------------------------------------------------------

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
	# Left leg straight, right knee bent and fallen outward.
	out[CrewBody.L_LEG].basis = Basis.from_euler(Vector3(-0.12, 0.0, 0.12))
	out[CrewBody.L_SHIN].basis = Basis.from_euler(Vector3(0.18, 0.0, 0.0))
	out[CrewBody.L_FOOT].basis = Basis.from_euler(Vector3(0.6, 0.15, 0.0))
	out[CrewBody.R_LEG].basis = Basis.from_euler(Vector3(-0.85, 0.0, -0.55))
	out[CrewBody.R_SHIN].basis = Basis.from_euler(Vector3(1.35, 0.0, 0.0))
	out[CrewBody.R_FOOT].basis = Basis.from_euler(Vector3(0.45, -0.2, 0.0))
	return out


## Held across the carrier's arms (bridal carry): pelvis at the model origin,
## head toward +X, face up, legs hanging over the carrier's forearm. The head lolls,
## the lower arm swings and the legs trail on springs driven by the carrier's stride.
func _carried_pose(t: float) -> Array[Transform3D]:
	var out := _rest_pose()
	var sway := 0.05 * sin(t * 3.0)
	var dh := _dangle[0]
	var da := _dangle[1]
	var dl := _dangle[2]
	var lay := Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
	out[CrewBody.HIPS] = Transform3D(lay * Basis.from_euler(Vector3(0.25, 0.0, 0.0)), Vector3(-0.06, 0.02, 0.0))
	out[CrewBody.SPINE].basis = Basis.from_euler(Vector3(-0.32 + sway * 0.3, 0.0, 0.0))
	out[CrewBody.CHEST].basis = Basis.from_euler(Vector3(-0.22, 0.0, 0.0))
	out[CrewBody.NECK].basis = Basis.from_euler(Vector3(-0.35 + dh * 0.5, dh * 0.3, 0.0))
	out[CrewBody.HEAD].basis = Basis.from_euler(Vector3(-0.4 + sway + dh, 0.2 + dh * 0.4, dh * 0.3))
	# One arm dangles toward the floor, the other lies on the chest.
	out[CrewBody.L_ARM].basis = Basis.from_euler(Vector3(1.45 + sway + da, 0.0, 0.1 + da * 0.3))
	out[CrewBody.L_FORE].basis = Basis.from_euler(Vector3(-0.15 - absf(da) * 0.3, 0.0, 0.0))
	out[CrewBody.R_ARM].basis = Basis.from_euler(Vector3(-0.3, 0.0, -0.2))
	out[CrewBody.R_FORE].basis = Basis.from_euler(Vector3(-1.5, 0.0, 0.0)) * Basis(Vector3.UP, -0.9)
	for leg in [CrewBody.L_LEG, CrewBody.R_LEG]:
		var s := 1.0 if leg == CrewBody.L_LEG else -1.0
		out[leg].basis = Basis.from_euler(Vector3(-0.55 + 0.06 * s + dl * 0.3, 0.0, s * 0.1))
		out[leg + 1].basis = Basis.from_euler(Vector3(1.45 - sway * s + dl, 0.0, 0.0))
		out[leg + 2].basis = Basis.from_euler(Vector3(0.5, 0.0, 0.0))
	return out


## Being dragged by the right wrist: on the back, head first toward +Z, the torso
## pulled up toward the raised arm (DRAG_HANDLE), head lolling, heels trailing.
func _dragged_pose(t: float) -> Array[Transform3D]:
	var out := _rest_pose()
	var bump := 0.04 * sin(t * 7.3) * clampf(_speed, 0.0, 1.5)
	var c := cos(0.3)
	var sn := sin(0.3)
	var lay := Basis(Vector3(-1, 0, 0), Vector3(0, sn, c), Vector3(0, c, -sn))
	out[CrewBody.HIPS] = Transform3D(lay * Basis(Vector3.UP, 0.12), Vector3(0.0, 0.15, 0.0))
	out[CrewBody.SPINE].basis = Basis.from_euler(Vector3(0.16, 0.05, 0.04))
	out[CrewBody.CHEST].basis = Basis.from_euler(Vector3(0.12, 0.1, 0.06))
	out[CrewBody.NECK].basis = Basis.from_euler(Vector3(-0.3 + bump, 0.2, 0.1))
	out[CrewBody.HEAD].basis = Basis.from_euler(Vector3(-0.35 + bump, 0.45 + 0.08 * sin(t * 1.3), 0.2))
	out[CrewBody.L_ARM].basis = Basis.from_euler(Vector3(0.2, 0.0, 0.45))
	out[CrewBody.L_FORE].basis = Basis.from_euler(Vector3(-0.3, 0.0, 0.0))
	out[CrewBody.L_HAND].basis = Basis.from_euler(Vector3(0.25, 0.0, 0.2))
	for leg in [CrewBody.L_LEG, CrewBody.R_LEG]:
		var s := 1.0 if leg == CrewBody.L_LEG else -1.0
		out[leg].basis = Basis.from_euler(Vector3(-0.36 + 0.03 * s + bump * 0.5 * s, 0.0, s * 0.09))
		out[leg + 1].basis = Basis.from_euler(Vector3(0.14, 0.0, 0.0))
		out[leg + 2].basis = Basis.from_euler(Vector3(-0.2, s * 0.55, 0.0))
	# Right arm stretched to the handle.
	var chest_xf := Transform3D.IDENTITY
	for b in [CrewBody.HIPS, CrewBody.SPINE, CrewBody.CHEST]:
		chest_xf = chest_xf * out[b]
	var lt := chest_xf.affine_inverse() * DRAG_HANDLE
	var ik := _two_bone(out[CrewBody.R_ARM].origin, lt, chest_xf.basis.inverse() * Vector3(-1.0, 0.3, 0.0), 0.295, 0.27, -1.0)
	out[CrewBody.R_ARM].basis = ik[0]
	out[CrewBody.R_FORE].basis = ik[1]
	out[CrewBody.R_HAND].basis = Basis.from_euler(Vector3(0.3, 0.0, 0.0))
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
