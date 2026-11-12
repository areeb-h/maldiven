extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/island.tscn").instantiate()
	root.add_child(scene)
	for frame in range(45):
		await physics_frame
	var player = scene.get_node("Explorer")
	assert(player.is_on_floor(), "Explorer must settle onto the island")
	var start: Vector3 = player.position
	player.move_input = Vector2(0, -1)
	for frame in range(30):
		await physics_frame
	assert(player.position.z < start.z - 1.0, "Forward input must move toward camera forward")
	player.clear_input()
	for frame in range(30):
		await physics_frame
	assert(Vector2(player.velocity.x, player.velocity.z).length() < 0.1, "Release must stop movement")
	player.jump_pending = true
	for frame in range(5):
		await physics_frame
	assert(player.velocity.y > 0, "Jump must produce upward velocity")
	player.position = Vector3(0, -10, 0)
	for frame in range(3):
		await physics_frame
	assert(player.position.distance_to(player.spawn) < 1.0, "Invalid positions must recover to spawn")
	var controls = scene.get_child(scene.get_child_count() - 1).get_child(0)
	# Three independent fingers: movement, camera and jump.
	await process_frame
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.pressed = true
	touch.position = Vector2(100, 500)
	controls._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(100, 440)
	controls._input(drag)
	assert(player.move_input.y < -0.5, "Touch joystick must update movement")
	touch.index = 2
	touch.position = Vector2(800, 300)
	controls._input(touch)
	var previous_yaw: float = player.yaw
	drag.index = 2
	drag.relative = Vector2(20, 0)
	controls._input(drag)
	assert(player.yaw != previous_yaw, "Second finger must rotate camera")
	touch.index = 3
	touch.position = controls.size - Vector2(90, 90)
	controls._input(touch)
	assert(player.jump_pending, "Third finger must trigger jump")
	touch.index = 1
	touch.pressed = false
	controls._input(touch)
	assert(player.move_input == Vector2.ZERO, "Releasing joystick must clear movement")
	controls.toggle_pause()
	assert(paused and player.move_input == Vector2.ZERO, "Pause must clear active input")
	controls.toggle_pause()
	assert(not paused, "Resume must restore processing")
	print("PASS: floor, movement, stopping, jump, recovery, independent multi-touch and pause")
	quit()
