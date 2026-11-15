extends RefCounted
## Armory (Security): a wall weapon locker. Red lower cabinet with hazard kick and
## status strip, a backlit display bay where the gun hangs on brushed hooks
## (barrel to the right, flank to the room), a sliding glass door, a right-hand
## service column with a status screen, and a header with warning lamps and the
## label projector. While locked a red forcefield covers the closed door; on
## unlock the door slides right behind the column. Front face at z = 0.

const RED := Color(0.8, 0.2, 0.22)
const W := 1.6
const D := 0.5
const H := 2.3
const BAY_X := Vector2(-0.75, 0.05)  # display bay span (x)
const BAY_Y := Vector2(0.9, 1.95)  # display bay span (y)


static func build(b: SocketKit.Build) -> void:
	SocketKit.palette(b, RED, Color(0.86, 0.87, 0.88), {"glow_a": Color(1.0, 0.86, 0.72)})
	var k := b.body
	var zc := -D * 0.5
	var bay_w := BAY_X.y - BAY_X.x
	var bay_h := BAY_Y.y - BAY_Y.x
	var bay_c := Vector3((BAY_X.x + BAY_X.y) * 0.5, (BAY_Y.x + BAY_Y.y) * 0.5, 0.0)
	# Carcass: lower cabinet, header, right column, left pillar, back panel.
	k.part(ItemKit.GRAPHITE, 0.9)
	k.rounded_box(Vector3(0, BAY_Y.x * 0.5, zc), Vector3(W, BAY_Y.x, D), 0.04, Basis.IDENTITY, 1)
	k.rounded_box(Vector3(0, (BAY_Y.y + H) * 0.5, zc), Vector3(W, H - BAY_Y.y, D), 0.04, Basis.IDENTITY, 1)
	k.rounded_box(Vector3((BAY_X.y + W * 0.5) * 0.5, bay_c.y, zc), Vector3(W * 0.5 - BAY_X.y, bay_h + 0.02, D), 0.02)
	k.rounded_box(Vector3((BAY_X.x - W * 0.5) * 0.5, bay_c.y, zc), Vector3(W * 0.5 + BAY_X.x, bay_h + 0.02, D), 0.012)
	k.part(ItemKit.GRAPHITE, 0.6)
	k.rounded_box(Vector3(bay_c.x, bay_c.y, -D + 0.02), Vector3(bay_w, bay_h, 0.04), 0.0)
	# Lower cabinet face: red doors with seams, hazard kick, status strip, chevrons.
	k.part(ItemKit.SHELL_B)
	for s in [-1.0, 1.0]:
		k.rounded_box(Vector3(s * 0.38, 0.47, 0.012), Vector3(0.72, 0.62, 0.025), 0.014)
	k.part(ItemKit.HAZARD)
	k.rounded_box(Vector3(0, 0.07, 0.008), Vector3(W - 0.06, 0.1, 0.018), 0.006)
	k.part(ItemKit.STATUS)
	k.rounded_box(Vector3(0, 0.83, 0.02), Vector3(1.3, 0.035, 0.008), 0.0)
	k.part(ItemKit.METAL)
	for s in [-1.0, 1.0]:
		k.rounded_box(Vector3(s * 0.06, 0.55, 0.03), Vector3(0.025, 0.2, 0.025), 0.008)
	k.part(ItemKit.DECAL)
	k.decal(Vector3(-0.38, 0.62, 0.0255), Vector3.RIGHT, Vector3.UP, Vector2(0.26, 0.08), ItemKit.DECAL_TEXT)
	k.decal(Vector3(0.38, 0.62, 0.0255), Vector3.RIGHT, Vector3.UP, Vector2(0.14, 0.14), ItemKit.DECAL_BOLT)
	# Display bay: backlit panel, light bars, two brushed hooks.
	k.part(ItemKit.SHELL_A, 0.95)
	k.rounded_box(Vector3(bay_c.x, bay_c.y, -D + 0.05), Vector3(bay_w - 0.06, bay_h - 0.06, 0.02), 0.01)
	k.part(ItemKit.GLOW_A, 0.75)
	for y in [BAY_Y.x + 0.03, BAY_Y.y - 0.03]:
		k.rounded_box(Vector3(bay_c.x, y, -0.25), Vector3(bay_w - 0.02, 0.018, 0.4), 0.0)
	k.part(ItemKit.METAL)
	for x in [-0.53, -0.39]:
		k.rounded_box(Vector3(x, 1.33, -0.34), Vector3(0.03, 0.03, 0.26), 0.008)
		k.rounded_box(Vector3(x, 1.36, -0.215), Vector3(0.03, 0.06, 0.02), 0.008)
	k.part(ItemKit.GRAPHITE, 0.8)
	k.rounded_box(Vector3(bay_c.x, BAY_Y.x + 0.01, -0.22), Vector3(bay_w, 0.02, 0.44), 0.0)
	# Right service column: screen, vents, lock pad.
	var col_x := (BAY_X.y + W * 0.5) * 0.5
	k.part(ItemKit.SHELL_A, 0.9)
	k.rounded_box(Vector3(col_x, bay_c.y, 0.008), Vector3(0.66, bay_h - 0.04, 0.02), 0.012)
	k.part(ItemKit.SCREEN)
	k.rounded_box(Vector3(col_x, 1.58, 0.02), Vector3(0.44, 0.3, 0.006), 0.0)
	k.part(ItemKit.GRAPHITE, 0.7)
	for i in 4:
		k.rounded_box(Vector3(col_x, 1.12 + float(i) * 0.045, 0.02), Vector3(0.4, 0.016, 0.006), 0.0)
	k.part(ItemKit.LED, 1.0, 1)
	k.rounded_box(Vector3(col_x + 0.24, 1.35, 0.02), Vector3(0.03, 0.03, 0.006), 0.0)
	# Header: red fascia, warning lamps, projector.
	k.part(ItemKit.SHELL_B)
	k.rounded_box(Vector3(0, (BAY_Y.y + H) * 0.5, 0.012), Vector3(W - 0.08, H - BAY_Y.y - 0.08, 0.025), 0.014)
	k.part(ItemKit.WARN, 1.0, 0)
	k.disc(Vector3(-0.6, 2.12, 0.026), Vector3.BACK, 0.04, 10, 0.016)
	k.part(ItemKit.WARN, 1.0, 1)
	k.disc(Vector3(0.6, 2.12, 0.026), Vector3.BACK, 0.04, 10, 0.016)
	k.part(ItemKit.STATUS, 0.9)
	k.rounded_box(Vector3(0, 2.12, 0.027), Vector3(0.8, 0.03, 0.006), 0.0)
	b.label_at = Vector3(0, 2.62, -0.05)
	b.label_width = 1.0
	SocketKit.emitter(b, Vector3(0, H + 0.002, -0.15))
	# Glass door: a brushed frame round a clear pane; slides right on unlock.
	var door := ItemKit.new()
	var door_fx := ItemKit.new()
	var dw := bay_w + 0.02
	var dh := bay_h + 0.02
	door.part(ItemKit.METAL)
	for s in [-1.0, 1.0]:
		door.rounded_box(Vector3(s * (dw * 0.5 - 0.015), 0, 0), Vector3(0.03, dh, 0.025), 0.008)
		door.rounded_box(Vector3(0, s * (dh * 0.5 - 0.015), 0), Vector3(dw - 0.06, 0.03, 0.025), 0.008)
	door.part(ItemKit.GRAPHITE)
	door.rounded_box(Vector3(-dw * 0.5 + 0.06, 0, 0.018), Vector3(0.025, 0.24, 0.02), 0.008)
	SocketKit.pane(door_fx, ItemKit.FX_GLASS, Vector3.ZERO, Vector2(dw - 0.05, dh - 0.05))
	var closed := Transform3D(Basis.IDENTITY, Vector3(bay_c.x, bay_c.y, 0.035))
	SocketKit.moving_part(b, "Door", door, door_fx, "unlock", closed, closed.translated(Vector3(0.74, 0, 0)))
	SocketKit.pane(b.fx, ItemKit.FX_FIELD, Vector3(bay_c.x, bay_c.y, 0.06), Vector2(bay_w + 0.04, bay_h + 0.04), 1, 1)
	SocketKit.box_collider(b, Vector3(0, H * 0.5, zc + 0.02), Vector3(W, H, D + 0.04))
	# Gun on the hooks: grip at the seat, barrel toward +X, flank facing the room.
	b.seat = Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(-0.47, 1.297, -0.27))
