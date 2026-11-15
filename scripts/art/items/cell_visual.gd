class_name CellVisual
extends RefCounted
## Power cell: a chunky battery canister readable at 20 m. Off-white clear-coated
## shell plates over a glowing amber core seen through four tall windows (four
## stacked charge bars with rising bubbles and a charge sweep), a hazard-striped
## collar, an orange cap with a brass terminal, two side carry handles with rubber
## sleeves, stencils and a blinking status LED. One draw call.
## Origin at the bottom centre; ~0.58 m tall, 0.2 m radius over the handles.

const SHELL := Color(0.86, 0.87, 0.85)
const CAP := Color(0.95, 0.36, 0.05)
const AMBER := Color(1.0, 0.58, 0.1)

const R_CORE := 0.126  # glowing core cylinder
const R_SHELL := 0.148  # outer face of the shell plates
const Y_FOOT := 0.072
const Y_WIN_LO := 0.118
const Y_WIN_HI := 0.408
const Y_TOP := 0.452

static var _mesh: ArrayMesh


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Cell"
	var mi := ItemKit.mesh_instance(mesh(), material(), "Mesh")
	root.add_child(mi)
	return root


static func material() -> ShaderMaterial:
	return ItemMaterials.shared_body("cell", {
		"shell_a": SHELL, "shell_b": CAP, "glow_a": AMBER, "glow_energy": 1.75,
		"charge_span": Vector2(Y_WIN_LO - 0.004, Y_WIN_HI + 0.004), "led_color": Color(0.35, 1.0, 0.5),
	})


static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var k := ItemKit.new()
	var seg := 18
	# Foot: satin graphite base with a rubber bumper.
	k.part(ItemKit.GRAPHITE, 0.95)
	k.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.13, 0.0), Vector2(0.152, 0.016), Vector2(0.15, Y_FOOT)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0, 0.6, 1, 0.3]))
	k.part(ItemKit.RUBBER)
	k.lathe(PackedVector2Array([Vector2(0.15, 0.02), Vector2(0.162, 0.026), Vector2(0.162, 0.044), Vector2(0.15, 0.05)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.5, 1, 1, 0.5]))
	# Glowing charge core, visible through the windows.
	k.part(ItemKit.CHARGE)
	k.lathe(PackedVector2Array([Vector2(R_CORE, Y_FOOT - 0.005), Vector2(R_CORE, Y_TOP + 0.005)]), Transform3D.IDENTITY, 24)
	# Lower shell collar and the hazard-striped upper collar framing the windows.
	k.part(ItemKit.SHELL_A)
	k.lathe(PackedVector2Array([Vector2(0.142, Y_FOOT - 0.004), Vector2(R_SHELL, Y_FOOT + 0.006), Vector2(R_SHELL, Y_WIN_LO - 0.008), Vector2(0.141, Y_WIN_LO)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.8, 0.4, 0.4, 0.8]))
	k.part(ItemKit.HAZARD)
	k.lathe(PackedVector2Array([Vector2(0.141, Y_WIN_HI), Vector2(R_SHELL, Y_WIN_HI + 0.008), Vector2(R_SHELL, Y_TOP - 0.006), Vector2(0.144, Y_TOP)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.8, 0.4, 0.4, 0.8]))
	# Four curved shell plates between the windows (front, sides, back).
	k.part(ItemKit.SHELL_A)
	var plate_arc := deg_to_rad(52.0)
	for i in 4:
		var theta := float(i) * PI * 0.5
		k.plate(Vector3(0, (Y_WIN_LO + Y_WIN_HI) * 0.5, 0), R_SHELL - 0.022, theta, Vector3(plate_arc * (R_SHELL - 0.011), Y_WIN_HI - Y_WIN_LO + 0.004, 0.022), 0.009, Vector3i(3, 1, 1))
	# Thin brushed window frames (vertical rails at each window edge).
	k.part(ItemKit.METAL, 0.9)
	for i in 4:
		var mid := float(i) * PI * 0.5 + PI * 0.25
		for s in [-1.0, 1.0]:
			var a: float = mid + s * deg_to_rad(18.5)
			var p := Vector3(sin(a), 0, cos(a)) * (R_CORE + 0.008)
			k.rounded_box(p + Vector3(0, (Y_WIN_LO + Y_WIN_HI) * 0.5, 0), Vector3(0.006, Y_WIN_HI - Y_WIN_LO, 0.014), 0.0, Basis(Vector3.UP, a))
	# Shoulder, orange cap and brass terminal with a lit ring.
	k.part(ItemKit.GRAPHITE, 1.0)
	k.lathe(PackedVector2Array([Vector2(0.146, Y_TOP - 0.002), Vector2(0.144, Y_TOP + 0.016), Vector2(0.132, Y_TOP + 0.04), Vector2(0.108, Y_TOP + 0.058)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.3, 0.9, 0.6, 0.9]))
	k.part(ItemKit.SHELL_B)
	k.lathe(PackedVector2Array([Vector2(0.11, Y_TOP + 0.056), Vector2(0.1, Y_TOP + 0.07), Vector2(0.07, Y_TOP + 0.079), Vector2(0.0, Y_TOP + 0.082)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([1, 0.6, 0.1, 0]))
	k.part(ItemKit.GRAPHITE)
	k.lathe(PackedVector2Array([Vector2(0.05, Y_TOP + 0.074), Vector2(0.05, Y_TOP + 0.088), Vector2(0.044, Y_TOP + 0.092), Vector2(0.03, Y_TOP + 0.092)]),
		Transform3D.IDENTITY, 14, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0, 0.8, 0.8, 0]))
	k.part(ItemKit.GLOW_A)
	k.band(Vector3(0, Y_TOP + 0.099, 0), 0.0395, 0.012, 14)
	k.part(ItemKit.BRASS)
	k.lathe(PackedVector2Array([Vector2(0.036, Y_TOP + 0.09), Vector2(0.037, Y_TOP + 0.12), Vector2(0.027, Y_TOP + 0.128), Vector2(0.0, Y_TOP + 0.13)]),
		Transform3D.IDENTITY, 14, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0, 1, 0.5, 0]))
	# Side carry handles: brushed loops with rubber sleeves on graphite mounts.
	for s in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		for p in [Vector2(0.142, 0.398), Vector2(0.18, 0.392), Vector2(0.197, 0.33), Vector2(0.199, 0.26), Vector2(0.197, 0.19), Vector2(0.18, 0.13), Vector2(0.142, 0.124)]:
			pts.append(Vector3(s * p.x, p.y, 0.0))
		k.part(ItemKit.METAL)
		k.tube(pts, 0.0125, 6, 10)
		k.part(ItemKit.RUBBER)
		k.cylinder(Vector3(s * 0.1985, 0.205, 0.0), Vector3(s * 0.1985, 0.315, 0.0), 0.017, 8, 0.006)
		k.part(ItemKit.GRAPHITE, 1.05)
		for y in [0.396, 0.126]:
			k.ellipsoid(Vector3(s * 0.152, y, 0.0), Vector3(0.014, 0.018, 0.024), Basis.IDENTITY, 8, 3)
	# Stencils: hazard bolt and barcode on the front plate, serial text on the back.
	k.part(ItemKit.DECAL)
	k.cyl_decal(Vector3.ZERO, R_SHELL + 0.0012, 0.0, 0.305, Vector2(0.082, 0.082), ItemKit.DECAL_BOLT, 4)
	k.cyl_decal(Vector3.ZERO, R_SHELL + 0.0012, 0.0, 0.178, Vector2(0.075, 0.03), ItemKit.DECAL_BARCODE, 4)
	k.cyl_decal(Vector3.ZERO, R_SHELL + 0.0012, PI, 0.31, Vector2(0.085, 0.05), ItemKit.DECAL_TEXT, 4)
	k.cyl_decal(Vector3.ZERO, R_SHELL + 0.0012, PI, 0.2, Vector2(0.07, 0.07), ItemKit.DECAL_TREFOIL, 4)
	# Status LED in a graphite bezel on the shoulder, front.
	k.part(ItemKit.GRAPHITE, 0.8)
	k.disc(Vector3(0, Y_TOP + 0.03, 0.137), Vector3(0, 0.35, 1), 0.017, 10, 0.004)
	k.part(ItemKit.LED)
	k.disc(Vector3(0, Y_TOP + 0.0305, 0.1405), Vector3(0, 0.35, 1), 0.0095, 8, 0.006)
	# Contact shading from the body onto the handles and foot.
	k.add_occluder(Vector3(0, 0.26, 0), 0.13)
	k.add_occluder(Vector3(0, 0.12, 0), 0.12)
	k.add_occluder(Vector3(0, 0.4, 0), 0.12)
	k.bake_ao(0.7)
	_mesh = k.to_mesh()
	return _mesh
