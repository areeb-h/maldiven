class_name StationBuilder
extends RefCounted
## Procedural art + collision for Drift Station, built from StationLayout.
## build() adds a "Station" node (an ArtStationFX) with environment, lighting,
## per-room merged meshes, collision (layer 1), signage, decor, exterior and sky.
## set_power_state() tweens between "emergency", "restored" and "blackout".
##
## Per room or corridor: one merged visual mesh (one surface per material, no
## shadow casting), one shadow-only proxy built from the collision boxes, one
## omni light, one reflection probe and at most six decals. All text (room
## names, plaques, stencils) is vector TextMesh geometry merged into those
## meshes, so it costs no extra draw calls. Every prop a player can walk into
## has a box/cylinder collider that hugs its silhouette and is registered in
## ArtStationFX.props for the art smoke test.

const SPINNER := preload("res://scripts/art/spinner.gd")
const T := 0.4  # wall thickness (walls sit outside the room/corridor rects)
const H := StationLayout.WALL_HEIGHT
const COLLIDER_TOP := StationLayout.WALL_HEIGHT + 1.8
const WALL_IN := 0.12  # wall colliders reach this far into the room (covers wall-mounted kit)
const SHADOW_TOP := StationLayout.WALL_HEIGHT + 0.22
const KICK := 0.3
const TRIM_LO := 2.72
const TRIM_HI := 2.8
const SILL := 1.0
const WIN_TOP := 2.45
const WIN_HALF := 0.9
const WIN_PITCH := 3.0
const VIEW_SILL := 0.42
const VIEW_TOP := 2.6
const VIEW_HALF := 1.3
const VIEW_PITCH := 2.9
const LINTEL := 2.7  # top of the doorway light strips
const SUN_DIR := Vector3(0.55, 0.72, -0.42)
const WALL_TINT := Color(0.93, 0.93, 0.91)
const DARK := Color(0.16, 0.17, 0.19)
const GUNMETAL := Color(0.3, 0.32, 0.35)
const EMERGENCY_RED := Color(1.0, 0.1, 0.04)
const GUIDE := Color(0.45, 0.85, 1.0)
const COVE := Color(1.0, 0.9, 0.76)
const SCREEN_BLUE := Color(0.3, 0.72, 1.0)
const BEACON := Color(1.0, 0.28, 0.04)
const AO_DARK := Color(0.42, 0.42, 0.45)
const GRAPHITE := Color(0.2, 0.21, 0.23)
const BRUSHED := Color(0.62, 0.64, 0.67)
const PAPER := Color(0.93, 0.92, 0.86)
const LED_GREEN := Color(0.3, 1.0, 0.45)
const LED_AMBER := Color(1.0, 0.6, 0.12)
const FIRE_RED := Color(0.78, 0.1, 0.07)

## Floor label offsets so names don't sit under big centre props.
const LABEL_OFFSET := {"reactor": Vector2(4.3, -3.3), "command": Vector2(0, 2.6), "docking": Vector2(0, 3.0), "observation": Vector2(0, 0.2), "cargo": Vector2(0, -0.2)}
## Floor names read from the room's main entrance (direction to the reader).
const LABEL_FACING := {"reactor": Vector3(0, 0, -1), "medical": Vector3(0, 0, -1), "engineering": Vector3(-1, 0, 0), "airlock": Vector3(1, 0, 0), "observation": Vector3(-1, 0, 0)}
## Two-letter codes for door plaques ("MD-02").
const ROOM_CODES := {"commons": "CM", "command": "CD", "security": "SC", "docking": "DK", "cargo": "CG", "engineering": "EN", "reactor": "RX", "medical": "MD", "observation": "OB", "airlock": "AL"}
## Walls that become floor-to-ceiling viewports (towards the planet, north).
const VIEWPORT_WALLS := {"observation": "n", "command": "n"}
## Wall-panel feature rotation per room (picked by a stable hash per bay).
const FEATURE_SETS := {
	"default": ["screen", "vent", "stencil", "conduit", "fusebox", "blank", "extinguisher"],
	"corridor": ["stencil", "vent", "screen", "blank", "conduit", "extinguisher", "fusebox", "vent"],
	"engineering": ["conduit", "fusebox", "vent", "stencil", "conduit", "screen"],
	"reactor": ["stencil", "conduit", "screen", "vent", "fusebox"],
	"medical": ["screen", "blank", "stencil", "vent", "extinguisher"],
	"command": ["screen", "screen", "vent", "blank", "stencil"],
	"security": ["screen", "fusebox", "stencil", "vent", "screen"],
	"cargo": ["stencil", "vent", "conduit", "blank", "fusebox"],
	"docking": ["stencil", "conduit", "vent", "screen", "extinguisher"],
	"commons": ["screen", "vent", "blank", "extinguisher", "stencil"],
	"observation": ["blank", "screen", "vent", "stencil"],
	"airlock": ["stencil", "vent"],
}
const STENCILS := {
	"default": ["CAUTION", "KEEP CLEAR", "DECK 2", "O2 LINE", "LIFE SUPPORT"],
	"corridor": ["DECK 2", "KEEP CLEAR", "O2 LINE", "SERVICE", "CAUTION"],
	"engineering": ["HIGH VOLTAGE", "COOLANT", "EAR PROTECTION"],
	"reactor": ["RADIATION", "AUTHORISED ONLY", "COOLANT"],
	"medical": ["STERILE", "TRIAGE", "QUIET"],
	"command": ["BRIDGE", "AUTHORISED ONLY"],
	"security": ["RESTRICTED", "ARMORY", "NO WEAPONS"],
	"cargo": ["MAX LOAD 4T", "FORKLIFT LANE", "STACK 3 HIGH"],
	"docking": ["FUEL LINE", "PAD CLEAR", "NO SMOKING"],
	"commons": ["MESS", "RECREATION", "WASH HANDS"],
	"observation": ["VIEWING DECK", "MIND THE STEP"],
	"airlock": ["VACUUM DANGER", "CYCLE 3.5 S"],
}


static func build(parent: Node3D) -> Node3D:
	var fx := ArtStationFX.new()
	fx.name = "Station"
	parent.add_child(fx)
	var mats := _make_materials()
	for key in ArtStationFX.MATERIAL_PARAMS:
		fx.mats[key] = mats[key]
	_build_environment(fx)
	for room_id in StationLayout.ROOMS:
		_build_room(fx, mats, room_id)
	for corridor_id in StationLayout.CORRIDORS:
		_build_corridor(fx, mats, corridor_id)
	_build_exterior(fx, mats)
	_ctx_fx = null
	_ctx_node = null
	_ctx_shadow = null
	fx.set_state("emergency", 0.0)
	return fx


## Airlock: "idle", "warning" (red strobe + klaxon light), "venting" (outer door
## opens, chamber flashes, back to idle after ~2 s).
static func set_airlock_state(station: Node3D, state: String) -> void:
	var fx := _fx(station)
	if fx != null:
		fx.set_airlock_state(state)


static func _fx(station: Node3D) -> ArtStationFX:
	var fx := station as ArtStationFX
	if fx == null and station != null:
		fx = station.get_node_or_null("Station") as ArtStationFX
	if fx == null:
		push_warning("StationBuilder: not a station node")
	return fx


static func set_power_state(station: Node3D, state: String) -> void:
	var fx := _fx(station)
	if fx == null:
		return
	var duration := 1.2
	if state == "blackout":
		duration = 0.6
	elif state == "restored":
		duration = 1.5
	fx.set_state(state, duration)


# --- materials / environment ---------------------------------------------------------

## Kit remap: every light-strip key lands on the shared "lights" surface.
static func _new_kit() -> ArtMeshKit:
	var kit := ArtMeshKit.new()
	var last := float(ArtStationFX.LIGHT_GROUPS.size() - 1)
	for i in range(ArtStationFX.LIGHT_GROUPS.size()):
		kit.remap[ArtStationFX.LIGHT_GROUPS[i]] = ["lights", float(i) / last]
	return kit


static var _shadow_mat: StandardMaterial3D


static func _make_materials() -> Dictionary:
	var mats := {
		# Rubbery graphite floor mats and glossy off-white painted panels.
		"floor": ArtMaterials.world_pbr("floor_plate", Color(0.6, 0.63, 0.68), 2.0, 1.1, 0.12, 0.18),
		"wall": ArtMaterials.world_pbr("wall_panel", WALL_TINT, 2.0, 0.8, 0.35, -0.24),
		"painted": ArtMaterials.painted(),
		"metal": ArtMaterials.metal(),
		"soft": ArtMaterials.soft(),
		"glass": ArtMaterials.glass(Color(0.55, 0.75, 0.95), 0.08),
		"hazard": ArtMaterials.hazard(),
		"lights": ArtMaterials.light_groups(),
		"screen": ArtMaterials.glow(1.5, true),
		"reactor": ArtMaterials.glow(3.0, false, 1.0),
		"ao": ArtMaterials.ao(),
	}
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mats


static func _build_environment(fx: ArtStationFX) -> void:
	var sun_dir := SUN_DIR.normalized()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ArtMaterials.sky_material(sun_dir)
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Mobile's colour buffer tops out at 2.0: AgX keeps saturated emissive hues
	# (our room colours) as they brighten; glow tuned for the 2.0 range.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.set("tonemap_agx_contrast", 1.25)
	env.tonemap_white = 2.0
	env.glow_enabled = true
	env.glow_normalized = false
	for level in range(7):
		env.set_glow_level(level, [0.0, 1.0, 0.8, 0.6, 0.4, 0.0, 0.0][level])
	env.glow_strength = 1.1
	env.glow_bloom = 0.01
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.13)
	env.fog_density = 0.005
	env.fog_sky_affect = 0.0
	env.fog_height = 0.4
	env.fog_height_density = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.15
	# Dark gradients band badly in RGB10A2; debanding is cheap.
	if fx.is_inside_tree():
		fx.get_viewport().use_debanding = true
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	fx.add_child(world_env)
	fx.env = env
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	fx.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Indoors the camera is ~5 m behind the player: 30 m of shadow is plenty
	# and keeps the two cascades sharp and cheap.
	sun.directional_shadow_max_distance = 30.0
	sun.light_angular_distance = 0.6
	sun.shadow_blur = 1.2
	fx.sun = sun
	# Cool, low, shadowless fill from the opposite side: sculpts the glossy
	# toy forms and contrasts the red emergency key.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fx.add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.45, -0.3, -0.85), Vector3.UP)
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.shadow_enabled = false
	fill.light_specular = 0.8
	fx.fill = fill
	# Gas giant with an atmosphere shell, plus a small moon. Kept inside the
	# gameplay camera's far plane (1500 m).
	var centre := Vector3(30, 0, 0)
	var planet_dir := Vector3(-0.32, 0.17, -1.0).normalized()
	var radius := 380.0
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	planet.mesh = sphere
	planet.material_override = ArtMaterials.planet_material(sun_dir)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.position = centre + planet_dir * 1050.0
	planet.rotation = Vector3(0.0, 0.4, 0.38)
	fx.add_child(planet)
	var shell := MeshInstance3D.new()
	shell.name = "Atmosphere"
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = radius * 1.07
	shell_mesh.height = radius * 2.14
	shell_mesh.radial_segments = 64
	shell_mesh.rings = 32
	shell.mesh = shell_mesh
	shell.material_override = ArtMaterials.atmosphere_material(sun_dir, sqrt(1.0 - pow(1.0 / 1.07, 2.0)))
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = planet.position
	fx.add_child(shell)
	var moon := MeshInstance3D.new()
	moon.name = "Moon"
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 34.0
	moon_mesh.height = 68.0
	moon.mesh = moon_mesh
	var moon_mat := ArtMaterials.planet_material(sun_dir)
	moon_mat.set_shader_parameter("col_a", Vector3(0.62, 0.6, 0.58))
	moon_mat.set_shader_parameter("col_b", Vector3(0.42, 0.41, 0.4))
	moon_mat.set_shader_parameter("col_c", Vector3(0.5, 0.48, 0.47))
	moon_mat.set_shader_parameter("atmo", Vector3(0.05, 0.05, 0.06))
	moon.material_override = moon_mat
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.position = centre + Vector3(0.75, 0.32, -0.55).normalized() * 950.0
	fx.add_child(moon)


# --- build context ----------------------------------------------------------------------

## Set per room/corridor while it is built (decor helpers add text, spinners,
## shadow proxies and prop records through these).
static var _ctx_fx: ArtStationFX
static var _ctx_node: Node3D
static var _ctx_shadow: ArtMeshKit
static var _ctx_mats: Dictionary
static var _ctx_room := ""
static var _reserve: Array = []  # wall spans kept free of windows/features: [along_x, fixed, a0, a1]


# --- small helpers --------------------------------------------------------------------

## Point from wall-local coordinates: `along` the wall, `across` the fixed axis.
static func _v(along_x: bool, along: float, y: float, across: float) -> Vector3:
	return Vector3(along, y, across) if along_x else Vector3(across, y, along)


static func _s(along_x: bool, sa: float, sy: float, sc: float) -> Vector3:
	return Vector3(sa, sy, sc) if along_x else Vector3(sc, sy, sa)


static func _yb(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw)


static func _wbox(kit: ArtMeshKit, key: String, along_x: bool, a0: float, a1: float, y0: float, y1: float, across: float, depth: float, color: Color, color_b = null) -> void:
	var c := _v(along_x, (a0 + a1) * 0.5, (y0 + y1) * 0.5, across)
	kit.box(key, c, _s(along_x, a1 - a0, y1 - y0, depth), color, Basis.IDENTITY, color_b, 0 if along_x else 2)


## Pill-shaped light strip(s) running along a wall at height y. With `offset`
## > 0 one strip sits on each face (walls are seen from both sides).
static func _pill(kit: ArtMeshKit, key: String, along_x: bool, a0: float, a1: float, y: float, across: float, offset: float, radius: float, color: Color, color_b = null) -> void:
	var faces := [0.0] if offset <= 0.0 else [-offset, offset]
	for f in faces:
		var a := _v(along_x, a0, y, across + f)
		var b := _v(along_x, a1, y, across + f)
		if color_b is Color and color_b != color:
			var steps := maxi(1, int((a1 - a0) / 3.0))
			for i in range(steps):
				var t0 := float(i) / float(steps)
				var t1 := float(i + 1) / float(steps)
				kit.cylinder(key, a.lerp(b, t0), a.lerp(b, t1), radius, color.lerp(color_b, (t0 + t1) * 0.5), 6)
		else:
			kit.cylinder(key, a, b, radius, color, 6)
		kit.sphere(key, a, radius, color, 6)
		kit.sphere(key, b, radius, color_b if color_b is Color else color, 6)


## Collision box on layer 1. Also feeds the room's shadow proxy (tops clamped
## to just above the walls) unless `shadow` is false.
static func _collider(body: StaticBody3D, center: Vector3, size: Vector3, basis := Basis.IDENTITY, shadow := true) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)
	if shadow and _ctx_shadow != null and center.y + size.y * 0.5 > 0.05:
		var c := center
		var sz := size
		if basis == Basis.IDENTITY and c.y + sz.y * 0.5 > SHADOW_TOP:
			var bottom := maxf(c.y - sz.y * 0.5, 0.0)
			sz.y = SHADOW_TOP - bottom
			c.y = bottom + sz.y * 0.5
		_ctx_shadow.box("shadow", c, sz, Color.WHITE, basis)


static func _cyl_collider(body: StaticBody3D, center: Vector3, radius: float, height: float, shadow := true) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	if shadow and _ctx_shadow != null:
		_ctx_shadow.cylinder("shadow", center - Vector3(0, height * 0.5, 0), center + Vector3(0, height * 0.5, 0), radius, Color.WHITE, 10)


static func _body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	return body


## Records a free-standing prop's visual bounds for the collision test.
static func _reg(prop_name: String, center: Vector3, size: Vector3, yaw := 0.0) -> void:
	if _ctx_fx != null:
		_ctx_fx.props.append({"name": "%s/%s" % [_ctx_room, prop_name], "center": center, "size": size, "yaw": yaw})


## A solid bevelled block: visual, matching collider and prop record.
static func _block(kit: ArtMeshKit, body: StaticBody3D, key: String, center: Vector3, size: Vector3, color: Color, bevel := 0.05, yaw := 0.0, prop_name := "") -> void:
	var b := _yb(yaw)
	kit.bevel_box(key, center, size, bevel, color, b)
	_collider(body, center, size, b)
	if prop_name != "":
		_reg(prop_name, center, size, yaw)


## Text helper. Upright text faces `facing`; flat text lies on the floor and
## reads upright for someone standing on the `facing` side.
static func _text(kit: ArtMeshKit, key: String, s: String, pos: Vector3, facing: Vector3, height: float, color: Color, flat := false, max_width := 0.0) -> float:
	var yaw := atan2(facing.x, facing.z)
	var b := Basis.from_euler(Vector3(-PI / 2.0, yaw, 0.0), EULER_ORDER_YXZ) if flat else _yb(yaw)
	return kit.text(key, s, Transform3D(b, pos), color, height, max_width)


static func _grow(r: Rect2, by: float) -> Rect2:
	return Rect2(r.position - Vector2(by, by), r.size + Vector2(by, by) * 2.0)


## True when a flat point is inside (or right next to) any room or corridor.
static func _inside_station(p: Vector2) -> bool:
	for room_id in StationLayout.ROOMS:
		if _grow(StationLayout.room_rect(room_id), T + 0.3).has_point(p):
			return true
	for corridor_id in StationLayout.CORRIDORS:
		if _grow(StationLayout.corridor_rect(corridor_id), T + 0.3).has_point(p):
			return true
	return false


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


static func _hash(a: float, b: float, c: float) -> int:
	return absi(hash(Vector3i(roundi(a * 10.0), roundi(b * 10.0), roundi(c * 10.0))))


static func _reserved(along_x: bool, fixed: float, a0: float, a1: float) -> bool:
	for r in _reserve:
		if r[0] == along_x and absf(r[1] - fixed) < 0.05 and a1 > r[2] and a0 < r[3]:
			return true
	return false


## Soft contact shadow around a footprint (half extents `half`, rotated by yaw).
static func _ao_rect(kit: ArtMeshKit, center: Vector3, half: Vector2, yaw := 0.0, spread := 0.45, darkness := AO_DARK) -> void:
	var b := _yb(yaw)
	var y := Vector3(0, 0.005, 0)
	var inner := [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]
	var outer := [Vector3(-half.x - spread, 0, -half.y - spread), Vector3(half.x + spread, 0, -half.y - spread), Vector3(half.x + spread, 0, half.y + spread), Vector3(-half.x - spread, 0, half.y + spread)]
	var c := center + y
	kit.quad_grad("ao", c + b * inner[0], c + b * inner[1], c + b * inner[2], c + b * inner[3], Vector3.UP, darkness, darkness)
	for i in range(4):
		var j := (i + 1) % 4
		kit.quad_grad("ao", c + b * inner[i], c + b * inner[j], c + b * outer[j], c + b * outer[i], Vector3.UP, darkness, Color.WHITE)


## A separately spinning part (fan, hologram). `xform` orients the spin axis
## (local Y). Cheap: one small mesh, culled beyond 40 m, no shadows.
static func _spinner(kit: ArtMeshKit, xform: Transform3D, speed: float, bob := 0.0) -> void:
	if _ctx_node == null:
		return
	var holder := Node3D.new()
	holder.name = "Spin"
	holder.transform = xform
	_ctx_node.add_child(holder)
	var spin := Node3D.new()
	spin.set_script(SPINNER)
	spin.set("speed", speed)
	spin.set("bob", bob)
	holder.add_child(spin)
	var mi := kit.to_instance(_ctx_mats, "Mesh", false)
	mi.visibility_range_end = 40.0
	spin.add_child(mi)


static func _decal(node: Node3D, tex: String, pos: Vector2, size: float, yaw: float, mix := 0.85, tint := Color.WHITE) -> void:
	var decal := Decal.new()
	decal.texture_albedo = ArtMaterials.texture(tex)
	decal.size = Vector3(size, 1.0, size)
	decal.position = Vector3(pos.x, 0.2, pos.y)
	decal.rotation.y = yaw
	decal.albedo_mix = mix
	decal.modulate = tint
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	decal.cull_mask = 1
	node.add_child(decal)


# --- walls -----------------------------------------------------------------------------

## Builds one straight wall segment on the boundary line `fixed` (z when the wall
## runs along x, otherwise x), spanning `a0..a1`, extending `outward` (+1/-1) by T.
## Exterior stretches get windows ("viewport" style: tall panoramic panes).
## Solid stretches get panel features; long ones get wall-top services.
static func _wall(kit: ArtMeshKit, body: StaticBody3D, along_x: bool, fixed: float, a0: float, a1: float, outward: float, accent: Color, accent_b: Color, windows_ok: bool, style := "") -> Array[float]:
	var length := a1 - a0
	var mid_across := fixed + outward * T * 0.5
	# Solid from the outer face to WALL_IN inside, so wall-mounted kit is solid.
	_collider(body, _v(along_x, (a0 + a1) * 0.5, COLLIDER_TOP * 0.5, fixed + outward * (T - WALL_IN) * 0.5), _s(along_x, length, COLLIDER_TOP, T + WALL_IN))
	var viewport := style == "viewport"
	var pitch := VIEW_PITCH if viewport else WIN_PITCH
	var half := VIEW_HALF if viewport else WIN_HALF
	var sill := VIEW_SILL if viewport else SILL
	var top := VIEW_TOP if viewport else WIN_TOP
	var windows: Array[float] = []
	if windows_ok and length >= 3.0:
		var count := int(floor((length - 0.8) / pitch))
		var first := (a0 + a1) * 0.5 - float(count - 1) * pitch * 0.5
		for i in range(count):
			var w := first + float(i) * pitch
			var near := _flat(_v(along_x, w, 0.0, fixed + outward * 1.6))
			var far := _flat(_v(along_x, w, 0.0, fixed + outward * 4.5))
			if not _inside_station(near) and not _inside_station(far) and not _reserved(along_x, fixed, w - half - 0.2, w + half + 0.2):
				windows.append(w)
	var wall_c := WALL_TINT
	# Contact shadow on the floor along the inner face.
	var inner := fixed - outward * 0.004
	var reach := fixed - outward * 0.95
	kit.quad_grad("ao", _v(along_x, a0, 0.004, inner), _v(along_x, a1, 0.004, inner), _v(along_x, a1, 0.004, reach), _v(along_x, a0, 0.004, reach), Vector3.UP, AO_DARK, Color.WHITE)
	# Kickplate, main panels (with window openings), trim, upper band, cap, cove.
	kit.bevel_box("painted", _v(along_x, (a0 + a1) * 0.5, KICK * 0.5, mid_across), _s(along_x, length, KICK, T + 0.08), 0.04, GRAPHITE)
	_pill(kit, "emergency", along_x, a0 + 0.05, a1 - 0.05, 0.4, mid_across, T * 0.5 + 0.05, 0.035, EMERGENCY_RED)
	var bays: Array = []  # [start, end] of solid panel bays (for features)
	if windows.is_empty():
		_wbox(kit, "wall", along_x, a0, a1, KICK, TRIM_LO, mid_across, T, wall_c)
		var rib := ceilf((a0 + 0.5) / 2.0) * 2.0
		var cursor := a0
		while rib < a1 - 0.5:
			kit.bevel_box("painted", _v(along_x, rib, (KICK + TRIM_LO) * 0.5, mid_across), _s(along_x, 0.26, TRIM_LO - KICK, T + 0.14), 0.08, GRAPHITE)
			bays.append([cursor, rib])
			cursor = rib
			rib += 2.0
		bays.append([cursor, a1])
	else:
		var sill_c := wall_c if not viewport else GRAPHITE
		_wbox(kit, "wall" if not viewport else "painted", along_x, a0, a1, KICK, sill, mid_across, T, sill_c)
		_wbox(kit, "wall", along_x, a0, a1, top, TRIM_LO, mid_across, T, wall_c)
		var cursor := a0
		for w in windows:
			_wbox(kit, "wall", along_x, cursor, w - half, sill, top, mid_across, T, wall_c)
			if w - half - cursor >= 1.6:
				bays.append([cursor, w - half])
			cursor = w + half
			_window(kit, along_x, w, mid_across, outward, half, sill, top, viewport)
		_wbox(kit, "wall", along_x, cursor, a1, sill, top, mid_across, T, wall_c)
		if a1 - cursor >= 1.6:
			bays.append([cursor, a1])
		for i in range(windows.size() - 1):
			var pillar := (windows[i] + windows[i + 1]) * 0.5
			kit.bevel_box("painted", _v(along_x, pillar, (KICK + TRIM_LO) * 0.5, mid_across), _s(along_x, 0.26 if not viewport else 0.3, TRIM_LO - KICK, T + 0.14), 0.08, GRAPHITE)
		if viewport:
			# A lit sill ledge under the panorama.
			_wbox(kit, "metal", along_x, a0 + 0.1, a1 - 0.1, sill - 0.05, sill + 0.03, fixed - outward * 0.1, 0.24, BRUSHED)
			_pill(kit, "trim", along_x, a0 + 0.2, a1 - 0.2, sill - 0.08, fixed - outward * 0.2, 0.0, 0.025, accent.lightened(0.3))
		else:
			# Low louvred vents under every other window.
			for i in range(windows.size()):
				if (_hash(fixed, windows[i], outward) + i) % 2 == 0:
					_vent(kit, along_x, fixed, outward, windows[i], 0.62, 0.8, 0.36)
	# Bold room-colour band (toy playset livery) with a pill light strip under it.
	_wbox(kit, "painted", along_x, a0, a1, TRIM_LO - 0.02, H, mid_across, T + 0.05, accent.darkened(0.12), accent_b.darkened(0.12))
	_pill(kit, "trim", along_x, a0 + 0.05, a1 - 0.05, TRIM_LO - 0.06, mid_across, T * 0.5 + 0.045, 0.04, accent.lightened(0.25), accent_b.lightened(0.25))
	kit.bevel_box("metal", _v(along_x, (a0 + a1) * 0.5, H + 0.06, mid_across), _s(along_x, length, 0.14, T + 0.18), 0.06, BRUSHED)
	_pill(kit, "ceiling", along_x, a0 + 0.05, a1 - 0.05, H + 0.15, mid_across, 0.0, 0.035, COVE)
	if style != "bare":
		var set_key := style if style == "corridor" else _ctx_room
		var features: Array = FEATURE_SETS.get(set_key, FEATURE_SETS["default"])
		for bay in bays:
			var b0: float = bay[0]
			var b1: float = bay[1]
			if b1 - b0 < 1.3 or _reserved(along_x, fixed, b0 + 0.2, b1 - 0.2):
				continue
			var h := _hash(fixed, (b0 + b1) * 0.5, outward)
			if h % 7 == 0:
				continue
			_wall_feature(kit, along_x, fixed, outward, (b0 + b1) * 0.5, b1 - b0, features[h % features.size()], accent, set_key, h)
		if length >= 3.0 and not _reserved(along_x, fixed, a0, a1):
			_wall_top(kit, along_x, fixed, outward, a0 + 0.3, a1 - 0.3, accent, _hash(fixed, a0, a1) % 3)
	return windows


static func _window(kit: ArtMeshKit, along_x: bool, w: float, across: float, outward: float, half := WIN_HALF, sill := SILL, top := WIN_TOP, viewport := false) -> void:
	var n := _v(along_x, 0.0, 0.0, outward).normalized()
	var a := _v(along_x, w - half, sill, across)
	var b := _v(along_x, w + half, sill, across)
	var c := _v(along_x, w + half, top, across)
	var d := _v(along_x, w - half, top, across)
	kit.quad("glass", a, b, c, d, n, Color.WHITE)
	var depth := T + 0.1
	var frame := GUNMETAL if not viewport else GRAPHITE
	kit.bevel_box("metal", _v(along_x, w, sill - 0.04, across), _s(along_x, half * 2.0 + 0.2, 0.1, depth + 0.06), 0.03, frame)
	kit.bevel_box("metal", _v(along_x, w, top + 0.04, across), _s(along_x, half * 2.0 + 0.2, 0.1, depth), 0.03, frame)
	kit.bevel_box("metal", _v(along_x, w - half - 0.04, (sill + top) * 0.5, across), _s(along_x, 0.1, top - sill, depth), 0.03, frame)
	kit.bevel_box("metal", _v(along_x, w + half + 0.04, (sill + top) * 0.5, across), _s(along_x, 0.1, top - sill, depth), 0.03, frame)
	if viewport:
		# One slim horizontal transom, no centre mullion: an uninterrupted view.
		kit.box("metal", _v(along_x, w, top - 0.42, across), _s(along_x, half * 2.0, 0.05, 0.08), frame)
	else:
		kit.box("metal", _v(along_x, w, (sill + top) * 0.5, across), _s(along_x, 0.05, top - sill, 0.08), GUNMETAL)


## Louvred grille centred at `along`, `y` on the inner face of a wall.
static func _vent(kit: ArtMeshKit, along_x: bool, fixed: float, outward: float, along: float, y: float, width: float, height: float) -> void:
	var p := func(a: float, yy: float, out: float) -> Vector3: return _v(along_x, a, yy, fixed - outward * out)
	kit.bevel_box("painted", p.call(along, y, 0.02), _s(along_x, width, height, 0.05), 0.02, DARK)
	var slats := maxi(3, int(height / 0.08))
	for i in range(slats):
		var yy := y - height * 0.5 + height * (float(i) + 0.5) / float(slats)
		kit.box("metal", p.call(along, yy, 0.05), _s(along_x, width - 0.1, height / float(slats) * 0.45, 0.03), GUNMETAL)


## One panel-bay feature on a wall's inner face (depth <= WALL_IN, so the wall
## collider covers it).
static func _wall_feature(kit: ArtMeshKit, along_x: bool, fixed: float, outward: float, mid: float, bay: float, kind: String, accent: Color, set_key: String, h: int) -> void:
	var inward := _v(along_x, 0.0, 0.0, -outward).normalized()
	var p := func(a: float, y: float, out: float) -> Vector3: return _v(along_x, a, y, fixed - outward * out)
	match kind:
		"vent":
			_vent(kit, along_x, fixed, outward, mid, 0.62, minf(bay - 0.5, 1.0), 0.42)
			_vent(kit, along_x, fixed, outward, mid, 2.25, minf(bay - 0.7, 0.7), 0.3)
		"screen":
			var w := minf(bay - 0.5, 1.15)
			kit.bevel_box("painted", p.call(mid, 1.6, 0.035), _s(along_x, w, 0.7, 0.07), 0.025, DARK)
			kit.box("screen", p.call(mid, 1.63, 0.072), _s(along_x, w - 0.12, 0.52, 0.01), SCREEN_BLUE.lerp(accent, 0.35 * float(h % 3) / 2.0))
			kit.sphere("blink", p.call(mid + w * 0.5 - 0.07, 1.31, 0.075), 0.022, LED_GREEN if h % 2 == 0 else LED_AMBER, 6)
			kit.box("painted", p.call(mid, 1.2, 0.02), _s(along_x, 0.1, 0.1, 0.04), GRAPHITE)
		"conduit":
			var pc := accent.darkened(0.25) if h % 2 == 0 else Color(0.42, 0.44, 0.47)
			for k in [-1.0, 1.0]:
				var a: float = mid + k * 0.13
				kit.cylinder("painted", p.call(a, KICK, 0.065), p.call(a, TRIM_LO - 0.05, 0.065), 0.045, pc if k < 0.0 else Color(0.42, 0.44, 0.47), 8)
			for y in [0.75, 1.9, 2.5]:
				kit.box("metal", p.call(mid, y, 0.06), _s(along_x, 0.42, 0.06, 0.12), GUNMETAL)
			kit.bevel_box("painted", p.call(mid, 1.35, 0.06), _s(along_x, 0.44, 0.52, 0.11), 0.03, Color(0.62, 0.64, 0.66))
			kit.box("hazard", p.call(mid, 1.52, 0.116), _s(along_x, 0.34, 0.07, 0.01), Color.WHITE)
			kit.sphere("blink", p.call(mid - 0.12, 1.2, 0.118), 0.02, LED_GREEN, 6)
			kit.sphere("blink", p.call(mid + 0.12, 1.2, 0.118), 0.02, LED_AMBER, 6)
		"stencil":
			var words: Array = STENCILS.get(set_key, STENCILS["default"])
			var word: String = words[h % words.size()]
			var w := minf(bay - 0.4, 1.6)
			kit.box("hazard", p.call(mid, 2.02, 0.006), _s(along_x, w, 0.1, 0.012), Color.WHITE)
			_text(kit, "painted", word, p.call(mid, 1.8, 0.014), inward, 0.22, GRAPHITE, false, w)
			_text(kit, "painted", "SECTION %d-%02d" % [2 + h % 3, h % 40], p.call(mid, 1.6, 0.014), inward, 0.1, Color(0.38, 0.4, 0.43), false, w)
		"fusebox":
			kit.bevel_box("painted", p.call(mid, 1.35, 0.05), _s(along_x, 0.56, 0.78, 0.1), 0.03, Color(0.6, 0.62, 0.65))
			kit.box("painted", p.call(mid, 1.35, 0.102), _s(along_x, 0.005, 0.66, 0.006), DARK)
			for i in range(3):
				kit.sphere("blink", p.call(mid - 0.14 + float(i) * 0.14, 1.66, 0.104), 0.018, [LED_GREEN, LED_AMBER, LED_GREEN][i], 6)
			_text(kit, "painted", "PWR %d" % (h % 9 + 1), p.call(mid, 1.15, 0.103), inward, 0.08, DARK)
			kit.box("hazard", p.call(mid, 0.98, 0.103), _s(along_x, 0.46, 0.05, 0.006), Color.WHITE)
		"extinguisher":
			kit.bevel_box("painted", p.call(mid, 1.05, 0.012), _s(along_x, 0.36, 0.95, 0.024), 0.01, FIRE_RED)
			kit.cylinder("painted", p.call(mid, 0.66, 0.085), p.call(mid, 1.12, 0.085), 0.065, Color(0.88, 0.12, 0.08), 10)
			kit.sphere("painted", p.call(mid, 1.12, 0.085), 0.065, Color(0.88, 0.12, 0.08), 10, Vector3(1, 0.6, 1))
			kit.cylinder("metal", p.call(mid, 1.15, 0.085), p.call(mid, 1.24, 0.085), 0.025, GRAPHITE, 6)
			kit.box("metal", p.call(mid, 0.9, 0.04), _s(along_x, 0.16, 0.04, 0.08), GUNMETAL)
			_text(kit, "sign", "FIRE", p.call(mid, 1.4, 0.026), inward, 0.12, Color(1.0, 0.82, 0.78))
		"blank":
			kit.bevel_box("painted", p.call(mid, 1.45, 0.01), _s(along_x, minf(bay - 0.55, 1.3), 1.7, 0.02), 0.01, WALL_TINT.darkened(0.07))
			for sy in [-1.0, 1.0]:
				for sa in [-1.0, 1.0]:
					kit.sphere("metal", p.call(mid + sa * (minf(bay - 0.55, 1.3) * 0.5 - 0.06), 1.45 + sy * 0.79, 0.022), 0.018, BRUSHED, 6)


## Services along the top of a wall's inner face (never across the room).
## kind 0: two pipes on brackets, 1: cable tray, 2: square duct with flanges.
static func _wall_top(kit: ArtMeshKit, along_x: bool, fixed: float, outward: float, a0: float, a1: float, accent: Color, kind: int) -> void:
	var p := func(a: float, y: float, out: float) -> Vector3: return _v(along_x, a, y, fixed - outward * out)
	match kind:
		0:
			kit.cylinder("painted", p.call(a0, 3.0, 0.09), p.call(a1, 3.0, 0.09), 0.05, Color(0.42, 0.44, 0.47), 8)
			kit.cylinder("painted", p.call(a0, 3.11, 0.06), p.call(a1, 3.11, 0.06), 0.032, accent.darkened(0.3), 8)
			var br := a0 + 0.5
			while br < a1:
				kit.box("metal", p.call(br, 3.04, 0.07), _s(along_x, 0.06, 0.2, 0.16), GUNMETAL)
				br += 1.8
		1:
			kit.box("painted", p.call((a0 + a1) * 0.5, 2.92, 0.17), _s(along_x, a1 - a0, 0.03, 0.3), GRAPHITE)
			kit.box("painted", p.call((a0 + a1) * 0.5, 2.97, 0.31), _s(along_x, a1 - a0, 0.1, 0.02), GRAPHITE)
			var cols := [Color(0.08, 0.08, 0.09), accent.darkened(0.2), Color(0.85, 0.5, 0.1)]
			for i in range(3):
				kit.cylinder("painted", p.call(a0, 2.97, 0.08 + 0.08 * float(i)), p.call(a1, 2.97, 0.08 + 0.08 * float(i)), 0.03, cols[i], 6)
			var br := a0 + 0.4
			while br < a1:
				kit.box("metal", p.call(br, 2.84, 0.17), _s(along_x, 0.05, 0.14, 0.32), GUNMETAL)
				br += 1.5
		2:
			kit.bevel_box("painted", p.call((a0 + a1) * 0.5, 2.98, 0.17), _s(along_x, a1 - a0, 0.26, 0.3), 0.04, Color(0.7, 0.72, 0.74))
			var fl := a0 + 0.6
			while fl < a1 - 0.3:
				kit.box("metal", p.call(fl, 2.98, 0.17), _s(along_x, 0.06, 0.32, 0.36), GUNMETAL)
				fl += 1.6
			if a1 - a0 > 4.0:
				kit.box("hazard", p.call((a0 + a1) * 0.5, 2.98, 0.325), _s(along_x, 0.8, 0.1, 0.01), Color.WHITE)


static func _beacon(kit: ArtMeshKit, pos: Vector3, inward: Vector3) -> void:
	kit.bevel_box("painted", pos, Vector3(0.2, 0.12, 0.2), 0.02, DARK)
	kit.sphere("beacon", pos + inward * 0.06 + Vector3(0, 0.04, 0), 0.09, BEACON, 10, Vector3(1.0, 0.8, 1.0))


# --- doorways --------------------------------------------------------------------------

static func _doorway(fx: ArtStationFX, kit: ArtMeshKit, body: StaticBody3D, along_x: bool, fixed: float, g0: float, g1: float, outward: float, color: Color, room_id: String, dest_id: String, corridor_len: float, door_no: int) -> void:
	# No lintel: the third-person camera follows players through doorways at
	# ~3-4 m, so anything spanning the opening would fill the screen. Pylons,
	# light strips, plaques and floor signage carry the doorway instead.
	var dest: Dictionary = StationLayout.ROOMS[dest_id]
	var dest_color: Color = dest.color
	var across := fixed + outward * T * 0.5
	var depth := T + 0.3
	var top := H + 0.45
	var inward := _v(along_x, 0.0, 0.0, -outward).normalized()
	for side: float in [-1.0, 1.0]:
		var edge := g0 if side < 0.0 else g1
		var post_c := edge + side * 0.17
		kit.bevel_box("painted", _v(along_x, post_c, top * 0.5, across), _s(along_x, 0.38, top, depth + 0.04), 0.12, GRAPHITE)
		_collider(body, _v(along_x, post_c, top * 0.5, across), _s(along_x, 0.38, top, depth + 0.04))
		for face: float in [-1.0, 1.0]:
			var strip := _v(along_x, edge + side * 0.05, 0.0, across + face * (depth * 0.5 + 0.02))
			kit.cylinder("door", strip + Vector3(0, 0.2, 0), strip + Vector3(0, top - 0.25, 0), 0.04, color, 6)
			kit.sphere("door", strip + Vector3(0, 0.2, 0), 0.04, color, 6)
			kit.sphere("door", strip + Vector3(0, top - 0.25, 0), 0.04, color, 6)
		kit.sphere("door", _v(along_x, post_c, top + 0.01, across), 0.1, color, 12, Vector3(1.0, 0.4, 1.0))
		# Hazard chevrons on the jamb base.
		kit.bevel_box("hazard", _v(along_x, post_c, 0.25, across), _s(along_x, 0.4, 0.5, depth + 0.07), 0.06, Color.WHITE)
	# Room-number plaque on the room face of the right-hand pylon, with the
	# destination's colour chip under it.
	var plaque_at := _v(along_x, g1 + 0.17, 1.72, across) + inward * (depth * 0.5 + 0.035)
	kit.bevel_box("painted", plaque_at, _s(along_x, 0.32, 0.3, 0.03), 0.01, DARK)
	_text(kit, "sign", "%s-%02d" % [ROOM_CODES.get(room_id, "ST"), door_no], plaque_at + inward * 0.017 + Vector3(0, 0.04, 0), inward, 0.12, Color(0.95, 0.95, 0.92), false, 0.28)
	kit.box("door", plaque_at + inward * 0.017 + Vector3(0, -0.085, 0), _s(along_x, 0.24, 0.04, 0.005), dest_color)
	# Floor threshold: hazard plate plus lit edges and a brushed transition strip.
	_wbox(kit, "hazard", along_x, g0 + 0.05, g1 - 0.05, 0.0, 0.012, across, T - 0.12, Color.WHITE)
	for off in [-T * 0.5 + 0.03, T * 0.5 - 0.03]:
		_wbox(kit, "door", along_x, g0 + 0.05, g1 - 0.05, 0.0, 0.016, across + off, 0.05, color)
	for off in [-T * 0.5 - 0.09, T * 0.5 + 0.09]:
		_wbox(kit, "metal", along_x, g0, g1, 0.0, 0.01, across + off, 0.14, BRUSHED)
	# Floor sign just inside the room: an arrow in the destination's colour and
	# its name, readable as you walk out.
	var mid := (g0 + g1) * 0.5
	var out_dir := _v(along_x, 0.0, 0.0, outward).normalized()
	var inside := _v(along_x, mid, 0.012, fixed) - out_dir * 1.3
	_door_floor_label(kit, dest.name, inside, -out_dir, dest_color, g1 - g0)
	_floor_arrow(kit, inside + out_dir * 0.62, out_dir, 0.5, dest_color.darkened(0.15))
	if corridor_len >= 5.0:
		var outside := _v(along_x, mid, 0.012, fixed) + out_dir * (T + 1.1)
		_door_floor_label(kit, String(StationLayout.ROOMS[room_id].name), outside, out_dir, color, g1 - g0)


static func _door_floor_label(kit: ArtMeshKit, text: String, pos: Vector3, facing: Vector3, color: Color, width: float) -> void:
	_text(kit, "sign", text.to_upper(), pos, facing, 0.36, Color(color.r, color.g, color.b).lightened(0.1) * 0.85, true, width - 0.6)


## Chevron arrow lying on the floor, pointing along `dir`.
static func _floor_arrow(kit: ArtMeshKit, pos: Vector3, dir: Vector3, size: float, color: Color, key := "sign") -> void:
	var yaw := atan2(dir.x, dir.z)
	for sgn in [-1.0, 1.0]:
		var b := _yb(yaw + sgn * 0.75)
		var off := _yb(yaw) * Vector3(sgn * size * 0.22, 0, -size * 0.05)
		kit.box(key, pos + off + Vector3(0, 0.004, 0), Vector3(size * 0.16, 0.008, size * 0.62), color, b)


# --- rooms ------------------------------------------------------------------------------

static func _room_gaps(room_id: String) -> Dictionary:
	var r := StationLayout.room_rect(room_id)
	var gaps := {"n": [], "s": [], "w": [], "e": []}
	for corridor_id in StationLayout.CORRIDORS:
		var spec: Dictionary = StationLayout.CORRIDORS[corridor_id]
		if spec.a != room_id and spec.b != room_id:
			continue
		var c := StationLayout.corridor_rect(corridor_id)
		var other: String = spec.b if spec.a == room_id else spec.a
		var clen := c.size.x if _corridor_along_x(corridor_id) else c.size.y
		if absf(c.end.y - r.position.y) < 0.01:
			gaps["n"].append([c.position.x, c.end.x, other, clen])
		elif absf(c.position.y - r.end.y) < 0.01:
			gaps["s"].append([c.position.x, c.end.x, other, clen])
		elif absf(c.end.x - r.position.x) < 0.01:
			gaps["w"].append([c.position.y, c.end.y, other, clen])
		elif absf(c.position.x - r.end.x) < 0.01:
			gaps["e"].append([c.position.y, c.end.y, other, clen])
	return gaps


## Wall spans (side, a0, a1) kept clear of windows and panel features because a
## room prop is mounted or stands there.
static func _room_reservations(room_id: String) -> Array:
	match room_id:
		"commons":
			return [["e", -6.6, -4.2], ["e", 4.2, 6.6], ["s", 2.4, 5.6], ["n", -7.2, -3.4]]
		"command":
			return [["e", -25.6, -22.6], ["w", -23.8, -16.0]]
		"security":
			return [["n", 38.8, 46.0], ["e", -25.6, -20.6], ["e", -17.8, -14.0], ["s", 43.6, 47.4]]
		"docking":
			return [["s", 16.6, 22.4], ["s", 13.0, 15.8], ["s", 24.2, 27.0]]
		"engineering":
			return [["n", 56.0, 68.0], ["e", 0.6, 5.6], ["s", 56.4, 59.6], ["e", -3.6, -0.6]]
		"reactor":
			return [["e", 15.0, 18.4], ["s", 55.0, 69.0], ["w", 14.0, 16.6]]
		"medical":
			return [["w", 14.6, 20.8], ["n", -6.0, -3.0], ["n", 3.2, 6.0], ["e", 15.0, 17.6], ["s", 5.4, 7.0]]
		"observation":
			return [["s", 27.0, 34.2], ["e", 23.0, 27.0]]
		"cargo":
			return [["n", 43.0, 46.6]]
	return []


static func _build_room(fx: ArtStationFX, mats: Dictionary, room_id: String) -> void:
	var spec: Dictionary = StationLayout.ROOMS[room_id]
	var r := StationLayout.room_rect(room_id)
	var color: Color = spec.color
	var node := Node3D.new()
	node.name = "Room_" + room_id
	fx.add_child(node)
	var body := _body(node, "Collision")
	var kit := _new_kit()
	_ctx_fx = fx
	_ctx_node = node
	_ctx_shadow = ArtMeshKit.new()
	_ctx_mats = mats
	_ctx_room = room_id
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	_reserve = []
	for res in _room_reservations(room_id):
		var side: String = res[0]
		var fixed := {"n": z0, "s": z1, "w": x0, "e": x1}[side] as float
		_reserve.append([side in ["n", "s"], fixed, res[1], res[2]])
	# Floor slab (under walls too) and exterior underside.
	kit.box_mm("floor", Vector3(x0 - T, -0.25, z0 - T), Vector3(x1 + T, 0.0, z1 + T), Color.WHITE)
	kit.bevel_box("metal", Vector3((x0 + x1) * 0.5, -0.7, (z0 + z1) * 0.5), Vector3(r.size.x + T * 2.0 + 0.2, 0.9, r.size.y + T * 2.0 + 0.2), 0.12, Color(0.22, 0.23, 0.25))
	_collider(body, Vector3((x0 + x1) * 0.5, -0.25, (z0 + z1) * 0.5), Vector3(r.size.x + T * 2.0, 0.5, r.size.y + T * 2.0))
	# Walls with doorway gaps.
	var gaps := _room_gaps(room_id)
	var sides := [
		["n", true, z0, -1.0, x0 - T, x1 + T],
		["s", true, z1, 1.0, x0 - T, x1 + T],
		["w", false, x0, -1.0, z0, z1],
		["e", false, x1, 1.0, z0, z1],
	]
	var long_segments := []
	var door_no := 1
	for side in sides:
		var key: String = side[0]
		var along_x: bool = side[1]
		var fixed: float = side[2]
		var outward: float = side[3]
		var cursor: float = side[4]
		var end: float = side[5]
		var style := "viewport" if VIEWPORT_WALLS.get(room_id, "") == key else ""
		if room_id == "airlock" and key == "w":
			_airlock_outer_wall(fx, kit, body, node, fixed, cursor, end, color)
			continue
		var side_gaps: Array = gaps[key]
		side_gaps.sort_custom(func(a, b): return a[0] < b[0])
		for gap in side_gaps:
			if gap[0] - cursor > 0.05:
				_wall(kit, body, along_x, fixed, cursor, gap[0], outward, color, color, true, style)
				long_segments.append([along_x, fixed, cursor, gap[0], outward])
			_doorway(fx, kit, body, along_x, fixed, gap[0], gap[1], outward, color, room_id, gap[2], gap[3], door_no)
			door_no += 1
			cursor = gap[1]
		if end - cursor > 0.05:
			_wall(kit, body, along_x, fixed, cursor, end, outward, color, color, true, style)
			long_segments.append([along_x, fixed, cursor, end, outward])
	# Room name on the colour band of the two longest walls, beacons on them.
	long_segments.sort_custom(func(a, b): return (a[3] - a[2]) > (b[3] - b[2]))
	for i in range(mini(2, long_segments.size())):
		var seg: Array = long_segments[i]
		var along_x: bool = seg[0]
		var fixed: float = seg[1]
		var a0: float = seg[2]
		var a1: float = seg[3]
		var outward: float = seg[4]
		var inward := _v(along_x, 0.0, 0.0, -outward).normalized()
		if a1 - a0 >= 5.5:
			_text(kit, "sign", String(spec.name).to_upper(), _v(along_x, (a0 + a1) * 0.5, (TRIM_HI + H) * 0.5 - 0.02, fixed) + inward * 0.03, inward, 0.34, color.lightened(0.55) * 0.8, false, a1 - a0 - 2.0)
		if a1 - a0 >= 3.0:
			var beacon_at := (a0 + a1) * 0.5 + (a1 - a0) * 0.3
			_beacon(kit, _v(along_x, beacon_at, 2.58, fixed) + inward * 0.1, inward)
	# Floor dressing: perimeter stripe with guide lights, centre emblem, label.
	var inset := 0.65
	var stripe_c := color.darkened(0.25)
	kit.box_mm("painted", Vector3(x0 + inset, 0.0, z0 + inset), Vector3(x1 - inset, 0.008, z0 + inset + 0.18), stripe_c)
	kit.box_mm("painted", Vector3(x0 + inset, 0.0, z1 - inset - 0.18), Vector3(x1 - inset, 0.008, z1 - inset), stripe_c)
	kit.box_mm("painted", Vector3(x0 + inset, 0.0, z0 + inset), Vector3(x0 + inset + 0.18, 0.008, z1 - inset), stripe_c)
	kit.box_mm("painted", Vector3(x1 - inset - 0.18, 0.0, z0 + inset), Vector3(x1 - inset, 0.008, z1 - inset), stripe_c)
	var gx := x0 + inset + 0.09
	while gx < x1 - inset:
		kit.box("guide", Vector3(gx, 0.006, z0 + inset + 0.09), Vector3(0.1, 0.012, 0.1), GUIDE)
		kit.box("guide", Vector3(gx, 0.006, z1 - inset - 0.09), Vector3(0.1, 0.012, 0.1), GUIDE)
		gx += 1.5
	var centre3 := Vector3(spec.center.x, 0.0, spec.center.y)
	var label_off: Vector2 = LABEL_OFFSET.get(room_id, Vector2.ZERO)
	if not room_id in ["reactor", "airlock"]:
		kit.cylinder("painted", centre3, centre3 + Vector3(0, 0.006, 0), 2.3, color.darkened(0.55), 40)
		kit.torus("trim", centre3 + Vector3(0, 0.004, 0), 2.28, 2.42, color, Basis.from_scale(Vector3(1, 0.09, 1)), 48, 4)
		# Tick marks around the emblem ring (compass-rose detail).
		for i in range(16):
			var ang := TAU * float(i) / 16.0
			var tick := centre3 + Vector3(cos(ang), 0.0, sin(ang)) * 2.62
			kit.box("painted", tick + Vector3(0, 0.005, 0), Vector3(0.06, 0.01, 0.26 if i % 4 == 0 else 0.13), color.darkened(0.3), _yb(-ang + PI / 2.0))
	_text(kit, "sign", String(spec.name).to_upper(), Vector3(spec.center.x + label_off.x, 0.012, spec.center.y + label_off.y), LABEL_FACING.get(room_id, Vector3(0, 0, 1)), 0.9 if r.size.x >= 8.0 else 0.6, color * 0.8, true, minf(r.size.x, r.size.y) * 0.62)
	# Floor service hatches: two inset plates per bigger room.
	if r.size.x >= 12.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(room_id + "hatch")
		for k in range(2):
			var hp := Vector3(lerpf(x0 + 1.6, x1 - 1.6, 0.18 + 0.64 * float(k)), 0.0, z1 - 1.6 if k == 0 else z0 + 1.6)
			_floor_hatch(kit, hp, rng.randf() < 0.5)
	# Raised decks of this room, then the room-specific story props.
	_build_platforms(kit, body, room_id, color)
	match room_id:
		"command":
			_dress_command(kit, body, color)
		"security":
			_dress_security(kit, body, color)
		"commons":
			_dress_commons(kit, body, color)
		"docking":
			_dress_docking(kit, body, color)
		"cargo":
			_dress_cargo(kit, body, color)
		"engineering":
			_dress_engineering(kit, body, color)
		"reactor":
			_dress_reactor(kit, body, color)
		"medical":
			_dress_medical(kit, body, color)
		"observation":
			_dress_observation(kit, body, color)
		"airlock":
			_dress_airlock(kit, body, color)
	_finish_meshes(node, kit, mats)
	# One omni per room (no shadows), a reflection probe and a few decals.
	var light := OmniLight3D.new()
	light.name = "RoomLight"
	light.position = Vector3(spec.center.x, 2.9, spec.center.y)
	if room_id == "reactor":
		light.position = Vector3(62, 3.4, 19.3)
	light.omni_range = maxf(r.size.x, r.size.y) * 0.85
	light.omni_attenuation = 0.9
	light.shadow_enabled = false
	light.light_specular = 0.6
	light.distance_fade_enabled = true
	light.distance_fade_begin = 34.0
	light.distance_fade_length = 8.0
	node.add_child(light)
	fx.room_lights.append(light)
	fx.room_light_colors.append(color.lerp(Color.WHITE, 0.62))
	var probe := ReflectionProbe.new()
	probe.name = "Probe"
	probe.position = Vector3(spec.center.x, 1.6, spec.center.y)
	probe.size = Vector3(r.size.x + 1.0, 7.0, r.size.y + 1.0)
	probe.origin_offset = Vector3.ZERO
	probe.box_projection = true
	probe.interior = true
	probe.intensity = 0.7
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	node.add_child(probe)
	fx.probes.append(probe)
	_room_decals(node, room_id, r)
	_reserve = []


## Merged visual mesh (no shadows) plus a shadow-only proxy built from the
## collision boxes: the shadow pass draws ~12 triangles per solid instead of the
## full bevelled, text-covered detail.
static func _finish_meshes(node: Node3D, kit: ArtMeshKit, mats: Dictionary) -> void:
	node.add_child(kit.to_instance(mats, "Mesh", false))
	if _ctx_shadow != null and _ctx_shadow.vertex_count() > 0:
		var proxy := _ctx_shadow.to_instance({"shadow": _shadow_mat}, "ShadowProxy", true)
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.add_child(proxy)


## Grime in three corners, boot scuffs by the busiest doorway, and a leak under
## the room's thirstiest machine. At most six per room (Mobile: 8 per mesh).
static func _room_decals(node: Node3D, room_id: String, r: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room_id)
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	for corner in [Vector2(x0 + 1.0, z0 + 1.0), Vector2(x1 - 1.0, z1 - 1.0), Vector2(x0 + 1.0, z1 - 1.0)]:
		_decal(node, "grime_decal", corner, 3.2, rng.randf() * TAU)
	var gaps := _room_gaps(room_id)
	var scuffs := 0
	for side in ["n", "s", "w", "e"]:
		for gap in gaps[side]:
			if scuffs >= 2:
				break
			var mid: float = (gap[0] + gap[1]) * 0.5
			var at: Vector2 = {"n": Vector2(mid, z0 + 1.6), "s": Vector2(mid, z1 - 1.6), "w": Vector2(x0 + 1.6, mid), "e": Vector2(x1 - 1.6, mid)}[side]
			_decal(node, "scuff_decal", at, 2.6, rng.randf() * TAU, 0.7)
			scuffs += 1
	var leaks := {"engineering": [Vector2(59.0, -3.6), Color(0.85, 0.95, 0.7)], "cargo": [Vector2(45.3, -1.9), Color(1, 1, 1)], "docking": [Vector2(25.0, 4.0), Color(1.0, 0.85, 0.6)], "reactor": [Vector2(57.2, 16.6), Color(0.8, 0.85, 1.0)]}
	if leaks.has(room_id):
		_decal(node, "leak_decal", leaks[room_id][0], 1.5, rng.randf() * TAU, 0.9, leaks[room_id][1])


static func _floor_hatch(kit: ArtMeshKit, p: Vector3, round_lid: bool) -> void:
	kit.box("metal", p + Vector3(0, 0.004, 0), Vector3(1.05, 0.008, 1.05), GUNMETAL)
	kit.box("painted", p + Vector3(0, 0.007, 0), Vector3(0.9, 0.008, 0.9), Color(0.26, 0.27, 0.29))
	if round_lid:
		kit.cylinder("metal", p + Vector3(0, 0.004, 0), p + Vector3(0, 0.014, 0), 0.32, BRUSHED, 16)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.box("hazard", p + Vector3(sx * 0.38, 0.012, sz * 0.38), Vector3(0.12, 0.004, 0.12), Color.WHITE)
	kit.box("painted", p + Vector3(0, 0.014, 0.3), Vector3(0.22, 0.01, 0.04), DARK)


# --- platforms ------------------------------------------------------------------------------

## Raised decks from StationLayout.PLATFORMS: floor-plated top, lit nosing on
## exposed edges, railings except where ramps come up, rotated-box ramps.
static func _build_platforms(kit: ArtMeshKit, body: StaticBody3D, room_id: String, color: Color) -> void:
	var room := StationLayout.room_rect(room_id)
	for pid in StationLayout.PLATFORMS:
		var spec: Dictionary = StationLayout.PLATFORMS[pid]
		if spec.room != room_id:
			continue
		var r: Rect2 = spec.rect
		var h: float = spec.height
		var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
		kit.box("floor", c + Vector3(0, h - 0.03, 0), Vector3(r.size.x, 0.06, r.size.y), Color(0.9, 0.92, 0.96))
		kit.box("painted", c + Vector3(0, (h - 0.06) * 0.5, 0), Vector3(r.size.x - 0.02, h - 0.06, r.size.y - 0.02), GRAPHITE)
		_collider(body, c + Vector3(0, h * 0.5, 0), Vector3(r.size.x, h, r.size.y))
		# Which edges are exposed (not against a wall), and the ramp spans on them.
		var edges := {
			"n": [true, r.position.y, r.position.x, r.end.x, -1.0],
			"s": [true, r.end.y, r.position.x, r.end.x, 1.0],
			"w": [false, r.position.x, r.position.y, r.end.y, -1.0],
			"e": [false, r.end.x, r.position.y, r.end.y, 1.0],
		}
		var walls := {"n": room.position.y, "s": room.end.y, "w": room.position.x, "e": room.end.x}
		for side in edges:
			var e: Array = edges[side]
			if absf(float(e[1]) - float(walls[side])) < 0.05:
				continue
			var along_x: bool = e[0]
			var fixed: float = e[1]
			var outward: float = e[4]
			var spans: Array = [[float(e[2]), float(e[3])]]
			for ramp in spec.ramps:
				if ramp.side != side:
					continue
				var next: Array = []
				for sp in spans:
					if ramp.to <= sp[0] or ramp.from >= sp[1]:
						next.append(sp)
						continue
					if ramp.from > sp[0]:
						next.append([sp[0], ramp.from])
					if ramp.to < sp[1]:
						next.append([ramp.to, sp[1]])
				spans = next
			# Lit nosing along the whole exposed edge, hazard nosing on top.
			_wbox(kit, "trim", along_x, e[2], e[3], h - 0.07, h - 0.03, fixed + outward * 0.012, 0.025, color.lightened(0.2))
			_wbox(kit, "hazard", along_x, e[2], e[3], h, h + 0.006, fixed - outward * 0.06, 0.12, Color.WHITE)
			for sp in spans:
				if sp[1] - sp[0] < 0.2:
					continue
				var a := _v(along_x, sp[0] + 0.06, h, fixed - outward * 0.08)
				var b := _v(along_x, sp[1] - 0.06, h, fixed - outward * 0.08)
				_railing(kit, body, a, b, color)
		for i in range((spec.ramps as Array).size()):
			_ramp(kit, body, pid, i, h)


static func _ramp(kit: ArtMeshKit, body: StaticBody3D, pid: String, index: int, h: float) -> void:
	var rr: Array = StationLayout.ramp_rect(pid, index)
	var rect: Rect2 = rr[0]
	var up2: Vector2 = rr[1]
	var length: float = StationLayout.PLATFORMS[pid].ramps[index].length
	var up := Vector3(up2.x, 0, up2.y)
	var across := Vector3(-up2.y, 0, up2.x)
	var width := rect.size.y if absf(up2.x) > 0.5 else rect.size.x
	var centre := Vector3(rect.get_center().x, 0, rect.get_center().y)
	var foot := centre - up * (length * 0.5)
	var top := centre + up * (length * 0.5) + Vector3(0, h, 0)
	var slope := (top - foot).normalized()
	var normal := slope.cross(across)
	if normal.y < 0.0:
		across = -across
		normal = -normal
	var thick := 0.2
	var basis := Basis(across, normal, slope)
	var run := foot.distance_to(top) + 0.12
	var c := (foot + top) * 0.5 - normal * thick * 0.5 + slope * 0.06
	_collider(body, c, Vector3(width, thick, run), basis)
	kit.box("metal", c, Vector3(width, thick, run), Color(0.5, 0.52, 0.55), basis)
	for k in range(int(run / 0.3)):
		kit.box("painted", (foot + slope * (0.2 + 0.3 * float(k))) + normal * 0.004, Vector3(width - 0.3, 0.008, 0.06), GRAPHITE, basis)
	for sgn in [-1.0, 1.0]:
		kit.box("hazard", (foot + top) * 0.5 + across * sgn * (width * 0.5 - 0.07) + normal * 0.004, Vector3(0.12, 0.008, run - 0.1), Color.WHITE, basis)
	for sgn in [-1.0, 1.0]:
		kit.box("guide", foot + across * sgn * (width * 0.5 - 0.15) - up * 0.12 + Vector3(0, 0.006, 0), Vector3(0.1, 0.012, 0.1), GUIDE)


## Railing between two points (y = the deck top): posts, a fat top rail with a
## light strip under it, a mid rail; one thin collider box.
static func _railing(kit: ArtMeshKit, body: StaticBody3D, a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.001)
	var posts := maxi(1, int(ceil(length / 1.3)))
	for i in range(posts + 1):
		var p := a.lerp(b, float(i) / float(posts))
		kit.cylinder("painted", p, p + Vector3(0, 0.95, 0), 0.04, GRAPHITE, 8)
		kit.sphere("metal", p + Vector3(0, 0.97, 0), 0.055, BRUSHED, 8)
	kit.cylinder("painted", a + Vector3(0, 0.95, 0), b + Vector3(0, 0.95, 0), 0.045, color.darkened(0.1), 8)
	kit.cylinder("trim", a + Vector3(0, 0.88, 0), b + Vector3(0, 0.88, 0), 0.015, color.lightened(0.3), 6)
	kit.cylinder("metal", a + Vector3(0, 0.5, 0), b + Vector3(0, 0.5, 0), 0.025, BRUSHED, 6)
	var yaw := atan2(dir.x, dir.z)
	var mid := (a + b) * 0.5 + Vector3(0, 0.5, 0)
	var size := Vector3(0.1, 1.0, length + 0.1)
	_collider(body, mid, size, _yb(yaw))
	_reg("railing", mid, size, yaw)


# --- corridors ---------------------------------------------------------------------------

## A corridor runs along the axis separating its two rooms (short stubs can be
## wider than they are long, so the rect's aspect is not enough).
static func _corridor_along_x(corridor_id: String) -> bool:
	var spec: Dictionary = StationLayout.CORRIDORS[corridor_id]
	var ca: Vector2 = StationLayout.ROOMS[spec.a].center
	var cb: Vector2 = StationLayout.ROOMS[spec.b].center
	return absf(ca.x - cb.x) > absf(ca.y - cb.y)


static func _build_corridor(fx: ArtStationFX, mats: Dictionary, corridor_id: String) -> void:
	var spec: Dictionary = StationLayout.CORRIDORS[corridor_id]
	var c := StationLayout.corridor_rect(corridor_id)
	var node := Node3D.new()
	node.name = "Corridor_" + corridor_id
	fx.add_child(node)
	var body := _body(node, "Collision")
	var kit := _new_kit()
	_ctx_fx = fx
	_ctx_node = node
	_ctx_shadow = ArtMeshKit.new()
	_ctx_mats = mats
	_ctx_room = "corridor"
	_reserve = []
	var along_x := _corridor_along_x(corridor_id)
	var a0 := c.position.x if along_x else c.position.y
	var a1 := c.end.x if along_x else c.end.y
	var lo := c.position.y if along_x else c.position.x
	var hi := c.end.y if along_x else c.end.x
	var room_a: Dictionary = StationLayout.ROOMS[spec.a]
	var room_b: Dictionary = StationLayout.ROOMS[spec.b]
	var a_low: bool = (room_a.center.x if along_x else room_a.center.y) < (room_b.center.x if along_x else room_b.center.y)
	var col_lo: Color = room_a.color if a_low else room_b.color
	var col_hi: Color = room_b.color if a_low else room_a.color
	# Floor: between the two room floors (which already cover the wall thickness).
	var f0 := a0 + T
	var f1 := a1 - T
	var mid_across := (lo + hi) * 0.5
	var width := hi - lo
	kit.box("floor", _v(along_x, (f0 + f1) * 0.5, -0.125, mid_across), _s(along_x, f1 - f0, 0.25, width + T * 2.0), Color.WHITE)
	kit.bevel_box("metal", _v(along_x, (f0 + f1) * 0.5, -0.55, mid_across), _s(along_x, f1 - f0 + 0.1, 0.6, width + T * 2.0 + 0.1), 0.1, Color(0.22, 0.23, 0.25))
	_collider(body, _v(along_x, (a0 + a1) * 0.5, -0.25, mid_across), _s(along_x, a1 - a0, 0.5, width + T * 2.0))
	# Centre walkway band, two-tone towards each end's room colour.
	_wbox(kit, "painted", along_x, f0, f1, 0.0, 0.006, mid_across, 1.0, col_lo.darkened(0.72), col_hi.darkened(0.72))
	_wbox(kit, "painted", along_x, f0, f1, 0.0, 0.008, mid_across - 0.52, 0.04, col_lo.darkened(0.3), col_hi.darkened(0.3))
	_wbox(kit, "painted", along_x, f0, f1, 0.0, 0.008, mid_across + 0.52, 0.04, col_lo.darkened(0.3), col_hi.darkened(0.3))
	var d := f0 + 0.3
	while d < f1 - 0.5:
		_wbox(kit, "guide", along_x, d, d + 0.45, 0.0, 0.014, lo + 0.28, 0.06, GUIDE)
		_wbox(kit, "guide", along_x, d, d + 0.45, 0.0, 0.014, hi - 0.28, 0.06, GUIDE)
		d += 1.2
	# Two-way floor arrows: one lane heads to each room, in that room's colour.
	var length := a1 - a0
	var ch := f0 + 2.2
	while ch < f1 - 2.0:
		_floor_arrow(kit, _v(along_x, ch, 0.006, mid_across - 0.26), _v(along_x, 1.0, 0.0, 0.0).normalized(), 0.42, col_hi.darkened(0.2), "painted")
		_floor_arrow(kit, _v(along_x, ch + 0.8, 0.006, mid_across + 0.26), _v(along_x, -1.0, 0.0, 0.0).normalized(), 0.42, col_lo.darkened(0.2), "painted")
		ch += 5.0
	# Side walls (shortened by T to butt against the room walls' outer faces).
	_wall(kit, body, along_x, lo, a0 + T, a1 - T, -1.0, col_lo, col_hi, true, "corridor")
	_wall(kit, body, along_x, hi, a0 + T, a1 - T, 1.0, col_lo, col_hi, true, "corridor")
	if length >= 12.0:
		var count := int(length / 12.0)
		for i in range(count):
			var at := a0 + length * (float(i) + 0.5) / float(count)
			_beacon(kit, _v(along_x, at, 2.58, lo + 0.1), _v(along_x, 0, 0, 1).normalized())
		# One tired wall lamp per long corridor that never quite stays on.
		var lamp_at := a0 + length * 0.62
		var lamp := _v(along_x, lamp_at, 2.45, hi - 0.06)
		kit.bevel_box("painted", lamp, _s(along_x, 0.7, 0.16, 0.1), 0.03, DARK)
		kit.box("flicker", lamp + _v(along_x, 0, -0.05, -0.05), _s(along_x, 0.6, 0.05, 0.02), Color(0.9, 0.95, 1.0))
	_finish_meshes(node, kit, mats)
	if length >= 14.0:
		var light := OmniLight3D.new()
		light.name = "CorridorLight"
		light.position = _v(along_x, (a0 + a1) * 0.5, 2.8, mid_across)
		light.omni_range = minf(length * 0.55, 14.0)
		light.omni_attenuation = 1.0
		light.light_specular = 0.4
		light.distance_fade_enabled = true
		light.distance_fade_begin = 34.0
		light.distance_fade_length = 8.0
		node.add_child(light)
		fx.room_lights.append(light)
		fx.room_light_colors.append(col_lo.lerp(col_hi, 0.5).lerp(Color.WHITE, 0.75))


# --- decor helpers ------------------------------------------------------------------------

## Console desk: front faces +Z rotated by `yaw`. `pos` is floor centre.
static func _console(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, width: float, screen_color: Color, accent: Color) -> void:
	var b := _yb(yaw)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.45, 0), Vector3(width, 0.9, 0.7), 0.05, DARK)
	kit.box("trim", pos + b * Vector3(0, 0.12, 0.351), Vector3(width - 0.2, 0.03, 0.01), accent)
	var tilt := b * Basis(Vector3.RIGHT, 0.45)
	kit.bevel_box("metal", pos + b * Vector3(0, 0.98, 0.05), Vector3(width, 0.08, 0.6), 0.02, GUNMETAL, tilt)
	kit.box("screen", pos + b * Vector3(0, 1.03, 0.07), Vector3(width - 0.3, 0.02, 0.42), screen_color, tilt)
	# Button strip and status LEDs along the front lip.
	for i in range(int(width / 0.25)):
		var bx := -width * 0.5 + 0.2 + float(i) * 0.25
		kit.box("blink" if i % 3 == 0 else "painted", pos + b * Vector3(bx, 0.86, 0.36), Vector3(0.1, 0.03, 0.02), [LED_GREEN, Color(0.25, 0.27, 0.3), LED_AMBER][i % 3])
	# Upright monitors on the back edge.
	var monitors := maxi(1, int(width / 1.2))
	for i in range(monitors):
		var mx := -width * 0.5 + width * (float(i) + 0.5) / float(monitors)
		kit.bevel_box("painted", pos + b * Vector3(mx, 1.45, -0.26), Vector3(1.0, 0.62, 0.08), 0.02, DARK)
		kit.box("screen", pos + b * Vector3(mx, 1.45, -0.215), Vector3(0.9, 0.52, 0.01), screen_color.lerp(Color(1, 0.75, 0.3), 0.3 * float(i % 2)))
		kit.box("metal", pos + b * Vector3(mx, 1.05, -0.28), Vector3(0.08, 0.3, 0.06), GUNMETAL)
	var cc := pos + b * Vector3(0, 0.6, -0.02)
	_collider(body, cc, Vector3(width, 1.2, 0.76), b)
	_reg("console", pos + b * Vector3(0, 0.45, 0), Vector3(width, 0.9, 0.7), yaw)
	_ao_rect(kit, pos, Vector2(width * 0.5, 0.36), yaw)


static func _crate(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, size: Vector3, color: Color, yaw := 0.0, number := "") -> void:
	var b := _yb(yaw)
	var c := pos + Vector3(0, size.y * 0.5, 0)
	# Chunky rounded toy crate: soft-bevelled body, brushed bumper bands.
	kit.bevel_box("painted", c, size, minf(0.14, size.y * 0.15), color, b)
	for sy in [-1.0, 1.0]:
		kit.bevel_box("metal", c + b * Vector3(0, sy * (size.y * 0.5 - 0.1), 0), Vector3(size.x + 0.05, 0.12, size.z + 0.05), 0.05, BRUSHED, b)
	kit.bevel_box("hazard", c + b * Vector3(-size.x * 0.25, 0.0, size.z * 0.5 + 0.01), Vector3(size.x * 0.32, 0.16, 0.04), 0.02, Color.WHITE, b)
	_collider(body, c, size + Vector3(0.04, 0, 0.04), b)
	_reg("crate", c, size, yaw)
	if pos.y < 0.05:
		_ao_rect(kit, pos, Vector2(size.x, size.z) * 0.5, yaw, 0.35)
	if number != "":
		var face := b * Vector3(0, 0, 1)
		_text(kit, "painted", number, c + b * Vector3(size.x * 0.18, 0.05, size.z * 0.5 + 0.035), face, 0.2, PAPER)


static func _tank(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, radius: float, height: float, color: Color) -> void:
	kit.cylinder("painted", pos + Vector3(0, 0.15, 0), pos + Vector3(0, height - radius * 0.4, 0), radius, color, 20)
	kit.sphere("painted", pos + Vector3(0, height - radius * 0.4, 0), radius, color, 20, Vector3(1, 0.4, 1))
	kit.cylinder("metal", pos, pos + Vector3(0, 0.18, 0), radius + 0.06, GUNMETAL, 20)
	for band_y in [height * 0.3, height * 0.7]:
		kit.cylinder("metal", pos + Vector3(0, band_y - 0.05, 0), pos + Vector3(0, band_y + 0.05, 0), radius + 0.025, GUNMETAL, 20)
	kit.cylinder("guide", pos + Vector3(0, height * 0.5 - 0.02, 0), pos + Vector3(0, height * 0.5 + 0.02, 0), radius + 0.01, Color(0.3, 1.0, 0.6), 20)
	_cyl_collider(body, pos + Vector3(0, height * 0.5, 0), radius + 0.06, height)
	_reg("tank", pos + Vector3(0, height * 0.5, 0), Vector3(radius * 2.0 + 0.12, height, radius * 2.0 + 0.12))
	_ao_rect(kit, pos, Vector2(radius, radius) * 0.75, 0.0, radius * 0.8)


static func _pipe_run(kit: ArtMeshKit, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	kit.cylinder("painted", a, b, radius, color, 10)
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var f := 1.0
	while f < length - 0.5:
		kit.cylinder("metal", a + dir * (f - 0.04), a + dir * (f + 0.04), radius * 1.45, GUNMETAL, 10)
		f += 2.0


## Sagging cable between two points (catenary-ish polyline of thin cylinders).
static func _cable(kit: ArtMeshKit, a: Vector3, b: Vector3, sag: float, radius: float, color: Color) -> void:
	var steps := 8
	var prev := a
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		kit.cylinder("painted", prev, p, radius, color, 6)
		prev = p


static func _valve_wheel(kit: ArtMeshKit, pos: Vector3, axis_basis: Basis, radius: float, color: Color) -> void:
	kit.torus("painted", pos, radius - 0.03, radius + 0.02, color, axis_basis, 16, 6)
	for k in range(3):
		var ang := TAU * float(k) / 3.0
		var spoke := axis_basis * Vector3(cos(ang), 0, sin(ang)) * radius
		kit.cylinder("painted", pos, pos + spoke, 0.012, color, 4)
	kit.cylinder("metal", pos - axis_basis * Vector3(0, 0.04, 0), pos + axis_basis * Vector3(0, 0.03, 0), 0.04, GUNMETAL, 8)


## Swivel chair facing local +Z rotated by yaw.
static func _chair(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, color: Color) -> void:
	var b := _yb(yaw)
	kit.cylinder("metal", pos, pos + Vector3(0, 0.05, 0), 0.26, GUNMETAL, 10)
	kit.cylinder("metal", pos + Vector3(0, 0.05, 0), pos + Vector3(0, 0.42, 0), 0.04, BRUSHED, 6)
	kit.bevel_box("soft", pos + Vector3(0, 0.47, 0), Vector3(0.5, 0.1, 0.48), 0.04, color, b)
	kit.bevel_box("soft", pos + b * Vector3(0, 0.8, -0.22), Vector3(0.46, 0.52, 0.08), 0.04, color, b)
	kit.box("metal", pos + b * Vector3(0, 0.55, -0.22), Vector3(0.06, 0.16, 0.04), GUNMETAL, b)
	_collider(body, pos + Vector3(0, 0.53, 0), Vector3(0.5, 1.06, 0.5), b)
	_reg("chair", pos + Vector3(0, 0.53, 0), Vector3(0.5, 1.06, 0.5), yaw)
	_ao_rect(kit, pos, Vector2(0.2, 0.2), yaw, 0.2)


## Lounge sofa, seat facing local +Z rotated by yaw; `pos` is the floor centre.
static func _sofa(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, length: float, color: Color) -> void:
	var b := _yb(yaw)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.12, 0), Vector3(length, 0.22, 0.82), 0.05, GRAPHITE, b)
	var seats := maxi(1, int(round(length / 0.8)))
	var arm := 0.16
	var inner := length - arm * 2.0
	for i in range(seats):
		var sx := -inner * 0.5 + inner * (float(i) + 0.5) / float(seats)
		kit.bevel_box("soft", pos + b * Vector3(sx, 0.32, 0.06), Vector3(inner / float(seats) - 0.03, 0.18, 0.66), 0.07, color, b)
		kit.bevel_box("soft", pos + b * Vector3(sx, 0.62, -0.3), Vector3(inner / float(seats) - 0.03, 0.46, 0.2), 0.08, color.darkened(0.08), b)
	for sx in [-1.0, 1.0]:
		kit.bevel_box("soft", pos + b * Vector3(sx * (length * 0.5 - arm * 0.5), 0.36, 0.0), Vector3(arm, 0.5, 0.82), 0.06, color.darkened(0.15), b)
	kit.box("trim", pos + b * Vector3(0, 0.05, 0.412), Vector3(length - 0.3, 0.02, 0.01), color.lightened(0.4))
	_collider(body, pos + b * Vector3(0, 0.3, 0.0), Vector3(length, 0.6, 0.82), b)
	_collider(body, pos + b * Vector3(0, 0.62, -0.3), Vector3(length, 0.64, 0.22), b, false)
	_reg("sofa", pos + b * Vector3(0, 0.425, 0), Vector3(length, 0.85, 0.82), yaw)
	_ao_rect(kit, pos, Vector2(length * 0.5, 0.41), yaw, 0.3)


## Planter box with clustered rounded foliage (soft spheres); collider covers
## the box and the bushy part a player would brush.
static func _planter(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, size: Vector2, height: float, seed_value: int, flower := Color(0.75, 0.55, 1.0)) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	kit.bevel_box("painted", pos + Vector3(0, height * 0.5, 0), Vector3(size.x, height, size.y), 0.05, DARK)
	kit.box("trim", pos + Vector3(0, height - 0.05, 0), Vector3(size.x + 0.01, 0.025, size.y + 0.01), flower.lerp(Color.WHITE, 0.3))
	kit.box("soft", pos + Vector3(0, height + 0.005, 0), Vector3(size.x - 0.1, 0.02, size.y - 0.1), Color(0.18, 0.12, 0.08))
	var count := int(maxf(size.x, size.y) / 0.32)
	var long_x := size.x >= size.y
	for i in range(count):
		var t := (float(i) + 0.5) / float(count) - 0.5
		var o := Vector3(t * (size.x - 0.25), 0, rng.randf_range(-0.1, 0.1)) if long_x else Vector3(rng.randf_range(-0.1, 0.1), 0, t * (size.y - 0.25))
		var leaf := Color(0.16, 0.42, 0.18).lerp(Color(0.38, 0.62, 0.2), rng.randf())
		kit.sphere("soft", pos + o + Vector3(0, height + 0.18 + rng.randf() * 0.18, 0), rng.randf_range(0.18, 0.27), leaf, 8, Vector3(1, 1.3, 1))
		if rng.randf() < 0.35:
			kit.sphere("soft", pos + o + Vector3(rng.randf_range(-0.1, 0.1), height + 0.45 + rng.randf() * 0.15, rng.randf_range(-0.08, 0.08)), 0.06, flower, 6)
	_collider(body, pos + Vector3(0, (height + 0.45) * 0.5, 0), Vector3(size.x, height + 0.45, size.y))
	_reg("planter", pos + Vector3(0, height * 0.5, 0), Vector3(size.x, height, size.y))
	_ao_rect(kit, pos, size * 0.5, 0.0, 0.3)


## Tall potted plant (round pot, layered leaf balls).
static func _potted_plant(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	kit.cylinder("painted", pos, pos + Vector3(0, 0.55, 0), 0.24, Color(0.85, 0.84, 0.8), 14, 0.3)
	kit.torus("trim", pos + Vector3(0, 0.5, 0), 0.27, 0.31, Color(0.9, 0.75, 0.45), Basis.IDENTITY, 14, 4)
	kit.cylinder("soft", pos + Vector3(0, 0.55, 0), pos + Vector3(0, 1.0, 0), 0.03, Color(0.3, 0.22, 0.14), 5)
	for i in range(5):
		var ang := TAU * float(i) / 5.0 + rng.randf()
		kit.sphere("soft", pos + Vector3(cos(ang) * 0.2, 0.95 + rng.randf() * 0.5, sin(ang) * 0.2), rng.randf_range(0.2, 0.28), Color(0.15, 0.45, 0.2).lerp(Color(0.35, 0.6, 0.22), rng.randf()), 8, Vector3(1, 1.25, 1))
	_cyl_collider(body, pos + Vector3(0, 0.75, 0), 0.32, 1.5)
	_reg("plant", pos + Vector3(0, 0.75, 0), Vector3(0.64, 1.5, 0.64))
	_ao_rect(kit, pos, Vector2(0.22, 0.22), 0.0, 0.25)


## Full-height structural pillar with lit corner strips (sightline breaker).
static func _pillar(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, w: float, color: Color) -> void:
	kit.bevel_box("painted", pos + Vector3(0, H * 0.5, 0), Vector3(w, H, w), 0.08, GRAPHITE)
	kit.bevel_box("painted", pos + Vector3(0, 0.15, 0), Vector3(w + 0.1, 0.3, w + 0.1), 0.05, DARK)
	kit.bevel_box("painted", pos + Vector3(0, H - 0.25, 0), Vector3(w + 0.1, 0.5, w + 0.1), 0.06, color.darkened(0.12))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := pos + Vector3(sx * (w * 0.5 + 0.005), 0, sz * (w * 0.5 + 0.005))
			kit.box("trim", corner + Vector3(0, 1.55, 0), Vector3(0.03, 2.1, 0.03), color.lightened(0.25))
	kit.box("hazard", pos + Vector3(0, 0.55, 0), Vector3(w + 0.02, 0.2, w + 0.02), Color.WHITE)
	_collider(body, pos + Vector3(0, COLLIDER_TOP * 0.5, 0), Vector3(w + 0.1, COLLIDER_TOP, w + 0.1))
	_reg("pillar", pos + Vector3(0, H * 0.5, 0), Vector3(w + 0.1, H, w + 0.1))
	_ao_rect(kit, pos, Vector2(w, w) * 0.55, 0.0, 0.35)


## Vending machine, front +Z rotated by yaw.
static func _vending(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, shell: Color, glow: Color, brand: String) -> void:
	var b := _yb(yaw)
	kit.bevel_box("painted", pos + Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 0.82), 0.07, shell, b)
	kit.bevel_box("painted", pos + b * Vector3(0, 1.88, 0.0), Vector3(1.02, 0.24, 0.84), 0.06, shell.lightened(0.25), b)
	_text(kit, "sign", brand, pos + b * Vector3(0, 1.88, 0.425), b * Vector3(0, 0, 1), 0.16, glow.lightened(0.3), false, 0.85)
	kit.box("screen", pos + b * Vector3(-0.1, 1.15, 0.412), Vector3(0.62, 1.1, 0.01), glow)
	for i in range(4):
		kit.box("metal", pos + b * Vector3(-0.1, 0.7 + float(i) * 0.27, 0.42), Vector3(0.62, 0.02, 0.02), BRUSHED, b)
	kit.bevel_box("painted", pos + b * Vector3(0.36, 1.2, 0.42), Vector3(0.18, 0.5, 0.03), 0.01, DARK, b)
	kit.sphere("blink", pos + b * Vector3(0.36, 1.38, 0.44), 0.025, LED_GREEN, 6)
	kit.box("painted", pos + b * Vector3(0.36, 1.12, 0.437), Vector3(0.06, 0.12, 0.005), Color(0.05, 0.05, 0.06), b)
	kit.bevel_box("painted", pos + b * Vector3(-0.1, 0.36, 0.42), Vector3(0.66, 0.24, 0.04), 0.02, Color(0.08, 0.08, 0.09), b)
	_collider(body, pos + Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 0.84), b)
	_reg("vending", pos + Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 0.82), yaw)
	_ao_rect(kit, pos, Vector2(0.5, 0.41), yaw, 0.35)


## Bank of lockers along local X, doors facing +Z rotated by yaw.
static func _lockers(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, count: int, color: Color, accent: Color) -> void:
	var b := _yb(yaw)
	var w := 0.62
	var total := w * float(count)
	for i in range(count):
		var lx := -total * 0.5 + w * (float(i) + 0.5)
		var shade := color.lerp(GUNMETAL, 0.35 * float(i % 2))
		kit.bevel_box("painted", pos + b * Vector3(lx, 1.02, 0), Vector3(w - 0.02, 2.04, 0.56), 0.03, shade, b)
		for v in range(4):
			kit.box("painted", pos + b * Vector3(lx, 1.62 + float(v) * 0.07, 0.282), Vector3(0.36, 0.025, 0.01), DARK, b)
		kit.box("metal", pos + b * Vector3(lx + w * 0.32, 1.0, 0.29), Vector3(0.03, 0.22, 0.03), BRUSHED, b)
		kit.box("painted", pos + b * Vector3(lx, 1.32, 0.283), Vector3(0.24, 0.1, 0.005), PAPER, b)
		_text(kit, "painted", "%02d" % (i + 1), pos + b * Vector3(lx, 1.32, 0.287), b * Vector3(0, 0, 1), 0.08, DARK)
		kit.box("trim", pos + b * Vector3(lx, 0.12, 0.282), Vector3(w - 0.12, 0.03, 0.01), accent)
	kit.bevel_box("painted", pos + b * Vector3(0, 2.09, 0), Vector3(total + 0.04, 0.08, 0.6), 0.02, DARK, b)
	_collider(body, pos + Vector3(0, 1.065, 0), Vector3(total, 2.13, 0.58), b)
	_reg("lockers", pos + Vector3(0, 1.065, 0), Vector3(total, 2.13, 0.58), yaw)
	_ao_rect(kit, pos, Vector2(total * 0.5, 0.29), yaw, 0.3)


## Bed with its head toward local -Z rotated by yaw; `pos` is the bed's floor centre.
static func _bed(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, color: Color) -> void:
	var b := _yb(yaw)
	kit.bevel_box("metal", pos + Vector3(0, 0.3, 0), Vector3(0.95, 0.12, 2.0), 0.03, GUNMETAL, b)
	for sx in [-0.4, 0.4]:
		for sz in [-0.9, 0.9]:
			kit.cylinder("metal", pos + b * Vector3(sx, 0, sz), pos + b * Vector3(sx, 0.3, sz), 0.035, GUNMETAL, 6)
			kit.sphere("painted", pos + b * Vector3(sx, 0.04, sz), 0.05, GRAPHITE, 6)
	kit.bevel_box("soft", pos + b * Vector3(0, 0.44, 0.02), Vector3(0.88, 0.16, 1.9), 0.06, Color(0.85, 0.88, 0.9), b)
	kit.bevel_box("soft", pos + b * Vector3(0, 0.55, -0.72), Vector3(0.6, 0.1, 0.35), 0.05, Color.WHITE, b)
	kit.bevel_box("soft", pos + b * Vector3(0, 0.53, 0.35), Vector3(0.92, 0.06, 1.15), 0.03, color.darkened(0.35), b)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.6, -1.0), Vector3(0.95, 1.2, 0.08), 0.03, Color(0.86, 0.88, 0.9), b)
	kit.box("screen", pos + b * Vector3(0.0, 0.95, -0.955), Vector3(0.5, 0.25, 0.01), Color(0.4, 1.0, 0.55), b)
	kit.sphere("breathe", pos + b * Vector3(0.36, 1.12, -0.955), 0.03, LED_GREEN, 6)
	# Foot rail.
	kit.cylinder("metal", pos + b * Vector3(-0.42, 0.62, 0.98), pos + b * Vector3(0.42, 0.62, 0.98), 0.025, BRUSHED, 6)
	_collider(body, pos + b * Vector3(0, 0.35, -0.02), Vector3(0.97, 0.7, 2.06), b)
	_collider(body, pos + b * Vector3(0, 0.6, -1.0), Vector3(0.97, 1.2, 0.1), b, false)
	_reg("bed", pos + Vector3(0, 0.35, 0), Vector3(0.95, 0.7, 2.0), yaw)
	_ao_rect(kit, pos, Vector2(0.45, 0.95), yaw, 0.35)


## Square holo-table base with a separately spinning hologram above it.
static func _holo_table(kit: ArtMeshKit, body: StaticBody3D, holo: Vector3, color: Color, planet := true) -> void:
	kit.cylinder("painted", holo, holo + Vector3(0, 0.85, 0), 0.45, DARK, 16, 0.55)
	kit.cylinder("metal", holo + Vector3(0, 0.85, 0), holo + Vector3(0, 0.95, 0), 0.95, GUNMETAL, 24)
	kit.cylinder("screen", holo + Vector3(0, 0.951, 0), holo + Vector3(0, 0.956, 0), 0.8, SCREEN_BLUE.darkened(0.3), 24)
	kit.torus("trim", holo + Vector3(0, 0.96, 0), 0.82, 0.9, color, Basis.IDENTITY, 32, 4)
	for i in range(6):
		var ang := TAU * float(i) / 6.0
		kit.sphere("blink", holo + Vector3(cos(ang) * 0.93, 0.9, sin(ang) * 0.93), 0.025, SCREEN_BLUE, 6)
	_cyl_collider(body, holo + Vector3(0, 0.5, 0), 0.95, 1.0)
	_reg("holo_table", holo + Vector3(0, 0.5, 0), Vector3(1.9, 1.0, 1.9))
	_ao_rect(kit, holo, Vector2(0.5, 0.5), 0.0, 0.5)
	var spin := _new_kit()
	if planet:
		spin.sphere("screen", Vector3.ZERO, 0.3, SCREEN_BLUE, 16)
		spin.torus("trim", Vector3.ZERO, 0.46, 0.5, color.lightened(0.3), Basis(Vector3.RIGHT, 0.35), 32, 4)
		spin.sphere("screen", Vector3(0.62, 0.08, 0), 0.07, Color(1.0, 0.8, 0.5), 8)
	else:
		spin.torus("trim", Vector3.ZERO, 0.32, 0.36, color.lightened(0.3), Basis.IDENTITY, 24, 4)
		spin.torus("screen", Vector3.ZERO, 0.2, 0.23, SCREEN_BLUE, Basis(Vector3.RIGHT, PI / 2.0), 24, 4)
	_spinner(spin, Transform3D(Basis.IDENTITY, holo + Vector3(0, 1.45, 0)), 0.45, 0.03)


## A box fan in a shroud: the blades spin. `xform` puts the fan axis on local Y.
static func _fan(kit: ArtMeshKit, xform: Transform3D, radius: float, speed: float) -> void:
	kit.torus("painted", xform.origin, radius, radius + 0.08, DARK, xform.basis, 24, 6)
	for k in range(4):
		var ang := TAU * float(k) / 4.0 + PI / 4.0
		kit.cylinder("metal", xform.origin, xform * (Vector3(cos(ang), 0.02, sin(ang)) * radius), 0.012, GUNMETAL, 4)
	var blades := _new_kit()
	blades.cylinder("painted", Vector3(0, -0.05, 0), Vector3(0, 0.05, 0), radius * 0.22, GRAPHITE, 12)
	blades.sphere("blink", Vector3(0, 0.06, 0), radius * 0.08, LED_AMBER, 6)
	for k in range(5):
		var ang := TAU * float(k) / 5.0
		var bb := Basis(Vector3.UP, -ang) * Basis(Vector3.RIGHT, 0.35)
		blades.bevel_box("painted", Basis(Vector3.UP, -ang) * Vector3(radius * 0.55, 0, 0), Vector3(radius * 0.72, 0.02, radius * 0.32), 0.01, Color(0.75, 0.77, 0.8), bb)
	_spinner(blades, xform, speed)


## Generator: housing with cooling fins, a top fan, gauges, a stencil plate.
## Front faces +Z rotated by yaw.
static func _generator(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, size: Vector3, color: Color, accent: Color, code: String) -> void:
	var b := _yb(yaw)
	var c := pos + Vector3(0, size.y * 0.5, 0)
	kit.bevel_box("painted", c, size, 0.08, color, b)
	kit.bevel_box("painted", pos + Vector3(0, 0.08, 0), Vector3(size.x + 0.12, 0.16, size.z + 0.12), 0.04, GRAPHITE, b)
	for i in range(7):
		var fx := -size.x * 0.5 + 0.25 + float(i) * (size.x - 0.5) / 6.0
		kit.box("metal", pos + b * Vector3(fx, size.y * 0.55, size.z * 0.5 + 0.02), Vector3(0.05, size.y * 0.5, 0.05), GUNMETAL, b)
	kit.box("hazard", pos + b * Vector3(0, 0.3, size.z * 0.5 + 0.005), Vector3(size.x - 0.1, 0.18, 0.01), Color.WHITE, b)
	kit.box("screen", pos + b * Vector3(-size.x * 0.32, size.y * 0.82, size.z * 0.5 + 0.005), Vector3(0.55, 0.3, 0.01), Color(0.4, 1.0, 0.5), b)
	for i in range(2):
		var gp := pos + b * Vector3(size.x * 0.1 + float(i) * 0.32, size.y * 0.82, size.z * 0.5 + 0.02)
		kit.cylinder("metal", gp - b * Vector3(0, 0, 0.02), gp + b * Vector3(0, 0, 0.02), 0.12, BRUSHED, 14)
		kit.cylinder("screen", gp + b * Vector3(0, 0, 0.021), gp + b * Vector3(0, 0, 0.025), 0.1, PAPER, 14)
	kit.sphere("blink", pos + b * Vector3(size.x * 0.42, size.y * 0.9, size.z * 0.5 + 0.01), 0.03, LED_GREEN, 6)
	kit.sphere("blink", pos + b * Vector3(size.x * 0.42, size.y * 0.8, size.z * 0.5 + 0.01), 0.03, LED_AMBER, 6)
	_text(kit, "painted", code, pos + b * Vector3(-size.x * 0.32, size.y * 0.6, size.z * 0.5 + 0.012), b * Vector3(0, 0, 1), 0.14, accent.darkened(0.5))
	# Top fan with a guard ring.
	kit.cylinder("painted", c + Vector3(0, size.y * 0.5, 0), c + Vector3(0, size.y * 0.5 + 0.12, 0), minf(size.x, size.z) * 0.36, GRAPHITE, 20)
	_fan(kit, Transform3D(Basis.IDENTITY, c + Vector3(0, size.y * 0.5 + 0.14, 0)), minf(size.x, size.z) * 0.3, 7.0)
	_collider(body, c, size + Vector3(0.12, 0, 0.12), b)
	_reg("generator", c, size, yaw)
	_ao_rect(kit, pos, Vector2(size.x, size.z) * 0.5, yaw, 0.45)


## Forklift, forks towards local +Z rotated by yaw.
static func _forklift(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float) -> void:
	var b := _yb(yaw)
	var yellow := Color(0.95, 0.68, 0.12)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.55, 0), Vector3(1.1, 0.7, 1.4), 0.1, yellow, b)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.6, -0.78), Vector3(1.1, 0.6, 0.32), 0.1, GRAPHITE, b)
	kit.box("hazard", pos + b * Vector3(0, 0.62, -0.945), Vector3(0.9, 0.2, 0.01), Color.WHITE, b)
	for sx in [-1.0, 1.0]:
		for sz in [-0.45, 0.45]:
			var wc := pos + b * Vector3(sx * 0.55, 0.22, sz)
			kit.cylinder("painted", wc - b * Vector3(0.09, 0, 0), wc + b * Vector3(0.09, 0, 0), 0.22, Color(0.1, 0.1, 0.11), 14)
			kit.cylinder("metal", wc + b * Vector3(sx * 0.09, 0, 0), wc + b * Vector3(sx * 0.1, 0, 0), 0.11, BRUSHED, 10)
	for sx in [-0.46, 0.46]:
		for sz in [-0.45, 0.4]:
			kit.cylinder("painted", pos + b * Vector3(sx, 0.9, sz), pos + b * Vector3(sx, 2.0, sz), 0.035, GRAPHITE, 6)
	kit.bevel_box("painted", pos + b * Vector3(0, 2.02, 0), Vector3(1.0, 0.06, 0.95), 0.02, GRAPHITE, b)
	kit.sphere("blink", pos + b * Vector3(0.3, 2.1, -0.3), 0.07, LED_AMBER, 8)
	kit.bevel_box("soft", pos + b * Vector3(0, 1.0, -0.2), Vector3(0.5, 0.12, 0.45), 0.04, Color(0.15, 0.15, 0.17), b)
	kit.bevel_box("soft", pos + b * Vector3(0, 1.3, -0.42), Vector3(0.5, 0.5, 0.1), 0.04, Color(0.15, 0.15, 0.17), b)
	kit.torus("painted", pos + b * Vector3(0, 1.3, 0.35), 0.13, 0.16, GRAPHITE, b * Basis(Vector3.RIGHT, -0.9), 14, 4)
	for sx in [-0.3, 0.3]:
		kit.box("metal", pos + b * Vector3(sx, 1.1, 0.78), Vector3(0.08, 2.2, 0.1), GUNMETAL, b)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.45, 0.86), Vector3(0.8, 0.5, 0.06), 0.02, GRAPHITE, b)
	for sx in [-0.25, 0.25]:
		kit.box("metal", pos + b * Vector3(sx, 0.08, 1.35), Vector3(0.12, 0.05, 1.0), BRUSHED, b)
	_collider(body, pos + b * Vector3(0, 1.03, -0.05), Vector3(1.24, 2.06, 1.9), b)
	_collider(body, pos + b * Vector3(0, 0.1, 1.35), Vector3(0.72, 0.2, 1.0), b)
	_reg("forklift", pos + b * Vector3(0, 1.03, -0.05), Vector3(1.24, 2.06, 1.9), yaw)
	_ao_rect(kit, pos + b * Vector3(0, 0, 0.2), Vector2(0.6, 1.2), yaw, 0.4)


static func _pallet(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float) -> void:
	var b := _yb(yaw)
	var wood := Color(0.62, 0.45, 0.28)
	for sx in [-0.5, 0.0, 0.5]:
		kit.box("painted", pos + b * Vector3(sx, 0.05, 0), Vector3(0.12, 0.1, 1.0), wood.darkened(0.15), b)
	for i in range(5):
		kit.box("painted", pos + b * Vector3(0, 0.12, -0.42 + float(i) * 0.21), Vector3(1.2, 0.04, 0.15), wood, b)
	_collider(body, pos + Vector3(0, 0.07, 0), Vector3(1.2, 0.14, 1.0), b)


## Pegboard of tools on a wall plus a rolling tool chest in front of it.
## Front faces +Z rotated by yaw; `pos` is the floor point at the wall face.
static func _tool_wall(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, width: float, accent: Color) -> void:
	var b := _yb(yaw)
	kit.bevel_box("painted", pos + b * Vector3(0, 1.75, 0.03), Vector3(width, 1.1, 0.04), 0.01, Color(0.36, 0.38, 0.4), b)
	for i in range(int(width / 0.12)):
		for j in range(8):
			if (i + j) % 2 == 0:
				kit.box("painted", pos + b * Vector3(-width * 0.5 + 0.08 + float(i) * 0.12, 1.25 + float(j) * 0.13, 0.052), Vector3(0.02, 0.02, 0.004), DARK, b)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 7.0 + pos.z * 13.0)
	var tool_cols := [Color(0.85, 0.15, 0.1), Color(0.95, 0.7, 0.1), Color(0.2, 0.45, 0.85), BRUSHED, accent]
	var x := -width * 0.5 + 0.25
	while x < width * 0.5 - 0.2:
		var tc: Color = tool_cols[rng.randi() % tool_cols.size()]
		var y := rng.randf_range(1.45, 2.0)
		var kind := rng.randi() % 3
		if kind == 0:  # wrench
			kit.box("metal", pos + b * Vector3(x, y, 0.07), Vector3(0.04, 0.34, 0.02), BRUSHED, b)
			kit.torus("metal", pos + b * Vector3(x, y + 0.19, 0.07), 0.025, 0.05, BRUSHED, b * Basis(Vector3.RIGHT, PI / 2.0), 10, 4)
		elif kind == 1:  # screwdriver / driver
			kit.cylinder("painted", pos + b * Vector3(x, y - 0.18, 0.07), pos + b * Vector3(x, y, 0.07), 0.03, tc, 6)
			kit.cylinder("metal", pos + b * Vector3(x, y, 0.07), pos + b * Vector3(x, y + 0.18, 0.07), 0.008, BRUSHED, 4)
		else:  # hammer
			kit.box("painted", pos + b * Vector3(x, y, 0.07), Vector3(0.04, 0.32, 0.03), tc, b)
			kit.box("metal", pos + b * Vector3(x, y + 0.17, 0.07), Vector3(0.16, 0.06, 0.05), GUNMETAL, b)
		x += rng.randf_range(0.18, 0.3)
	# Rolling tool chest.
	var chest := pos + b * Vector3(0, 0, 0.33)
	kit.bevel_box("painted", chest + Vector3(0, 0.55, 0), Vector3(0.95, 0.9, 0.5), 0.04, FIRE_RED, b)
	for d in range(4):
		kit.box("metal", chest + b * Vector3(0, 0.28 + float(d) * 0.2, 0.255), Vector3(0.7, 0.025, 0.02), BRUSHED, b)
	kit.bevel_box("metal", chest + Vector3(0, 1.02, 0), Vector3(0.97, 0.05, 0.52), 0.02, GUNMETAL, b)
	for sx in [-0.4, 0.4]:
		for sz in [-0.18, 0.18]:
			kit.sphere("painted", chest + b * Vector3(sx, 0.05, sz), 0.05, Color(0.1, 0.1, 0.11), 6)
	_collider(body, chest + Vector3(0, 0.525, 0), Vector3(0.97, 1.05, 0.52), b)
	_reg("tool_chest", chest + Vector3(0, 0.525, 0), Vector3(0.97, 1.05, 0.52), yaw)
	_ao_rect(kit, chest, Vector2(0.48, 0.25), yaw, 0.25)


## Coiled hose lying on the floor (low: no collider needed).
static func _hose_coil(kit: ArtMeshKit, pos: Vector3, color: Color) -> void:
	for i in range(3):
		kit.torus("painted", pos + Vector3(0, 0.04 + float(i) * 0.06, 0), 0.22 - float(i) * 0.02, 0.28 - float(i) * 0.02, color, Basis.IDENTITY, 16, 5)
	kit.cylinder("metal", pos + Vector3(0.25, 0.05, 0), pos + Vector3(0.45, 0.05, 0.1), 0.03, BRUSHED, 6)


## Cork noticeboard on a wall; front faces +Z rotated by yaw, `pos` on the wall
## face at floor level.
static func _noticeboard(kit: ArtMeshKit, pos: Vector3, yaw: float, accent: Color) -> void:
	var b := _yb(yaw)
	var f := b * Vector3(0, 0, 1)
	kit.bevel_box("painted", pos + b * Vector3(0, 1.55, 0.03), Vector3(2.0, 1.2, 0.05), 0.02, Color(0.45, 0.32, 0.2), b)
	kit.box("soft", pos + b * Vector3(0, 1.5, 0.057), Vector3(1.86, 0.98, 0.005), Color(0.74, 0.56, 0.36), b)
	kit.box("painted", pos + b * Vector3(0, 2.07, 0.06), Vector3(1.9, 0.16, 0.01), accent.darkened(0.2), b)
	_text(kit, "painted", "NOTICES", pos + b * Vector3(0, 2.07, 0.068), f, 0.12, PAPER)
	var notes := [[-0.62, 1.68, 0.05, PAPER, "ROSTER"], [-0.15, 1.72, -0.06, Color(1.0, 0.92, 0.45), "WHO TOOK\nMY CELL?"], [0.4, 1.66, 0.04, Color(0.7, 0.9, 1.0), "MOVIE\nNIGHT"], [-0.5, 1.25, -0.03, Color(1.0, 0.7, 0.75), ""], [0.05, 1.28, 0.07, PAPER, "DRILL\n03:00"], [0.6, 1.24, -0.05, Color(0.75, 1.0, 0.7), ""]]
	for n in notes:
		var nb := b * Basis(Vector3.BACK, n[2])
		kit.box("soft", pos + b * Vector3(n[0], n[1], 0.064), Vector3(0.36, 0.3, 0.004), n[3], nb)
		kit.sphere("painted", pos + b * Vector3(n[0], float(n[1]) + 0.12, 0.068), 0.015, Color(0.9, 0.15, 0.1), 5)
		if String(n[4]) != "":
			kit.text("painted", n[4], Transform3D(nb, pos + b * Vector3(n[0], float(n[1]) - 0.01, 0.067)), DARK, 0.06, 0.3)


## Walk-through scanner arch; the walk-through axis is local Z rotated by yaw.
static func _scanner_arch(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, span: float, color: Color) -> void:
	var b := _yb(yaw)
	for sx in [-1.0, 1.0]:
		var leg := pos + b * Vector3(sx * (span * 0.5 + 0.16), 0, 0)
		kit.bevel_box("painted", leg + Vector3(0, 1.15, 0), Vector3(0.32, 2.3, 0.5), 0.08, Color(0.88, 0.9, 0.9), b)
		kit.box("breathe", leg + b * Vector3(-sx * 0.165, 1.2, 0), Vector3(0.01, 1.8, 0.08), color.lightened(0.2), b)
		_collider(body, leg + Vector3(0, 1.15, 0), Vector3(0.34, 2.3, 0.52), b)
		_reg("arch_leg", leg + Vector3(0, 1.15, 0), Vector3(0.32, 2.3, 0.5), yaw)
	kit.bevel_box("painted", pos + Vector3(0, 2.42, 0), Vector3(span + 0.64, 0.26, 0.5), 0.1, Color(0.88, 0.9, 0.9), b)
	kit.box("trim", pos + b * Vector3(0, 2.28, 0), Vector3(span, 0.02, 0.1), color.lightened(0.3), b)
	kit.box("screen", pos + b * Vector3(0, 2.42, 0.255), Vector3(0.6, 0.14, 0.01), color, b)
	_collider(body, pos + Vector3(0, 2.42, 0), Vector3(span + 0.64, 0.26, 0.52), b)
	kit.box("hazard", pos + Vector3(0, 0.006, 0), Vector3(span, 0.012, 0.36), Color.WHITE, b)


## Free-standing privacy screen: a soft curtain on a frame (sightline breaker).
static func _curtain(kit: ArtMeshKit, body: StaticBody3D, a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var yaw := atan2(dir.x, dir.z)
	var basis := _yb(yaw)
	var folds := int(length / 0.18)
	for i in range(folds):
		var p := a.lerp(b, (float(i) + 0.5) / float(folds))
		kit.box("soft", p + Vector3(0, 1.15, 0) + basis * Vector3((0.03 if i % 2 == 0 else -0.03), 0, 0), Vector3(0.05, 1.7, length / float(folds) + 0.01), color.darkened(0.06 * float(i % 2)), basis)
	kit.cylinder("metal", a + Vector3(0, 2.05, 0), b + Vector3(0, 2.05, 0), 0.025, BRUSHED, 6)
	for p in [a, b]:
		kit.cylinder("metal", p, p + Vector3(0, 2.05, 0), 0.03, BRUSHED, 6)
		kit.cylinder("metal", p, p + Vector3(0, 0.03, 0), 0.18, GUNMETAL, 10)
	var mid := (a + b) * 0.5 + Vector3(0, 1.03, 0)
	_collider(body, mid, Vector3(0.14, 2.06, length + 0.1), basis)
	_reg("curtain", mid, Vector3(0.12, 2.06, length), yaw)


# --- per-room dressing -------------------------------------------------------------------

static func _dress_command(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Vault dais around the vault socket (0, -23.5), framed against the viewport.
	var vault := Vector3(0, 0, -23.5)
	kit.cylinder("painted", vault, vault + Vector3(0, 0.03, 0), 2.4, Color(0.13, 0.15, 0.2), 40)
	kit.torus("trim", vault + Vector3(0, 0.03, 0), 2.32, 2.46, color, Basis.from_scale(Vector3(1, 0.12, 1)), 48, 4)
	kit.torus("hazard", vault + Vector3(0, 0.02, 0), 1.75, 2.05, Color.WHITE, Basis.from_scale(Vector3(1, 0.05, 1)), 40, 4)
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * 2.4, 0, -25.35)
		kit.bevel_box("painted", p + Vector3(0, 1.6, 0), Vector3(0.7, 3.2, 0.7), 0.08, DARK)
		kit.box("trim", p + Vector3(0, 1.6, 0.355), Vector3(0.08, 2.6, 0.01), color)
		kit.box("trim", p + Vector3(-sx * 0.355, 1.6, 0), Vector3(0.01, 2.6, 0.08), color)
		kit.box("blink", p + Vector3(0, 0.5, 0.356), Vector3(0.2, 0.05, 0.01), LED_GREEN)
		_collider(body, p + Vector3(0, 1.6, 0), Vector3(0.7, 3.2, 0.7))
		_reg("vault_pylon", p + Vector3(0, 1.6, 0), Vector3(0.7, 3.2, 0.7))
	kit.bevel_box("metal", Vector3(0, 3.05, -25.35), Vector3(5.5, 0.3, 0.5), 0.05, GUNMETAL)
	_text(kit, "sign", "STATION CORE VAULT", Vector3(0, 3.05, -25.09), Vector3(0, 0, 1), 0.19, color.lightened(0.45))
	# Duty consoles on the west wall and the north-east corner, with chairs.
	for cz in [-22.4, -17.4]:
		_console(kit, body, Vector3(-6.25, 0, cz), PI / 2.0, 2.4, SCREEN_BLUE, color)
		_chair(kit, body, Vector3(-4.95, 0, cz), -PI / 2.0, color.darkened(0.35))
	_console(kit, body, Vector3(6.25, 0, -24.2), -PI / 2.0, 2.2, SCREEN_BLUE, color)
	_chair(kit, body, Vector3(4.95, 0, -24.2), PI / 2.0, color.darkened(0.35))
	# Big tactical screen on the west wall between the consoles.
	kit.bevel_box("painted", Vector3(-6.95, 1.95, -19.9), Vector3(0.1, 1.1, 2.1), 0.03, DARK)
	kit.box("screen", Vector3(-6.89, 1.95, -19.9), Vector3(0.01, 0.95, 1.95), SCREEN_BLUE.lerp(color, 0.3))
	# Holo table with a turning planet, and the captain's chair facing the vault.
	_holo_table(kit, body, Vector3(3.6, 0, -16.6), color)
	_chair(kit, body, Vector3(2.2, 0, -16.0), PI * 0.75, color.darkened(0.35))
	_chair(kit, body, Vector3(4.9, 0, -15.4), -PI * 0.8, color.darkened(0.35))
	var cap := Vector3(-3.4, 0, -16.2)
	kit.cylinder("metal", cap, cap + Vector3(0, 0.1, 0), 0.5, GUNMETAL, 18)
	_chair(kit, body, cap + Vector3(0, 0.0, 0), PI * 0.85, Color(0.18, 0.2, 0.3))
	kit.bevel_box("painted", cap + Vector3(-0.36, 0.62, 0.1), Vector3(0.1, 0.12, 0.42), 0.03, color.darkened(0.2))
	kit.bevel_box("painted", cap + Vector3(0.36, 0.62, 0.1), Vector3(0.1, 0.12, 0.42), 0.03, color.darkened(0.2))
	_potted_plant(kit, body, Vector3(-6.3, 0, -14.75), 31)
	_potted_plant(kit, body, Vector3(6.3, 0, -14.75), 37)


static func _dress_security(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Monitor wall (3 x 2 feeds) on the north wall, east of the armory socket.
	for i in range(3):
		for j in range(2):
			var mx := 40.1 + float(i) * 1.95
			var my := 1.6 + float(j) * 0.9
			kit.bevel_box("painted", Vector3(mx, my, -25.93), Vector3(1.85, 0.82, 0.1), 0.03, DARK)
			kit.box("screen", Vector3(mx, my, -25.875), Vector3(1.7, 0.68, 0.01), SCREEN_BLUE.lerp(color, 0.3 * float((i + j) % 2)))
			kit.sphere("blink", Vector3(mx + 0.8, my - 0.3, -25.87), 0.022, Color(1.0, 0.2, 0.15), 6)
	_text(kit, "sign", "CAM FEEDS", Vector3(42.05, 3.0, -25.86), Vector3(0, 0, 1), 0.14, color.lightened(0.5))
	_console(kit, body, Vector3(42.0, 0, -24.95), 0.0, 3.4, SCREEN_BLUE, color)
	_chair(kit, body, Vector3(41.2, 0, -23.75), PI, color.darkened(0.4))
	# Armory alcove frame behind the socket.
	for sx in [-1.0, 1.0]:
		kit.bevel_box("metal", Vector3(37.0 + sx * 1.15, 1.4, -25.7), Vector3(0.2, 2.8, 0.5), 0.04, GUNMETAL)
		kit.box("trim", Vector3(37.0 + sx * 1.05, 1.4, -25.5), Vector3(0.02, 2.4, 0.04), color)
		_collider(body, Vector3(37.0 + sx * 1.15, 1.4, -25.7), Vector3(0.2, 2.8, 0.5))
	kit.bevel_box("metal", Vector3(37.0, 2.7, -25.7), Vector3(2.5, 0.2, 0.5), 0.04, GUNMETAL)
	_text(kit, "sign", "ARMORY", Vector3(37.0, 2.95, -25.86), Vector3(0, 0, 1), 0.18, Color(1.0, 0.75, 0.7))
	kit.box_mm("hazard", Vector3(35.6, 0.0, -25.95), Vector3(38.4, 0.012, -23.4), Color.WHITE)
	# Lockers along the east wall (north part).
	_lockers(kit, body, Vector3(46.68, 0, -22.9), -PI / 2.0, 7, Color(0.42, 0.18, 0.2), color)
	# Holding cell in the south-east corner: bars on two sides, bunk inside.
	var cell_x := 44.0
	var cell_z := -17.6
	var z := cell_z + 0.15
	while z < -14.05:
		kit.cylinder("metal", Vector3(cell_x, 0.05, z), Vector3(cell_x, 2.6, z), 0.03, BRUSHED, 6)
		z += 0.22
	var x := cell_x + 0.15
	while x < 47.0:
		kit.cylinder("metal", Vector3(x, 0.05, cell_z), Vector3(x, 2.6, cell_z), 0.03, BRUSHED, 6)
		x += 0.22
	kit.bevel_box("painted", Vector3(cell_x, 2.65, (cell_z - 14.0) * 0.5), Vector3(0.14, 0.14, 3.6), 0.03, GRAPHITE)
	kit.bevel_box("painted", Vector3((cell_x + 47.0) * 0.5, 2.65, cell_z), Vector3(3.0, 0.14, 0.14), 0.03, GRAPHITE)
	kit.bevel_box("painted", Vector3(cell_x, 0.05, (cell_z - 14.0) * 0.5), Vector3(0.14, 0.1, 3.6), 0.03, GRAPHITE)
	kit.bevel_box("painted", Vector3((cell_x + 47.0) * 0.5, 0.05, cell_z), Vector3(3.0, 0.1, 0.14), 0.03, GRAPHITE)
	kit.bevel_box("painted", Vector3(cell_x, 1.0, -16.0), Vector3(0.12, 0.3, 0.2), 0.02, DARK)
	kit.sphere("blink", Vector3(cell_x - 0.065, 1.05, -16.0), 0.025, Color(1.0, 0.2, 0.15), 6)
	_collider(body, Vector3(cell_x, 1.4, (cell_z - 14.0) * 0.5), Vector3(0.12, 2.8, 3.6))
	_collider(body, Vector3((cell_x + 47.0) * 0.5, 1.4, cell_z), Vector3(3.0, 2.8, 0.12))
	_reg("cell_bars_w", Vector3(cell_x, 1.3, (cell_z - 14.0) * 0.5), Vector3(0.08, 2.6, 3.4))
	_reg("cell_bars_n", Vector3((cell_x + 47.0) * 0.5, 1.3, cell_z), Vector3(2.8, 2.6, 0.08))
	kit.bevel_box("metal", Vector3(46.3, 0.45, -15.5), Vector3(1.2, 0.08, 2.2), 0.02, GUNMETAL)
	kit.bevel_box("soft", Vector3(46.3, 0.54, -15.5), Vector3(1.0, 0.08, 2.0), 0.03, Color(0.55, 0.3, 0.3))
	_text(kit, "painted", "HOLDING", Vector3(cell_x - 0.075, 2.65, -15.8), Vector3(-1, 0, 0), 0.1, PAPER)
	# Desk island facing the south door: the duty officer sees who walks in.
	var desk := Vector3(38.6, 0, -18.6)
	kit.bevel_box("painted", desk + Vector3(0, 0.42, 0), Vector3(2.4, 0.84, 0.9), 0.06, Color(0.32, 0.18, 0.2))
	kit.bevel_box("metal", desk + Vector3(0, 0.87, 0), Vector3(2.5, 0.06, 1.0), 0.02, GUNMETAL)
	kit.box("trim", desk + Vector3(0, 0.15, 0.452), Vector3(2.2, 0.03, 0.01), color)
	kit.bevel_box("painted", desk + Vector3(-0.5, 1.15, -0.2), Vector3(0.8, 0.5, 0.06), 0.02, DARK)
	kit.box("screen", desk + Vector3(-0.5, 1.15, -0.165), Vector3(0.7, 0.4, 0.01), SCREEN_BLUE)
	kit.box("painted", desk + Vector3(0.6, 0.92, 0.1), Vector3(0.4, 0.04, 0.3), PAPER)
	_text(kit, "sign", "SECURITY", desk + Vector3(0, 0.55, 0.455), Vector3(0, 0, 1), 0.16, color.lightened(0.5))
	_collider(body, desk + Vector3(0, 0.45, 0), Vector3(2.5, 0.9, 1.0))
	_reg("desk", desk + Vector3(0, 0.45, 0), Vector3(2.5, 0.9, 1.0))
	_ao_rect(kit, desk, Vector2(1.2, 0.45), 0.0, 0.35)
	_chair(kit, body, desk + Vector3(0.2, 0, -1.0), 0.0, color.darkened(0.4))
	# Bench by the south wall, west of the doorway.
	kit.bevel_box("metal", Vector3(35.5, 0.45, -14.6), Vector3(2.6, 0.08, 0.5), 0.02, GUNMETAL)
	kit.bevel_box("painted", Vector3(35.5, 0.22, -14.6), Vector3(2.4, 0.44, 0.3), 0.02, DARK)
	_collider(body, Vector3(35.5, 0.25, -14.6), Vector3(2.6, 0.5, 0.5))
	_reg("bench", Vector3(35.5, 0.25, -14.6), Vector3(2.6, 0.5, 0.5))
	_ao_rect(kit, Vector3(35.5, 0, -14.6), Vector2(1.3, 0.25), 0.0, 0.3)


static func _dress_commons(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Mess tables (long axis along X) in the east half, clear of the spawn ring.
	for sz in [-1.0, 1.0]:
		var t := Vector3(4.8, 0, sz * 5.0)
		kit.bevel_box("metal", t + Vector3(0, 0.76, 0), Vector3(2.3, 0.06, 1.0), 0.02, Color(0.55, 0.56, 0.58))
		kit.bevel_box("painted", t + Vector3(0, 0.38, 0), Vector3(1.6, 0.72, 0.3), 0.03, DARK)
		kit.box("trim", t + Vector3(0, 0.72, 0), Vector3(2.32, 0.015, 1.02), color)
		_collider(body, t + Vector3(0, 0.4, 0), Vector3(2.3, 0.8, 1.0))
		_reg("mess_table", t + Vector3(0, 0.4, 0), Vector3(2.3, 0.8, 1.0))
		# Trays, cups and a jug on the table (story: lunch was interrupted).
		kit.bevel_box("painted", t + Vector3(-0.6, 0.8, 0.2), Vector3(0.42, 0.03, 0.3), 0.01, Color(0.85, 0.5, 0.2))
		kit.bevel_box("painted", t + Vector3(0.45, 0.8, -0.22), Vector3(0.42, 0.03, 0.3), 0.01, Color(0.3, 0.6, 0.8))
		kit.cylinder("painted", t + Vector3(0.1, 0.79, 0.25), t + Vector3(0.1, 0.9, 0.25), 0.04, PAPER, 8)
		kit.cylinder("glass", t + Vector3(-0.15, 0.79, -0.2), t + Vector3(-0.15, 1.0, -0.2), 0.07, Color.WHITE, 10)
		for bz in [-1.0, 1.0]:
			var b := t + Vector3(0, 0, bz * 1.12)
			kit.bevel_box("soft", b + Vector3(0, 0.46, 0), Vector3(2.2, 0.1, 0.42), 0.04, color.darkened(0.35))
			kit.bevel_box("painted", b + Vector3(0, 0.21, 0), Vector3(1.8, 0.42, 0.2), 0.02, DARK)
			_collider(body, b + Vector3(0, 0.25, 0), Vector3(2.2, 0.5, 0.42))
			_reg("mess_bench", b + Vector3(0, 0.25, 0), Vector3(2.2, 0.5, 0.42))
		_ao_rect(kit, t, Vector2(1.15, 1.3), 0.0, 0.4)
	# Lounge corner (north-west): L of sofas round a low table, a tall plant.
	_sofa(kit, body, Vector3(-5.2, 0, -6.35), 0.0, 2.8, color.darkened(0.25))
	_sofa(kit, body, Vector3(-7.35, 0, -3.9), PI / 2.0, 2.0, color.darkened(0.25))
	kit.bevel_box("painted", Vector3(-5.4, 0.2, -4.4), Vector3(1.1, 0.4, 0.7), 0.06, GRAPHITE)
	kit.bevel_box("metal", Vector3(-5.4, 0.42, -4.4), Vector3(1.16, 0.05, 0.76), 0.02, BRUSHED)
	kit.cylinder("painted", Vector3(-5.6, 0.44, -4.3), Vector3(-5.6, 0.54, -4.3), 0.045, Color(0.9, 0.3, 0.25), 8)
	kit.bevel_box("soft", Vector3(-5.15, 0.46, -4.5), Vector3(0.3, 0.03, 0.22), 0.01, Color(0.3, 0.55, 0.9))
	_collider(body, Vector3(-5.4, 0.225, -4.4), Vector3(1.16, 0.45, 0.76))
	_reg("coffee_table", Vector3(-5.4, 0.225, -4.4), Vector3(1.16, 0.45, 0.76))
	_potted_plant(kit, body, Vector3(-7.35, 0, -6.35), 5)
	# Four slim pillars frame the spawn floor (sightline breakers, cover).
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_pillar(kit, body, Vector3(sx * 3.0, 0, sz * 4.6), 0.5, color)
	# Planter under the south-west windows, clear of the airlock console.
	_planter(kit, body, Vector3(-7.35, 0, 5.6), Vector2(0.7, 2.0), 0.6, 7)
	# Hazard apron in front of the airlock doorway.
	kit.box_mm("hazard", Vector3(-7.95, 0.0, -1.5), Vector3(-7.2, 0.012, 1.5), Color.WHITE)
	_text(kit, "painted", "AIRLOCK", Vector3(-6.6, 0.012, 0.0), Vector3(1, 0, 0), 0.32, Color(0.85, 0.35, 0.15), true)
	# Vending machines in the east corners, facing west.
	_vending(kit, body, Vector3(7.45, 0, -5.4), -PI / 2.0, color.darkened(0.45), Color(1.0, 0.75, 0.35), "SNAX")
	_vending(kit, body, Vector3(7.45, 0, 5.4), -PI / 2.0, Color(0.2, 0.35, 0.55), Color(0.45, 0.85, 1.0), "AQUA")
	# Noticeboard on the south wall and a water cooler under it.
	_noticeboard(kit, Vector3(4.0, 0, 7.0), PI, color)
	var cooler := Vector3(2.85, 0, 6.6)
	kit.bevel_box("painted", cooler + Vector3(0, 0.5, 0), Vector3(0.42, 1.0, 0.42), 0.05, PAPER)
	kit.cylinder("glass", cooler + Vector3(0, 1.0, 0), cooler + Vector3(0, 1.42, 0), 0.16, Color.WHITE, 12)
	kit.cylinder("screen", cooler + Vector3(0, 1.02, 0), cooler + Vector3(0, 1.25, 0), 0.14, Color(0.4, 0.75, 1.0), 12)
	kit.sphere("blink", cooler + Vector3(0.1, 0.8, -0.215), 0.02, Color(0.4, 0.75, 1.0), 6)
	_collider(body, cooler + Vector3(0, 0.71, 0), Vector3(0.44, 1.42, 0.44))
	_reg("water_cooler", cooler + Vector3(0, 0.71, 0), Vector3(0.42, 1.42, 0.42))
	_ao_rect(kit, cooler, Vector2(0.21, 0.21), 0.0, 0.2)


static func _dress_docking(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var hull: Dictionary = StationLayout.SHUTTLE_HULL
	var hc := Vector3(hull.center.x, 0, hull.center.y)
	var hs: Vector2 = hull.size
	var white := Color(0.92, 0.92, 0.9)
	var fus_len := hs.x - 1.2
	var r := 1.15
	var fus_y := 1.55
	var squash := Basis.from_scale(Vector3(0.88, 1.0, 1.0))
	var along := Basis(Vector3.BACK, PI / 2.0)  # mesh Y -> world X
	var fc := hc + Vector3(-0.1, fus_y, 0)
	# Landing pad: painted outline with corner brackets and a pad number.
	var pad0 := Vector3(hc.x - hs.x * 0.5 - 0.5, 0, hc.z - hs.y * 0.5 + 0.1)
	var pad1 := Vector3(hc.x + hs.x * 0.5 + 0.5, 0, hc.z + hs.y * 0.5 + 0.9)
	var pad_c := Color(0.95, 0.75, 0.2)
	kit.box_mm("painted", Vector3(pad0.x, 0.0, pad0.z), Vector3(pad1.x, 0.006, pad1.z), Color(0.26, 0.28, 0.3))
	for e in [[pad0.x, pad1.x, pad0.z, pad0.z + 0.12], [pad0.x, pad1.x, pad1.z - 0.12, pad1.z], [pad0.x, pad0.x + 0.12, pad0.z, pad1.z], [pad1.x - 0.12, pad1.x, pad0.z, pad1.z]]:
		kit.box_mm("painted", Vector3(e[0], 0.0, e[2]), Vector3(e[1], 0.009, e[3]), pad_c)
	for cx in [pad0.x + 0.12, pad1.x - 0.12]:
		var gx: float = cx + 0.3 if cx < hc.x else cx - 0.3
		kit.box("guide", Vector3(gx, 0.008, pad1.z - 0.35), Vector3(0.14, 0.012, 0.14), GUIDE)
	_text(kit, "painted", "PAD 01", Vector3(pad1.x - 1.3, 0.01, pad1.z - 0.45), Vector3(0, 0, 1), 0.36, pad_c, true)
	_text(kit, "painted", "CREW SHUTTLE", Vector3(pad0.x + 1.9, 0.01, pad1.z - 0.45), Vector3(0, 0, 1), 0.26, pad_c.darkened(0.15), true)
	# Cute but sturdy shuttle: one rounded fuselage, painted bands, bubble
	# canopy, fat engine pods and rounded fins.
	var fus := CapsuleMesh.new()
	fus.radius = r
	fus.height = fus_len
	fus.radial_segments = 28
	fus.rings = 10
	kit.mesh("painted", fus, Transform3D(along * squash, fc), white)
	if _ctx_shadow != null:
		_ctx_shadow.mesh("shadow", fus, Transform3D(along * squash, fc), Color.WHITE)
	for band in [[0.9, 0.85, color], [-2.2, 0.22, GRAPHITE]]:
		var ring := CylinderMesh.new()
		ring.top_radius = r * 1.012
		ring.bottom_radius = r * 1.012
		ring.height = band[1]
		ring.radial_segments = 28
		ring.rings = 1
		kit.mesh("painted", ring, Transform3D(along * squash, fc + Vector3(band[0], 0, 0)), band[2])
	var glow_ring := CylinderMesh.new()
	glow_ring.top_radius = r * 1.016
	glow_ring.bottom_radius = r * 1.016
	glow_ring.height = 0.06
	glow_ring.radial_segments = 28
	glow_ring.rings = 1
	kit.mesh("trim", glow_ring, Transform3D(along * squash, fc + Vector3(1.38, 0, 0)), color.lightened(0.2))
	kit.mesh("trim", glow_ring, Transform3D(along * squash, fc + Vector3(0.42, 0, 0)), color.lightened(0.2))
	_text(kit, "painted", "DS-7", fc + Vector3(-0.2, 0.15, r * 0.9 + 0.05), Vector3(0, 0, 1), 0.34, GRAPHITE)
	kit.sphere("screen", fc + Vector3(-fus_len * 0.5 + 1.2, 0.55, 0), 0.8, Color(0.12, 0.32, 0.5), 20, Vector3(1.25, 0.62, 0.95))
	kit.torus("metal", fc + Vector3(-fus_len * 0.5 + 1.2, 0.36, 0), 0.72, 0.84, BRUSHED, Basis.from_scale(Vector3(1.25, 0.6, 0.95)), 28, 6)
	for sz in [-1.0, 1.0]:
		for i in range(3):
			var px := fc.x - 0.5 + float(i) * 0.75
			kit.sphere("screen", Vector3(px, fc.y + 0.28, fc.z + sz * r * 0.93), 0.17, Color(1.0, 0.82, 0.55), 12, Vector3(1, 1, 0.45))
			kit.torus("metal", Vector3(px, fc.y + 0.28, fc.z + sz * r * 0.95), 0.16, 0.22, BRUSHED, Basis(Vector3.RIGHT, PI / 2.0), 16, 6)
	var tail_x := fc.x + fus_len * 0.5 - 0.2
	for sz in [-1.0, 1.0]:
		var pod := CapsuleMesh.new()
		pod.radius = 0.42
		pod.height = 2.0
		pod.radial_segments = 20
		pod.rings = 6
		var pc := Vector3(tail_x - 0.6, fc.y - 0.15, fc.z + sz * 1.05)
		kit.mesh("painted", pod, Transform3D(along, pc), white)
		kit.mesh("painted", glow_ring, Transform3D(along * Basis.from_scale(Vector3(0.38 / r, 1.0, 0.38 / r)), pc + Vector3(-0.3, 0, 0)), color)
		kit.cylinder("metal", pc + Vector3(0.75, 0, 0), pc + Vector3(1.05, 0, 0), 0.34, BRUSHED, 16, 0.38)
		kit.cylinder("breathe", pc + Vector3(1.04, 0, 0), pc + Vector3(1.07, 0, 0), 0.3, Color(0.45, 0.85, 1.0), 16)
	kit.bevel_box("painted", Vector3(tail_x - 1.0, fc.y + r * 0.88 + 0.22, fc.z), Vector3(1.5, 0.75, 0.2), 0.09, white, Basis(Vector3.BACK, -0.45))
	kit.bevel_box("painted", Vector3(tail_x - 0.85, fc.y + r * 0.88 + 0.42, fc.z), Vector3(0.8, 0.16, 0.22), 0.07, color, Basis(Vector3.BACK, -0.45))
	kit.sphere("nav", Vector3(tail_x - 0.5, fc.y + r * 0.88 + 0.62, fc.z), 0.06, Color(1, 1, 1), 6)
	for sz in [-1.0, 1.0]:
		kit.bevel_box("painted", Vector3(fc.x + 0.6, fc.y - 0.35, fc.z + sz * (r + 0.05)), Vector3(1.8, 0.16, 0.45), 0.07, white, Basis(Vector3.RIGHT, sz * 0.3))
		kit.sphere("nav", Vector3(fc.x + 0.6, fc.y - 0.38, fc.z + sz * (r + 0.3)), 0.07, Color(1, 0.15, 0.1) if sz < 0.0 else Color(0.2, 1, 0.3), 8)
	for sx in [-2.4, 0.4, 2.6]:
		for sz in [-0.75, 0.75]:
			var strut := Vector3(fc.x + sx, 0, fc.z + sz)
			kit.cylinder("metal", strut + Vector3(0, 0.08, 0), strut + Vector3(0, 0.7, 0), 0.08, BRUSHED, 10)
			kit.sphere("painted", strut + Vector3(0, 0.06, 0), 0.2, GRAPHITE, 12, Vector3(1, 0.45, 1))
	_ao_rect(kit, hc, Vector2(hs.x * 0.5 - 0.4, r * 0.9), 0.0, 0.6, Color(0.3, 0.3, 0.33))
	# Hull collision hugs the fuselage: a body box plus the engine pods.
	_collider(body, hc + Vector3(-0.1, 1.45, 0), Vector3(fus_len + r * 2.0 - 0.6, 2.9, r * 2.0 * 0.95), Basis.IDENTITY, false)
	_collider(body, Vector3(tail_x - 0.4, fc.y - 0.15, fc.z), Vector3(2.4, 0.9, 3.0), Basis.IDENTITY, false)
	_reg("shuttle", hc + Vector3(-0.1, 1.45, 0), Vector3(fus_len + r * 2.0 - 0.6, 2.9, r * 2.0 * 0.88))
	# Loading ramp from the side hatch down to the floor (west of the socket).
	var hatch_x := hc.x - 1.9
	var top := Vector3(hatch_x, 0.55, hc.z + 1.05)
	var foot := Vector3(hatch_x, 0.0, hc.z + hs.y * 0.5 + 1.6)
	var ramp_len := top.distance_to(foot)
	var ang := atan2(top.y - foot.y, foot.z - top.z)
	var rb := Basis(Vector3.RIGHT, ang)
	var rc := (top + foot) * 0.5 + rb * Vector3(0, -0.04, 0)
	kit.bevel_box("metal", rc, Vector3(1.4, 0.08, ramp_len), 0.02, GUNMETAL, rb)
	kit.box("hazard", rc + rb * Vector3(-0.62, 0.045, 0), Vector3(0.12, 0.01, ramp_len), Color.WHITE, rb)
	kit.box("hazard", rc + rb * Vector3(0.62, 0.045, 0), Vector3(0.12, 0.01, ramp_len), Color.WHITE, rb)
	_collider(body, rc, Vector3(1.4, 0.08, ramp_len), rb)
	kit.bevel_box("painted", Vector3(hatch_x, 1.3, hc.z + 1.08), Vector3(1.2, 1.35, 0.16), 0.08, GRAPHITE)
	for hx in [-0.6, 0.6]:
		kit.cylinder("door", Vector3(hatch_x + hx * 0.92, 0.75, hc.z + 1.17), Vector3(hatch_x + hx * 0.92, 1.85, hc.z + 1.17), 0.035, color, 8)
	kit.sphere("screen", Vector3(hatch_x, 1.6, hc.z + 1.16), 0.13, Color(1.0, 0.8, 0.5), 10, Vector3(1, 1, 0.4))
	# Fuel farm on the south wall: two tanks, a manifold with valve wheels and
	# a hose coiled on the floor.
	var fuel := Color(0.75, 0.42, 0.15)
	_tank(kit, body, Vector3(14.6, 0, 5.0), 0.55, 2.3, fuel)
	_tank(kit, body, Vector3(25.4, 0, 5.0), 0.55, 2.3, fuel)
	_pipe_run(kit, Vector3(14.6, 2.0, 5.75), Vector3(25.4, 2.0, 5.75), 0.08, fuel)
	_text(kit, "painted", "FUEL", Vector3(14.6, 1.55, 4.44), Vector3(0, 0, -1), 0.2, GRAPHITE)
	_text(kit, "painted", "FUEL", Vector3(25.4, 1.55, 4.44), Vector3(0, 0, -1), 0.2, GRAPHITE)
	for vx in [16.0, 24.0]:
		kit.cylinder("painted", Vector3(vx, 2.0, 5.75), Vector3(vx, 0.9, 5.75), 0.06, fuel, 8)
		_valve_wheel(kit, Vector3(vx, 1.3, 5.62), Basis(Vector3.RIGHT, PI / 2.0), 0.14, FIRE_RED)
	_hose_coil(kit, Vector3(23.3, 0, 3.6), Color(0.15, 0.15, 0.17))
	_cable(kit, Vector3(24.0, 0.9, 5.75), Vector3(23.4, 0.1, 3.95), 0.25, 0.035, Color(0.15, 0.15, 0.17))
	# Tool wall with a rolling chest, between the tanks.
	_tool_wall(kit, body, Vector3(19.5, 0, 6.0), PI, 3.6, color)
	_crate(kit, body, Vector3(22.5, 0, 5.2), Vector3(1.1, 0.9, 1.0), Color(0.3, 0.42, 0.4), 0.0, "DK")
	# Cargo cover by the west door: a pallet with two crates.
	_pallet(kit, body, Vector3(15.6, 0, 3.2), 0.1)
	_crate(kit, body, Vector3(15.35, 0.14, 3.2), Vector3(0.8, 0.8, 0.8), Color(0.86, 0.45, 0.16), 0.1, "14")
	_crate(kit, body, Vector3(16.0, 0.14, 3.05), Vector3(0.5, 0.55, 0.6), PAPER.darkened(0.1), -0.2)


static func _dress_cargo(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var pod: Dictionary = StationLayout.POD_HULL
	var pc := Vector3(pod.center.x, 0, pod.center.y)
	var ps: Vector2 = pod.size
	# Launch cradle: hazard plate, corner posts and top frame.
	kit.box_mm("hazard", pc - Vector3(ps.x * 0.5 + 0.15, 0, ps.y * 0.5 + 0.15), pc + Vector3(ps.x * 0.5 + 0.15, 0.012, ps.y * 0.5 + 0.15), Color.WHITE)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.bevel_box("metal", pc + Vector3(sx * (ps.x * 0.5 - 0.1), 1.45, sz * (ps.y * 0.5 - 0.1)), Vector3(0.18, 2.9, 0.18), 0.03, GUNMETAL)
			kit.sphere("blink", pc + Vector3(sx * (ps.x * 0.5 - 0.1), 2.7, sz * (ps.y * 0.5 - 0.02)), 0.035, LED_AMBER, 6)
	kit.bevel_box("metal", pc + Vector3(0, 2.9, 0), Vector3(ps.x, 0.16, ps.y), 0.04, GUNMETAL)
	# Pod body: squat capsule with a hazard band, hatch facing the socket (-X).
	var body_c := pc + Vector3(0, 0.25, 0)
	kit.cylinder("metal", pc, pc + Vector3(0, 0.25, 0), 0.9, GUNMETAL, 20)
	kit.cylinder("painted", body_c, body_c + Vector3(0, 1.6, 0), 1.0, Color(0.85, 0.84, 0.8), 20)
	kit.sphere("painted", body_c + Vector3(0, 1.6, 0), 1.0, Color(0.85, 0.84, 0.8), 20, Vector3(1, 0.55, 1))
	kit.cylinder("hazard", body_c + Vector3(0, 0.25, 0), body_c + Vector3(0, 0.6, 0), 1.02, Color.WHITE, 20)
	kit.cylinder("trim", body_c + Vector3(0, 1.62, 0), body_c + Vector3(0, 1.68, 0), 1.01, color, 20)
	kit.bevel_box("painted", body_c + Vector3(-0.93, 1.0, 0), Vector3(0.2, 1.3, 0.85), 0.06, DARK)
	kit.sphere("screen", body_c + Vector3(-0.97, 1.35, 0), 0.16, Color(1.0, 0.8, 0.5), 10, Vector3(0.5, 1, 1))
	_text(kit, "painted", "POD-3", body_c + Vector3(0, 1.15, -1.02), Vector3(0, 0, -1), 0.24, GRAPHITE)
	_collider(body, pc + Vector3(0, 1.5, 0), Vector3(ps.x, 3.0, ps.y), Basis.IDENTITY, false)
	_cyl_collider(body, pc + Vector3(0, 1.2, 0), 1.0, 2.4, true)
	_reg("pod_cradle", pc + Vector3(0, 1.5, 0), Vector3(ps.x, 3.0, ps.y))
	# Crate stacks in the north corners.
	_crate(kit, body, Vector3(34.3, 0, -5.8), Vector3(1.4, 1.2, 1.4), Color(0.86, 0.45, 0.16), 0.0, "07")
	_crate(kit, body, Vector3(35.9, 0, -5.9), Vector3(1.2, 1.0, 1.2), Color(0.3, 0.55, 0.62), 0.15, "12")
	_crate(kit, body, Vector3(34.3, 1.2, -5.8), Vector3(1.0, 0.8, 1.0), Color(0.88, 0.88, 0.86), 0.3)
	_crate(kit, body, Vector3(44.0, 0, -5.8), Vector3(1.4, 1.1, 1.4), Color(0.88, 0.88, 0.86), 0.0, "33")
	_crate(kit, body, Vector3(45.8, 0, -5.6), Vector3(1.2, 1.4, 1.2), Color(0.86, 0.45, 0.16), 0.1, "18")
	_crate(kit, body, Vector3(44.0, 1.1, -5.8), Vector3(1.0, 0.8, 1.0), Color(0.3, 0.55, 0.62), -0.25)
	# Pallet cover in the middle-west: "I saw you go behind the crates".
	_pallet(kit, body, Vector3(37.0, 0, -2.9), 0.0)
	_crate(kit, body, Vector3(36.75, 0.14, -2.9), Vector3(0.7, 1.0, 0.9), Color(0.86, 0.45, 0.16), 0.0, "26")
	_crate(kit, body, Vector3(37.35, 0.14, -2.75), Vector3(0.45, 0.6, 0.5), Color(0.3, 0.55, 0.62), 0.25)
	# Forklift parked by the north-east stacks.
	_forklift(kit, body, Vector3(44.6, 0, -2.9), -PI / 2.0)
	# Loading dock (raised deck, south-west): crates waiting to go out.
	var dh: float = StationLayout.PLATFORMS["cargo_dock"].height
	_crate(kit, body, Vector3(34.2, dh, 5.8), Vector3(1.4, 1.2, 1.3), Color(0.3, 0.55, 0.62), 0.0, "41")
	_crate(kit, body, Vector3(35.85, dh, 6.1), Vector3(1.1, 0.9, 1.0), Color(0.86, 0.45, 0.16), -0.15, "09")
	_crate(kit, body, Vector3(34.2, dh + 1.2, 5.8), Vector3(0.9, 0.7, 0.9), PAPER.darkened(0.1), 0.2)
	_text(kit, "painted", "DOCK B", Vector3(35.3, dh + 0.007, 3.75), Vector3(0, 0, -1), 0.34, Color(0.95, 0.75, 0.2), true)
	# Forklift lanes.
	var d := 34.0
	while d < 46.0:
		kit.box_mm("painted", Vector3(d, 0.0, -1.95), Vector3(d + 0.7, 0.008, -1.85), Color(0.9, 0.7, 0.15))
		kit.box_mm("painted", Vector3(d, 0.0, 1.85), Vector3(d + 0.7, 0.008, 1.95), Color(0.9, 0.7, 0.15))
		d += 1.1
	# Big exhaust fan high on the north wall.
	kit.bevel_box("painted", Vector3(44.8, 2.1, -6.94), Vector3(1.5, 1.5, 0.1), 0.05, DARK)
	_fan(kit, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(44.8, 2.1, -6.86)), 0.6, 2.4)
	kit.box("hazard", Vector3(44.8, 1.28, -6.94), Vector3(1.5, 0.1, 0.1), Color.WHITE)


static func _dress_engineering(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Main generator against the north wall (spinning top fan).
	_generator(kit, body, Vector3(59.2, 0, -4.9), 0.0, Vector3(2.6, 1.9, 1.5), Color(0.32, 0.3, 0.18), color, "GEN-A")
	# Pipe runs along the north wall with flanges and valve wheels (the VFX
	# steam vents sit on these).
	_pipe_run(kit, Vector3(56.3, 0.75, -5.75), Vector3(67.7, 0.75, -5.75), 0.12, Color(0.7, 0.55, 0.15))
	_pipe_run(kit, Vector3(56.3, 2.3, -5.72), Vector3(67.7, 2.3, -5.72), 0.15, Color(0.35, 0.42, 0.5))
	_pipe_run(kit, Vector3(61.0, 1.3, -5.78), Vector3(67.7, 1.3, -5.78), 0.09, Color(0.6, 0.2, 0.15))
	for px in [62.5, 65.5]:
		_pipe_run(kit, Vector3(px, 0.0, -5.6), Vector3(px, 2.6, -5.6), 0.1, Color(0.35, 0.42, 0.5))
		_valve_wheel(kit, Vector3(px, 1.6, -5.42), Basis(Vector3.RIGHT, PI / 2.0), 0.17, Color(0.75, 0.15, 0.1))
	for i in range(3):
		var gx := 63.4 + float(i) * 0.55
		kit.cylinder("metal", Vector3(gx, 1.85, -5.86), Vector3(gx, 1.85, -5.8), 0.12, BRUSHED, 12)
		kit.cylinder("screen", Vector3(gx, 1.85, -5.8), Vector3(gx, 1.85, -5.79), 0.1, PAPER, 12)
	_text(kit, "painted", "COOLANT LOOP", Vector3(64.0, 1.0, -5.62), Vector3(0, 0, 1), 0.14, GRAPHITE)
	_collider(body, Vector3(62.0, 1.4, -5.62), Vector3(11.4, 2.8, 0.76))
	# Coolant tanks along the east wall, cables sagging above.
	_tank(kit, body, Vector3(66.9, 0, 2.0), 0.6, 2.6, Color(0.3, 0.45, 0.55))
	_tank(kit, body, Vector3(66.9, 0, 4.4), 0.6, 2.6, Color(0.3, 0.45, 0.55))
	_cable(kit, Vector3(67.75, 2.7, -5.0), Vector3(67.75, 2.7, 0.0), 0.45, 0.035, Color(0.08, 0.08, 0.09))
	_cable(kit, Vector3(67.7, 2.6, -4.2), Vector3(67.7, 2.6, 0.8), 0.6, 0.03, Color(0.5, 0.12, 0.08))
	_cable(kit, Vector3(67.75, 2.7, 0.0), Vector3(67.75, 2.7, 5.5), 0.4, 0.035, Color(0.08, 0.08, 0.09))
	# Transformer cabinet on the east wall, humming.
	var tr := Vector3(67.25, 0, -2.1)
	kit.bevel_box("painted", tr + Vector3(0, 0.95, 0), Vector3(1.0, 1.9, 1.6), 0.06, Color(0.55, 0.57, 0.6))
	for i in range(6):
		kit.box("metal", tr + Vector3(-0.51, 0.5 + float(i) * 0.2, 0), Vector3(0.02, 0.06, 1.3), GUNMETAL)
	kit.box("hazard", tr + Vector3(-0.505, 1.75, 0), Vector3(0.01, 0.16, 1.4), Color.WHITE)
	_text(kit, "painted", "11 KV", tr + Vector3(-0.512, 1.5, 0), Vector3(-1, 0, 0), 0.2, GRAPHITE)
	kit.sphere("blink", tr + Vector3(-0.51, 1.75, 0.6), 0.03, Color(1.0, 0.2, 0.1), 6)
	_collider(body, tr + Vector3(0, 0.95, 0), Vector3(1.04, 1.9, 1.64))
	_reg("transformer", tr + Vector3(0, 0.95, 0), Vector3(1.0, 1.9, 1.6))
	_ao_rect(kit, tr, Vector2(0.5, 0.8), 0.0, 0.35)
	# Workbench in the south-west, with a vice and a parts tray.
	var wb := Vector3(57.9, 0, 5.3)
	kit.bevel_box("metal", wb + Vector3(0, 0.88, 0), Vector3(2.2, 0.07, 0.75), 0.02, Color(0.6, 0.5, 0.35))
	kit.bevel_box("painted", wb + Vector3(0.65, 0.42, 0), Vector3(0.8, 0.84, 0.7), 0.03, color.darkened(0.35))
	for sx in [-1.0, 1.0]:
		kit.box("metal", wb + Vector3(sx * 1.02, 0.42, 0.3), Vector3(0.06, 0.84, 0.06), GUNMETAL)
		kit.box("metal", wb + Vector3(sx * 1.02, 0.42, -0.3), Vector3(0.06, 0.84, 0.06), GUNMETAL)
	kit.bevel_box("metal", wb + Vector3(-0.6, 1.0, 0.2), Vector3(0.25, 0.18, 0.2), 0.02, GUNMETAL)
	kit.bevel_box("painted", wb + Vector3(0.1, 0.95, -0.1), Vector3(0.5, 0.06, 0.3), 0.01, Color(0.2, 0.45, 0.8))
	kit.sphere("painted", wb + Vector3(-0.15, 0.96, 0.1), 0.06, Color(0.95, 0.7, 0.1), 6)
	_collider(body, wb + Vector3(0, 0.46, 0), Vector3(2.2, 0.92, 0.75))
	_reg("workbench", wb + Vector3(0, 0.46, 0), Vector3(2.2, 0.92, 0.75))
	_ao_rect(kit, wb, Vector2(1.1, 0.37), 0.0, 0.3)
	_tool_wall(kit, body, Vector3(56.0, 0, 3.5), PI / 2.0, 1.4, color)
	# Cable spool (cover) and coiled hoses on the floor.
	var spool := Vector3(60.0, 0, 2.6)
	kit.cylinder("painted", spool + Vector3(-0.45, 0.6, 0), spool + Vector3(-0.38, 0.6, 0), 0.6, Color(0.62, 0.45, 0.28), 18)
	kit.cylinder("painted", spool + Vector3(0.38, 0.6, 0), spool + Vector3(0.45, 0.6, 0), 0.6, Color(0.62, 0.45, 0.28), 18)
	kit.cylinder("painted", spool + Vector3(-0.38, 0.6, 0), spool + Vector3(0.38, 0.6, 0), 0.42, Color(0.12, 0.12, 0.13), 18)
	_collider(body, spool + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 1.2))
	_reg("cable_spool", spool + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 1.2))
	_ao_rect(kit, spool, Vector2(0.45, 0.3), 0.0, 0.3)
	_hose_coil(kit, Vector3(64.6, 0, 4.7), Color(0.85, 0.25, 0.1))
	_hose_coil(kit, Vector3(63.7, 0, 5.1), Color(0.15, 0.15, 0.17))
	kit.box("hazard", Vector3(59.2, 0.006, -3.75), Vector3(2.8, 0.012, 0.3), Color.WHITE)


static func _dress_reactor(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var c := Vector3(62, 0, 19.3)
	var core_col := color.lerp(Color(0.85, 0.75, 1.0), 0.45)
	# Bulbous toy reactor: rounded plinth, glowing capsule core in a glass
	# capsule, chunky graphite rings, a domed cap and a thick friendly railing.
	kit.cylinder("painted", c, c + Vector3(0, 0.3, 0), 1.6, GRAPHITE, 32, 1.5)
	kit.torus("metal", c + Vector3(0, 0.3, 0), 1.25, 1.5, BRUSHED, Basis.IDENTITY, 32, 8)
	# Warning rings: hazard band, a violet dashed keep-out circle and text.
	kit.torus("hazard", c + Vector3(0, 0.01, 0), 1.7, 1.95, Color.WHITE, Basis.from_scale(Vector3(1, 0.05, 1)), 40, 4)
	for i in range(24):
		var ang := TAU * float(i) / 24.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * 2.55
		kit.box("sign", p + Vector3(0, 0.006, 0), Vector3(0.1, 0.008, 0.42), core_col * 0.7, _yb(-ang))
	for k in range(2):
		var ang := PI * 0.5 + PI * float(k)
		var tp := c + Vector3(cos(ang), 0, sin(ang)) * 2.25
		_text(kit, "painted", "KEEP CLEAR", tp + Vector3(0, 0.011, 0), Vector3(cos(ang), 0, sin(ang)), 0.2, Color(0.95, 0.75, 0.2), true)
	var core := CapsuleMesh.new()
	core.radius = 0.62
	core.height = 3.3
	core.radial_segments = 24
	core.rings = 8
	kit.mesh("reactor", core, Transform3D(Basis.IDENTITY, c + Vector3(0, 2.05, 0)), core_col)
	var shell := CapsuleMesh.new()
	shell.radius = 0.9
	shell.height = 3.7
	shell.radial_segments = 24
	shell.rings = 8
	kit.mesh("glass", shell, Transform3D(Basis.IDENTITY, c + Vector3(0, 2.1, 0)), Color.WHITE)
	for i in range(3):
		var y := 1.05 + float(i) * 1.0
		kit.torus("painted", c + Vector3(0, y, 0), 0.82, 1.12, GRAPHITE, Basis.IDENTITY, 32, 8)
		kit.torus("trim", c + Vector3(0, y, 0), 1.1, 1.16, color, Basis.IDENTITY, 32, 4)
	for i in range(4):
		var ang := TAU * (float(i) + 0.5) / 4.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * 1.0
		kit.bevel_box("painted", p + Vector3(0, 2.1, 0), Vector3(0.22, 3.4, 0.22), 0.09, GRAPHITE, Basis(Vector3.UP, -ang))
	kit.sphere("painted", c + Vector3(0, 3.95, 0), 1.15, GRAPHITE, 28, Vector3(1, 0.42, 1))
	kit.torus("trim", c + Vector3(0, 3.85, 0), 1.1, 1.18, color, Basis.IDENTITY, 32, 4)
	kit.sphere("reactor", c + Vector3(0, 4.45, 0), 0.32, core_col, 16)
	# Collision: the plinth and its railing (r 1.52 + rail) up to rail height,
	# then the narrower column; socket approach points stay > 2.5 m away.
	_cyl_collider(body, c + Vector3(0, 0.62, 0), 1.6, 1.24)
	_cyl_collider(body, c + Vector3(0, 2.6, 0), 1.18, 2.8)
	_reg("reactor_rail", c + Vector3(0, 0.62, 0), Vector3(3.2, 1.24, 3.2))
	var rail_r := 1.45
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * rail_r
		kit.cylinder("painted", p + Vector3(0, 0.3, 0), p + Vector3(0, 1.15, 0), 0.065, GRAPHITE, 8)
		kit.sphere("painted", p + Vector3(0, 1.17, 0), 0.095, BRUSHED, 8)
	kit.torus("painted", c + Vector3(0, 1.15, 0), rail_r - 0.07, rail_r + 0.07, color.darkened(0.1), Basis.IDENTITY, 40, 8)
	kit.torus("trim", c + Vector3(0, 1.08, 0), rail_r - 0.02, rail_r + 0.02, color.lightened(0.3), Basis.IDENTITY, 40, 4)
	kit.torus("painted", c + Vector3(0, 0.75, 0), rail_r - 0.045, rail_r + 0.045, GRAPHITE, Basis.IDENTITY, 40, 6)
	_ao_rect(kit, c, Vector2(1.5, 1.5), 0.0, 0.8)
	# Energy conduits from each reactor socket to the core.
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		if spec.kind != "reactor":
			continue
		var s := Vector3(spec.pos.x, 0, spec.pos.y)
		var dir := (c - s)
		dir.y = 0
		var dist := dir.length()
		dir = dir / dist
		var a := s + dir * 0.7
		var b := c - dir * 1.62
		var mid := (a + b) * 0.5
		var yaw := atan2(dir.x, dir.z)
		kit.box("painted", mid + Vector3(0, 0.004, 0), Vector3(0.36, 0.008, a.distance_to(b)), DARK, _yb(yaw))
		kit.box("reactor", mid + Vector3(0, 0.012, 0), Vector3(0.1, 0.012, a.distance_to(b)), core_col, _yb(yaw))
	# Coolant pipes along the south wall behind the sockets, dropping into
	# the floor at both ends, with flanges and a pump in the north-west corner.
	var cool := Color(0.3, 0.55, 0.75)
	_pipe_run(kit, Vector3(55.4, 2.35, 25.6), Vector3(68.6, 2.35, 25.6), 0.16, cool)
	_pipe_run(kit, Vector3(55.4, 1.75, 25.68), Vector3(68.6, 1.75, 25.68), 0.11, Color(0.75, 0.75, 0.78))
	for px in [56.0, 68.0]:
		kit.cylinder("painted", Vector3(px, 2.35, 25.6), Vector3(px, 0.0, 25.6), 0.16, cool, 10)
		kit.cylinder("metal", Vector3(px, 0.0, 25.6), Vector3(px, 0.1, 25.6), 0.26, GUNMETAL, 10)
	_text(kit, "painted", "PRIMARY COOLANT", Vector3(62.0, 2.72, 25.42), Vector3(0, 0, -1), 0.13, GRAPHITE)
	_collider(body, Vector3(62.0, 1.3, 25.7), Vector3(13.6, 2.6, 0.6))
	var pump := Vector3(56.35, 0, 15.3)
	kit.bevel_box("painted", pump + Vector3(0, 0.7, 0), Vector3(1.4, 1.4, 1.2), 0.08, Color(0.32, 0.36, 0.5))
	kit.cylinder("painted", pump + Vector3(0, 1.4, 0), pump + Vector3(0, 1.62, 0), 0.4, GRAPHITE, 16)
	_fan(kit, Transform3D(Basis.IDENTITY, pump + Vector3(0, 1.64, 0)), 0.32, 9.0)
	kit.cylinder("painted", pump + Vector3(0.71, 0.5, 0), pump + Vector3(1.2, 0.5, 0), 0.1, cool, 10)
	_valve_wheel(kit, pump + Vector3(0.95, 0.68, 0), Basis.IDENTITY, 0.13, FIRE_RED)
	kit.box("screen", pump + Vector3(0.705, 1.0, -0.25), Vector3(0.01, 0.3, 0.45), core_col)
	_text(kit, "painted", "PUMP 2", pump + Vector3(0.71, 1.0, 0.33), Vector3(1, 0, 0), 0.12, PAPER)
	_collider(body, pump + Vector3(0, 0.8, 0), Vector3(1.44, 1.6, 1.24))
	_reg("pump", pump + Vector3(0, 0.7, 0), Vector3(1.4, 1.4, 1.2))
	_ao_rect(kit, pump, Vector2(0.7, 0.6), 0.0, 0.4)
	# Monitoring console on the east wall.
	_console(kit, body, Vector3(68.25, 0, 16.6), -PI / 2.0, 2.4, Color(0.75, 0.55, 1.0), color)
	_chair(kit, body, Vector3(66.95, 0, 16.6), PI / 2.0, color.darkened(0.4))


static func _dress_medical(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Green cross on the centre emblem.
	var mc := Vector3(0, 0.008, 20)
	kit.box("sign", mc + Vector3(0, 0, -1.2), Vector3(0.5, 0.006, 0.5), color * 0.6)
	# Beds along the west wall, with a privacy curtain between them.
	_bed(kit, body, Vector3(-6.0, 0, 16.3), PI / 2.0, color)
	_bed(kit, body, Vector3(-6.0, 0, 19.2), PI / 2.0, color)
	_curtain(kit, body, Vector3(-6.95, 0, 17.75), Vector3(-4.75, 0, 17.75), Color(0.72, 0.88, 0.78))
	_curtain(kit, body, Vector3(-6.95, 0, 20.75), Vector3(-4.75, 0, 20.75), Color(0.72, 0.88, 0.78))
	# Walk-through body scanner in the middle of the ward.
	_scanner_arch(kit, body, Vector3(-2.0, 0, 19.0), PI / 2.0, 2.2, color)
	# Medical cabinets with glowing crosses on the north wall.
	for cx in [-4.5, 4.6]:
		var cab := Vector3(cx, 0, 14.33)
		kit.bevel_box("painted", cab + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.62), 0.05, Color(0.88, 0.9, 0.9))
		kit.box("trim", cab + Vector3(0, 1.62, 0.315), Vector3(0.36, 0.1, 0.01), color)
		kit.box("trim", cab + Vector3(0, 1.62, 0.315), Vector3(0.1, 0.36, 0.01), color)
		kit.box("glass", cab + Vector3(0, 0.85, 0.315), Vector3(1.5, 0.9, 0.01), Color.WHITE)
		for sy in [0.62, 0.95]:
			kit.box("metal", cab + Vector3(0, sy, 0.1), Vector3(1.5, 0.02, 0.36), BRUSHED)
			for k in range(5):
				kit.cylinder("painted", cab + Vector3(-0.6 + float(k) * 0.3, sy + 0.01, 0.12), cab + Vector3(-0.6 + float(k) * 0.3, sy + 0.16, 0.12), 0.045, [PAPER, Color(0.95, 0.6, 0.2), Color(0.4, 0.7, 1.0)][k % 3], 6)
		_collider(body, cab + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.62))
		_reg("cabinet", cab + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.62))
		_ao_rect(kit, cab, Vector2(0.9, 0.31), 0.0, 0.35)
	# Doctor's desk on the east wall.
	_console(kit, body, Vector3(6.25, 0, 16.2), -PI / 2.0, 2.0, Color(0.4, 1.0, 0.6), color)
	_chair(kit, body, Vector3(5.0, 0, 16.2), PI / 2.0, Color(0.85, 0.88, 0.9))
	# Scanner tower, IV stand and a supply crate along the south wall.
	kit.bevel_box("painted", Vector3(6.2, 1.1, 25.55), Vector3(1.0, 2.2, 0.7), 0.05, Color(0.85, 0.87, 0.88))
	kit.box("screen", Vector3(6.2, 1.45, 25.19), Vector3(0.75, 0.6, 0.01), Color(0.4, 1.0, 0.55))
	kit.box("trim", Vector3(6.2, 0.6, 25.19), Vector3(0.75, 0.05, 0.01), color)
	kit.sphere("breathe", Vector3(6.2, 1.95, 25.19), 0.05, LED_GREEN, 8)
	_collider(body, Vector3(6.2, 1.1, 25.55), Vector3(1.0, 2.2, 0.7))
	_reg("scanner_tower", Vector3(6.2, 1.1, 25.55), Vector3(1.0, 2.2, 0.7))
	_ao_rect(kit, Vector3(6.2, 0, 25.55), Vector2(0.5, 0.35), 0.0, 0.35)
	var iv := Vector3(1.4, 0, 24.6)
	kit.cylinder("metal", iv + Vector3(0, 0.02, 0), iv + Vector3(0, 1.9, 0), 0.025, GUNMETAL, 6)
	kit.cylinder("metal", iv, iv + Vector3(0, 0.04, 0), 0.25, GUNMETAL, 12)
	kit.box("glass", iv + Vector3(0, 1.65, 0), Vector3(0.14, 0.24, 0.05), Color.WHITE)
	kit.box("screen", iv + Vector3(0, 1.6, 0), Vector3(0.1, 0.12, 0.03), Color(0.5, 0.9, 1.0))
	kit.box("metal", iv + Vector3(0, 1.88, 0), Vector3(0.4, 0.03, 0.03), GUNMETAL)
	_cyl_collider(body, iv + Vector3(0, 0.95, 0), 0.25, 1.9)
	_reg("iv_stand", iv + Vector3(0, 0.95, 0), Vector3(0.5, 1.9, 0.5))
	_crate(kit, body, Vector3(-1.0, 0, 25.3), Vector3(1.0, 0.9, 0.8), Color(0.82, 0.84, 0.86), 0.0, "MED")
	_potted_plant(kit, body, Vector3(-6.4, 0, 25.4), 13)


static func _dress_observation(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var deck: Dictionary = StationLayout.PLATFORMS["observation_deck"]
	var dh: float = deck.height
	var deck_r: Rect2 = deck.rect
	# On the deck: sofas facing the panorama, a telescope at the centre.
	_sofa(kit, body, Vector3(26.4, dh, 16.75), PI, 2.4, color.darkened(0.3))
	_sofa(kit, body, Vector3(35.6, dh, 16.75), PI, 2.4, color.darkened(0.3))
	var scope := Vector3(31.0, dh, 15.9)
	for k in range(3):
		var ang := TAU * float(k) / 3.0 + 0.4
		kit.cylinder("metal", scope + Vector3(cos(ang) * 0.38, 0.0, sin(ang) * 0.38), scope + Vector3(0, 1.05, 0), 0.025, BRUSHED, 6)
	kit.sphere("painted", scope + Vector3(0, 1.08, 0), 0.09, GRAPHITE, 8)
	var tube_b := Basis(Vector3.RIGHT, -PI / 2.0 + 0.45)
	kit.cylinder("painted", scope + Vector3(0, 1.15, 0.45), scope + Vector3(0, 1.15, 0.45) + tube_b * Vector3(0, 1.3, 0), 0.11, Color(0.92, 0.9, 0.85), 14, 0.14)
	kit.cylinder("trim", scope + Vector3(0, 1.15, 0.45) + tube_b * Vector3(0, 1.18, 0), scope + Vector3(0, 1.15, 0.45) + tube_b * Vector3(0, 1.24, 0), 0.145, color.lightened(0.2), 14)
	kit.cylinder("metal", scope + Vector3(0, 1.15, 0.45), scope + Vector3(0, 1.15, 0.45) - tube_b * Vector3(0, 0.25, 0), 0.04, GUNMETAL, 8)
	_cyl_collider(body, scope + Vector3(0, 0.75, 0), 0.45, 1.5)
	_reg("telescope", scope + Vector3(0, 0.75, 0), Vector3(0.9, 1.5, 0.9))
	_text(kit, "sign", "OBSERVATION DECK", Vector3(31.0, dh + 0.008, deck_r.end.y - 0.5), Vector3(0, 0, 1), 0.3, color * 0.75, true)
	# Lounge floor: two pillars break the long sightline from door to door.
	_pillar(kit, body, Vector3(28.5, 0, 22.4), 0.55, color)
	_pillar(kit, body, Vector3(33.5, 0, 22.4), 0.55, color)
	# Starlight bar along the south wall: counter, stools, back shelf, neon.
	var bar := Vector3(30.6, 0, 25.95)
	kit.bevel_box("painted", bar + Vector3(0, 0.52, 0), Vector3(5.6, 1.04, 0.8), 0.08, color.darkened(0.55))
	kit.bevel_box("metal", bar + Vector3(0, 1.07, -0.05), Vector3(5.7, 0.06, 0.92), 0.03, BRUSHED)
	kit.box("trim", bar + Vector3(0, 0.98, -0.405), Vector3(5.4, 0.03, 0.01), color.lightened(0.3))
	kit.box("breathe", bar + Vector3(0, 0.12, -0.405), Vector3(5.4, 0.03, 0.01), color.lightened(0.1))
	_collider(body, bar + Vector3(0, 0.55, -0.05), Vector3(5.7, 1.1, 0.92))
	_reg("bar_counter", bar + Vector3(0, 0.52, 0), Vector3(5.6, 1.04, 0.8))
	_ao_rect(kit, bar, Vector2(2.8, 0.4), 0.0, 0.35)
	for i in range(5):
		var st := Vector3(28.4 + float(i) * 1.1, 0, 25.05)
		kit.cylinder("metal", st, st + Vector3(0, 0.04, 0), 0.22, GUNMETAL, 12)
		kit.cylinder("metal", st + Vector3(0, 0.04, 0), st + Vector3(0, 0.7, 0), 0.04, BRUSHED, 6)
		kit.torus("metal", st + Vector3(0, 0.3, 0), 0.14, 0.17, BRUSHED, Basis.IDENTITY, 12, 4)
		kit.cylinder("soft", st + Vector3(0, 0.68, 0), st + Vector3(0, 0.78, 0), 0.21, color.darkened(0.2), 14)
		_cyl_collider(body, st + Vector3(0, 0.39, 0), 0.22, 0.78)
		_reg("stool", st + Vector3(0, 0.39, 0), Vector3(0.44, 0.78, 0.44))
	for sy in [1.35, 1.8]:
		kit.bevel_box("metal", Vector3(30.6, sy, 26.82), Vector3(4.4, 0.04, 0.3), 0.01, BRUSHED)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(sy * 100.0)
		var bx := 28.6
		while bx < 32.6:
			var bc: Color = [Color(0.3, 0.75, 0.4), Color(0.85, 0.5, 0.15), Color(0.5, 0.75, 1.0), Color(0.9, 0.3, 0.45)][rng.randi() % 4]
			var hgt := rng.randf_range(0.22, 0.34)
			kit.cylinder("glass", Vector3(bx, sy + 0.02, 26.8), Vector3(bx, sy + 0.02 + hgt, 26.8), 0.05, Color.WHITE, 8, 0.03)
			kit.cylinder("screen", Vector3(bx, sy + 0.03, 26.8), Vector3(bx, sy + hgt * 0.6, 26.8), 0.04, bc, 8)
			bx += rng.randf_range(0.18, 0.3)
	_text(kit, "breathe", "STARLIGHT", Vector3(30.6, 2.36, 26.95), Vector3(0, 0, -1), 0.36, Color(1.0, 0.55, 0.8))
	_text(kit, "sign", "LOUNGE  .  BAR", Vector3(30.6, 2.12, 26.95), Vector3(0, 0, -1), 0.12, Color(1.0, 0.85, 0.9))
	# South-west booth: L of sofas around a low table, plants behind.
	_sofa(kit, body, Vector3(23.45, 0, 24.6), PI / 2.0, 2.4, color.darkened(0.3))
	_sofa(kit, body, Vector3(25.35, 0, 26.55), PI, 2.0, color.darkened(0.3))
	var tbl := Vector3(25.1, 0, 24.65)
	kit.cylinder("painted", tbl, tbl + Vector3(0, 0.42, 0), 0.12, GRAPHITE, 10)
	kit.cylinder("metal", tbl + Vector3(0, 0.42, 0), tbl + Vector3(0, 0.47, 0), 0.5, BRUSHED, 18)
	kit.cylinder("glass", tbl + Vector3(0.12, 0.47, 0.05), tbl + Vector3(0.12, 0.6, 0.05), 0.04, Color.WHITE, 8)
	_cyl_collider(body, tbl + Vector3(0, 0.235, 0), 0.5, 0.47)
	_reg("booth_table", tbl + Vector3(0, 0.235, 0), Vector3(1.0, 0.47, 1.0))
	# South-east alcove behind a planter wall: the private-chat corner.
	_planter(kit, body, Vector3(37.3, 0, 22.95), Vector2(3.4, 0.6), 0.9, 23, color)
	_planter(kit, body, Vector3(35.75, 0, 23.9), Vector2(0.6, 1.3), 0.9, 29, color)
	_sofa(kit, body, Vector3(38.55, 0, 25.3), -PI / 2.0, 2.2, Color(0.35, 0.3, 0.45))
	_vending(kit, body, Vector3(36.6, 0, 26.55), PI, Color(0.3, 0.2, 0.35), Color(1.0, 0.5, 0.75), "COSMO")
	_potted_plant(kit, body, Vector3(23.6, 0, 22.3), 17)
	_potted_plant(kit, body, Vector3(38.5, 0, 18.75), 19)


static func _dress_airlock(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var r := StationLayout.room_rect("airlock")
	# Hazard border and a central drain grate.
	kit.box_mm("hazard", Vector3(r.position.x + 0.05, 0.0, r.position.y + 0.05), Vector3(r.end.x - 0.05, 0.011, r.position.y + 0.35), Color.WHITE)
	kit.box_mm("hazard", Vector3(r.position.x + 0.05, 0.0, r.end.y - 0.35), Vector3(r.end.x - 0.05, 0.011, r.end.y - 0.05), Color.WHITE)
	kit.box_mm("hazard", Vector3(r.position.x + 0.05, 0.0, r.position.y + 0.05), Vector3(r.position.x + 0.35, 0.011, r.end.y - 0.05), Color.WHITE)
	var c := Vector3((r.position.x + r.end.x) * 0.5, 0, (r.position.y + r.end.y) * 0.5)
	kit.box("metal", c + Vector3(0, 0.006, 0), Vector3(1.6, 0.012, 1.6), Color(0.18, 0.19, 0.2))
	for i in range(7):
		kit.box("painted", c + Vector3(-0.6 + float(i) * 0.2, 0.013, 0), Vector3(0.06, 0.004, 1.4), Color(0.04, 0.04, 0.05))
	_text(kit, "painted", "VACUUM DANGER", c + Vector3(0.95, 0.012, 0), Vector3(1, 0, 0), 0.22, Color(0.95, 0.4, 0.15), true)
	# Suit lockers on the north and south walls (a helmet behind each window).
	for sz in [-1.0, 1.0]:
		for i in range(2):
			var p := Vector3(r.position.x + 1.6 + float(i) * 1.0, 0, (r.position.y + 0.3) if sz < 0.0 else (r.end.y - 0.3))
			kit.bevel_box("painted", p + Vector3(0, 1.0, 0), Vector3(0.9, 2.0, 0.5), 0.04, Color(0.3, 0.32, 0.35))
			kit.box("glass", p + Vector3(0, 1.25, -sz * 0.255), Vector3(0.6, 1.2, 0.01), Color.WHITE)
			kit.sphere("painted", p + Vector3(0, 1.6, 0.0), 0.17, Color(0.85, 0.85, 0.82), 10)
			kit.box("painted", p + Vector3(0, 1.05, 0.0), Vector3(0.4, 0.7, 0.2), Color(0.85, 0.5, 0.2))
			kit.box("trim", p + Vector3(0, 0.15, -sz * 0.255), Vector3(0.6, 0.04, 0.01), color)
			kit.sphere("blink", p + Vector3(0.36, 1.92, -sz * 0.256), 0.02, LED_GREEN, 6)
		var lc := Vector3(r.position.x + 2.1, 1.0, (r.position.y + 0.3) if sz < 0.0 else (r.end.y - 0.3))
		_collider(body, lc, Vector3(1.9, 2.0, 0.5))
		_reg("suit_lockers", lc, Vector3(1.9, 2.0, 0.5))
		_ao_rect(kit, Vector3(lc.x, 0, lc.z), Vector2(0.95, 0.25), 0.0, 0.3)
	# Pressure gauges by the inner door.
	for sz in [-1.0, 1.0]:
		kit.box("screen", Vector3(r.end.x - 0.03, 1.6, sz * 1.95), Vector3(0.01, 0.4, 0.5), Color(1.0, 0.55, 0.2))


# --- exterior -----------------------------------------------------------------------------

static func _build_exterior(fx: ArtStationFX, mats: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Exterior"
	fx.add_child(node)
	_ctx_shadow = null
	var kit := _new_kit()
	var solar_mat := ArtMaterials.world_pbr("floor_plate", Color(0.25, 0.35, 0.75), 0.6, 0.6, 1.0, -0.25)
	var ext_mats := mats.duplicate()
	ext_mats["solar"] = solar_mat
	# Solar wings: west of Commons and east of Engineering.
	for wing in [[Vector3(-7.4, 1.6, 20.0), -1.0], [Vector3(68.4, 1.6, 0), 1.0]]:
		var root: Vector3 = wing[0]
		var dir: float = wing[1]
		var tip := root + Vector3(dir * 27.0, 0, 0)
		kit.bevel_box("metal", (root + tip) * 0.5, Vector3(27.0, 0.45, 0.45), 0.08, GUNMETAL)
		for i in range(3):
			var px := root.x + dir * (5.5 + float(i) * 7.5)
			for sz in [-1.0, 1.0]:
				var pc := Vector3(px, root.y, root.z + sz * 5.6)
				var pb := Basis(Vector3.RIGHT, sz * 0.32)
				kit.box("solar", pc, Vector3(6.6, 0.08, 9.6), Color.WHITE, pb)
				kit.bevel_box("metal", pc + pb * Vector3(0, -0.06, 0), Vector3(6.8, 0.06, 9.8), 0.02, GUNMETAL, pb)
				kit.cylinder("metal", Vector3(px, root.y, root.z), pc + pb * Vector3(0, -0.1, -sz * 4.6), 0.08, GUNMETAL, 6)
		kit.sphere("nav", tip, 0.25, Color(1.0, 0.15, 0.1) if dir < 0 else Color(0.2, 1.0, 0.3), 10)
	# Radiator fins north of Security.
	for i in range(5):
		var fx_pos := Vector3(36.0 + float(i) * 2.2, 1.6, -31.0)
		kit.bevel_box("painted", fx_pos, Vector3(0.12, 2.8, 8.0), 0.03, Color(0.85, 0.85, 0.83))
		kit.box("trim", fx_pos + Vector3(0, 1.42, 0), Vector3(0.14, 0.04, 8.0), Color(1.0, 0.45, 0.2))
	kit.bevel_box("metal", Vector3(40.4, 1.6, -27.0), Vector3(10.0, 0.4, 0.4), 0.06, GUNMETAL)
	kit.bevel_box("metal", Vector3(40.4, 1.6, -31.0), Vector3(10.0, 0.3, 0.3), 0.05, GUNMETAL)
	# Comms mast and dish off Security's north-east corner (kept out of the
	# planet's sight line from the west rooms).
	var mast := Vector3(49.6, 0, -28.0)
	kit.cylinder("metal", mast + Vector3(0, -0.8, 0), mast + Vector3(0, 7.0, 0), 0.18, GUNMETAL, 10)
	kit.bevel_box("metal", mast + Vector3(1.0, 1.0, 0), Vector3(2.0, 0.3, 0.3), 0.04, GUNMETAL)
	var dish := CylinderMesh.new()
	dish.top_radius = 2.2
	dish.bottom_radius = 0.3
	dish.height = 0.7
	dish.radial_segments = 24
	dish.rings = 1
	kit.mesh("painted", dish, Transform3D(Basis(Vector3.RIGHT, -0.9) * Basis(Vector3.UP, 0.4), mast + Vector3(0, 7.3, 0)), Color(0.85, 0.85, 0.83))
	kit.sphere("nav", mast + Vector3(0, 7.15, 0), 0.18, Color(1.0, 0.2, 0.1), 8)
	# Navigation lights on the outer corners.
	var corners := [[Vector3(-7.4, H + 0.3, -26.4), Color(1, 0.15, 0.1)], [Vector3(-7.4, H + 0.3, 26.4), Color(1, 0.15, 0.1)], [Vector3(69.4, H + 0.3, 26.4), Color(0.2, 1, 0.3)], [Vector3(68.4, H + 0.3, -6.4), Color(0.2, 1, 0.3)], [Vector3(47.4, H + 0.3, -26.4), Color(1, 1, 1)], [Vector3(31.0, H + 0.3, 27.4), Color(1, 1, 1)]]
	for corner in corners:
		kit.sphere("nav", corner[0], 0.16, corner[1], 8)
	node.add_child(kit.to_instance(ext_mats, "Mesh"))


# --- airlock ---------------------------------------------------------------------------------

const AIRLOCK_DOOR_HALF := 1.1
const AIRLOCK_DOOR_TOP := 2.6


## West wall of the airlock with the heavy outer hull door (two sliding leaves).
## Collision always spans the opening: players never leave the station.
static func _airlock_outer_wall(fx: ArtStationFX, kit: ArtMeshKit, body: StaticBody3D, node: Node3D, fixed: float, a0: float, a1: float, color: Color) -> void:
	var hw := AIRLOCK_DOOR_HALF
	var mid := (a0 + a1) * 0.5
	_wall(kit, body, false, fixed, a0, mid - hw, -1.0, color, color, false, "bare")
	_wall(kit, body, false, fixed, mid + hw, a1, -1.0, color, color, false, "bare")
	var across := fixed - T * 0.5
	_wbox(kit, "wall", false, mid - hw, mid + hw, AIRLOCK_DOOR_TOP, TRIM_LO, across, T, WALL_TINT)
	_wbox(kit, "trim", false, mid - hw, mid + hw, TRIM_LO, TRIM_HI, across, T + 0.05, color)
	_wbox(kit, "painted", false, mid - hw, mid + hw, TRIM_HI, H, across, T + 0.04, DARK)
	kit.bevel_box("metal", Vector3(across, H + 0.05, mid), Vector3(T + 0.16, 0.1, hw * 2.0), 0.03, GUNMETAL)
	_collider(body, Vector3(across, COLLIDER_TOP * 0.5, mid), Vector3(T, COLLIDER_TOP, hw * 2.0))
	# Heavy hazard-striped frame on the inner face, warning lamps on top.
	for sz in [-1.0, 1.0]:
		var post := Vector3(fixed + 0.18, 1.45, mid + sz * (hw + 0.17))
		kit.bevel_box("metal", post, Vector3(0.36, 2.9, 0.34), 0.05, GUNMETAL)
		kit.box("hazard", post + Vector3(0.185, -0.6, 0), Vector3(0.01, 1.4, 0.26), Color.WHITE)
		kit.sphere("alarm", Vector3(fixed + 0.25, 3.0, mid + sz * (hw + 0.17)), 0.12, Color(1.0, 0.12, 0.05), 10)
		_collider(body, post, Vector3(0.36, 2.9, 0.34))
	kit.bevel_box("metal", Vector3(fixed + 0.18, AIRLOCK_DOOR_TOP + 0.17, mid), Vector3(0.36, 0.34, hw * 2.0 + 0.68), 0.05, GUNMETAL)
	kit.box("alarm", Vector3(fixed + 0.18, AIRLOCK_DOOR_TOP - 0.01, mid), Vector3(0.2, 0.02, hw * 2.0), Color(1.0, 0.12, 0.05))
	kit.box("hazard", Vector3(fixed + 0.365, AIRLOCK_DOOR_TOP + 0.17, mid), Vector3(0.01, 0.26, hw * 2.0 + 0.4), Color.WHITE)
	# Door track rails.
	kit.box("metal", Vector3(across, 0.02, mid), Vector3(0.3, 0.04, hw * 4.0), GUNMETAL)
	# The leaves: separate nodes so the FX can slide them.
	var mats := {"painted": ArtMaterials.painted(), "metal": ArtMaterials.metal(), "hazard": fx.mats.get("hazard_ref", ArtMaterials.hazard()), "glass": ArtMaterials.glass(Color(0.55, 0.75, 0.95), 0.08)}
	for sz: float in [-1.0, 1.0]:
		var leaf_kit := _new_kit()
		var w := hw  # leaf width (z)
		var inner_z := -sz * w * 0.5  # local z of the meeting edge
		var win_lo := 1.35
		var win_hi := 1.95
		var wz0 := -0.18
		var wz1 := 0.18
		var th := 0.22
		leaf_kit.box_mm("painted", Vector3(-th * 0.5, 0.0, -w * 0.5), Vector3(th * 0.5, win_lo, w * 0.5), Color(0.55, 0.32, 0.18))
		leaf_kit.box_mm("painted", Vector3(-th * 0.5, win_hi, -w * 0.5), Vector3(th * 0.5, AIRLOCK_DOOR_TOP, w * 0.5), Color(0.55, 0.32, 0.18))
		leaf_kit.box_mm("painted", Vector3(-th * 0.5, win_lo, -w * 0.5), Vector3(th * 0.5, win_hi, wz0), Color(0.55, 0.32, 0.18))
		leaf_kit.box_mm("painted", Vector3(-th * 0.5, win_lo, wz1), Vector3(th * 0.5, win_hi, w * 0.5), Color(0.55, 0.32, 0.18))
		leaf_kit.quad("glass", Vector3(0, win_lo, wz0), Vector3(0, win_lo, wz1), Vector3(0, win_hi, wz1), Vector3(0, win_hi, wz0), Vector3(1, 0, 0), Color.WHITE)
		for fx_off in [-th * 0.5 - 0.02, th * 0.5 + 0.02]:
			leaf_kit.box("metal", Vector3(fx_off, (win_lo + win_hi) * 0.5, wz0 - 0.03), Vector3(0.04, win_hi - win_lo + 0.12, 0.06), GUNMETAL)
			leaf_kit.box("metal", Vector3(fx_off, (win_lo + win_hi) * 0.5, wz1 + 0.03), Vector3(0.04, win_hi - win_lo + 0.12, 0.06), GUNMETAL)
			leaf_kit.box("metal", Vector3(fx_off, win_lo - 0.03, 0), Vector3(0.04, 0.06, wz1 - wz0 + 0.12), GUNMETAL)
			leaf_kit.box("metal", Vector3(fx_off, win_hi + 0.03, 0), Vector3(0.04, 0.06, wz1 - wz0 + 0.12), GUNMETAL)
			leaf_kit.box("hazard", Vector3(fx_off, 0.3, 0), Vector3(0.02, 0.45, w - 0.06), Color.WHITE)
			leaf_kit.box("metal", Vector3(fx_off, 1.0, inner_z + sz * 0.08), Vector3(0.05, 1.6, 0.08), GUNMETAL)
		var leaf := leaf_kit.to_instance(mats, "OuterDoor" + ("L" if sz < 0.0 else "R"))
		leaf.position = Vector3(across, 0.0, mid + sz * w * 0.5)
		node.add_child(leaf)
		fx.airlock_doors.append(leaf)
		fx.airlock_door_closed.append(leaf.position)
		fx.airlock_door_open_dir.append(Vector3(0, 0, sz * w * 0.95))
	var klaxon := OmniLight3D.new()
	klaxon.name = "Klaxon"
	klaxon.position = Vector3(fixed + 2.5, 2.7, mid)
	klaxon.light_color = Color(1.0, 0.1, 0.05)
	klaxon.omni_range = 8.5
	klaxon.shadow_enabled = false
	klaxon.visible = false
	node.add_child(klaxon)
	fx.airlock_light = klaxon
	_text(kit, "sign", "OUTER HULL DOOR", Vector3(fixed + 0.37, AIRLOCK_DOOR_TOP + 0.17, mid), Vector3(1, 0, 0), 0.13, Color(1.0, 0.85, 0.6))
