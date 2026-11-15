extends RefCounted
## Core vault (Command): a round graphite plinth with blue shell plates and a lit
## seat, under an overhead crown carried by a rear spine. While locked a ring of
## brushed bars encloses the core inside a red forcefield; on unlock the cage
## lifts into the crown and the field collapses. Seat (core) at y 0.58.

const BLUE := Color(0.22, 0.4, 0.95)
const DECK := 0.58
const CAGE_R := 0.5
const CAGE_LO := 0.62
const CAGE_HI := 1.52
const CROWN := 2.42
const LIFT := 0.84


static func build(b: SocketKit.Build) -> void:
	SocketKit.palette(b, BLUE)
	var k := b.body
	var seg := 30
	# Plinth: flared skirt, straight drum, brushed deck.
	k.part(ItemKit.GRAPHITE, 0.9)
	k.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.68, 0.0), Vector2(0.69, 0.03), Vector2(0.62, 0.1), Vector2(0.6, 0.12),
			Vector2(0.6, 0.5), Vector2(0.585, 0.53)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0, 0.5, 1, 0.6, 0.3, 0.3, 0.8]))
	k.part(ItemKit.METAL)
	k.lathe(PackedVector2Array([Vector2(0.6, 0.525), Vector2(0.612, 0.545), Vector2(0.6, DECK), Vector2(0.36, DECK)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.5, 1, 0.5, 0]))
	SocketKit.seat_ring(b, Vector3(0, DECK, 0), 0.24, 0.3, seg)
	k.part(ItemKit.GRAPHITE, 0.75)
	k.annulus(Vector3(0, DECK - 0.002, 0), Vector3.UP, 0.33, 0.36, seg)
	# Six blue shell plates around the drum; the front one carries the status strip.
	k.part(ItemKit.SHELL_B)
	for i in 6:
		k.plate(Vector3(0, 0.31, 0), 0.6, float(i) * TAU / 6.0, Vector3(0.56, 0.32, 0.03), 0.012, Vector3i(3, 1, 1))
	k.part(ItemKit.STATUS)
	k.plate(Vector3(0, 0.38, 0), 0.632, 0.0, Vector3(0.34, 0.03, 0.006), 0.0, Vector3i(3, 1, 1))
	k.part(ItemKit.DECAL)
	k.cyl_decal(Vector3.ZERO, 0.6325, 0.0, 0.25, Vector2(0.2, 0.1), ItemKit.DECAL_CHEVRON, 3)
	k.cyl_decal(Vector3.ZERO, 0.6325, PI / 3.0, 0.31, Vector2(0.22, 0.07), ItemKit.DECAL_TEXT, 3)
	k.cyl_decal(Vector3.ZERO, 0.6325, -PI / 3.0, 0.31, Vector2(0.2, 0.05), ItemKit.DECAL_BARCODE, 3)
	# Rear spine with a lit channel, and the crown arm reaching over the seat.
	k.part(ItemKit.GRAPHITE)
	k.rounded_box(Vector3(0, 1.3, -0.74), Vector3(0.36, 2.6, 0.24), 0.04, Basis.IDENTITY, 1)
	k.part(ItemKit.SHELL_A)
	for s in [-1.0, 1.0]:
		k.rounded_box(Vector3(s * 0.2, 1.25, -0.74), Vector3(0.05, 2.1, 0.2), 0.016)
	k.part(ItemKit.STATUS, 0.85)
	k.rounded_box(Vector3(0, 1.35, -0.617), Vector3(0.05, 1.7, 0.012), 0.0)
	k.part(ItemKit.GRAPHITE, 1.05)
	k.rounded_box(Vector3(0, CROWN + 0.13, -0.36), Vector3(0.3, 0.16, 0.72), 0.04, Basis.IDENTITY, 1)
	# Crown: glossy ring with a status underglow and a blue light ring.
	k.part(ItemKit.SHELL_A)
	k.lathe(PackedVector2Array([Vector2(0.46, CROWN - 0.06), Vector2(0.6, CROWN - 0.05), Vector2(0.62, CROWN), Vector2(0.6, CROWN + 0.06), Vector2(0.46, CROWN + 0.07)]),
		Transform3D.IDENTITY, seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.6, 0.8, 1, 0.8, 0.6]))
	k.part(ItemKit.STATUS)
	k.annulus(Vector3(0, CROWN - 0.062, 0), Vector3.DOWN, 0.48, 0.58, seg)
	k.part(ItemKit.GLOW_A)
	k.band(Vector3(0, CROWN, 0), 0.623, 0.018, seg)
	k.part(ItemKit.GRAPHITE, 0.8)
	k.lathe(PackedVector2Array([Vector2(0.46, CROWN + 0.07), Vector2(0.44, CROWN + 0.02), Vector2(0.44, CROWN - 0.04), Vector2(0.46, CROWN - 0.06)]),
		Transform3D.IDENTITY, seg)
	# Cage: brushed bars between two rings; lifts into the crown on unlock.
	var cage := ItemKit.new()
	cage.part(ItemKit.METAL)
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		var p := Vector3(sin(a), 0, cos(a)) * CAGE_R
		cage.cylinder(p + Vector3(0, CAGE_LO, 0), p + Vector3(0, CAGE_HI, 0), 0.017, 8, 0.004)
	cage.part(ItemKit.SHELL_B, 0.8)
	for y in [CAGE_LO, CAGE_HI]:
		cage.ring(Vector3(0, y, 0), CAGE_R, 0.024, Basis.IDENTITY, 28, 4)
	cage.part(ItemKit.STATUS, 0.9)
	cage.band(Vector3(0, CAGE_LO, 0), CAGE_R + 0.025, 0.012, 28)
	SocketKit.moving_part(b, "Cage", cage, null, "unlock", Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(0, LIFT, 0)))
	SocketKit.field_cylinder(b, Vector3(0, CAGE_LO, 0), CAGE_R - 0.02, CAGE_HI - CAGE_LO)
	SocketKit.cyl_collider(b, Vector3(0, DECK * 0.5, 0), 0.66, DECK)
	SocketKit.box_collider(b, Vector3(0, 1.3, -0.74), Vector3(0.36, 2.6, 0.24))
	b.seat = Transform3D(Basis.IDENTITY, Vector3(0, DECK, 0))
	b.label_at = Vector3(0, CROWN + 0.42, -0.1)
	b.label_width = 1.15
