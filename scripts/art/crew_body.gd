class_name CrewBody
extends RefCounted
## Rig layout and procedural geometry of the crew EVA suit.
## Bind pose: origin at the feet, facing +Z, character's left = +X, arms straight down.

enum { HIPS, SPINE, CHEST, NECK, HEAD, L_ARM, L_FORE, L_HAND, R_ARM, R_FORE, R_HAND, L_LEG, L_SHIN, L_FOOT, R_LEG, R_SHIN, R_FOOT }

const BONE_NAMES: Array[String] = ["Hips", "Spine", "Chest", "Neck", "Head",
	"LeftArm", "LeftForearm", "LeftHand", "RightArm", "RightForearm", "RightHand",
	"LeftLeg", "LeftShin", "LeftFoot", "RightLeg", "RightShin", "RightFoot"]
const PARENTS: Array[int] = [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]
const JOINTS: Array[Vector3] = [
	Vector3(0, 0.97, 0), Vector3(0, 1.07, 0), Vector3(0, 1.21, -0.01), Vector3(0, 1.47, -0.012), Vector3(0, 1.555, -0.005),
	Vector3(0.212, 1.425, -0.015), Vector3(0.212, 1.13, -0.015), Vector3(0.212, 0.86, -0.015),
	Vector3(-0.212, 1.425, -0.015), Vector3(-0.212, 1.13, -0.015), Vector3(-0.212, 0.86, -0.015),
	Vector3(0.098, 0.93, 0), Vector3(0.098, 0.505, 0), Vector3(0.098, 0.09, 0),
	Vector3(-0.098, 0.93, 0), Vector3(-0.098, 0.505, 0), Vector3(-0.098, 0.09, 0),
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

const HELMET_PROFILE: Array[Vector2] = [
	Vector2(0.094, 1.528), Vector2(0.116, 1.538), Vector2(0.134, 1.556), Vector2(0.148, 1.584),
	Vector2(0.157, 1.618), Vector2(0.161, 1.655), Vector2(0.159, 1.692), Vector2(0.151, 1.726),
	Vector2(0.137, 1.755), Vector2(0.115, 1.779), Vector2(0.085, 1.796), Vector2(0.046, 1.805), Vector2(0.0, 1.808)]
const HELMET_Z := -0.006
const HELMET_DEPTH := 1.1
const VISOR_Y := Vector2(1.585, 1.728)
const VISOR_HALF_ANGLE := 1.0

static var _cache := {}


static func body_mesh() -> ArrayMesh:
	if not _cache.has("body"):
		_build()
	return _cache["body"]


static func visor_mesh() -> ArrayMesh:
	if not _cache.has("visor"):
		_build()
	return _cache["visor"]


static func _build() -> void:
	var kit := CrewMeshKit.new()
	_hips(kit)
	_torso(kit)
	_backpack(kit)
	_head(kit)
	for s in [1.0, -1.0]:
		_arm(kit, s)
		_leg(kit, s)
	_occluders(kit)
	kit.bake_ao()
	_cache["body"] = kit.commit()
	_cache["body_tris"] = kit.triangle_count()
	var vk := CrewMeshKit.new()
	_visor(vk)
	_cache["visor"] = vk.commit()
	_cache["visor_tris"] = vk.triangle_count()


static func triangle_counts() -> Vector2i:
	body_mesh()
	return Vector2i(_cache["body_tris"], _cache["visor_tris"])


static func shifted(c: Callable, off: Vector3) -> Callable:
	return func(p: Vector3) -> Vector3: return c.call(p + off)


static func helmet_radius(y: float) -> float:
	for k in range(1, HELMET_PROFILE.size()):
		var a := HELMET_PROFILE[k - 1]
		var b := HELMET_PROFILE[k]
		if y <= b.y:
			return lerpf(a.x, b.x, clampf((y - a.y) / (b.y - a.y), 0.0, 1.0))
	return 0.0


# --- body parts ---------------------------------------------------------------------

static func _hips(k: CrewMeshKit) -> void:
	k.set_part(HIPS, F, 0.9)
	k.deform = CrewMeshKit.taper(0.86, 1.0, 0.1)
	k.rounded_box(Vector3(0, 0.935, -0.005), Vector3(0.29, 0.2, 0.21), 0.08, Basis.IDENTITY, 2)
	# Belt.
	k.set_part(HIPS, S, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.142, 0.968), Vector2(0.156, 0.974), Vector2(0.159, 0.99), Vector2(0.159, 1.012), Vector2(0.154, 1.024), Vector2(0.14, 1.03)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.004)), 24, Vector2(1.0, 0.8), 0.0, TAU, PackedFloat32Array([0, 1, 0, 0, 1, 0]))
	k.set_part(HIPS, M, 1.0)
	k.rounded_box(Vector3(0, 0.997, 0.128), Vector3(0.075, 0.052, 0.02), 0.008, Basis.IDENTITY, 1)
	k.set_part(HIPS, A)
	k.rounded_box(Vector3(0, 0.997, 0.139), Vector3(0.042, 0.008, 0.004), 0.002, Basis.IDENTITY, 1)
	# Front and rear plates.
	k.set_part(HIPS, P, 0.92)
	k.deform = shifted(CrewMeshKit.shell(0.15, 0.0, 0.55, 0.055), Vector3.ZERO)
	k.rounded_box(Vector3(0, 0.905, 0.1), Vector3(0.13, 0.11, 0.026), 0.012, Basis.IDENTITY, 2)
	k.set_part(HIPS, S, 1.1)
	k.deform = CrewMeshKit.shell(0.16, 0.0, 0.8, 0.05)
	k.rounded_box(Vector3(0, 0.93, -0.112), Vector3(0.21, 0.1, 0.026), 0.01, Basis(Vector3.UP, PI), 2)
	# Side tassets.
	for s in [1.0, -1.0]:
		k.set_part(HIPS, P, 1.0)
		k.deform = CrewMeshKit.shell(0.2, 0.0, 0.85, 0.075)
		k.rounded_box(Vector3(s * 0.158, 0.905, 0.0), Vector3(0.16, 0.15, 0.024), 0.01, Basis(Vector3.UP, s * PI * 0.5) * Basis(Vector3.RIGHT, -0.12), 2)
		k.set_part(HIPS, A)
		k.deform = CrewMeshKit.shell(0.2, 0.0, 0.85, 0.075)
		k.rounded_box(Vector3(s * 0.172, 0.94, 0.0), Vector3(0.1, 0.008, 0.004), 0.002, Basis(Vector3.UP, s * PI * 0.5) * Basis(Vector3.RIGHT, -0.12), 1)


static func _torso(k: CrewMeshKit) -> void:
	# Abdomen bellows (spine), blending into hips below.
	var prof := PackedVector2Array()
	var em := PackedFloat32Array()
	for i in 21:
		var y := lerpf(0.99, 1.25, float(i) / 20.0)
		var rr := 0.112 + 0.006 * cos(float(i) * PI * 0.5) + 0.012 * sin(clampf((y - 0.99) / 0.26, 0.0, 1.0) * PI)
		prof.append(Vector2(rr, y))
		em.append(0.0)
	k.set_part(SPINE, F, 0.8)
	k.set_blend(HIPS, Vector3(0, 1.03, 0), Vector3.DOWN, 0.04)
	k.lathe(prof, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 18, Vector2(1.0, 0.78), 0.0, TAU, em)
	# Abdominal armour bands (graphite: dark waist, bright chest -> heroic V).
	k.set_part(SPINE, S, 1.15)
	k.deform = CrewMeshKit.shell(0.13, 0.0, 0.85, 0.025)
	k.rounded_box(Vector3(0, 1.125, 0.085), Vector3(0.17, 0.05, 0.026), 0.01, Basis.IDENTITY, 2)
	k.set_part(SPINE, S, 1.0)
	k.set_blend(HIPS, Vector3(0, 1.03, 0), Vector3.DOWN, 0.04)
	k.deform = CrewMeshKit.shell(0.13, 0.0, 0.8, 0.022)
	k.rounded_box(Vector3(0, 1.07, 0.088), Vector3(0.15, 0.044, 0.024), 0.01, Basis.IDENTITY, 2)
	# Chest core.
	k.set_part(CHEST, F, 0.9)
	k.deform = CrewMeshKit.taper(0.78, 1.0, 0.15, 0.85, 1.0)
	k.rounded_box(Vector3(0, 1.325, -0.015), Vector3(0.33, 0.3, 0.22), 0.09, Basis.IDENTITY, 2, Vector3i(2, 2, 1))
	# Pectoral plates wrapping the torso.
	for s in [1.0, -1.0]:
		k.set_part(CHEST, P, 1.0)
		k.deform = shifted(CrewMeshKit.shell(0.19, 0.42, 0.82, 0.095), Vector3(s * 0.088, 0, 0))
		k.rounded_box(Vector3(0, 1.362, 0.098), Vector3(0.155, 0.19, 0.042), 0.018, Basis.IDENTITY, 2)
		k.set_part(CHEST, P, 0.78)
		k.deform = shifted(CrewMeshKit.shell(0.17, 0.0, 0.85, 0.025), Vector3(s * 0.072, 0, 0))
		k.rounded_box(Vector3(0, 1.232, 0.092), Vector3(0.12, 0.05, 0.03), 0.012, Basis.IDENTITY, 2)
		# Accent piping under the pecs.
		k.set_part(CHEST, A)
		k.deform = shifted(CrewMeshKit.shell(0.2, 0.0), Vector3(s * 0.1, 0, 0))
		k.rounded_box(Vector3(0, 1.268, 0.112), Vector3(0.09, 0.006, 0.006), 0.002, Basis.IDENTITY, 1)
		# Shoulder yoke (trapezius armour), sloping out.
		k.set_part(CHEST, S, 1.2)
		k.deform = Callable()
		k.rounded_box(Vector3(s * 0.12, 1.455, -0.02), Vector3(0.13, 0.04, 0.19), 0.016, Basis(Vector3.BACK, s * -0.32), 2)
	# Chest rig with status light.
	k.set_part(CHEST, S, 1.25)
	k.deform = CrewMeshKit.shell(0.25, 0.0, 0.85, 0.08)
	k.rounded_box(Vector3(0, 1.31, 0.122), Vector3(0.085, 0.16, 0.036), 0.012, Basis.IDENTITY, 2)
	k.set_part(CHEST, M)
	k.ring(Vector3(0, 1.335, 0.141), 0.022, 0.0045, Basis(Vector3.RIGHT, PI * 0.5), 18, 6)
	k.set_part(CHEST, ST)
	k.cylinder(Vector3(0, 1.335, 0.134), Vector3(0, 1.335, 0.143), 0.019, 16, 0.003)
	k.set_part(CHEST, A)
	for i in 3:
		k.rounded_box(Vector3(0, 1.29 - i * 0.016, 0.141), Vector3(0.04 - i * 0.008, 0.006, 0.004), 0.002, Basis.IDENTITY, 1)
	# Collar ring.
	k.set_part(CHEST, S, 1.0)
	k.deform = Callable()
	k.lathe(PackedVector2Array([Vector2(0.108, 1.44), Vector2(0.132, 1.452), Vector2(0.142, 1.47), Vector2(0.138, 1.492), Vector2(0.124, 1.503), Vector2(0.11, 1.506)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 26, Vector2(1.05, 0.98), 0.0, TAU, PackedFloat32Array([0, 0.6, 1, 0.6, 0.3, 0]))
	k.set_part(CHEST, M)
	k.lathe(PackedVector2Array([Vector2(0.1, 1.5), Vector2(0.112, 1.503), Vector2(0.114, 1.512), Vector2(0.104, 1.518)]),
		Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.012)), 26, Vector2(1.05, 0.98))
	# Neck seal bellows.
	var np := PackedVector2Array()
	for i in 9:
		var y2 := lerpf(1.45, 1.575, float(i) / 8.0)
		np.append(Vector2(0.074 + 0.005 * cos(float(i) * PI * 0.5), y2))
	k.set_part(NECK, F, 0.7)
	k.set_blend(HEAD, Vector3(0, 1.54, 0), Vector3.UP, 0.025)
	k.lathe(np, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.008)), 14)


static func _backpack(k: CrewMeshKit) -> void:
	k.set_part(CHEST, S, 1.0)
	k.deform = CrewMeshKit.taper(1.0, 0.92, 0.2)
	k.rounded_box(Vector3(0, 1.275, -0.205), Vector3(0.3, 0.4, 0.14), 0.038, Basis.IDENTITY, 2, Vector3i(1, 2, 1))
	k.deform = Callable()
	for s in [1.0, -1.0]:
		k.set_part(CHEST, P, 1.0)
		k.rounded_box(Vector3(s * 0.146, 1.27, -0.208), Vector3(0.04, 0.37, 0.132), 0.016, Basis.IDENTITY, 2)
		k.set_part(CHEST, A)
		k.rounded_box(Vector3(s * 0.168, 1.27, -0.208), Vector3(0.006, 0.28, 0.012), 0.002, Basis.IDENTITY, 1)
		k.rounded_box(Vector3(s * 0.112, 1.29, -0.277), Vector3(0.012, 0.3, 0.008), 0.003, Basis.IDENTITY, 1)
		# Thruster nozzles under the pack.
		k.set_part(CHEST, M)
		k.lathe(PackedVector2Array([Vector2(0.026, 1.03), Vector2(0.032, 1.04), Vector2(0.028, 1.075), Vector2(0.02, 1.085)]),
			Transform3D(Basis.IDENTITY, Vector3(s * 0.085, 0, -0.205)), 14)
		k.set_part(CHEST, A)
		k.cylinder(Vector3(s * 0.085, 1.034, -0.205), Vector3(s * 0.085, 1.036, -0.205), 0.022, 12, 0.001)
		# Hoses from pack over the yoke into the chest rig.
		k.set_part(CHEST, S, 1.6)
		k.tube(PackedVector3Array([Vector3(s * 0.09, 1.46, -0.17), Vector3(s * 0.15, 1.51, -0.08), Vector3(s * 0.155, 1.49, 0.04), Vector3(s * 0.1, 1.42, 0.11), Vector3(s * 0.04, 1.37, 0.14)]),
			0.015, 8, 22, 55.0, 0.22)
	# Top cap and upper back plate.
	k.set_part(CHEST, P, 0.9)
	k.rounded_box(Vector3(0, 1.478, -0.205), Vector3(0.23, 0.036, 0.115), 0.014, Basis.IDENTITY, 2)
	k.set_part(CHEST, P, 1.05)
	k.rounded_box(Vector3(0, 1.395, -0.272), Vector3(0.2, 0.09, 0.014), 0.006, Basis.IDENTITY, 2)
	# Glowing vent: emissive panel behind graphite slats.
	k.set_part(CHEST, A)
	k.rounded_box(Vector3(0, 1.22, -0.27), Vector3(0.17, 0.15, 0.008), 0.003, Basis.IDENTITY, 1)
	k.set_part(CHEST, S, 1.4)
	for i in 6:
		k.rounded_box(Vector3(0, 1.157 + i * 0.026, -0.279), Vector3(0.19, 0.011, 0.016), 0.004, Basis(Vector3.RIGHT, 0.5), 1)
	k.set_part(CHEST, S, 1.3)
	k.rounded_box(Vector3(0, 1.098, -0.262), Vector3(0.21, 0.03, 0.03), 0.01, Basis.IDENTITY, 1)


static func _head(k: CrewMeshKit) -> void:
	var prof := PackedVector2Array(HELMET_PROFILE)
	var em := PackedFloat32Array()
	for i in prof.size():
		em.append(0.0)
	k.set_part(HEAD, P, 1.0)
	k.lathe(prof, Transform3D(Basis.IDENTITY, Vector3(0, 0, HELMET_Z)), 30, Vector2(1.0, HELMET_DEPTH), 0.0, TAU, em)
	# Graphite jaw ring with a ledge.
	var jaw := PackedVector2Array()
	var jaw_y: Array[float] = [1.524, 1.532, 1.55, 1.57, 1.588, 1.598]
	for i in jaw_y.size():
		var y := jaw_y[i]
		var inset := -0.006 if i == 0 else (-0.004 if i == jaw_y.size() - 1 else 0.0)
		jaw.append(Vector2(helmet_radius(y) * 1.035 + inset, y))
	k.set_part(HEAD, S, 1.1)
	k.lathe(jaw, Transform3D(Basis.IDENTITY, Vector3(0, 0, HELMET_Z)), 30, Vector2(1.0, HELMET_DEPTH), 0.0, TAU, PackedFloat32Array([0, 1, 0, 0, 1, 0]))
	# Visor frame.
	k.set_part(HEAD, S, 1.3)
	k.tube(_visor_outline(0.006), 0.0075, 8, 64)
	# Crest along the top with an accent inlay.
	var crest := shifted(CrewMeshKit.arc_z(0.17), Vector3(0, 0, -0.025))
	k.set_part(HEAD, S, 1.2)
	k.deform = crest
	k.rounded_box(Vector3(0, 1.808, HELMET_Z), Vector3(0.05, 0.024, 0.3), 0.01, Basis.IDENTITY, 2, Vector3i(1, 1, 10))
	k.set_part(HEAD, A)
	k.deform = shifted(CrewMeshKit.arc_z(0.17), Vector3(0, 0.012, -0.025))
	k.rounded_box(Vector3(0, 1.808, HELMET_Z), Vector3(0.014, 0.008, 0.27), 0.003, Basis.IDENTITY, 1, Vector3i(1, 1, 10))
	k.deform = Callable()
	for s in [1.0, -1.0]:
		var c := Vector3(s * 0.15, 1.648, -0.012)
		k.set_part(HEAD, S, 1.15)
		k.cylinder(c, c + Vector3(s * 0.03, 0, 0), 0.05, 20, 0.008)
		k.set_part(HEAD, A)
		k.ring(c + Vector3(s * 0.031, 0, 0), 0.036, 0.0045, Basis(Vector3.BACK, -s * PI * 0.5), 20, 6)
		k.set_part(HEAD, M)
		k.cylinder(c + Vector3(s * 0.028, 0, 0), c + Vector3(s * 0.037, 0, 0), 0.021, 14, 0.004)
	# Helmet lamp (right side, character's right = -X).
	k.set_part(HEAD, S, 1.3)
	k.rounded_box(Vector3(-0.166, 1.712, 0.045), Vector3(0.03, 0.03, 0.075), 0.009, Basis.IDENTITY, 1)
	k.set_part(HEAD, L)
	k.cylinder(Vector3(-0.166, 1.712, 0.08), Vector3(-0.166, 1.712, 0.0865), 0.011, 12, 0.002, 0.0)
	# Antenna (left).
	k.set_part(HEAD, M)
	k.cylinder(Vector3(0.17, 1.68, -0.05), Vector3(0.19, 1.85, -0.115), 0.005, 6, 0.001)
	k.set_part(HEAD, A)
	k.ellipsoid(Vector3(0.19, 1.852, -0.116), Vector3(0.009, 0.009, 0.009), Basis.IDENTITY, 8, 4)
	# Rear comms module.
	k.set_part(HEAD, S, 1.2)
	k.deform = CrewMeshKit.shell(0.17)
	k.rounded_box(Vector3(0, 1.625, HELMET_Z - 0.168), Vector3(0.11, 0.06, 0.03), 0.01, Basis(Vector3.UP, PI), 2)
	k.set_part(HEAD, A)
	k.rounded_box(Vector3(0, 1.628, HELMET_Z - 0.184), Vector3(0.07, 0.008, 0.006), 0.002, Basis(Vector3.UP, PI), 1)
	k.deform = Callable()


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
	var n := 24
	for i in n + 1:
		var v := 0.5 - 0.5 * cos(PI * float(i) / float(n))
		pts.append(_visor_point(1.0, v, lift))
	for i in range(1, n + 1):
		var v2 := 0.5 + 0.5 * cos(PI * float(i) / float(n))
		pts.append(_visor_point(0.0, v2, lift))
	return pts


static func _visor(k: CrewMeshKit) -> void:
	k.set_part(HEAD, CrewMaterials.PRIMARY)
	var head := JOINTS[HEAD]
	k.patch(func(u: float, v: float) -> Vector3: return _visor_point(u, v, 0.004) - head,
		22, 12, Vector3(0, 1.66, HELMET_Z) - head)


static func _arm(k: CrewMeshKit, s: float) -> void:
	var up := L_ARM if s > 0.0 else R_ARM
	var fore := L_FORE if s > 0.0 else R_FORE
	var hand := L_HAND if s > 0.0 else R_HAND
	var x := 0.212 * s
	var face_out := Basis(Vector3.UP, s * PI * 0.5)
	# Upper arm.
	k.set_part(up, F, 0.85)
	k.set_blend(fore, Vector3(x, 1.135, 0), Vector3.DOWN, 0.03)
	k.capsule(Vector3(x, 1.44, -0.015), Vector3(x, 1.12, -0.015), 0.06, 0.05, 14, 3, 3)
	k.set_part(up, P, 0.95)
	k.deform = CrewMeshKit.shell(0.062, 0.0, 0.85, 0.06)
	k.rounded_box(Vector3(x + s * 0.058, 1.29, -0.015), Vector3(0.1, 0.12, 0.022), 0.009, face_out, 2)
	# Shoulder pads: layered, curved over the deltoid.
	var pad_basis := Basis.IDENTITY if s > 0.0 else Basis(Vector3.UP, PI)
	k.set_part(up, S, 1.15)
	k.deform = shifted(CrewMeshKit.arc_x(0.085), Vector3(0.025, 0, 0))
	k.rounded_box(Vector3(x + s * 0.012, 1.452, -0.015), Vector3(0.15, 0.03, 0.18), 0.012, pad_basis, 2, Vector3i(4, 1, 1))
	k.set_part(up, P, 1.0)
	k.deform = shifted(CrewMeshKit.arc_x(0.09), Vector3(0.012, 0, 0))
	k.rounded_box(Vector3(x - s * 0.002, 1.488, -0.015), Vector3(0.16, 0.034, 0.17), 0.015, pad_basis, 2, Vector3i(4, 1, 1))
	k.set_part(up, A)
	k.deform = shifted(CrewMeshKit.arc_x(0.09), Vector3(0.07, 0.018, 0))
	k.rounded_box(Vector3(x - s * 0.002, 1.488, -0.015), Vector3(0.012, 0.004, 0.13), 0.002, pad_basis, 1)
	k.deform = Callable()
	# Elbow joint and cap.
	k.set_part(fore, M, 1.0)
	k.cylinder(Vector3(x - s * 0.045, 1.13, -0.015), Vector3(x + s * 0.045, 1.13, -0.015), 0.036, 14, 0.006)
	k.set_part(fore, S, 1.2)
	k.deform = CrewMeshKit.shell(0.05, 0.05)
	k.rounded_box(Vector3(x, 1.135, -0.05), Vector3(0.075, 0.07, 0.022), 0.01, Basis(Vector3.UP, PI), 2)
	k.deform = Callable()
	# Forearm and gauntlet.
	k.set_part(fore, F, 0.85)
	k.set_blend(up, Vector3(x, 1.12, 0), Vector3.UP, 0.025)
	k.capsule(Vector3(x, 1.13, -0.015), Vector3(x, 0.89, -0.015), 0.048, 0.04, 12, 2, 2)
	k.set_part(fore, P, 1.0)
	k.deform = CrewMeshKit.taper(0.82, 1.0, 0.08, 0.86, 1.0)
	k.rounded_box(Vector3(x, 0.98, -0.012), Vector3(0.1, 0.16, 0.105), 0.03, Basis.IDENTITY, 2)
	k.deform = Callable()
	k.set_part(fore, S, 1.25)
	k.rounded_box(Vector3(x + s * 0.044, 0.995, -0.012), Vector3(0.024, 0.11, 0.07), 0.009, Basis.IDENTITY, 1)
	k.set_part(fore, A)
	k.rounded_box(Vector3(x + s * 0.054, 0.995, -0.012), Vector3(0.004, 0.07, 0.035), 0.0015, Basis.IDENTITY, 1)
	k.set_part(fore, M)
	k.lathe(PackedVector2Array([Vector2(0.04, 0.878), Vector2(0.046, 0.882), Vector2(0.047, 0.896), Vector2(0.041, 0.9)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.012)), 14, Vector2(1.0, 1.05))
	# Glove.
	k.set_part(hand, S, 1.05)
	k.rounded_box(Vector3(x - s * 0.004, 0.818, -0.006), Vector3(0.045, 0.085, 0.088), 0.018, Basis.IDENTITY, 2)
	k.set_part(hand, P, 0.85)
	k.rounded_box(Vector3(x + s * 0.019, 0.822, -0.006), Vector3(0.012, 0.062, 0.072), 0.005, Basis.IDENTITY, 1)
	k.set_part(hand, R, 1.0)
	for i in 4:
		var z := -0.038 + i * 0.025
		var l := 0.05 if i in [1, 2] else 0.044
		k.capsule(Vector3(x - s * 0.004, 0.782, z), Vector3(x - s * 0.016, 0.782 - l, z + 0.004), 0.0115, 0.0105, 8, 2, 1)
	k.capsule(Vector3(x - s * 0.012, 0.83, 0.03), Vector3(x - s * 0.022, 0.785, 0.058), 0.013, 0.0115, 8, 2, 1)


static func _leg(k: CrewMeshKit, s: float) -> void:
	var thigh := L_LEG if s > 0.0 else R_LEG
	var shin := L_SHIN if s > 0.0 else R_SHIN
	var foot := L_FOOT if s > 0.0 else R_FOOT
	var x := 0.098 * s
	# Thigh.
	k.set_part(thigh, F, 0.85)
	k.set_blend(HIPS, Vector3(x, 0.9, 0), Vector3.UP, 0.05)
	k.capsule(Vector3(x, 0.52, 0.0), Vector3(x, 0.97, -0.005), 0.066, 0.088, 14, 3, 3)
	k.set_part(thigh, P, 1.0)
	k.deform = CrewMeshKit.shell(0.085, 0.7, 0.72, 0.12)
	k.rounded_box(Vector3(x + s * 0.012, 0.74, 0.07), Vector3(0.13, 0.24, 0.026), 0.011, Basis(Vector3.UP, s * 0.22), 2, Vector3i(1, 2, 1))
	k.set_part(thigh, S, 1.15)
	k.deform = CrewMeshKit.shell(0.09, 0.0, 0.9, 0.06)
	k.rounded_box(Vector3(x + s * 0.083, 0.79, -0.005), Vector3(0.1, 0.11, 0.04), 0.014, Basis(Vector3.UP, s * PI * 0.5), 2)
	k.set_part(thigh, A)
	k.rounded_box(Vector3(x + s * 0.104, 0.81, -0.005), Vector3(0.05, 0.006, 0.004), 0.0015, Basis(Vector3.UP, s * PI * 0.5), 1)
	k.deform = Callable()
	# Knee.
	k.set_part(shin, M)
	k.cylinder(Vector3(x - s * 0.06, 0.505, -0.005), Vector3(x + s * 0.06, 0.505, -0.005), 0.034, 14, 0.006)
	k.set_part(shin, P, 0.82)
	k.deform = CrewMeshKit.shell(0.065, 0.075, 0.9, 0.055)
	k.rounded_box(Vector3(x, 0.508, 0.058), Vector3(0.1, 0.11, 0.03), 0.013, Basis.IDENTITY, 2)
	k.deform = Callable()
	# Shin.
	k.set_part(shin, F, 0.85)
	k.set_blend(thigh, Vector3(x, 0.51, 0), Vector3.UP, 0.03)
	k.capsule(Vector3(x, 0.51, -0.005), Vector3(x, 0.15, -0.01), 0.062, 0.05, 14, 2, 3)
	k.set_part(shin, P, 1.0)
	k.deform = CrewMeshKit.shell(0.062, 0.9, 0.78, 0.11)
	k.rounded_box(Vector3(x, 0.335, 0.045), Vector3(0.1, 0.22, 0.026), 0.011, Basis.IDENTITY, 2, Vector3i(1, 2, 1))
	k.set_part(shin, A)
	k.rounded_box(Vector3(x, 0.335, 0.06), Vector3(0.006, 0.14, 0.004), 0.0015, Basis.IDENTITY, 1)
	k.deform = Callable()
	# Boot cuff.
	k.set_part(shin, S, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.056, 0.085), Vector2(0.064, 0.1), Vector2(0.066, 0.2), Vector2(0.068, 0.228), Vector2(0.06, 0.238)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.008)), 16, Vector2(1.0, 1.15), 0.0, TAU, PackedFloat32Array([0, 0, 0, 1, 0]))
	k.set_part(shin, M)
	k.lathe(PackedVector2Array([Vector2(0.066, 0.226), Vector2(0.072, 0.23), Vector2(0.072, 0.242), Vector2(0.064, 0.246)]),
		Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.008)), 16, Vector2(1.0, 1.15))
	# Boot.
	k.set_part(foot, M)
	k.cylinder(Vector3(x - s * 0.06, 0.09, -0.01), Vector3(x + s * 0.06, 0.09, -0.01), 0.028, 12, 0.005)
	k.set_part(foot, S, 1.0)
	k.deform = CrewMeshKit.taper(1.0, 0.86, 0.045)
	k.rounded_box(Vector3(x, 0.07, 0.04), Vector3(0.11, 0.09, 0.27), 0.035, Basis.IDENTITY, 2, Vector3i(1, 1, 2))
	k.deform = Callable()
	k.set_part(foot, P, 0.95)
	k.rounded_box(Vector3(x, 0.066, 0.138), Vector3(0.106, 0.074, 0.085), 0.03, Basis.IDENTITY, 2)
	k.set_part(foot, T, 0.9)
	k.rounded_box(Vector3(x, 0.072, -0.078), Vector3(0.1, 0.07, 0.05), 0.02, Basis.IDENTITY, 2)
	k.set_part(foot, R)
	k.rounded_box(Vector3(x, 0.016, 0.04), Vector3(0.118, 0.032, 0.29), 0.012, Basis.IDENTITY, 1)
	k.set_part(foot, A)
	k.rounded_box(Vector3(x, 0.03, 0.04), Vector3(0.122, 0.006, 0.25), 0.0025, Basis.IDENTITY, 1)


static func _occluders(k: CrewMeshKit) -> void:
	k.add_occluder(Vector3(0, 1.32, -0.015), 0.13)
	k.add_occluder(Vector3(0, 1.27, -0.2), 0.12)
	k.add_occluder(Vector3(0, 0.94, 0), 0.11)
	k.add_occluder(Vector3(0, 1.12, -0.01), 0.1)
	k.add_occluder(Vector3(0, 1.665, HELMET_Z), 0.15)
	for s in [1.0, -1.0]:
		k.add_occluder(Vector3(s * 0.212, 1.3, -0.015), 0.055)
		k.add_occluder(Vector3(s * 0.212, 0.99, -0.012), 0.05)
		k.add_occluder(Vector3(s * 0.23, 1.47, -0.015), 0.06)
		k.add_occluder(Vector3(s * 0.098, 0.78, 0), 0.08)
		k.add_occluder(Vector3(s * 0.098, 0.62, 0), 0.07)
		k.add_occluder(Vector3(s * 0.098, 0.33, 0), 0.055)
		k.add_occluder(Vector3(s * 0.098, 0.06, 0.05), 0.055)
