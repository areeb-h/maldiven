class_name CrewBody
extends RefCounted
## Rig layout and procedural geometry of the crew EVA suit.
## Bind pose: origin at the feet, facing +Z, character's left = +X, arms straight down
## (the animation adds the A-pose). Joints are covered action-figure style: hinge
## barrels with bolted caps on knees and elbows, crisp flex ribs at the waist, wrists
## and ankles, bearing balls in the shoulders, and plates that step into each other.

enum { HIPS, SPINE, CHEST, NECK, HEAD, L_ARM, L_FORE, L_HAND, R_ARM, R_FORE, R_HAND, L_LEG, L_SHIN, L_FOOT, R_LEG, R_SHIN, R_FOOT,
	ANTENNA, PACK }

const BONE_NAMES: Array[String] = ["Hips", "Spine", "Chest", "Neck", "Head",
	"LeftArm", "LeftForearm", "LeftHand", "RightArm", "RightForearm", "RightHand",
	"LeftLeg", "LeftShin", "LeftFoot", "RightLeg", "RightShin", "RightFoot", "Antenna", "Backpack"]
const PARENTS: Array[int] = [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15, 4, 2]
const JOINTS: Array[Vector3] = [
	Vector3(0, 0.97, 0), Vector3(0, 1.07, 0), Vector3(0, 1.21, -0.01), Vector3(0, 1.47, -0.012), Vector3(0, 1.555, -0.005),
	Vector3(0.235, 1.425, -0.015), Vector3(0.235, 1.13, -0.015), Vector3(0.235, 0.86, -0.015),
	Vector3(-0.235, 1.425, -0.015), Vector3(-0.235, 1.13, -0.015), Vector3(-0.235, 0.86, -0.015),
	Vector3(0.1, 0.93, 0), Vector3(0.1, 0.505, 0), Vector3(0.1, 0.09, 0),
	Vector3(-0.1, 0.93, 0), Vector3(-0.1, 0.505, 0), Vector3(-0.1, 0.09, 0),
	Vector3(0, 1.648, -0.006), Vector3(0, 1.25, -0.13),
]

const P := CrewMaterials.PRIMARY
const S := CrewMaterials.SECONDARY
const F := CrewMaterials.FABRIC
const M := CrewMaterials.METAL
const A := CrewMaterials.ACCENT
const R := CrewMaterials.RUBBER
const ST := CrewMaterials.STATUS
const L := CrewMaterials.LAMP
const T := CrewMaterials.TRIM
const DC := CrewMaterials.DECAL
const BL := CrewMaterials.BLINK
const V := CrewMaterials.VENT
const G := CrewMaterials.GAUGE
const SO := CrewMaterials.SOLE

## Decal styles (UV2.x on DECAL vertices); drawn procedurally by the suit shader.
const DECAL_PAINT := 0.0  # player number painted on a shell
const DECAL_GLOW := 1.0  # glowing player number on a graphite panel
const DECAL_HAZARD := 2.0  # hazard stripes
const DECAL_NAMEPLATE := 3.0  # number + text dashes
const DECAL_GRILLE := 4.0  # round vent grille (ear pods)
const DECAL_INSIGNIA := 5.0  # crew emblem + stencil text
const DECAL_DISPLAY := 6.0  # chest status screen (oxygen bar + readout)

## Helmet: a slightly squashed sphere, open at the neck.
const HELMET_C := 1.648
const HELMET_RX := 0.178
const HELMET_RY := 0.168
const HELMET_BASE := 1.515
const HELMET_Z := -0.006
const HELMET_DEPTH := 1.05
const VISOR_Y := Vector2(1.565, 1.742)
const VISOR_HALF_ANGLE := 1.0
const VARIANTS := 4
## Abdominal plate: height range, radius (bottom, top) and wrap span.
const ABS_Y := Vector2(1.042, 1.142)
const ABS_R := Vector2(0.114, 0.12)
const ABS_SPAN := 2.1
## Backpack panel curvature radii (convex toward the back).
const PACK_CURVE := 0.5
const PACK_CURVE_WIDE := 1.0
## Box basis whose local +Z faces backward (-Z), so shell() bulges toward the back.
const BACK_FACING := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
## Bevel softening applied to every rounded box of the suit.
const BEVEL_SCALE := 1.35
## Shading multiplier for rubber joint covers.
const RUBBER_SHADE := 0.62

static var _cache := {}


## Shared body mesh for a cosmetic variant (0..3), built once and cached.
static func body_mesh(variant := 0) -> ArrayMesh:
	var key := "body%d" % posmod(variant, VARIANTS)
	if not _cache.has(key):
		_build(posmod(variant, VARIANTS))
	return _cache[key]


## Shared visor mesh (child of the Head bone, LED face shader).
static func visor_mesh() -> ArrayMesh:
	if not _cache.has("visor"):
		var vk := CrewMeshKit.new()
		_visor(vk)
		_cache["visor"] = vk.commit()
		_cache["visor_tris"] = vk.triangle_count()
	return _cache["visor"]


## (body, visor) triangle counts for a variant.
static func triangle_counts(variant := 0) -> Vector2i:
	body_mesh(variant)
	visor_mesh()
	return Vector2i(_cache["body_tris%d" % posmod(variant, VARIANTS)], _cache["visor_tris"])


static func _build(variant: int) -> void:
	var kit := CrewMeshKit.new()
	kit.bevel_scale = BEVEL_SCALE
	kit.round_outline = true
	_hips(kit)
	_torso(kit)
	_backpack(kit, variant)
	_head(kit, variant)
	for s in [1.0, -1.0]:
		_arm(kit, s)
		_leg(kit, s)
	_occluders(kit)
	kit.bake_ao()
	var creases: Array[Vector3] = []
	for j in [L_FORE, R_FORE, L_SHIN, R_SHIN]:
		creases.append(JOINTS[j])
	kit.bake_creases(creases, 0.075, F)
	_cache["body%d" % variant] = kit.commit()
	_cache["body_tris%d" % variant] = kit.triangle_count()


static func shifted(c: Callable, off: Vector3) -> Callable:
	return func(p: Vector3) -> Vector3: return c.call(p + off)


static func helmet_radius(y: float) -> float:
	var t := clampf((y - HELMET_C) / HELMET_RY, -1.0, 1.0)
	return HELMET_RX * sqrt(1.0 - t * t)


## Point on the helmet shell at height y and angle a (0 = front, + toward +X).
static func helmet_point(a: float, y: float, lift := 0.0) -> Vector3:
	var r := helmet_radius(y) + lift
	return Vector3(sin(a) * r, y, cos(a) * r * HELMET_DEPTH + HELMET_Z)


static func helmet_profile() -> PackedVector2Array:
	var prof := PackedVector2Array()
	var t0 := asin(clampf((HELMET_BASE - HELMET_C) / HELMET_RY, -1.0, 1.0))
	prof.append(Vector2(helmet_radius(HELMET_BASE) - 0.012, HELMET_BASE - 0.004))
	for i in 11:
		var t := lerpf(t0, PI * 0.5, float(i) / 10.0)
		prof.append(Vector2(HELMET_RX * cos(t), HELMET_C + HELMET_RY * sin(t)))
	prof[prof.size() - 1] = Vector2(0.0, HELMET_C + HELMET_RY)
	return prof


# --- reusable pieces ----------------------------------------------------------------

## Smooth rubber hinge barrel on the hinge (X) axis of a knee or elbow, rigid on the
## lower bone: a cylinder about its own rotation axis covers the joint at any bend.
static func _barrel(k: CrewMeshKit, bone: int, center: Vector3, half_len: float, radius: float, segments: int) -> void:
	var prof := PackedVector2Array([Vector2(0.0, -half_len - radius * 0.3), Vector2(radius * 0.72, -half_len - radius * 0.18),
		Vector2(radius * 0.97, -half_len), Vector2(radius, -half_len * 0.4), Vector2(radius, half_len * 0.4),
		Vector2(radius * 0.97, half_len), Vector2(radius * 0.72, half_len + radius * 0.18), Vector2(0.0, half_len + radius * 0.3)])
	k.set_part(bone, F, RUBBER_SHADE)
	k.lathe(prof, Transform3D(Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK), center), segments)


## Crisp flex ribs: separate, evenly spaced, bevelled rings around local Y.
static func _ribs(k: CrewMeshKit, bone: int, center: Vector3, count: int, spacing: float, r_out: float, segments: int, scale_xz := Vector2.ONE, mat := F, shade := RUBBER_SHADE) -> void:
	var h := spacing * 0.34
	var bv := h * 0.5
	for i in count:
		var y0 := (float(i) - float(count - 1) * 0.5) * spacing
		var prof := PackedVector2Array([Vector2(r_out - bv * 1.6, y0 - h), Vector2(r_out, y0 - h + bv), Vector2(r_out, y0 + h - bv), Vector2(r_out - bv * 1.6, y0 + h)])
		k.set_part(bone, mat, shade)
		k.lathe(prof, Transform3D(Basis.IDENTITY, center), segments, scale_xz, 0.0, TAU, PackedFloat32Array([0.6, 1, 1, 0.6]))


## Tapered, sculpted limb: a lathe along a -> b through the given radii (evenly spaced).
static func _limb(k: CrewMeshKit, a: Vector3, b: Vector3, radii: Array[float], segments: int, scale_xz := Vector2.ONE) -> void:
	var length := a.distance_to(b)
	var prof := PackedVector2Array()
	prof.append(Vector2(0.0, -radii[0] * 0.8))
	prof.append(Vector2(radii[0] * 0.75, -radii[0] * 0.55))
	for i in radii.size():
		prof.append(Vector2(radii[i], length * float(i) / float(radii.size() - 1)))
	var rl: float = radii[radii.size() - 1]
	prof.append(Vector2(rl * 0.75, length + rl * 0.55))
	prof.append(Vector2(0.0, length + rl * 0.8))
	var y := (b - a).normalized()
	var ref := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	k.lathe(prof, Transform3D(Basis(x, y, x.cross(y)), a), segments, scale_xz)


## Hinge cap with a metal bolt on the outer side of an elbow / knee.
static func _hinge(k: CrewMeshKit, bone: int, at: Vector3, out: Vector3, radius: float) -> void:
	k.set_part(bone, S, 1.2)
	k.disc(at, out, radius, 12, radius * 0.35)
	k.set_part(bone, M)
	k.disc(at + out * radius * 0.36, out, radius * 0.38, 6, radius * 0.12)


## Thin cylindrical band hugging a vertical cylinder of radius r (tank straps, light rings).
static func _band(k: CrewMeshKit, bone: int, mat: int, center: Vector3, r: float, height: float, segments: int) -> void:
	k.set_part(bone, mat)
	k.lathe(PackedVector2Array([Vector2(r, -height * 0.5), Vector2(r, height * 0.5)]), Transform3D(Basis.IDENTITY, center), segments)


## Flat emissive band (annulus) facing `normal`.
static func _annulus(k: CrewMeshKit, bone: int, mat: int, center: Vector3, normal: Vector3, r_in: float, r_out: float, segments: int) -> void:
	k.set_part(bone, mat)
	var y := normal.normalized()
	var ref := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	k.lathe(PackedVector2Array([Vector2(r_out, 0.0), Vector2(r_in, 0.0)]), Transform3D(Basis(x, y, x.cross(y)), center), segments)


## Flat (or surface-following) decal patch, UV 0..1; `right` = +U, `up` = +V.
static func _decal(k: CrewMeshKit, bone: int, center: Vector3, right: Vector3, up: Vector3, size: Vector2, style: float, cols := 1, surface := Callable(), rows := 1) -> void:
	k.set_part(bone, DC)
	var normal := right.cross(up).normalized()
	k.patch(func(u: float, v: float) -> Vector3:
			var p := center + right * (u - 0.5) * size.x + up * (v - 0.5) * size.y
			return surface.call(p) if surface.is_valid() else p,
		cols, rows, center - normal * 0.2, Vector2.ONE, Callable(), Vector2(style, size.x / size.y))


## Round decal (polar patch) facing `normal`, UV 0..1 across the disc.
static func _disc_decal(k: CrewMeshKit, bone: int, center: Vector3, normal: Vector3, radius: float, style: float, segments := 12) -> void:
	k.set_part(bone, DC)
	var n := normal.normalized()
	var t1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := n.cross(t1)
	k.patch(func(u: float, v: float) -> Vector3: return center + (t1 * cos(u * TAU) + t2 * sin(u * TAU)) * radius * v,
		segments, 2, center - n * 0.1, Vector2.ONE,
		func(u: float, v: float) -> Vector2: return Vector2(0.5 + 0.5 * cos(u * TAU) * v, 0.5 + 0.5 * sin(u * TAU) * v),
		Vector2(style, 1.0))


## Curved armour shell wrapped around a vertical axis from a (bottom) to b (top):
## spans `span` radians centred on `theta` (0 = front, +PI/2 = +X) and follows the
## radius profile r(t) = lerp(r_bottom, r_top, t) + flare * t^2 + bulge * sin(PI t)
## at a constant `gap`, with real thickness, half-round lips and rounded corners.
## `ridge` raises a soft centre crest so highlights roll across the plate;
## `scale_z` squashes the wrap into an ellipse (torso and hips); `span_bottom` narrows
## the wrap toward the bottom edge so the outline tapers (thighs into the knee).
static func _shell(k: CrewMeshKit, bone: int, mat: int, shade: float, a: Vector3, b: Vector3, r_bottom: float, r_top: float,
		theta: float, span: float, thick: float, gap: float, segs_around: int, segs_up: int, flare := 0.0,
		bulge := 0.0, scale_z := 1.0, ridge := 0.0, span_bottom := 1.0) -> void:
	var height := a.distance_to(b)
	var r_mid := (r_bottom + r_top) * 0.5 + bulge * 0.6 + gap + thick * 0.5
	var width := span * r_mid
	var turn := Basis(Vector3.UP, theta)
	k.set_part(bone, mat, shade)
	k.deform = func(p: Vector3) -> Vector3:
		var t := clampf(p.y / height + 0.5, 0.0, 1.0)
		var n := clampf(p.x / (width * 0.5), -1.0, 1.0)
		var ang := n * span * 0.5 * lerpf(span_bottom, 1.0, t)
		var r := lerpf(r_bottom, r_top, t) + flare * t * t + bulge * sin(PI * t) + gap + thick * 0.5 + p.z
		r += ridge * pow(1.0 - absf(n), 2.0)
		var q := turn * Vector3(sin(ang) * r, p.y, cos(ang) * r)
		q.z *= scale_z
		return q
	k.skip_back = true
	k.rounded_box((a + b) * 0.5, Vector3(width, height, thick), thick * 0.5, Basis.IDENTITY, 1, Vector3i(segs_around, segs_up, 1))
	k.deform = Callable()
	k.skip_back = false


## Domed cap (knee / elbow) facing `forward`, elongated `stretch` along world Y.
static func _cap(k: CrewMeshKit, bone: int, mat: int, shade: float, center: Vector3, forward: Vector3, radius: float, depth: float, stretch: float, segments: int) -> void:
	var prof := PackedVector2Array([Vector2(radius * 0.86, -depth * 0.15), Vector2(radius, depth * 0.1), Vector2(radius * 0.96, depth * 0.42),
		Vector2(radius * 0.78, depth * 0.72), Vector2(radius * 0.46, depth * 0.93), Vector2(0.0, depth)])
	var y := forward.normalized()
	var x := Vector3.UP.cross(y).normalized()
	var z := x.cross(y)
	k.set_part(bone, mat, shade)
	k.lathe(prof, Transform3D(Basis(x, y, z), center), segments, Vector2(1.0, stretch), 0.0, TAU, PackedFloat32Array([0, 1, 0, 0, 0, 0]))


## Armour plate wrapped around a limb axis: `theta` = angle around the limb (0 = front, +PI/2 = +X).
static func _plate(k: CrewMeshKit, axis: Vector3, radius: float, theta: float, size: Vector3, corner: float, curve := 0.0, taper_bottom := 1.0, segs := Vector3i(1, 1, 1)) -> void:
	var dir := Vector3(sin(theta), 0.0, cos(theta))
	k.deform = CrewMeshKit.shell(radius + size.z * 0.5, curve, taper_bottom, size.y * 0.5)
	k.skip_back = true
	k.rounded_box(axis + dir * (radius + size.z * 0.5), size, corner, Basis(Vector3.UP, theta), 1, segs)
	k.deform = Callable()
	k.skip_back = false


static func _profile_r(prof: PackedVector2Array, y: float) -> float:
	for i in range(1, prof.size()):
		if y <= prof[i].y:
			var t := clampf((y - prof[i - 1].y) / maxf(prof[i].y - prof[i - 1].y, 1e-5), 0.0, 1.0)
			return lerpf(prof[i - 1].x, prof[i].x, t)
	return prof[prof.size() - 1].x


# --- hips and torso -----------------------------------------------------------------

static func _hips(k: CrewMeshKit) -> void:
	k.set_part(HIPS, F, 0.9)
	k.deform = CrewMeshKit.taper(0.86, 1.0, 0.1)
	k.rounded_box(Vector3(0, 0.935, -0.005), Vector3(0.315, 0.2, 0.22), 0.08, Basis.IDENTITY, 1)
	# Utility belt with buckle and pouches (the ring the thigh guards tuck under).
	k.set_part(HIPS, S, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.142, 0.962), Vector2(0.16, 0.968), Vector2(0.164, 0.99), Vector2(0.163, 1.014), Vector2(0.156, 1.026), Vector2(0.14, 1.032)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.004)), 14, Vector2(1.0, 0.8), 0.0, TAU, PackedFloat32Array([0, 1, 0, 0, 1, 0]))
	k.set_part(HIPS, M, 1.0)
	k.rounded_box(Vector3(0, 0.997, 0.13), Vector3(0.075, 0.054, 0.022), 0.009, Basis.IDENTITY, 1)
	k.set_part(HIPS, A)
	k.rounded_box(Vector3(0, 0.997, 0.142), Vector3(0.042, 0.008, 0.004), 0.0, Basis.IDENTITY, 1)
	# Curved codpiece and rear plate wrapping the pelvis.
	var hip_axis := Vector3(0, 0, -0.005)
	_shell(k, HIPS, P, 0.92, hip_axis + Vector3(0, 0.85, 0), hip_axis + Vector3(0, 0.958, 0), 0.094, 0.106, 0.0, 1.0, 0.022, 0.004, 6, 2, 0.0, 0.0, 1.0, 0.004)
	_shell(k, HIPS, S, 1.1, hip_axis + Vector3(0, 0.88, 0), hip_axis + Vector3(0, 0.958, 0), 0.1, 0.108, PI, 1.6, 0.02, 0.004, 7, 1)
	for s in [1.0, -1.0]:
		# Curved hip tassets wrapping the outer top of each thigh, hanging from the belt.
		var thigh_axis := Vector3(s * 0.1, 0, 0)
		_shell(k, HIPS, P, 1.0, thigh_axis + Vector3(0, 0.848, 0), thigh_axis + Vector3(0, 0.975, 0), 0.128, 0.11, s * 1.45, 1.6, 0.018, 0.0, 7, 2, 0.0, 0.0, 1.0, 0.004)
		# Belt pouches.
		k.set_part(HIPS, S, 1.25)
		k.deform = CrewMeshKit.shell(0.17, 0.0)
		k.rounded_box(Vector3(s * 0.11, 0.975, 0.112), Vector3(0.06, 0.06, 0.036), 0.014, Basis(Vector3.UP, s * 0.75), 1)
		k.deform = Callable()


static func _torso(k: CrewMeshKit) -> void:
	# Waist: smooth satin sleeve (spine, skinned into the hips) with crisp flex ribs.
	var prof := PackedVector2Array()
	for i in 6:
		var y := lerpf(0.99, 1.25, float(i) / 5.0)
		prof.append(Vector2(0.108 + 0.012 * sin(clampf((y - 0.99) / 0.26, 0.0, 1.0) * PI), y))
	k.set_part(SPINE, F, 0.8)
	k.set_blend(HIPS, Vector3(0, 1.03, 0), Vector3.DOWN, 0.04)
	k.lathe(prof, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 14, Vector2(1.0, 0.78))
	k.clear_blend()
	_ribs(k, SPINE, Vector3(0, 1.165, -0.012), 2, 0.024, 0.127, 16, Vector2(1.0, 0.8))
	# Curved off-white abdominal plates wrapping the waist.
	var waist := Vector3(0, 0, -0.012)
	_shell(k, SPINE, T, 1.0, waist + Vector3(0, ABS_Y.x, 0), waist + Vector3(0, ABS_Y.y, 0), ABS_R.x, ABS_R.y, 0.0, ABS_SPAN, 0.022, 0.004, 10, 2, 0.0, 0.0, 0.78, 0.004, 0.85)
	k.set_part(SPINE, S, 1.1)
	k.rounded_box(waist + Vector3(0, 1.092, 0.0), Vector3(0.006, 0.07, 0.004), 0.0, Basis.IDENTITY, 1)
	# Chest core: elliptical section so the plates can hug it.
	var tp := PackedVector2Array([Vector2(0.118, 1.15), Vector2(0.142, 1.2), Vector2(0.162, 1.26), Vector2(0.176, 1.33),
		Vector2(0.178, 1.39), Vector2(0.168, 1.44), Vector2(0.14, 1.475), Vector2(0.1, 1.5)])
	k.set_part(CHEST, F, 0.9)
	k.set_blend(SPINE, Vector3(0, 1.2, 0), Vector3.DOWN, 0.04)
	k.lathe(tp, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.015)), 14, Vector2(1.0, 0.68))
	k.clear_blend()
	var chest_axis := Vector3(0, 0, -0.015)
	for s in [1.0, -1.0]:
		# Layered chest armour: coloured pectoral shells over off-white lower plates,
		# all wrapping the elliptical chest so highlights roll across them.
		_shell(k, CHEST, P, 1.0, chest_axis + Vector3(0, 1.205, 0), chest_axis + Vector3(0, 1.458, 0), 0.143, 0.163, s * 0.5, 0.98, 0.028, 0.004, 6, 5, 0.0, 0.026, 0.7, 0.006, 0.82)
		# Shoulder yoke (trapezius armour), sloping out under the pauldrons.
		k.set_part(CHEST, S, 1.2)
		k.rounded_box(Vector3(s * 0.13, 1.462, -0.02), Vector3(0.15, 0.04, 0.19), 0.016, Basis(Vector3.BACK, s * -0.32), 1)
	# Collar guard: off-white lip framing the neck seal.
	k.set_part(CHEST, T, 1.0)
	k.deform = CrewMeshKit.shell(0.16, 0.0, 0.92, 0.02)
	k.skip_back = true
	k.rounded_box(Vector3(0, 1.468, 0.112), Vector3(0.17, 0.04, 0.022), 0.01, Basis(Vector3.RIGHT, -0.42), 1)
	k.deform = Callable()
	# Chest rig: status light and a small screen with an oxygen bar and readout.
	k.set_part(CHEST, S, 1.25)
	k.deform = CrewMeshKit.shell(0.3, 0.0, 0.85, 0.08)
	k.skip_back = true
	k.rounded_box(Vector3(0, 1.315, 0.138), Vector3(0.07, 0.17, 0.036), 0.012, Basis.IDENTITY, 1)
	k.deform = Callable()
	k.set_part(CHEST, M)
	k.ring(Vector3(0, 1.358, 0.157), 0.02, 0.0042, Basis(Vector3.RIGHT, PI * 0.5), 12, 4)
	k.set_part(CHEST, ST)
	k.disc(Vector3(0, 1.358, 0.155), Vector3.BACK, 0.017, 12, 0.006)
	_decal(k, CHEST, Vector3(0, 1.288, 0.1575), Vector3.RIGHT, Vector3.UP, Vector2(0.05, 0.05), DECAL_DISPLAY)
	# Name plate on the left of the abdominal plate, following its outer surface.
	var name_surface := func(u: float, v: float) -> Vector3:
		var yy := lerpf(1.1, 1.126, v)
		var t := (yy - ABS_Y.x) / (ABS_Y.y - ABS_Y.x)
		var ang := lerpf(0.32, 0.8, u)
		var n := ang / (ABS_SPAN * 0.5 * lerpf(0.85, 1.0, t))
		var r := lerpf(ABS_R.x, ABS_R.y, t) + 0.004 + 0.022 + 0.004 * pow(1.0 - n, 2.0) + 0.0015
		return waist + Vector3(sin(ang) * r, yy, cos(ang) * r * 0.78)
	k.set_part(SPINE, DC)
	k.patch(name_surface, 4, 1, waist + Vector3(0, 1.11, 0), Vector2.ONE, Callable(), Vector2(DECAL_NAMEPLATE, 2.9))
	# Segmented collar ring (crisp) with a brushed-metal lip the helmet sits in.
	_ribs(k, CHEST, Vector3(0, 1.474, -0.012), 2, 0.028, 0.146, 16, Vector2(1.05, 0.98), S, 1.0)
	k.set_part(CHEST, M)
	k.lathe(PackedVector2Array([Vector2(0.1, 1.5), Vector2(0.113, 1.503), Vector2(0.115, 1.512), Vector2(0.104, 1.518)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 16, Vector2(1.05, 0.98))
	# Neck seal (mostly hidden inside the collar and helmet).
	var np := PackedVector2Array([Vector2(0.08, 1.45), Vector2(0.078, 1.5), Vector2(0.078, 1.54), Vector2(0.08, 1.575)])
	k.set_part(NECK, F, 0.7)
	k.set_blend(HEAD, Vector3(0, 1.54, 0), Vector3.UP, 0.025)
	k.lathe(np, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.008)), 7)
	k.clear_blend()


# --- backpack -----------------------------------------------------------------------

static func _backpack(k: CrewMeshKit, variant: int) -> void:
	for s in [1.0, -1.0]:
		# Hoses from the pack over the yoke into the chest rig.
		k.set_part(CHEST, S, 1.6)
		k.set_blend(PACK, Vector3(0, 1.45, -0.13), Vector3.FORWARD, 0.03)
		k.tube(PackedVector3Array([Vector3(s * 0.1, 1.46, -0.17), Vector3(s * 0.168, 1.5, -0.075), Vector3(s * 0.172, 1.485, 0.04), Vector3(s * 0.11, 1.42, 0.13), Vector3(s * 0.03, 1.38, 0.152)]),
			0.015, 5, 9, 55.0, 0.22)
		# Ribbed air hoses with a gentle sag from the pack top into the helmet ports.
		k.set_part(PACK, T, 0.75)
		k.set_blend(HEAD, Vector3(0, 1.52, 0), Vector3.UP, 0.02)
		k.tube(PackedVector3Array([Vector3(s * 0.075, 1.47, -0.2), Vector3(s * 0.12, 1.465, -0.175), Vector3(s * 0.135, 1.5, -0.14), Vector3(s * 0.108, 1.548, -0.118)]),
			0.011, 6, 8, 70.0, 0.25)
		k.clear_blend()
	match variant:
		0:
			_pack_tanks(k)
		1:
			_pack_classic(k)
		2:
			_pack_dome(k)
		3:
			_pack_thrusters(k)


## Decal surface following a pack panel curved with CrewMeshKit.shell(radius) (sag toward the body).
static func _pack_sag(radius: float) -> Callable:
	return func(p: Vector3) -> Vector3: return p + Vector3(0, 0, radius * (1.0 - cos(p.x / radius)))


## Glowing player number, oxygen gauge and hazard stripes on the back of the pack.
static func _back_decals(k: CrewMeshKit, number_at: Vector3, number_size: Vector2, gauge_at: Vector3, gauge_w: float, hazard_at: Vector3, hazard_w: float, surface := Callable()) -> void:
	# Seen from behind, +U must run toward the viewer's right, which is world -X.
	var curved := surface.is_valid()
	_decal(k, PACK, number_at, Vector3.LEFT, Vector3.UP, number_size, DECAL_GLOW, 5 if curved else 2, surface, 3 if curved else 1)
	k.set_part(PACK, G)
	k.patch(func(u: float, v: float) -> Vector3:
			var p := gauge_at + Vector3(-(u - 0.5) * gauge_w, (v - 0.5) * 0.013, 0.0)
			return surface.call(p) if curved else p,
		5 if curved else 3, 1, gauge_at + Vector3(0, 0, 0.2), Vector2.ONE, func(u: float, v: float) -> Vector2: return Vector2(u, v))
	_decal(k, PACK, hazard_at, Vector3.LEFT, Vector3.UP, Vector2(hazard_w, 0.022), DECAL_HAZARD, 5 if curved else 2, surface)


## Default life-support unit: twin pill tanks in the suit colour around a glowing core.
static func _pack_tanks(k: CrewMeshKit) -> void:
	k.set_part(PACK, S, 1.0)
	k.deform = CrewMeshKit.shell(PACK_CURVE)
	k.rounded_box(Vector3(0, 1.28, -0.195), Vector3(0.2, 0.36, 0.13), 0.04, BACK_FACING, 1, Vector3i(2, 1, 1))
	k.deform = Callable()
	for s in [1.0, -1.0]:
		k.set_part(PACK, P, 1.0)
		k.capsule(Vector3(s * 0.112, 1.1, -0.22), Vector3(s * 0.112, 1.44, -0.22), 0.064, 0.064, 12, 3, 2)
		_band(k, PACK, M, Vector3(s * 0.112, 1.17, -0.22), 0.0655, 0.014, 14)
		_band(k, PACK, A, Vector3(s * 0.112, 1.37, -0.22), 0.0655, 0.008, 14)
		_nozzle(k, Vector3(s * 0.112, 1.04, -0.22))
	k.set_part(PACK, V)
	k.rounded_box(Vector3(0, 1.205, -0.261), Vector3(0.09, 0.15, 0.008), 0.0, Basis.IDENTITY, 1)
	k.set_part(PACK, S, 1.4)
	for i in 5:
		k.rounded_box(Vector3(0, 1.15 + i * 0.028, -0.268), Vector3(0.1, 0.012, 0.016), 0.0, Basis(Vector3.RIGHT, 0.5), 1)
	k.set_part(PACK, P, 0.9)
	k.deform = CrewMeshKit.shell(0.12)
	k.rounded_box(Vector3(0, 1.47, -0.2), Vector3(0.16, 0.034, 0.1), 0.015, BACK_FACING, 1, Vector3i(3, 1, 1))
	k.deform = Callable()
	_back_decals(k, Vector3(0, 1.36, -0.2615), Vector2(0.09, 0.09), Vector3(0, 1.47, -0.2515), 0.12, Vector3(0, 1.118, -0.2615), 0.14, _pack_sag(PACK_CURVE))


## Boxy life-support unit with a slatted, glowing vent.
static func _pack_classic(k: CrewMeshKit) -> void:
	k.set_part(PACK, S, 1.0)
	k.deform = CrewMeshKit.taper(1.0, 0.92, 0.2)
	k.rounded_box(Vector3(0, 1.275, -0.2), Vector3(0.3, 0.4, 0.15), 0.04, Basis.IDENTITY, 1, Vector3i(1, 2, 1))
	k.deform = Callable()
	for s in [1.0, -1.0]:
		k.set_part(PACK, P, 1.0)
		k.deform = CrewMeshKit.shell(0.0, 0.5)
		k.rounded_box(Vector3(s * 0.146, 1.27, -0.208), Vector3(0.134, 0.37, 0.042), 0.018, Basis(Vector3.UP, s * PI * 0.5), 1, Vector3i(1, 3, 1))
		k.deform = Callable()
		k.set_part(PACK, A)
		k.rounded_box(Vector3(s * 0.169, 1.27, -0.208), Vector3(0.006, 0.28, 0.012), 0.0, Basis.IDENTITY, 1)
		k.rounded_box(Vector3(s * 0.112, 1.27, -0.277), Vector3(0.012, 0.26, 0.008), 0.0, Basis.IDENTITY, 1)
		_nozzle(k, Vector3(s * 0.085, 1.03, -0.205))
	k.set_part(PACK, P, 0.9)
	k.deform = CrewMeshKit.shell(0.16)
	k.rounded_box(Vector3(0, 1.478, -0.205), Vector3(0.23, 0.038, 0.115), 0.016, BACK_FACING, 1, Vector3i(3, 1, 1))
	k.set_part(PACK, P, 1.05)
	k.deform = CrewMeshKit.shell(PACK_CURVE_WIDE)
	k.rounded_box(Vector3(0, 1.4, -0.272), Vector3(0.2, 0.1, 0.016), 0.007, BACK_FACING, 1, Vector3i(3, 1, 1))
	k.deform = Callable()
	k.set_part(PACK, V)
	k.rounded_box(Vector3(0, 1.215, -0.27), Vector3(0.17, 0.14, 0.008), 0.0, Basis.IDENTITY, 1)
	k.set_part(PACK, S, 1.4)
	for i in 5:
		k.rounded_box(Vector3(0, 1.16 + i * 0.027, -0.279), Vector3(0.19, 0.011, 0.016), 0.0, Basis(Vector3.RIGHT, 0.5), 1)
	k.set_part(PACK, S, 1.3)
	k.rounded_box(Vector3(0, 1.098, -0.262), Vector3(0.21, 0.03, 0.03), 0.012, Basis.IDENTITY, 1)
	_back_decals(k, Vector3(0, 1.4, -0.2815), Vector2(0.15, 0.085), Vector3(0, 1.322, -0.2765), 0.15, Vector3(0, 1.098, -0.2785), 0.19, _pack_sag(PACK_CURVE_WIDE))


## Rounded shell pack with a circular turbine vent.
static func _pack_dome(k: CrewMeshKit) -> void:
	k.set_part(PACK, S, 1.0)
	k.rounded_box(Vector3(0, 1.28, -0.175), Vector3(0.28, 0.36, 0.08), 0.035, Basis.IDENTITY, 1)
	k.set_part(PACK, P, 1.0)
	k.ellipsoid(Vector3(0, 1.28, -0.2), Vector3(0.155, 0.2, 0.085), Basis.IDENTITY, 20, 9)
	k.set_part(PACK, S, 1.25)
	k.cylinder(Vector3(0, 1.255, -0.268), Vector3(0, 1.255, -0.29), 0.072, 18, 0.008)
	k.set_part(PACK, M)
	k.ring(Vector3(0, 1.255, -0.291), 0.064, 0.006, Basis(Vector3.RIGHT, PI * 0.5), 18, 4)
	k.set_part(PACK, V)
	k.disc(Vector3(0, 1.255, -0.2915), Vector3.FORWARD, 0.056, 16, 0.004)
	k.set_part(PACK, S, 1.5)
	for i in 3:
		k.rounded_box(Vector3(0, 1.255, -0.295), Vector3(0.11, 0.008, 0.006), 0.0, Basis(Vector3.BACK, PI * float(i) / 3.0), 1)
	k.set_part(PACK, M)
	k.disc(Vector3(0, 1.255, -0.298), Vector3.FORWARD, 0.016, 10, 0.006)
	for s in [1.0, -1.0]:
		k.set_part(PACK, A)
		k.rounded_box(Vector3(s * 0.118, 1.28, -0.255), Vector3(0.008, 0.18, 0.008), 0.0, Basis(Vector3.UP, s * 0.7), 1)
		_nozzle(k, Vector3(s * 0.07, 1.06, -0.2))
	var dome := func(p: Vector3) -> Vector3:
		var e := 1.0 - pow(p.x / 0.155, 2.0) - pow((p.y - 1.28) / 0.2, 2.0)
		return Vector3(p.x, p.y, -0.2 - 0.085 * sqrt(maxf(e, 0.0)) - 0.003)
	_back_decals(k, Vector3(0, 1.405, 0), Vector2(0.1, 0.08), Vector3(0, 1.165, 0), 0.1, Vector3(0, 1.128, 0), 0.11, dome)


## Wide, flat pack with two thruster pods at the bottom corners.
static func _pack_thrusters(k: CrewMeshKit) -> void:
	k.set_part(PACK, S, 1.0)
	k.rounded_box(Vector3(0, 1.31, -0.195), Vector3(0.32, 0.3, 0.13), 0.04, Basis.IDENTITY, 2)
	k.set_part(PACK, P, 1.0)
	k.deform = CrewMeshKit.shell(PACK_CURVE_WIDE)
	k.rounded_box(Vector3(0, 1.36, -0.262), Vector3(0.28, 0.16, 0.018), 0.008, BACK_FACING, 1, Vector3i(4, 1, 1))
	k.deform = Callable()
	k.set_part(PACK, V)
	k.rounded_box(Vector3(0, 1.227, -0.262), Vector3(0.16, 0.012, 0.008), 0.0, Basis.IDENTITY, 1)
	for s in [1.0, -1.0]:
		k.set_part(PACK, P, 0.92)
		k.capsule(Vector3(s * 0.13, 1.06, -0.215), Vector3(s * 0.13, 1.21, -0.215), 0.05, 0.05, 12, 3, 1)
		_band(k, PACK, A, Vector3(s * 0.13, 1.15, -0.215), 0.0505, 0.009, 12)
		_nozzle(k, Vector3(s * 0.13, 1.0, -0.215))
		k.set_part(PACK, A)
		k.rounded_box(Vector3(s * 0.165, 1.36, -0.205), Vector3(0.006, 0.2, 0.012), 0.0, Basis.IDENTITY, 1)
	_back_decals(k, Vector3(0, 1.37, -0.2725), Vector2(0.12, 0.09), Vector3(0, 1.255, -0.2615), 0.18, Vector3(0, 1.195, -0.2615), 0.14, _pack_sag(PACK_CURVE_WIDE))


static func _nozzle(k: CrewMeshKit, at: Vector3) -> void:
	k.set_part(PACK, M)
	k.lathe(PackedVector2Array([Vector2(0.026, 0.0), Vector2(0.032, 0.01), Vector2(0.028, 0.045), Vector2(0.02, 0.055)]),
		Transform3D(Basis.IDENTITY, at), 12)
	k.set_part(PACK, V)
	k.disc(at + Vector3(0, 0.006, 0), Vector3.DOWN, 0.024, 10, 0.0)


# --- helmet -------------------------------------------------------------------------

static func _head(k: CrewMeshKit, variant: int) -> void:
	var top := HELMET_C + HELMET_RY
	k.set_part(HEAD, P, 1.0)
	k.lathe(helmet_profile(), Transform3D(Basis.IDENTITY, Vector3(0, 0, HELMET_Z)), 22, Vector2(1.0, HELMET_DEPTH))
	# Graphite jaw ring (panel seam between shell and collar seal).
	var jaw := PackedVector2Array()
	var jaw_y: Array[float] = [HELMET_BASE - 0.006, HELMET_BASE, 1.54, 1.562, 1.572]
	for i in jaw_y.size():
		var y := jaw_y[i]
		var inset := -0.008 if i == 0 else (-0.004 if i == jaw_y.size() - 1 else 0.0)
		jaw.append(Vector2(helmet_radius(maxf(y, HELMET_BASE)) * 1.035 + inset, y))
	k.set_part(HEAD, S, 1.1)
	k.lathe(jaw, Transform3D(Basis.IDENTITY, Vector3(0, 0, HELMET_Z)), 18, Vector2(1.0, HELMET_DEPTH), 0.0, TAU, PackedFloat32Array([0, 1, 0, 1, 0]))
	# Thick graphite bezel around the visor (the glass draws the thin emissive line).
	k.set_part(HEAD, S, 1.3)
	k.tube(_visor_outline(0.007), 0.0095, 5, 24, 0.0, 0.0, true)
	# Visor hood: the bezel thickens into a brow over the top of the visor (tapered ends).
	var hood := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		var u := 1.0 if t < 0.5 else 0.0
		var v := lerpf(0.55, 1.0, t * 2.0) if t < 0.5 else lerpf(1.0, 0.55, t * 2.0 - 1.0)
		hood.append(_visor_point(u, v, 0.012) + Vector3(0, 0.007, 0))
	k.set_part(HEAD, S, 1.25)
	k.tube(hood, 0.0145, 5, 18, 0.0, 0.0, false, func(t: float) -> float: return 0.35 + 0.65 * pow(sin(t * PI), 0.6))
	for s in [1.0, -1.0]:
		# Ear pods: rounded comm units with an emissive band, a vent grille and a light.
		var c := Vector3(s * 0.168, HELMET_C, -0.012)
		var out := Vector3(s, 0, 0)
		k.set_part(HEAD, S, 1.15)
		k.cylinder(c, c + out * 0.034, 0.055, 14, 0.016)
		_annulus(k, HEAD, A, c + out * 0.0345, out, 0.034, 0.041, 14)
		_disc_decal(k, HEAD, c + out * 0.035, out, 0.031, DECAL_GRILLE, 12)
		k.set_part(HEAD, ST)
		k.rounded_box(c + Vector3(s * 0.022, 0.0, 0.057), Vector3(0.012, 0.008, 0.005), 0.0, Basis.IDENTITY, 1)
		# Side lamps above the ears.
		k.set_part(HEAD, S, 1.3)
		k.cylinder(Vector3(s * 0.166, 1.728, 0.0), Vector3(s * 0.166, 1.728, 0.066), 0.016, 8, 0.006)
		k.set_part(HEAD, L)
		k.disc(Vector3(s * 0.166, 1.728, 0.0665), Vector3.BACK, 0.0115, 8, 0.004)
		# Rear life-support ports where the air hoses plug in.
		var hose_end := Vector3(s * 0.108, 1.548, -0.118)
		var hose_dir := (hose_end - Vector3(s * 0.135, 1.5, -0.14)).normalized()
		k.set_part(HEAD, M)
		k.cylinder(hose_end - hose_dir * 0.016, hose_end + hose_dir * 0.006, 0.017, 10, 0.004)
	# Crew insignia and stencil text on the left rear of the helmet.
	k.set_part(HEAD, DC)
	k.patch(func(u: float, v: float) -> Vector3: return helmet_point(lerpf(1.85, 2.45, u), lerpf(1.665, 1.735, v), 0.0018),
		4, 2, Vector3(0, HELMET_C, HELMET_Z), Vector2.ONE, Callable(), Vector2(DECAL_INSIGNIA, 1.5))
	# Rear comms module with a player-colour slit (readable from behind).
	k.set_part(HEAD, S, 1.2)
	k.deform = CrewMeshKit.shell(0.185)
	k.skip_back = true
	k.rounded_box(Vector3(0, 1.6, HELMET_Z - 0.184), Vector3(0.12, 0.065, 0.032), 0.012, Basis(Vector3.UP, PI), 1)
	k.set_part(HEAD, A)
	k.deform = CrewMeshKit.shell(0.2)
	k.rounded_box(Vector3(0, 1.603, HELMET_Z - 0.201), Vector3(0.08, 0.009, 0.006), 0.0, Basis(Vector3.UP, PI), 1)
	k.deform = Callable()
	match variant:
		0:
			# Crest with an accent inlay + left whip antenna.
			k.set_part(HEAD, S, 1.2)
			k.deform = shifted(CrewMeshKit.arc_z(0.18), Vector3(0, 0, -0.03))
			k.rounded_box(Vector3(0, top, HELMET_Z), Vector3(0.052, 0.026, 0.28), 0.012, Basis.IDENTITY, 1, Vector3i(1, 1, 6))
			k.set_part(HEAD, A)
			k.deform = shifted(CrewMeshKit.arc_z(0.18), Vector3(0, 0.013, -0.03))
			k.rounded_box(Vector3(0, top, HELMET_Z), Vector3(0.015, 0.008, 0.25), 0.0, Basis.IDENTITY, 1, Vector3i(1, 1, 8))
			k.deform = Callable()
			_antenna(k, Vector3(0.18, 1.7, -0.05), Vector3(0.2, 1.865, -0.12))
		1:
			# Swept dorsal fin in the suit colour with a glowing leading edge.
			k.set_part(HEAD, P, 1.0)
			k.deform = shifted(CrewMeshKit.arc_z(0.2), Vector3(0, 0, -0.045))
			k.rounded_box(Vector3(0, top + 0.012, HELMET_Z), Vector3(0.026, 0.075, 0.24), 0.012, CrewMeshKit.shear_basis(0.45), 1, Vector3i(1, 1, 6))
			k.set_part(HEAD, A)
			k.deform = shifted(CrewMeshKit.arc_z(0.2), Vector3(0, 0.039, -0.045))
			k.rounded_box(Vector3(0, top + 0.012, HELMET_Z), Vector3(0.012, 0.008, 0.2), 0.0, Basis.IDENTITY, 1, Vector3i(1, 1, 6))
			k.deform = Callable()
		2:
			# Twin antennae rising from the ear pods, low dome sensor on top.
			for s2 in [1.0, -1.0]:
				_antenna(k, Vector3(s2 * 0.19, 1.69, -0.035), Vector3(s2 * 0.215, 1.84, -0.07))
			k.set_part(HEAD, S, 1.2)
			k.ellipsoid(Vector3(0, top - 0.004, HELMET_Z - 0.02), Vector3(0.032, 0.014, 0.05), Basis.IDENTITY, 10, 4)
			_annulus(k, HEAD, A, Vector3(0, top + 0.0095, HELMET_Z - 0.02), Vector3.UP, 0.008, 0.016, 10)
		3:
			# Halo crown band + stubby rear beacon.
			var hy := 1.772
			k.set_part(HEAD, A)
			k.ring(Vector3(0, hy, HELMET_Z), helmet_radius(hy) + 0.002, 0.0055, Basis.IDENTITY, 24, 4, Vector2(1.0, HELMET_DEPTH))
			_antenna(k, Vector3(0, 1.75, HELMET_Z - 0.13), Vector3(0, 1.82, HELMET_Z - 0.17), 0.018)


## Antenna skinned from the head (base) to the spring-driven Antenna bone (tip).
static func _antenna(k: CrewMeshKit, a: Vector3, b: Vector3, stub := 0.0) -> void:
	var d := (b - a).normalized()
	var length := a.distance_to(b)
	k.set_part(HEAD, S, 1.2)
	k.cylinder(a, a + (b - a) * 0.15, 0.011 if stub == 0.0 else stub, 8, 0.004)
	k.set_part(HEAD, M)
	k.set_blend(ANTENNA, a + d * length * 0.5, d, length * 0.5)
	k.cylinder(a, b, 0.0055 if stub == 0.0 else stub * 0.6, 6, 0.001)
	k.clear_blend()
	k.set_part(ANTENNA, BL)
	k.ellipsoid(b, Vector3(0.012, 0.012, 0.012), Basis.IDENTITY, 8, 4)


static func _visor_point(u: float, v: float, lift: float) -> Vector3:
	var tv := 2.0 * v - 1.0
	var half := VISOR_HALF_ANGLE * pow(maxf(1.0 - pow(absf(tv), 4.0), 0.0), 0.25) * (0.8 + 0.2 * v)
	var a := (2.0 * u - 1.0) * half
	var y := lerpf(VISOR_Y.x, VISOR_Y.y, v)
	var bulge := 0.009 * (1.0 - tv * tv) * (1.0 - pow(2.0 * u - 1.0, 2.0))
	return helmet_point(a, y, lift + bulge)


static func _visor_outline(lift: float) -> PackedVector3Array:
	# The visor's width pinches to zero at v = 0 and v = 1, so its outline is the
	# u = 1 edge going up followed by the u = 0 edge coming back down.
	var pts := PackedVector3Array()
	var n := 20
	for i in n + 1:
		var v := 0.5 - 0.5 * cos(PI * float(i) / float(n))
		pts.append(_visor_point(1.0, v, lift))
	for i in range(1, n + 1):
		var v2 := 0.5 + 0.5 * cos(PI * float(i) / float(n))
		pts.append(_visor_point(0.0, v2, lift))
	return pts


static func _visor(k: CrewMeshKit) -> void:
	# UV is in metres on the glass: x = arc length from the centre line (+ = character's
	# left), y = height above the visor middle. The LED face shader draws in this space.
	k.set_part(HEAD, CrewMaterials.PRIMARY)
	var head := JOINTS[HEAD]
	var mid := (VISOR_Y.x + VISOR_Y.y) * 0.5
	k.patch(func(u: float, v: float) -> Vector3: return _visor_point(u, v, 0.004) - head,
		16, 9, Vector3(0, HELMET_C, HELMET_Z) - head, Vector2.ONE,
		func(u: float, v: float) -> Vector2:
			var p := _visor_point(u, v, 0.004)
			return Vector2(atan2(p.x, (p.z - HELMET_Z) / HELMET_DEPTH) * HELMET_RX, p.y - mid),
		Vector2.ZERO, true)


# --- limbs --------------------------------------------------------------------------

static func _arm(k: CrewMeshKit, s: float) -> void:
	var up := L_ARM if s > 0.0 else R_ARM
	var fore := L_FORE if s > 0.0 else R_FORE
	var x := JOINTS[up].x
	var z0 := JOINTS[up].z
	var out := Vector3(s, 0, 0)
	# Shoulder bearing ball: fills the socket whatever the arm angle.
	k.set_part(up, F, 0.7)
	k.ellipsoid(Vector3(x - s * 0.01, 1.425, z0), Vector3(0.068, 0.066, 0.072), Basis.IDENTITY, 8, 4)
	# Upper arm: wide at the shoulder, tapering to the elbow.
	k.set_part(up, F, 0.85)
	_limb(k, Vector3(x, 1.17, z0), Vector3(x, 1.42, z0), [0.052, 0.056, 0.061, 0.064] as Array[float], 12)
	# Coloured upper-arm shell wrapping the outer/front side; tucks under the pauldron
	# and steps down onto the elbow barrel. Accent band near its lower edge.
	_shell(k, up, P, 1.0, Vector3(x, 1.2, z0), Vector3(x, 1.375, z0), 0.0535, 0.0625, s * 1.05, 2.7, 0.017, 0.004, 8, 2)
	_shell(k, up, A, 1.0, Vector3(x, 1.215, z0), Vector3(x, 1.222, z0), 0.0745, 0.0749, s * 1.05, 1.5, 0.003, 0.0, 6, 1)
	# Pauldron: graphite under-layer + domed cap overlapping the arm shell, emissive rim
	# band, held by a strap with a brushed-metal buckle.
	var pad_dir := Vector3(s * 0.5, 0.866, 0.0)
	var pad_basis := Basis(pad_dir.cross(Vector3.BACK).normalized(), pad_dir, Vector3.BACK)
	var pad_c := Vector3(x + s * 0.018, 1.446, z0)
	var sc := 0.82
	k.set_part(up, S, 1.15)
	k.lathe(PackedVector2Array([Vector2(0.09 * sc, -0.05 * sc), Vector2(0.106 * sc, -0.044 * sc), Vector2(0.11 * sc, -0.022 * sc), Vector2(0.1 * sc, 0.0), Vector2(0.084 * sc, 0.012 * sc)]),
		Transform3D(pad_basis, pad_c), 12, Vector2(1.0, 1.08), 0.0, TAU, PackedFloat32Array([0, 1, 0.5, 1, 0]))
	k.set_part(up, P, 1.0)
	var dome := PackedVector2Array([Vector2(0.092 * sc, -0.006 * sc), Vector2(0.1 * sc, 0.006 * sc), Vector2(0.095 * sc, 0.034 * sc), Vector2(0.076 * sc, 0.062 * sc), Vector2(0.042 * sc, 0.078 * sc), Vector2(0.0, 0.083 * sc)])
	k.lathe(dome, Transform3D(pad_basis, pad_c), 14, Vector2(1.0, 1.08), 0.0, TAU, PackedFloat32Array([0, 1, 0, 0, 0, 0]))
	k.set_part(up, A)
	k.lathe(PackedVector2Array([Vector2(0.1 * sc + 0.0012, 0.003), Vector2(0.098 * sc + 0.0012, 0.0115)]),
		Transform3D(pad_basis, pad_c), 14, Vector2(1.0, 1.08))
	k.set_part(up, S, 1.3)
	k.rounded_box(Vector3(x + s * 0.091, 1.372, z0), Vector3(0.008, 0.06, 0.03), 0.0035, Basis(Vector3.BACK, s * 0.12), 1)
	k.set_part(up, M)
	k.rounded_box(Vector3(x + s * 0.0955, 1.362, z0), Vector3(0.005, 0.018, 0.036), 0.0, Basis(Vector3.BACK, s * 0.12), 1)
	# Player number on the outer face of the pauldron, following the dome.
	var out_h := Vector3(s * 0.866, -0.5, 0.0)
	var side := Vector3(0, 0, -s)
	k.set_part(up, DC)
	k.patch(func(u: float, v: float) -> Vector3:
			var yy := lerpf(0.004, 0.042, v)
			var rr := _profile_r(dome, yy) + 0.0016
			var al := (u - 0.5) * 0.85
			return pad_c + pad_dir * yy + out_h * cos(al) * rr + side * sin(al) * rr * 1.08,
		4, 2, pad_c, Vector2.ONE, Callable(), Vector2(DECAL_PAINT, 1.6))
	# Elbow: smooth hinge barrel, bolted cap, graphite elbow cop.
	_barrel(k, fore, Vector3(x, 1.13, z0), 0.044, 0.057, 14)
	_hinge(k, fore, Vector3(x + s * 0.06, 1.13, z0), out, 0.03)
	_cap(k, fore, S, 1.2, Vector3(x, 1.135, z0 - 0.045), Vector3.FORWARD, 0.04, 0.026, 1.1, 12)
	# Forearm and flared gauntlet: a wrapped shell open on the palm side, two-tone cuff.
	k.set_part(fore, F, 0.85)
	_limb(k, Vector3(x, 0.89, z0), Vector3(x, 1.1, z0), [0.042, 0.047, 0.052, 0.05] as Array[float], 12)
	_shell(k, fore, P, 1.0, Vector3(x, 0.93, z0 + 0.003), Vector3(x, 1.07, z0 + 0.003), 0.045, 0.051, s * 0.85, 4.9, 0.02, 0.006, 11, 2, 0.008)
	_shell(k, fore, T, 1.0, Vector3(x, 0.898, z0 + 0.003), Vector3(x, 0.926, z0 + 0.003), 0.0435, 0.045, s * 0.85, 4.9, 0.016, 0.006, 10, 1)
	k.set_part(fore, A)
	k.rounded_box(Vector3(x + s * 0.077, 0.995, z0 + 0.003), Vector3(0.003, 0.055, 0.026), 0.0, Basis.IDENTITY, 1)
	# Wrist: crisp flex ribs; the CrewHand glove (separate mesh on the hand bone)
	# starts just below them.
	_ribs(k, fore, Vector3(x, 0.876, z0 + 0.004), 1, 0.02, 0.047, 12)


static func _leg(k: CrewMeshKit, s: float) -> void:
	var thigh := L_LEG if s > 0.0 else R_LEG
	var shin := L_SHIN if s > 0.0 else R_SHIN
	var foot := L_FOOT if s > 0.0 else R_FOOT
	var x := JOINTS[thigh].x
	var out := Vector3(s, 0, 0)
	# Thigh: muscle-like taper, skinned into the hips at the top.
	k.set_part(thigh, F, 0.85)
	k.set_blend(HIPS, Vector3(x, 0.9, 0), Vector3.UP, 0.05)
	_limb(k, Vector3(x, 0.545, 0.0), Vector3(x, 0.97, -0.005), [0.07, 0.08, 0.09, 0.096, 0.097] as Array[float], 12)
	k.clear_blend()
	# Articulated thigh armour: two overlapping wrapped shells (upper over lower) with a
	# soft centre ridge, covering the front and outer side and tapering to the knee.
	# The inner edge stops short of the other leg so the legs never collide.
	var thigh_theta := s * 0.9
	_shell(k, thigh, P, 1.0, Vector3(x, 0.585, 0.0), Vector3(x, 0.74, 0.0), 0.0735, 0.0875, thigh_theta, 3.0, 0.018, 0.005, 10, 2, 0.0, 0.0, 1.0, 0.007, 0.72)
	_shell(k, thigh, P, 0.96, Vector3(x, 0.705, -0.002), Vector3(x, 0.845, -0.002), 0.094, 0.083, thigh_theta, 3.0, 0.018, 0.016, 10, 2, 0.0, 0.0, 1.0, 0.007, 0.95)
	if s < 0.0:
		# Right thigh: holster on the back-outer side, on a strap round the inner leg.
		k.set_part(thigh, S, 1.15)
		_plate(k, Vector3(x, 0.7, -0.005), 0.088, s * 2.85, Vector3(0.06, 0.14, 0.04), 0.015, 0.0, 0.85)
		k.set_part(thigh, S, 0.9)
		k.lathe(PackedVector2Array([Vector2(0.084, 0.688), Vector2(0.091, 0.692), Vector2(0.091, 0.706), Vector2(0.084, 0.71)]),
			Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.002)), 8, Vector2.ONE, 1.45, 3.7)
	else:
		k.set_part(thigh, S, 1.15)
		_plate(k, Vector3(x, 0.72, -0.005), 0.088, s * 2.85, Vector3(0.07, 0.1, 0.038), 0.015)
	# Knee: smooth hinge barrel, bolted cap, off-white knee guard on the shin.
	_barrel(k, shin, Vector3(x, 0.505, -0.004), 0.058, 0.075, 12)
	_hinge(k, shin, Vector3(x + s * 0.079, 0.505, -0.004), out, 0.036)
	_cap(k, shin, T, 1.0, Vector3(x, 0.508, 0.062), Vector3.BACK, 0.056, 0.038, 1.3, 14)
	# Shin with a calf bulge; wrapped shin guard with an accent stripe, calf shell.
	k.set_part(shin, F, 0.85)
	_limb(k, Vector3(x, 0.15, -0.01), Vector3(x, 0.49, -0.005), [0.062, 0.066, 0.072, 0.074, 0.068] as Array[float], 14, Vector2(1.0, 1.08))
	_shell(k, shin, P, 1.0, Vector3(x, 0.245, -0.005), Vector3(x, 0.435, -0.005), 0.0695, 0.0765, 0.0, 2.7, 0.02, 0.005, 9, 2)
	_shell(k, shin, A, 1.0, Vector3(x, 0.27, -0.005), Vector3(x, 0.41, -0.005), 0.0943, 0.1013, 0.0, 0.07, 0.003, 0.0, 1, 3)
	_shell(k, shin, P, 0.9, Vector3(x, 0.29, -0.012), Vector3(x, 0.43, -0.012), 0.072, 0.0755, PI, 2.1, 0.016, 0.005, 6, 2)
	# Chunky boot cuff with a brushed-metal lip.
	k.set_part(shin, S, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.062, 0.12), Vector2(0.071, 0.13), Vector2(0.074, 0.2), Vector2(0.076, 0.228), Vector2(0.066, 0.238)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.008)), 14, Vector2(1.0, 1.15), 0.0, TAU, PackedFloat32Array([0, 1, 0, 1, 0]))
	k.set_part(shin, M)
	k.lathe(PackedVector2Array([Vector2(0.074, 0.226), Vector2(0.08, 0.23), Vector2(0.08, 0.242), Vector2(0.072, 0.246)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.008)), 14, Vector2(1.0, 1.15))
	# Ankle: crisp flex ribs under the cuff, guard plate with a bolt.
	_ribs(k, shin, Vector3(x, 0.11, -0.008), 1, 0.022, 0.067, 14, Vector2(1.0, 1.12))
	k.set_part(foot, S, 1.2)
	k.rounded_box(Vector3(x + s * 0.064, 0.092, -0.014), Vector3(0.02, 0.074, 0.078), 0.009, Basis.IDENTITY, 1)
	k.set_part(foot, M)
	k.disc(Vector3(x + s * 0.0745, 0.094, -0.014), out, 0.014, 6, 0.004)
	# Magnetic boot: shell, off-white toe cap, thick sole with treads and a glow ring.
	k.set_part(foot, S, 1.0)
	k.deform = CrewMeshKit.taper(1.0, 0.86, 0.045)
	k.rounded_box(Vector3(x, 0.072, 0.04), Vector3(0.124, 0.095, 0.28), 0.038, Basis.IDENTITY, 1)
	k.deform = Callable()
	k.set_part(foot, T, 0.95)
	k.rounded_box(Vector3(x, 0.068, 0.14), Vector3(0.11, 0.076, 0.088), 0.032, Basis.IDENTITY, 1)
	k.set_part(foot, R)
	k.rounded_box(Vector3(x, 0.02, 0.04), Vector3(0.122, 0.03, 0.292), 0.012, Basis.IDENTITY, 1)
	k.set_part(foot, SO)
	k.rounded_box(Vector3(x, 0.031, 0.04), Vector3(0.126, 0.007, 0.262), 0.0, Basis.IDENTITY, 1)
	k.set_part(foot, R, 0.8)
	for i in 4:
		k.rounded_box(Vector3(x, 0.004, -0.07 + i * 0.07), Vector3(0.1, 0.008, 0.032), 0.0, Basis.IDENTITY, 1)


static func _occluders(k: CrewMeshKit) -> void:
	k.add_occluder(Vector3(0, 1.33, -0.015), 0.12)
	k.add_occluder(Vector3(0, 1.27, -0.2), 0.12)
	k.add_occluder(Vector3(0, 0.94, 0), 0.11)
	k.add_occluder(Vector3(0, 1.12, -0.01), 0.1)
	k.add_occluder(Vector3(0, HELMET_C, HELMET_Z), 0.165)
	for s in [1.0, -1.0]:
		k.add_occluder(Vector3(s * 0.235, 1.3, -0.015), 0.055)
		k.add_occluder(Vector3(s * 0.235, 0.99, -0.012), 0.05)
		k.add_occluder(Vector3(s * 0.25, 1.47, -0.015), 0.06)
		k.add_occluder(Vector3(s * 0.1, 0.78, 0), 0.08)
		k.add_occluder(Vector3(s * 0.1, 0.62, 0), 0.07)
		k.add_occluder(Vector3(s * 0.1, 0.33, 0), 0.055)
		k.add_occluder(Vector3(s * 0.1, 0.06, 0.05), 0.055)
