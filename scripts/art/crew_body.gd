class_name CrewBody
extends RefCounted
## Rig layout and procedural geometry of the crew EVA suit.
## Bind pose: origin at the feet, facing +Z, character's left = +X, arms straight down.
## Every joint is covered: bellows sleeves (skinned across the joint), bearing balls,
## hinge caps with bolts, and overlapping plates, so no pose opens a gap.

enum { HIPS, SPINE, CHEST, NECK, HEAD, L_ARM, L_FORE, L_HAND, R_ARM, R_FORE, R_HAND, L_LEG, L_SHIN, L_FOOT, R_LEG, R_SHIN, R_FOOT,
	L_FINGERS, L_THUMB, R_FINGERS, R_THUMB, ANTENNA, PACK }

const BONE_NAMES: Array[String] = ["Hips", "Spine", "Chest", "Neck", "Head",
	"LeftArm", "LeftForearm", "LeftHand", "RightArm", "RightForearm", "RightHand",
	"LeftLeg", "LeftShin", "LeftFoot", "RightLeg", "RightShin", "RightFoot",
	"LeftFingers", "LeftThumb", "RightFingers", "RightThumb", "Antenna", "Backpack"]
const PARENTS: Array[int] = [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15, 7, 7, 10, 10, 4, 2]
const JOINTS: Array[Vector3] = [
	Vector3(0, 0.97, 0), Vector3(0, 1.07, 0), Vector3(0, 1.21, -0.01), Vector3(0, 1.47, -0.012), Vector3(0, 1.555, -0.005),
	Vector3(0.222, 1.425, -0.015), Vector3(0.222, 1.13, -0.015), Vector3(0.222, 0.86, -0.015),
	Vector3(-0.222, 1.425, -0.015), Vector3(-0.222, 1.13, -0.015), Vector3(-0.222, 0.86, -0.015),
	Vector3(0.1, 0.93, 0), Vector3(0.1, 0.505, 0), Vector3(0.1, 0.09, 0),
	Vector3(-0.1, 0.93, 0), Vector3(-0.1, 0.505, 0), Vector3(-0.1, 0.09, 0),
	Vector3(0.216, 0.776, -0.006), Vector3(0.207, 0.832, 0.035),
	Vector3(-0.216, 0.776, -0.006), Vector3(-0.207, 0.832, 0.035),
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

## Decal styles (UV2.x on DECAL vertices).
const DECAL_PAINT := 0.0
const DECAL_GLOW := 1.0
const DECAL_HAZARD := 2.0
const DECAL_NAMEPLATE := 3.0

## Helmet: a slightly squashed sphere (about 1.1x the v1 shell), open at the neck.
const HELMET_C := 1.648
const HELMET_RX := 0.178
const HELMET_RY := 0.168
const HELMET_BASE := 1.515
const HELMET_Z := -0.006
const HELMET_DEPTH := 1.05
const VISOR_Y := Vector2(1.565, 1.742)
const VISOR_HALF_ANGLE := 1.0
const VARIANTS := 4

static var _cache := {}


static func body_mesh(variant := 0) -> ArrayMesh:
	var key := "body%d" % posmod(variant, VARIANTS)
	if not _cache.has(key):
		_build(posmod(variant, VARIANTS))
	return _cache[key]


static func visor_mesh() -> ArrayMesh:
	if not _cache.has("visor"):
		var vk := CrewMeshKit.new()
		_visor(vk)
		_cache["visor"] = vk.commit()
		_cache["visor_tris"] = vk.triangle_count()
	return _cache["visor"]


## (body, visor) triangles for a variant.
static func triangle_counts(variant := 0) -> Vector2i:
	body_mesh(variant)
	visor_mesh()
	return Vector2i(_cache["body_tris%d" % posmod(variant, VARIANTS)], _cache["visor_tris"])


static func _build(variant: int) -> void:
	var kit := CrewMeshKit.new()
	kit.bevel_scale = 1.35
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
	for j in [L_FORE, R_FORE, L_SHIN, R_SHIN, L_ARM, R_ARM]:
		creases.append(JOINTS[j])
	kit.bake_creases(creases, 0.1, F)
	_cache["body%d" % variant] = kit.commit()
	_cache["body_tris%d" % variant] = kit.triangle_count()


static func shifted(c: Callable, off: Vector3) -> Callable:
	return func(p: Vector3) -> Vector3: return c.call(p + off)


static func helmet_radius(y: float) -> float:
	var t := clampf((y - HELMET_C) / HELMET_RY, -1.0, 1.0)
	return HELMET_RX * sqrt(1.0 - t * t)


static func helmet_profile() -> PackedVector2Array:
	var prof := PackedVector2Array()
	var t0 := asin(clampf((HELMET_BASE - HELMET_C) / HELMET_RY, -1.0, 1.0))
	prof.append(Vector2(helmet_radius(HELMET_BASE) - 0.012, HELMET_BASE - 0.004))
	for i in 11:
		var t := lerpf(t0, PI * 0.5, float(i) / 10.0)
		prof.append(Vector2(HELMET_RX * cos(t), HELMET_C + HELMET_RY * sin(t)))
	prof[prof.size() - 1] = Vector2(0.0, HELMET_C + HELMET_RY)
	return prof


# --- reusable joint pieces -----------------------------------------------------------

## Accordion rubber sleeve centred on a joint, skinned from `bone` to `other` across it.
static func _bellows(k: CrewMeshKit, center: Vector3, down: Vector3, length: float, radius: float, ripples: int, segments: int, bone: int, other: int, scale_xz := Vector2.ONE, skin := true) -> void:
	var prof := PackedVector2Array()
	var rows := ripples * 2
	for i in rows + 1:
		var t := float(i) / float(rows)
		var rr := radius * (1.0 + 0.09 * cos(float(i) * PI))
		prof.append(Vector2(rr, length * (t - 0.5)))
	k.set_part(bone, F, 0.72)
	if skin:
		k.set_blend(other, center, down, length * 0.42)
	var up := -down.normalized()
	var ref := Vector3.BACK if absf(up.dot(Vector3.BACK)) < 0.9 else Vector3.RIGHT
	var x := up.cross(ref).normalized()
	var z := x.cross(up)
	k.lathe(prof, Transform3D(Basis(x, up, z), center), segments, scale_xz)
	k.clear_blend()


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


## Ridged rubber hinge barrel on the hinge (X) axis of a knee or elbow, rigid on the
## lower bone: a cylinder about its own rotation axis covers the joint at any bend.
static func _barrel(k: CrewMeshKit, bone: int, center: Vector3, half_len: float, radius: float, ripples: int, segments: int) -> void:
	var prof := PackedVector2Array()
	prof.append(Vector2(0.0, -half_len - radius * 0.32))
	prof.append(Vector2(radius * 0.7, -half_len - radius * 0.2))
	var rows := ripples * 2
	for i in rows + 1:
		var t := float(i) / float(rows)
		prof.append(Vector2(radius * (1.0 - 0.07 * cos(float(i) * PI)), lerpf(-half_len, half_len, t)))
	prof.append(Vector2(radius * 0.7, half_len + radius * 0.2))
	prof.append(Vector2(0.0, half_len + radius * 0.32))
	k.set_part(bone, F, 0.72)
	k.lathe(prof, Transform3D(Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK), center), segments)


## Hinge cap with a metal bolt on the outer side of an elbow / knee / ankle.
static func _hinge(k: CrewMeshKit, bone: int, at: Vector3, out: Vector3, radius: float) -> void:
	k.set_part(bone, S, 1.2)
	k.disc(at, out, radius, 12, radius * 0.35)
	k.set_part(bone, M)
	k.disc(at + out * radius * 0.36, out, radius * 0.38, 6, radius * 0.12)


## Flat decal patch (UV 0..1) facing `normal`, `right` = +U direction.
static func _decal(k: CrewMeshKit, bone: int, center: Vector3, right: Vector3, up: Vector3, size: Vector2, style: float, cols := 1, surface := Callable(), rows := 1) -> void:
	k.set_part(bone, DC)
	var normal := right.cross(up).normalized()
	k.patch(func(u: float, v: float) -> Vector3:
			var p := center + right * (u - 0.5) * size.x + up * (v - 0.5) * size.y
			return surface.call(p) if surface.is_valid() else p,
		cols, rows, center - normal * 0.2, Vector2.ONE, Callable(), Vector2(style, size.x / size.y))


# --- body parts ---------------------------------------------------------------------

static func _hips(k: CrewMeshKit) -> void:
	k.set_part(HIPS, F, 0.9)
	k.deform = CrewMeshKit.taper(0.86, 1.0, 0.1)
	k.rounded_box(Vector3(0, 0.935, -0.005), Vector3(0.315, 0.2, 0.22), 0.08, Basis.IDENTITY, 2)
	# Belt (the hip ring the thigh guards tuck under).
	k.set_part(HIPS, S, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.142, 0.962), Vector2(0.16, 0.968), Vector2(0.164, 0.99), Vector2(0.163, 1.014), Vector2(0.156, 1.026), Vector2(0.14, 1.032)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.004)), 20, Vector2(1.0, 0.8), 0.0, TAU, PackedFloat32Array([0, 1, 0, 0, 1, 0]))
	k.set_part(HIPS, M, 1.0)
	k.rounded_box(Vector3(0, 0.997, 0.13), Vector3(0.075, 0.054, 0.022), 0.009, Basis.IDENTITY, 1)
	k.set_part(HIPS, A)
	k.rounded_box(Vector3(0, 0.997, 0.142), Vector3(0.042, 0.008, 0.004), 0.0, Basis.IDENTITY, 1)
	# Front and rear plates.
	k.set_part(HIPS, P, 0.92)
	k.deform = CrewMeshKit.shell(0.15, 0.0, 0.55, 0.055)
	k.skip_back = true
	k.rounded_box(Vector3(0, 0.905, 0.1), Vector3(0.13, 0.11, 0.028), 0.012, Basis.IDENTITY, 1)
	k.set_part(HIPS, S, 1.1)
	k.deform = CrewMeshKit.shell(0.16, 0.0, 0.8, 0.05)
	k.skip_back = true
	k.rounded_box(Vector3(0, 0.93, -0.112), Vector3(0.21, 0.1, 0.028), 0.01, Basis(Vector3.UP, PI), 1)
	for s in [1.0, -1.0]:
		# Thigh guards hang from under the belt.
		k.set_part(HIPS, P, 1.0)
		k.deform = CrewMeshKit.shell(0.2, 0.0, 0.85, 0.08)
		k.skip_back = true
		k.rounded_box(Vector3(s * 0.162, 0.9, 0.0), Vector3(0.16, 0.16, 0.026), 0.012, Basis(Vector3.UP, s * PI * 0.5) * Basis(Vector3.RIGHT, -0.12), 1)
		k.set_part(HIPS, A)
		k.rounded_box(Vector3(s * 0.177, 0.94, 0.0), Vector3(0.1, 0.008, 0.004), 0.0, Basis(Vector3.UP, s * PI * 0.5) * Basis(Vector3.RIGHT, -0.12), 1)
		# Belt pouch.
		k.set_part(HIPS, S, 1.25)
		k.deform = CrewMeshKit.shell(0.17, 0.0)
		k.rounded_box(Vector3(s * 0.11, 0.975, 0.112), Vector3(0.06, 0.06, 0.036), 0.014, Basis(Vector3.UP, s * 0.75), 1)
		k.deform = Callable()


static func _torso(k: CrewMeshKit) -> void:
	# Waist bellows (spine), blending into hips below.
	var prof := PackedVector2Array()
	for i in 11:
		var y := lerpf(0.99, 1.25, float(i) / 10.0)
		var rr := 0.112 + 0.007 * cos(float(i) * PI) + 0.012 * sin(clampf((y - 0.99) / 0.26, 0.0, 1.0) * PI)
		prof.append(Vector2(rr, y))
	k.set_part(SPINE, F, 0.8)
	k.set_blend(HIPS, Vector3(0, 1.03, 0), Vector3.DOWN, 0.04)
	k.lathe(prof, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 14, Vector2(1.0, 0.78))
	# Abdominal armour bands (graphite: dark waist, bright chest -> heroic V).
	k.set_part(SPINE, S, 1.15)
	k.deform = CrewMeshKit.shell(0.175, 0.0)
	k.skip_back = true
	k.rounded_box(Vector3(0, 1.128, 0.1), Vector3(0.16, 0.042, 0.024), 0.01, Basis.IDENTITY, 1)
	k.set_part(SPINE, S, 1.0)
	k.set_blend(HIPS, Vector3(0, 1.03, 0), Vector3.DOWN, 0.04)
	k.deform = CrewMeshKit.shell(0.17, 0.0)
	k.skip_back = true
	k.rounded_box(Vector3(0, 1.075, 0.097), Vector3(0.145, 0.04, 0.024), 0.01, Basis.IDENTITY, 1)
	# Chest core: elliptical section so the plates can hug it.
	var tp := PackedVector2Array([Vector2(0.118, 1.15), Vector2(0.142, 1.2), Vector2(0.162, 1.26), Vector2(0.176, 1.33),
		Vector2(0.178, 1.39), Vector2(0.168, 1.44), Vector2(0.14, 1.475), Vector2(0.1, 1.5)])
	k.set_part(CHEST, F, 0.9)
	k.set_blend(SPINE, Vector3(0, 1.2, 0), Vector3.DOWN, 0.04)
	k.lathe(tp, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.015)), 18, Vector2(1.0, 0.68))
	for s in [1.0, -1.0]:
		# Pectoral plates wrapping the torso, with a channel for the chest rig.
		k.set_part(CHEST, P, 1.0)
		k.deform = shifted(CrewMeshKit.shell(0.29, 0.5, 0.78, 0.105), Vector3(s * 0.09, 0, 0))
		k.skip_back = true
		k.rounded_box(Vector3(0, 1.362, 0.128), Vector3(0.16, 0.21, 0.044), 0.02, Basis.IDENTITY, 1, Vector3i(1, 2, 1))
		k.set_part(CHEST, P, 0.78)
		k.deform = shifted(CrewMeshKit.shell(0.24, 0.0, 0.85, 0.025), Vector3(s * 0.07, 0, 0))
		k.skip_back = true
		k.rounded_box(Vector3(0, 1.228, 0.106), Vector3(0.12, 0.05, 0.03), 0.012, Basis.IDENTITY, 1)
		k.set_part(CHEST, A)
		k.deform = shifted(CrewMeshKit.shell(0.3, 0.0), Vector3(s * 0.1, 0, 0))
		k.rounded_box(Vector3(0, 1.262, 0.142), Vector3(0.1, 0.006, 0.006), 0.0, Basis.IDENTITY, 1)
		# Shoulder yoke (trapezius armour), sloping out under the pauldrons.
		k.set_part(CHEST, S, 1.2)
		k.deform = Callable()
		k.rounded_box(Vector3(s * 0.125, 1.462, -0.02), Vector3(0.14, 0.04, 0.19), 0.016, Basis(Vector3.BACK, s * -0.32), 1)
	# Chest rig with status light.
	k.set_part(CHEST, S, 1.25)
	k.deform = CrewMeshKit.shell(0.3, 0.0, 0.85, 0.08)
	k.skip_back = true
	k.rounded_box(Vector3(0, 1.315, 0.138), Vector3(0.07, 0.17, 0.036), 0.012, Basis.IDENTITY, 1)
	k.deform = Callable()
	k.set_part(CHEST, M)
	k.ring(Vector3(0, 1.345, 0.157), 0.022, 0.0045, Basis(Vector3.RIGHT, PI * 0.5), 14, 4)
	k.set_part(CHEST, ST)
	k.disc(Vector3(0, 1.345, 0.155), Vector3.BACK, 0.019, 14, 0.006)
	k.set_part(CHEST, A)
	for i in 3:
		k.rounded_box(Vector3(0, 1.298 - i * 0.016, 0.157), Vector3(0.036 - i * 0.008, 0.006, 0.004), 0.0, Basis.IDENTITY, 1)
	# Name plate on the left rib plate (follows the plate's wrap).
	_decal(k, CHEST, Vector3(0.075, 1.228, 0.0), Vector3.RIGHT, Vector3.UP, Vector2(0.075, 0.026), DECAL_NAMEPLATE, 4,
		func(p: Vector3) -> Vector3:
			var a := p.x / 0.24
			return Vector3(sin(a) * 0.2566, p.y, 0.106 + cos(a) * 0.2566 - 0.24))
	# Collar ring: the soft seal the helmet sits in.
	k.set_part(CHEST, S, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.108, 1.44), Vector2(0.132, 1.452), Vector2(0.144, 1.47), Vector2(0.14, 1.492), Vector2(0.126, 1.503), Vector2(0.11, 1.506)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 20, Vector2(1.05, 0.98), 0.0, TAU, PackedFloat32Array([0, 0.6, 1, 0.6, 0.3, 0]))
	k.set_part(CHEST, M)
	k.lathe(PackedVector2Array([Vector2(0.1, 1.5), Vector2(0.113, 1.503), Vector2(0.115, 1.512), Vector2(0.104, 1.518)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 20, Vector2(1.05, 0.98))
	# Neck seal bellows.
	var np := PackedVector2Array()
	for i in 7:
		var y2 := lerpf(1.45, 1.575, float(i) / 6.0)
		np.append(Vector2(0.078 + 0.006 * cos(float(i) * PI), y2))
	k.set_part(NECK, F, 0.7)
	k.set_blend(HEAD, Vector3(0, 1.54, 0), Vector3.UP, 0.025)
	k.lathe(np, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.008)), 12)


static func _backpack(k: CrewMeshKit, variant: int) -> void:
	for s in [1.0, -1.0]:
		# Hoses from the pack over the yoke into the chest rig.
		k.set_part(CHEST, S, 1.6)
		k.set_blend(PACK, Vector3(0, 1.45, -0.13), Vector3.FORWARD, 0.03)
		k.tube(PackedVector3Array([Vector3(s * 0.1, 1.46, -0.17), Vector3(s * 0.165, 1.5, -0.075), Vector3(s * 0.17, 1.485, 0.04), Vector3(s * 0.11, 1.42, 0.13), Vector3(s * 0.03, 1.38, 0.152)]),
			0.015, 6, 12, 55.0, 0.22)
		# Short sagging air hoses from the pack top into the helmet seal.
		k.set_part(PACK, T, 0.75)
		k.set_blend(HEAD, Vector3(0, 1.52, 0), Vector3.UP, 0.02)
		k.tube(PackedVector3Array([Vector3(s * 0.075, 1.47, -0.2), Vector3(s * 0.12, 1.465, -0.175), Vector3(s * 0.135, 1.5, -0.14), Vector3(s * 0.108, 1.548, -0.118)]),
			0.011, 6, 8, 70.0, 0.25)
		k.clear_blend()
	match variant:
		0:
			_pack_classic(k)
		1:
			_pack_tanks(k)
		2:
			_pack_dome(k)
		3:
			_pack_thrusters(k)


static func _back_decals(k: CrewMeshKit, number_at: Vector3, number_size: Vector2, gauge_at: Vector3, gauge_w: float, hazard_at: Vector3, hazard_w: float, surface := Callable()) -> void:
	# Seen from behind, +U must run toward the viewer's right, which is world -X.
	_decal(k, PACK, number_at, Vector3.LEFT, Vector3.UP, number_size, DECAL_GLOW, 5 if surface.is_valid() else 2, surface, 3 if surface.is_valid() else 1)
	k.set_part(PACK, G)
	k.patch(func(u: float, v: float) -> Vector3:
			var p := gauge_at + Vector3(-(u - 0.5) * gauge_w, (v - 0.5) * 0.013, 0.0)
			return surface.call(p) if surface.is_valid() else p,
		5 if surface.is_valid() else 3, 1, gauge_at + Vector3(0, 0, 0.2), Vector2.ONE, func(u: float, v: float) -> Vector2: return Vector2(u, v))
	_decal(k, PACK, hazard_at, Vector3.LEFT, Vector3.UP, Vector2(hazard_w, 0.022), DECAL_HAZARD, 5 if surface.is_valid() else 2, surface)


## Boxy life-support unit with a slatted, glowing vent.
static func _pack_classic(k: CrewMeshKit) -> void:
	k.set_part(PACK, S, 1.0)
	k.deform = CrewMeshKit.taper(1.0, 0.92, 0.2)
	k.rounded_box(Vector3(0, 1.275, -0.2), Vector3(0.3, 0.4, 0.15), 0.04, Basis.IDENTITY, 2, Vector3i(1, 2, 1))
	k.deform = Callable()
	for s in [1.0, -1.0]:
		k.set_part(PACK, P, 1.0)
		k.rounded_box(Vector3(s * 0.146, 1.27, -0.208), Vector3(0.042, 0.37, 0.134), 0.018, Basis.IDENTITY, 1)
		k.set_part(PACK, A)
		k.rounded_box(Vector3(s * 0.169, 1.27, -0.208), Vector3(0.006, 0.28, 0.012), 0.0, Basis.IDENTITY, 1)
		k.rounded_box(Vector3(s * 0.112, 1.27, -0.277), Vector3(0.012, 0.26, 0.008), 0.0, Basis.IDENTITY, 1)
		_nozzle(k, Vector3(s * 0.085, 1.03, -0.205))
	k.set_part(PACK, P, 0.9)
	k.rounded_box(Vector3(0, 1.478, -0.205), Vector3(0.23, 0.038, 0.115), 0.016, Basis.IDENTITY, 1)
	k.set_part(PACK, P, 1.05)
	k.rounded_box(Vector3(0, 1.4, -0.272), Vector3(0.2, 0.1, 0.016), 0.007, Basis.IDENTITY, 1)
	k.set_part(PACK, V)
	k.rounded_box(Vector3(0, 1.215, -0.27), Vector3(0.17, 0.14, 0.008), 0.0, Basis.IDENTITY, 1)
	k.set_part(PACK, S, 1.4)
	for i in 5:
		k.rounded_box(Vector3(0, 1.16 + i * 0.027, -0.279), Vector3(0.19, 0.011, 0.016), 0.0, Basis(Vector3.RIGHT, 0.5), 1)
	k.set_part(PACK, S, 1.3)
	k.rounded_box(Vector3(0, 1.098, -0.262), Vector3(0.21, 0.03, 0.03), 0.012, Basis.IDENTITY, 1)
	_back_decals(k, Vector3(0, 1.4, -0.2815), Vector2(0.15, 0.085), Vector3(0, 1.322, -0.2765), 0.15, Vector3(0, 1.098, -0.2785), 0.19)


## Twin pill-shaped oxygen tanks in the suit colour around a glowing core.
static func _pack_tanks(k: CrewMeshKit) -> void:
	k.set_part(PACK, S, 1.0)
	k.rounded_box(Vector3(0, 1.28, -0.195), Vector3(0.2, 0.36, 0.13), 0.04, Basis.IDENTITY, 1)
	for s in [1.0, -1.0]:
		k.set_part(PACK, P, 1.0)
		k.capsule(Vector3(s * 0.112, 1.1, -0.22), Vector3(s * 0.112, 1.44, -0.22), 0.064, 0.064, 14, 3, 2)
		k.set_part(PACK, M)
		k.ring(Vector3(s * 0.112, 1.17, -0.22), 0.065, 0.006, Basis.IDENTITY, 14, 4)
		k.set_part(PACK, A)
		k.ring(Vector3(s * 0.112, 1.37, -0.22), 0.065, 0.005, Basis.IDENTITY, 14, 4)
		_nozzle(k, Vector3(s * 0.112, 1.04, -0.22))
	k.set_part(PACK, V)
	k.rounded_box(Vector3(0, 1.205, -0.261), Vector3(0.09, 0.15, 0.008), 0.0, Basis.IDENTITY, 1)
	k.set_part(PACK, S, 1.4)
	for i in 5:
		k.rounded_box(Vector3(0, 1.15 + i * 0.028, -0.268), Vector3(0.1, 0.012, 0.016), 0.0, Basis(Vector3.RIGHT, 0.5), 1)
	k.set_part(PACK, P, 0.9)
	k.rounded_box(Vector3(0, 1.47, -0.2), Vector3(0.16, 0.034, 0.1), 0.015, Basis.IDENTITY, 1)
	_back_decals(k, Vector3(0, 1.36, -0.2615), Vector2(0.09, 0.09), Vector3(0, 1.47, -0.2515), 0.12, Vector3(0, 1.118, -0.2615), 0.14)


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
	k.rounded_box(Vector3(0, 1.36, -0.262), Vector3(0.28, 0.16, 0.018), 0.008, Basis.IDENTITY, 1)
	k.set_part(PACK, V)
	k.rounded_box(Vector3(0, 1.227, -0.262), Vector3(0.16, 0.012, 0.008), 0.0, Basis.IDENTITY, 1)
	for s in [1.0, -1.0]:
		k.set_part(PACK, P, 0.92)
		k.capsule(Vector3(s * 0.13, 1.06, -0.215), Vector3(s * 0.13, 1.21, -0.215), 0.05, 0.05, 14, 3, 1)
		k.set_part(PACK, A)
		k.ring(Vector3(s * 0.13, 1.15, -0.215), 0.051, 0.005, Basis.IDENTITY, 14, 4)
		_nozzle(k, Vector3(s * 0.13, 1.0, -0.215))
		k.set_part(PACK, A)
		k.rounded_box(Vector3(s * 0.165, 1.36, -0.205), Vector3(0.006, 0.2, 0.012), 0.0, Basis.IDENTITY, 1)
	_back_decals(k, Vector3(0, 1.37, -0.2725), Vector2(0.12, 0.09), Vector3(0, 1.255, -0.2615), 0.18, Vector3(0, 1.195, -0.2615), 0.14)


static func _nozzle(k: CrewMeshKit, at: Vector3) -> void:
	k.set_part(PACK, M)
	k.lathe(PackedVector2Array([Vector2(0.026, 0.0), Vector2(0.032, 0.01), Vector2(0.028, 0.045), Vector2(0.02, 0.055)]),
		Transform3D(Basis.IDENTITY, at), 12)
	k.set_part(PACK, V)
	k.disc(at + Vector3(0, 0.006, 0), Vector3.DOWN, 0.024, 10, 0.0)


static func _head(k: CrewMeshKit, variant: int) -> void:
	var top := HELMET_C + HELMET_RY
	k.set_part(HEAD, P, 1.0)
	k.lathe(helmet_profile(), Transform3D(Basis.IDENTITY, Vector3(0, 0, HELMET_Z)), 24, Vector2(1.0, HELMET_DEPTH))
	# Graphite jaw ring (panel seam between shell and collar seal).
	var jaw := PackedVector2Array()
	var jaw_y: Array[float] = [HELMET_BASE - 0.006, HELMET_BASE, 1.54, 1.562, 1.572]
	for i in jaw_y.size():
		var y := jaw_y[i]
		var inset := -0.008 if i == 0 else (-0.004 if i == jaw_y.size() - 1 else 0.0)
		jaw.append(Vector2(helmet_radius(maxf(y, HELMET_BASE)) * 1.035 + inset, y))
	k.set_part(HEAD, S, 1.1)
	k.lathe(jaw, Transform3D(Basis.IDENTITY, Vector3(0, 0, HELMET_Z)), 24, Vector2(1.0, HELMET_DEPTH), 0.0, TAU, PackedFloat32Array([0, 1, 0, 1, 0]))
	# Visor frame.
	k.set_part(HEAD, S, 1.3)
	k.tube(_visor_outline(0.006), 0.0072, 6, 26, 0.0, 0.0, true)
	for s in [1.0, -1.0]:
		# Ear pucks: graphite, emissive ring, metal cap.
		var c := Vector3(s * 0.168, HELMET_C, -0.012)
		k.set_part(HEAD, S, 1.15)
		k.cylinder(c, c + Vector3(s * 0.032, 0, 0), 0.054, 14, 0.012)
		k.set_part(HEAD, A)
		k.ring(c + Vector3(s * 0.033, 0, 0), 0.039, 0.0048, Basis(Vector3.BACK, -s * PI * 0.5), 14, 4)
		k.set_part(HEAD, M)
		k.disc(c + Vector3(s * 0.032, 0, 0), Vector3(s, 0, 0), 0.024, 10, 0.009)
		# Small side lamps above the ears.
		k.set_part(HEAD, S, 1.3)
		k.cylinder(Vector3(s * 0.158, 1.738, 0.022), Vector3(s * 0.158, 1.738, 0.088), 0.016, 8, 0.006)
		k.set_part(HEAD, L)
		k.disc(Vector3(s * 0.158, 1.738, 0.0885), Vector3.BACK, 0.0115, 8, 0.004)
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
			k.deform = shifted(CrewMeshKit.arc_z(0.18), Vector3(0, 0, -0.025))
			k.rounded_box(Vector3(0, top, HELMET_Z), Vector3(0.052, 0.026, 0.31), 0.012, Basis.IDENTITY, 1, Vector3i(1, 1, 6))
			k.set_part(HEAD, A)
			k.deform = shifted(CrewMeshKit.arc_z(0.18), Vector3(0, 0.013, -0.025))
			k.rounded_box(Vector3(0, top, HELMET_Z), Vector3(0.015, 0.008, 0.28), 0.0, Basis.IDENTITY, 1, Vector3i(1, 1, 8))
			k.deform = Callable()
			_antenna(k, Vector3(0.18, 1.7, -0.05), Vector3(0.2, 1.865, -0.12))
		1:
			# Dorsal fin in the suit colour with a glowing leading edge.
			k.set_part(HEAD, P, 1.0)
			k.deform = shifted(CrewMeshKit.arc_z(0.2), Vector3(0, 0, -0.04))
			k.rounded_box(Vector3(0, top + 0.012, HELMET_Z), Vector3(0.026, 0.075, 0.24), 0.012, Basis.IDENTITY, 1, Vector3i(1, 1, 6))
			k.set_part(HEAD, A)
			k.deform = shifted(CrewMeshKit.arc_z(0.2), Vector3(0, 0.039, -0.04))
			k.rounded_box(Vector3(0, top + 0.012, HELMET_Z), Vector3(0.012, 0.008, 0.22), 0.0, Basis.IDENTITY, 1, Vector3i(1, 1, 6))
			k.deform = Callable()
		2:
			# Twin antennae rising from the ear pucks.
			for s2 in [1.0, -1.0]:
				_antenna(k, Vector3(s2 * 0.19, 1.69, -0.035), Vector3(s2 * 0.215, 1.84, -0.07))
			k.set_part(HEAD, S, 1.2)
			k.ellipsoid(Vector3(0, top - 0.004, HELMET_Z - 0.02), Vector3(0.03, 0.014, 0.05), Basis.IDENTITY, 10, 4)
		3:
			# Halo crown band + stubby rear beacon.
			var hy := 1.772
			k.set_part(HEAD, A)
			k.ring(Vector3(0, hy, HELMET_Z), helmet_radius(hy) + 0.002, 0.0055, Basis.IDENTITY, 26, 4, Vector2(1.0, HELMET_DEPTH))
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
	k.set_part(ANTENNA, BL)
	k.ellipsoid(b, Vector3(0.012, 0.012, 0.012), Basis.IDENTITY, 8, 4)


static func _visor_point(u: float, v: float, lift: float) -> Vector3:
	var tv := 2.0 * v - 1.0
	var half := VISOR_HALF_ANGLE * pow(maxf(1.0 - pow(absf(tv), 4.0), 0.0), 0.25) * (0.8 + 0.2 * v)
	var a := (2.0 * u - 1.0) * half
	var y := lerpf(VISOR_Y.x, VISOR_Y.y, v)
	var bulge := 0.009 * (1.0 - tv * tv) * (1.0 - pow(2.0 * u - 1.0, 2.0))
	var r := helmet_radius(y) + lift + bulge
	return Vector3(sin(a) * r, y, cos(a) * r * HELMET_DEPTH + HELMET_Z)


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
		18, 10, Vector3(0, HELMET_C, HELMET_Z) - head, Vector2.ONE,
		func(u: float, v: float) -> Vector2:
			var p := _visor_point(u, v, 0.004)
			return Vector2(atan2(p.x, (p.z - HELMET_Z) / HELMET_DEPTH) * HELMET_RX, p.y - mid))


## Armour plate wrapped around a limb axis: `theta` = angle around the limb (0 = front, +PI/2 = +X).
static func _plate(k: CrewMeshKit, axis: Vector3, radius: float, theta: float, size: Vector3, corner: float, curve := 0.0, taper_bottom := 1.0, segs := Vector3i(1, 1, 1)) -> void:
	var dir := Vector3(sin(theta), 0.0, cos(theta))
	k.deform = CrewMeshKit.shell(radius + size.z * 0.5, curve, taper_bottom, size.y * 0.5)
	k.skip_back = true
	k.rounded_box(axis + dir * (radius + size.z * 0.5), size, corner, Basis(Vector3.UP, theta), 1, segs)
	k.deform = Callable()
	k.skip_back = false


static func _arm(k: CrewMeshKit, s: float) -> void:
	var up := L_ARM if s > 0.0 else R_ARM
	var fore := L_FORE if s > 0.0 else R_FORE
	var hand := L_HAND if s > 0.0 else R_HAND
	var fingers := L_FINGERS if s > 0.0 else R_FINGERS
	var thumb := L_THUMB if s > 0.0 else R_THUMB
	var x := JOINTS[up].x
	var z0 := JOINTS[up].z
	var out := Vector3(s, 0, 0)
	# Shoulder bearing ball: fills the socket whatever the arm angle.
	k.set_part(up, F, 0.7)
	k.ellipsoid(Vector3(x - s * 0.008, 1.425, z0), Vector3(0.074, 0.07, 0.078), Basis.IDENTITY, 10, 5)
	# Upper arm: wide at the shoulder, tapering to the elbow.
	k.set_part(up, F, 0.85)
	_limb(k, Vector3(x, 1.17, z0), Vector3(x, 1.42, z0), [0.053, 0.058, 0.064, 0.067] as Array[float], 10)
	k.set_part(up, P, 0.95)
	_plate(k, Vector3(x, 1.28, z0), 0.064, s * PI * 0.5, Vector3(0.12, 0.13, 0.026), 0.011, 0.0, 0.85)
	k.set_part(up, A)
	_plate(k, Vector3(x, 1.212, z0), 0.068, s * PI * 0.5, Vector3(0.06, 0.006, 0.004), 0.0)
	# Pauldron: graphite under-layer + domed cap overlapping the upper arm, emissive rim.
	var pad_dir := Vector3(s * 0.5, 0.866, 0.0)
	var pad_basis := Basis(pad_dir.cross(Vector3.BACK).normalized(), pad_dir, Vector3.BACK)
	var pad_c := Vector3(x + s * 0.03, 1.448, z0)
	k.set_part(up, S, 1.15)
	k.lathe(PackedVector2Array([Vector2(0.09, -0.05), Vector2(0.106, -0.044), Vector2(0.11, -0.022), Vector2(0.1, 0.0), Vector2(0.084, 0.012)]),
		Transform3D(pad_basis, pad_c), 14, Vector2(1.0, 1.08), 0.0, TAU, PackedFloat32Array([0, 1, 0.5, 1, 0]))
	k.set_part(up, P, 1.0)
	var dome := PackedVector2Array([Vector2(0.092, -0.006), Vector2(0.1, 0.006), Vector2(0.095, 0.034), Vector2(0.076, 0.062), Vector2(0.042, 0.078), Vector2(0.0, 0.083)])
	k.lathe(dome, Transform3D(pad_basis, pad_c), 14, Vector2(1.0, 1.08), 0.0, TAU, PackedFloat32Array([0, 1, 0, 0, 0, 0]))
	k.set_part(up, A)
	k.ring(pad_c + pad_dir * 0.012, 0.1, 0.0035, pad_basis, 14, 4, Vector2(1.0, 1.08))
	# Player number on the outer face of the pauldron, following the dome.
	var out_h := Vector3(s * 0.866, -0.5, 0.0)
	var side := Vector3(0, 0, -s)
	k.set_part(up, DC)
	k.patch(func(u: float, v: float) -> Vector3:
			var yy := lerpf(0.004, 0.05, v)
			var rr := _profile_r(dome, yy) + 0.0016
			var al := (u - 0.5) * 0.85
			return pad_c + pad_dir * yy + out_h * cos(al) * rr + side * sin(al) * rr * 1.08,
		4, 2, pad_c, Vector2.ONE, Callable(), Vector2(DECAL_PAINT, 1.6))
	# Elbow: bellows sleeve across the joint, hinge cap with bolt, graphite cop.
	_barrel(k, fore, Vector3(x, 1.13, z0), 0.046, 0.06, 2, 10)
	_hinge(k, fore, Vector3(x + s * 0.062, 1.13, z0), out, 0.03)
	k.set_part(fore, S, 1.2)
	_plate(k, Vector3(x, 1.14, z0), 0.052, PI, Vector3(0.08, 0.075, 0.024), 0.011, 0.06)
	# Forearm and flared gauntlet.
	k.set_part(fore, F, 0.85)
	_limb(k, Vector3(x, 0.89, z0), Vector3(x, 1.1, z0), [0.042, 0.047, 0.052, 0.05] as Array[float], 10)
	k.set_part(fore, P, 1.0)
	k.deform = CrewMeshKit.taper(0.84, 1.0, 0.085, 0.86, 1.0)
	k.rounded_box(Vector3(x, 0.982, z0 + 0.003), Vector3(0.114, 0.17, 0.118), 0.032, Basis.IDENTITY, 1)
	k.deform = Callable()
	k.set_part(fore, S, 1.25)
	k.rounded_box(Vector3(x + s * 0.05, 0.995, z0 + 0.003), Vector3(0.026, 0.11, 0.075), 0.01, Basis.IDENTITY, 1)
	k.set_part(fore, A)
	k.rounded_box(Vector3(x + s * 0.0635, 0.995, z0 + 0.003), Vector3(0.004, 0.075, 0.04), 0.0, Basis.IDENTITY, 1)
	# Wrist: bellows under a flared glove cuff.
	_bellows(k, Vector3(x, 0.872, z0 + 0.004), Vector3.DOWN, 0.045, 0.047, 2, 10, fore, hand, Vector2.ONE, false)
	k.set_part(hand, P, 0.85)
	k.lathe(PackedVector2Array([Vector2(0.044, 0.83), Vector2(0.054, 0.836), Vector2(0.058, 0.858), Vector2(0.052, 0.866), Vector2(0.046, 0.864)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, z0 + 0.006)), 12, Vector2(0.92, 1.1), 0.0, TAU, PackedFloat32Array([0, 1, 0, 1, 0]))
	# Chunky glove: palm block, back-of-hand plate, three fingers and a thumb that curl.
	k.set_part(hand, S, 1.05)
	k.rounded_box(Vector3(x - s * 0.004, 0.808, z0 + 0.009), Vector3(0.056, 0.07, 0.098), 0.022, Basis.IDENTITY, 1)
	k.set_part(hand, P, 0.85)
	k.rounded_box(Vector3(x + s * 0.024, 0.81, z0 + 0.009), Vector3(0.012, 0.055, 0.078), 0.005, Basis.IDENTITY, 1)
	for i in 3:
		var zf := z0 + 0.009 + (float(i) - 1.0) * 0.031
		k.set_part(hand, R, 1.0)
		k.set_blend(fingers, Vector3(x, 0.772, zf), Vector3.DOWN, 0.014)
		k.capsule(Vector3(x - s * 0.006, 0.786, zf), Vector3(x - s * 0.01, 0.722, zf + 0.003), 0.0165, 0.0155, 6, 2, 2)
	k.set_part(hand, R, 1.0)
	var tb := Vector3(x - s * 0.014, 0.835, z0 + 0.05)
	var tt := Vector3(x - s * 0.03, 0.79, z0 + 0.078)
	k.set_blend(thumb, tb + (tt - tb) * 0.3, (tt - tb).normalized(), 0.012)
	k.capsule(tb, tt, 0.016, 0.015, 6, 2, 1)
	k.clear_blend()


static func _profile_r(prof: PackedVector2Array, y: float) -> float:
	for i in range(1, prof.size()):
		if y <= prof[i].y:
			var t := clampf((y - prof[i - 1].y) / maxf(prof[i].y - prof[i - 1].y, 1e-5), 0.0, 1.0)
			return lerpf(prof[i - 1].x, prof[i].x, t)
	return prof[prof.size() - 1].x


static func _leg(k: CrewMeshKit, s: float) -> void:
	var thigh := L_LEG if s > 0.0 else R_LEG
	var shin := L_SHIN if s > 0.0 else R_SHIN
	var foot := L_FOOT if s > 0.0 else R_FOOT
	var x := JOINTS[thigh].x
	var out := Vector3(s, 0, 0)
	# Thigh: muscle-like taper, skinned into the hips at the top.
	k.set_part(thigh, F, 0.85)
	k.set_blend(HIPS, Vector3(x, 0.9, 0), Vector3.UP, 0.05)
	_limb(k, Vector3(x, 0.545, 0.0), Vector3(x, 0.97, -0.005), [0.07, 0.08, 0.09, 0.096, 0.097] as Array[float], 10)
	k.clear_blend()
	k.set_part(thigh, P, 1.0)
	_plate(k, Vector3(x, 0.75, 0.0), 0.09, s * 0.3, Vector3(0.16, 0.27, 0.028), 0.012, 0.7, 0.78)
	k.set_part(thigh, S, 1.15)
	_plate(k, Vector3(x, 0.8, -0.005), 0.09, s * PI * 0.5, Vector3(0.1, 0.11, 0.04), 0.015)
	k.set_part(thigh, A)
	_plate(k, Vector3(x, 0.82, -0.005), 0.13, s * PI * 0.5, Vector3(0.05, 0.006, 0.004), 0.0)
	# Knee: bellows sleeve, hinge caps with bolts, domed knee guard on the shin.
	_barrel(k, shin, Vector3(x, 0.505, -0.004), 0.058, 0.077, 2, 12)
	_hinge(k, shin, Vector3(x + s * 0.079, 0.505, -0.004), out, 0.036)
	_hinge(k, shin, Vector3(x - s * 0.079, 0.505, -0.004), -out, 0.032)
	k.set_part(shin, P, 0.82)
	_plate(k, Vector3(x, 0.512, -0.005), 0.082, 0.0, Vector3(0.118, 0.125, 0.032), 0.015, 0.09)
	# Shin with a calf bulge, shin guard and accent.
	k.set_part(shin, F, 0.85)
	_limb(k, Vector3(x, 0.15, -0.01), Vector3(x, 0.49, -0.005), [0.062, 0.066, 0.072, 0.074, 0.068] as Array[float], 10, Vector2(1.0, 1.08))
	k.set_part(shin, P, 1.0)
	_plate(k, Vector3(x, 0.335, -0.005), 0.074, 0.0, Vector3(0.12, 0.22, 0.028), 0.012, 0.0, 0.82, Vector3i(1, 2, 1))
	k.set_part(shin, A)
	_plate(k, Vector3(x, 0.335, -0.005), 0.102, 0.0, Vector3(0.006, 0.15, 0.004), 0.0)
	# Chunky boot cuff.
	k.set_part(shin, S, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.062, 0.12), Vector2(0.071, 0.13), Vector2(0.074, 0.2), Vector2(0.076, 0.228), Vector2(0.066, 0.238)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.008)), 14, Vector2(1.0, 1.15), 0.0, TAU, PackedFloat32Array([0, 1, 0, 1, 0]))
	k.set_part(shin, M)
	k.lathe(PackedVector2Array([Vector2(0.074, 0.226), Vector2(0.08, 0.23), Vector2(0.08, 0.242), Vector2(0.072, 0.246)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.008)), 14, Vector2(1.0, 1.15))
	# Ankle: bellows into the boot, hinge bracket with bolt.
	_bellows(k, Vector3(x, 0.115, -0.008), Vector3.DOWN, 0.05, 0.066, 2, 12, shin, foot, Vector2(1.0, 1.12), false)
	k.set_part(foot, S, 1.2)
	k.rounded_box(Vector3(x + s * 0.064, 0.09, -0.012), Vector3(0.018, 0.07, 0.064), 0.008, Basis.IDENTITY, 1)
	k.set_part(foot, M)
	k.disc(Vector3(x + s * 0.073, 0.092, -0.012), out, 0.014, 6, 0.004)
	# Boot: shell, toe cap, thick sole with treads and a magnetic glow ring.
	k.set_part(foot, S, 1.0)
	k.deform = CrewMeshKit.taper(1.0, 0.86, 0.045)
	k.rounded_box(Vector3(x, 0.072, 0.04), Vector3(0.124, 0.095, 0.28), 0.038, Basis.IDENTITY, 1, Vector3i(1, 1, 2))
	k.deform = Callable()
	k.set_part(foot, P, 0.95)
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
		k.add_occluder(Vector3(s * 0.222, 1.3, -0.015), 0.055)
		k.add_occluder(Vector3(s * 0.222, 0.99, -0.012), 0.05)
		k.add_occluder(Vector3(s * 0.25, 1.47, -0.015), 0.06)
		k.add_occluder(Vector3(s * 0.1, 0.78, 0), 0.08)
		k.add_occluder(Vector3(s * 0.1, 0.62, 0), 0.07)
		k.add_occluder(Vector3(s * 0.1, 0.33, 0), 0.055)
		k.add_occluder(Vector3(s * 0.1, 0.06, 0.05), 0.055)
