extends SceneTree
## Smoke test for CrewModel: builds 8 colours, drives every animation state and
## overlay, and checks the triangle / draw-call budgets.
## Run: godot --headless --path . --script tests/crew_model_smoke.gd

const MAX_TRIS := 20000
const MAX_DRAW_CALLS := 12
const COLORS: Array[Color] = [
	Color(0.95, 0.35, 0.1), Color(0.15, 0.55, 0.95), Color(0.2, 0.85, 0.35), Color(0.95, 0.85, 0.15),
	Color(0.75, 0.25, 0.9), Color(0.95, 0.3, 0.55), Color(0.9, 0.9, 0.92), Color(0.1, 0.8, 0.8)]

var _failures: Array[String] = []


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var models: Array[CrewModel] = []
	for ci in COLORS.size():
		var m := CrewModel.build(COLORS[ci], ci % CrewBody.VARIANTS, ci + 1)
		root.add_child(m)
		models.append(m)
	print("crew: built %d models in %d ms" % [models.size(), Time.get_ticks_msec() - t0])
	var first := models[0]
	_check(models[4].body.mesh == first.body.mesh, "body mesh is shared between players of a variant")
	_check(models[1].body.mesh != first.body.mesh, "variants have their own meshes")
	_check(first.carry_anchor != null and first.carry_anchor.get_parent() == first, "carry_anchor exists")
	_check(first.hand_anchor != null and first.hand_anchor.get_parent().name == "RightHand", "hand_anchor on right hand")
	for n in ["LeftLeg", "RightLeg", "LeftArm", "RightArm", "Hips", "Spine", "Chest", "Neck", "Head", "LeftForearm", "LeftHand", "LeftShin", "LeftFoot", "LeftFingers", "RightThumb", "Antenna", "Backpack"]:
		_check(first.find_child(n, true, false) is Node3D, "pivot %s exists" % n)
	var tris := 0
	var calls := 0
	for v in CrewBody.VARIANTS:
		var tc := CrewBody.triangle_counts(v)
		print("crew: variant %d: %d body + %d visor triangles" % [v, tc.x, tc.y])
		_check(tc.x + tc.y <= MAX_TRIS, "variant %d triangle budget (%d)" % [v, tc.x + tc.y])
	for node in first.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		calls += mi.mesh.get_surface_count()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	print("crew: %d triangles, %d draw calls per character" % [tris, calls])
	_check(tris <= MAX_TRIS, "triangle budget (%d <= %d)" % [tris, MAX_TRIS])
	_check(calls <= MAX_DRAW_CALLS, "draw call budget (%d <= %d)" % [calls, MAX_DRAW_CALLS])

	var dt := 1.0 / 60.0
	var states := [
		["idle", 0.0, true, false, false],
		["walk", CrewModel.WALK_SPEED, true, false, false],
		["run", CrewModel.RUN_SPEED, true, false, false],
		["carry", CrewModel.WALK_SPEED, true, true, false],
		["air", 2.0, false, false, false],
		["stunned", 0.0, true, false, true],
	]
	for st in states:
		for m in models:
			for f in 45:
				m.set_motion(st[1], st[2], st[3], st[4], dt)
		_check_finite(first, st[0])
	# Footsteps fire while walking.
	var steps := [0]
	first.footstep.connect(func(_side: int) -> void: steps[0] += 1)
	for f in 90:
		first.set_motion(CrewModel.WALK_SPEED, true, false, false, dt)
	_check(steps[0] >= 3, "footstep signal fires (%d)" % steps[0])
	# Faces and fidgets.
	for e in CrewMaterials.EXPRESSIONS:
		first.set_expression(e)
		first._process(dt)
		_check(first.get_expression() == e, "expression " + e)
	first.set_expression("shocked", 0.2)
	for f in 20:
		first._process(dt)
	_check(first.get_expression() == "ghost", "held expression returns to the base face")
	first.set_expression("neutral")
	for k in 3:
		first.play_fidget(k)
		for f in 60:
			first.set_motion(0.0, true, false, false, dt)
		_check_finite(first, "fidget %d" % k)
	first.set_number(7)
	# Feet must not skate: during stance, the planted foot moves backward at the ground speed.
	_check(_stance_speed_ok(first), "stance foot matches ground speed")
	# Overlays and states.
	for m in models:
		m.play_shove()
		m.play_hit()
		m.set_flashlight_on(true)
		m.set_aiming(true)
	for f in 30:
		for m in models:
			m.set_motion(1.0, true, false, false, dt)
	_check_finite(first, "shove/hit/aim")
	first.set_flashlight_on(false)
	first.set_aiming(false)
	first.set_downed(true)
	for f in 40:
		first.set_motion(0.0, true, false, false, dt)
	_check_finite(first, "downed")
	_check(first.bones[0].position.y < 0.3, "downed hips near the floor")
	first.set_carried(true)
	for f in 40:
		first.set_motion(0.0, true, false, false, dt)
	_check_finite(first, "carried")
	first.set_carried(false)
	first.set_downed(false)
	first.set_ghost(true)
	for f in 40:
		first.set_motion(2.0, true, false, false, dt)
	_check(first.body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ghost casts no shadow")
	_check_finite(first, "ghost")
	first.set_ghost(false)
	# Legacy path: gameplay swinging LeftLeg etc. without set_motion.
	(models[2].find_child("LeftLeg", true, false) as Node3D).rotation.x = 0.5
	models[2]._process(dt)
	_check_finite(models[2], "legacy")
	for m in models:
		m.queue_free()
	if _failures.is_empty():
		print("PASS: crew model")
		quit(0)
	else:
		for f in _failures:
			print("  failed: " + f)
		print("FAIL: crew model")
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _check_finite(m: CrewModel, state: String) -> void:
	for b in m.bones:
		var t := b.transform
		if not (t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite()):
			_failures.append("non-finite pose in state " + state)
			return
		if absf(t.basis.determinant() - 1.0) > 0.05:
			_failures.append("non-rigid bone %s in state %s" % [b.name, state])
			return


func _stance_speed_ok(m: CrewModel) -> bool:
	var dt := 1.0 / 120.0
	var speed := CrewModel.WALK_SPEED
	for f in 120:
		m.set_motion(speed, true, false, false, dt)
	var foot := m.bones[CrewBody.L_FOOT]
	var worst := 0.0
	var prev := m._root_xf(CrewBody.L_FOOT).origin
	var samples := 0
	for f in 120:
		m.set_motion(speed, true, false, false, dt)
		var now := m._root_xf(CrewBody.L_FOOT).origin
		var lp := m._phase
		var g := m._gait(speed)
		# Mid-stance only (heel and toe roll excluded).
		if lp > g.y * 0.25 and lp < g.y * 0.6:
			var v := (now.z - prev.z) / dt
			worst = maxf(worst, absf(v + speed))
			samples += 1
		prev = now
	if foot == null or samples == 0:
		return false
	print("crew: worst stance skate %.2f m/s over %d samples" % [worst, samples])
	return worst < 0.6
