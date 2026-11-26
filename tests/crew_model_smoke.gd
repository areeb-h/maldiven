extends SceneTree
## Smoke test for CrewModel: builds 8 colours, drives every animation state and
## overlay, and checks the triangle / draw-call budgets.
## Run: godot --headless --path . --script tests/crew_model_smoke.gd

## v4: +~560 triangles (rounder hoses, lamps, beacon, helmet and ear pods for hero
## close-ups; the owner flagged faceting). Still one skinned draw call per suit.
const MAX_TRIS := 21000
const MAX_DRAW_CALLS := 12
const COLORS: Array[Color] = [
	Color(0.95, 0.35, 0.1), Color(0.15, 0.55, 0.95), Color(0.2, 0.85, 0.35), Color(0.95, 0.85, 0.15),
	Color(0.75, 0.25, 0.9), Color(0.95, 0.3, 0.55), Color(0.9, 0.9, 0.92), Color(0.1, 0.8, 0.8)]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")  # models need to be inside the tree for world-space checks


func _run() -> void:
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
	_check(first.hands.size() == 2 and first.hands[0].get_parent().name == "LeftHand" and first.hands[1].get_parent().name == "RightHand", "gloves on both hand bones")
	_check(first.hand_anchor != null and first.hand_anchor == first.hands[1].grip_node("gun"), "hand_anchor is the right glove's gun grip")
	for n in ["LeftLeg", "RightLeg", "LeftArm", "RightArm", "Hips", "Spine", "Chest", "Neck", "Head", "LeftForearm", "LeftHand", "LeftShin", "LeftFoot", "Antenna", "Backpack"]:
		_check(first.find_child(n, true, false) is Node3D, "pivot %s exists" % n)
	var tris := 0
	var calls := 0
	for v in CrewBody.VARIANTS:
		var tc := CrewBody.triangle_counts(v)
		var gloves := 2 * CrewHand.triangle_count()
		print("crew: variant %d: %d body + %d visor + %d glove triangles" % [v, tc.x, tc.y, gloves])
		_check(tc.x + tc.y + gloves <= MAX_TRIS, "variant %d triangle budget (%d)" % [v, tc.x + tc.y + gloves])
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
	_check(first.get_expression() == CrewMaterials.EXPRESSIONS[-1], "held expression returns to the base face")
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
		m.set_held_item("gun")
		m.set_aiming(true)
	for f in 30:
		for m in models:
			m.set_motion(1.0, true, false, false, dt)
			if f % 10 == 0:
				m.on_shot()
	_check_finite(first, "shove/hit/aim")
	_check(first.hands[1].get_pose() == "grip_gun_trigger", "aiming glove pose (%s)" % first.hands[1].get_pose())
	for kind in ["cell", "core"]:
		first.set_aiming(false)
		first.set_held_item(kind)
		for f in 40:
			first.set_motion(1.0, true, true, false, dt)
		_check_finite(first, "carry " + kind)
		var want := "grip_core" if kind == "core" else "grip_large"
		_check(first.hands[0].get_pose() == want and first.hands[1].get_pose() == want, "carry %s glove pose" % kind)
	first.set_held_item("")
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
	_acting_checks(models[3], models[5], dt)
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


## v4 acting API: expressions with body language, gestures, reach, look, one-shots.
func _acting_checks(m: CrewModel, other: CrewModel, dt: float) -> void:
	m.position = Vector3(10, 0, 0)
	m.rotation.y = 0.6
	var settle := func(frames: int, speed := 0.0) -> void:
		for f in frames:
			m.set_motion(speed, true, false, false, dt)
			m._process(dt)
	for e in CrewMaterials.EXPRESSIONS:
		m.set_expression(e, 0.0, 0.12, e == "angry")
		settle.call(30)
		_check_finite(m, "expression body " + e)
		_check(m.get_expression() == e, "expression %s shows (glitch cut too)" % e)
	m.set_expression("neutral")
	# Every held gesture, standing and walking.
	for g in CrewModel.HELD_GESTURES:
		m.set_performance(g, 0.0)
		settle.call(40)
		_check_finite(m, "gesture " + g)
		settle.call(20, 2.0)
		_check_finite(m, "gesture %s walking" % g)
	m.set_performance("", 0.0)
	settle.call(20)
	# Point at a target: the arm (shoulder -> fingertip) aims at it.
	var target := m.global_transform * Vector3(-1.5, 1.6, 3.0)
	m.set_gesture("point", 1.0, target)
	settle.call(40)
	var shoulder := m.bones[CrewBody.R_ARM].global_position
	var aim := (m.get_fingertip(1) - shoulder).normalized()
	var want := (target - shoulder).normalized()
	_check(rad_to_deg(aim.angle_to(want)) < 15.0, "point aims at the target (%.1f deg)" % rad_to_deg(aim.angle_to(want)))
	settle.call(30, 3.0)
	aim = (m.get_fingertip(1) - m.bones[CrewBody.R_ARM].global_position).normalized()
	want = (target - m.bones[CrewBody.R_ARM].global_position).normalized()
	_check(rad_to_deg(aim.angle_to(want)) < 20.0, "point holds while walking (%.1f deg)" % rad_to_deg(aim.angle_to(want)))
	m.set_gesture("point", 0.0)
	settle.call(30)
	# Helmet tap: two beats on time, the fingertip on the ear pod at each contact.
	var beats: Array[float] = []
	var clock := [0.0]
	m.gesture_beat.connect(func(g: String, _i: int) -> void:
		if g == "helmet_tap":
			beats.append(clock[0]))
	for walk in [0.0, 2.5]:
		beats.clear()
		clock[0] = 0.0
		m.play_gesture("helmet_tap")
		var worst := 0.0
		for f in 60:
			clock[0] += dt
			m.set_motion(walk, true, false, false, dt)
			m._process(dt)
			if absf(clock[0] - 0.3) < dt * 0.6 or absf(clock[0] - 0.52) < dt * 0.6:
				var pod := m.bones[CrewBody.HEAD].global_transform * Vector3(-0.212, 0.095, 0.015)
				worst = maxf(worst, m.get_fingertip(1).distance_to(pod))
		_check(beats.size() == 2 and absf(beats[0] - 0.3) < 0.03 and absf(beats[1] - 0.52) < 0.03, "helmet_tap beats at 0.30/0.52 s (%s, speed %.1f)" % [beats, walk])
		_check(worst < 0.03, "helmet_tap fingertip touches the helmet (%.3f m, speed %.1f)" % [worst, walk])
		_check_finite(m, "helmet_tap")
	# Random idle fidgets never pick the helmet tap.
	var picked_tap := false
	for i in 400:
		m._fidget_t = -1.0
		m._fidget_timer = 0.0
		m._update_fidget(dt)
		picked_tap = picked_tap or m._fidget_kind == 1
	_check(not picked_tap, "random fidgets never pick the helmet tap")
	m._fidget_t = -1.0
	# Reach: fingertip on the target within 1 cm; weight ramp without pops.
	var reach_t := m.global_transform * Vector3(-0.3, 1.2, 0.5)
	var prev := m.get_fingertip(1)
	var steps: Array[float] = []
	for f in 40:
		m.set_reach(1, reach_t, clampf(float(f) / 8.0, 0.0, 1.0), "open")
		settle.call(1)
		steps.append(m.get_fingertip(1).distance_to(prev))
		prev = m.get_fingertip(1)
	_check(m.get_fingertip(1).distance_to(reach_t) < 0.01, "reach fingertip within 1 cm (%.3f m)" % m.get_fingertip(1).distance_to(reach_t))
	# The 8-frame ramp moves the hand ~0.6 m; a pop is one step far above the average.
	var ramp := steps.slice(0, 9)
	var mean := 0.0
	for v in ramp:
		mean += v / ramp.size()
	_check(ramp.max() < mean * 2.5 and steps.slice(22).max() < 0.01, "reach blends in without popping (max %.3f, mean %.3f, settled %.4f m/frame)" % [ramp.max(), mean, steps.slice(22).max()])
	m.set_reach(1, reach_t, 0.0)
	settle.call(20)
	# Look target at 60 degrees: the head turns to it.
	var look_at := m.global_transform * Vector3(sin(1.05) * 3.0, 1.6, cos(1.05) * 3.0)
	m.set_look_target(look_at)
	settle.call(60)
	var head := m.bones[CrewBody.HEAD].global_transform
	var hdir := Vector3(head.basis.z.x, 0, head.basis.z.z).normalized()
	var tdir := Vector3(look_at.x - head.origin.x, 0, look_at.z - head.origin.z).normalized()
	_check(rad_to_deg(hdir.angle_to(tdir)) < 15.0, "head turns to the look target (%.1f deg off)" % rad_to_deg(hdir.angle_to(tdir)))
	m.set_look_target(null)
	m.play_head("nod")
	m.play_head("shake")
	settle.call(60)
	# One-shots, step back root motion, draw, stagger, hit with a source.
	for g in CrewModel.ONE_SHOTS:
		m.play_gesture(g)
		settle.call(int(float(CrewModel.ONE_SHOTS[g]) / dt) + 4)
		_check_finite(m, "one-shot " + g)
	var rm := m.take_root_motion()
	_check(rm.is_equal_approx(Vector3(0, 0, -CrewModel.STEP_BACK)), "step_back leaves root motion (%s)" % rm)
	m.set_held_item("gun")
	m.play_draw()
	settle.call(40)
	m.set_aiming(true, 0.0)
	m.set_trigger(0.6)
	m.on_shot()
	settle.call(30)
	m.set_aiming(false)
	m.set_trigger(0.0)
	m.set_held_item("")
	m.play_stagger(m.global_position + Vector3(0, 0, 3))
	m.play_hit(m.global_position + Vector3(2, 1, 0))
	settle.call(80)
	_check_finite(m, "draw/aim/stagger/hit")
	# Downed -> get up (standing again within GET_UP_TIME).
	m.set_downed(true)
	settle.call(40)
	m.play_get_up()
	settle.call(int(CrewModel.GET_UP_TIME / dt) + 10)
	_check(m.bones[CrewBody.HIPS].position.y > 0.85 and m.get_expression() != "downed", "play_get_up stands up (hips %.2f, face %s)" % [m.bones[CrewBody.HIPS].position.y, m.get_expression()])
	# Tension, lights, glints, frost, wear, body carry, carried dangle.
	m.set_tension(1.0)
	m.set_lights(0.0, 0.0, 0.0)
	m.set_visor_glint(0, Vector3(0, 3, 3), Color(0.3, 0.9, 1.0, 1.0), 0.1)
	m.set_frost(0.6)
	m.set_wear(1.5)
	m.set_held_item("body")
	for f in 40:
		m.set_motion(2.0, true, true, false, dt)
	_check_finite(m, "tension / body carry")
	m.set_tension(0.0)
	m.set_lights()
	m.set_held_item("")
	other.set_carried(true)
	for f in 60:
		other.position.y = 0.05 * sin(f * 0.4)
		other.set_motion(0.0, true, false, false, dt)
	_check_finite(other, "carried dangle")
	other.set_carried(false)
	other.set_downed(false)
	# Determinism: two identical suits driven identically pose identically.
	var a := CrewModel.build(Color(0.3, 0.6, 0.9), 2, 4)
	var b := CrewModel.build(Color(0.3, 0.6, 0.9), 2, 4)
	root.add_child(a)
	root.add_child(b)
	for mm in [a, b]:
		mm.set_expression("suspicious")
		mm.play_gesture("wave")
	var same := true
	for f in 400:
		for mm: CrewModel in [a, b]:
			mm.set_motion(1.0 if f > 200 else 0.0, true, false, false, dt)
			mm._process(dt)
		for i in a.bones.size():
			same = same and a.bones[i].transform.is_equal_approx(b.bones[i].transform)
		same = same and a._blink == b._blink and a._look == b._look
	_check(same, "identical suits animate identically (deterministic)")
	a.queue_free()
	b.queue_free()
	m.position = Vector3.ZERO
	m.rotation.y = 0.0


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
