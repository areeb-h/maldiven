class_name CrewHand
extends Node3D
## Armoured EVA glove for the crew suit: premium "collectible figure" styling (glossy
## player-colour plates over satin graphite and grippy rubber, a brushed-metal wrist
## ring, a glowing status light), a Node3D finger rig, GPU skinning in ONE draw call,
## and fully procedural, spring-blended hand poses with idle life and secondary motion.
##
## LOCAL AXES (identical to the body's bind-pose bone axes, so attach with IDENTITY):
##   origin  the wrist joint (the pivot of CrewBody's LeftHand / RightHand bone)
##   -Y      the fingers (they hang along -Y when the arm hangs down)
##   +Z      the thumb / index side (forward when the arm hangs at the side)
##   +X*side the palm normal: side = +1 (right hand) palm faces +X, side = -1 (left
##           hand) palm faces -X. Either way the palm faces the body and the back of
##           the hand faces outward, matching CrewModel (character's left = +X).
## The cuff spans y = +0.012 .. -0.030 (metal ring on top meets the forearm ribs);
## the middle fingertip reaches y = -0.148 when open. Palm 9.4 cm wide at the knuckles.
##
## Usage:
##   var hand := CrewHand.build(color, -1)        # left hand
##   model.bones[CrewBody.L_HAND].add_child(hand) # transform stays IDENTITY
##   hand.set_pose("grip_large")                  # spring-blended, no popping
##   hand.set_motion(speed, delta)                # every frame: idle life + inertia
##   item.reparent(hand.grip_node("cell"), false)  # held item exactly in the palm
##
## Joint frames (all bones): local X = flexion hinge (positive rotation curls toward the
## palm), local Y = toward the parent joint (the digit points along -Y), local Z = the
## dorsal side (back of the hand / nail). Pose angles are (flex, twist, spread) per bone.

enum { WRIST, PALM, INDEX1, INDEX2, INDEX3, MIDDLE1, MIDDLE2, MIDDLE3, RING1, RING2, RING3,
	PINKY1, PINKY2, PINKY3, THUMB1, THUMB2, THUMB3 }

const BONE_COUNT := 17
const BONE_NAMES: Array[String] = ["Wrist", "Palm", "Index1", "Index2", "Index3", "Middle1", "Middle2", "Middle3",
	"Ring1", "Ring2", "Ring3", "Pinky1", "Pinky2", "Pinky3", "Thumb1", "Thumb2", "Thumb3"]
const PARENTS: Array[int] = [-1, 0, 1, 2, 3, 1, 5, 6, 1, 8, 9, 1, 11, 12, 1, 14, 15]
## The suit shader fades the ghost below ~0.78 m of model-space height (the legs turn
## into a wisp). The glove's palette is lifted by this much and the mesh instance
## lowered by the same amount, so world positions are unchanged but the shader sees
## the glove above the fade.
const MODEL_Y_BIAS := 1.0
## Fingers besides the thumb. Both layouts were rendered side by side on the crew body
## (build_with_fingers): at gameplay distance (~5-8 px hands) they are identical, while in
## close-ups (lobby, key art, emotes, grips) four fingers read as a premium glove and
## wrap items believably; three read cartoonish. Cost: 1362 vs 1208 triangles.
const FINGERS := 4
const POSES: Array[String] = ["relaxed", "open", "fist", "grip_large", "grip_core", "grip_gun", "grip_gun_trigger",
	"point", "thumbs_up", "wave", "push", "brace", "limp", "ghost"]
const ANCHORS: Array[String] = ["cell", "core", "gun"]
## Budgets (per hand). The smoke test checks them.
const MAX_TRIANGLES := 1500
const MAX_DRAW_CALLS := 2

## Finger layout for the canonical RIGHT hand (palm +X, dorsal -X, thumb +Z).
## mcp: knuckle pivot; dir: rest pointing direction; len: phalanx lengths
## (proximal, middle, distal); r: radii at MCP, PIP, DIP and the fingertip.
const _FINGER_SPECS := {
	4: [
		{"bone": INDEX1, "mcp": Vector3(-0.0015, -0.0718, 0.0334), "dir": Vector3(0.0, -1.0, 0.08), "len": Vector3(0.026, 0.0175, 0.0145), "r": Vector4(0.0103, 0.0098, 0.0093, 0.0096)},
		{"bone": MIDDLE1, "mcp": Vector3(-0.0015, -0.0748, 0.0111), "dir": Vector3(0.0, -1.0, 0.025), "len": Vector3(0.0285, 0.019, 0.0155), "r": Vector4(0.0106, 0.0101, 0.0096, 0.0099)},
		{"bone": RING1, "mcp": Vector3(-0.0015, -0.0728, -0.0111), "dir": Vector3(0.0, -1.0, -0.035), "len": Vector3(0.027, 0.018, 0.015), "r": Vector4(0.0102, 0.0097, 0.0092, 0.0095)},
		{"bone": PINKY1, "mcp": Vector3(-0.0015, -0.0678, -0.0326), "dir": Vector3(0.0, -1.0, -0.1), "len": Vector3(0.021, 0.0145, 0.0125), "r": Vector4(0.0094, 0.0089, 0.0084, 0.0087)},
	],
	3: [
		{"bone": INDEX1, "mcp": Vector3(-0.0015, -0.0725, 0.0298), "dir": Vector3(0.0, -1.0, 0.07), "len": Vector3(0.027, 0.018, 0.015), "r": Vector4(0.0136, 0.013, 0.0123, 0.0127)},
		{"bone": MIDDLE1, "mcp": Vector3(-0.0015, -0.0755, 0.0), "dir": Vector3(0.0, -1.0, 0.0), "len": Vector3(0.0285, 0.019, 0.0155), "r": Vector4(0.014, 0.0134, 0.0127, 0.0131)},
		{"bone": PINKY1, "mcp": Vector3(-0.0015, -0.0715, -0.0298), "dir": Vector3(0.0, -1.0, -0.07), "len": Vector3(0.025, 0.017, 0.014), "r": Vector4(0.0132, 0.0126, 0.012, 0.0124)},
	],
}
## Thumb: CMC (base, inside the thenar pad), MCP and IP pivots of the canonical right hand.
const _THUMB_CMC := Vector3(0.007, -0.016, 0.026)
const _THUMB_META_DIR := Vector3(0.34, -0.78, 0.36)
const _THUMB_META_LEN := 0.03
const _THUMB_DIR := Vector3(0.3, -0.88, 0.24)
const _THUMB_LEN := Vector2(0.023, 0.019)
const _THUMB_R := Vector4(0.0128, 0.0112, 0.0104, 0.0107)  # CMC, MCP, IP, tip
const _THUMB_NAIL := Vector3(-0.6, 0.0, 0.8)  # dorsal (nail) direction hint
const _PALM_PIVOT := Vector3(0.0, -0.006, 0.0)
## Width / thickness of the finger section (curl-plane section stays circular so the
## rounded joint caps cover every curl angle exactly).
const _WIDTH := 1.0

## Pose table (canonical right hand, radians).
##   w: wrist (flex toward the palm, twist = pronation, deviation toward the thumb)
##   f: per finger (index, middle, ring, pinky): MCP flex, PIP flex, DIP flex, spread (+ = toward the thumb)
##   t: thumb CMC flex, CMC twist (opposition), CMC spread (abduction away from the palm), MCP flex, IP flex
const _POSE_DATA := {
	"open": {"w": Vector3(-0.05, 0.0, 0.0), "f": [Vector4(-0.04, 0.02, 0.02, 0.17), Vector4(-0.04, 0.02, 0.02, 0.05), Vector4(-0.03, 0.02, 0.02, -0.08), Vector4(-0.02, 0.03, 0.03, -0.22)],
		"t": [-0.1, 0.05, 0.42, -0.05, 0.0]},
	"relaxed": {"w": Vector3(0.12, 0.0, -0.04), "f": [Vector4(0.24, 0.36, 0.22, 0.06), Vector4(0.3, 0.44, 0.26, 0.0), Vector4(0.36, 0.5, 0.3, -0.05), Vector4(0.44, 0.58, 0.34, -0.1)],
		"t": [0.33, 0.11, 0.2, 0.2, 0.22]},
	"fist": {"w": Vector3(0.0, 0.0, 0.0), "f": [Vector4(0.94, 1.24, 0.30, 0.0), Vector4(1.34, 1.51, 0.59, 0.0), Vector4(1.22, 1.37, 0.99, -0.02), Vector4(1.0, 1.5, 0.96, -0.05)],
		"t": [-0.66, 1.0, 0.2, 1.2, 1.04]},
	"grip_large": {"w": Vector3(0.0, 0.0, 0.0), "f": [Vector4(0.23, 0.39, 0.13, 0.07), Vector4(0.15, 0.34, 0.14, 0.01), Vector4(0.14, 0.33, 0.16, -0.05), Vector4(0.19, 0.50, 0.14, -0.11)],
		"t": [-0.44, 0.10, 0.26, -0.20, -0.06]},
	"grip_core": {"w": Vector3(0.0, 0.0, 0.0), "f": [Vector4(0.73, 0.73, 0.16, 0.20), Vector4(0.87, 0.67, 0.23, 0.06), Vector4(0.82, 0.66, 0.22, -0.08), Vector4(0.69, 0.54, 0.15, -0.24)],
		"t": [0.43, 0.09, 0.72, 0.08, 0.12]},
	"grip_gun": {"w": Vector3(-0.45, 0.0, 0.0), "f": [Vector4(0.08, 0.06, 0.04, 0.02), Vector4(-0.01, 1.73, 1.30, 0.0), Vector4(-0.05, 1.72, 1.30, -0.03), Vector4(-0.13, 1.49, 1.22, -0.07)],
		"t": [-0.70, 0.35, -0.20, 0.42, 0.60]},
	"grip_gun_trigger": {"w": Vector3(-0.45, 0.0, 0.0), "f": [Vector4(0.42, 0.88, 0.42, 0.0), Vector4(-0.01, 1.73, 1.30, 0.0), Vector4(-0.05, 1.72, 1.30, -0.03), Vector4(-0.13, 1.49, 1.22, -0.07)],
		"t": [-0.70, 0.35, -0.20, 0.42, 0.60]},
	"point": {"w": Vector3(-0.05, 0.0, 0.0), "f": [Vector4(0.0, 0.03, 0.03, 0.04), Vector4(1.0, 1.25, 0.30, 0.0), Vector4(1.35, 1.21, 1.06, -0.02), Vector4(1.0, 1.5, 0.96, -0.05)],
		"t": [0.05, 0.89, 0.41, 1.2, 0.64]},
	"thumbs_up": {"w": Vector3(0.0, 0.0, 0.0), "f": [Vector4(0.94, 1.24, 0.30, 0.0), Vector4(1.34, 1.51, 0.59, 0.0), Vector4(1.22, 1.37, 0.99, -0.02), Vector4(1.0, 1.5, 0.96, -0.05)],
		"t": [-0.32, -0.15, 0.32, -0.12, -0.1]},
	"wave": {"w": Vector3(-0.15, 0.0, 0.0), "f": [Vector4(0.02, 0.06, 0.04, 0.1), Vector4(0.0, 0.05, 0.04, 0.03), Vector4(0.02, 0.06, 0.04, -0.04), Vector4(0.05, 0.08, 0.05, -0.12)],
		"t": [-0.1, 0.05, 0.45, 0.0, 0.05]},
	"push": {"w": Vector3(-0.35, 0.0, 0.0), "f": [Vector4(-0.1, 0.0, 0.0, 0.08), Vector4(-0.1, 0.0, 0.0, 0.02), Vector4(-0.09, 0.0, 0.0, -0.04), Vector4(-0.08, 0.0, 0.0, -0.1)],
		"t": [-0.1, 0.0, 0.38, -0.05, -0.05]},
	"brace": {"w": Vector3(-0.5, 0.0, 0.0), "f": [Vector4(-0.12, 0.08, 0.14, 0.26), Vector4(-0.12, 0.08, 0.14, 0.08), Vector4(-0.1, 0.1, 0.14, -0.12), Vector4(-0.08, 0.12, 0.16, -0.34)],
		"t": [-0.2, 0.0, 0.75, -0.08, 0.05]},
	"limp": {"w": Vector3(0.32, 0.0, -0.08), "f": [Vector4(0.2, 0.32, 0.2, 0.05), Vector4(0.28, 0.42, 0.24, 0.0), Vector4(0.36, 0.5, 0.3, -0.04), Vector4(0.46, 0.6, 0.36, -0.08)],
		"t": [0.2, 0.18, 0.18, 0.12, 0.15]},
	"ghost": {"w": Vector3(0.06, 0.0, 0.0), "f": [Vector4(0.12, 0.2, 0.14, 0.1), Vector4(0.16, 0.24, 0.16, 0.02), Vector4(0.2, 0.28, 0.18, -0.06), Vector4(0.26, 0.32, 0.2, -0.14)],
		"t": [0.0, 0.08, 0.38, 0.08, 0.1]},
}
## Index finger at the bottom of a trigger squeeze.
const _SQUEEZE := Vector3(0.62, 1.22, 0.58)
## Per pose: idle breath amplitude, fidget family ("idle", "grip", "gun" or ""), run curl.
const _POSE_LIFE := {
	"open": [0.7, "idle", 0.0], "relaxed": [1.0, "idle", 1.0], "fist": [0.4, "", 0.0], "grip_large": [0.35, "grip", 0.0],
	"grip_core": [0.35, "grip", 0.0], "grip_gun": [0.3, "gun", 0.0], "grip_gun_trigger": [0.25, "", 0.0],
	"point": [0.4, "", 0.0], "thumbs_up": [0.4, "", 0.0], "wave": [0.5, "", 0.0], "push": [0.2, "", 0.0],
	"brace": [0.3, "", 0.0], "limp": [0.3, "", 0.0], "ghost": [0.0, "", 0.0], "curl": [0.8, "", 0.6],
}
## Uniform scale the Props blaster takes in the hand (see _GRIP_ANCHORS["gun"]).
const GUN_SCALE := 0.62
## Item anchors for the canonical right hand. `pivot` (item space) lands on `center`
## (hand space); item +Y runs along the knuckle line toward the thumb, tilted by `tilt`
## toward the palm normal, then rolled by `roll` about the palm normal. The gun's
## barrel (item -Z) runs along the fingers; cell and core are yawed (`yaw`) so their
## front (+Z) faces where the fingers point, i.e. forward when carried.
## `scale` is the item's uniform scale in the hand.
const _GRIP_ANCHORS := {
	# Power cell (Props casing radius 0.16, glow band 0.168): held from the side over the
	# upper glow band, palm on the casing, fingers wrapping round the curve.
	"cell": {"tilt": 0.0, "yaw": PI, "scale": 1.0, "pivot": Vector3(0.0, 0.39, 0.0), "center": Vector3(0.1866, -0.063, 0.0)},
	# Core (cage radius 0.235, field 0.24): cradled from below-side, palm turned 35 deg up.
	"core": {"tilt": 0.61, "yaw": PI, "scale": 1.0, "pivot": Vector3(0.0, 0.36, 0.0), "center": Vector3(0.2585, -0.064, 0.0)},
	# Blaster: grip in the palm, barrel along the extended index finger. The Props
	# blaster grip is 11 cm deep (a 7.4 cm palm cannot close round it), so the held
	# blaster is shown at pistol scale.
	# `roll` (about the palm normal) squares the raked grip to the knuckle line, which
	# cants the barrel 16 deg toward the thumb like a real pistol hold.
	"gun": {"tilt": 0.0, "roll": -0.28, "scale": GUN_SCALE, "pivot": Vector3(0.0, 0.1, 0.11), "center": Vector3(0.0435, -0.0424, 0.012)},
}
## Grip pose whose wrist angle each anchor is measured with.
const _ANCHOR_POSE := {"cell": "grip_large", "core": "grip_core", "gun": "grip_gun"}

static var _mesh_cache := {}
static var _tri_cache := {}
static var _rest_cache := {}

var side := 1
var color := Color.WHITE
var finger_count := FINGERS
## Scales the idle micro-motion, fidgets and inertia (0 = perfectly still; tests use it).
var micro_motion := 1.0
var mesh_instance: MeshInstance3D
var joints: Array[Node3D] = []

var _mat: ShaderMaterial
var _ghost_mat: ShaderMaterial
var _ghost_look := false
var _local_rest: Array[Transform3D] = []
var _bind_inv: Array[Transform3D] = []
var _palette: Array[Projection] = []
var _xf: Array[Transform3D] = []

# Pose springs: (flex, twist, spread) per bone, critically damped toward _target.
var _pose := "relaxed"
var _x := PackedFloat32Array()
var _v := PackedFloat32Array()
var _target := PackedFloat32Array()
var _omega := 30.0
var _out := PackedFloat32Array()

# Layer weights and timers.
var _driven := false
var _time := 0.0
var _speed := 0.0
var _run_w := 0.0
var _idle_w := 1.0
var _wave_w := 0.0
var _ghost_w := 0.0
var _brace_w := 0.0
var _breath_amp := 1.0
var _run_curl := 1.0
var _trigger_t := -1.0
var _fidget_t := -1.0
var _fidget_kind := 0
var _fidget_finger := 0
var _fidget_timer := 5.0
var _rng := RandomNumberGenerator.new()
var _phase := 0.0

# Secondary motion, driven by the wrist's acceleration in hand space: per digit a base
# (MCP) spring and a delayed tip spring [0..9] react to palm-normal acceleration; a
# swing-drag spring [10] trails the hand behind the arm swing and a fan spring [11]
# follows it a beat later on the finger spread (overlapping action).
var _prev_p := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _motion_ready := 0
var _lag := PackedFloat32Array()
var _lag_v := PackedFloat32Array()


## A hand for `side` (-1 left, +1 right) in the suit colour.
static func build(p_color: Color, p_side: int) -> CrewHand:
	return build_with_fingers(p_color, p_side, FINGERS)


## Same as build() with an explicit finger layout (4, or the stylised 3). Used by the
## look-dev comparison; gameplay uses build().
static func build_with_fingers(p_color: Color, p_side: int, fingers: int) -> CrewHand:
	var h := CrewHand.new()
	h._setup(p_color, -1 if p_side < 0 else 1, 3 if fingers == 3 else 4)
	return h


## Triangles in the hand mesh for a layout (same for both sides).
static func triangle_count(fingers := FINGERS) -> int:
	hand_mesh(1, fingers)
	return _tri_cache[fingers]


## Shared, colour-independent skinned mesh (colour lives in the material).
static func hand_mesh(p_side: int, fingers := FINGERS) -> ArrayMesh:
	var key := "%d:%d" % [p_side, fingers]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _build_mesh(p_side, fingers)
	return _mesh_cache[key]


func _setup(p_color: Color, p_side: int, fingers: int) -> void:
	color = p_color
	side = p_side
	finger_count = fingers
	name = "LeftGlove" if side < 0 else "RightGlove"
	_rng.randomize()
	_phase = _rng.randf() * TAU
	_fidget_timer = _rng.randf_range(2.0, 6.0)
	var rest := _rest_frames(side, finger_count)
	var rest_xf: Array = rest
	for i in BONE_COUNT:
		var g: Transform3D = rest_xf[i]
		var p := PARENTS[i]
		var parent_g: Transform3D = rest_xf[p] if p >= 0 else Transform3D.IDENTITY
		_local_rest.append(parent_g.affine_inverse() * g)
		_bind_inv.append(g.affine_inverse())
		_xf.append(g)
		var n := Node3D.new()
		n.name = BONE_NAMES[i]
		n.transform = _local_rest[i] if i > 0 else Transform3D.IDENTITY
		if i == 0:
			add_child(n)
		else:
			joints[p].add_child(n)
		joints.append(n)
	for i in CrewMaterials.BONE_COUNT:
		_palette.append(Projection())
	_x.resize(BONE_COUNT * 3)
	_v.resize(BONE_COUNT * 3)
	_out.resize(BONE_COUNT * 3)
	_lag.resize(12)
	_lag_v.resize(12)
	_mat = CrewMaterials.instance("suit", color)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Glove"
	mesh_instance.mesh = hand_mesh(side, finger_count)
	mesh_instance.material_override = _mat
	mesh_instance.position = Vector3(0.0, -MODEL_Y_BIAS, 0.0)
	mesh_instance.custom_aabb = AABB(Vector3(-0.16, MODEL_Y_BIAS - 0.26, -0.16), Vector3(0.32, 0.3, 0.32))
	add_child(mesh_instance)
	_target = _dofs("relaxed")
	_x = _target.duplicate()
	_apply_pose_life("relaxed", "")
	_compose()
	_upload()


# --- public API ---------------------------------------------------------------------

## Blend to a named pose (see POSES; "trigger" is an alias of "grip_gun_trigger").
## Every joint follows a critically damped spring that settles in about `blend_time`
## seconds, so switching mid-blend never pops. blend_time <= 0 snaps.
func set_pose(pose_name: String, blend_time := 0.15) -> void:
	var key := "grip_gun_trigger" if pose_name == "trigger" else pose_name
	if not _POSE_DATA.has(key):
		push_warning("CrewHand: unknown pose " + pose_name)
		return
	var old_family := _fidget_family()
	_pose = key
	_target = _dofs(key)
	_set_blend(blend_time)
	_apply_pose_life(key, old_family)
	set_ghost_look(key == "ghost")


func get_pose() -> String:
	return _pose


## Continuous open (0) .. fist (1) for procedural use; call as often as you like.
func set_curl(amount: float) -> void:
	var a := clampf(amount, 0.0, 1.0)
	var open := _dofs("open")
	var fist := _dofs("fist")
	for i in _target.size():
		_target[i] = lerpf(open[i], fist[i], a)
	if _pose != "curl":
		var old_family := _fidget_family()
		_pose = "curl"
		_set_blend(0.1)
		_apply_pose_life("curl", old_family)
		set_ghost_look(false)


## Quick index-finger squeeze (~0.12 s); works from any pose, best from grip_gun(_trigger).
func trigger_pull() -> void:
	_trigger_t = 0.0


## Per frame: `speed` is the character's ground speed (m/s). Drives idle micro-motion,
## fidgets every 4-9 s, a looser fist while running, and finger inertia (lag and
## overlap) from how the wrist accelerates. Also call it when not moving (speed 0).
func set_motion(speed: float, delta: float) -> void:
	_driven = true
	_step(speed, delta)


## Where a held item's root should sit, in this hand's local space, with the wrist
## at its grip pose: "cell", "core" or "gun" (the gun anchor carries GUN_SCALE).
## Prefer grip_node(): it rides on the Palm joint, so the item follows the wrist.
func get_grip_anchor(kind: String) -> Transform3D:
	if not _GRIP_ANCHORS.has(kind):
		push_warning("CrewHand: unknown grip anchor " + kind)
		return Transform3D.IDENTITY
	return grip_anchor(kind, side)


## A Node3D on the Palm joint at the grip anchor ("cell", "core" or "gun"), created
## on first use. Parent the held item to it with an identity transform.
func grip_node(kind: String) -> Node3D:
	var node_name := "Grip_" + kind
	var palm := joints[PALM]
	var existing := palm.get_node_or_null(node_name) as Node3D
	if existing != null:
		return existing
	var n := Node3D.new()
	n.name = node_name
	var g: Transform3D = _rest_frames(side, finger_count)[PALM]
	n.transform = g.affine_inverse() * _anchor_in_palm(kind, side)
	palm.add_child(n)
	return n


## Static form of get_grip_anchor for a side, usable before any hand exists.
static func grip_anchor(kind: String, p_side: int) -> Transform3D:
	var g: Transform3D = _rest_frames(p_side, FINGERS)[PALM]
	var pose: Dictionary = _POSE_DATA[_ANCHOR_POSE.get(kind, "grip_gun")]
	var w: Vector3 = pose.w
	var m := -1.0 if p_side < 0 else 1.0
	var rot := Basis(Vector3(0, 0, 1), w.z * m) * Basis(Vector3(0, 1, 0), w.y * m) * Basis(Vector3(1, 0, 0), w.x)
	return g * Transform3D(rot, Vector3.ZERO) * g.affine_inverse() * _anchor_in_palm(kind, p_side)


## The anchor in hand space with the wrist straight (moves with the Palm joint).
static func _anchor_in_palm(kind: String, p_side: int) -> Transform3D:
	var spec: Dictionary = _GRIP_ANCHORS.get(kind, _GRIP_ANCHORS["gun"])
	var th: float = spec.tilt
	var sc: float = spec.scale
	var y := Vector3(sin(th), 0.0, cos(th))
	var z := Vector3(0.0, 1.0, 0.0)
	var rot := Basis(Vector3(1, 0, 0), float(spec.get("roll", 0.0))) * Basis(y.cross(z), y, z) * Basis(Vector3.UP, float(spec.get("yaw", 0.0)))
	var pivot: Vector3 = spec.pivot
	var center: Vector3 = spec.center
	var xf := Transform3D(rot.scaled_local(Vector3(sc, sc, sc)), center - rot * (pivot * sc))
	return xf if p_side > 0 else _mirror_xf(xf)


## Ghost look (translucent shader); set_pose("ghost") turns it on, other poses off.
func set_ghost_look(on: bool) -> void:
	if on == _ghost_look:
		return
	_ghost_look = on
	if on and _ghost_mat == null:
		_ghost_mat = CrewMaterials.instance("ghost", color)
	mesh_instance.material_override = _ghost_mat if on else _mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_upload()


## Forward a suit shader uniform (hit_flash, distress, accent_energy ...) so the glove
## reacts with the body.
func set_suit_param(key: String, value: Variant) -> void:
	_mat.set_shader_parameter(key, value)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter(key, value)


func get_material() -> ShaderMaterial:
	return _ghost_mat if _ghost_look else _mat


## Current joint position in hand space (after blending and all motion layers).
func get_joint_position(bone: int) -> Vector3:
	return _xf[bone].origin


## Current joint transform in hand space.
func get_joint_transform(bone: int) -> Transform3D:
	return _xf[bone]


## Tip of a digit (0 thumb, 1 index .. 4 pinky) in hand space.
func get_fingertip(digit: int) -> Vector3:
	var b := THUMB3 if digit == 0 else INDEX3 + (digit - 1) * 3
	var tip_len := _THUMB_LEN.y + _THUMB_R.w
	if digit > 0:
		for spec in _FINGER_SPECS[finger_count]:
			if int(spec.bone) + 2 == b:
				tip_len = (spec.len as Vector3).z + (spec.r as Vector4).w
	return _xf[b] * Vector3(0.0, -tip_len, 0.0)


func _process(delta: float) -> void:
	if not _driven:
		_step(_speed, delta)
	_driven = false


# --- animation ----------------------------------------------------------------------

func _set_blend(blend_time: float) -> void:
	if blend_time <= 0.0:
		_x = _target.duplicate()
		_v.fill(0.0)
		_omega = 40.0
		# Snap the pose layers too (wave swing, ghost float, brace tremor).
		_wave_w = 1.0 if _pose == "wave" else 0.0
		_ghost_w = 1.0 if _pose == "ghost" else 0.0
		_brace_w = 1.0 if _pose == "brace" else 0.0
	else:
		# Critically damped: (1 + w t) e^(-w t) = 5% at t = blend_time.
		_omega = 4.74 / blend_time


func _apply_pose_life(key: String, old_family: String) -> void:
	var life: Array = _POSE_LIFE.get(key, [1.0, "", 0.0])
	_breath_amp = life[0]
	_run_curl = life[2]
	if _fidget_t >= 0.0 and old_family != _family_of(key):
		_fidget_t = -1.0  # a tap or regrip makes no sense in the new pose


func _family_of(key: String) -> String:
	var life: Array = _POSE_LIFE.get(key, [1.0, "", 0.0])
	return life[1]


func _fidget_family() -> String:
	return _family_of(_pose)


func _step(speed: float, delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	_time += dt
	_speed = maxf(speed, 0.0)
	var k := 1.0 - exp(-dt * 6.0)
	_run_w = lerpf(_run_w, smoothstep(2.0, 6.0, _speed), k)
	_idle_w = lerpf(_idle_w, 1.0 - smoothstep(0.2, 1.2, _speed), k)
	_wave_w = lerpf(_wave_w, 1.0 if _pose == "wave" else 0.0, 1.0 - exp(-dt * 8.0))
	_ghost_w = lerpf(_ghost_w, 1.0 if _pose == "ghost" else 0.0, 1.0 - exp(-dt * 3.0))
	_brace_w = lerpf(_brace_w, 1.0 if _pose == "brace" else 0.0, 1.0 - exp(-dt * 10.0))
	if dt > 0.0:
		for i in _x.size():
			# Exact critically damped spring step (stable for any dt).
			var o := _omega * dt
			var e := 1.0 / (1.0 + o + 0.48 * o * o + 0.235 * o * o * o)
			var change := _x[i] - _target[i]
			var temp := (_v[i] + _omega * change) * dt
			_v[i] = (_v[i] - _omega * temp) * e
			_x[i] = _target[i] + (change + temp) * e
		_secondary(dt)
		_update_fidget(dt)
		if _trigger_t >= 0.0:
			_trigger_t += dt
			if _trigger_t > 0.12:
				_trigger_t = -1.0
	_compose()
	_upload()


## Finger inertia: springs driven by the wrist's acceleration in hand space.
func _secondary(dt: float) -> void:
	var gx := global_transform if is_inside_tree() else Transform3D.IDENTITY
	var p := gx.origin
	var vel := (p - _prev_p) / dt
	var acc := Vector3.ZERO
	if _motion_ready == 0 or (p - _prev_p).length() > 1.5:
		# First frame, teleport or respawn: no impulse.
		vel = Vector3.ZERO
		_motion_ready = 0
	elif _motion_ready >= 2:
		acc = (vel - _prev_vel) / dt
	_motion_ready = mini(_motion_ready + 1, 2)
	_prev_p = p
	_prev_vel = vel
	var la := (gx.basis.orthonormalized().transposed() * acc).limit_length(90.0) * micro_motion
	# Accelerating toward the palm leaves the fingers behind (they open), and vice versa.
	var palmar := la.x * float(side)
	var steps := 2
	var h := dt / steps
	for s in steps:
		for f in 5:
			var w0 := TAU * (6.4 - 0.35 * f)
			var force := -palmar * 7.0 + (la.y * 1.5 if f == 0 else 0.0)
			var a0 := -w0 * w0 * _lag[f] - 2.0 * 0.42 * w0 * _lag_v[f] + force
			_lag_v[f] += a0 * h
			_lag[f] += _lag_v[f] * h
			# Tip follows the base a beat later (overlapping action).
			var w1 := TAU * 4.6
			var a1 := -w1 * w1 * (_lag[5 + f] - _lag[f]) - 2.0 * 0.5 * w1 * _lag_v[5 + f]
			_lag_v[5 + f] += a1 * h
			_lag[5 + f] += _lag_v[5 + f] * h
		# Swing drag: the hand trails the arm's swing (deviation away from the
		# acceleration along the knuckle line) and the fingers fan after it a beat later.
		var wd := TAU * 3.6
		var ad := -wd * wd * _lag[10] - 2.0 * 0.38 * wd * _lag_v[10] - la.z * 3.2
		_lag_v[10] += ad * h
		_lag[10] += _lag_v[10] * h
		var wf := TAU * 2.8
		var af := -wf * wf * (_lag[11] - _lag[10] * 0.9) - 2.0 * 0.45 * wf * _lag_v[11]
		_lag_v[11] += af * h
		_lag[11] += _lag_v[11] * h
	for i in 12:
		_lag[i] = clampf(_lag[i], -0.35, 0.35)


func _update_fidget(dt: float) -> void:
	var family := _fidget_family()
	if _fidget_t >= 0.0:
		_fidget_t += dt
		if _fidget_t > _fidget_dur():
			_fidget_t = -1.0
			_fidget_timer = _rng.randf_range(4.0, 9.0)
		return
	if family == "" or _idle_w < 0.6 or micro_motion <= 0.0:
		return
	_fidget_timer -= dt
	if _fidget_timer <= 0.0:
		_fidget_t = 0.0
		match family:
			"idle":
				_fidget_kind = _rng.randi_range(0, 3)
			"grip":
				_fidget_kind = 4
			"gun":
				_fidget_kind = 5
		_fidget_finger = _rng.randi_range(0, 1)


## Test / tooling hook: start a fidget now (0 tap, 1 finger roll, 2 stretch, 3 thumb
## rub, 4 regrip, 5 gun regrip).
func play_fidget(kind: int) -> void:
	_fidget_kind = clampi(kind, 0, 5)
	_fidget_finger = 0
	_fidget_t = 0.0


func _fidget_dur() -> float:
	return [0.75, 1.1, 1.2, 1.3, 1.1, 0.9][_fidget_kind]


static func _bell(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	var s := sin(PI * u)
	return s * s


func _compose() -> void:
	for i in _out.size():
		_out[i] = _x[i]
	var t := _time + _phase
	var mm := micro_motion
	var spec_list: Array = _FINGER_SPECS[finger_count]
	# Idle life: breathing curl, slow incommensurate drift (never frozen).
	var breath := _breath_amp * mm * (0.35 + 0.65 * _idle_w)
	for f in spec_list.size():
		var b: int = spec_list[f].bone
		var ph := float(f) * 0.45
		var drift := 0.6 * sin(t * 0.73 + ph * 2.3) + 0.4 * sin(t * 1.21 + ph * 3.7)
		var d := breath * (0.022 * sin(t * TAU * 0.27 - ph) + 0.014 * drift)
		_add(b, 0, d)
		_add(b + 1, 0, d * 0.8)
		_add(b + 2, 0, d * 0.5)
		_add(b, 2, breath * 0.006 * sin(t * 0.61 + ph * 4.1))
		# Running: a looser fist, held a little tighter as speed rises.
		var rc := _run_curl * _run_w * (0.3 + 0.05 * f)
		_add(b, 0, rc)
		_add(b + 1, 0, rc * 0.9)
		_add(b + 2, 0, rc * 0.4)
		# Inertia (base spring on MCP, delayed tip spring on PIP / DIP).
		var lag_base := _lag[f + 1] * mm
		var lag_tip := _lag[6 + f] * mm
		_add(b, 0, lag_base)
		_add(b + 1, 0, lag_tip * 0.8)
		_add(b + 2, 0, lag_tip * 0.6)
		_add(b, 2, _lag[11] * mm * (0.55 + 0.15 * f))
		# Wave: the wrist swings and the fingers follow a beat behind.
		if _wave_w > 0.001:
			var wv := sin(_time * TAU * 1.7 - 0.9 - f * 0.3)
			_add(b, 0, 0.1 * wv * _wave_w)
			_add(b + 1, 0, 0.08 * wv * _wave_w)
		# Ghost: slow weightless finger float.
		if _ghost_w > 0.001:
			var gf := sin(t * 1.35 + f * 0.8)
			_add(b, 0, 0.13 * gf * _ghost_w)
			_add(b + 1, 0, 0.11 * sin(t * 1.35 + f * 0.8 - 0.7) * _ghost_w)
			_add(b + 2, 0, 0.08 * sin(t * 1.35 + f * 0.8 - 1.3) * _ghost_w)
			_add(b, 2, 0.06 * sin(t * 0.87 + f * 1.3) * _ghost_w)
		# Brace: muscle tremor under load.
		if _brace_w > 0.001:
			_add(b, 0, 0.018 * sin(_time * 23.0 + f * 1.9) * _brace_w * mm)
	# Thumb life.
	var tb := breath * (0.018 * sin(t * TAU * 0.27 + 0.6) + 0.012 * sin(t * 0.91))
	_add(THUMB1, 0, tb)
	_add(THUMB2, 0, tb * 0.7)
	_add(THUMB1, 0, _lag[0] * mm * 0.6)
	_add(THUMB3, 0, _lag[5] * mm * 0.6)
	_add(THUMB1, 0, _run_curl * _run_w * 0.12)
	if _ghost_w > 0.001:
		_add(THUMB1, 2, 0.08 * sin(t * 1.1 + 2.0) * _ghost_w)
		_add(PALM, 0, 0.1 * sin(t * 0.8) * _ghost_w)
		_add(PALM, 1, 0.08 * sin(t * 0.6 + 1.0) * _ghost_w)
	if _wave_w > 0.001:
		_add(PALM, 2, 0.42 * sin(_time * TAU * 1.7) * _wave_w)
		_add(THUMB1, 2, 0.06 * sin(_time * TAU * 1.7 - 1.2) * _wave_w)
	_add(PALM, 0, breath * 0.012 * sin(t * TAU * 0.27 + 1.2))
	_add(PALM, 2, _lag[10] * mm)
	_add(THUMB1, 2, _lag[11] * mm * 0.4)
	_compose_fidget(spec_list)
	# Trigger squeeze: the index snaps onto the trigger and back.
	if _trigger_t >= 0.0:
		var env := smoothstep(0.0, 0.035, _trigger_t) * (1.0 - smoothstep(0.05, 0.12, _trigger_t))
		_set_lerp(INDEX1, 0, _SQUEEZE.x, env)
		_set_lerp(INDEX2, 0, _SQUEEZE.y, env)
		_set_lerp(INDEX3, 0, _SQUEEZE.z, env)
		_set_lerp(INDEX1, 2, 0.0, env)
	for i in range(1, BONE_COUNT):
		var flex := _out[i * 3]
		var twist := _out[i * 3 + 1]
		var spread := _out[i * 3 + 2]
		if side < 0:
			twist = -twist
			spread = -spread
		var rot := Basis(Vector3(0, 0, 1), spread) * Basis(Vector3(0, 1, 0), twist) * Basis(Vector3(1, 0, 0), flex)
		joints[i].transform = _local_rest[i] * Transform3D(rot, Vector3.ZERO)


func _compose_fidget(spec_list: Array) -> void:
	if _fidget_t < 0.0:
		return
	var u := _fidget_t / _fidget_dur()
	var env := _bell(u)
	var mm := micro_motion
	match _fidget_kind:
		0:
			# Finger tap: two quick taps of the index (or middle) finger.
			var b: int = spec_list[_fidget_finger].bone
			var tap := pow(absf(sin(_fidget_t * PI / 0.3)), 2.0) * (1.0 if _fidget_t < 0.6 else 0.0)
			_add(b, 0, 0.42 * tap * mm)
			_add(b + 1, 0, 0.22 * tap * mm)
			_add(b, 0, -0.08 * env * mm)
		1:
			# Finger roll: a curl wave from the pinky to the index.
			for f in spec_list.size():
				var bf: int = spec_list[f].bone
				var w := _bell(clampf((_fidget_t - (spec_list.size() - 1 - f) * 0.09) / 0.75, 0.0, 1.0))
				_add(bf, 0, 0.5 * w * mm)
				_add(bf + 1, 0, 0.45 * w * mm)
				_add(bf + 2, 0, 0.25 * w * mm)
			_add(THUMB1, 0, 0.2 * env * mm)
		2:
			# Stretch: fingers open and fan, then settle.
			for f in spec_list.size():
				var bs: int = spec_list[f].bone
				var fan := (1.5 - float(f)) / 1.5
				_add(bs, 0, -0.3 * env * mm)
				_add(bs + 1, 0, -0.3 * env * mm)
				_add(bs + 2, 0, -0.2 * env * mm)
				_add(bs, 2, 0.12 * fan * env * mm)
			_add(THUMB1, 2, 0.25 * env * mm)
			_add(PALM, 0, -0.12 * env * mm)
		3:
			# Thumb rub: the thumb rolls over the side of the curled index.
			var osc := sin(_fidget_t * TAU * 3.2)
			_add(THUMB1, 0, (0.3 + 0.08 * osc) * env * mm)
			_add(THUMB1, 1, (0.25 + 0.1 * osc) * env * mm)
			_add(THUMB2, 0, 0.15 * env * mm)
			_add(INDEX1, 0, 0.3 * env * mm)
			_add(INDEX2, 0, 0.35 * env * mm)
		4, 5:
			# Regrip: one finger at a time lifts off the item and resettles.
			var first := 1 if _fidget_kind == 5 else 0
			var n := spec_list.size() - first
			for f in range(first, spec_list.size()):
				var br: int = spec_list[f].bone
				var order := spec_list.size() - 1 - f
				var w2 := _bell(clampf((_fidget_t - order * 0.12) / 0.5, 0.0, 1.0))
				_add(br, 0, -0.16 * w2 * mm)
				_add(br + 1, 0, -0.12 * w2 * mm)
			if n > 0 and _fidget_kind == 4:
				_add(THUMB1, 2, 0.1 * env * mm)


func _add(bone: int, dof: int, value: float) -> void:
	_out[bone * 3 + dof] += value


func _set_lerp(bone: int, dof: int, value: float, w: float) -> void:
	var i := bone * 3 + dof
	_out[i] = lerpf(_out[i], value, w)


func _upload() -> void:
	var lift := Transform3D(Basis.IDENTITY, Vector3(0.0, MODEL_Y_BIAS, 0.0))
	_xf[0] = joints[0].transform
	_palette[0] = Projection(lift * _xf[0] * _bind_inv[0])
	for i in range(1, BONE_COUNT):
		_xf[i] = _xf[PARENTS[i]] * joints[i].transform
		_palette[i] = Projection(lift * _xf[i] * _bind_inv[i])
	_mat.set_shader_parameter("bones", _palette)
	if _ghost_mat != null:
		_ghost_mat.set_shader_parameter("bones", _palette)


## Pose name -> flat (flex, twist, spread) per bone, canonical (right-hand) angles.
func _dofs(key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BONE_COUNT * 3)
	var pd: Dictionary = _POSE_DATA[key]
	var w: Vector3 = pd.w
	out[PALM * 3] = w.x
	out[PALM * 3 + 1] = w.y
	out[PALM * 3 + 2] = w.z
	var fingers: Array = pd.f
	var spec_list: Array = _FINGER_SPECS[finger_count]
	for spec in spec_list:
		var b: int = spec.bone
		# Map the 3-finger layout's outer finger onto the pinky row of the table.
		var row := (b - INDEX1) / 3
		var fv: Vector4 = fingers[row]
		out[b * 3] = fv.x
		out[b * 3 + 2] = fv.w
		out[(b + 1) * 3] = fv.y
		out[(b + 2) * 3] = fv.z
	var th: Array = pd.t
	out[THUMB1 * 3] = th[0]
	out[THUMB1 * 3 + 1] = th[1]
	out[THUMB1 * 3 + 2] = th[2]
	out[THUMB2 * 3] = th[3]
	out[THUMB3 * 3] = th[4]
	return out


# --- rig ------------------------------------------------------------------------------

## Joint frame for a digit pointing along `dir` with the nail toward `nail`.
static func _frame(dir: Vector3, nail: Vector3) -> Basis:
	var y := -dir.normalized()
	var z := (nail - y * nail.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


## Mirror a canonical (right-hand) transform to the left hand: positions flip in X and
## frames stay proper rotations (hinge axis flips; flex keeps its sign).
static func _mirror_xf(t: Transform3D) -> Transform3D:
	var m := Vector3(-1, 1, 1)
	var b := Basis(-(t.basis.x * m), t.basis.y * m, t.basis.z * m)
	return Transform3D(b, t.origin * m)


## Rest (bind) transforms of every bone in hand space.
static func _rest_frames(p_side: int, fingers: int) -> Array[Transform3D]:
	var key := "%d:%d" % [p_side, fingers]
	if _rest_cache.has(key):
		return _rest_cache[key]
	var out: Array[Transform3D] = []
	out.resize(BONE_COUNT)
	for i in BONE_COUNT:
		out[i] = Transform3D.IDENTITY
	var dorsal := Vector3(-1, 0, 0)
	out[PALM] = Transform3D(_frame(Vector3.DOWN, dorsal), _PALM_PIVOT)
	var all_specs: Array = _FINGER_SPECS[4]
	var used: Array = _FINGER_SPECS[fingers]
	for spec in all_specs + used:
		var b: int = spec.bone
		var dir: Vector3 = (spec.dir as Vector3).normalized()
		var fr := _frame(dir, dorsal)
		var l: Vector3 = spec.len
		var p: Vector3 = spec.mcp
		out[b] = Transform3D(fr, p)
		out[b + 1] = Transform3D(fr, p + dir * l.x)
		out[b + 2] = Transform3D(fr, p + dir * (l.x + l.y))
	var md := _THUMB_META_DIR.normalized()
	var td := _THUMB_DIR.normalized()
	out[THUMB1] = Transform3D(_frame(md, _THUMB_NAIL), _THUMB_CMC)
	var tm := _THUMB_CMC + md * _THUMB_META_LEN
	out[THUMB2] = Transform3D(_frame(td, _THUMB_NAIL), tm)
	out[THUMB3] = Transform3D(_frame(td, _THUMB_NAIL), tm + td * _THUMB_LEN.x)
	if p_side < 0:
		for i in BONE_COUNT:
			out[i] = _mirror_xf(out[i])
	_rest_cache[key] = out
	return out


# --- geometry -----------------------------------------------------------------------

const _P := CrewMaterials.PRIMARY
const _S := CrewMaterials.SECONDARY
const _M := CrewMaterials.METAL
const _R := CrewMaterials.RUBBER
const _ST := CrewMaterials.STATUS
const _A := CrewMaterials.ACCENT
enum { SEG_BASE, SEG_MID, SEG_TIP }


static func _build_mesh(p_side: int, fingers: int) -> ArrayMesh:
	var k := CrewMeshKit.new()
	var rest := _rest_frames(1, fingers)
	_cuff(k)
	_palm(k)
	for spec in _FINGER_SPECS[fingers]:
		_finger(k, spec, rest)
	_thumb(k, rest)
	for spec in _FINGER_SPECS[fingers]:
		var r: Vector4 = spec.r
		var dir: Vector3 = (spec.dir as Vector3).normalized()
		k.add_occluder((spec.mcp as Vector3) + dir * 0.015, r.x * 0.9)
	k.add_occluder(Vector3(0.0, -0.045, 0.0), 0.012)
	k.bake_ao(0.6)
	if p_side < 0:
		_mirror_kit(k)
	_tri_cache[fingers] = k.triangle_count()
	return k.commit()


## Mirror the built canonical (right) hand into a left hand: flip X, keep facing.
static func _mirror_kit(k: CrewMeshKit) -> void:
	for i in k.positions.size():
		var p := k.positions[i]
		k.positions[i] = Vector3(-p.x, p.y, p.z)
		var n := k.normals[i]
		k.normals[i] = Vector3(-n.x, n.y, n.z)
	for t in range(0, k.indices.size(), 3):
		var tmp := k.indices[t + 1]
		k.indices[t + 1] = k.indices[t + 2]
		k.indices[t + 2] = tmp


## Wrist: brushed-metal disconnect ring (meets the forearm ribs) over a tapered
## player-colour gauntlet cuff with rolled lips and a status light on the back. A satin
## sleeve on the palm bone fills the cuff mouth at every wrist angle.
static func _cuff(k: CrewMeshKit) -> void:
	var sc := Vector2(0.9, 1.0)
	k.set_part(WRIST, _M)
	k.lathe(PackedVector2Array([Vector2(0.0508, 0.0008), Vector2(0.0512, 0.0088), Vector2(0.0462, 0.0118)]),
		Transform3D.IDENTITY, 12, sc)
	k.set_part(WRIST, _P, 0.95)
	# Profiles run bottom -> top (the kit's lathe faces outward that way).
	k.lathe(PackedVector2Array([Vector2(0.0385, -0.0262), Vector2(0.0446, -0.0292), Vector2(0.0514, -0.0215), Vector2(0.0546, -0.0005), Vector2(0.049, 0.0025)]),
		Transform3D.IDENTITY, 12, sc, 0.0, TAU, PackedFloat32Array([0.3, 0.9, 0.0, 0.8, 0.0]))
	# Status light on the back of the wrist (dorsal = -X), in a graphite bezel.
	var back := Vector3(-0.0484, -0.0112, 0.0)
	var tilt := Basis(Vector3(0, 0, 1), -0.16)
	k.set_part(WRIST, _S, 1.3)
	k.rounded_box(back, Vector3(0.0036, 0.011, 0.024), 0.0, tilt)
	k.set_part(WRIST, _ST)
	k.rounded_box(back + tilt * Vector3(-0.0019, 0.0, 0.0), Vector3(0.0012, 0.0056, 0.017), 0.0, tilt)


## Palm block (satin graphite), curved back-of-hand armour plate with an accent strip,
## rubber grip panel, satin wrist sleeve.
static func _palm(k: CrewMeshKit) -> void:
	k.set_part(PALM, CrewMaterials.FABRIC, 0.7)
	k.lathe(PackedVector2Array([Vector2(0.034, -0.022), Vector2(0.0425, -0.011), Vector2(0.0455, 0.0075)]),
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)), 12, Vector2(0.8, 0.98))
	k.set_part(PALM, _S, 1.0)
	k.deform = CrewMeshKit.taper(0.82, 1.0, 0.037, 1.0, 0.8)
	k.rounded_box(Vector3(-0.0005, -0.0415, 0.0005), Vector3(0.034, 0.074, 0.094), 0.014)
	# Back plate: wraps across the width, narrows toward the wrist, overhangs the knuckles.
	var plate_b := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	k.set_part(PALM, _P, 1.0)
	k.deform = CrewMeshKit.shell(0.1, 0.0, 1.0, 0.028, 0.84)
	k.skip_back = true
	k.rounded_box(Vector3(-0.0186, -0.046, 0.0005), Vector3(0.085, 0.056, 0.0076), 0.0037, plate_b, 1, Vector3i(3, 1, 1))
	k.deform = Callable()
	k.skip_back = false
	# Accent strip across the plate, just above the knuckles.
	k.set_part(PALM, _A)
	k.deform = CrewMeshKit.shell(0.1045, 0.0, 1.0, 0.002)
	k.rounded_box(Vector3(-0.0228, -0.0655, 0.0005), Vector3(0.05, 0.0026, 0.0012), 0.0, plate_b, 1, Vector3i(2, 1, 1))
	k.deform = Callable()
	# Rubber grip panel on the palm (lug grooves come from the rubber shader), bowed to
	# follow the palm's width.
	k.set_part(PALM, _R, 1.0)
	k.deform = CrewMeshKit.shell(0.12, 0.0, 1.0, 0.025, 0.88)
	k.skip_back = true
	k.rounded_box(Vector3(0.0158, -0.046, 0.0005), Vector3(0.07, 0.05, 0.0024), 0.0, Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0)), 1, Vector3i(3, 2, 1))
	k.deform = Callable()
	k.skip_back = false


## Palmar grip pad: the rubber half bulges between the joint creases.
static func _pad(length: float, amount: float) -> Callable:
	return func(p: Vector3) -> Vector3:
		if p.z <= 0.0 or p.y <= 0.0 or p.y >= length:
			return p
		var b := pow(sin(PI * p.y / length), 0.7)
		return Vector3(p.x, p.y, p.z * (1.0 + amount * b))


## One phalanx along its joint frame: dorsal half (graphite) + palmar rubber half.
## Its distal end is a cap centred exactly on the next joint, round in the curl plane,
## so the joint stays closed at every angle; SEG_MID / SEG_TIP start inside the
## parent's cap instead of carrying their own.
static func _phalanx(k: CrewMeshKit, bone: int, at: Vector3, frame: Basis, length: float, r0: float, r1: float, kind: int, dorsal_mat := _S, dorsal_shade := 1.0, pad := 0.14) -> void:
	var prof := PackedVector2Array()
	match kind:
		SEG_BASE:
			prof = PackedVector2Array([Vector2(0.0, -r0), Vector2(r0 * 0.74, -r0 * 0.68), Vector2(r0, 0.0), Vector2(r1, length),
				Vector2(r1 * 0.74, length + r1 * 0.68), Vector2(0.0, length + r1)])
		SEG_MID:
			prof = PackedVector2Array([Vector2(r0 * 0.95, 0.0), Vector2(r1, length), Vector2(r1 * 0.74, length + r1 * 0.68), Vector2(0.0, length + r1)])
		SEG_TIP:
			prof = PackedVector2Array([Vector2(r0 * 0.95, 0.0), Vector2(r1 * 1.0, length * 0.62), Vector2(r1 * 0.96, length + r1 * 0.22),
				Vector2(r1 * 0.7, length + r1 * 0.74), Vector2(0.0, length + r1 * 0.98)])
	var xf := Transform3D(Basis(frame.x, -frame.y, -frame.z), at)
	k.set_part(bone, _R, 1.0)
	k.deform = _pad(length, pad)
	k.lathe(prof, xf, 3, Vector2(_WIDTH, 1.0), -PI * 0.5, PI * 0.5)
	k.deform = Callable()
	k.set_part(bone, dorsal_mat, dorsal_shade)
	k.lathe(prof, xf, 4, Vector2(_WIDTH, 1.0), PI * 0.5, PI * 1.5)


## Armour plate over the back of a phalanx: a dorsal arc concentric with the digit,
## lifted off its surface, wrapping from over the knuckle cap (y0 < 0) to y1, with
## rolled ends that touch down so it never floats.
static func _plate(k: CrewMeshKit, bone: int, at: Vector3, frame: Basis, r0: float, r1: float, length: float, y0: float, y1: float, lift: float, half_angle: float) -> void:
	var surf := func(y: float) -> float:
		return sqrt(maxf(r0 * r0 - y * y, 0.0)) if y < 0.0 else lerpf(r0, r1, clampf(y / length, 0.0, 1.0))
	var ys: Array[float] = [y0, y0 + (y1 - y0) * 0.16, y0 + (y1 - y0) * 0.55, y1 - (y1 - y0) * 0.1, y1]
	var lifts: Array[float] = [0.0003, lift * 0.92, lift, lift * 0.9, 0.0003]
	var prof := PackedVector2Array()
	for i in ys.size():
		prof.append(Vector2(float(surf.call(ys[i])) + lifts[i], ys[i]))
	var xf := Transform3D(Basis(frame.x, -frame.y, -frame.z), at)
	k.set_part(bone, _P, 1.0)
	k.lathe(prof, xf, 4, Vector2(_WIDTH, 1.0), PI - half_angle, PI + half_angle, PackedFloat32Array([1.0, 0.5, 0.0, 0.5, 1.0]))


static func _finger(k: CrewMeshKit, spec: Dictionary, rest: Array[Transform3D]) -> void:
	var b: int = spec.bone
	var l: Vector3 = spec.len
	var r: Vector4 = spec.r
	var fr := rest[b].basis
	_phalanx(k, b, rest[b].origin, fr, l.x, r.x, r.y, SEG_BASE)
	_phalanx(k, b + 1, rest[b + 1].origin, fr, l.y, r.y, r.z, SEG_MID)
	_phalanx(k, b + 2, rest[b + 2].origin, fr, l.z, r.z, r.w, SEG_TIP)
	# Knuckle guard (player colour) riding on the proximal phalanx, over the knuckle.
	_plate(k, b, rest[b].origin, fr, r.x, r.y, l.x, -r.x * 0.72, l.x * 0.66, 0.0021, 0.95)


static func _thumb(k: CrewMeshKit, rest: Array[Transform3D]) -> void:
	# Thenar: metacarpal capsule, its base buried in the palm, its end the MCP knuckle.
	_phalanx(k, THUMB1, rest[THUMB1].origin, rest[THUMB1].basis, _THUMB_META_LEN, _THUMB_R.x, _THUMB_R.y, SEG_BASE, _S, 1.0, 0.18)
	_phalanx(k, THUMB2, rest[THUMB2].origin, rest[THUMB2].basis, _THUMB_LEN.x, _THUMB_R.y, _THUMB_R.z, SEG_MID)
	_phalanx(k, THUMB3, rest[THUMB3].origin, rest[THUMB3].basis, _THUMB_LEN.y, _THUMB_R.z, _THUMB_R.w, SEG_TIP)
	_plate(k, THUMB2, rest[THUMB2].origin, rest[THUMB2].basis, _THUMB_R.y, _THUMB_R.z, _THUMB_LEN.x, -_THUMB_R.y * 0.55, _THUMB_LEN.x * 0.7, 0.0021, 1.05)
