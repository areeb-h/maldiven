extends SceneTree
## Print every static collider footprint (world AABB) inside each room, ignoring floors/walls.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	StationBuilder.build(w)
	for s in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[s]
		var node: Node3D = Props.make_socket(spec.kind)
		node.position = StationLayout.to_world(spec.pos)
		node.rotation.y = spec.facing
		w.add_child(node)
	var out := {}
	for cs in _all(w):
		var shape: Shape3D = cs.shape
		var aabb: AABB
		if shape is BoxShape3D:
			aabb = AABB(-shape.size * 0.5, shape.size)
		elif shape is CylinderShape3D:
			aabb = AABB(Vector3(-shape.radius, -shape.height * 0.5, -shape.radius), Vector3(shape.radius * 2, shape.height, shape.radius * 2))
		else:
			continue
		var g: Transform3D = cs.global_transform
		var world_aabb := g * aabb
		if world_aabb.size.y < 0.6 and world_aabb.position.y < -0.1:
			continue  # floor slab
		if world_aabb.size.x > 4.5 or world_aabb.size.z > 4.5:
			if world_aabb.size.x < 0.6 or world_aabb.size.z < 0.6:
				continue  # walls
		var c := world_aabb.get_center()
		var room := StationLayout.room_at(c)
		if room == "":
			room = "corridor/outside"
		if not out.has(room):
			out[room] = []
		out[room].append("c=(%.2f,%.2f) size=(%.2f x %.2f) y=[%.2f..%.2f] %s" % [c.x, c.z, world_aabb.size.x, world_aabb.size.z, world_aabb.position.y, world_aabb.end.y, cs.get_parent().name])
	for room in out:
		print("== ", room)
		for line in out[room]:
			print("   ", line)
	quit()

func _all(n: Node) -> Array:
	var r := []
	if n is CollisionShape3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_all(c))
	return r
