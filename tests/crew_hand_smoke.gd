extends SceneTree
## Smoke test for CrewHand: builds left and right hands in 8 colours, blends through
## every pose (and curl / trigger / fidgets / running inertia), and checks finite
## transforms, the triangle and draw-call budgets, mesh / material sharing and the
## left-right mirror symmetry of the joints in a fist.
## Run: godot --headless --path . --script tests/crew_hand_smoke.gd

const COLORS: Array[Color] = [
	Color(0.95, 0.35, 0.1), Color(0.15, 0.55, 0.95), Color(0.2, 0.85, 0.35), Color(0.95, 0.85, 0.15),
	Color(0.75, 0.25, 0.9), Color(0.95, 0.3, 0.55), Color(0.9, 0.9, 0.92), Color(0.1, 0.8, 0.8)]
const DT := 1.0 / 60.0

var _failures: Array[String] = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var hands: Array[CrewHand] = []
	for c in COLORS:
		for s in [-1, 1]:
			var h := CrewHand.build(c, s)
			root.add_child(h)
			hands.append(h)
	print("crew hand: built %d hands in %d ms" % [hands.size(), Time.get_ticks_msec() - t0])
	var left := hands[0]
	var right := hands[1]
	_check(left.side == -1 and right.side == 1, "sides")
	_check(hands[2].mesh_instance.mesh == left.mesh_instance.mesh, "left mesh shared between colours")
	_check(left.mesh_instance.mesh != right.mesh_instance.mesh, "left and right meshes are separate (mirrored)")
	_check(left.get_material() != hands[2].get_material(), "per-hand material instance (own bone palette)")
	_check(left.joints.size() == CrewHand.BONE_COUNT, "rig has %d joints" % CrewHand.BONE_COUNT)
	for n in CrewHand.BONE_NAMES:
		_check(left.find_child(n, true, false) is Node3D, "joint %s exists" % n)

	# Budgets.
	var tris := 0
	var calls := 0
	for node in right.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		calls += mi.mesh.get_surface_count()
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
	print("crew hand: %d triangles, %d draw call(s) per hand" % [tris, calls])
	_check(tris == CrewHand.triangle_count(), "triangle_count() matches the mesh")
	_check(tris <= CrewHand.MAX_TRIANGLES, "triangle budget (%d <= %d)" % [tris, CrewHand.MAX_TRIANGLES])
	_check(calls <= CrewHand.MAX_DRAW_CALLS, "draw call budget (%d <= %d)" % [calls, CrewHand.MAX_DRAW_CALLS])

	# Every pose, blended from the previous one, with the hands swinging like running arms.
	var t := 0.0
	for pose in CrewHand.POSES + ["trigger"]:
		for h in hands:
			h.set_pose(pose, 0.15)
		var prev := _tip(right)
		var max_jump := 0.0
		for f in 30:
			t += DT
			for h in hands:
				h.position = Vector3(0.3 * sin(t * 9.0) * h.side, 0.1 * cos(t * 18.0), 0.0)
				h.set_motion(6.0 if f % 2 == 0 else 0.0, DT)
			var tip := _tip(right)
			max_jump = maxf(max_jump, tip.distance_to(prev))
			prev = tip
		_check_finite(hands, pose)
		# A 0.15 s blend into a fist peaks near 1.5 m/s at the fingertip; a snap would
		# move ~0.12 m in one frame. 5 cm per frame (3 m/s) separates the two.
		_check(max_jump < 0.05, "no popping into %s (max fingertip step %.3f m)" % [pose, max_jump])
	_check(right.get_pose() == "grip_gun_trigger", "trigger alias resolves")

	# Continuous curl, trigger squeeze, fidgets, ghost material.
	for a in [0.0, 0.25, 0.5, 0.75, 1.0]:
		for f in 10:
			right.set_curl(a)
			right.set_motion(0.0, DT)
		_check_finite([right], "curl %.2f" % a)
	right.set_pose("grip_gun", 0.0)
	for f in 5:
		right.set_motion(0.0, DT)
	var rest_index := right.get_joint_position(CrewHand.INDEX3)
	right.trigger_pull()
	var moved := 0.0
	for f in 4:
		right.set_motion(0.0, DT)
		moved = maxf(moved, right.get_joint_position(CrewHand.INDEX3).distance_to(rest_index))
	for f in 12:
		right.set_motion(0.0, DT)
	_check(moved > 0.008, "trigger_pull moves the index (%.3f m)" % moved)
	_check(right.get_joint_position(CrewHand.INDEX3).distance_to(rest_index) < 0.004, "trigger_pull returns within ~0.12 s")
	right.set_pose("relaxed", 0.0)
	for k in 6:
		right.play_fidget(k)
		for f in 90:
			right.set_motion(0.0, DT)
		_check_finite([right], "fidget %d" % k)
	right.set_pose("ghost")
	right.set_motion(0.0, DT)
	_check(right.mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ghost look casts no shadow")
	right.set_pose("relaxed")
	_check(right.mesh_instance.material_override == right.get_material() and right.mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "ghost look clears")

	# Grip anchors: finite, proper rotations, mirrored between the hands.
	for kind in CrewHand.ANCHORS:
		var al := left.get_grip_anchor(kind)
		var ar := right.get_grip_anchor(kind)
		_check(al.origin.is_finite() and ar.origin.is_finite(), "anchor %s finite" % kind)
		_check(absf(ar.basis.determinant() - 1.0) < 1e-4 and absf(al.basis.determinant() - 1.0) < 1e-4, "anchor %s is a rotation" % kind)
		_check(al.origin.is_equal_approx(ar.origin * Vector3(-1, 1, 1)), "anchor %s mirrored" % kind)

	# Mirror symmetry of the joints in a fist (micro-motion off: it is desynced per hand).
	for h in [left, right]:
		h.position = Vector3.ZERO
		h.micro_motion = 0.0
		h.set_pose("fist", 0.15)
	for f in 150:
		left.set_motion(0.0, DT)
		right.set_motion(0.0, DT)
	var worst := 0.0
	for b in CrewHand.BONE_COUNT:
		var pl := left.get_joint_position(b)
		var pr := right.get_joint_position(b)
		worst = maxf(worst, pl.distance_to(pr * Vector3(-1, 1, 1)))
	for d in 5:
		worst = maxf(worst, left.get_fingertip(d).distance_to(right.get_fingertip(d) * Vector3(-1, 1, 1)))
	print("crew hand: fist mirror error %.6f m" % worst)
	_check(worst < 1e-4, "left/right fist joints mirror (%.6f m)" % worst)
	# A fist is closed: every fingertip ends near the palm, well above the open tip.
	for d in range(1, 5):
		_check(right.get_fingertip(d).y > -0.1, "fist curls digit %d (tip y %.3f)" % [d, right.get_fingertip(d).y])

	for h in hands:
		h.queue_free()
	if _failures.is_empty():
		print("PASS: crew hand")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: " + f)
		print("FAIL: crew hand")
		quit(1)


func _tip(h: CrewHand) -> Vector3:
	return h.get_fingertip(2)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _check_finite(hands: Array, state: String) -> void:
	for h: CrewHand in hands:
		for b in CrewHand.BONE_COUNT:
			var x := h.get_joint_transform(b)
			if not (x.origin.is_finite() and x.basis.x.is_finite() and x.basis.y.is_finite() and x.basis.z.is_finite()):
				_failures.append("non-finite joint %s in %s" % [CrewHand.BONE_NAMES[b], state])
				return
