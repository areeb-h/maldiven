class_name CrewMeshKit
extends RefCounted
## Procedural geometry builder for the crew suit.
##
## Every primitive is emitted as an indexed, smooth-shaded patch with:
##   COLOR   = (baked AO, edge-wear mask, panel shade, 1)
##   CUSTOM0 = (bone A, bone B, weight of B, material id)   [RGBA float]
## The crew shader skins each vertex between two rig bones on the GPU, so a
## whole character is one draw call while soft suit parts still bend smoothly.

const QUANT := 20000.0

var positions := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()  # box faces: panel half extents (m); decals: (style, aspect)
var colors := PackedColorArray()
var customs := PackedColorArray()
var indices := PackedInt32Array()
var occluders: Array[Vector4] = []  # xyz centre, w radius

# Current drawing state.
var bone := 0
var mat := 0
var shade := 1.0
var blend_bone := -1
var blend_origin := Vector3.ZERO
var blend_axis := Vector3.UP
var blend_width := 0.05
var deform := Callable()
## Skip the local -Z face of the next boxes (plates sitting flush on the body).
var skip_back := false
## Softens every rounded_box bevel (capped by the box's half thickness).
var bevel_scale := 1.0
## Rounds the outline corners of boxes (in the plane of their two largest axes) with
## a consistent radius, so plates read as rounded rectangles rather than slabs.
var round_outline := false

# Primitive scratch.
var _tp := PackedVector3Array()
var _th := PackedVector3Array()
var _tu := PackedVector2Array()
var _t2 := PackedVector2Array()
var _te := PackedFloat32Array()
var _ti := PackedInt32Array()


func set_part(p_bone: int, p_mat: int, p_shade := 1.0) -> void:
	bone = p_bone
	mat = p_mat
	shade = p_shade
	blend_bone = -1
	deform = Callable()
	skip_back = false


## Vertices past `origin` along `axis` blend toward bone `other` over +-width.
func set_blend(other: int, origin: Vector3, axis: Vector3, width: float) -> void:
	blend_bone = other
	blend_origin = origin
	blend_axis = axis.normalized()
	blend_width = width


func clear_blend() -> void:
	blend_bone = -1


func add_occluder(center: Vector3, radius: float) -> void:
	occluders.append(Vector4(center.x, center.y, center.z, radius))


func triangle_count() -> int:
	return indices.size() / 3


# --- deformers (local-space Callables) ---------------------------------------------

## Armour-plate shaping: taper X toward the bottom, wrap around a vertical cylinder
## (radius `wrap_r`, z = outward thickness) and curve around X (radius `curve_r`).
static func shell(wrap_r: float, curve_r := 0.0, taper_bottom := 1.0, half_h := 0.1, taper_top := 1.0) -> Callable:
	return func(p: Vector3) -> Vector3:
		var t := clampf((p.y + half_h) / (2.0 * half_h), 0.0, 1.0)
		var q := Vector3(p.x * lerpf(taper_bottom, taper_top, t), p.y, p.z)
		if wrap_r > 0.0:
			var a := q.x / wrap_r
			var rr := wrap_r + q.z
			q = Vector3(sin(a) * rr, q.y, cos(a) * rr - wrap_r)
		if curve_r > 0.0:
			var b := q.y / curve_r
			var rr2 := curve_r + q.z
			q = Vector3(q.x, sin(b) * rr2, cos(b) * rr2 - curve_r)
		return q


## Bend a part whose length runs along Z over a circle in the YZ plane (crests).
static func arc_z(radius: float) -> Callable:
	return func(p: Vector3) -> Vector3:
		var a := p.z / radius
		var rr := radius + p.y
		return Vector3(p.x, cos(a) * rr - radius, sin(a) * rr)


## Basis that shears local Z by local Y (z' = z - k * y): sweeps a part backward with height.
static func shear_basis(k: float) -> Basis:
	return Basis(Vector3(1, 0, 0), Vector3(0, 1, -k), Vector3(0, 0, 1))


static func taper(bottom: float, top: float, half_h: float, bottom_z := -1.0, top_z := -1.0) -> Callable:
	var bz := bottom if bottom_z < 0.0 else bottom_z
	var tz := top if top_z < 0.0 else top_z
	return func(p: Vector3) -> Vector3:
		var t := clampf((p.y + half_h) / (2.0 * half_h), 0.0, 1.0)
		return Vector3(p.x * lerpf(bottom, top, t), p.y, p.z * lerpf(bz, tz, t))


# --- primitives ---------------------------------------------------------------------

## Box with rounded edges (Minkowski box + sphere), smooth normals, planar UVs (metres).
func rounded_box(center: Vector3, size: Vector3, radius: float, basis := Basis.IDENTITY, arc := 2, segs := Vector3i(1, 1, 1)) -> void:
	var h := size * 0.5
	var r := radius
	if r >= 0.0035:
		r *= bevel_scale
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.98)
	var hi := h - Vector3(r, r, r)
	if r < 0.0035:
		r = 0.0  # tiny trim strips: a plain box
		hi = h
	elif r < 0.024:
		arc = mini(arc, 1)  # small bevels: two segments per 90 degrees is plenty
	var samples: Array[PackedFloat32Array] = []
	for axis in 3:
		samples.append(_box_samples(h[axis], hi[axis], r, arc, segs[axis]))
	# Outline rounding happens in the plane of the two largest axes.
	var thin := 0 if h.x <= h.y and h.x <= h.z else (1 if h.y <= h.z else 2)
	var oa := (thin + 1) % 3
	var ob := (thin + 2) % 3
	var outline_r := 0.0
	if round_outline and r > 0.0:
		outline_r = minf(maxf(outline_radius(h[oa], h[ob]), r), minf(h[oa], h[ob]) * 0.95)
	_begin()
	var faces := [[0, 1, 2], [1, 2, 0], [2, 0, 1]]
	for f in faces:
		var n_axis: int = f[0]
		var u_axis: int = f[1]
		var v_axis: int = f[2]
		for side in [-1.0, 1.0]:
			if skip_back and n_axis == 2 and side < 0.0:
				continue
			var su := samples[u_axis]
			var sv := samples[v_axis]
			var base := _tp.size()
			for j in sv.size():
				for i in su.size():
					var pp := Vector3.ZERO
					pp[n_axis] = h[n_axis] * side
					pp[u_axis] = su[i]
					pp[v_axis] = sv[j]
					var inner := pp.clamp(-hi, hi)
					var d := pp - inner
					var n := Vector3.ZERO
					n[n_axis] = side
					var p := pp
					if r > 0.0 and d.length_squared() > 1e-12:
						n = d.normalized()
						p = inner + n * r
					var edge := clampf((1.0 - maxf(absf(n.x), maxf(absf(n.y), absf(n.z)))) / 0.25, 0.0, 1.0)
					if outline_r > 0.0:
						p = _round_corner(p, h, oa, ob, outline_r)
					_push(p, n, Vector2(pp[u_axis], pp[v_axis]), edge, Vector2(h[u_axis], h[v_axis]) if r > 0.0 else Vector2.ZERO)
			_quads(base, su.size() - 1, sv.size() - 1)
	_end(Transform3D(basis, center))


## Outline corner radius used for a plate of half extents (a, b); the shader's panel
## line uses the same rule so it stays concentric with the plate edge.
static func outline_radius(a: float, b: float) -> float:
	return clampf(minf(a, b) * 0.4, 0.008, 0.035)


## Maps the square corner zones of the (a, b) plane onto quarter discs of radius rc.
static func _round_corner(p: Vector3, h: Vector3, a: int, b: int, rc: float) -> Vector3:
	var ca := h[a] - rc
	var cb := h[b] - rc
	var da := absf(p[a]) - ca
	var db := absf(p[b]) - cb
	if da <= 0.0 or db <= 0.0:
		return p
	var f := maxf(da, db) / sqrt(da * da + db * db)
	var q := p
	q[a] = signf(p[a]) * (ca + da * f)
	q[b] = signf(p[b]) * (cb + db * f)
	return q


func _box_samples(h: float, hi: float, r: float, arc: int, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if r <= 0.0:
		arc = 0
	var steps := maxi(arc, 1) if r > 0.0 else 0
	# Bevel band from -h (45 deg) to -hi (0 deg), then interior, then mirrored.
	for k in range(steps, -1, -1):
		if r <= 0.0:
			break
		var ang := deg_to_rad(45.0) * float(k) / float(steps)
		out.append(-(hi + r * tan(ang)))
	if r <= 0.0:
		out.append(-h)
	for j in range(1, seg):
		out.append(-hi + 2.0 * hi * float(j) / float(seg))
	for k in range(0, steps + 1):
		if r <= 0.0:
			break
		var ang2 := deg_to_rad(45.0) * float(k) / float(steps)
		out.append(hi + r * tan(ang2))
	if r <= 0.0:
		out.append(h)
	return out


## Surface of revolution around local Y. Profile points are (radius, y), bottom to top.
## Angle 0 faces +Z, increasing toward +X.
func lathe(profile: PackedVector2Array, xf: Transform3D, segments: int, scale_xz := Vector2.ONE, a0 := 0.0, a1 := TAU, edge_mask := PackedFloat32Array(), outward := true) -> void:
	_begin()
	var full := is_equal_approx(a1 - a0, TAU)
	var cols := segments
	var plen := 0.0
	var vlen := PackedFloat32Array()
	for k in profile.size():
		if k > 0:
			plen += profile[k].distance_to(profile[k - 1])
		vlen.append(plen)
	var rmax := 0.0
	for pt in profile:
		rmax = maxf(rmax, pt.x)
	var base := _tp.size()
	for k in profile.size():
		var prev := profile[maxi(k - 1, 0)]
		var nxt := profile[mini(k + 1, profile.size() - 1)]
		var t := nxt - prev
		var n2 := Vector2(t.y, -t.x).normalized()
		if not outward:
			n2 = -n2
		for i in cols + 1:
			var a := lerpf(a0, a1, float(i) / float(cols))
			var s := sin(a)
			var c := cos(a)
			var p := Vector3(s * profile[k].x * scale_xz.x, profile[k].y, c * profile[k].x * scale_xz.y)
			var n := Vector3(s * n2.x / scale_xz.x, n2.y, c * n2.x / scale_xz.y).normalized()
			var e := edge_mask[k] if k < edge_mask.size() else 0.0
			_push(p, n, Vector2((a - a0) * rmax, vlen[k]), e)
	_quads(base, cols, profile.size() - 1)
	if full:
		pass  # seam vertices share positions; normals are welded in _end
	_end(xf)


## Tapered capsule from a to b. Radii ra / rb.
func capsule(a: Vector3, b: Vector3, ra: float, rb: float, segments := 12, cap_rings := 3, body_rings := 2, scale_xz := Vector2.ONE, roll := 0.0) -> void:
	var length := a.distance_to(b)
	var prof := PackedVector2Array()
	for k in range(cap_rings + 1):
		var th := -PI * 0.5 + PI * 0.5 * float(k) / float(cap_rings)
		prof.append(Vector2(ra * cos(th), ra * sin(th)))
	for k in range(1, body_rings):
		var t := float(k) / float(body_rings)
		prof.append(Vector2(lerpf(ra, rb, t), length * t))
	for k in range(cap_rings + 1):
		var th2 := PI * 0.5 * float(k) / float(cap_rings)
		prof.append(Vector2(rb * cos(th2), length + rb * sin(th2)))
	lathe(prof, Transform3D(_basis_y(b - a, roll), a), segments, scale_xz)


func ellipsoid(center: Vector3, radii: Vector3, basis := Basis.IDENTITY, segments := 16, rings := 8) -> void:
	var prof := PackedVector2Array()
	for k in rings + 1:
		var th := -PI * 0.5 + PI * float(k) / float(rings)
		prof.append(Vector2(cos(th), sin(th) * radii.y))
	lathe(prof, Transform3D(basis, center), segments, Vector2(radii.x, radii.z))


## Closed cylinder (with rounded rims) between a and b.
func cylinder(a: Vector3, b: Vector3, radius: float, segments := 12, bevel := 0.004, roll := 0.0) -> void:
	var length := a.distance_to(b)
	var bv := minf(bevel, minf(radius * 0.4, length * 0.3))
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(radius - bv, 0.0), Vector2(radius, bv),
		Vector2(radius, length - bv), Vector2(radius - bv, length), Vector2(0.0, length)])
	var em := PackedFloat32Array([0, 0.4, 0.8, 0.8, 0.4, 0])
	lathe(prof, Transform3D(_basis_y(b - a, roll), a), segments, Vector2.ONE, 0.0, TAU, em)


## Flat or slightly domed disc facing `normal` (lenses, lights, caps).
func disc(center: Vector3, normal: Vector3, radius: float, segments := 12, dome := 0.0) -> void:
	var prof := PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * 0.7, dome * 0.6), Vector2(0.0, dome)])
	lathe(prof, Transform3D(_basis_y(normal), center), segments)


## Torus ring around local Y at `center` (major radius R, minor r).
func ring(center: Vector3, major: float, minor: float, basis := Basis.IDENTITY, segments := 20, sides := 6, scale_xz := Vector2.ONE) -> void:
	var prof := PackedVector2Array()
	for k in sides + 1:
		var th := -PI * 0.5 + TAU * float(k) / float(sides)
		prof.append(Vector2(major + cos(th) * minor, sin(th) * minor))
	# Profile goes around the tube: first half bottom->outer->top is outward-facing order.
	lathe(prof, Transform3D(basis, center), segments, scale_xz, 0.0, TAU, PackedFloat32Array(), true)


## Swept tube along a Catmull-Rom path through `points`. Optional ribs (hoses).
## radius_fn(t) (t = 0..1 along the path) scales the radius when given (tapered ends).
func tube(points: PackedVector3Array, radius: float, sides := 8, samples := 16, rib_freq := 0.0, rib_depth := 0.0, closed := false, radius_fn := Callable()) -> void:
	var path := PackedVector3Array()
	var ctrl := points
	if closed:
		# Pad with wrapped neighbours so the loop has continuous tangents at the join.
		ctrl = PackedVector3Array([points[points.size() - 2]]) + points + PackedVector3Array([points[1]])
	var segs := ctrl.size() - 1
	for s in samples + 1:
		var t := float(s) / float(samples)
		if closed:
			t = (1.0 + t * float(segs - 2)) / float(segs)
		path.append(_catmull(ctrl, t))
	_begin()
	var base := _tp.size()
	var along := 0.0
	var up := Vector3.UP
	var tan0 := (path[1] - path[0]).normalized()
	if absf(tan0.dot(up)) > 0.9:
		up = Vector3.RIGHT
	var nrm := tan0.cross(up).normalized()
	for s in path.size():
		var t := (path[mini(s + 1, path.size() - 1)] - path[maxi(s - 1, 0)]).normalized()
		nrm = (nrm - t * nrm.dot(t)).normalized()  # parallel transport
		var bin := t.cross(nrm).normalized()
		if s > 0:
			along += path[s].distance_to(path[s - 1])
		var rr := radius
		if radius_fn.is_valid():
			rr *= float(radius_fn.call(float(s) / float(path.size() - 1)))
		if rib_freq > 0.0:
			rr = radius * (1.0 - rib_depth * (0.5 + 0.5 * cos(along * rib_freq * TAU)))
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var dir := nrm * cos(a) + bin * sin(a)
			_push(path[s] + dir * rr, dir, Vector2(a * radius, along), 0.0)
	_quads(base, sides, path.size() - 1)
	_end(Transform3D.IDENTITY)


## Generic parametric patch: fn(u, v) -> Vector3 over [0,1]^2; hints point away from `inside`.
## uv2_param = true stores the (u, v) patch parameters in UV2 instead of the constant uv2.
func patch(fn: Callable, cols: int, rows: int, inside: Vector3, uv_scale := Vector2.ONE, uv_fn := Callable(), uv2 := Vector2.ZERO, uv2_param := false) -> void:
	_begin()
	var base := _tp.size()
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / float(cols)
			var v := float(j) / float(rows)
			var p: Vector3 = fn.call(u, v)
			var uv := Vector2(u * uv_scale.x, v * uv_scale.y)
			if uv_fn.is_valid():
				uv = uv_fn.call(u, v)
			_push(p, (p - inside).normalized(), uv, 0.0, Vector2(u, v) if uv2_param else uv2)
	_quads(base, cols, rows)
	_end(Transform3D.IDENTITY)


# --- internals ----------------------------------------------------------------------

func _begin() -> void:
	_tp.clear()
	_th.clear()
	_tu.clear()
	_t2.clear()
	_te.clear()
	_ti.clear()


func _push(p: Vector3, hint: Vector3, uv: Vector2, edge: float, uv2 := Vector2.ZERO) -> void:
	_tp.append(p)
	_th.append(hint)
	_tu.append(uv)
	_t2.append(uv2)
	_te.append(edge)


func _quads(base: int, cols: int, rows: int) -> void:
	var stride := cols + 1
	for j in rows:
		for i in cols:
			var a := base + j * stride + i
			var b := a + 1
			var c := a + stride + 1
			var d := a + stride
			_ti.append_array(PackedInt32Array([a, b, c, a, c, d]))


func _end(xf: Transform3D) -> void:
	var n := _tp.size()
	var world := PackedVector3Array()
	world.resize(n)
	var hints := PackedVector3Array()
	hints.resize(n)
	for i in n:
		var p := _tp[i]
		if deform.is_valid():
			# Deformed hint: finite difference along the hint direction.
			var q: Vector3 = deform.call(p)
			var q2: Vector3 = deform.call(p + _th[i] * 0.001)
			hints[i] = xf.basis * (q2 - q)
			p = q
		else:
			hints[i] = xf.basis * _th[i]
		world[i] = xf * p
	var acc := PackedVector3Array()
	acc.resize(n)
	var tris := PackedInt32Array()
	for t in range(0, _ti.size(), 3):
		var a := _ti[t]
		var b := _ti[t + 1]
		var c := _ti[t + 2]
		var fn := (world[c] - world[a]).cross(world[b] - world[a])
		if fn.length_squared() < 1e-16:
			continue
		if fn.dot(hints[a] + hints[b] + hints[c]) < 0.0:
			var tmp := b
			b = c
			c = tmp
			fn = -fn
		tris.append_array(PackedInt32Array([a, b, c]))
		acc[a] += fn
		acc[b] += fn
		acc[c] += fn
	# Weld normals across coincident vertices (UV seams, box faces, poles).
	var groups := {}
	var keys: Array[Vector3i] = []
	keys.resize(n)
	for i in n:
		var key := Vector3i(roundi(world[i].x * QUANT), roundi(world[i].y * QUANT), roundi(world[i].z * QUANT))
		keys[i] = key
		groups[key] = groups.get(key, Vector3.ZERO) + acc[i]
	var offset := positions.size()
	for i in n:
		var nn: Vector3 = groups[keys[i]]
		if nn.length_squared() < 1e-20:
			nn = hints[i]
		nn = nn.normalized()
		positions.append(world[i])
		normals.append(nn)
		uvs.append(_tu[i])
		uv2s.append(_t2[i])
		colors.append(Color(1.0, _te[i], shade, 0.0))
		var w := 0.0
		var other := bone
		if blend_bone >= 0:
			w = smoothstep(-blend_width, blend_width, (world[i] - blend_origin).dot(blend_axis))
			other = blend_bone
		customs.append(Color(float(bone), float(other), w, float(mat)))
	for t in tris:
		indices.append(t + offset)


func _basis_y(dir: Vector3, roll := 0.0) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var b := Basis(x, y, -z)
	if absf(b.determinant() - 1.0) > 0.01:
		b = Basis(x, y, z)
	if roll != 0.0:
		b = b * Basis(Vector3.UP, roll)
	return b


static func _catmull(pts: PackedVector3Array, t: float) -> Vector3:
	var segs := pts.size() - 1
	var f := clampf(t, 0.0, 1.0) * segs
	var i := mini(int(f), segs - 1)
	var u := f - i
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, segs)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


# --- baking -------------------------------------------------------------------------

## Analytic sphere occlusion from the registered volumes, stored in COLOR.r.
func bake_ao(strength := 0.85) -> void:
	for i in positions.size():
		var p := positions[i]
		var nn := normals[i]
		var occ := 0.0
		for o in occluders:
			var d := Vector3(o.x, o.y, o.z) - p
			var dist2 := d.length_squared()
			var r2 := o.w * o.w
			if dist2 <= r2 * 1.02:
				continue
			var dist := sqrt(dist2)
			var cosv := nn.dot(d / dist)
			if cosv <= 0.0:
				continue
			occ += cosv * r2 / dist2
		var c := colors[i]
		c.r = clampf(1.0 - occ * strength, 0.28, 1.0)
		colors[i] = c


## Soft fold creases on the undersuit near the given joints, stored in COLOR.a.
func bake_creases(joints: Array[Vector3], radius: float, fabric_mat: int) -> void:
	for i in positions.size():
		if int(customs[i].a + 0.5) != fabric_mat:
			continue
		var m := 0.0
		for j in joints:
			m = maxf(m, 1.0 - smoothstep(radius * 0.35, radius, positions[i].distance_to(j)))
		var c := colors[i]
		c.a = m
		colors[i] = c


func commit() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for i in positions.size():
		st.set_normal(normals[i])
		st.set_uv(uvs[i])
		st.set_uv2(uv2s[i])
		st.set_color(colors[i])
		st.set_custom(0, customs[i])
		st.add_vertex(positions[i])
	for t in indices:
		st.add_index(t)
	st.generate_tangents()
	return st.commit()
