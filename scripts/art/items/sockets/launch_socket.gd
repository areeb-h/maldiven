extends RefCounted
## Core loading points: "shuttle" (Docking, clean white and teal) and "pod" (Cargo,
## rust orange with heavy hazard paint). A lit floor plate, a waisted column with
## shell plates and a chevron strip, a brushed cradle whose three clamp fingers
## close when the core is seated, a tilted status screen with the label
## projector, and a beacon post that strobes and sweeps during the countdown.
## Seat (core) at y 0.965. Kept within 0.55 m behind the origin (the pod's cradle).

const TEAL := Color(0.16, 0.66, 0.58)
const RUST := Color(0.86, 0.38, 0.1)
const SEAT := 0.965


static func build(b: SocketKit.Build) -> void:
	var pod := b.socket.kind == "pod"
	SocketKit.palette(b, RUST if pod else TEAL, Color(0.8, 0.78, 0.73) if pod else Color(0.88, 0.89, 0.9))
	var k := b.body
	# Floor plate with a lit rim.
	k.part(ItemKit.METAL, 0.85)
	k.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.6, 0.0), Vector2(0.62, 0.03), Vector2(0.58, 0.07), Vector2(0.36, 0.07)]),
		Transform3D.IDENTITY, 28, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0, 0.5, 1, 0.6, 0]))
	k.part(ItemKit.STATUS, 0.9)
	k.annulus(Vector3(0, 0.072, 0), Vector3.UP, 0.48, 0.55, 28)
	if pod:
		k.part(ItemKit.HAZARD)
		k.annulus(Vector3(0, 0.071, 0), Vector3.UP, 0.36, 0.47, 28)
	# Waisted column.
	k.part(ItemKit.GRAPHITE, 0.9)
	k.lathe(PackedVector2Array([Vector2(0.36, 0.07), Vector2(0.33, 0.12), Vector2(0.29, 0.19), Vector2(0.29, 0.79), Vector2(0.31, 0.84), Vector2(0.31, 0.88)]),
		Transform3D.IDENTITY, 24, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.5, 0.3, 0.1, 0.1, 0.6, 0.8]))
	k.part(ItemKit.SHELL_B)
	for i in 3:
		var a := float(i) * TAU / 3.0
		k.deform = CrewMeshKit.shell(0.305, 0.0, 1.0, 0.3)
		k.skip_back = true
		k.rounded_box(Vector3(sin(a), 0, cos(a)) * 0.305 + Vector3(0, 0.48, 0), Vector3(0.44, 0.6, 0.03), 0.014, Basis(Vector3.UP, a), 1, Vector3i(3, 2, 1))
		k.deform = Callable()
		k.skip_back = false
	k.part(ItemKit.DECAL)
	k.cyl_decal(Vector3.ZERO, 0.3215, 0.0, 0.62, Vector2(0.2, 0.14), ItemKit.DECAL_CHEVRON, 3)
	k.cyl_decal(Vector3.ZERO, 0.3215, TAU / 3.0, 0.5, Vector2(0.16, 0.16), ItemKit.DECAL_TREFOIL if pod else ItemKit.DECAL_TEXT, 3)
	k.cyl_decal(Vector3.ZERO, 0.3215, -TAU / 3.0, 0.5, Vector2(0.2, 0.05), ItemKit.DECAL_BARCODE, 3)
	k.part(ItemKit.STATUS)
	k.cyl_decal(Vector3.ZERO, 0.322, 0.0, 0.3, Vector2(0.26, 0.026), 0.0, 3)
	if pod:
		k.part(ItemKit.HAZARD)
		k.band(Vector3(0, 0.13, 0), 0.34, 0.05, 24)
	# Cradle: brushed collar and the seat ring.
	k.part(ItemKit.METAL)
	k.lathe(PackedVector2Array([Vector2(0.3, 0.86), Vector2(0.32, 0.9), Vector2(0.31, SEAT - 0.01), Vector2(0.25, SEAT)]),
		Transform3D.IDENTITY, 24, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.4, 1, 0.8, 0.4]))
	SocketKit.seat_ring(b, Vector3(0, SEAT, 0), 0.19, 0.235, 24)
	# Three clamp fingers on hinges: open while empty, closed on the core when filled.
	for i in 3:
		var a := float(i) * TAU / 3.0 + PI / 3.0
		var dir := Vector3(sin(a), 0, cos(a))
		var f := ItemKit.new()
		f.part(ItemKit.SHELL_A)
		f.rounded_box(Vector3(0, 0.1, 0), Vector3(0.06, 0.2, 0.04), 0.015)
		f.part(ItemKit.GRAPHITE)
		f.rounded_box(Vector3(0, 0.01, 0), Vector3(0.08, 0.05, 0.06), 0.016)
		f.part(ItemKit.STATUS)
		f.rounded_box(Vector3(0, 0.15, -0.0215), Vector3(0.03, 0.07, 0.006), 0.0)
		f.part(ItemKit.METAL)
		f.rounded_box(Vector3(0, 0.205, -0.012), Vector3(0.05, 0.02, 0.05), 0.006)
		# Finger local +Z faces the seat (status pad outside); hinge at its foot.
		var base := Basis(Vector3.UP, a + PI)
		var at := dir * 0.275 + Vector3(0, SEAT - 0.005, 0)
		SocketKit.moving_part(b, "Clamp%d" % i, f, null, "fill", Transform3D(base * Basis(Vector3.RIGHT, -0.42), at),
			Transform3D(base * Basis(Vector3.RIGHT, 0.2), at))
	# Rear: tilted status screen on a stand with the label projector on top.
	k.part(ItemKit.GRAPHITE)
	k.rounded_box(Vector3(0, 0.62, -0.42), Vector3(0.14, 1.2, 0.12), 0.03, Basis.IDENTITY, 1)
	var tilt := Basis(Vector3.RIGHT, -0.32)
	k.rounded_box(Vector3(0, 1.28, -0.4), Vector3(0.6, 0.38, 0.07), 0.03, tilt, 1)
	k.part(ItemKit.SHELL_B, 0.9)
	k.rounded_box(Vector3(0, 1.28, -0.4) + tilt * Vector3(0, 0, 0.028), Vector3(0.56, 0.34, 0.02), 0.01, tilt)
	k.part(ItemKit.SCREEN)
	k.rounded_box(Vector3(0, 1.28, -0.4) + tilt * Vector3(0, 0, 0.04), Vector3(0.46, 0.25, 0.006), 0.0, tilt)
	b.label_at = Vector3(0, 1.98, -0.32)
	b.label_width = 1.35 if pod else 1.05
	SocketKit.emitter(b, Vector3(0, 1.28, -0.4) + tilt * Vector3(0, 0.19, -0.01))
	# Beacon post and warning lamps.
	k.part(ItemKit.METAL)
	k.cylinder(Vector3(0.4, 0.0, -0.3), Vector3(0.4, 1.56, -0.3), 0.03, 10, 0.006)
	k.part(ItemKit.GRAPHITE)
	k.cylinder(Vector3(0.4, 0.0, -0.3), Vector3(0.4, 0.12, -0.3), 0.07, 12, 0.012)
	SocketKit.beacon(b, Vector3(0.4, 1.6, -0.3))
	k.part(ItemKit.WARN, 1.0, 0)
	k.disc(Vector3(-0.17, 0.84, 0.255), Vector3(-0.6, 0, 0.8), 0.035, 10, 0.014)
	k.part(ItemKit.WARN, 1.0, 1)
	k.disc(Vector3(0.18, 0.84, 0.25), Vector3(0.6, 0, 0.8), 0.035, 10, 0.014)
	SocketKit.cyl_collider(b, Vector3(0, 0.49, 0), 0.34, 0.98)
	SocketKit.box_collider(b, Vector3(0, 0.75, -0.42), Vector3(0.6, 1.5, 0.16))
	SocketKit.cyl_collider(b, Vector3(0.4, 0.8, -0.3), 0.07, 1.6)
	b.seat = Transform3D(Basis.IDENTITY, Vector3(0, SEAT, 0))
