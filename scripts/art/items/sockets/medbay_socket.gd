extends RefCounted
## Medbay revive bed (Medical): a pedestal bed along local X with a glossy frame,
## a vinyl mattress and pillow (head at +X), side rails carrying a scanner arch
## that sweeps along the patient with a light curtain, and a head unit with a
## vitals screen, a glowing cross and the label projector. The patient side faces
## +Z (the room). Seat: a body lying on its back, feet at -X, face up.

const GREEN := Color(0.3, 0.85, 0.45)
const VINYL := Color(0.42, 0.6, 0.64)
const BED_TOP := 0.58
const MAT_TOP := 0.72


static func build(b: SocketKit.Build) -> void:
	SocketKit.palette(b, VINYL, Color(0.9, 0.92, 0.93), {"glow_a": Color(0.45, 1.0, 0.6)})
	var k := b.body
	# Pedestal and glossy bed frame with a status strip along the patient side.
	k.part(ItemKit.GRAPHITE, 0.9)
	k.rounded_box(Vector3(-0.05, 0.22, 0), Vector3(1.5, 0.44, 0.56), 0.05, Basis.IDENTITY, 1)
	k.part(ItemKit.METAL, 0.85)
	k.rounded_box(Vector3(-0.05, 0.02, 0), Vector3(1.66, 0.04, 0.7), 0.015)
	k.part(ItemKit.SHELL_A)
	k.rounded_box(Vector3(0, BED_TOP - 0.07, 0), Vector3(2.1, 0.14, 0.86), 0.05, Basis.IDENTITY, 1)
	k.part(ItemKit.STATUS)
	k.rounded_box(Vector3(-0.1, BED_TOP - 0.075, 0.432), Vector3(1.5, 0.03, 0.006), 0.0)
	k.part(ItemKit.GLOW_A, 0.8)
	k.rounded_box(Vector3(-0.05, 0.06, 0.29), Vector3(1.3, 0.02, 0.01), 0.0)
	# Mattress and pillow.
	k.part(ItemKit.SHELL_B, 1.0)
	k.rounded_box(Vector3(-0.05, (BED_TOP + MAT_TOP) * 0.5, 0), Vector3(1.9, MAT_TOP - BED_TOP, 0.74), 0.05, Basis.IDENTITY, 1, Vector3i(3, 1, 1))
	k.part(ItemKit.SHELL_A, 0.97)
	k.rounded_box(Vector3(0.74, MAT_TOP + 0.035, 0), Vector3(0.3, 0.08, 0.56), 0.035, Basis.IDENTITY, 1)
	# Side rails for the scanner carriage.
	k.part(ItemKit.METAL)
	for s in [-1.0, 1.0]:
		k.rounded_box(Vector3(-0.1, BED_TOP - 0.03, s * 0.445), Vector3(1.8, 0.035, 0.03), 0.01)
	# Head unit: tower, vitals screen on a bracket, glowing cross, projector.
	k.part(ItemKit.GRAPHITE)
	k.rounded_box(Vector3(1.14, 0.66, -0.08), Vector3(0.16, 1.32, 0.66), 0.04, Basis.IDENTITY, 1)
	k.part(ItemKit.SHELL_A)
	k.rounded_box(Vector3(1.055, 0.95, -0.08), Vector3(0.02, 0.6, 0.5), 0.01)
	k.part(ItemKit.DECAL)
	k.decal(Vector3(1.0435, 1.1, 0.06), Vector3(0, 0, -1), Vector3.UP, Vector2(0.16, 0.16), ItemKit.DECAL_CROSS)
	var mon := Basis(Vector3.UP, -0.55)
	k.part(ItemKit.GRAPHITE, 1.05)
	k.rounded_box(Vector3(1.0, 1.42, 0.12), Vector3(0.5, 0.34, 0.05), 0.02, mon, 1)
	k.part(ItemKit.SCREEN)
	k.rounded_box(Vector3(1.0, 1.42, 0.12) + mon * Vector3(0, 0, 0.027), Vector3(0.42, 0.26, 0.004), 0.0, mon)
	k.part(ItemKit.METAL)
	k.rounded_box(Vector3(1.1, 1.3, 0.0), Vector3(0.04, 0.06, 0.26), 0.01, mon)
	b.label_at = Vector3(0.0, 1.95, -0.1)
	b.label_width = 0.95
	SocketKit.emitter(b, Vector3(1.14, 1.322, -0.2))
	# Scanner arch on the rails: glossy hoop, status inner edge, light curtain.
	var arch := ItemKit.new()
	var curtain := ItemKit.new()
	var pts := PackedVector3Array()
	var inner := PackedVector3Array()
	for i in 11:
		var a := lerpf(-0.05, PI + 0.05, float(i) / 10.0)
		pts.append(Vector3(0, BED_TOP - 0.03 + sin(a) * 0.55, cos(a) * 0.46))
		inner.append(Vector3(0, BED_TOP - 0.03 + sin(a) * 0.5, cos(a) * 0.41))
	arch.part(ItemKit.SHELL_A)
	arch.tube(pts, 0.045, 8, 16)
	arch.part(ItemKit.STATUS)
	arch.tube(inner, 0.011, 5, 16)
	arch.part(ItemKit.GRAPHITE)
	for s in [-1.0, 1.0]:
		arch.rounded_box(Vector3(0, BED_TOP - 0.03, s * 0.46), Vector3(0.12, 0.07, 0.07), 0.02)
	curtain.part(ItemKit.FX_SCAN)
	curtain.patch(func(u: float, v: float) -> Vector3:
			var a2 := lerpf(0.0, PI, u)
			return Vector3(0, lerpf(MAT_TOP + 0.01, BED_TOP - 0.03 + sin(a2) * 0.49, v), cos(a2) * 0.4),
		8, 1, Vector3(-1, 0.9, 0), Vector2.ONE)
	SocketKit.moving_part(b, "Scanner", arch, curtain, "unlock", Transform3D(Basis.IDENTITY, Vector3(0.62, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(-0.1, 0, 0)), Vector3(0.62, 0, 0))
	SocketKit.box_collider(b, Vector3(0, 0.37, 0), Vector3(2.1, 0.74, 0.86))
	SocketKit.box_collider(b, Vector3(1.14, 0.66, -0.08), Vector3(0.16, 1.32, 0.66))
	b.seat = Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(-0.9, MAT_TOP + 0.02, 0.0))
