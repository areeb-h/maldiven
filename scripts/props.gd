class_name Props
extends RefCounted
## Static factories for gameplay-facing visuals: carried items, interaction
## sockets, crew members and flashlights. All built procedurally from shared
## materials (ArtMaterials) so they batch and stay cheap on phones.

const SPINNER := preload("res://scripts/art/spinner.gd")
const GUN_SCRIPT := preload("res://scripts/art/gun_visual.gd")
const DARK := Color(0.14, 0.15, 0.17)
const GUNMETAL := Color(0.32, 0.34, 0.37)
const CELL_GLOW := Color(1.0, 0.68, 0.12)
const CORE_GLOW := Color(0.25, 0.95, 1.0)

static var _mats: Dictionary = {}


static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"cell_glow":
			m = ArtMaterials.glow(2.0)
		"core_glow":
			m = ArtMaterials.glow(2.0, false, 0.5)
		"core_halo":
			m = ArtMaterials.forcefield(CORE_GLOW)
		"accent":
			m = ArtMaterials.glow(1.8)
		"glass":
			m = ArtMaterials.glass(Color(0.6, 0.8, 1.0), 0.06)
		"visor":
			m = ArtMaterials.glass(Color(0.45, 0.65, 0.9), 0.14, false)
		"hazard":
			m = ArtMaterials.hazard()
	_mats[key] = m
	return m


static func _base_mats() -> Dictionary:
	return {
		"painted": ArtMaterials.painted(),
		"metal": ArtMaterials.metal(),
		"soft": ArtMaterials.soft(),
		"hazard": _mat("hazard"),
		"glass": _mat("glass"),
		"accent": _mat("accent"),
	}


# --- items ---------------------------------------------------------------------------------

## "cell", "core" or "gun". Origin at the item's bottom centre. The gun's
## barrel points along -Z and its root has set_ammo(n) for 0-3 charge cells.
static func make_item(kind: String) -> Node3D:
	return ItemFactory.make(kind)  # scripts/art/items/ (gun: grip at origin, barrel +Z)


static func _build_gun() -> Node3D:
	var root = GUN_SCRIPT.new()
	root.name = "Gun"
	var kit := ArtMeshKit.new()
	var graphite := Color(0.2, 0.21, 0.24)
	var shell := Color(0.93, 0.93, 0.9)
	var accent := Color(1.0, 0.45, 0.2)
	# Chunky toy blaster: rounded grip, fat body, bulb emitter, barrel along -Z.
	kit.bevel_box("painted", Vector3(0, 0.1, 0.11), Vector3(0.085, 0.2, 0.11), 0.035, graphite, Basis(Vector3.RIGHT, -0.28))
	kit.bevel_box("painted", Vector3(0, 0.235, -0.03), Vector3(0.12, 0.14, 0.36), 0.05, shell)
	kit.bevel_box("painted", Vector3(0, 0.31, 0.0), Vector3(0.07, 0.05, 0.2), 0.025, accent)
	var barrel := CapsuleMesh.new()
	barrel.radius = 0.045
	barrel.height = 0.24
	barrel.radial_segments = 14
	barrel.rings = 4
	kit.mesh("painted", barrel, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.235, -0.26)), graphite)
	kit.torus("metal", Vector3(0, 0.235, -0.22), 0.04, 0.065, Color(0.7, 0.72, 0.75), Basis(Vector3.RIGHT, PI / 2.0), 16, 6)
	kit.sphere("accent", Vector3(0, 0.235, -0.385), 0.04, Color(0.3, 0.9, 1.0), 12)
	kit.torus("painted", Vector3(0, 0.13, 0.03), 0.04, 0.06, graphite, Basis(Vector3.BACK, PI / 2.0), 14, 6)
	var mats := _base_mats()
	for i in range(3):
		var key := "cell%d" % i
		for sx in [-1.0, 1.0]:
			kit.sphere(key, Vector3(sx * 0.062, 0.235, 0.09 - float(i) * 0.065), 0.024, Color(0.3, 1.0, 0.75), 10, Vector3(0.6, 1, 1))
		var m := ArtMaterials.glow(2.0)
		mats[key] = m
		root.cell_mats.append(m)
	root.add_child(kit.to_instance(mats, "Mesh"))
	root.set_ammo(3)
	return root


static func _build_cell(root: Node3D) -> void:
	var kit := ArtMeshKit.new()
	# Chunky battery: rounded graphite casing, fat amber glow bands, terminal knob.
	kit.cylinder("painted", Vector3(0, 0.07, 0), Vector3(0, 0.5, 0), 0.16, DARK, 20)
	kit.sphere("painted", Vector3(0, 0.07, 0), 0.16, DARK, 20, Vector3(1, 0.45, 1))
	kit.sphere("painted", Vector3(0, 0.5, 0), 0.16, DARK, 20, Vector3(1, 0.45, 1))
	for y in [0.18, 0.39]:
		kit.cylinder("cell_glow", Vector3(0, y - 0.035, 0), Vector3(0, y + 0.035, 0), 0.168, CELL_GLOW, 20)
	kit.torus("metal", Vector3(0, 0.285, 0), 0.15, 0.185, Color(0.72, 0.74, 0.77), Basis.IDENTITY, 24, 8)
	kit.cylinder("metal", Vector3(0, 0.55, 0), Vector3(0, 0.6, 0), 0.06, Color(0.85, 0.7, 0.3), 12)
	kit.sphere("cell_glow", Vector3(0, 0.6, 0), 0.05, CELL_GLOW, 10)
	kit.torus("painted", Vector3(0, 0.56, 0), 0.075, 0.11, Color(0.95, 0.75, 0.2), Basis(Vector3.RIGHT, PI / 2.0), 16, 8)
	var mats := _base_mats()
	mats["cell_glow"] = _mat("cell_glow")
	root.add_child(kit.to_instance(mats, "Mesh"))


static func _build_core(root: Node3D) -> void:
	var kit := ArtMeshKit.new()
	# Rounded cradle with a lit collar.
	kit.cylinder("painted", Vector3(0, 0, 0), Vector3(0, 0.07, 0), 0.2, DARK, 24, 0.17)
	kit.torus("accent", Vector3(0, 0.075, 0), 0.12, 0.16, CORE_GLOW, Basis.from_scale(Vector3(1, 0.5, 1)), 24, 6)
	var mats := _base_mats()
	root.add_child(kit.to_instance(mats, "Base"))
	# Glowing cyan orb inside a rounded cage, spinning slowly.
	var spin := Node3D.new()
	spin.name = "Crystal"
	spin.set_script(SPINNER)
	spin.position = Vector3(0, 0.36, 0)
	root.add_child(spin)
	var ck := ArtMeshKit.new()
	ck.sphere("core_glow", Vector3.ZERO, 0.15, CORE_GLOW, 20)
	for ang in [0.0, PI / 2.0]:
		ck.torus("metal", Vector3.ZERO, 0.2, 0.235, Color(0.85, 0.87, 0.9), Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, PI / 2.0), 32, 8)
	ck.torus("metal", Vector3.ZERO, 0.2, 0.235, Color(0.85, 0.87, 0.9), Basis.IDENTITY, 32, 8)
	ck.sphere("painted", Vector3(0, 0.22, 0), 0.05, DARK, 10)
	ck.sphere("painted", Vector3(0, -0.22, 0), 0.05, DARK, 10)
	ck.sphere("core_halo", Vector3.ZERO, 0.24, Color.WHITE, 18)
	var cmats := mats.duplicate()
	cmats["core_glow"] = _mat("core_glow")
	cmats["core_halo"] = _mat("core_halo")
	spin.add_child(ck.to_instance(cmats, "Mesh", false))
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = CORE_GLOW
	light.light_energy = 1.2
	light.omni_range = 3.2
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.position = Vector3(0, 0.36, 0)
	root.add_child(light)


# --- sockets -------------------------------------------------------------------------------

## "vault", "reactor", "shuttle", "pod", "armory", "medbay" or "airlock_console".
## Returns a SocketVisual (front = +Z).
static func make_socket(kind: String) -> Node3D:
	return SocketKit.make(kind)  # scripts/art/items/sockets/ (SocketVisual: set_state, get_seat_transform)


static func _box_collider(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


static func _build_vault(socket: SocketVisual, kit: ArtMeshKit, body: StaticBody3D) -> float:
	var blue := Color(0.3, 0.5, 1.0)
	kit.cylinder("painted", Vector3.ZERO, Vector3(0, 0.55, 0), 0.72, DARK, 6, 0.62)
	kit.cylinder("metal", Vector3(0, 0.55, 0), Vector3(0, 0.62, 0), 0.6, GUNMETAL, 6, 0.55)
	kit.torus("status", Vector3(0, 0.625, 0), 0.32, 0.38, Color.WHITE, Basis.from_scale(Vector3(1, 0.4, 1)), 24, 4)
	kit.box("status", Vector3(0, 0.3, 0.62), Vector3(0.36, 0.06, 0.02), Color.WHITE)
	# Backplate with lit spine.
	kit.bevel_box("painted", Vector3(0, 1.15, -0.78), Vector3(1.4, 2.3, 0.22), 0.06, DARK)
	kit.box("status", Vector3(0, 1.3, -0.665), Vector3(0.06, 1.6, 0.01), Color.WHITE)
	for sx in [-0.45, 0.45]:
		kit.box("accent", Vector3(sx, 1.3, -0.665), Vector3(0.03, 1.8, 0.01), blue)
	kit.bevel_box("metal", Vector3(0, 2.32, -0.6), Vector3(1.5, 0.12, 0.6), 0.03, GUNMETAL)
	_box_collider(body, Vector3(0, 0.3, 0), Vector3(1.2, 0.6, 1.2))
	_box_collider(body, Vector3(0, 1.15, -0.78), Vector3(1.4, 2.3, 0.22))
	# Cage + forcefield, shown while locked.
	var cage := ArtMeshKit.new()
	for i in range(6):
		var ang := TAU * (float(i) + 0.5) / 6.0
		var p := Vector3(cos(ang), 0, sin(ang)) * 0.68
		cage.cylinder("metal", p + Vector3(0, 0.6, 0), p + Vector3(0, 2.0, 0), 0.03, GUNMETAL, 6)
	cage.torus("metal", Vector3(0, 2.0, 0), 0.62, 0.74, GUNMETAL, Basis.IDENTITY, 6, 4)
	var shell := CylinderMesh.new()
	shell.top_radius = 0.66
	shell.bottom_radius = 0.66
	shell.height = 1.4
	shell.radial_segments = 24
	shell.rings = 1
	shell.cap_top = false
	shell.cap_bottom = false
	_add_field(socket, cage, shell, Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), Color(0.35, 0.6, 1.0))
	return 0.63


## Shared cage + forcefield (vault and armory), hidden when unlocked.
static func _add_field(socket: SocketVisual, cage: ArtMeshKit, field_mesh: Mesh, field_xform: Transform3D, color: Color) -> void:
	cage.mesh("field", field_mesh, field_xform, Color.WHITE)
	var field_mat := ArtMaterials.forcefield(color)
	var cage_mats := _base_mats()
	cage_mats["field"] = field_mat
	var cage_mi := cage.to_instance(cage_mats, "Cage", false)
	socket.add_child(cage_mi)
	socket.field = cage_mi
	socket.field_mat = field_mat


static func _build_armory(socket: SocketVisual, kit: ArtMeshKit, body: StaticBody3D) -> float:
	var red := Color(0.95, 0.3, 0.3)
	# Wall rack: back panel, shelf, cradle with a lit outline; front faces +Z.
	kit.bevel_box("painted", Vector3(0, 1.2, -0.35), Vector3(1.5, 2.3, 0.16), 0.05, DARK)
	kit.bevel_box("painted", Vector3(0, 0.4, -0.1), Vector3(1.3, 0.8, 0.5), 0.05, Color(0.3, 0.17, 0.18))
	kit.box("hazard", Vector3(0, 0.12, 0.152), Vector3(1.26, 0.14, 0.01), Color.WHITE)
	kit.box("status", Vector3(0, 0.66, 0.152), Vector3(0.9, 0.05, 0.01), Color.WHITE)
	kit.bevel_box("metal", Vector3(0, 0.84, -0.1), Vector3(1.36, 0.08, 0.56), 0.02, GUNMETAL)
	kit.bevel_box("metal", Vector3(0, 1.15, -0.25), Vector3(0.24, 0.5, 0.12), 0.02, GUNMETAL)
	kit.box("status", Vector3(0, 1.2, -0.265), Vector3(0.3, 0.7, 0.01), Color.WHITE)
	for sx in [-0.5, 0.5]:
		kit.box("accent", Vector3(sx, 1.4, -0.265), Vector3(0.03, 1.6, 0.01), red)
	kit.bevel_box("metal", Vector3(0, 2.38, -0.2), Vector3(1.6, 0.12, 0.5), 0.03, GUNMETAL)
	_box_collider(body, Vector3(0, 0.45, -0.12), Vector3(1.4, 0.9, 0.56))
	_box_collider(body, Vector3(0, 1.2, -0.35), Vector3(1.5, 2.3, 0.16))
	var cage := ArtMeshKit.new()
	for i in range(5):
		var x := -0.6 + float(i) * 0.3
		cage.cylinder("metal", Vector3(x, 0.88, 0.2), Vector3(x, 2.3, 0.2), 0.025, GUNMETAL, 6)
	cage.box("metal", Vector3(0, 2.3, 0.2), Vector3(1.3, 0.05, 0.05), GUNMETAL)
	var plane := QuadMesh.new()
	plane.size = Vector2(1.3, 1.42)
	_add_field(socket, cage, plane, Transform3D(Basis.IDENTITY, Vector3(0, 1.59, 0.18)), Color(1.0, 0.35, 0.3))
	return 0.95


static func _build_medbay(kit: ArtMeshKit, body: StaticBody3D) -> float:
	var green := Color(0.35, 0.95, 0.45)
	# Bed along local X; the patient side faces +Z (the room).
	kit.bevel_box("painted", Vector3(0, 0.3, 0), Vector3(2.1, 0.6, 0.85), 0.06, Color(0.86, 0.88, 0.9))
	kit.box("status", Vector3(0, 0.3, 0.428), Vector3(1.6, 0.05, 0.01), Color.WHITE)
	kit.bevel_box("soft", Vector3(0.05, 0.66, 0), Vector3(1.95, 0.12, 0.78), 0.05, Color(0.75, 0.82, 0.86))
	kit.bevel_box("soft", Vector3(0.8, 0.76, 0), Vector3(0.35, 0.08, 0.55), 0.04, Color.WHITE)
	# Scanner arch over the bed and a vitals monitor at the head.
	kit.torus("metal", Vector3(0.0, 0.62, 0), 0.62, 0.74, GUNMETAL, Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0), 32, 8)
	kit.torus("status", Vector3(0.0, 0.62, 0), 0.6, 0.63, Color.WHITE, Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0), 32, 4)
	kit.bevel_box("painted", Vector3(1.2, 1.0, -0.2), Vector3(0.12, 1.2, 0.5), 0.03, DARK)
	kit.box("accent", Vector3(1.135, 1.3, -0.2), Vector3(0.01, 0.3, 0.4), green)
	_box_collider(body, Vector3(0, 0.36, 0), Vector3(2.1, 0.72, 0.85))
	return 0.74


static func _build_airlock_console(kit: ArtMeshKit, body: StaticBody3D) -> float:
	var orange := Color(1.0, 0.48, 0.24)
	# Pedestal console with an angled panel and a big red lever + button.
	kit.bevel_box("painted", Vector3(0, 0.5, -0.05), Vector3(0.7, 1.0, 0.5), 0.05, DARK)
	kit.box("hazard", Vector3(0, 0.15, 0.202), Vector3(0.66, 0.24, 0.01), Color.WHITE)
	kit.bevel_box("metal", Vector3(0, 1.06, 0.0), Vector3(0.76, 0.08, 0.56), 0.02, GUNMETAL, Basis(Vector3.RIGHT, 0.4))
	kit.box("status", Vector3(-0.12, 1.1, 0.02), Vector3(0.38, 0.01, 0.34), Color.WHITE, Basis(Vector3.RIGHT, 0.4))
	kit.cylinder("painted", Vector3(0.22, 1.08, 0.08), Vector3(0.22, 1.13, 0.08), 0.1, Color(0.2, 0.2, 0.22), 16)
	kit.cylinder("alarm_btn", Vector3(0.22, 1.12, 0.08), Vector3(0.22, 1.18, 0.08), 0.075, Color(1.0, 0.1, 0.05), 16)
	kit.bevel_box("metal", Vector3(0.3, 1.0, -0.26), Vector3(0.06, 0.12, 0.08), 0.01, GUNMETAL)
	kit.cylinder("painted", Vector3(0.3, 1.0, -0.26), Vector3(0.3, 1.45, -0.12), 0.025, Color(0.75, 0.1, 0.06), 8)
	kit.sphere("painted", Vector3(0.3, 1.47, -0.11), 0.05, Color(0.85, 0.12, 0.07), 10)
	kit.box("accent", Vector3(0, 0.75, 0.203), Vector3(0.5, 0.04, 0.01), orange)
	_box_collider(body, Vector3(0, 0.55, -0.05), Vector3(0.7, 1.1, 0.5))
	return 1.12


static func _build_reactor_socket(kit: ArtMeshKit, body: StaticBody3D) -> float:
	var violet := Color(0.65, 0.4, 1.0)
	kit.bevel_box("painted", Vector3(0, 0.35, 0), Vector3(0.78, 0.7, 0.7), 0.06, DARK)
	kit.box("hazard", Vector3(0, 0.08, 0.352), Vector3(0.74, 0.12, 0.01), Color.WHITE)
	kit.box("status", Vector3(0, 0.5, 0.352), Vector3(0.5, 0.05, 0.01), Color.WHITE)
	kit.cylinder("metal", Vector3(0, 0.7, 0), Vector3(0, 0.76, 0), 0.24, GUNMETAL, 16)
	kit.torus("status", Vector3(0, 0.765, 0), 0.17, 0.21, Color.WHITE, Basis.from_scale(Vector3(1, 0.4, 1)), 20, 4)
	for sx in [-1.0, 1.0]:
		kit.bevel_box("metal", Vector3(sx * 0.27, 1.0, 0), Vector3(0.06, 0.55, 0.16), 0.015, GUNMETAL)
		kit.box("accent", Vector3(sx * 0.24, 1.0, 0), Vector3(0.01, 0.4, 0.05), violet)
	kit.cylinder("glass", Vector3(0, 0.76, 0), Vector3(0, 1.4, 0), 0.21, Color.WHITE, 16)
	kit.cylinder("metal", Vector3(0, 1.4, 0), Vector3(0, 1.44, 0), 0.23, GUNMETAL, 16)
	# Conduit into the floor behind.
	kit.cylinder("painted", Vector3(0, 0.25, -0.35), Vector3(0, 0.25, -0.6), 0.08, DARK, 8)
	_box_collider(body, Vector3(0, 0.38, 0), Vector3(0.78, 0.76, 0.7))
	return 0.765


static func _build_launch_socket(kit: ArtMeshKit, body: StaticBody3D, shell: Color, accent: Color, hazard_heavy: bool) -> float:
	kit.cylinder("metal", Vector3.ZERO, Vector3(0, 0.08, 0), 0.6, GUNMETAL, 20)
	kit.torus("status", Vector3(0, 0.085, 0), 0.62, 0.68, Color.WHITE, Basis.from_scale(Vector3(1, 0.2, 1)), 32, 4)
	kit.bevel_box("painted", Vector3(0, 0.5, 0), Vector3(0.62, 0.84, 0.56), 0.06, shell)
	kit.box("hazard", Vector3(0, 0.22, 0.282), Vector3(0.58, 0.18 if not hazard_heavy else 0.34, 0.01), Color.WHITE)
	if hazard_heavy:
		kit.box("hazard", Vector3(0.312, 0.4, 0), Vector3(0.01, 0.5, 0.5), Color.WHITE)
		kit.box("hazard", Vector3(-0.312, 0.4, 0), Vector3(0.01, 0.5, 0.5), Color.WHITE)
	kit.box("accent", Vector3(0, 0.75, 0.282), Vector3(0.4, 0.05, 0.01), accent)
	# Clamp cradle on top.
	kit.cylinder("metal", Vector3(0, 0.92, 0), Vector3(0, 0.98, 0), 0.26, GUNMETAL, 16)
	kit.torus("status", Vector3(0, 0.99, 0), 0.19, 0.24, Color.WHITE, Basis.from_scale(Vector3(1, 0.45, 1)), 20, 4)
	for i in range(3):
		var ang := TAU * float(i) / 3.0 + PI / 6.0
		var p := Vector3(cos(ang), 0, sin(ang)) * 0.22
		kit.bevel_box("metal", p + Vector3(0, 1.1, 0), Vector3(0.05, 0.25, 0.05), 0.012, GUNMETAL, Basis(Vector3.UP, -ang) * Basis(Vector3.BACK, -0.3))
	# Angled status screen and a warning beacon post.
	kit.bevel_box("painted", Vector3(0.0, 1.05, -0.33), Vector3(0.6, 0.4, 0.06), 0.02, DARK, Basis(Vector3.RIGHT, -0.35))
	kit.box("status", Vector3(0.0, 1.06, -0.305), Vector3(0.5, 0.3, 0.01), Color.WHITE, Basis(Vector3.RIGHT, -0.35))
	kit.cylinder("metal", Vector3(0.36, 0.0, -0.22), Vector3(0.36, 1.55, -0.22), 0.03, GUNMETAL, 6)
	kit.sphere("status", Vector3(0.36, 1.6, -0.22), 0.07, Color.WHITE, 10)
	_box_collider(body, Vector3(0, 0.5, 0), Vector3(0.62, 1.0, 0.56))
	return 0.99


# --- crew --------------------------------------------------------------------------------------

## Explorer model dressed as a space crew member in `color`. Native orientation
## (faces +Z); the caller applies rotation.y = PI. Limb pivots keep their names.
static func make_crew_visual(color: Color) -> Node3D:
	var packed: PackedScene = load("res://assets/models/explorer.glb")
	var visual: Node3D = packed.instantiate()
	var suit := _crew_mat(color, 0.55, 0.15)
	var pants := _crew_mat(color.darkened(0.55).lerp(Color(0.12, 0.13, 0.15), 0.4), 0.7, 0.1)
	var boots := _crew_mat(Color(0.12, 0.12, 0.13), 0.6, 0.3)
	var gloves := _crew_mat(Color(0.2, 0.21, 0.23), 0.65, 0.1)
	var trim := _crew_mat(Color(0.82, 0.83, 0.85), 0.4, 0.5)
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var lname := String(mi.name).to_lower()
		if lname.begins_with("hat_"):
			mi.visible = false
			continue
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(i)
			var mname := src.resource_name.to_lower() if src != null else ""
			var replacement: Material = null
			if mname == "shirt" or lname.contains("forearm"):
				replacement = suit
			elif mname == "pants":
				replacement = pants
			elif mname == "shoe":
				replacement = boots
			elif lname.contains("hand"):
				replacement = gloves
			elif mname == "trim":
				replacement = trim
			if replacement != null:
				mi.set_surface_override_material(i, replacement)
	# Helmet, collar ring, backpack with a status light.
	var kit := ArtMeshKit.new()
	kit.torus("trim_c", Vector3(0, 1.455, 0.0), 0.15, 0.225, color.lightened(0.25), Basis.from_scale(Vector3(1, 0.7, 1)), 24, 8)
	kit.torus("metal", Vector3(0, 1.49, 0.0), 0.2, 0.235, Color(0.75, 0.77, 0.8), Basis.IDENTITY, 24, 6)
	kit.bevel_box("painted", Vector3(0, 1.13, -0.25), Vector3(0.38, 0.46, 0.2), 0.05, Color(0.78, 0.79, 0.8))
	kit.bevel_box("painted", Vector3(0, 1.13, -0.36), Vector3(0.3, 0.36, 0.04), 0.015, color.darkened(0.3))
	for sx in [-0.12, 0.12]:
		kit.cylinder("metal", Vector3(sx, 0.92, -0.3), Vector3(sx, 1.34, -0.3), 0.045, Color(0.55, 0.57, 0.6), 8)
	kit.box("light", Vector3(0.0, 1.37, -0.29), Vector3(0.12, 0.03, 0.08), color.lightened(0.3))
	kit.box("light", Vector3(0.0, 1.13, 0.145), Vector3(0.14, 0.03, 0.01), color.lightened(0.4))
	var light_mat := ArtMaterials.glow(2.5)
	var trim_c := _crew_mat(color.lightened(0.25), 0.4, 0.4)
	trim_c.vertex_color_use_as_albedo = false
	var mats := _base_mats()
	mats["light"] = light_mat
	mats["trim_c"] = trim_c
	var gear := kit.to_instance(mats, "Gear")
	visual.add_child(gear)
	var helmet := MeshInstance3D.new()
	helmet.name = "Helmet"
	var dome := SphereMesh.new()
	dome.radius = 0.265
	dome.height = 0.53
	dome.radial_segments = 24
	dome.rings = 12
	helmet.mesh = dome
	helmet.material_override = _mat("visor")
	helmet.position = Vector3(0, 1.7, 0.02)
	helmet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(helmet)
	return visual


static func _crew_mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.albedo_texture = ArtMaterials.texture("metal_paint_albedo")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(3, 3, 3)
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	return m


# --- flashlight --------------------------------------------------------------------------------

static func make_flashlight() -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "Flashlight"
	light.light_color = Color(1.0, 0.95, 0.86)
	light.light_energy = 4.0
	light.light_specular = 0.6
	light.spot_range = 14.0
	light.spot_attenuation = 0.9
	light.spot_angle = 27.0
	light.spot_angle_attenuation = 1.6
	light.shadow_enabled = false
	return light
