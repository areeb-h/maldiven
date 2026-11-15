extends SceneTree
## Clipping probe: capsule approximation of every phalanx; reports penetrations between
## digits, into the palm block, and into held items (via the grip anchors).

const H := preload("res://scripts/art/crew_hand.gd")
var hand: CrewHand
var rest: Array


func _initialize() -> void:
	hand = CrewHand.build(Color.WHITE, 1)
	root.add_child(hand)
	hand.micro_motion = 0.0
	rest = CrewHand._rest_frames(1, CrewHand.FINGERS)
	var only := ""
	for a in OS.get_cmdline_user_args():
		only = a
	for pose in CrewHand.POSES:
		if only != "" and pose != only:
			continue
		hand.set_pose(pose, 0.0)
		for i in 3:
			hand.set_motion(0.0, 1.0 / 60.0)
		print(_report(pose))
	quit(0)


func _caps() -> Array:
	var out := []
	for spec in CrewHand._FINGER_SPECS[CrewHand.FINGERS]:
		var b: int = spec.bone
		var l: Vector3 = spec.len
		var r: Vector4 = spec.r
		var lens := [l.x, l.y, l.z + r.w * 0.5]
		var rads := [r.x, r.y, r.z]
		for j in 3:
			var x: Transform3D = hand.get_joint_transform(b + j)
			out.append({"bone": b + j, "digit": (b - 2) / 3 + 1, "a": x.origin, "b": x * Vector3(0, -lens[j], 0), "r": rads[j], "seg": j})
	var tl := [CrewHand._THUMB_META_LEN, CrewHand._THUMB_LEN.x, CrewHand._THUMB_LEN.y + CrewHand._THUMB_R.w * 0.5]
	var tr := [CrewHand._THUMB_R.x, CrewHand._THUMB_R.y, CrewHand._THUMB_R.z]
	for j in 3:
		var x2: Transform3D = hand.get_joint_transform(CrewHand.THUMB1 + j)
		out.append({"bone": CrewHand.THUMB1 + j, "digit": 0, "a": x2.origin, "b": x2 * Vector3(0, -tl[j], 0), "r": tr[j], "seg": j})
	return out


static func seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var best := 1e9
	for i in 9:
		var a := p1.lerp(q1, i / 8.0)
		var c := Geometry3D.get_closest_point_to_segment(a, p2, q2)
		best = minf(best, a.distance_to(c))
	for i in 9:
		var a2 := p2.lerp(q2, i / 8.0)
		var c2 := Geometry3D.get_closest_point_to_segment(a2, p1, q1)
		best = minf(best, a2.distance_to(c2))
	return best


func _palm_sdf(p: Vector3) -> float:
	var palm_xf: Transform3D = hand.get_joint_transform(CrewHand.PALM)
	var q: Vector3 = (rest[CrewHand.PALM] as Transform3D) * (palm_xf.affine_inverse() * p)
	q -= Vector3(-0.0005, -0.0415, 0.0005)
	var t := clampf((q.y + 0.037) / 0.074, 0.0, 1.0)
	var he := Vector3(0.017 * lerpf(0.82, 1.0, t), 0.037, 0.047 * lerpf(1.0, 0.8, t))
	var rr := 0.014
	var d := q.abs() - (he - Vector3(rr, rr, rr))
	return d.max(Vector3.ZERO).length() + minf(maxf(d.x, maxf(d.y, d.z)), 0.0) - rr


func _report(pose: String) -> String:
	var caps := _caps()
	var worst_ff := 0.0
	var ff_what := ""
	for i in caps.size():
		for j in range(i + 1, caps.size()):
			var a: Dictionary = caps[i]
			var b: Dictionary = caps[j]
			if a.digit == b.digit:
				continue
			if a.digit == 0 and a.seg == 0 or b.digit == 0 and b.seg == 0:
				continue  # thenar sits against the index base by design
			var pen: float = a.r + b.r - seg_dist(a.a, a.b, b.a, b.b)
			if pen > worst_ff:
				worst_ff = pen
				ff_what = "%s/%s" % [CrewHand.BONE_NAMES[a.bone], CrewHand.BONE_NAMES[b.bone]]
	var worst_palm := 0.0
	var palm_what := ""
	for c in caps:
		if c.seg == 0:
			continue
		for k in 7:
			var p: Vector3 = (c.a as Vector3).lerp(c.b, k / 6.0)
			var pen2: float = c.r - _palm_sdf(p)
			if pen2 > worst_palm:
				worst_palm = pen2
				palm_what = CrewHand.BONE_NAMES[c.bone]
	var s := "%-17s digit-digit %5.1f mm (%s)  digit-palm %5.1f mm (%s)" % [pose, worst_ff * 1000, ff_what, worst_palm * 1000, palm_what]
	var item: String = {"grip_large": "cell", "grip_core": "core", "grip_gun": "gun", "grip_gun_trigger": "gun"}.get(pose, "")
	if item != "":
		s += "\n    " + _item_report(item, caps)
	return s


func _item_sdf(kind: String, q: Vector3) -> float:
	match kind:
		"cell":
			# CellVisual: shell r 0.148 (0.072..0.452), handles: bar x = +-0.1985, y 0.205..0.315, r 0.017.
			var rad := Vector2(q.x, q.z).length()
			var d := maxf(rad - 0.148, maxf(0.072 - q.y, q.y - 0.452))
			for sx in [-1.0, 1.0]:
				var bq := Vector3(q.x - sx * 0.1985, clampf(q.y, 0.205, 0.315), q.z)
				d = minf(d, Vector3(q.x - sx * 0.1985, q.y - bq.y, q.z).length() - 0.017)
			return d
		"core":
			var c := q - Vector3(0, 0.36, 0)
			return minf(c.length() - 0.2255, c.length() - 0.142)
		"gun":
			# GunVisual: grip, frame and upper shell.
			var g := _box_sdf(Basis(Vector3.RIGHT, 0.24).inverse() * (q - Vector3(0, 0.002, -0.012)), Vector3(0.0165, 0.046, 0.024), 0.011)
			g = minf(g, _box_sdf(q - Vector3(0, 0.066, 0.045), Vector3(0.023, 0.018, 0.115), 0.012))
			g = minf(g, _box_sdf(q - Vector3(0, 0.113, 0.052), Vector3(0.031, 0.029, 0.132), 0.018))
			return g
	return 1e9


static func _box_sdf(q: Vector3, he: Vector3, rr: float) -> float:
	var d := q.abs() - (he - Vector3(rr, rr, rr))
	return d.max(Vector3.ZERO).length() + minf(maxf(d.x, maxf(d.y, d.z)), 0.0) - rr


func _item_report(kind: String, caps: Array) -> String:
	var inv := hand.get_grip_anchor(kind).affine_inverse()  # wrist pose included
	var parts := PackedStringArray()
	var worst := 0.0
	for c in caps:
		var best := 1e9
		for k in 7:
			var p: Vector3 = (c.a as Vector3).lerp(c.b, k / 6.0)
			best = minf(best, _item_sdf(kind, inv * p) - c.r)
		worst = minf(worst, best)
		parts.append("%s:%+.1f" % [CrewHand.BONE_NAMES[c.bone].substr(0, 1) + CrewHand.BONE_NAMES[c.bone].right(1), best * 1000])
	# Palm surface distance (palm centre point on the palmar face).
	var pc := (hand.get_joint_transform(CrewHand.PALM) * (rest[CrewHand.PALM] as Transform3D).affine_inverse()) * Vector3(0.018, -0.05, 0.0)
	var pk := (hand.get_joint_transform(CrewHand.PALM) * (rest[CrewHand.PALM] as Transform3D).affine_inverse()) * Vector3(0.016, -0.072, 0.0)
	return "%s gap mm (neg = inside): palm %+.1f knuckle-line %+.1f | %s" % [kind, _item_sdf(kind, inv * pc) * 1000, _item_sdf(kind, inv * pk) * 1000, " ".join(parts)]
