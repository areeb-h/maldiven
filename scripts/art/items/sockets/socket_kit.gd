class_name SocketKit
extends RefCounted
## Shared construction for the interaction sockets. A socket is a SocketVisual with:
##   Mesh      one opaque ItemKit mesh (ItemMaterials body shader, per-socket uniforms)
##   Fx        one additive / glass mesh (forcefield, seat glow, hologram, beams)
##   parts     optional moving nodes (cage, doors, clamps, lever) driven by state
##   labels    holographic title + status (billboarded Label3D)
##   Collision StaticBody3D on layer 1 hugging the silhouette, clear of the
##             approach point 1.2 m in front (+Z)
## Builders in this folder fill a Build (body / fx kits, palette) and call finish().

const SOCKET_SCRIPTS := {
	"vault": preload("res://scripts/art/items/sockets/vault_socket.gd"),
	"reactor": preload("res://scripts/art/items/sockets/reactor_socket.gd"),
	"shuttle": preload("res://scripts/art/items/sockets/launch_socket.gd"),
	"pod": preload("res://scripts/art/items/sockets/launch_socket.gd"),
	"armory": preload("res://scripts/art/items/sockets/armory_socket.gd"),
	"medbay": preload("res://scripts/art/items/sockets/medbay_socket.gd"),
	"airlock_console": preload("res://scripts/art/items/sockets/airlock_socket.gd"),
}


class Build:
	var socket: SocketVisual
	var body := ItemKit.new()
	var fx := ItemKit.new()
	var collision: StaticBody3D
	var seat := Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0))
	var label_at := Vector3(0, 1.9, 0)
	var label_width := 1.0


## "vault", "reactor", "shuttle", "pod", "armory", "medbay" or "airlock_console".
static func make(kind: String) -> SocketVisual:
	var b := Build.new()
	var s := SocketVisual.new()
	s.name = "Socket_" + kind
	s.kind = kind
	b.socket = s
	b.collision = StaticBody3D.new()
	b.collision.name = "Collision"
	b.collision.collision_layer = 1
	b.collision.collision_mask = 1
	s.add_child(b.collision)
	var script: Script = SOCKET_SCRIPTS.get(kind)
	if script == null:
		push_warning("SocketKit: unknown socket kind " + kind)
		script = SOCKET_SCRIPTS["reactor"]
	script.call("build", b)
	_finish(b)
	s.set_state(false, kind in ["vault", "armory"], false)
	return s


## Palette for a socket's body material (room accent as shell_b / glow_a).
static func palette(b: Build, accent: Color, shell := Color(0.86, 0.87, 0.88), extra := {}) -> void:
	var params := {
		"shell_a": shell, "shell_b": accent, "glow_a": accent.lightened(0.25), "glow_b": Color(0.35, 0.85, 1.0),
		"glow_energy": 1.5, "warn_color": SocketVisual.ACTIVE, "phase": randf(),
	}
	params.merge(extra, true)
	b.socket.body_mat = ItemMaterials.body(params)
	b.socket.fx_mat = ItemMaterials.fx({"field_color": SocketVisual.FIELD, "warn_color": SocketVisual.ACTIVE, "phase": randf()})
	b.socket.fx_mat.render_priority = -1


static func _finish(b: Build) -> void:
	var s := b.socket
	b.body.bake_ao(0.6)
	s.add_child(ItemKit.mesh_instance(b.body.to_mesh(), s.body_mat, "Mesh"))
	if b.fx.triangle_count() > 0:
		s.add_child(ItemKit.fx_instance(b.fx.to_mesh(), s.fx_mat, "Fx"))
	var seat := Marker3D.new()
	seat.name = "Seat"
	seat.transform = b.seat
	s.add_child(seat)
	s.seat = seat
	_labels(b)
	var alarm := OmniLight3D.new()
	alarm.name = "Alarm"
	alarm.light_color = SocketVisual.ACTIVE
	alarm.omni_range = 4.5
	alarm.omni_attenuation = 1.6
	alarm.light_specular = 0.3
	alarm.shadow_enabled = false
	alarm.position = b.label_at + Vector3(0, -0.4, 0.3)
	alarm.visible = false
	s.add_child(alarm)
	s.alarm = alarm


## Holographic title + status, Y-billboarded, over a camera-facing backing panel.
static func _labels(b: Build) -> void:
	var s := b.socket
	var title := Label3D.new()
	title.name = "Title"
	title.font = UiStyle.font("head")
	title.font_size = 64
	title.pixel_size = 0.0028
	title.outline_size = 12
	title.outline_modulate = Color(0.0, 0.03, 0.06, 0.55)
	title.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	title.shaded = false
	title.double_sided = true
	title.render_priority = 2
	title.outline_render_priority = 1
	title.position = b.label_at + Vector3(0, 0.07, 0)
	s.add_child(title)
	s.title_label = title
	var status := Label3D.new()
	status.name = "Status"
	status.font = UiStyle.font("bold")
	status.font_size = 48
	status.pixel_size = 0.0025
	status.outline_size = 10
	status.outline_modulate = Color(0.0, 0.02, 0.04, 0.6)
	status.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	status.shaded = false
	status.double_sided = true
	status.render_priority = 2
	status.outline_render_priority = 1
	status.position = b.label_at + Vector3(0, -0.105, 0)
	s.add_child(status)
	s.status_label = status
	# Backing panel (fx group 1 turns about holo_pivot to face the camera).
	var w := b.label_width
	var h := 0.42
	var c := b.label_at
	b.fx.part(ItemKit.FX_HOLO, 1.0, 1)
	b.fx.patch(func(u: float, v: float) -> Vector3: return c + Vector3((u - 0.5) * w, (v - 0.5) * h, -0.02),
		1, 1, c - Vector3(0, 0, 0.3), Vector2.ONE)
	s.fx_mat.set_shader_parameter("holo_pivot", c)


# --- shared parts ------------------------------------------------------------------

## Seat ring on a horizontal deck at `c`: brushed collar, status ring, glow disc.
static func seat_ring(b: Build, c: Vector3, r_in: float, r_out: float, seg := 28) -> void:
	b.body.part(ItemKit.METAL)
	b.body.lathe(PackedVector2Array([Vector2(r_out, c.y - 0.03), Vector2(r_out + 0.03, c.y - 0.012), Vector2(r_out + 0.03, c.y + 0.006), Vector2(r_out, c.y + 0.016)]),
		Transform3D(Basis.IDENTITY, Vector3(c.x, 0, c.z)), seg, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0.4, 1, 1, 0.4]))
	b.body.part(ItemKit.STATUS)
	b.body.annulus(c + Vector3(0, 0.004, 0), Vector3.UP, r_in, r_out, seg)
	b.body.part(ItemKit.GRAPHITE, 0.7)
	b.body.annulus(c, Vector3.UP, 0.0, r_in, seg)
	glow_disc(b, c + Vector3(0, 0.012, 0), r_out + 0.12)


## Additive seat glow: soft disc with rings converging on the seat (fx FX_SEAT).
static func glow_disc(b: Build, c: Vector3, r: float, seg := 20) -> void:
	b.fx.part(ItemKit.FX_SEAT)
	b.fx.patch(func(u: float, v: float) -> Vector3: return c + Vector3(cos(u * TAU), 0.0, sin(u * TAU)) * r * v,
		seg, 2, c - Vector3(0, 0.2, 0), Vector2.ONE,
		func(u: float, v: float) -> Vector2: return Vector2(0.5 + 0.5 * cos(u * TAU) * v, 0.5 + 0.5 * sin(u * TAU) * v))


## Vertical forcefield cylinder (fx FX_FIELD, shown while locked).
static func field_cylinder(b: Build, c: Vector3, r: float, height: float, seg := 28) -> void:
	b.fx.part(ItemKit.FX_FIELD)
	b.fx.patch(func(u: float, v: float) -> Vector3: return c + Vector3(sin(u * TAU) * r, v * height, cos(u * TAU) * r),
		seg, 2, c + Vector3(0, height * 0.5, 0), Vector2(r * TAU, height))


## Flat forcefield / glass pane facing +Z.
static func pane(k: ItemKit, mat: int, c: Vector3, size: Vector2, cols := 1, rows := 1) -> void:
	k.part(mat)
	k.patch(func(u: float, v: float) -> Vector3: return c + Vector3((u - 0.5) * size.x, (v - 0.5) * size.y, 0.0),
		cols, rows, c - Vector3(0, 0, 0.3), size)


## Rotating warning beacon: graphite base, beacon dome, two sweeping beams.
static func beacon(b: Build, top: Vector3, r := 0.07) -> void:
	b.body.part(ItemKit.GRAPHITE)
	b.body.cylinder(top - Vector3(0, 0.05, 0), top + Vector3(0, 0.01, 0), r + 0.02, 14, 0.008)
	b.body.part(ItemKit.BEACON)
	b.body.lathe(PackedVector2Array([Vector2(r, 0.0), Vector2(r, r * 0.6), Vector2(r * 0.8, r * 1.15), Vector2(r * 0.4, r * 1.45), Vector2(0.0, r * 1.52)]),
		Transform3D(Basis.IDENTITY, top + Vector3(0, 0.01, 0)), 14)
	b.body.part(ItemKit.METAL)
	b.body.ellipsoid(top + Vector3(0, 0.012 + r * 1.55, 0), Vector3(0.016, 0.01, 0.016), Basis.IDENTITY, 8, 3)
	var pivot := top + Vector3(0, r * 0.6, 0)
	b.fx.part(ItemKit.FX_BEAM)
	for side in [-1.0, 1.0]:
		for tilt in [-1.0, 1.0]:
			var len := 1.6
			var dir := Vector3(0, 0, side)
			var up := Vector3(0, 1, 0).rotated(dir, tilt * 0.6)
			var x := up.cross(dir).normalized()
			b.fx.patch(func(u: float, v: float) -> Vector3:
					var spread := lerpf(0.03, 0.42, v)
					return pivot + dir * (r * 0.8 + v * len) + x * (u - 0.5) * spread * 2.0 - Vector3(0, v * 0.12, 0),
				1, 3, pivot + Vector3(0, -0.5, 0), Vector2.ONE)
	b.socket.fx_mat.set_shader_parameter("beam_pivot", pivot)


## Small holo projector puck (status-tinted lens) where a label beam starts.
static func emitter(b: Build, at: Vector3, normal := Vector3.UP) -> void:
	b.body.part(ItemKit.GRAPHITE)
	b.body.cylinder(at - normal * 0.03, at, 0.055, 12, 0.008)
	b.body.part(ItemKit.STATUS, 0.9)
	b.body.disc(at + normal * 0.001, normal, 0.034, 12, 0.012)
	var c := b.label_at
	var base := at + normal * 0.012
	b.fx.part(ItemKit.FX_HOLO)
	b.fx.patch(func(u: float, v: float) -> Vector3:
			var top := c + Vector3(cos(u * TAU) * b.label_width * 0.42, -0.2, sin(u * TAU) * 0.06)
			var bot := base + Vector3(cos(u * TAU), 0.0, sin(u * TAU)) * 0.03
			return bot.lerp(top, v),
		12, 1, (base + c) * 0.5, Vector2.ONE, func(u: float, v: float) -> Vector2: return Vector2(u, v))


static func box_collider(b: Build, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	b.collision.add_child(cs)


static func cyl_collider(b: Build, center: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	b.collision.add_child(cs)


## Moving part: its own body (and optional fx) mesh, transformed between `a` and
## `b` by `driver` ("unlock", "fill" or "active"); `sweep` oscillates while engaged.
static func moving_part(b: Build, node_name: String, body_kit: ItemKit, fx_kit: ItemKit, driver: String, a: Transform3D, moved: Transform3D, sweep := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.transform = a
	b.socket.add_child(n)
	if body_kit != null and body_kit.triangle_count() > 0:
		body_kit.bake_ao(0.5)
		n.add_child(ItemKit.mesh_instance(body_kit.to_mesh(), b.socket.body_mat, "Mesh"))
	if fx_kit != null and fx_kit.triangle_count() > 0:
		n.add_child(ItemKit.fx_instance(fx_kit.to_mesh(), b.socket.fx_mat, "Fx"))
	var rec := {"node": n, "a": a, "b": moved, "driver": driver}
	if sweep != Vector3.ZERO:
		rec["sweep"] = sweep
	b.socket.parts.append(rec)
	return n
