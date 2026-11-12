extends Node3D
const Explorer = preload("res://scripts/explorer.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

func block(at: Vector3, dimensions: Vector3, color: Color, solid := true) -> Node3D:
	var root := StaticBody3D.new() if solid else Node3D.new()
	root.position = at
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	root.add_child(instance)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = dimensions
		var collision := CollisionShape3D.new()
		collision.shape = shape
		root.add_child(collision)
	add_child(root)
	return root

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("8fc6d5")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c7d9df")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_color = Color("ffe0ac")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)
	block(Vector3(0, -0.8, 0), Vector3(68, 1.6, 56), Color("e2ce98"))
	block(Vector3(0, 0.02, -5), Vector3(40, 0.05, 28), Color("8eac6b"), false)
	block(Vector3(0, -0.5, 0), Vector3(350, 0.15, 350), Color("3aabb8"), false)
	# Ramp, steps and wall deliberately exercise the controller and camera.
	var ramp := block(Vector3(15, 1, -5), Vector3(7, 0.6, 12), Color("b5aa8a"))
	ramp.rotation_degrees.x = -14
	for step in range(5):
		block(Vector3(-12, 0.15 + step * 0.3, 6 - step), Vector3(4, 0.3 + step * 0.6, 1), Color("b9b7a5"))
	block(Vector3(-8, 1.5, -8), Vector3(6, 3, 0.5), Color("dfc6a6"))
	for x in [-15.0, 0.0, 13.0]:
		block(Vector3(x, 1.6, -16), Vector3(6, 3.2, 5), Color("edddbd"))
		block(Vector3(x, 3.4, -16), Vector3(7, 0.5, 6), Color("af7860"))
		block(Vector3(x, 1, -13.45), Vector3(1.2, 2, 0.12), Color("526f70"), false)
	for z in range(6):
		block(Vector3(-24, 0.3, 20 + z * 2), Vector3(3, 0.3, 2), Color("a17c55"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	for index in range(22):
		var x := rng.randf_range(-30, 30)
		var z := rng.randf_range(-24, 20)
		if absf(x) < 6 or (z < -10 and absf(x) < 20):
			continue
		block(Vector3(x, 2, z), Vector3(0.4, 4, 0.4), Color("9b8060"))
		for leaf in range(4):
			var foliage := block(Vector3(x, 4.2, z), Vector3(4, 0.12, 0.9), Color("4b8b68"), false)
			foliage.rotation.y = leaf * PI / 2
	var player := Explorer.new()
	player.name = "Explorer"
	add_child(player)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var controls := TouchControls.new()
	controls.explorer = player
	canvas.add_child(controls)
