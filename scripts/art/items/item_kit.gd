class_name ItemKit
extends CrewMeshKit
## Geometry builder for the gameplay items and sockets. Reuses the crew suit's
## smooth, indexed primitives (rounded boxes with panel UVs, lathes, tubes, patches)
## and writes the same vertex layout:
##   COLOR   = (baked AO, edge-wear mask, panel shade, 0)
##   CUSTOM0 = (group, group, 0, material id)
## ItemMaterials' shaders pick the look per vertex from the material id, so a whole
## item is one opaque draw call (plus an optional additive "fx" mesh).
## `group` is a small per-part integer the shaders use (gun charge cell 1..3,
## alternating warning lamps, beam index ...).

# Opaque body materials (ItemMaterials.BODY shader).
const SHELL_A := 0  # glossy toy paint, colour shell_a
const SHELL_B := 1  # glossy toy paint, colour shell_b
const GRAPHITE := 2  # satin graphite composite
const METAL := 3  # brushed metal
const RUBBER := 4  # grippy rubber with lug grooves
const GLOW_A := 5  # steady emissive accent (glow_a)
const GLOW_B := 6  # steady emissive accent (glow_b)
const HAZARD := 7  # yellow / black hazard stripes
const CHARGE := 8  # power-cell energy window (animated charge bars)
const ORB := 9  # core plasma orb (animated swirl)
const AMMO := 10  # gun charge cell, lit while group <= ammo
const STATUS := 11  # socket status light (state colour, chase / pulse)
const DECAL := 12  # procedural stencil: UV 0..1, UV2 = (style, aspect)
const LED := 13  # tiny blinking status LED
const LENS := 14  # dark glossy glass (sights, dead screens, visors)
const BEACON := 15  # rotating warning beacon dome (lit while warn > 0)
const SCREEN := 16  # animated status display (rounded box face)
const BRASS := 17  # warm brushed brass (terminals, contacts)
const WARN := 18  # warning lamp: strobes while warn > 0, dim red glass otherwise

# Additive / glass fx materials (ItemMaterials.FX shader).
const FX_FIELD := 20  # forcefield shimmer (shown while locked)
const FX_HOLO := 21  # holographic projector glow and label backing
const FX_GLASS := 22  # clear glass with fresnel and streak reflections
const FX_HALO := 23  # soft fresnel glow shell (orb, muzzle)
const FX_BEAM := 24  # rotating beacon light beams (active only)
const FX_SCAN := 25  # medbay scanner sheet
const FX_SEAT := 26  # "insert here" floor / seat glow with converging rings

# Decal styles (UV2.x on DECAL patches).
const DECAL_BOLT := 0.0  # hazard triangle with a lightning bolt
const DECAL_TEXT := 1.0  # stencilled serial text dashes
const DECAL_CHEVRON := 2.0  # glowing chevrons pointing down into the seat
const DECAL_CROSS := 3.0  # glowing medical cross
const DECAL_DIGIT := 4.0  # glowing seven-segment digit (decal_number)
const DECAL_TREFOIL := 5.0  # "high energy" trefoil
const DECAL_BARCODE := 6.0  # barcode / tick strip


func part(p_mat: int, p_shade := 1.0, group := 0) -> void:
	set_part(group, p_mat, p_shade)


## Flat decal patch, UV 0..1 (`right` = +U, `up` = +V); optional surface projection.
func decal(center: Vector3, right: Vector3, up: Vector3, size: Vector2, style: float, surface := Callable(), cols := 1, rows := 1) -> void:
	var r := right.normalized()
	var u := up.normalized()
	var normal := r.cross(u).normalized()
	patch(func(pu: float, pv: float) -> Vector3:
			var p := center + r * (pu - 0.5) * size.x + u * (pv - 0.5) * size.y
			return surface.call(p) if surface.is_valid() else p,
		cols, rows, center - normal * 0.2, Vector2.ONE, Callable(), Vector2(style, size.x / size.y))


## Decal wrapped onto a vertical cylinder of radius `radius` (axis through `axis`),
## centred at angle `theta` (0 = +Z, PI/2 = +X) and height `y`.
func cyl_decal(axis: Vector3, radius: float, theta: float, y: float, size: Vector2, style: float, cols := 4) -> void:
	var half := size.x * 0.5 / radius
	patch(func(pu: float, pv: float) -> Vector3:
			var a := theta + lerpf(-half, half, pu)
			return axis + Vector3(sin(a) * radius, y + (pv - 0.5) * size.y, cos(a) * radius),
		cols, 1, axis + Vector3(0, y, 0), Vector2.ONE, Callable(), Vector2(style, size.x / size.y))


## Curved plate wrapped around a vertical axis (`theta` 0 = +Z, PI/2 = +X); size.x is
## the arc length, size.z the thickness. Panel lines come from the rounded-box UVs.
func plate(axis: Vector3, radius: float, theta: float, size: Vector3, corner: float, segs := Vector3i(3, 1, 1)) -> void:
	var dir := Vector3(sin(theta), 0.0, cos(theta))
	deform = CrewMeshKit.shell(radius + size.z * 0.5, 0.0, 1.0, size.y * 0.5)
	skip_back = true
	rounded_box(axis + dir * (radius + size.z * 0.5), size, corner, Basis(Vector3.UP, theta), 1, segs)
	deform = Callable()
	skip_back = false


## Thin band hugging a vertical cylinder.
func band(center: Vector3, r: float, height: float, segments: int) -> void:
	lathe(PackedVector2Array([Vector2(r, -height * 0.5), Vector2(r, height * 0.5)]), Transform3D(Basis.IDENTITY, center), segments)


## Flat ring (annulus) facing `normal`.
func annulus(center: Vector3, normal: Vector3, r_in: float, r_out: float, segments: int) -> void:
	lathe(PackedVector2Array([Vector2(r_out, 0.0), Vector2(r_in, 0.0)]), Transform3D(basis_y(normal), center), segments)


## Bevelled ring band (a short tube with rounded lips) around local Y.
func collar(center: Vector3, r_in: float, r_out: float, height: float, segments: int, basis := Basis.IDENTITY) -> void:
	var h := height * 0.5
	var b := minf((r_out - r_in) * 0.45, h * 0.6)
	var prof := PackedVector2Array([
		Vector2(r_in, -h), Vector2(r_out - b, -h), Vector2(r_out, -h + b), Vector2(r_out, h - b),
		Vector2(r_out - b, h), Vector2(r_in, h)])
	lathe(prof, Transform3D(basis, center), segments, Vector2.ONE, 0.0, TAU, PackedFloat32Array([0, 0.5, 1, 1, 0.5, 0]))


## Basis whose +Y is `dir` (any roll).
static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


## Bakes into an ArrayMesh (one surface) with `material` as its surface material.
func to_mesh(material: Material = null) -> ArrayMesh:
	var m := commit()
	if material != null and m.get_surface_count() > 0:
		m.surface_set_material(0, material)
	return m


## MeshInstance3D for the baked kit. `material` goes in material_override so cached
## meshes can be shared while each instance keeps its own state uniforms.
func to_instance(material: Material, node_name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## MeshInstance3D for an fx mesh: no shadows, skipped by the interact outline.
static func fx_instance(mesh: Mesh, material: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.set_meta("vfx_skip", true)
	return mi


static func mesh_instance(mesh: Mesh, material: Material, node_name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Triangles and surfaces of every visible MeshInstance3D under `node` (budget checks).
static func count(node: Node) -> Vector2i:
	var tris := 0
	var surfaces := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m := (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				surfaces += 1
				var arrays := m.surface_get_arrays(s)
				var idx = arrays[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
					tris += (idx as PackedInt32Array).size() / 3
				else:
					tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		for c in n.get_children():
			stack.append(c)
	return Vector2i(tris, surfaces)
