class_name PropFactory
extends RefCounted
## Procedural pushable props in the station's premium-toy style: chunky bevels,
## glossy painted shells, brushed bumpers and a room-colour accent. Each kind has
## a matching compound collider, mass, surface and push resistance.
##
## Origin at the bottom centre, front = +Z. Meshes are cached per (kind, accent).

const KINDS := ["crate", "crate_small", "barrel", "cart", "chair", "toolbox", "canister"]

## mass kg, friction, bounce, push: 0..1 how much the prop slows a player pushing
## it, radius: bounding radius (m, for budget checks), height (m), damp: linear damp.
const SPECS := {
	"crate": {"mass": 16.0, "friction": 0.75, "bounce": 0.05, "push": 0.30, "radius": 0.56, "height": 0.66, "damp": 0.05},
	"crate_small": {"mass": 8.0, "friction": 0.7, "bounce": 0.08, "push": 0.16, "radius": 0.4, "height": 0.5, "damp": 0.05},
	"barrel": {"mass": 22.0, "friction": 0.55, "bounce": 0.12, "push": 0.40, "radius": 0.48, "height": 0.92, "damp": 0.05},
	"cart": {"mass": 18.0, "friction": 0.06, "bounce": 0.1, "push": 0.12, "radius": 0.62, "height": 0.95, "damp": 0.45},
	"chair": {"mass": 6.0, "friction": 0.55, "bounce": 0.1, "push": 0.08, "radius": 0.42, "height": 1.0, "damp": 0.05},
	"toolbox": {"mass": 5.0, "friction": 0.7, "bounce": 0.1, "push": 0.06, "radius": 0.3, "height": 0.3, "damp": 0.05},
	"canister": {"mass": 4.0, "friction": 0.45, "bounce": 0.18, "push": 0.05, "radius": 0.33, "height": 0.62, "damp": 0.05},
}

const GRAPHITE := Color(0.2, 0.21, 0.23)
const SHELL := Color(0.9, 0.9, 0.87)
const BRUSHED := Color(0.64, 0.66, 0.69)
const RUBBER := Color(0.1, 0.1, 0.11)

static var _mesh_cache := {}
static var _mats := {}


## A RigidBody3D-ready description: {"mesh": Mesh, "shapes": [[Shape3D, Transform3D]], spec...}.
static func describe(kind: String, accent: Color) -> Dictionary:
	var out: Dictionary = SPECS[kind].duplicate()
	out["kind"] = kind
	out["mesh"] = _mesh(kind, accent)
	out["shapes"] = _shapes(kind)
	return out


# --- materials --------------------------------------------------------------------------

## Object-space versions of the station's painted/metal finishes: world-space
## triplanar detail would swim across a prop as it tumbles.
static func materials() -> Dictionary:
	if _mats.is_empty():
		var painted: StandardMaterial3D = ArtMaterials.painted().duplicate()
		painted.uv1_world_triplanar = false
		painted.uv1_scale = Vector3(2.2, 2.2, 2.2)
		var metal: StandardMaterial3D = ArtMaterials.metal().duplicate()
		metal.uv1_world_triplanar = false
		metal.uv1_scale = Vector3(2.2, 2.2, 2.2)
		_mats = {"painted": painted, "metal": metal, "soft": ArtMaterials.soft(),
			"glow": ArtMaterials.glow(1.7), "hazard": ArtMaterials.hazard()}
	return _mats


# --- meshes -----------------------------------------------------------------------------

static func _mesh(kind: String, accent: Color) -> Mesh:
	var key := "%s_%s" % [kind, accent.to_html(false)]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var kit := ArtMeshKit.new()
	match kind:
		"crate":
			_crate(kit, Vector3(0.78, 0.66, 0.78), accent, SHELL)
		"crate_small":
			_crate(kit, Vector3(0.56, 0.5, 0.56), accent, accent.lerp(SHELL, 0.35))
		"barrel":
			_barrel(kit, accent)
		"cart":
			_cart(kit, accent)
		"chair":
			_chair(kit, accent)
		"toolbox":
			_toolbox(kit, accent)
		"canister":
			_canister(kit, accent)
	var mesh := kit.build(materials())
	_mesh_cache[key] = mesh
	return mesh


static func _crate(kit: ArtMeshKit, size: Vector3, accent: Color, shell: Color) -> void:
	var c := Vector3(0, size.y * 0.5, 0)
	var bevel := minf(0.11, size.y * 0.16)
	kit.bevel_box("painted", c, size - Vector3(0.04, 0.0, 0.04), bevel, shell)
	# Brushed bumper bands top and bottom, chunky corner posts.
	for sy in [-1.0, 1.0]:
		kit.bevel_box("metal", c + Vector3(0, sy * (size.y * 0.5 - 0.075), 0), Vector3(size.x + 0.02, 0.1, size.z + 0.02), 0.04, BRUSHED)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.bevel_box("painted", c + Vector3(sx * (size.x * 0.5 - 0.05), 0, sz * (size.z * 0.5 - 0.05)), Vector3(0.12, size.y - 0.04, 0.12), 0.045, GRAPHITE)
	# Accent glow strip and a hazard tag on the front and back; inset side panels.
	for sz in [-1.0, 1.0]:
		var face := c + Vector3(0, 0, sz * size.z * 0.5)
		kit.bevel_box("glow", face + Vector3(0, 0.02, sz * 0.012), Vector3(size.x * 0.56, 0.05, 0.03), 0.012, accent)
		kit.bevel_box("hazard", face + Vector3(-size.x * 0.2, -size.y * 0.16, sz * 0.012), Vector3(size.x * 0.22, size.y * 0.16, 0.03), 0.012, Color.WHITE)
	for sx in [-1.0, 1.0]:
		var side := c + Vector3(sx * size.x * 0.5, 0, 0)
		kit.bevel_box("painted", side + Vector3(sx * 0.01, 0, 0), Vector3(0.03, size.y * 0.5, size.z * 0.56), 0.012, shell.darkened(0.12))
		kit.bevel_box("metal", side + Vector3(sx * 0.03, size.y * 0.12, 0), Vector3(0.05, 0.05, size.z * 0.34), 0.02, BRUSHED)  # grab handle


static func _barrel(kit: ArtMeshKit, accent: Color) -> void:
	var r := 0.3
	var h := 0.92
	var body := accent.lerp(Color(0.95, 0.55, 0.15), 0.5)
	kit.cylinder("painted", Vector3(0, 0.05, 0), Vector3(0, h - 0.05, 0), r - 0.012, body, 24)
	kit.cylinder("painted", Vector3(0, h - 0.05, 0), Vector3(0, h, 0), r - 0.012, body.darkened(0.15), 24, r - 0.05)
	kit.cylinder("painted", Vector3(0, 0, 0), Vector3(0, 0.05, 0), r - 0.05, GRAPHITE, 24, r - 0.012)
	for y in [0.06, 0.32, 0.6, 0.86]:
		kit.torus("metal", Vector3(0, y, 0), r - 0.03, r + 0.012, BRUSHED, Basis.IDENTITY, 28, 8)
	kit.cylinder("hazard", Vector3(0, 0.4, 0), Vector3(0, 0.52, 0), r + 0.002, Color.WHITE, 24)
	kit.cylinder("glow", Vector3(0, 0.7, 0), Vector3(0, 0.74, 0), r + 0.004, accent.lightened(0.2), 24)
	# Lid: recessed disc, bung and a fat rim.
	kit.cylinder("painted", Vector3(0, h - 0.012, 0), Vector3(0, h + 0.004, 0), r - 0.07, GRAPHITE, 20)
	kit.cylinder("metal", Vector3(0.12, h, 0.05), Vector3(0.12, h + 0.04, 0.05), 0.045, BRUSHED, 12)
	kit.torus("painted", Vector3(0, h - 0.01, 0), r - 0.07, r - 0.01, body.darkened(0.25), Basis.IDENTITY, 28, 6)


static func _cart(kit: ArtMeshKit, accent: Color) -> void:
	var tray := Vector3(1.0, 0.16, 0.58)
	# Two rounded trays on four posts, a push handle, fat caster wheels.
	for y in [0.3, 0.74]:
		kit.bevel_box("painted", Vector3(0, y, 0), tray, 0.06, SHELL)
		kit.bevel_box("glow", Vector3(0, y + 0.02, tray.z * 0.5 + 0.005), Vector3(tray.x * 0.7, 0.035, 0.02), 0.01, accent)
		kit.bevel_box("painted", Vector3(0, y + 0.09, 0), Vector3(tray.x - 0.12, 0.03, tray.z - 0.12), 0.012, accent.darkened(0.35))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := Vector3(sx * (tray.x * 0.5 - 0.07), 0, sz * (tray.z * 0.5 - 0.07))
			kit.cylinder("metal", post + Vector3(0, 0.2, 0), post + Vector3(0, 0.82, 0), 0.03, BRUSHED, 10)
			kit.cylinder("painted", post + Vector3(0, 0.16, 0), post + Vector3(0, 0.22, 0), 0.05, GRAPHITE, 10)
			var axle := post + Vector3(0, 0.085, 0)
			kit.cylinder("painted", axle - Vector3(0, 0, 0.035), axle + Vector3(0, 0, 0.035), 0.08, RUBBER, 16)
			kit.cylinder("metal", axle - Vector3(0, 0, 0.04), axle + Vector3(0, 0, 0.04), 0.035, BRUSHED, 10)
	var hx := -tray.x * 0.5 - 0.02
	kit.cylinder("metal", Vector3(hx, 0.78, -0.22), Vector3(hx - 0.06, 0.98, -0.22), 0.025, BRUSHED, 10)
	kit.cylinder("metal", Vector3(hx, 0.78, 0.22), Vector3(hx - 0.06, 0.98, 0.22), 0.025, BRUSHED, 10)
	kit.cylinder("painted", Vector3(hx - 0.06, 0.98, -0.26), Vector3(hx - 0.06, 0.98, 0.26), 0.035, GRAPHITE, 12)
	# Cargo on the top tray: a small box and a canister.
	kit.bevel_box("painted", Vector3(0.18, 0.92, 0.05), Vector3(0.3, 0.2, 0.26), 0.04, accent.lerp(SHELL, 0.4))
	kit.cylinder("painted", Vector3(-0.2, 0.83, -0.08), Vector3(-0.2, 1.0, -0.08), 0.07, Color(0.3, 0.75, 0.55), 14)
	kit.sphere("metal", Vector3(-0.2, 1.0, -0.08), 0.03, BRUSHED, 8)


static func _chair(kit: ArtMeshKit, accent: Color) -> void:
	# Swivel chair: five-star base on casters, chrome column, cushioned seat and back.
	for i in range(5):
		var ang := TAU * float(i) / 5.0
		var dir := Vector3(sin(ang), 0, cos(ang))
		var basis := Basis(Vector3.UP, ang)
		kit.bevel_box("painted", dir * 0.13 + Vector3(0, 0.07, 0), Vector3(0.06, 0.05, 0.26), 0.02, GRAPHITE, basis)
		kit.sphere("painted", dir * 0.25 + Vector3(0, 0.035, 0), 0.035, RUBBER, 8)
	kit.cylinder("metal", Vector3(0, 0.06, 0), Vector3(0, 0.42, 0), 0.035, BRUSHED, 12)
	kit.cylinder("painted", Vector3(0, 0.05, 0), Vector3(0, 0.12, 0), 0.06, GRAPHITE, 12)
	kit.bevel_box("painted", Vector3(0, 0.44, 0), Vector3(0.44, 0.05, 0.42), 0.02, GRAPHITE)
	kit.bevel_box("soft", Vector3(0, 0.5, 0.01), Vector3(0.48, 0.09, 0.46), 0.04, accent.darkened(0.2))
	kit.bevel_box("painted", Vector3(0, 0.62, -0.2), Vector3(0.06, 0.26, 0.04), 0.015, BRUSHED)
	kit.bevel_box("soft", Vector3(0, 0.84, -0.215), Vector3(0.44, 0.38, 0.08), 0.04, accent.darkened(0.2))
	kit.bevel_box("glow", Vector3(0, 0.98, -0.255), Vector3(0.3, 0.03, 0.02), 0.008, accent)
	for sx in [-1.0, 1.0]:
		kit.bevel_box("painted", Vector3(sx * 0.25, 0.62, -0.02), Vector3(0.04, 0.04, 0.3), 0.015, GRAPHITE)
		kit.cylinder("metal", Vector3(sx * 0.25, 0.47, -0.02), Vector3(sx * 0.25, 0.61, -0.02), 0.014, BRUSHED, 8)


static func _toolbox(kit: ArtMeshKit, accent: Color) -> void:
	var body := accent.lerp(Color(0.92, 0.22, 0.16), 0.45)
	kit.bevel_box("painted", Vector3(0, 0.1, 0), Vector3(0.5, 0.2, 0.26), 0.035, body)
	kit.bevel_box("painted", Vector3(0, 0.215, 0), Vector3(0.51, 0.04, 0.27), 0.015, body.darkened(0.3))
	kit.bevel_box("painted", Vector3(0, 0.235, 0), Vector3(0.46, 0.03, 0.22), 0.012, body.lightened(0.1))
	kit.torus("metal", Vector3(0, 0.25, 0), 0.05, 0.07, BRUSHED, Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.8, 1, 1)), 16, 6)
	for sx in [-1.0, 1.0]:
		kit.bevel_box("metal", Vector3(sx * 0.17, 0.19, 0.134), Vector3(0.05, 0.06, 0.02), 0.01, BRUSHED)
		kit.bevel_box("painted", Vector3(sx * 0.23, 0.012, 0), Vector3(0.05, 0.024, 0.24), 0.01, RUBBER)
	kit.bevel_box("glow", Vector3(0, 0.1, 0.132), Vector3(0.16, 0.025, 0.012), 0.006, accent.lightened(0.25))


static func _canister(kit: ArtMeshKit, accent: Color) -> void:
	var r := 0.15
	var body := Color(0.32, 0.72, 0.5).lerp(accent, 0.3)
	kit.cylinder("painted", Vector3(0, 0.04, 0), Vector3(0, 0.44, 0), r, body, 20)
	kit.sphere("painted", Vector3(0, 0.44, 0), r, body, 20, Vector3(1, 0.62, 1))
	kit.cylinder("painted", Vector3(0, 0, 0), Vector3(0, 0.05, 0), r - 0.02, GRAPHITE, 20, r)
	kit.torus("metal", Vector3(0, 0.05, 0), r - 0.02, r + 0.012, BRUSHED, Basis.IDENTITY, 24, 6)
	kit.cylinder("hazard", Vector3(0, 0.22, 0), Vector3(0, 0.29, 0), r + 0.003, Color.WHITE, 20)
	kit.cylinder("glow", Vector3(0, 0.35, 0), Vector3(0, 0.37, 0), r + 0.004, accent.lightened(0.2), 20)
	# Valve: neck, guard ring and a bright knob.
	kit.cylinder("metal", Vector3(0, 0.52, 0), Vector3(0, 0.58, 0), 0.035, BRUSHED, 10)
	kit.torus("metal", Vector3(0, 0.575, 0), 0.05, 0.068, BRUSHED, Basis.IDENTITY, 16, 6)
	kit.cylinder("painted", Vector3(0, 0.58, 0), Vector3(0, 0.615, 0), 0.03, Color(0.95, 0.3, 0.2), 10)


# --- colliders --------------------------------------------------------------------------

static func _shapes(kind: String) -> Array:
	var out := []
	match kind:
		"crate":
			out.append([_box(Vector3(0.78, 0.66, 0.78)), Transform3D(Basis.IDENTITY, Vector3(0, 0.33, 0))])
		"crate_small":
			out.append([_box(Vector3(0.56, 0.5, 0.56)), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0))])
		"barrel":
			out.append([_cylinder(0.3, 0.92), Transform3D(Basis.IDENTITY, Vector3(0, 0.46, 0))])
		"cart":
			# Body box held off the floor; four frictionless-ish wheel spheres roll.
			out.append([_box(Vector3(1.02, 0.6, 0.6)), Transform3D(Basis.IDENTITY, Vector3(0, 0.52, 0))])
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					out.append([_sphere(0.085), Transform3D(Basis.IDENTITY, Vector3(sx * 0.43, 0.085, sz * 0.22))])
		"chair":
			out.append([_cylinder(0.27, 0.08), Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0))])
			out.append([_box(Vector3(0.08, 0.36, 0.08)), Transform3D(Basis.IDENTITY, Vector3(0, 0.26, 0))])
			out.append([_box(Vector3(0.48, 0.12, 0.46)), Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0.01))])
			out.append([_box(Vector3(0.44, 0.42, 0.09)), Transform3D(Basis.IDENTITY, Vector3(0, 0.8, -0.215))])
		"toolbox":
			out.append([_box(Vector3(0.51, 0.25, 0.27)), Transform3D(Basis.IDENTITY, Vector3(0, 0.125, 0))])
		"canister":
			out.append([_cylinder(0.15, 0.52), Transform3D(Basis.IDENTITY, Vector3(0, 0.26, 0))])
			out.append([_sphere(0.15), Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0))])
	return out


## Item colliders fitted to the item visual's bounds (items are visual nodes
## owned by Props/ItemFactory; fitting at runtime follows any art change).
## `aabb` is the visual's local AABB (origin = the item's origin).
static func item_shapes(kind: String, aabb := AABB()) -> Array:
	if aabb.size.length() < 0.05:
		aabb = {"cell": AABB(Vector3(-0.17, 0, -0.17), Vector3(0.34, 0.62, 0.34)),
			"core": AABB(Vector3(-0.24, 0, -0.24), Vector3(0.48, 0.6, 0.48)),
			"gun": AABB(Vector3(-0.043, -0.052, -0.091), Vector3(0.085, 0.213, 0.406))}.get(kind, AABB(Vector3(-0.2, 0, -0.2), Vector3(0.4, 0.4, 0.4)))
	var c := aabb.get_center()
	var s := aabb.size
	match kind:
		"cell":
			var r := maxf(0.08, minf(s.x, s.z) * 0.5 - 0.005)
			return [[_cylinder(r, s.y), Transform3D(Basis.IDENTITY, c)]]
		"core":
			# A low base plus a ball for the cage: rolls a little, comes to rest upright-ish.
			var r := maxf(0.1, minf(s.x, s.z) * 0.5 - 0.01)
			var base_h := minf(0.14, s.y * 0.25)
			return [[_cylinder(r * 0.85, base_h), Transform3D(Basis.IDENTITY, Vector3(c.x, aabb.position.y + base_h * 0.5, c.z))],
				[_sphere(minf(r, (s.y - base_h * 0.5) * 0.5)), Transform3D(Basis.IDENTITY, Vector3(c.x, aabb.end.y - minf(r, (s.y - base_h * 0.5) * 0.5), c.z))]]
	return [[_box(s.max(Vector3(0.05, 0.05, 0.05))), Transform3D(Basis.IDENTITY, c)]]


const ITEM_SPECS := {
	"cell": {"mass": 8.0, "friction": 0.55, "bounce": 0.22, "radius": 0.36},
	"core": {"mass": 12.0, "friction": 0.5, "bounce": 0.18, "radius": 0.42},
	"gun": {"mass": 1.5, "friction": 0.6, "bounce": 0.25, "radius": 0.3},
}


static func _box(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


static func _cylinder(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


static func _sphere(radius: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = radius
	return s
