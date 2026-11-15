extends RefCounted
## Reactor cell socket (x3 in the Reactor room): a chunky graphite base with a
## violet front plate showing its glowing number, a brushed receptacle with three
## clamp arms around the seat, a rear power tower with a gauge screen and the
## label projector, and a ribbed conduit into the floor. Seat (cell) at y 0.745.

const VIOLET := Color(0.5, 0.3, 0.92)
const TOP := 0.66
const SEAT := 0.745


static func build(b: SocketKit.Build) -> void:
	SocketKit.palette(b, VIOLET)
	var k := b.body
	# Base block with a violet front plate, glowing number, status strip, hazard kick.
	k.part(ItemKit.GRAPHITE, 0.9)
	k.rounded_box(Vector3(0, TOP * 0.5, -0.03), Vector3(0.84, TOP, 0.72), 0.05, Basis.IDENTITY, 1)
	k.part(ItemKit.SHELL_B)
	k.rounded_box(Vector3(0, 0.38, 0.338), Vector3(0.7, 0.4, 0.03), 0.014)
	k.part(ItemKit.DECAL)
	k.decal(Vector3(0, 0.4, 0.3545), Vector3.RIGHT, Vector3.UP, Vector2(0.16, 0.2), ItemKit.DECAL_DIGIT)
	k.decal(Vector3(-0.22, 0.43, 0.3545), Vector3.RIGHT, Vector3.UP, Vector2(0.14, 0.14), ItemKit.DECAL_BOLT)
	k.decal(Vector3(0.22, 0.43, 0.3545), Vector3.RIGHT, Vector3.UP, Vector2(0.16, 0.06), ItemKit.DECAL_TEXT)
	k.part(ItemKit.STATUS)
	k.rounded_box(Vector3(0, 0.235, 0.355), Vector3(0.56, 0.03, 0.006), 0.0)
	k.part(ItemKit.HAZARD)
	k.rounded_box(Vector3(0, 0.055, 0.33), Vector3(0.8, 0.08, 0.02), 0.006)
	# Receptacle: brushed collar, seat ring, three clamp arms with status pads.
	k.part(ItemKit.METAL)
	k.lathe(PackedVector2Array([Vector2(0.3, TOP - 0.01), Vector2(0.3, TOP + 0.03), Vector2(0.285, SEAT - 0.01), Vector2(0.24, SEAT)]),
		Transform3D.IDENTITY, 24, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.4, 0.8, 1, 0.5]))
	SocketKit.seat_ring(b, Vector3(0, SEAT, 0), 0.17, 0.21, 24)
	for a in [PI * 0.36, -PI * 0.36, PI]:
		var dir := Vector3(sin(a), 0, cos(a))
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.08)
		k.part(ItemKit.SHELL_A)
		k.rounded_box(dir * 0.255 + Vector3(0, SEAT + 0.12, 0), Vector3(0.07, 0.3, 0.045), 0.016, basis)
		k.part(ItemKit.GRAPHITE)
		k.rounded_box(dir * 0.268 + Vector3(0, SEAT - 0.01, 0), Vector3(0.1, 0.07, 0.08), 0.018, Basis(Vector3.UP, a))
		k.part(ItemKit.STATUS)
		k.rounded_box(dir * 0.232 + Vector3(0, SEAT + 0.21, 0), Vector3(0.035, 0.08, 0.008), 0.0, basis)
	# Rear power tower: gauge screen, side strips, holo projector on top.
	k.part(ItemKit.GRAPHITE)
	k.rounded_box(Vector3(0, 1.08, -0.39), Vector3(0.3, 0.84, 0.2), 0.04, Basis.IDENTITY, 1)
	k.part(ItemKit.SHELL_A)
	k.rounded_box(Vector3(0, 1.08, -0.285), Vector3(0.24, 0.7, 0.02), 0.01)
	k.part(ItemKit.SCREEN)
	k.rounded_box(Vector3(0, 1.14, -0.272), Vector3(0.18, 0.36, 0.008), 0.003)
	k.part(ItemKit.LED, 1.0, 1)
	k.rounded_box(Vector3(0, 0.88, -0.272), Vector3(0.12, 0.016, 0.006), 0.0)
	k.part(ItemKit.GLOW_A)
	for s in [-1.0, 1.0]:
		k.rounded_box(Vector3(s * 0.152, 1.08, -0.39), Vector3(0.006, 0.6, 0.06), 0.0)
	b.label_at = Vector3(0, 1.88, -0.34)
	b.label_width = 1.12
	SocketKit.emitter(b, Vector3(0, 1.515, -0.39))
	# Conduit into the floor behind, with lit ribs.
	k.part(ItemKit.GRAPHITE, 1.05)
	k.tube(PackedVector3Array([Vector3(0, 0.3, -0.38), Vector3(0, 0.27, -0.5), Vector3(0, 0.14, -0.6), Vector3(0, -0.02, -0.64)]), 0.07, 10, 8)
	k.part(ItemKit.GLOW_A, 0.9)
	k.band(Vector3(0, 0.07, -0.63), 0.074, 0.02, 10)
	SocketKit.box_collider(b, Vector3(0, (TOP + 0.04) * 0.5, -0.03), Vector3(0.84, TOP + 0.04, 0.74))
	SocketKit.box_collider(b, Vector3(0, 1.08, -0.39), Vector3(0.3, 0.86, 0.2))
	b.seat = Transform3D(Basis.IDENTITY, Vector3(0, SEAT, 0))
