extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var collisions := {}
	for name in ["cottage", "palm", "coastal_rocks", "jetty", "grass_tuft", "bench", "island_terrain", "explorer"]:
		var packed = load("res://assets/models/%s.glb" % name)
		assert(packed is PackedScene, "Resource must import: " + name)
		var instance: Node3D = packed.instantiate()
		root.add_child(instance)
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		assert(not meshes.is_empty(), "Resource must contain actual meshes")
		var shapes := instance.find_children("*", "CollisionShape3D", true, false)
		collisions[name] = shapes.size()
		if name in ["cottage", "palm", "jetty", "bench", "island_terrain"]:
			assert(not shapes.is_empty(), "Solid resource must have imported collision: " + name)
		if name == "explorer":
			assert(instance.find_child("LeftLeg", true, false) != null)
			assert(instance.find_child("RightArm", true, false) != null)
		instance.queue_free()
	print("PASS: all eight GLBs import with meshes, required collision and character pivots: ", collisions)
	quit()
