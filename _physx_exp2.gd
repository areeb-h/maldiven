extends SceneTree
## Hinge axis semantics + limits with Jolt.

var a: RigidBody3D
var b: RigidBody3D
var t := 0

func _mk(pos: Vector3, frozen: bool) -> RigidBody3D:
	var r := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.06
	cap.height = 0.4
	cs.shape = cap
	r.add_child(cs)
	r.position = pos
	r.freeze = frozen
	r.collision_layer = 64
	r.collision_mask = 0
	r.mass = 2
	return r

func _initialize() -> void:
	var n := Node3D.new()
	root.add_child(n)
	a = _mk(Vector3(0, 2, 0), true)
	b = _mk(Vector3(0, 1.6, 0), false)
	n.add_child(a)
	n.add_child(b)
	var j := HingeJoint3D.new()
	# joint frame: basis with Z = world X (hinge about X)
	j.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(0, 1.8, 0))
	n.add_child(j)
	j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(0))
	j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(90))
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	physics_frame.connect(_step)

func _step() -> void:
	t += 1
	if t == 5:
		b.apply_central_impulse(Vector3(0, 0, 3))  # swing toward +Z
	if t == 80:
		b.apply_central_impulse(Vector3(0, 0, -6))
	if t % 10 == 0:
		var dir := -b.global_transform.basis.y
		print(t, " dir=", dir.snapped(Vector3.ONE * 0.01), " angle_about_x=", snapped(rad_to_deg(atan2(dir.z, -dir.y)), 0.1))
	if t > 160:
		quit()
