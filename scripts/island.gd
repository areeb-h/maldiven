extends Node3D
## Resource-driven island. Geometry, materials and static collision live in GLBs.
const Explorer = preload("res://scripts/explorer.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")

func place(asset_name: String, at: Vector3, yaw := 0.0, uniform_scale := 1.0) -> Node3D:
	var packed: PackedScene = load("res://assets/models/%s.glb" % asset_name)
	var instance: Node3D = packed.instantiate()
	instance.position = at
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * uniform_scale
	add_child(instance)
	return instance

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("a8cfd6")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dae5e4")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color("ffe4b8")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50
	sun.shadow_bias = 0.04
	add_child(sun)
	place("island_terrain", Vector3.ZERO)
	# Keep the sea separate from the collision-bearing ground; no coplanar plates.
	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(250, 250)
	ocean.mesh = plane
	ocean.position.y = -0.42
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("68b9ba")
	water.roughness = 0.4
	ocean.material_override = water
	add_child(ocean)
	for at in [Vector3(-7, 0.42, -1), Vector3(6, 0.42, -3), Vector3(-8, 0.42, -10)]:
		place("cottage", at)
	var palms := [Vector3(-14, 0.42, 9), Vector3(10, 0.42, 9), Vector3(-18, 0.42, -6), Vector3(16, 0.6, -10), Vector3(5, 0.42, -15), Vector3(-20, 0.42, 1), Vector3(-9, 0.42, 15), Vector3(15, 0.42, 3)]
	for index in range(palms.size()):
		place("palm", palms[index], index * 1.7, 0.95 + (index % 3) * 0.1)
	for at in [Vector3(-21, 0.3, 12), Vector3(21, 0.3, 8), Vector3(20, 0.5, -13), Vector3(-17, 0.3, -15)]:
		place("coastal_rocks", at, 1.3, 1.1)
	place("jetty", Vector3(0, -0.1, 28))
	place("bench", Vector3(-4, 0.42, 3), PI)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for index in range(35):
		var x := rng.randf_range(-21, 21)
		var z := rng.randf_range(-15, 18)
		if absf(x) > 4:
			place("grass_tuft", Vector3(x, 0.43, z), float(index))
	var player := Explorer.new()
	player.name = "Explorer"
	add_child(player)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var controls := TouchControls.new()
	controls.explorer = player
	canvas.add_child(controls)
