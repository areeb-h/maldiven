extends RefCounted
## Identical static collision for server motion and client prediction.
const WALK_SPEED := 4.0
const RUN_SPEED := 6.0
const TICK_RATE := 30
const INPUT_TIMEOUT_MS := 250

static func material(color: Color, glow := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.75
	if glow:
		result.emission_enabled = true
		result.emission = color
	return result

static func box(parent: Node3D, size: Vector3, position: Vector3, color: Color, solid: bool, visible: bool) -> void:
	if solid:
		var body := StaticBody3D.new()
		body.position = position
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)
	if visible:
		var mesh := MeshInstance3D.new()
		var geometry := BoxMesh.new()
		geometry.size = size
		mesh.mesh = geometry
		mesh.material_override = material(color)
		mesh.position = position
		parent.add_child(mesh)

static func add_sign(parent: Node3D, text: String, at: Vector3, size := 60) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.006
	label.position = at
	label.modulate = Color("caedf1")
	parent.add_child(label)

static func build(parent: Node, visual: bool) -> Node3D:
	var world := Node3D.new()
	world.name = "MovementRoom"
	parent.add_child(world)
	box(world, Vector3(28, 0.4, 20), Vector3(0, -0.2, 0), Color("182936"), true, visual)
	for z in [-10.0, 10.0]:
		box(world, Vector3(28.4, 3.5, 0.4), Vector3(0, 1.75, z), Color("283d4e"), true, visual)
	for x in [-14.0, 14.0]:
		box(world, Vector3(0.4, 3.5, 20), Vector3(x, 1.75, 0), Color("283d4e"), true, visual)
	box(world, Vector3(4, 2.4, 2), Vector3(0, 1.2, 0), Color("425969"), true, visual)
	if visual:
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color("0a1523")
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		settings.ambient_light_color = Color("b9d6e5")
		settings.ambient_light_energy = 0.7
		environment.environment = settings
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55, -25, 0)
		light.light_energy = 1.2
		light.shadow_enabled = true
		world.add_child(light)
		for x in range(-12, 13, 2):
			box(world, Vector3(0.025, 0.012, 19.2), Vector3(x, 0.008, 0), Color("304655"), false, true)
		for z in range(-8, 9, 2):
			box(world, Vector3(27.2, 0.012, 0.025), Vector3(0, 0.008, z), Color("304655"), false, true)
		for x in [-13.3, 13.3]:
			box(world, Vector3(0.08, 0.035, 18.5), Vector3(x, 0.04, 0), Color("42bec8"), false, true)
		box(world, Vector3(3.6, 0.06, 1.65), Vector3(0, 2.45, 0), Color("4eb7bc"), false, true)
		for x in [-11.0, -7.0, 7.0, 11.0]:
			box(world, Vector3(1.5, 0.07, 0.1), Vector3(x, 0.05, -5), Color("e2b060"), false, true)
		add_sign(world, "DRIFT STATION", Vector3(0, 2.7, -9.7), 110)
		add_sign(world, "01   /   ARRIVAL DECK", Vector3(0, 1.9, -9.65), 54)
		add_sign(world, "MOVEMENT LAB", Vector3(0, 2.9, 0), 52)
	return world

static func spawn_for(identity: String) -> Vector3:
	var index := int(identity.trim_prefix("player-")) - 1
	return Vector3(-5 + (index % 3) * 5, 0.95, 5 + int(index / 3) * 2)

static func body(parent: Node3D, at: Vector3) -> CharacterBody3D:
	var result := CharacterBody3D.new()
	result.collision_layer = 2
	result.collision_mask = 1 # First lab: world collision; avatars do not block each other.
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	collision.shape = shape
	result.add_child(collision)
	parent.add_child(result)
	result.position = at
	return result

static func advance(actor: CharacterBody3D, axis: Vector2, sprint: bool, delta: float) -> void:
	axis = axis.limit_length(1.0)
	var speed := RUN_SPEED if sprint else WALK_SPEED
	actor.velocity.x = axis.x * speed
	actor.velocity.z = axis.y * speed
	actor.velocity.y = -0.5 if actor.is_on_floor() else actor.velocity.y - 9.8 * delta
	actor.move_and_slide()

static func avatar(parent: Node3D, identity: String, local: bool) -> Node3D:
	var model := Node3D.new()
	parent.add_child(model)
	var palette := [Color("4ed0cd"), Color("f1b56d"), Color("bca5ee"), Color("e991a7"), Color("87c992"), Color("88b9ec")]
	var color: Color = palette[(int(identity.trim_prefix("player-")) - 1) % palette.size()]
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.25
	torso.mesh = capsule
	torso.position.y = -0.12
	torso.material_override = material(color)
	model.add_child(torso)
	var helmet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	helmet.mesh = sphere
	helmet.position.y = 0.61
	helmet.material_override = material(Color("e0e8e9"))
	model.add_child(helmet)
	box(model, Vector3(0.48, 0.22, 0.1), Vector3(0, 0.65, 0.28), Color("163346"), false, true)
	box(model, Vector3(0.2, 0.46, 0.28), Vector3(-0.21, -0.67, 0), color.darkened(0.25), false, true)
	box(model, Vector3(0.2, 0.46, 0.28), Vector3(0.21, -0.67, 0), color.darkened(0.25), false, true)
	var label := Label3D.new()
	label.text = ("YOU  /  " if local else "CREW  /  ") + identity.trim_prefix("player-").pad_zeros(2)
	label.position.y = 1.25
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.004
	model.add_child(label)
	return model
