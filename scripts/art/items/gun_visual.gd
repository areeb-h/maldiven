class_name GunVisual
extends Node3D
## The only gun: a chunky toy-scifi sidearm. Glossy white upper shell with an orange
## spine, satin graphite frame and grip, rubber grip panels sized for the crew's
## three-finger glove, three glowing charge cells on each flank plus a rear charge
## readout the shooter sees over the shoulder (0-3 lit; the last one throbs), a
## vented shroud, a brushed muzzle crown with a cyan glow ring and an under-barrel
## capacitor pod. One draw call.
## Origin at the grip (where the hand anchor closes), barrel along +Z, top +Y;
## the pommel sits just below the origin so a dropped gun stands on its grip.

const SHELL := Color(0.92, 0.92, 0.9)
const ACCENT := Color(1.0, 0.42, 0.12)
const CHARGE := Color(0.32, 1.0, 0.78)
const GRIP_TILT := 0.24
const GRIP_C := Vector3(0.0, 0.016, -0.012)

static var _mesh: ArrayMesh

var mat: ShaderMaterial
var ammo := 3


static func build() -> GunVisual:
	var root := GunVisual.new()
	root.name = "Gun"
	root.mat = ItemMaterials.body({
		"shell_a": SHELL, "shell_b": ACCENT, "glow_a": Color(1.0, 0.5, 0.15), "glow_b": CHARGE,
		"glow_energy": 1.8, "led_color": Color(1.0, 0.35, 0.15),
	})
	root.add_child(ItemKit.mesh_instance(mesh(), root.mat, "Mesh"))
	root.set_ammo(3)
	return root


## 0-3 charge cells lit.
func set_ammo(n: int) -> void:
	ammo = clampi(n, 0, 3)
	if mat != null:
		mat.set_shader_parameter("ammo", float(ammo))


static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var k := ItemKit.new()
	var tilt := Basis(Vector3.RIGHT, GRIP_TILT)
	var up := tilt * Vector3.UP
	# Grip: graphite core, rubber side panels, orange pommel cap.
	k.part(ItemKit.GRAPHITE, 0.9)
	k.rounded_box(GRIP_C, Vector3(0.032, 0.078, 0.044), 0.012, tilt)
	k.part(ItemKit.RUBBER)
	for s in [-1.0, 1.0]:
		k.rounded_box(GRIP_C + tilt * Vector3(s * 0.0165, -0.002, 0.002), Vector3(0.006, 0.062, 0.036), 0.0028, tilt)
	k.part(ItemKit.SHELL_B)
	k.rounded_box(GRIP_C - up * 0.039 + tilt * Vector3(0, 0, -0.002), Vector3(0.038, 0.014, 0.052), 0.0065, tilt)
	# Frame (lower receiver) in graphite, trigger guard and trigger.
	k.part(ItemKit.GRAPHITE)
	k.rounded_box(Vector3(0.0, 0.066, 0.045), Vector3(0.046, 0.036, 0.23), 0.012)
	k.part(ItemKit.GRAPHITE, 1.1)
	k.tube(PackedVector3Array([Vector3(0, 0.05, 0.026), Vector3(0, 0.012, 0.032), Vector3(0, -0.002, 0.06),
		Vector3(0, 0.006, 0.094), Vector3(0, 0.05, 0.108)]), 0.0055, 6, 10)
	k.part(ItemKit.SHELL_B)
	k.rounded_box(Vector3(0, 0.03, 0.052), Vector3(0.009, 0.034, 0.012), 0.0036, Basis(Vector3.RIGHT, 0.32))
	# Upper shell: glossy white with panel lines, orange spine.
	k.part(ItemKit.SHELL_A)
	k.rounded_box(Vector3(0.0, 0.113, 0.052), Vector3(0.062, 0.058, 0.264), 0.018)
	k.part(ItemKit.SHELL_B)
	k.rounded_box(Vector3(0.0, 0.1435, 0.07), Vector3(0.026, 0.012, 0.15), 0.0055)
	# Charge cells on both flanks (group 1..3, rear to front) in graphite sockets.
	for s in [-1.0, 1.0]:
		k.part(ItemKit.GRAPHITE, 0.75)
		k.rounded_box(Vector3(s * 0.031, 0.113, 0.048), Vector3(0.006, 0.042, 0.112), 0.0029)
		for i in 3:
			var z := 0.012 + float(i) * 0.036
			k.part(ItemKit.AMMO, 1.0, i + 1)
			k.capsule(Vector3(s * 0.0335, 0.098, z), Vector3(s * 0.0335, 0.128, z), 0.0092, 0.0092, 8, 2, 1)
	# Rear readout: graphite plate with three charge bars facing the shooter.
	k.part(ItemKit.GRAPHITE, 0.85)
	k.rounded_box(Vector3(0.0, 0.112, -0.083), Vector3(0.05, 0.044, 0.01), 0.0034)
	for i in 3:
		k.part(ItemKit.AMMO, 1.0, i + 1)
		k.rounded_box(Vector3(-0.014 + float(i) * 0.014, 0.112, -0.0885), Vector3(0.009, 0.026, 0.004), 0.0)
	# Rear sight with a status LED, front sight fin.
	k.part(ItemKit.GRAPHITE)
	for s in [-1.0, 1.0]:
		k.rounded_box(Vector3(s * 0.011, 0.149, -0.06), Vector3(0.009, 0.016, 0.02), 0.0036)
	k.part(ItemKit.LED)
	k.rounded_box(Vector3(0.0, 0.1445, -0.07), Vector3(0.008, 0.006, 0.006), 0.0)
	k.part(ItemKit.SHELL_B)
	k.rounded_box(Vector3(0.0, 0.151, 0.168), Vector3(0.007, 0.02, 0.024), 0.0034)
	# Vented barrel shroud, barrel, brushed muzzle crown and cyan glow ring.
	var bz := Vector3(0, 0, 1)
	k.part(ItemKit.GRAPHITE, 0.95)
	k.cylinder(Vector3(0, 0.112, 0.178), Vector3(0, 0.112, 0.27), 0.026, 14, 0.006)
	k.part(ItemKit.METAL)
	for z in [0.204, 0.226, 0.248]:
		k.collar(Vector3(0, 0.112, z), 0.024, 0.0285, 0.007, 14, ItemKit.basis_y(bz))
	k.cylinder(Vector3(0, 0.112, 0.268), Vector3(0, 0.112, 0.298), 0.017, 12, 0.003)
	k.collar(Vector3(0, 0.112, 0.302), 0.013, 0.027, 0.016, 16, ItemKit.basis_y(bz))
	k.part(ItemKit.GLOW_B)
	k.ring(Vector3(0, 0.112, 0.311), 0.02, 0.0042, ItemKit.basis_y(bz), 18, 4)
	k.disc(Vector3(0, 0.112, 0.306), bz, 0.0125, 12, -0.004)
	# Under-barrel capacitor pod on a bracket: graphite body, orange nose, lit bands.
	k.part(ItemKit.GRAPHITE, 0.85)
	k.rounded_box(Vector3(0, 0.05, 0.15), Vector3(0.018, 0.014, 0.05), 0.005)
	k.part(ItemKit.GRAPHITE, 1.05)
	k.capsule(Vector3(0, 0.036, 0.118), Vector3(0, 0.036, 0.232), 0.0155, 0.0155, 10, 2, 1, Vector2.ONE, 0.0)
	k.part(ItemKit.GLOW_A)
	for z in [0.198, 0.212]:
		k.band(Vector3(0, 0.036, z), 0.0162, 0.005, 10)
	k.part(ItemKit.SHELL_B)
	k.ellipsoid(Vector3(0, 0.036, 0.236), Vector3(0.0165, 0.0165, 0.016), Basis.IDENTITY, 10, 4)
	# Bolts and stencils on the flanks.
	for s in [-1.0, 1.0]:
		var n := Vector3(s, 0, 0)
		k.part(ItemKit.METAL)
		k.disc(Vector3(s * 0.0311, 0.13, -0.048), n, 0.0055, 6, 0.0018)
		k.disc(Vector3(s * 0.0311, 0.094, -0.048), n, 0.0055, 6, 0.0018)
		k.part(ItemKit.DECAL)
		k.decal(Vector3(s * 0.0312, 0.124, 0.14), Vector3(0, 0, -s), Vector3.UP, Vector2(0.05, 0.016), ItemKit.DECAL_TEXT)
	k.add_occluder(Vector3(0, 0.1, 0.05), 0.03)
	k.bake_ao(0.45)
	_mesh = k.to_mesh()
	return _mesh
