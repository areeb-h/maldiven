class_name CrewRagdoll
extends Node3D
## A Jolt ragdoll for one CrewModel: 11 rigid bodies (pelvis, torso, head, upper
## and lower arms and legs) joined by cone-twist joints (spine, neck, shoulders,
## hips) and limited hinges (elbows, knees). Cosmetic and client-local: parts
## live on the RAGDOLL layer and collide with the static world only.
##
## The model is driven from outside: every physics frame apply_pose() writes the
## bodies' rotations into the model's bone nodes (unsimulated bones such as the
## spine, neck, hands and feet are derived or keep their animated pose) and
## re-uploads the skinning palette. Never edits the model's own scripts.
##
## Joints are created with the bodies in the rig's rest pose, so their limits
## mean the same thing whatever pose the ragdoll starts from.

const B := preload("res://scripts/art/crew_body.gd")
const MAX_SPEED := 22.0
const MAX_SPIN := 28.0
const SETTLE_SPEED := 0.16
const SETTLE_HOLD := 0.35

## bone -> parent segment bone (-1 root), mass, shapes [kind, size, local offset, (basis)]
const SEGMENTS := {
	B.HIPS: {"parent": -1, "mass": 11.0, "shapes": [["box", Vector3(0.32, 0.2, 0.22), Vector3(0, -0.03, 0)]]},
	B.CHEST: {"parent": B.HIPS, "mass": 24.0, "shapes": [["box", Vector3(0.4, 0.38, 0.25), Vector3(0, 0.07, 0.0)],
		["box", Vector3(0.3, 0.34, 0.13), Vector3(0, 0.05, -0.17)]]},
	B.HEAD: {"parent": B.CHEST, "mass": 5.0, "shapes": [["sphere", Vector3(0.185, 0, 0), Vector3(0, 0.095, 0.0)]]},
	B.L_ARM: {"parent": B.CHEST, "mass": 2.4, "shapes": [["capsule", Vector3(0.065, 0.42, 0), Vector3(0, -0.1475, 0)]]},
	B.R_ARM: {"parent": B.CHEST, "mass": 2.4, "shapes": [["capsule", Vector3(0.065, 0.42, 0), Vector3(0, -0.1475, 0)]]},
	B.L_FORE: {"parent": B.L_ARM, "mass": 2.0, "shapes": [["capsule", Vector3(0.06, 0.48, 0), Vector3(0, -0.19, 0)]]},
	B.R_FORE: {"parent": B.R_ARM, "mass": 2.0, "shapes": [["capsule", Vector3(0.06, 0.48, 0), Vector3(0, -0.19, 0)]]},
	B.L_LEG: {"parent": B.HIPS, "mass": 7.5, "shapes": [["capsule", Vector3(0.085, 0.58, 0), Vector3(0, -0.2125, 0)]]},
	B.R_LEG: {"parent": B.HIPS, "mass": 7.5, "shapes": [["capsule", Vector3(0.085, 0.58, 0), Vector3(0, -0.2125, 0)]]},
	B.L_SHIN: {"parent": B.L_LEG, "mass": 4.5, "shapes": [["capsule", Vector3(0.075, 0.5, 0), Vector3(0, -0.2, 0)],
		["box", Vector3(0.11, 0.07, 0.24), Vector3(0, -0.455, 0.05)]]},
	B.R_SHIN: {"parent": B.R_LEG, "mass": 4.5, "shapes": [["capsule", Vector3(0.075, 0.5, 0), Vector3(0, -0.2, 0)],
		["box", Vector3(0.11, 0.07, 0.24), Vector3(0, -0.455, 0.05)]]},
}

## [parent bone, child bone, kind, joint point bone, twist axis (cone) in model space, swing, twist]
## Hinges turn about model +X: the elbow lets the forearm come forward, the knee
## lets the shin go back (hinge angle sign measured for Jolt: + moves the child's
## -Y towards +Z).
const JOINTS := [
	[B.HIPS, B.CHEST, "cone", B.SPINE, Vector3(0, 1, 0), 0.45, 0.35],
	[B.CHEST, B.HEAD, "cone", B.NECK, Vector3(0, 1, 0.12), 0.55, 0.7],
	[B.CHEST, B.L_ARM, "cone", B.L_ARM, Vector3(0.45, -0.7, 0.5), 1.25, 0.8],
	[B.CHEST, B.R_ARM, "cone", B.R_ARM, Vector3(-0.45, -0.7, 0.5), 1.25, 0.8],
	[B.L_ARM, B.L_FORE, "hinge", B.L_FORE, Vector3.ZERO, -0.05, 2.3],
	[B.R_ARM, B.R_FORE, "hinge", B.R_FORE, Vector3.ZERO, -0.05, 2.3],
	[B.HIPS, B.L_LEG, "cone", B.L_LEG, Vector3(0.14, -0.86, 0.5), 0.95, 0.35],
	[B.HIPS, B.R_LEG, "cone", B.R_LEG, Vector3(-0.14, -0.86, 0.5), 0.95, 0.35],
	[B.L_LEG, B.L_SHIN, "hinge", B.L_SHIN, Vector3.ZERO, -2.3, 0.05],
	[B.R_LEG, B.R_SHIN, "hinge", B.R_SHIN, Vector3.ZERO, -2.3, 0.05],
]

static var active_count := 0

var model: Node3D  # CrewModel
var parts := {}  # bone -> RigidBody3D
var age := 0.0
var settled := false
var collide_world := true
## When set, the ragdoll drives its model by itself every physics frame (the
## spaced corpse); otherwise the owner calls apply_pose() after its animation.
var autonomous := false
## Optional horizontal tether for the pelvis: world point and stiffness (N/m).
## Keep the model's root under the pelvis (a corpse drifting far from where it
## started would otherwise leave its mesh bounds and get culled).
var follow_root := false
var tether := Vector3.INF
var tether_strength := 0.0
var _still := 0.0
var _counted := false
var _broken := false


## Builds the ragdoll at the model's current pose with `velocity` everywhere.
## Returns null if there's no room for another active ragdoll.
static func spawn(p_model: Node3D, parent: Node, velocity: Vector3, p_collide_world := true, limit := 4) -> CrewRagdoll:
	if active_count >= limit or p_model == null or not p_model.is_inside_tree():
		return null
	var rd := CrewRagdoll.new()
	rd.model = p_model
	rd.collide_world = p_collide_world
	rd.name = "Ragdoll"
	rd.top_level = true
	parent.add_child(rd)
	rd._build(velocity)
	return rd


func _build(velocity: Vector3) -> void:
	active_count += 1
	_counted = true
	var root: Transform3D = model.global_transform
	var bones: Array = model.bones
	var J := B.JOINTS
	# 1) Bodies at the rest pose: joints measure their limits from here.
	for bone in SEGMENTS:
		var seg: Dictionary = SEGMENTS[bone]
		var body := RigidBody3D.new()
		body.name = B.BONE_NAMES[bone]
		body.mass = seg.mass
		body.collision_layer = PhysicsLayers.RAGDOLL
		body.collision_mask = PhysicsLayers.WORLD if collide_world else 0
		body.continuous_cd = true
		body.can_sleep = false
		body.linear_damp = 0.08
		body.angular_damp = 1.6
		var surface := PhysicsMaterial.new()
		surface.friction = 0.85
		surface.bounce = 0.0
		body.physics_material_override = surface
		for shape_def in seg.shapes:
			var cs := CollisionShape3D.new()
			match shape_def[0]:
				"box":
					var box := BoxShape3D.new()
					box.size = shape_def[1]
					cs.shape = box
				"sphere":
					var sphere := SphereShape3D.new()
					sphere.radius = shape_def[1].x
					cs.shape = sphere
				"capsule":
					var capsule := CapsuleShape3D.new()
					capsule.radius = shape_def[1].x
					capsule.height = shape_def[1].y
					cs.shape = capsule
			cs.position = shape_def[2]
			body.add_child(cs)
		add_child(body)
		body.global_transform = root * Transform3D(Basis.IDENTITY, J[bone])
		parts[bone] = body
	for spec in JOINTS:
		_joint(root, spec)
	# 2) Now the real pose, and the motion it had.
	for bone in parts:
		var body: RigidBody3D = parts[bone]
		body.global_transform = _bone_world(root, bones, bone)
		body.linear_velocity = velocity
	_unstick()


func _joint(root: Transform3D, spec: Array) -> void:
	var joint: Joint3D
	var basis := Basis.IDENTITY
	if spec[2] == "hinge":
		var hinge := HingeJoint3D.new()
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, spec[5])
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, spec[6])
		# Hinge axis is the joint's Z: point it along model +X.
		basis = Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		joint = hinge
	else:
		var cone := ConeTwistJoint3D.new()
		cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, spec[5])
		cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, spec[6])
		# Twist axis is the joint's X.
		var x: Vector3 = (spec[4] as Vector3).normalized()
		var helper := Vector3.FORWARD if absf(x.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var y := helper.cross(x).normalized()
		basis = Basis(x, y, x.cross(y).normalized())
		joint = cone
	joint.exclude_nodes_from_collision = true
	add_child(joint)
	joint.global_transform = root * Transform3D(basis, B.JOINTS[spec[3]])
	joint.node_a = joint.get_path_to(parts[spec[0]])
	joint.node_b = joint.get_path_to(parts[spec[1]])


## World transform of a bone from the model's current local transforms.
static func _bone_world(root: Transform3D, bones: Array, bone: int) -> Transform3D:
	var xf: Transform3D = bones[bone].transform
	var p: int = B.PARENTS[bone]
	while p >= 0:
		xf = bones[p].transform * xf
		p = B.PARENTS[p]
	return root * xf


## A limb that starts inside a wall or the floor would be shot out of it: pull
## any overlapping part towards the pelvis until it's clear.
func _unstick() -> void:
	if not collide_world or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var pelvis: RigidBody3D = parts[B.HIPS]
	for bone in parts:
		var body: RigidBody3D = parts[bone]
		for attempt in range(10):
			if not _overlaps(space, body):
				break
			var toward := pelvis.global_position - body.global_position
			if bone == B.HIPS or toward.length() < 0.05:
				body.global_position += Vector3.UP * 0.04
			else:
				body.global_position += toward.normalized() * 0.06 + Vector3.UP * 0.02


func _overlaps(space: PhysicsDirectSpaceState3D, body: RigidBody3D) -> bool:
	for cs in body.get_children():
		if not cs is CollisionShape3D:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = cs.shape
		query.transform = body.global_transform * cs.transform
		query.collision_mask = PhysicsLayers.WORLD
		if not space.intersect_shape(query, 1).is_empty():
			return true
	return false


func impulse(bone: int, value: Vector3) -> void:
	if parts.has(bone):
		(parts[bone] as RigidBody3D).apply_central_impulse(value)


func spin(value: Vector3) -> void:
	for bone in parts:
		(parts[bone] as RigidBody3D).angular_velocity += value


## No gravity (outside the hull).
func weightless() -> void:
	for bone in parts:
		var body: RigidBody3D = parts[bone]
		body.gravity_scale = 0.0
		body.linear_damp = 0.0
		body.angular_damp = 0.4


func pelvis_position() -> Vector3:
	return (parts[B.HIPS] as RigidBody3D).global_position


func is_broken() -> bool:
	return _broken


func _physics_process(delta: float) -> void:
	if parts.is_empty():
		return
	age += delta
	var fastest := 0.0
	for bone in parts:
		var body: RigidBody3D = parts[bone]
		var xf := body.global_transform
		if not (xf.origin.is_finite() and xf.basis.x.is_finite() and xf.basis.y.is_finite() and xf.basis.z.is_finite()):
			_broken = true
			return
		# Never explode: clamp anything a bad contact could spike.
		if body.linear_velocity.length() > MAX_SPEED:
			body.linear_velocity = body.linear_velocity.limit_length(MAX_SPEED)
		if body.angular_velocity.length() > MAX_SPIN:
			body.angular_velocity = body.angular_velocity.limit_length(MAX_SPIN)
		fastest = maxf(fastest, body.linear_velocity.length())
	if tether_strength > 0.0 and tether.is_finite() and age > 0.2:
		var pelvis: RigidBody3D = parts[B.HIPS]
		var pull := tether - pelvis.global_position
		pull.y = 0.0
		var vel := pelvis.linear_velocity
		vel.y = 0.0
		pelvis.apply_central_force(pull * tether_strength - vel * tether_strength * 0.25)
	# Once the fall is over, joints stiffen a little (muscle tone): the body
	# comes to rest instead of rocking on round parts.
	if age > 1.1:
		var k := clampf((age - 1.1) / 0.6, 0.0, 1.0)
		for bone in parts:
			var body: RigidBody3D = parts[bone]
			body.angular_damp = lerpf(1.6, 6.0, k)
			body.linear_damp = lerpf(0.08, 1.2, k)
	_still = _still + delta if fastest < SETTLE_SPEED else 0.0
	settled = _still >= SETTLE_HOLD
	if autonomous:
		apply_pose()


## Writes the simulated pose into the model's bones (rotations only, so the rig
## never stretches; the pelvis also takes its position) and uploads it.
func apply_pose() -> void:
	if model == null or not is_instance_valid(model) or parts.is_empty() or _broken:
		return
	var bones: Array = model.bones
	if follow_root:
		model.global_position = (parts[B.HIPS] as RigidBody3D).global_position - model.global_basis * B.JOINTS[B.HIPS]
	var root_inv: Transform3D = model.global_transform.affine_inverse()
	var hips: Basis = (parts[B.HIPS] as RigidBody3D).global_basis.orthonormalized()
	var chest: Basis = (parts[B.CHEST] as RigidBody3D).global_basis.orthonormalized()
	var head: Basis = (parts[B.HEAD] as RigidBody3D).global_basis.orthonormalized()
	var root_basis: Basis = model.global_basis.orthonormalized()
	var world := {}
	world[B.HIPS] = hips
	var spine := Basis(hips.get_rotation_quaternion().slerp(chest.get_rotation_quaternion(), 0.5))
	world[B.SPINE] = spine
	world[B.CHEST] = chest
	var neck := Basis(chest.get_rotation_quaternion().slerp(head.get_rotation_quaternion(), 0.5))
	world[B.NECK] = neck
	world[B.HEAD] = head
	for bone in [B.L_ARM, B.L_FORE, B.R_ARM, B.R_FORE, B.L_LEG, B.L_SHIN, B.R_LEG, B.R_SHIN]:
		world[bone] = (parts[bone] as RigidBody3D).global_basis.orthonormalized()
	# Pelvis: full transform relative to the model root.
	var pelvis_xf := Transform3D(hips, (parts[B.HIPS] as RigidBody3D).global_position)
	bones[B.HIPS].transform = root_inv * pelvis_xf
	for bone in [B.SPINE, B.CHEST, B.NECK, B.HEAD, B.L_ARM, B.L_FORE, B.R_ARM, B.R_FORE, B.L_LEG, B.L_SHIN, B.R_LEG, B.R_SHIN]:
		var parent: int = B.PARENTS[bone]
		var parent_world: Basis = world[parent] if world.has(parent) else root_basis
		bones[bone].basis = (parent_world.inverse() * world[bone]).orthonormalized()
	if model.has_method("_upload"):
		model._upload()


## The current local transform of every bone (for blending back to animation).
func capture() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for bone in model.bones:
		out.append(bone.transform)
	return out


func _exit_tree() -> void:
	if _counted:
		_counted = false
		active_count = maxi(0, active_count - 1)
