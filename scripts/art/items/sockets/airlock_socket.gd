extends RefCounted
## Airlock console (Commons, by the airlock): a graphite pedestal with an orange
## front, hazard kick and status strip; a tilted deck with a status screen and a
## big red cycle button under a hazard-striped flip guard; a heavy pull lever
## inside a guard hoop; and a beacon. During the warning the guard flips open,
## the lever swings down, the lamps strobe and the beacon sweeps.

const ORANGE := Color(0.95, 0.42, 0.12)
const DECK_Y := 1.0


static func build(b: SocketKit.Build) -> void:
	SocketKit.palette(b, ORANGE)
	var k := b.body
	# Pedestal with an orange face, hazard kick, status strip and stencils.
	k.part(ItemKit.GRAPHITE, 0.9)
	k.rounded_box(Vector3(0, 0.47, -0.05), Vector3(0.64, 0.94, 0.46), 0.04, Basis.IDENTITY, 1)
	k.part(ItemKit.SHELL_B)
	k.rounded_box(Vector3(0, 0.5, 0.185), Vector3(0.54, 0.62, 0.02), 0.014)
	k.part(ItemKit.HAZARD)
	k.rounded_box(Vector3(0, 0.1, 0.18), Vector3(0.6, 0.14, 0.02), 0.006)
	k.part(ItemKit.STATUS)
	k.rounded_box(Vector3(0, 0.84, 0.19), Vector3(0.44, 0.03, 0.006), 0.0)
	k.part(ItemKit.DECAL)
	k.decal(Vector3(0, 0.6, 0.1955), Vector3.RIGHT, Vector3.UP, Vector2(0.2, 0.2), ItemKit.DECAL_BOLT)
	k.decal(Vector3(0, 0.36, 0.1955), Vector3.RIGHT, Vector3.UP, Vector2(0.34, 0.08), ItemKit.DECAL_TEXT)
	# Tilted deck: brushed slab, status screen, button bezel.
	var tilt := Basis(Vector3.RIGHT, 0.42)
	var deck := Vector3(0, DECK_Y, 0.0)
	k.part(ItemKit.METAL)
	k.rounded_box(deck, Vector3(0.72, 0.07, 0.56), 0.02, tilt)
	k.part(ItemKit.SCREEN)
	k.rounded_box(deck + tilt * Vector3(-0.15, 0.037, 0.0), Vector3(0.3, 0.004, 0.32), 0.0, tilt)
	var btn := deck + tilt * Vector3(0.17, 0.035, 0.04)
	var n := tilt * Vector3.UP
	k.part(ItemKit.GRAPHITE)
	k.cylinder(btn, btn + n * 0.03, 0.1, 16, 0.01)
	k.part(ItemKit.WARN, 1.0, 1)
	k.lathe(PackedVector2Array([Vector2(0.072, 0.0), Vector2(0.072, 0.03), Vector2(0.05, 0.05), Vector2(0.0, 0.056)]),
		Transform3D(ItemKit.basis_y(n), btn + n * 0.03), 14)
	# Flip guard over the button, hinged at its back edge.
	var guard := ItemKit.new()
	guard.part(ItemKit.HAZARD)
	guard.rounded_box(Vector3(0, 0.1, 0.11), Vector3(0.23, 0.014, 0.22), 0.006)
	guard.part(ItemKit.METAL)
	for s in [-1.0, 1.0]:
		guard.rounded_box(Vector3(s * 0.112, 0.05, 0.11), Vector3(0.012, 0.1, 0.22), 0.005)
	guard.rounded_box(Vector3(0, 0.05, 0.217), Vector3(0.23, 0.1, 0.012), 0.005)
	var hinge := btn + tilt * Vector3(0, 0.0, -0.11)
	SocketKit.moving_part(b, "Guard", guard, null, "active", Transform3D(tilt, hinge), Transform3D(tilt * Basis(Vector3.RIGHT, -1.9), hinge))
	# Pull lever on the right flank inside a guard hoop.
	var pivot := Vector3(0.36, 0.86, -0.08)
	k.part(ItemKit.GRAPHITE, 1.05)
	k.rounded_box(pivot + Vector3(-0.02, 0, 0), Vector3(0.06, 0.18, 0.18), 0.02)
	k.part(ItemKit.METAL)
	k.cylinder(pivot + Vector3(-0.02, 0, 0), pivot + Vector3(0.05, 0, 0), 0.035, 12, 0.006)
	k.tube(PackedVector3Array([pivot + Vector3(0.06, -0.08, 0.1), pivot + Vector3(0.07, 0.2, 0.2), pivot + Vector3(0.07, 0.48, 0.0),
		pivot + Vector3(0.07, 0.2, -0.2), pivot + Vector3(0.06, -0.08, -0.1)]), 0.012, 6, 14)
	var lever := ItemKit.new()
	lever.part(ItemKit.METAL)
	lever.cylinder(Vector3(0.04, 0, 0), Vector3(0.04, 0.34, 0.0), 0.016, 8, 0.004)
	lever.part(ItemKit.WARN, 1.0, 0)
	lever.capsule(Vector3(0.04, 0.33, 0), Vector3(0.04, 0.42, 0), 0.034, 0.034, 12, 2, 1)
	lever.part(ItemKit.GRAPHITE)
	lever.cylinder(Vector3(0.02, 0, 0), Vector3(0.06, 0, 0), 0.03, 10, 0.004)
	SocketKit.moving_part(b, "Lever", lever, null, "active", Transform3D(Basis(Vector3.RIGHT, -0.35), pivot),
		Transform3D(Basis(Vector3.RIGHT, 1.25), pivot))
	# Beacon on a short mast at the back left.
	k.part(ItemKit.METAL)
	k.cylinder(Vector3(-0.24, 0.9, -0.22), Vector3(-0.24, 1.4, -0.22), 0.022, 8, 0.005)
	SocketKit.beacon(b, Vector3(-0.24, 1.44, -0.22), 0.06)
	b.label_at = Vector3(0, 1.9, -0.05)
	b.label_width = 1.05
	SocketKit.emitter(b, deck + tilt * Vector3(0.0, 0.036, -0.24))
	SocketKit.box_collider(b, Vector3(0, 0.53, -0.04), Vector3(0.66, 1.06, 0.5))
	SocketKit.box_collider(b, pivot + Vector3(0.05, 0.1, 0), Vector3(0.12, 0.5, 0.42))
	b.seat = Transform3D(Basis.IDENTITY, Vector3(0, 1.12, 0.2))
