class_name ArtMeshKit
extends RefCounted
## Accumulates triangles per material key and bakes them into one ArrayMesh with
## one surface per key, so a whole room is a handful of draw calls.

var _surfaces: Dictionary = {}  # key -> {"v": PackedVector3Array, "n": ..., "c": PackedColorArray, "uv": PackedVector2Array}
var xform := Transform3D.IDENTITY  # applied to everything added (local -> kit space)

const _FACES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]


func _surface(key: String) -> Dictionary:
	if not _surfaces.has(key):
		_surfaces[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array()}
	return _surfaces[key]


func has_key(key: String) -> bool:
	return _surfaces.has(key)


func vertex_count() -> int:
	var total := 0
	for key in _surfaces:
		total += (_surfaces[key]["v"] as PackedVector3Array).size()
	return total


func _push(s: Dictionary, p: Vector3, n: Vector3, c: Color, uv: Vector2) -> void:
	(s["v"] as PackedVector3Array).append(xform * p)
	(s["n"] as PackedVector3Array).append((xform.basis * n).normalized())
	(s["c"] as PackedColorArray).append(c)
	(s["uv"] as PackedVector2Array).append(uv)


## Triangle with automatic winding so that it faces along `n` (Godot: clockwise front).
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
	var s := _surface(key)
	if (b - a).cross(c - a).dot(n) > 0.0:
		_push(s, a, n, color, uva)
		_push(s, c, n, color, uvc)
		_push(s, b, n, color, uvb)
	else:
		_push(s, a, n, color, uva)
		_push(s, b, n, color, uvb)
		_push(s, c, n, color, uvc)


func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color) -> void:
	tri(key, a, b, c, n, color, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	tri(key, a, c, d, n, color, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))


## Axis-aligned (optionally rotated by `basis`) box. `color_b` blends along local X.
func box(key: String, center: Vector3, size: Vector3, color: Color, basis := Basis.IDENTITY, color_b = null, grad_axis := 0) -> void:
	var s := _surface(key)
	var h := size * 0.5
	var grad := color_b is Color
	for face in _FACES:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var hn := absf(n.dot(h))
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var corners := [
			[n * hn - u * hu + v * hv, Vector2(0, 0)],
			[n * hn + u * hu + v * hv, Vector2(1, 0)],
			[n * hn + u * hu - v * hv, Vector2(1, 1)],
			[n * hn - u * hu - v * hv, Vector2(0, 1)],
		]
		var wn := basis * n
		for idx in [0, 1, 2, 0, 2, 3]:
			var local: Vector3 = corners[idx][0]
			var col := color
			if grad:
				col = color.lerp(color_b, clampf(local[grad_axis] / maxf(size[grad_axis], 0.001) + 0.5, 0.0, 1.0))
			_push(s, center + basis * local, wn, col, corners[idx][1])


## Box from min/max corners (axis aligned).
func box_mm(key: String, lo: Vector3, hi: Vector3, color: Color, color_b = null, grad_axis := 0) -> void:
	box(key, (lo + hi) * 0.5, hi - lo, color, Basis.IDENTITY, color_b, grad_axis)


## Chamfered box (bevelled edges): 6 faces, 12 edge strips, 8 corner triangles.
func bevel_box(key: String, center: Vector3, size: Vector3, bevel: float, color: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var c := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var ih := h - Vector3(c, c, c)
	var signs := [-1.0, 1.0]
	# Main faces.
	for axis in range(3):
		for sg in signs:
			var n := Vector3.ZERO
			n[axis] = sg
			var a1 := (axis + 1) % 3
			var a2 := (axis + 2) % 3
			var pts: Array[Vector3] = []
			for p in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var q := Vector3.ZERO
				q[axis] = sg * h[axis]
				q[a1] = float(p[0]) * ih[a1]
				q[a2] = float(p[1]) * ih[a2]
				pts.append(center + basis * q)
			var wn := basis * n
			tri(key, pts[0], pts[1], pts[2], wn, color)
			tri(key, pts[0], pts[2], pts[3], wn, color)
	# Edge strips between two faces.
	for axis in range(3):
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1 in signs:
			for s2 in signs:
				var n := Vector3.ZERO
				n[a1] = s1
				n[a2] = s2
				var pts: Array[Vector3] = []
				for along in [-1.0, 1.0]:
					var p1 := Vector3.ZERO
					p1[axis] = along * ih[axis]
					p1[a1] = s1 * h[a1]
					p1[a2] = s2 * ih[a2]
					var p2 := Vector3.ZERO
					p2[axis] = along * ih[axis]
					p2[a1] = s1 * ih[a1]
					p2[a2] = s2 * h[a2]
					pts.append(center + basis * p1)
					pts.append(center + basis * p2)
				var wn := (basis * n.normalized())
				tri(key, pts[0], pts[1], pts[3], wn, color)
				tri(key, pts[0], pts[3], pts[2], wn, color)
	# Corner triangles.
	for sx in signs:
		for sy in signs:
			for sz in signs:
				var a := Vector3(sx * h.x, sy * ih.y, sz * ih.z)
				var b := Vector3(sx * ih.x, sy * h.y, sz * ih.z)
				var d := Vector3(sx * ih.x, sy * ih.y, sz * h.z)
				tri(key, center + basis * a, center + basis * b, center + basis * d, basis * Vector3(sx, sy, sz).normalized(), color)


## Appends a primitive/array mesh (surface 0) transformed by `t`.
func mesh(key: String, m: Mesh, t: Transform3D, color: Color) -> void:
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var nbasis := t.basis.inverse().transposed()
	var flip := t.basis.determinant() < 0.0
	var s := _surface(key)
	var order: PackedInt32Array
	if indices is PackedInt32Array and (indices as PackedInt32Array).size() > 0:
		order = indices
	else:
		order = PackedInt32Array(range(verts.size()))
	var has_uv := uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == verts.size()
	var i := 0
	while i + 2 < order.size():
		var tri_idx := [order[i], order[i + 1], order[i + 2]]
		if flip:
			tri_idx = [order[i], order[i + 2], order[i + 1]]
		for k in tri_idx:
			var uv: Vector2 = (uvs as PackedVector2Array)[k] if has_uv else Vector2.ZERO
			_push(s, t * verts[k], (nbasis * normals[k]).normalized(), color, uv)
		i += 3


func cylinder(key: String, a: Vector3, b: Vector3, radius: float, color: Color, segments := 12, top_radius := -1.0) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.0001:
		return
	var cyl := CylinderMesh.new()
	cyl.radial_segments = segments
	cyl.rings = 1
	cyl.bottom_radius = radius
	cyl.top_radius = radius if top_radius < 0.0 else top_radius
	cyl.height = length
	var y := axis / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mesh(key, cyl, Transform3D(Basis(x, y, z), (a + b) * 0.5), color)


func sphere(key: String, center: Vector3, radius: float, color: Color, segments := 12, scale := Vector3.ONE) -> void:
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = segments
	sph.rings = maxi(segments / 2, 4)
	mesh(key, sph, Transform3D(Basis.from_scale(scale), center), color)


func torus(key: String, center: Vector3, inner: float, outer: float, color: Color, basis := Basis.IDENTITY, rings := 24, ring_segments := 8) -> void:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = ring_segments
	mesh(key, t, Transform3D(basis, center), color)


## Bakes into an ArrayMesh; `materials` maps key -> Material. Keys without a
## material are skipped.
func build(materials: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	var keys := _surfaces.keys()
	keys.sort()
	for key in keys:
		var s: Dictionary = _surfaces[key]
		if (s["v"] as PackedVector3Array).is_empty() or not materials.has(key):
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s["v"]
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		arrays[Mesh.ARRAY_COLOR] = s["c"]
		arrays[Mesh.ARRAY_TEX_UV] = s["uv"]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(am.get_surface_count() - 1, materials[key])
	return am


func to_instance(materials: Dictionary, node_name := "Mesh", shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = build(materials)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
