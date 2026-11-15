extends SceneTree
## Headless smoke test for the gameplay items and sockets (scripts/art/items/).
##   godot --headless --path . --script res://tests/items_smoke.gd
## Builds every item and socket through Props, exercises every set_state
## combination and set_ammo value, and checks orientation, origins, budgets,
## outlines (MeshInstance3D-based) and colliders. Prints "PASS: items" or FAIL.

const ITEM_TRIS := 2200  # "about 2k"
const ITEM_SURFACES := 3
const SOCKET_TRIS := 4000
const KINDS := ["vault", "reactor", "shuttle", "pod", "armory", "medbay", "airlock_console"]
const PLAYER_RADIUS := 0.38
const APPROACH := 1.2

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func fail(message: String) -> void:
	failures.append(message)
	print("FAIL: " + message)


func run() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	_check_items(world)
	await _check_sockets(world)
	if failures.is_empty():
		print("PASS: items")
		quit(0)
	else:
		print("FAIL: items (%d problems)" % failures.size())
		quit(1)


# --- items -------------------------------------------------------------------------

func _check_items(world: Node3D) -> void:
	for kind in ["cell", "core", "gun"]:
		var item: Node3D = Props.make_item(kind)
		if item == null:
			fail("make_item(%s) returned null" % kind)
			continue
		world.add_child(item)
		var meshes := item.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			fail("%s has no MeshInstance3D (outlines need them)" % kind)
		var budget := ItemKit.count(item)
		print("item %s: %d triangles, %d surfaces" % [kind, budget.x, budget.y])
		if budget.x > ITEM_TRIS:
			fail("%s has %d triangles (budget %d)" % [kind, budget.x, ITEM_TRIS])
		if budget.y > ITEM_SURFACES:
			fail("%s has %d surfaces (budget %d)" % [kind, budget.y, ITEM_SURFACES])
		var lights := item.find_children("*", "Light3D", true, false).size()
		if lights > (1 if kind == "core" else 0):
			fail("%s has %d lights" % [kind, lights])
		var box := _aabb(item)
		print("  bounds %s" % box)
		if kind == "gun":
			_check_gun(item, box)
		else:
			var centre := box.get_center()
			if absf(box.position.y) > 0.03 or absf(centre.x) > 0.05 or absf(centre.z) > 0.05:
				fail("%s origin must be its bottom centre (bounds %s)" % [kind, box])
			if box.size.y < 0.45 or box.size.y > 0.8:
				fail("%s height %.2f is off (expected ~0.6 m)" % [kind, box.size.y])
		item.queue_free()


func _check_gun(gun: Node3D, box: AABB) -> void:
	# Barrel along +Z, grip at the origin.
	if box.end.z < 0.25 or box.position.z < -0.12:
		fail("gun must point +Z with the grip at the origin (z %.3f..%.3f)" % [box.position.z, box.end.z])
	if not box.grow(0.001).has_point(Vector3.ZERO):
		fail("gun origin must lie inside the gun (grip), bounds %s" % box)
	if box.position.y > -0.03 or box.position.y < -0.08 or box.end.y < 0.12:
		fail("gun grip must hang below the origin and the body sit above it (y %.3f..%.3f)" % [box.position.y, box.end.y])
	# The lowest geometry is the grip: right under the origin, not the barrel.
	var low := Vector3.ZERO
	var count := 0
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			for v in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				if v.y < -0.025:
					low += v
					count += 1
	if count == 0:
		fail("gun has no grip below the origin")
	else:
		low /= float(count)
		if absf(low.x) > 0.01 or absf(low.z) > 0.05:
			fail("gun grip is not under the origin (lowest geometry centred at %s)" % low)
	# Grip width / depth for the crew glove (hand spec 2.6-2.8 x 4.5-5.5 cm): exact
	# cross-section of the mesh with a plane through the lower grip, in the grip's
	# own (tilted) frame, clear of the trigger guard.
	var to_grip := Transform3D(Basis(Vector3.RIGHT, GunVisual.GRIP_TILT), GunVisual.GRIP_C).affine_inverse()
	var cut := -0.02
	var grip := AABB()
	var first := true
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var m2 := (mi as MeshInstance3D).mesh
		for s in m2.get_surface_count():
			var arr := m2.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				for e in 3:
					var p0 := to_grip * verts[idx[t + e]]
					var p1 := to_grip * verts[idx[t + (e + 1) % 3]]
					if (p0.y - cut) * (p1.y - cut) >= 0.0:
						continue
					var q := p0.lerp(p1, (cut - p0.y) / (p1.y - p0.y))
					if absf(q.z) < 0.04 and absf(q.x) < 0.04:
						grip = AABB(q, Vector3.ZERO) if first else grip.expand(q)
						first = false
	print("  grip cross-section: %.3f wide x %.3f deep" % [grip.size.x, grip.size.z])
	if grip.size.x < 0.025 or grip.size.x > 0.0295 or grip.size.z < 0.044 or grip.size.z > 0.056:
		fail("gun grip %.3f x %.3f m must fit the glove (2.6-2.8 x 4.5-5.5 cm)" % [grip.size.x, grip.size.z])
	if not gun.has_method("set_ammo"):
		fail("gun needs set_ammo")
		return
	var mat := ((gun.find_children("*", "MeshInstance3D", true, false)[0]) as MeshInstance3D).material_override as ShaderMaterial
	for n in [0, 1, 2, 3, 5, -1]:
		gun.call("set_ammo", n)
		var want := clampi(n, 0, 3)
		if int(gun.get("ammo")) != want:
			fail("set_ammo(%d) left ammo at %s" % [n, gun.get("ammo")])
		if mat == null or absf(float(mat.get_shader_parameter("ammo")) - float(want)) > 0.01:
			fail("set_ammo(%d) did not reach the charge cells" % n)


## Item-space AABB of every mesh under `node`.
func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := node.global_transform.affine_inverse() * m.global_transform
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# --- sockets -----------------------------------------------------------------------

func _check_sockets(world: Node3D) -> void:
	for kind in KINDS:
		var node: Node3D = Props.make_socket(kind)
		if not (node is SocketVisual):
			fail("make_socket(%s) must return a SocketVisual" % kind)
			continue
		node.name = "Socket_%s_2" % kind if kind == "reactor" else "Socket_" + kind
		world.add_child(node)
		var budget := ItemKit.count(node)
		print("socket %s: %d triangles, %d surfaces" % [kind, budget.x, budget.y])
		if budget.x > SOCKET_TRIS:
			fail("socket %s has %d triangles (budget %d)" % [kind, budget.x, SOCKET_TRIS])
		for filled in [false, true]:
			for locked in [false, true]:
				for active in [false, true]:
					node.call("set_state", filled, locked, active)
					for i in 3:
						await process_frame
		var seat: Transform3D = node.call("get_seat_transform")
		if seat.origin.y < 0.3 or seat.origin.y > 1.5:
			fail("socket %s seat height %.2f is odd" % [kind, seat.origin.y])
		if not seat.basis.is_conformal() or absf(seat.basis.determinant() - 1.0) > 0.01:
			fail("socket %s seat basis must be a rotation" % kind)
		_check_colliders(node as SocketVisual, kind)
		var title := (node as SocketVisual).title_label
		if title == null or (node as SocketVisual).status_label == null:
			fail("socket %s needs a holographic title and status label" % kind)
		elif kind == "reactor" and title.text != "REACTOR 2":
			fail("reactor label should read REACTOR 2, reads '%s'" % title.text)
		for fx in node.find_children("Fx", "MeshInstance3D", true, false):
			if not fx.has_meta("vfx_skip"):
				fail("socket %s fx mesh must be skipped by the interact outline" % kind)
		node.call("set_state", false, kind in ["vault", "armory"], false)


func _check_colliders(s: SocketVisual, kind: String) -> void:
	var shapes := s.find_children("*", "CollisionShape3D", true, false)
	if shapes.is_empty():
		fail("socket %s has no collider" % kind)
		return
	for cs in shapes:
		var body := cs.get_parent() as StaticBody3D
		if body == null or body.collision_layer & 1 == 0:
			fail("socket %s collider must be on layer 1" % kind)
		var xf := (cs as CollisionShape3D).transform
		var shape := (cs as CollisionShape3D).shape
		var front := -INF
		if shape is BoxShape3D:
			var h: Vector3 = (shape as BoxShape3D).size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						front = maxf(front, (xf * Vector3(sx * h.x, sy * h.y, sz * h.z)).z)
		elif shape is CylinderShape3D:
			front = xf.origin.z + (shape as CylinderShape3D).radius
		else:
			fail("socket %s collider should be a box or cylinder" % kind)
			continue
		if front > APPROACH - PLAYER_RADIUS:
			fail("socket %s collider reaches z %.2f and blocks the approach point" % [kind, front])
