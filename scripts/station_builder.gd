class_name StationBuilder
extends RefCounted
## Procedural art + collision for Drift Station, built from StationLayout.
## build() adds a "Station" node (an ArtStationFX) with environment, lighting,
## per-room merged meshes, collision (layer 1), signage, decor, exterior and sky.
## set_power_state() tweens between "emergency", "restored" and "blackout".

const T := 0.4  # wall thickness (walls sit outside the room/corridor rects)
const H := StationLayout.WALL_HEIGHT
const COLLIDER_TOP := StationLayout.WALL_HEIGHT + 1.8
const KICK := 0.3
const TRIM_LO := 2.72
const TRIM_HI := 2.8
const SILL := 1.0
const WIN_TOP := 2.45
const WIN_HALF := 0.9
const WIN_PITCH := 3.0
const LINTEL := 2.7  # top of the doorway light strips
const SUN_DIR := Vector3(0.55, 0.72, -0.42)
const WALL_TINT := Color(0.74, 0.76, 0.79)
const DARK := Color(0.16, 0.17, 0.19)
const GUNMETAL := Color(0.3, 0.32, 0.35)
const EMERGENCY_RED := Color(1.0, 0.1, 0.04)
const GUIDE := Color(0.45, 0.85, 1.0)
const COVE := Color(1.0, 0.9, 0.76)
const SCREEN_BLUE := Color(0.3, 0.72, 1.0)
const BEACON := Color(1.0, 0.28, 0.04)
const AO_DARK := Color(0.42, 0.42, 0.45)

## Floor label offsets so names don't sit under big centre props.
const LABEL_OFFSET := {"reactor": Vector2(0, -3.1), "command": Vector2(0, 2.6), "docking": Vector2(0, 3.0)}
## Floor names read from the room's main entrance (direction to the reader).
const LABEL_FACING := {"reactor": Vector3(0, 0, -1), "medical": Vector3(0, 0, -1), "engineering": Vector3(-1, 0, 0), "airlock": Vector3(1, 0, 0)}


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
	for i in range(ArtStationFX.LIGHT_GROUPS.size()):
		kit.remap[ArtStationFX.LIGHT_GROUPS[i]] = ["lights", float(i) / 7.0]
	return kit


static func _make_materials() -> Dictionary:
	var mats := {
		"floor": ArtMaterials.world_pbr("floor_plate", Color(0.92, 0.94, 0.98), 2.0, 1.0, 1.0, 0.0),
		"wall": ArtMaterials.world_pbr("wall_panel", WALL_TINT, 2.0, 1.0, 1.0, 0.0),
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
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = false
	for level in range(7):
		env.set_glow_level(level, [0.0, 1.0, 0.8, 1.0, 0.6, 0.0, 0.0][level])
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.13)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
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
	sun.directional_shadow_max_distance = 40.0
	sun.light_angular_distance = 0.6
	sun.shadow_blur = 1.2
	fx.sun = sun
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


# --- small helpers --------------------------------------------------------------------

## Point from wall-local coordinates: `along` the wall, `across` the fixed axis.
static func _v(along_x: bool, along: float, y: float, across: float) -> Vector3:
	return Vector3(along, y, across) if along_x else Vector3(across, y, along)


static func _s(along_x: bool, sa: float, sy: float, sc: float) -> Vector3:
	return Vector3(sa, sy, sc) if along_x else Vector3(sc, sy, sa)


static func _wbox(kit: ArtMeshKit, key: String, along_x: bool, a0: float, a1: float, y0: float, y1: float, across: float, depth: float, color: Color, color_b = null) -> void:
	var c := _v(along_x, (a0 + a1) * 0.5, (y0 + y1) * 0.5, across)
	kit.box(key, c, _s(along_x, a1 - a0, y1 - y0, depth), color, Basis.IDENTITY, color_b, 0 if along_x else 2)


static func _collider(body: StaticBody3D, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)


static func _cyl_collider(body: StaticBody3D, center: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


static func _body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	return body


static var _font: FontVariation


static func _sign_font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.7
		_font.spacing_glyph = 6
	return _font


static func _label(fx: ArtStationFX, parent: Node3D, text: String, pos: Vector3, facing: Vector3, font_size: int, pixel: float, color: Color, flat := false) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _sign_font()
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = maxi(4, font_size / 10)
	label.double_sided = false
	label.shaded = false
	label.modulate = color
	label.position = pos
	if flat:
		label.rotation_order = EULER_ORDER_YXZ
		label.rotation = Vector3(-PI / 2.0, atan2(facing.x, facing.z), 0.0)
	else:
		label.rotation.y = atan2(facing.x, facing.z)
	parent.add_child(label)
	fx.labels.append(label)
	fx.label_colors.append(color)
	return label


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


## Soft contact shadow around a footprint (half extents `half`, rotated by yaw).
static func _ao_rect(kit: ArtMeshKit, center: Vector3, half: Vector2, yaw := 0.0, spread := 0.45, darkness := AO_DARK) -> void:
	var b := Basis(Vector3.UP, yaw)
	var y := Vector3(0, 0.005, 0)
	var inner := [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]
	var outer := [Vector3(-half.x - spread, 0, -half.y - spread), Vector3(half.x + spread, 0, -half.y - spread), Vector3(half.x + spread, 0, half.y + spread), Vector3(-half.x - spread, 0, half.y + spread)]
	var c := Vector3(center.x, 0, center.z) + y
	kit.quad_grad("ao", c + b * inner[0], c + b * inner[1], c + b * inner[2], c + b * inner[3], Vector3.UP, darkness, darkness)
	for i in range(4):
		var j := (i + 1) % 4
		kit.quad_grad("ao", c + b * inner[i], c + b * inner[j], c + b * outer[j], c + b * outer[i], Vector3.UP, darkness, Color.WHITE)


# --- walls -----------------------------------------------------------------------------

## Builds one straight wall segment on the boundary line `fixed` (z when the wall
## runs along x, otherwise x), spanning `a0..a1`, extending `outward` (+1/-1) by T.
## Exterior stretches get windows. Returns window centres (along coordinate).
static func _wall(kit: ArtMeshKit, body: StaticBody3D, along_x: bool, fixed: float, a0: float, a1: float, outward: float, accent: Color, accent_b: Color, windows_ok: bool) -> Array[float]:
	var length := a1 - a0
	var mid_across := fixed + outward * T * 0.5
	_collider(body, _v(along_x, (a0 + a1) * 0.5, COLLIDER_TOP * 0.5, mid_across), _s(along_x, length, COLLIDER_TOP, T))
	var windows: Array[float] = []
	if windows_ok and length >= 3.0:
		var count := int(floor((length - 0.8) / WIN_PITCH))
		var first := (a0 + a1) * 0.5 - float(count - 1) * WIN_PITCH * 0.5
		for i in range(count):
			var w := first + float(i) * WIN_PITCH
			var near := _flat(_v(along_x, w, 0.0, fixed + outward * 1.6))
			var far := _flat(_v(along_x, w, 0.0, fixed + outward * 4.5))
			if not _inside_station(near) and not _inside_station(far):
				windows.append(w)
	var wall_c := WALL_TINT
	# Contact shadow on the floor along the inner face.
	var inner := fixed - outward * 0.004
	var reach := fixed - outward * 0.95
	var n_up := Vector3.UP
	kit.quad_grad("ao", _v(along_x, a0, 0.004, inner), _v(along_x, a1, 0.004, inner), _v(along_x, a1, 0.004, reach), _v(along_x, a0, 0.004, reach), n_up, AO_DARK, Color.WHITE)
	# Kickplate, main panels (with window openings), trim, upper band, cap, cove.
	_wbox(kit, "painted", along_x, a0, a1, 0.0, KICK, mid_across, T + 0.06, DARK)
	_wbox(kit, "emergency", along_x, a0, a1, 0.36, 0.43, mid_across, T + 0.1, EMERGENCY_RED)
	if windows.is_empty():
		_wbox(kit, "wall", along_x, a0, a1, KICK, TRIM_LO, mid_across, T, wall_c)
		var rib := ceilf((a0 + 0.5) / 2.0) * 2.0
		while rib < a1 - 0.5:
			kit.bevel_box("painted", _v(along_x, rib, (KICK + TRIM_LO) * 0.5, mid_across), _s(along_x, 0.24, TRIM_LO - KICK, T + 0.12), 0.04, GUNMETAL)
			rib += 2.0
	else:
		_wbox(kit, "wall", along_x, a0, a1, KICK, SILL, mid_across, T, wall_c)
		_wbox(kit, "wall", along_x, a0, a1, WIN_TOP, TRIM_LO, mid_across, T, wall_c)
		var cursor := a0
		for w in windows:
			_wbox(kit, "wall", along_x, cursor, w - WIN_HALF, SILL, WIN_TOP, mid_across, T, wall_c)
			cursor = w + WIN_HALF
			_window(kit, along_x, w, mid_across, outward)
		_wbox(kit, "wall", along_x, cursor, a1, SILL, WIN_TOP, mid_across, T, wall_c)
		for i in range(windows.size() - 1):
			var pillar := (windows[i] + windows[i + 1]) * 0.5
			kit.bevel_box("painted", _v(along_x, pillar, (KICK + TRIM_LO) * 0.5, mid_across), _s(along_x, 0.24, TRIM_LO - KICK, T + 0.12), 0.04, GUNMETAL)
	_wbox(kit, "trim", along_x, a0, a1, TRIM_LO, TRIM_HI, mid_across, T + 0.05, accent, accent_b)
	_wbox(kit, "painted", along_x, a0, a1, TRIM_HI, H, mid_across, T + 0.04, DARK)
	kit.bevel_box("metal", _v(along_x, (a0 + a1) * 0.5, H + 0.05, mid_across), _s(along_x, length, 0.1, T + 0.16), 0.03, GUNMETAL)
	_wbox(kit, "ceiling", along_x, a0, a1, H + 0.1, H + 0.12, mid_across, 0.05, COVE)
	return windows


static func _window(kit: ArtMeshKit, along_x: bool, w: float, across: float, outward: float) -> void:
	var n := _v(along_x, 0.0, 0.0, outward).normalized()
	var a := _v(along_x, w - WIN_HALF, SILL, across)
	var b := _v(along_x, w + WIN_HALF, SILL, across)
	var c := _v(along_x, w + WIN_HALF, WIN_TOP, across)
	var d := _v(along_x, w - WIN_HALF, WIN_TOP, across)
	kit.quad("glass", a, b, c, d, n, Color.WHITE)
	var depth := T + 0.1
	kit.bevel_box("metal", _v(along_x, w, SILL - 0.04, across), _s(along_x, WIN_HALF * 2.0 + 0.2, 0.1, depth + 0.06), 0.03, GUNMETAL)
	kit.bevel_box("metal", _v(along_x, w, WIN_TOP + 0.04, across), _s(along_x, WIN_HALF * 2.0 + 0.2, 0.1, depth), 0.03, GUNMETAL)
	kit.bevel_box("metal", _v(along_x, w - WIN_HALF - 0.04, (SILL + WIN_TOP) * 0.5, across), _s(along_x, 0.1, WIN_TOP - SILL, depth), 0.03, GUNMETAL)
	kit.bevel_box("metal", _v(along_x, w + WIN_HALF + 0.04, (SILL + WIN_TOP) * 0.5, across), _s(along_x, 0.1, WIN_TOP - SILL, depth), 0.03, GUNMETAL)
	kit.box("metal", _v(along_x, w, (SILL + WIN_TOP) * 0.5, across), _s(along_x, 0.05, WIN_TOP - SILL, 0.08), GUNMETAL)


static func _beacon(kit: ArtMeshKit, pos: Vector3, inward: Vector3) -> void:
	kit.bevel_box("painted", pos, Vector3(0.2, 0.12, 0.2), 0.02, DARK)
	kit.sphere("beacon", pos + inward * 0.06 + Vector3(0, 0.04, 0), 0.09, BEACON, 10, Vector3(1.0, 0.8, 1.0))


# --- doorways --------------------------------------------------------------------------

static func _doorway(fx: ArtStationFX, kit: ArtMeshKit, node: Node3D, along_x: bool, fixed: float, g0: float, g1: float, outward: float, color: Color, own_name: String, dest_color: Color, dest_name: String, corridor_len: float) -> void:
	# No lintel: the third-person camera follows players through doorways at
	# ~3-4 m, so anything spanning the opening would fill the screen. Pylons,
	# light strips and floor signage carry the doorway instead.
	var across := fixed + outward * T * 0.5
	var depth := T + 0.3
	var top := H + 0.45
	for side: float in [-1.0, 1.0]:
		var edge := g0 if side < 0.0 else g1
		var post_c := edge + side * 0.17
		kit.bevel_box("metal", _v(along_x, post_c, top * 0.5, across), _s(along_x, 0.34, top, depth), 0.05, GUNMETAL)
		_wbox(kit, "door", along_x, edge + side * 0.035 - 0.02, edge + side * 0.035 + 0.02, 0.12, top - 0.12, across, depth + 0.02, color)
		_wbox(kit, "door", along_x, post_c - 0.12, post_c + 0.12, top, top + 0.04, across, depth - 0.06, color)
		# Hazard chevrons on the jamb base.
		_wbox(kit, "hazard", along_x, edge + side * 0.17 - 0.16, edge + side * 0.17 + 0.16, 0.0, 0.5, across, depth + 0.01, Color.WHITE)
	# Floor threshold: hazard plate plus lit edges.
	_wbox(kit, "hazard", along_x, g0 + 0.05, g1 - 0.05, 0.0, 0.012, across, T - 0.12, Color.WHITE)
	for off in [-T * 0.5 + 0.03, T * 0.5 - 0.03]:
		_wbox(kit, "door", along_x, g0 + 0.05, g1 - 0.05, 0.0, 0.016, across + off, 0.05, color)
	# Floor signs: the destination just inside the room, this room's name in
	# the corridor approach (when the corridor is long enough to hold it).
	var mid := (g0 + g1) * 0.5
	var out_dir := _v(along_x, 0.0, 0.0, outward).normalized()
	var inside := _v(along_x, mid, 0.022, fixed) - out_dir * 1.25
	_door_floor_label(fx, node, dest_name, inside, -out_dir, dest_color, g1 - g0)
	if corridor_len >= 5.0:
		var outside := _v(along_x, mid, 0.022, fixed) + out_dir * (T + 1.1)
		_door_floor_label(fx, node, own_name, outside, out_dir, color, g1 - g0)


static func _door_floor_label(fx: ArtStationFX, node: Node3D, text: String, pos: Vector3, facing: Vector3, color: Color, width: float) -> void:
	var chars := maxf(float(text.length()), 4.0)
	var pixel := minf(0.0068, (width - 0.5) / (chars * 52.0))
	var label := _label(fx, node, text.to_upper(), pos, facing, 72, pixel, Color(color.r, color.g, color.b, 0.95).lightened(0.15), true)
	label.outline_size = 0


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


static func _build_room(fx: ArtStationFX, mats: Dictionary, room_id: String) -> void:
	var spec: Dictionary = StationLayout.ROOMS[room_id]
	var r := StationLayout.room_rect(room_id)
	var color: Color = spec.color
	var node := Node3D.new()
	node.name = "Room_" + room_id
	fx.add_child(node)
	var body := _body(node, "Collision")
	var kit := _new_kit()
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	# Floor slab (under walls too) and exterior underside.
	kit.box_mm("floor", Vector3(x0 - T, -0.25, z0 - T), Vector3(x1 + T, 0.0, z1 + T), Color.WHITE)
	kit.bevel_box("metal", Vector3((x0 + x1) * 0.5, -0.7, (z0 + z1) * 0.5), Vector3(r.size.x + T * 2.0 + 0.2, 0.9, r.size.y + T * 2.0 + 0.2), 0.12, Color(0.22, 0.23, 0.25))
	_collider(body, Vector3((x0 + x1) * 0.5, -0.25, (z0 + z1) * 0.5), Vector3(r.size.x + T * 2.0, 0.5, r.size.y + T * 2.0))
	# Walls with doorway gaps.
	var gaps := _room_gaps(room_id)
	var accent := color
	var sides := [
		["n", true, z0, -1.0, x0 - T, x1 + T],
		["s", true, z1, 1.0, x0 - T, x1 + T],
		["w", false, x0, -1.0, z0, z1],
		["e", false, x1, 1.0, z0, z1],
	]
	var long_segments := []
	for side in sides:
		var key: String = side[0]
		var along_x: bool = side[1]
		var fixed: float = side[2]
		var outward: float = side[3]
		var cursor: float = side[4]
		var end: float = side[5]
		if room_id == "airlock" and key == "w":
			_airlock_outer_wall(fx, kit, body, node, fixed, cursor, end, color)
			continue
		var side_gaps: Array = gaps[key]
		side_gaps.sort_custom(func(a, b): return a[0] < b[0])
		for gap in side_gaps:
			if gap[0] - cursor > 0.05:
				_wall(kit, body, along_x, fixed, cursor, gap[0], outward, accent, accent, true)
				long_segments.append([along_x, fixed, cursor, gap[0], outward])
			var dest: String = gap[2]
			_doorway(fx, kit, node, along_x, fixed, gap[0], gap[1], outward, color, spec.name, StationLayout.ROOMS[dest].color, StationLayout.ROOMS[dest].name, gap[3])
			cursor = gap[1]
		if end - cursor > 0.05:
			_wall(kit, body, along_x, fixed, cursor, end, outward, accent, accent, true)
			long_segments.append([along_x, fixed, cursor, end, outward])
	# Room name on the upper band of every long wall, beacons on the two longest.
	long_segments.sort_custom(func(a, b): return (a[3] - a[2]) > (b[3] - b[2]))
	for i in range(long_segments.size()):
		var seg: Array = long_segments[i]
		var along_x: bool = seg[0]
		var fixed: float = seg[1]
		var a0: float = seg[2]
		var a1: float = seg[3]
		var outward: float = seg[4]
		var inward := _v(along_x, 0.0, 0.0, -outward).normalized()
		if a1 - a0 >= 5.5 and i < 2:
			_label(fx, node, String(spec.name).to_upper(), _v(along_x, (a0 + a1) * 0.5, (TRIM_HI + H) * 0.5, fixed) + inward * 0.035, inward, 64, 0.0055, color.lightened(0.2))
		if i < 2 and a1 - a0 >= 3.0:
			var beacon_at := (a0 + a1) * 0.5 + (a1 - a0) * 0.25
			_beacon(kit, _v(along_x, beacon_at, 2.58, fixed) + inward * 0.1, inward)
		if i < 3 and a1 - a0 >= 4.0:
			# Service pipes along the top of the wall (never over the floor).
			var p0 := a0 + 0.25
			var p1 := a1 - 0.25
			kit.cylinder("painted", _v(along_x, p0, 3.0, fixed) + inward * 0.09, _v(along_x, p1, 3.0, fixed) + inward * 0.09, 0.05, Color(0.42, 0.44, 0.47), 8)
			kit.cylinder("painted", _v(along_x, p0, 3.11, fixed) + inward * 0.06, _v(along_x, p1, 3.11, fixed) + inward * 0.06, 0.032, color.darkened(0.3), 8)
			var br := p0 + 0.6
			while br < p1:
				kit.box("metal", _v(along_x, br, 3.04, fixed) + inward * 0.07, _s(along_x, 0.06, 0.2, 0.16), GUNMETAL)
				br += 2.0
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
		kit.torus("trim", centre3 + Vector3(0, 0.004, 0), 2.28, 2.42, color, Basis.from_scale(Vector3(1, 0.09, 1)), 48, 6)
	var floor_label := _label(fx, node, String(spec.name).to_upper(), Vector3(spec.center.x + label_off.x, 0.02, spec.center.y + label_off.y), LABEL_FACING.get(room_id, Vector3(0, 0, 1)), 120 if r.size.x >= 8.0 else 80, 0.0085, Color(color.r, color.g, color.b, 0.9), true)
	floor_label.outline_size = 0
	# Room-specific dressing.
	match room_id:
		"command":
			_dress_command(fx, kit, body, node, color)
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
		"airlock":
			_dress_airlock(kit, body, color)
	node.add_child(kit.to_instance(mats, "Mesh"))
	# One omni per room (no shadows), a reflection probe and a few grime decals.
	var light := OmniLight3D.new()
	light.name = "RoomLight"
	light.position = Vector3(spec.center.x, 2.9, spec.center.y)
	if room_id == "reactor":
		light.position = Vector3(62, 3.4, 19.3)
	light.omni_range = maxf(r.size.x, r.size.y) * 0.85
	light.omni_attenuation = 0.9
	light.shadow_enabled = false
	light.light_specular = 0.6
	node.add_child(light)
	fx.room_lights.append(light)
	fx.room_light_colors.append(color.lerp(Color.WHITE, 0.62))
	var probe := ReflectionProbe.new()
	probe.name = "Probe"
	probe.position = Vector3(spec.center.x, 1.6, spec.center.y)
	probe.size = Vector3(r.size.x + 1.0, 7.0, r.size.y + 1.0)
	probe.origin_offset = Vector3.ZERO
	probe.box_projection = true
	probe.intensity = 0.7
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	node.add_child(probe)
	fx.probes.append(probe)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room_id)
	for corner in [Vector2(x0 + 1.0, z0 + 1.0), Vector2(x1 - 1.0, z1 - 1.0), Vector2(x0 + 1.0, z1 - 1.0)]:
		var decal := Decal.new()
		decal.texture_albedo = ArtMaterials.texture("grime_decal")
		decal.size = Vector3(3.2, 1.0, 3.2)
		decal.position = Vector3(corner.x, 0.2, corner.y)
		decal.rotation.y = rng.randf() * TAU
		decal.albedo_mix = 0.85
		decal.upper_fade = 0.2
		decal.lower_fade = 0.2
		decal.cull_mask = 1
		node.add_child(decal)


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
	# Centre walkway band and guide-light dashes along both edges.
	_wbox(kit, "painted", along_x, f0, f1, 0.0, 0.006, mid_across, 1.0, Color(0.2, 0.21, 0.23))
	var d := f0 + 0.3
	while d < f1 - 0.5:
		_wbox(kit, "guide", along_x, d, d + 0.45, 0.0, 0.014, lo + 0.28, 0.06, GUIDE)
		_wbox(kit, "guide", along_x, d, d + 0.45, 0.0, 0.014, hi - 0.28, 0.06, GUIDE)
		d += 1.2
	# Chevrons pointing along the corridor every 6 m on the walkway.
	var ch := f0 + 2.0
	while ch < f1 - 1.5:
		for sgn in [-1.0, 1.0]:
			var basis := Basis(Vector3.UP, (0.0 if along_x else PI / 2.0) + sgn * 0.6)
			kit.box("painted", _v(along_x, ch, 0.008, mid_across + sgn * 0.17), Vector3(0.5, 0.004, 0.08), Color(0.55, 0.56, 0.58), basis)
		ch += 6.0
	# Side walls (shortened by T to butt against the room walls' outer faces).
	_wall(kit, body, along_x, lo, a0 + T, a1 - T, -1.0, col_lo, col_hi, true)
	_wall(kit, body, along_x, hi, a0 + T, a1 - T, 1.0, col_lo, col_hi, true)
	var length := a1 - a0
	if length >= 12.0:
		var count := int(length / 12.0)
		for i in range(count):
			var at := a0 + length * (float(i) + 0.5) / float(count)
			_beacon(kit, _v(along_x, at, 2.58, lo + 0.1), _v(along_x, 0, 0, 1).normalized())
		# Cable trays overhead along one wall top.
		kit.cylinder("painted", _v(along_x, f0, H - 0.22, hi - 0.12), _v(along_x, f1, H - 0.22, hi - 0.12), 0.05, Color(0.1, 0.1, 0.11), 6)
		kit.cylinder("painted", _v(along_x, f0, H - 0.34, hi - 0.1), _v(along_x, f1, H - 0.34, hi - 0.1), 0.035, Color(0.5, 0.15, 0.1), 6)
	node.add_child(kit.to_instance(mats, "Mesh"))
	if length >= 20.0:
		var light := OmniLight3D.new()
		light.name = "CorridorLight"
		light.position = _v(along_x, (a0 + a1) * 0.5, 2.8, mid_across)
		light.omni_range = minf(length * 0.5, 14.0)
		light.omni_attenuation = 1.0
		light.light_specular = 0.4
		node.add_child(light)
		fx.room_lights.append(light)
		fx.room_light_colors.append(col_lo.lerp(col_hi, 0.5).lerp(Color.WHITE, 0.75))


# --- decor helpers ------------------------------------------------------------------------

## Console desk: front faces +Z rotated by `yaw`. `pos` is floor centre.
static func _console(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, width: float, screen_color: Color, accent: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.45, 0), Vector3(width, 0.9, 0.7), 0.05, DARK)
	kit.box("trim", pos + b * Vector3(0, 0.12, 0.351), Vector3(width - 0.2, 0.03, 0.01), accent)
	var tilt := b * Basis(Vector3.RIGHT, 0.45)
	kit.bevel_box("metal", pos + b * Vector3(0, 0.98, 0.05), Vector3(width, 0.08, 0.6), 0.02, GUNMETAL, tilt)
	kit.box("screen", pos + b * Vector3(0, 1.03, 0.07), Vector3(width - 0.3, 0.02, 0.42), screen_color, tilt)
	# Upright monitors on the back edge.
	var monitors := maxi(1, int(width / 1.2))
	for i in range(monitors):
		var mx := -width * 0.5 + width * (float(i) + 0.5) / float(monitors)
		kit.bevel_box("painted", pos + b * Vector3(mx, 1.45, -0.26), Vector3(1.0, 0.62, 0.08), 0.02, DARK)
		kit.box("screen", pos + b * Vector3(mx, 1.45, -0.215), Vector3(0.9, 0.52, 0.01), screen_color.lerp(Color(1, 0.75, 0.3), 0.3 * float(i % 2)))
		kit.box("metal", pos + b * Vector3(mx, 1.05, -0.28), Vector3(0.08, 0.3, 0.06), GUNMETAL)
	_collider(body, pos + b * Vector3(0, 0.6, -0.02), Vector3(width, 1.2, 0.76), b)
	_ao_rect(kit, pos, Vector2(width * 0.5, 0.36), yaw)


static func _crate(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, size: Vector3, color: Color, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var c := pos + Vector3(0, size.y * 0.5, 0)
	kit.bevel_box("painted", c, size, 0.05, color, b)
	# Metal corner bands and a hazard label strip.
	for sy in [-1.0, 1.0]:
		kit.bevel_box("metal", c + b * Vector3(0, sy * (size.y * 0.5 - 0.06), 0), Vector3(size.x + 0.03, 0.08, size.z + 0.03), 0.02, GUNMETAL, b)
	kit.box("hazard", c + b * Vector3(0, size.y * 0.15, size.z * 0.5 + 0.012), Vector3(size.x * 0.5, 0.12, 0.01), Color.WHITE, b)
	kit.box("hazard", c + b * Vector3(0, size.y * 0.15, -size.z * 0.5 - 0.012), Vector3(size.x * 0.5, 0.12, 0.01), Color.WHITE, b)
	_collider(body, c, size, b)
	if pos.y < 0.05:
		_ao_rect(kit, pos, Vector2(size.x, size.z) * 0.5, yaw, 0.35)


static func _tank(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, radius: float, height: float, color: Color) -> void:
	kit.cylinder("painted", pos + Vector3(0, 0.15, 0), pos + Vector3(0, height - radius * 0.4, 0), radius, color, 20)
	kit.sphere("painted", pos + Vector3(0, height - radius * 0.4, 0), radius, color, 20, Vector3(1, 0.4, 1))
	kit.cylinder("metal", pos, pos + Vector3(0, 0.18, 0), radius + 0.06, GUNMETAL, 20)
	for band_y in [height * 0.3, height * 0.7]:
		kit.cylinder("metal", pos + Vector3(0, band_y - 0.05, 0), pos + Vector3(0, band_y + 0.05, 0), radius + 0.025, GUNMETAL, 20)
	kit.cylinder("guide", pos + Vector3(0, height * 0.5 - 0.02, 0), pos + Vector3(0, height * 0.5 + 0.02, 0), radius + 0.01, Color(0.3, 1.0, 0.6), 20)
	_cyl_collider(body, pos + Vector3(0, height * 0.5, 0), radius + 0.06, height)
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


# --- per-room dressing -------------------------------------------------------------------

static func _dress_command(fx: ArtStationFX, kit: ArtMeshKit, body: StaticBody3D, node: Node3D, color: Color) -> void:
	# Vault dais around the vault socket (0, -23.5).
	var vault := Vector3(0, 0, -23.5)
	kit.cylinder("painted", vault, vault + Vector3(0, 0.03, 0), 2.4, Color(0.13, 0.15, 0.2), 40)
	kit.torus("trim", vault + Vector3(0, 0.03, 0), 2.32, 2.46, color, Basis.from_scale(Vector3(1, 0.12, 1)), 48, 6)
	kit.torus("hazard", vault + Vector3(0, 0.02, 0), 1.75, 2.05, Color.WHITE, Basis.from_scale(Vector3(1, 0.05, 1)), 40, 4)
	# Backdrop pylons framing the vault against the north window wall.
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * 2.4, 0, -25.35)
		kit.bevel_box("painted", p + Vector3(0, 1.6, 0), Vector3(0.7, 3.2, 0.7), 0.08, DARK)
		kit.box("trim", p + Vector3(0, 1.6, 0.355), Vector3(0.08, 2.6, 0.01), color)
		kit.box("trim", p + Vector3(-sx * 0.355, 1.6, 0), Vector3(0.01, 2.6, 0.08), color)
		_collider(body, p + Vector3(0, 1.6, 0), Vector3(0.7, 3.2, 0.7))
	kit.bevel_box("metal", Vector3(0, 3.05, -25.35), Vector3(5.5, 0.3, 0.5), 0.05, GUNMETAL)
	_label(fx, node, "STATION CORE VAULT", Vector3(0, 3.05, -25.09), Vector3(0, 0, 1), 48, 0.004, color.lightened(0.3))
	# Consoles along the west wall and north-east corner.
	_console(kit, body, Vector3(-6.25, 0, -22.4), PI / 2.0, 2.4, SCREEN_BLUE, color)
	_console(kit, body, Vector3(-6.25, 0, -17.4), PI / 2.0, 2.4, SCREEN_BLUE, color)
	_console(kit, body, Vector3(5.0, 0, -25.25), 0.0, 2.6, SCREEN_BLUE, color)
	# Holo table.
	var holo := Vector3(3.6, 0, -16.6)
	kit.cylinder("painted", holo, holo + Vector3(0, 0.85, 0), 0.45, DARK, 16, 0.55)
	kit.cylinder("metal", holo + Vector3(0, 0.85, 0), holo + Vector3(0, 0.95, 0), 0.95, GUNMETAL, 24)
	kit.torus("trim", holo + Vector3(0, 0.96, 0), 0.82, 0.9, color, Basis.IDENTITY, 32, 6)
	kit.sphere("screen", holo + Vector3(0, 1.45, 0), 0.32, SCREEN_BLUE, 14)
	kit.torus("trim", holo + Vector3(0, 1.45, 0), 0.5, 0.53, color, Basis(Vector3.RIGHT, 1.1), 32, 4)
	_cyl_collider(body, holo + Vector3(0, 0.5, 0), 0.95, 1.0)


static func _dress_security(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Monitor wall on the north wall, east of the armory socket (37, -24.5).
	for i in range(3):
		var mx := 40.1 + float(i) * 1.95
		kit.bevel_box("painted", Vector3(mx, 1.95, -25.93), Vector3(1.85, 1.05, 0.12), 0.03, DARK)
		kit.box("screen", Vector3(mx, 1.95, -25.86), Vector3(1.7, 0.9, 0.01), SCREEN_BLUE.lerp(color, 0.25 * float(i % 2)))
	_console(kit, body, Vector3(42.0, 0, -24.95), 0.0, 3.4, SCREEN_BLUE, color)
	# Armory alcove frame behind the socket.
	for sx in [-1.0, 1.0]:
		kit.bevel_box("metal", Vector3(37.0 + sx * 1.15, 1.4, -25.7), Vector3(0.2, 2.8, 0.5), 0.04, GUNMETAL)
		kit.box("trim", Vector3(37.0 + sx * 1.05, 1.4, -25.5), Vector3(0.02, 2.4, 0.04), color)
	kit.bevel_box("metal", Vector3(37.0, 2.7, -25.7), Vector3(2.5, 0.2, 0.5), 0.04, GUNMETAL)
	kit.box_mm("hazard", Vector3(35.6, 0.0, -25.95), Vector3(38.4, 0.012, -23.4), Color.WHITE)
	# Lockers along the east wall.
	for i in range(5):
		var lz := -19.3 + float(i) * 0.86
		var p := Vector3(46.67, 0, lz)
		kit.bevel_box("painted", p + Vector3(0, 1.05, 0), Vector3(0.62, 2.1, 0.82), 0.03, Color(0.42, 0.18, 0.2).lerp(GUNMETAL, 0.4 * float(i % 2)))
		for v in range(4):
			kit.box("painted", p + Vector3(-0.315, 1.65 + float(v) * 0.07, 0), Vector3(0.01, 0.025, 0.4), DARK)
		kit.box("trim", p + Vector3(-0.315, 1.0, 0.3), Vector3(0.01, 0.12, 0.04), color)
	_collider(body, Vector3(46.67, 1.05, -17.58), Vector3(0.62, 2.1, 4.3))
	_ao_rect(kit, Vector3(46.67, 0, -17.58), Vector2(0.31, 2.15))
	# Bench by the south wall, west of the doorway.
	kit.bevel_box("metal", Vector3(35.5, 0.45, -14.55), Vector3(2.6, 0.08, 0.5), 0.02, GUNMETAL)
	kit.bevel_box("painted", Vector3(35.5, 0.22, -14.55), Vector3(2.4, 0.44, 0.3), 0.02, DARK)
	_collider(body, Vector3(35.5, 0.25, -14.55), Vector3(2.6, 0.5, 0.5))
	_ao_rect(kit, Vector3(35.5, 0, -14.55), Vector2(1.3, 0.25), 0.0, 0.3)


static func _dress_commons(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Two mess tables (long axis along X) in the east half, clear of the spawn ring.
	for sz in [-1.0, 1.0]:
		var t := Vector3(4.8, 0, sz * 5.0)
		kit.bevel_box("metal", t + Vector3(0, 0.76, 0), Vector3(2.3, 0.06, 1.0), 0.02, Color(0.55, 0.56, 0.58))
		kit.bevel_box("painted", t + Vector3(0, 0.38, 0), Vector3(1.6, 0.72, 0.3), 0.03, DARK)
		kit.box("trim", t + Vector3(0, 0.72, 0), Vector3(2.32, 0.015, 1.02), color)
		_collider(body, t + Vector3(0, 0.4, 0), Vector3(2.3, 0.8, 1.0))
		for bz in [-1.0, 1.0]:
			var b := t + Vector3(0, 0, bz * 1.12)
			kit.bevel_box("soft", b + Vector3(0, 0.46, 0), Vector3(2.2, 0.1, 0.42), 0.04, color.darkened(0.35))
			kit.bevel_box("painted", b + Vector3(0, 0.21, 0), Vector3(1.8, 0.42, 0.2), 0.02, DARK)
			_collider(body, b + Vector3(0, 0.25, 0), Vector3(2.2, 0.5, 0.42))
		_ao_rect(kit, t, Vector2(1.15, 1.3), 0.0, 0.4)
	# Planters under the west windows (clear of the airlock doorway and console).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for spec in [[Vector3(-7.35, 0, -5.0), 2.6], [Vector3(-7.35, 0, 5.6), 2.0]]:
		var pl: Vector3 = spec[0]
		var length: float = spec[1]
		kit.bevel_box("painted", pl + Vector3(0, 0.3, 0), Vector3(0.7, 0.6, length), 0.04, DARK)
		kit.box("soft", pl + Vector3(0, 0.6, 0), Vector3(0.6, 0.02, length - 0.1), Color(0.18, 0.12, 0.08))
		var count := int(length / 0.36)
		for i in range(count):
			var z := pl.z - length * 0.5 + 0.2 + float(i) * (length - 0.4) / float(maxi(count - 1, 1))
			kit.sphere("soft", Vector3(pl.x + rng.randf_range(-0.15, 0.15), 0.75 + rng.randf() * 0.2, z), rng.randf_range(0.18, 0.28), Color(0.16, 0.42, 0.18).lerp(Color(0.35, 0.6, 0.2), rng.randf()), 8, Vector3(1, 1.4, 1))
		kit.box("trim", pl + Vector3(0.25, 1.95, 0), Vector3(0.06, 0.04, length - 0.2), Color(0.75, 0.55, 1.0))
		_collider(body, pl + Vector3(0, 0.5, 0), Vector3(0.7, 1.0, length))
		_ao_rect(kit, pl, Vector2(0.35, length * 0.5), 0.0, 0.35)
	# Hazard apron in front of the airlock doorway and the cycle console.
	kit.box_mm("hazard", Vector3(-7.95, 0.0, -1.5), Vector3(-7.2, 0.012, 1.5), Color.WHITE)
	# Vending machines in the east corners.
	for sz in [-1.0, 1.0]:
		var v := Vector3(7.5, 0, sz * 5.4)
		kit.bevel_box("painted", v + Vector3(0, 1.0, 0), Vector3(0.9, 2.0, 1.1), 0.05, color.darkened(0.45))
		kit.box("screen", v + Vector3(-0.455, 1.25, 0.12), Vector3(0.01, 1.1, 0.65), Color(1.0, 0.75, 0.35))
		kit.box("trim", v + Vector3(-0.455, 0.45, 0.12), Vector3(0.01, 0.12, 0.65), color)
		_collider(body, v + Vector3(0, 1.0, 0), Vector3(0.9, 2.0, 1.1))
		_ao_rect(kit, v, Vector2(0.45, 0.55), 0.0, 0.35)


static func _dress_docking(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var hull: Dictionary = StationLayout.SHUTTLE_HULL
	var hc := Vector3(hull.center.x, 0, hull.center.y)
	var hs: Vector2 = hull.size
	var white := Color(0.86, 0.87, 0.86)
	var fus_len := hs.x - 1.4
	var half_w := hs.y * 0.5 - 0.4
	var base := hc + Vector3(-0.2, 0, 0)
	# Hard-surface dropship: chamfered hull blocks, frustum nose, twin nacelles.
	kit.bevel_box("painted", base + Vector3(0.2, 1.5, 0), Vector3(fus_len, 1.7, half_w * 2.0), 0.32, white)
	kit.bevel_box("painted", base + Vector3(0.6, 2.5, 0), Vector3(fus_len * 0.62, 0.55, half_w * 1.4), 0.22, white)
	kit.bevel_box("metal", base + Vector3(0.2, 0.62, 0), Vector3(fus_len - 0.6, 0.36, half_w * 1.7), 0.12, Color(0.2, 0.21, 0.23))
	var nose := CylinderMesh.new()
	nose.radial_segments = 4
	nose.rings = 1
	nose.bottom_radius = 1.25
	nose.top_radius = 0.42
	nose.height = 1.5
	var nose_x := base.x + 0.2 - fus_len * 0.5 - 0.72
	kit.mesh("painted", nose, Transform3D(Basis(Vector3.BACK, PI / 2.0) * Basis(Vector3.UP, PI / 4.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.82)), Vector3(nose_x, 1.5, base.z)), white)
	# Cockpit glazing on the nose's upper slope.
	kit.box("screen", Vector3(nose_x + 0.05, 2.0, base.z), Vector3(1.0, 0.04, 1.1), Color(0.12, 0.3, 0.45), Basis(Vector3.BACK, 0.42))
	kit.box("trim", Vector3(nose_x - 0.62, 1.5, base.z), Vector3(0.06, 0.12, 0.5), color)
	# Livery stripes, panel seams, cabin windows (both sides).
	for sz in [-1.0, 1.0]:
		var side_z: float = base.z + sz * (half_w + 0.005)
		kit.box("trim", Vector3(base.x + 0.2, 1.62, side_z), Vector3(fus_len - 1.0, 0.09, 0.02), color)
		kit.box("painted", Vector3(base.x + 0.2, 1.42, side_z), Vector3(fus_len - 0.8, 0.22, 0.02), color.darkened(0.45))
		var seam := base.x + 0.2 - fus_len * 0.5 + 0.9
		while seam < base.x + 0.2 + fus_len * 0.5 - 0.6:
			kit.box("painted", Vector3(seam, 1.5, side_z), Vector3(0.025, 1.3, 0.02), Color(0.35, 0.36, 0.38))
			seam += 1.45
		for i in range(4):
			kit.bevel_box("screen", Vector3(base.x - 1.5 + float(i) * 0.85, 2.0, side_z), Vector3(0.48, 0.24, 0.06), 0.03, Color(1.0, 0.82, 0.55))
	# Twin engine nacelles with glowing nozzles.
	var tail_x := base.x + 0.2 + fus_len * 0.5
	for sz in [-0.85, 0.85]:
		var e := Vector3(tail_x, 1.65, base.z + sz)
		kit.cylinder("metal", e - Vector3(1.4, 0, 0), e + Vector3(0.55, 0, 0), 0.5, GUNMETAL, 16)
		kit.cylinder("metal", e + Vector3(0.55, 0, 0), e + Vector3(0.85, 0, 0), 0.5, GUNMETAL, 16, 0.42)
		kit.cylinder("trim", e + Vector3(0.84, 0, 0), e + Vector3(0.87, 0, 0), 0.36, Color(0.45, 0.85, 1.0), 16)
		kit.torus("painted", e + Vector3(-0.2, 0, 0), 0.5, 0.56, color.darkened(0.2), Basis(Vector3.BACK, PI / 2.0), 20, 6)
	# Tail fin and stub wings.
	kit.bevel_box("painted", Vector3(tail_x - 0.9, 2.62, base.z), Vector3(1.7, 0.9, 0.16), 0.05, white, Basis(Vector3.BACK, -0.45))
	kit.box("trim", Vector3(tail_x - 0.8, 2.75, base.z), Vector3(1.2, 0.07, 0.18), color, Basis(Vector3.BACK, -0.45))
	for sz in [-1.0, 1.0]:
		kit.bevel_box("painted", Vector3(base.x + 1.0, 1.15, base.z + sz * (half_w + 0.12)), Vector3(2.6, 0.14, 0.32), 0.05, white)
		kit.sphere("nav", Vector3(base.x + 1.0, 1.15, base.z + sz * (half_w + 0.3)), 0.06, Color(1, 0.15, 0.1) if sz < 0.0 else Color(0.2, 1, 0.3), 6)
	# Landing struts.
	for sx in [-2.6, 0.4, 2.8]:
		for sz in [-0.9, 0.9]:
			var strut := base + Vector3(sx, 0, sz)
			kit.cylinder("metal", strut + Vector3(0, 0.05, 0), strut + Vector3(0, 0.62, 0), 0.07, GUNMETAL, 8)
			kit.cylinder("metal", strut, strut + Vector3(0, 0.06, 0), 0.22, GUNMETAL, 12)
	_ao_rect(kit, hc, Vector2(hs.x * 0.5 - 0.3, hs.y * 0.5 - 0.3), 0.0, 0.6, Color(0.3, 0.3, 0.33))
	_collider(body, hc + Vector3(0, 1.45, 0), Vector3(hs.x, 2.9, hs.y))
	# Loading ramp from the side hatch down to the floor (west of the socket).
	var hatch_x := hc.x - 2.2
	var top := Vector3(hatch_x, 0.55, hc.z + hs.y * 0.5 - 0.4)
	var foot := Vector3(hatch_x, 0.0, hc.z + hs.y * 0.5 + 1.6)
	var ramp_len := top.distance_to(foot)
	var ang := atan2(top.y - foot.y, foot.z - top.z)
	var rb := Basis(Vector3.RIGHT, ang)
	var rc := (top + foot) * 0.5 + rb * Vector3(0, -0.04, 0)
	kit.bevel_box("metal", rc, Vector3(1.4, 0.08, ramp_len), 0.02, GUNMETAL, rb)
	kit.box("hazard", rc + rb * Vector3(-0.62, 0.045, 0), Vector3(0.12, 0.01, ramp_len), Color.WHITE, rb)
	kit.box("hazard", rc + rb * Vector3(0.62, 0.045, 0), Vector3(0.12, 0.01, ramp_len), Color.WHITE, rb)
	_collider(body, rc, Vector3(1.4, 0.08, ramp_len), rb)
	kit.bevel_box("painted", Vector3(hatch_x, 1.25, hc.z + hs.y * 0.5 - 0.4), Vector3(1.3, 1.4, 0.06), 0.03, DARK)
	for hx in [-0.6, 0.6]:
		kit.box("door", Vector3(hatch_x + hx, 1.25, hc.z + hs.y * 0.5 - 0.365), Vector3(0.04, 1.3, 0.01), color)
	kit.box("door", Vector3(hatch_x, 1.92, hc.z + hs.y * 0.5 - 0.365), Vector3(1.24, 0.04, 0.01), color)
	kit.box("screen", Vector3(hatch_x, 1.6, hc.z + hs.y * 0.5 - 0.36), Vector3(0.3, 0.2, 0.01), Color(1.0, 0.8, 0.5))
	# Landing pad hazard border on the south side and around the ends.
	kit.box_mm("hazard", Vector3(hc.x - hs.x * 0.5 - 0.3, 0.0, hc.z + hs.y * 0.5 + 0.15), Vector3(hc.x + hs.x * 0.5 + 0.3, 0.01, hc.z + hs.y * 0.5 + 0.35), Color.WHITE)
	# Fuel tanks against the south wall.
	_tank(kit, body, Vector3(14.6, 0, 5.0), 0.55, 2.3, Color(0.75, 0.42, 0.15))
	_tank(kit, body, Vector3(25.4, 0, 5.0), 0.55, 2.3, Color(0.75, 0.42, 0.15))
	_pipe_run(kit, Vector3(14.6, 2.0, 5.65), Vector3(25.4, 2.0, 5.65), 0.08, Color(0.75, 0.42, 0.15))
	_crate(kit, body, Vector3(23.2, 0, 5.1), Vector3(1.2, 1.0, 1.2), Color(0.3, 0.42, 0.4))


static func _dress_cargo(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var pod: Dictionary = StationLayout.POD_HULL
	var pc := Vector3(pod.center.x, 0, pod.center.y)
	var ps: Vector2 = pod.size
	# Launch cradle: hazard plate, corner posts and top frame.
	kit.box_mm("hazard", pc - Vector3(ps.x * 0.5 + 0.15, 0, ps.y * 0.5 + 0.15), pc + Vector3(ps.x * 0.5 + 0.15, 0.012, ps.y * 0.5 + 0.15), Color.WHITE)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.bevel_box("metal", pc + Vector3(sx * (ps.x * 0.5 - 0.1), 1.45, sz * (ps.y * 0.5 - 0.1)), Vector3(0.18, 2.9, 0.18), 0.03, GUNMETAL)
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
	_collider(body, pc + Vector3(0, 1.5, 0), Vector3(ps.x, 3.0, ps.y))
	# Crate stacks in three corners, clear of doorways, the pod and paths.
	_crate(kit, body, Vector3(34.3, 0, -5.8), Vector3(1.4, 1.2, 1.4), Color(0.62, 0.36, 0.16))
	_crate(kit, body, Vector3(35.9, 0, -5.9), Vector3(1.2, 1.0, 1.2), Color(0.3, 0.4, 0.3), 0.15)
	_crate(kit, body, Vector3(34.3, 1.2, -5.8), Vector3(1.0, 0.8, 1.0), Color(0.5, 0.52, 0.55), 0.3)
	_crate(kit, body, Vector3(34.4, 0, 5.7), Vector3(1.6, 1.3, 1.4), Color(0.3, 0.4, 0.3))
	_crate(kit, body, Vector3(36.4, 0, 5.8), Vector3(1.2, 0.9, 1.2), Color(0.62, 0.36, 0.16), -0.2)
	_crate(kit, body, Vector3(44.0, 0, -5.8), Vector3(1.4, 1.1, 1.4), Color(0.5, 0.52, 0.55))
	_crate(kit, body, Vector3(45.8, 0, -5.6), Vector3(1.2, 1.4, 1.2), Color(0.62, 0.36, 0.16), 0.1)
	_crate(kit, body, Vector3(44.0, 1.1, -5.8), Vector3(1.0, 0.8, 1.0), Color(0.3, 0.4, 0.3), -0.25)
	# Forklift lanes.
	var d := 34.0
	while d < 46.0:
		kit.box_mm("painted", Vector3(d, 0.0, -1.95), Vector3(d + 0.7, 0.008, -1.85), Color(0.9, 0.7, 0.15))
		kit.box_mm("painted", Vector3(d, 0.0, 1.85), Vector3(d + 0.7, 0.008, 1.95), Color(0.9, 0.7, 0.15))
		d += 1.1


static func _dress_engineering(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Generator unit against the north wall.
	var g := Vector3(59.2, 0, -4.9)
	kit.bevel_box("painted", g + Vector3(0, 0.95, 0), Vector3(2.6, 1.9, 1.6), 0.08, Color(0.32, 0.3, 0.18))
	kit.bevel_box("metal", g + Vector3(0, 1.95, 0), Vector3(2.2, 0.15, 1.3), 0.04, GUNMETAL)
	kit.box("hazard", g + Vector3(0, 0.15, 0.805), Vector3(2.5, 0.3, 0.01), Color.WHITE)
	kit.box("screen", g + Vector3(-0.6, 1.25, 0.805), Vector3(0.8, 0.5, 0.01), Color(0.4, 1.0, 0.5))
	kit.cylinder("trim", g + Vector3(0.6, 1.1, 0.78), g + Vector3(0.6, 1.1, 0.83), 0.3, color, 20)
	for v in range(5):
		kit.box("painted", g + Vector3(0.6, 0.45 + float(v) * 0.08, 0.805), Vector3(0.8, 0.03, 0.01), DARK)
	_collider(body, g + Vector3(0, 1.0, 0), Vector3(2.6, 2.0, 1.6))
	# Pipe runs along the north wall with flanges and valve wheels.
	_pipe_run(kit, Vector3(56.3, 0.75, -5.75), Vector3(67.7, 0.75, -5.75), 0.12, Color(0.7, 0.55, 0.15))
	_pipe_run(kit, Vector3(56.3, 2.3, -5.72), Vector3(67.7, 2.3, -5.72), 0.15, Color(0.35, 0.42, 0.5))
	_pipe_run(kit, Vector3(61.0, 1.3, -5.78), Vector3(67.7, 1.3, -5.78), 0.09, Color(0.6, 0.2, 0.15))
	for px in [62.5, 65.5]:
		_pipe_run(kit, Vector3(px, 0.0, -5.6), Vector3(px, 2.6, -5.6), 0.1, Color(0.35, 0.42, 0.5))
		kit.torus("painted", Vector3(px, 1.6, -5.42), 0.12, 0.17, Color(0.75, 0.15, 0.1), Basis(Vector3.RIGHT, PI / 2.0), 16, 6)
	_collider(body, Vector3(62.0, 1.4, -5.6), Vector3(11.4, 2.8, 0.8))
	# Coolant tanks along the east wall, cables sagging above.
	_tank(kit, body, Vector3(66.9, 0, 2.0), 0.6, 2.6, Color(0.3, 0.45, 0.55))
	_tank(kit, body, Vector3(66.9, 0, 4.4), 0.6, 2.6, Color(0.3, 0.45, 0.55))
	_cable(kit, Vector3(67.75, 2.7, -5.0), Vector3(67.75, 2.7, 0.0), 0.45, 0.035, Color(0.08, 0.08, 0.09))
	_cable(kit, Vector3(67.7, 2.6, -4.2), Vector3(67.7, 2.6, 0.8), 0.6, 0.03, Color(0.5, 0.12, 0.08))
	_cable(kit, Vector3(67.75, 2.7, 0.0), Vector3(67.75, 2.7, 5.5), 0.4, 0.035, Color(0.08, 0.08, 0.09))


static func _dress_reactor(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	var c := Vector3(62, 0, 19.3)
	var core_col := color.lerp(Color(0.85, 0.75, 1.0), 0.45)
	kit.cylinder("metal", c, c + Vector3(0, 0.35, 0), 1.75, GUNMETAL, 28, 1.6)
	kit.torus("hazard", c + Vector3(0, 0.01, 0), 1.9, 2.45, Color.WHITE, Basis.from_scale(Vector3(1, 0.05, 1)), 40, 4)
	kit.cylinder("reactor", c + Vector3(0, 0.35, 0), c + Vector3(0, 3.9, 0), 0.55, core_col, 20)
	kit.cylinder("glass", c + Vector3(0, 0.35, 0), c + Vector3(0, 3.9, 0), 0.85, Color.WHITE, 24)
	for i in range(4):
		var y := 0.9 + float(i) * 0.9
		kit.torus("metal", c + Vector3(0, y, 0), 0.82, 1.02, GUNMETAL, Basis.IDENTITY, 28, 8)
		kit.torus("trim", c + Vector3(0, y + 0.11, 0), 0.9, 0.95, color, Basis.IDENTITY, 28, 4)
	for i in range(6):
		var ang := TAU * float(i) / 6.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * 1.05
		kit.bevel_box("metal", p + Vector3(0, 2.15, 0), Vector3(0.14, 3.6, 0.14), 0.03, GUNMETAL, Basis(Vector3.UP, -ang))
	kit.cylinder("metal", c + Vector3(0, 3.9, 0), c + Vector3(0, 4.35, 0), 1.25, GUNMETAL, 28, 1.0)
	kit.cylinder("reactor", c + Vector3(0, 4.35, 0), c + Vector3(0, 4.75, 0), 0.4, core_col, 16, 0.15)
	kit.torus("trim", c + Vector3(0, 4.0, 0), 1.2, 1.3, color, Basis.IDENTITY, 28, 4)
	_cyl_collider(body, c + Vector3(0, 2.3, 0), 1.6, 4.6)
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
		var b := c - dir * 1.8
		var mid := (a + b) * 0.5
		var yaw := atan2(dir.x, dir.z)
		kit.box("painted", mid + Vector3(0, 0.004, 0), Vector3(0.36, 0.008, a.distance_to(b)), DARK, Basis(Vector3.UP, yaw))
		kit.box("reactor", mid + Vector3(0, 0.012, 0), Vector3(0.1, 0.012, a.distance_to(b)), core_col, Basis(Vector3.UP, yaw))
	# Monitoring console on the east wall.
	var console_body := body
	_console(kit, console_body, Vector3(68.25, 0, 16.6), -PI / 2.0, 2.4, Color(0.75, 0.55, 1.0), color)


static func _dress_medical(kit: ArtMeshKit, body: StaticBody3D, color: Color) -> void:
	# Beds along the west wall (head at the wall); the medbay socket sits at (3.5, 23.5).
	_bed(kit, body, Vector3(-6.0, 0, 16.3), PI / 2.0, color)
	_bed(kit, body, Vector3(-6.0, 0, 19.2), PI / 2.0, color)
	# Medical cabinet with a glowing cross on the north wall.
	var cab := Vector3(-4.6, 0, 14.33)
	kit.bevel_box("painted", cab + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.62), 0.05, Color(0.88, 0.9, 0.9))
	kit.box("trim", cab + Vector3(0, 1.45, 0.315), Vector3(0.42, 0.12, 0.01), color)
	kit.box("trim", cab + Vector3(0, 1.45, 0.315), Vector3(0.12, 0.42, 0.01), color)
	kit.box("glass", cab + Vector3(0, 0.75, 0.315), Vector3(1.5, 0.8, 0.01), Color.WHITE)
	_collider(body, cab + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 0.62))
	_ao_rect(kit, cab, Vector2(0.9, 0.31), 0.0, 0.35)
	# Equipment along the south wall either side of the medbay: IV stand,
	# scanner tower and supply carts.
	kit.bevel_box("painted", Vector3(6.2, 1.1, 25.55), Vector3(1.0, 2.2, 0.7), 0.05, Color(0.85, 0.87, 0.88))
	kit.box("screen", Vector3(6.2, 1.45, 25.19), Vector3(0.75, 0.6, 0.01), Color(0.4, 1.0, 0.55))
	kit.box("trim", Vector3(6.2, 0.6, 25.19), Vector3(0.75, 0.05, 0.01), color)
	_collider(body, Vector3(6.2, 1.1, 25.55), Vector3(1.0, 2.2, 0.7))
	_ao_rect(kit, Vector3(6.2, 0, 25.55), Vector2(0.5, 0.35), 0.0, 0.35)
	kit.cylinder("metal", Vector3(1.4, 0.02, 24.6), Vector3(1.4, 1.9, 24.6), 0.025, GUNMETAL, 6)
	kit.cylinder("metal", Vector3(1.4, 0.0, 24.6), Vector3(1.4, 0.04, 24.6), 0.25, GUNMETAL, 12)
	kit.box("glass", Vector3(1.4, 1.65, 24.6), Vector3(0.14, 0.24, 0.05), Color.WHITE)
	kit.box("metal", Vector3(1.4, 1.88, 24.6), Vector3(0.4, 0.03, 0.03), GUNMETAL)
	_crate(kit, body, Vector3(-1.0, 0, 25.3), Vector3(1.0, 0.9, 0.8), Color(0.82, 0.84, 0.86))


## Bed with its head toward local -Z rotated by yaw; `pos` is the bed's floor centre.
static func _bed(kit: ArtMeshKit, body: StaticBody3D, pos: Vector3, yaw: float, color: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.bevel_box("metal", pos + Vector3(0, 0.3, 0), Vector3(0.95, 0.12, 2.0), 0.03, GUNMETAL, b)
	for sx in [-0.4, 0.4]:
		for sz in [-0.9, 0.9]:
			kit.cylinder("metal", pos + b * Vector3(sx, 0, sz), pos + b * Vector3(sx, 0.3, sz), 0.035, GUNMETAL, 6)
	kit.bevel_box("soft", pos + b * Vector3(0, 0.44, 0.02), Vector3(0.88, 0.16, 1.9), 0.06, Color(0.85, 0.88, 0.9), b)
	kit.bevel_box("soft", pos + b * Vector3(0, 0.55, -0.72), Vector3(0.6, 0.1, 0.35), 0.05, Color.WHITE, b)
	kit.bevel_box("soft", pos + b * Vector3(0, 0.53, 0.35), Vector3(0.92, 0.06, 1.15), 0.03, color.darkened(0.35), b)
	kit.bevel_box("painted", pos + b * Vector3(0, 0.6, -1.0), Vector3(0.95, 1.2, 0.08), 0.03, Color(0.86, 0.88, 0.9), b)
	kit.box("screen", pos + b * Vector3(0.0, 0.95, -0.955), Vector3(0.5, 0.25, 0.01), Color(0.4, 1.0, 0.55), b)
	_collider(body, pos + Vector3(0, 0.35, 0), Vector3(0.95, 0.7, 2.0), b)
	_ao_rect(kit, pos, Vector2(0.45, 0.95), yaw, 0.35)


# --- exterior -----------------------------------------------------------------------------

static func _build_exterior(fx: ArtStationFX, mats: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Exterior"
	fx.add_child(node)
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
	var corners := [[Vector3(-7.4, H + 0.3, -26.4), Color(1, 0.15, 0.1)], [Vector3(-7.4, H + 0.3, 26.4), Color(1, 0.15, 0.1)], [Vector3(69.4, H + 0.3, 26.4), Color(0.2, 1, 0.3)], [Vector3(68.4, H + 0.3, -6.4), Color(0.2, 1, 0.3)], [Vector3(47.4, H + 0.3, -26.4), Color(1, 1, 1)]]
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
	_wall(kit, body, false, fixed, a0, mid - hw, -1.0, color, color, false)
	_wall(kit, body, false, fixed, mid + hw, a1, -1.0, color, color, false)
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
	_label(fx, node, "OUTER HULL DOOR", Vector3(fixed + 0.37, AIRLOCK_DOOR_TOP + 0.17, mid), Vector3(1, 0, 0), 40, 0.004, Color(1.0, 0.85, 0.6))


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
	# Suit lockers on the north and south walls.
	for sz in [-1.0, 1.0]:
		for i in range(2):
			var p := Vector3(r.position.x + 1.6 + float(i) * 1.0, 0, (r.position.y + 0.3) if sz < 0.0 else (r.end.y - 0.3))
			kit.bevel_box("painted", p + Vector3(0, 1.0, 0), Vector3(0.9, 2.0, 0.5), 0.04, Color(0.3, 0.32, 0.35))
			kit.box("glass", p + Vector3(0, 1.25, -sz * 0.255), Vector3(0.6, 1.2, 0.01), Color.WHITE)
			kit.sphere("painted", p + Vector3(0, 1.6, 0.0), 0.17, Color(0.85, 0.85, 0.82), 10)
			kit.box("painted", p + Vector3(0, 1.05, 0.0), Vector3(0.4, 0.7, 0.2), Color(0.85, 0.5, 0.2))
			kit.box("trim", p + Vector3(0, 0.15, -sz * 0.255), Vector3(0.6, 0.04, 0.01), color)
		_collider(body, Vector3(r.position.x + 2.1, 1.0, (r.position.y + 0.3) if sz < 0.0 else (r.end.y - 0.3)), Vector3(1.9, 2.0, 0.5))
		_ao_rect(kit, Vector3(r.position.x + 2.1, 0, (r.position.y + 0.3) if sz < 0.0 else (r.end.y - 0.3)), Vector2(0.95, 0.25), 0.0, 0.3)
	# Pressure gauges by the inner door.
	for sz in [-1.0, 1.0]:
		kit.box("screen", Vector3(r.end.x - 0.03, 1.6, sz * 1.95), Vector3(0.01, 0.4, 0.5), Color(1.0, 0.55, 0.2))

