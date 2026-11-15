extends SceneTree
## Pose solver: coordinate descent on a pose's joint angles against contact /
## penetration costs (capsule approximation). Prints the solved table rows.
## args: pose name

const Probe := preload("res://_probe.gd")
var probe: Probe
var hand: CrewHand
var item := ""
var mode := ""
var x0 := PackedFloat32Array()
var reg := 3.0
var wrap_w := 200.0
var thumb_w := 200.0
var stage := 0
var thumb_override := PackedFloat64Array()


func _initialize() -> void:
	var pose: String = OS.get_cmdline_user_args()[0]
	if OS.get_cmdline_user_args().size() > 1:
		reg = float(OS.get_cmdline_user_args()[1])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("stage="):
			stage = int(a.substr(6))
		if a.begins_with("thumb="):
			var tv := a.substr(6).split_floats(",")
			thumb_override = tv
	probe = Probe.new()
	probe.hand = CrewHand.build(Color.WHITE, 1)
	hand = probe.hand
	probe.rest = CrewHand._rest_frames(1, CrewHand.FINGERS)
	root.add_child(hand)
	hand.micro_motion = 0.0
	hand.set_pose(pose, 0.0)
	mode = pose
	item = {"grip_large": "cell", "grip_core": "core", "grip_gun": "gun", "grip_gun_trigger": "gun"}.get(pose, "")
	if thumb_override.size() == 5:
		hand._x[CrewHand.THUMB1 * 3] = thumb_override[0]
		hand._x[CrewHand.THUMB1 * 3 + 1] = thumb_override[1]
		hand._x[CrewHand.THUMB1 * 3 + 2] = thumb_override[2]
		hand._x[CrewHand.THUMB2 * 3] = thumb_override[3]
		hand._x[CrewHand.THUMB3 * 3] = thumb_override[4]
	if stage == 1:
		thumb_w = 0.0
	x0 = hand._x.duplicate()
	var dofs := _dofs_for(pose)
	if item != "" and "anchor" in OS.get_cmdline_user_args():
		var sp2: Dictionary = CrewHand._GRIP_ANCHORS[item]
		var c1: Vector3 = sp2.center
		x0.append_array(PackedFloat32Array([c1.x, c1.y, c1.z, 1.0]))
		var n1 := CrewHand.BONE_COUNT * 3
		dofs.append_array([n1, n1 + 1, n1 + 2])
	elif item == "gun" and not "fixed" in OS.get_cmdline_user_args():
		var spec: Dictionary = CrewHand._GRIP_ANCHORS["gun"]
		var c0: Vector3 = spec.center
		x0.append_array(PackedFloat32Array([c0.x, c0.y, c0.z, spec.scale]))
		var n := CrewHand.BONE_COUNT * 3
		var ua := OS.get_cmdline_user_args()
		if ua.size() > 2:
			var scf := float(ua[2])
			x0[n + 3] = scf
			x0[n] = 0.0172 + 0.0425 * scf + float(ua[4])
			x0[n + 1] = -0.064 + 0.055 * scf + (float(ua[6]) if ua.size() > 6 else 0.0)
			x0[n + 2] = float(ua[5])
			x0[CrewHand.PALM * 3] = float(ua[3])
		else:
			dofs.append_array([n, n + 1, n + 2, n + 3, CrewHand.PALM * 3])
	var x := x0.duplicate()
	var step := 0.12
	var best := _cost(x)
	print("start cost %.4f" % best)
	for it in 60:
		var improved := false
		for d in dofs:
			for sgn in [1.0, -1.0]:
				var y := x.duplicate()
				y[d] = _limit(d, y[d] + sgn * step * (0.05 if d >= CrewHand.BONE_COUNT * 3 else 1.0))
				var c := _cost(y)
				if c < best - 1e-9:
					best = c
					x = y
					improved = true
		if not improved:
			step *= 0.5
			if step < 0.004:
				break
	print("end cost %.4f" % best)
	_cost_verbose = true
	_cost(x)
	_apply(x)
	_print_row(x)
	print("wrist w.x %.3f" % x[CrewHand.PALM * 3])
	if x.size() > CrewHand.BONE_COUNT * 3:
		var n := CrewHand.BONE_COUNT * 3
		print("anchor center Vector3(%.4f, %.4f, %.4f) scale %.3f" % [x[n], x[n + 1], x[n + 2], x[n + 3]])
	quit(0)


func _dofs_for(pose: String) -> Array:
	var out := []
	var f_bones := [CrewHand.INDEX1, CrewHand.MIDDLE1, CrewHand.RING1, CrewHand.PINKY1]
	var skip_index := pose in ["grip_gun", "point"]
	var only_rp := "ringpinky" in OS.get_cmdline_user_args()
	for b in f_bones:
		if skip_index and b == CrewHand.INDEX1:
			continue
		if only_rp and b < CrewHand.RING1:
			continue
		if pose.begins_with("grip") or pose in ["fist", "point"]:
			out.append_array([b * 3, (b + 1) * 3, (b + 2) * 3])
	if pose in ["grip_large", "grip_core", "grip_gun", "grip_gun_trigger"] and "wrist" in OS.get_cmdline_user_args():
		out.append(CrewHand.PALM * 3)
	if stage == 1 or only_rp:
		return out
	if stage == 2:
		out = []
	for d in [0, 1, 2]:
		out.append(CrewHand.THUMB1 * 3 + d)
	out.append(CrewHand.THUMB2 * 3)
	out.append(CrewHand.THUMB3 * 3)
	if pose == "thumbs_up":
		out = [CrewHand.THUMB1 * 3, CrewHand.THUMB1 * 3 + 1, CrewHand.THUMB1 * 3 + 2]
		for b2 in f_bones:
			out.append_array([b2 * 3, (b2 + 1) * 3, (b2 + 2) * 3])
	return out


var anchor := Transform3D.IDENTITY
var _cost_verbose := false


func _apply(x: PackedFloat32Array) -> void:
	var n := CrewHand.BONE_COUNT * 3
	if x.size() > n:
		var sc := x[n + 3]
		var base := CrewHand._anchor_in_palm(item, 1)
		var rot := base.basis.orthonormalized()
		var piv: Vector3 = CrewHand._GRIP_ANCHORS[item].pivot
		anchor = Transform3D(rot.scaled_local(Vector3(sc, sc, sc)), Vector3(x[n], x[n + 1], x[n + 2]) - rot * (piv * sc))
		x = x.slice(0, n)
	elif item != "":
		anchor = CrewHand._anchor_in_palm(item, 1)
	hand._x = x
	hand._compose()
	hand._upload()


func _cost(x: PackedFloat32Array) -> float:
	_apply(x)
	var caps: Array = probe._caps()
	var c := 0.0
	# Digit-digit penetration.
	for i in caps.size():
		for j in range(i + 1, caps.size()):
			var a: Dictionary = caps[i]
			var b: Dictionary = caps[j]
			if a.digit == b.digit or (a.digit == 0 and a.seg == 0) or (b.digit == 0 and b.seg == 0):
				continue
			var gap: float = Probe.seg_dist(a.a, a.b, b.a, b.b) - a.r - b.r
			if gap < 0.0005:
				c += 4000.0 * (0.0005 - gap) * (0.0005 - gap) * 1e3
	# Palm penetration (and fist contact).
	for cp in caps:
		if cp.seg == 0:
			continue
		var m := 1e9
		for k in 7:
			m = minf(m, probe._palm_sdf((cp.a as Vector3).lerp(cp.b, k / 6.0)) - cp.r)
		var allow_p := -0.002 if (mode in ["fist", "point", "thumbs_up"] and cp.seg == 2 and cp.digit > 0) else 0.0005
		if m < allow_p:
			c += 4000.0 * (allow_p - m) * (allow_p - m) * 1e3
		if mode in ["fist", "point", "thumbs_up", "grip_gun", "grip_gun_trigger"] and cp.digit > 0 and cp.seg == 2:
			if not (mode in ["point", "grip_gun", "grip_gun_trigger"] and cp.digit == 1):
				c += 300.0 * (m - 0.001) * (m - 0.001) * 1e3
	# Item contact: wrap every digit segment except the ones left free.
	if item != "":
		var palm_m := hand.get_joint_transform(CrewHand.PALM) * (probe.rest[CrewHand.PALM] as Transform3D).affine_inverse()
		var inv := (palm_m * anchor).affine_inverse()
		var sc := anchor.basis.get_scale().x
		# Cuff and palm must stay out of the item; the palm should touch it.
		var cuff_r := {-0.0192: 0.0446, -0.0146: 0.0474, -0.006: 0.0496, 0.0012: 0.052, 0.0052: 0.0532, 0.0088: 0.0522}
		for yy: float in cuff_r:
			for a in 16:
				var ang := TAU * a / 16.0
				var rr: float = cuff_r[yy] + 0.001
				var cp0 := Vector3(rr * sin(ang) * CrewHand._flatten_x(yy, 0.66), yy, rr * cos(ang) * CrewHand._flatten_x(yy, 0.9))
				var dd := probe._item_sdf(item, inv * cp0) * sc
				if dd < 0.001:
					c += 4000.0 * (0.001 - dd) * (0.001 - dd) * 1e3
					if _cost_verbose and dd < -0.001:
						print("  cuff hit y %.3f ang %d depth %.1f mm" % [yy, a, -dd * 1000])
		var palm_xf := hand.get_joint_transform(CrewHand.PALM) * (probe.rest[CrewHand.PALM] as Transform3D).affine_inverse()
		var gsum := 0.0
		var gmin := 1e9
		for py in [-0.035, -0.05, -0.065]:
			for pz in [-0.03, 0.0, 0.03]:
				var dp := probe._item_sdf(item, inv * (palm_xf * Vector3(0.0172, py, pz))) * sc
				if dp < 0.0:
					c += 4000.0 * dp * dp * 1e3
				gsum += dp
				gmin = minf(gmin, dp)
				if _cost_verbose:
					print("  palm (%.3f, %.2f) gap %.1f mm" % [py, pz, dp * 1000])
		c += 2000.0 * (gmin - 0.0005) * (gmin - 0.0005) * 1e3 + 20.0 * (gsum / 9.0) * (gsum / 9.0) * 1e3
		if item == "gun":
			c += 40.0 * (0.8 - sc) * (0.8 - sc)
		for cp in caps:
			var m2 := 1e9
			for k in 7:
				m2 = minf(m2, probe._item_sdf(item, inv * (cp.a as Vector3).lerp(cp.b, k / 6.0)) * sc - cp.r)
			var allow := -0.004 if cp.bone == CrewHand.THUMB1 else 0.0008
			if m2 < allow:
				c += 4000.0 * (allow - m2) * (allow - m2) * 1e3
			var wraps: bool = cp.seg > 0 or cp.digit == 0
			if item == "gun" and cp.digit == 1:
				wraps = false
			if _cost_verbose:
				print("  %s gap %.1f mm" % [CrewHand.BONE_NAMES[cp.bone], m2 * 1000])
			if wraps:
				c += wrap_w * (m2 - 0.0012) * (m2 - 0.0012) * 1e3
	# Thumb in a fist: lie across the outside of the index / middle middle phalanges.
	if mode in ["fist", "point", "grip_gun", "grip_gun_trigger"]:
		var t3: Dictionary = caps[caps.size() - 1]
		var target_b := CrewHand.MIDDLE2 if mode != "fist" else CrewHand.INDEX2
		var tx := hand.get_joint_transform(target_b)
		var tx2 := hand.get_joint_transform(CrewHand.MIDDLE2)
		# Across the outside of the curled index / middle middle phalanges.
		var tgt := (tx * Vector3(0.0, -0.009, 0.0)).lerp(tx2 * Vector3(0.0, -0.009, 0.0), 0.6 if mode == "fist" else 0.0) + tx.basis.z * -(0.0101 + 0.0104 + 0.001)
		c += thumb_w * (t3.b as Vector3).lerp(t3.a, 0.5).distance_squared_to(tgt) * 1e3
	# Stay near the hand-authored intent.
	for i in x.size():
		c += reg * (x[i] - x0[i]) * (x[i] - x0[i])
	return c


## Anatomical limits per DOF (flex / twist / spread) and joint.
func _limit(d: int, v: float) -> float:
	if d >= CrewHand.BONE_COUNT * 3:
		return clampf(v, 0.5, 0.8) if d == CrewHand.BONE_COUNT * 3 + 3 else v
	if d == CrewHand.PALM * 3:
		return clampf(v, -0.6, 0.3)
	var bone := d / 3
	var dof := d % 3
	if bone >= CrewHand.THUMB1:
		var lim := [[-0.7, 0.9], [-0.5, 1.4], [-0.2, 1.0]]
		if bone > CrewHand.THUMB1:
			lim = [[-0.3, 1.2], [0, 0], [0, 0]]
		return clampf(v, lim[dof][0], lim[dof][1])
	var seg := (bone - CrewHand.INDEX1) % 3
	if dof == 2:
		return clampf(v, -0.4, 0.4)
	if mode in ["fist", "point"]:
		return clampf(v, [1.45, 1.5, 0.45][seg], [1.65, 1.8, 1.5][seg])
	return clampf(v, [-0.25, 0.0, -0.1][seg], [1.65, 1.95, 1.3][seg])


func _print_row(x: PackedFloat32Array) -> void:
	var rows := PackedStringArray()
	for b in [CrewHand.INDEX1, CrewHand.MIDDLE1, CrewHand.RING1, CrewHand.PINKY1]:
		rows.append("Vector4(%.2f, %.2f, %.2f, %.2f)" % [x[b * 3], x[(b + 1) * 3], x[(b + 2) * 3], x[b * 3 + 2]])
	print("\"f\": [" + ", ".join(rows) + "],")
	var t := CrewHand.THUMB1 * 3
	print("\"t\": [%.2f, %.2f, %.2f, %.2f, %.2f]" % [x[t], x[t + 1], x[t + 2], x[CrewHand.THUMB2 * 3], x[CrewHand.THUMB3 * 3]])
