class_name CoreVisual
extends Node3D
## The station core, the precious objective: a swirling cyan plasma orb inside a
## rounded cage of brushed-metal ribs with a glossy equator band, on a graphite
## cradle with a lit collar. Two emitter rings precess around the cage, the orb's
## bright limb blooms through glow and one small omni light tints whoever carries it.
## Silhouette: a glowing ball in a cage, nothing like the tall cell canister.
## Origin at the bottom centre; ~0.62 m tall, ~0.6 m across the rings.
## Draw calls: body + rings (2); the VFX layer adds its own halo and motes.

const CYAN := Color(0.25, 0.95, 1.0)
const SHELL := Color(0.9, 0.91, 0.9)
const ORB_Y := 0.36
const ORB_R := 0.142
const CAGE_R := 0.214
const RING_R := 0.272

static var _body_mesh: ArrayMesh
static var _ring_mesh: ArrayMesh

var rings: Node3D
var light: OmniLight3D
var _t := 0.0


static func build() -> Node3D:
	var root := CoreVisual.new()
	root.name = "Core"
	root._t = randf() * 10.0
	var mat := material()
	root.add_child(ItemKit.mesh_instance(body_mesh(), mat, "Mesh"))
	root.rings = Node3D.new()
	root.rings.name = "Rings"
	root.rings.position = Vector3(0, ORB_Y, 0)
	root.add_child(root.rings)
	root.rings.add_child(ItemKit.mesh_instance(ring_mesh(), mat, "RingMesh", false))
	root.light = OmniLight3D.new()
	root.light.name = "Light"
	root.light.light_color = CYAN
	root.light.light_energy = 1.1
	root.light.light_specular = 0.4
	root.light.omni_range = 3.0
	root.light.omni_attenuation = 1.4
	root.light.shadow_enabled = false
	root.light.position = Vector3(0, ORB_Y, 0)
	root.add_child(root.light)
	root._pose()
	return root


static func material() -> ShaderMaterial:
	return ItemMaterials.shared_body("core", {
		"shell_a": SHELL, "glow_b": CYAN, "glow_energy": 1.8, "orb_center": Vector3(0, ORB_Y, 0),
		"led_color": CYAN, "shell_b": Color(0.2, 0.55, 0.85),
	})


func _process(delta: float) -> void:
	_t += delta
	_pose()


## Rings precess slowly (a gyroscope), the light breathes with the plasma.
func _pose() -> void:
	if rings != null:
		rings.basis = Basis(Vector3.UP, _t * 0.55) * Basis(Vector3.RIGHT, 0.12 * sin(_t * 0.8))
	if light != null:
		light.light_energy = 1.0 + 0.12 * sin(_t * 5.03) + 0.05 * sin(_t * 13.0)


static func body_mesh() -> ArrayMesh:
	if _body_mesh != null:
		return _body_mesh
	var k := ItemKit.new()
	var c := Vector3(0, ORB_Y, 0)
	# Cradle: satin graphite plinth, brushed bumper, glowing collar.
	k.part(ItemKit.GRAPHITE, 0.95)
	k.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.172, 0.0), Vector2(0.19, 0.022),
			Vector2(0.176, 0.054), Vector2(0.1, 0.072)]),
		Transform3D.IDENTITY, 22, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0, 0.5, 1, 0.8, 0.1]))
	k.part(ItemKit.METAL)
	k.lathe(PackedVector2Array([Vector2(0.188, 0.016), Vector2(0.197, 0.02), Vector2(0.197, 0.032), Vector2(0.188, 0.036)]),
		Transform3D.IDENTITY, 22, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.4, 1, 1, 0.4]))
	k.part(ItemKit.GLOW_B)
	k.annulus(Vector3(0, 0.0675, 0), Vector3.UP, 0.112, 0.136, 22)
	# Lower hub: a brushed cup the cage ribs grow out of.
	k.part(ItemKit.METAL, 0.95)
	k.lathe(PackedVector2Array([Vector2(0.095, 0.066), Vector2(0.088, 0.09), Vector2(0.075, 0.13), Vector2(0.05, 0.15), Vector2(0.0, 0.154)]),
		Transform3D.IDENTITY, 12, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.4, 0.8, 0.6, 0.3, 0]))
	# Plasma orb.
	k.part(ItemKit.ORB)
	k.ellipsoid(c, Vector3(ORB_R, ORB_R, ORB_R), Basis.IDENTITY, 15, 8)
	# Six rounded meridian ribs from the lower hub to the top cap.
	k.part(ItemKit.METAL)
	for i in 6:
		var a := TAU * float(i) / 6.0 + PI / 6.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		var pts := PackedVector3Array()
		for j in 7:
			var lat := lerpf(-1.18, 1.22, float(j) / 6.0)
			pts.append(c + dir * cos(lat) * CAGE_R + Vector3(0, sin(lat) * CAGE_R, 0))
		k.tube(pts, 0.0115, 5, 8)
	# Glossy equator band with four cyan running lights.
	k.part(ItemKit.SHELL_A)
	k.lathe(PackedVector2Array([Vector2(CAGE_R - 0.004, -0.026), Vector2(CAGE_R + 0.02, -0.016), Vector2(CAGE_R + 0.02, 0.008), Vector2(CAGE_R - 0.004, 0.018)]),
		Transform3D(Basis.IDENTITY, c), 22, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.7, 0.2, 0.2, 0.7]))
	k.part(ItemKit.GLOW_B)
	for i in 4:
		var a2 := TAU * float(i) / 4.0
		k.plate(c + Vector3(0, -0.004, 0), CAGE_R + 0.019, a2, Vector3(0.05, 0.012, 0.004), 0.0, Vector3i(3, 1, 1))
	k.part(ItemKit.GRAPHITE, 0.8)
	for i in 4:
		var a3 := TAU * float(i) / 4.0 + PI / 4.0
		k.plate(c + Vector3(0, -0.004, 0), CAGE_R + 0.019, a3, Vector3(0.03, 0.026, 0.005), 0.003, Vector3i(2, 1, 1))
	# Top cap: graphite dome, brushed emitter, glowing tip.
	k.part(ItemKit.GRAPHITE)
	var top := c.y + CAGE_R * sin(1.22)
	k.lathe(PackedVector2Array([Vector2(0.075, top - 0.02), Vector2(0.078, top - 0.004), Vector2(0.068, top + 0.016), Vector2(0.045, top + 0.03), Vector2(0.0, top + 0.034)]),
		Transform3D.IDENTITY, 12, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.3, 1, 0.7, 0.3, 0]))
	k.part(ItemKit.METAL)
	k.lathe(PackedVector2Array([Vector2(0.022, top + 0.026), Vector2(0.022, top + 0.048), Vector2(0.0, top + 0.05)]), Transform3D.IDENTITY, 10)
	k.part(ItemKit.GLOW_B)
	k.ellipsoid(Vector3(0, top + 0.055, 0), Vector3(0.016, 0.012, 0.016), Basis.IDENTITY, 8, 3)
	# Underside ring where the ribs meet the hub.
	k.part(ItemKit.GRAPHITE, 0.9)
	var bot := c.y - CAGE_R * sin(1.18) + 0.004
	k.lathe(PackedVector2Array([Vector2(0.06, bot - 0.012), Vector2(0.088, bot - 0.006), Vector2(0.088, bot + 0.006), Vector2(0.06, bot + 0.012)]),
		Transform3D.IDENTITY, 12, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.4, 1, 1, 0.4]))
	k.add_occluder(c, ORB_R * 0.9)
	k.bake_ao(0.5)
	_body_mesh = k.to_mesh()
	return _body_mesh


## Two thin emitter rings with brushed nodes, built around the orb centre.
static func ring_mesh() -> ArrayMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var k := ItemKit.new()
	for i in 2:
		var tilt := Basis(Vector3.BACK, 0.42 if i == 0 else -0.42) * Basis(Vector3.RIGHT, 0.3 if i == 0 else -0.3)
		var r := RING_R - float(i) * 0.016
		k.part(ItemKit.GLOW_B, 0.9)
		k.ring(Vector3.ZERO, r, 0.0055, tilt, 24, 4)
		k.part(ItemKit.METAL)
		for j in 2:
			var a := PI * float(j) + float(i) * PI * 0.5
			var p := tilt * (Vector3(sin(a), 0.0, cos(a)) * r)
			k.ellipsoid(p, Vector3(0.017, 0.012, 0.017), tilt * Basis(Vector3.UP, a), 8, 3)
	_ring_mesh = k.to_mesh()
	return _ring_mesh

