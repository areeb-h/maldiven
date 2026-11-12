extends Control
var explorer
var move_finger := -1
var look_finger := -1
var stick_origin := Vector2.ZERO
var stick_point := Vector2.ZERO
var pause_button: Button
var panel: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var label := Label.new()
	label.text = "MALDIVEN  /  MOVEMENT PROTOTYPE\nWASD · drag to look · Space to jump · Esc to pause"
	label.position = Vector2(24, 20)
	label.add_theme_color_override("font_color", Color("203e48"))
	add_child(label)
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(-120, 20)
	pause_button.size = Vector2(96, 48)
	pause_button.pressed.connect(toggle_pause)
	add_child(pause_button)
	panel = PanelContainer.new()
	panel.position = Vector2(40, 115)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)
	var reset := Button.new()
	reset.text = "Return to beach"
	reset.pressed.connect(func():
		explorer.position = explorer.spawn
		explorer.velocity = Vector3.ZERO
		toggle_pause())
	box.add_child(reset)
	add_child(panel)
	panel.hide()

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	panel.visible = get_tree().paused
	pause_button.text = "Resume" if get_tree().paused else "Pause"
	reset_pointers()

func reset_pointers() -> void:
	move_finger = -1
	look_finger = -1
	explorer.clear_input()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(explorer):
		reset_pointers()
		if is_instance_valid(panel):
			get_tree().paused = true
			panel.show()
			pause_button.text = "Resume"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			toggle_pause()
		elif event.keycode == KEY_SPACE and not get_tree().paused:
			explorer.jump_pending = true
	if get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		explorer.look(event.relative)
	if event is InputEventScreenTouch:
		if not event.pressed:
			if event.index == move_finger:
				move_finger = -1
				explorer.move_input = Vector2.ZERO
			if event.index == look_finger:
				look_finger = -1
		elif event.position.y < 90:
			pass # Reserve top edge for pause UI.
		elif event.position.distance_to(Vector2(size.x - 90, size.y - 90)) < 64:
			explorer.jump_pending = true
		elif event.position.x < size.x * 0.43 and move_finger == -1:
			move_finger = event.index
			stick_origin = event.position
			stick_point = stick_origin
		elif event.position.x >= size.x * 0.43 and look_finger == -1:
			look_finger = event.index
	if event is InputEventScreenDrag:
		if event.index == move_finger:
			var offset: Vector2 = (event.position - stick_origin).limit_length(65)
			stick_point = stick_origin + offset
			explorer.move_input = offset / 65.0
		elif event.index == look_finger:
			explorer.look(event.relative)
	queue_redraw()

func _draw() -> void:
	var center := stick_origin if move_finger >= 0 else Vector2(110, size.y - 110)
	draw_circle(center, 68, Color(1, 1, 1, 0.15))
	draw_arc(center, 68, 0, TAU, 48, Color(1, 1, 1, 0.5), 2, true)
	draw_circle(stick_point if move_finger >= 0 else center, 26, Color(1, 1, 1, 0.45))
	var jump := Vector2(size.x - 90, size.y - 90)
	draw_circle(jump, 48, Color(1, 1, 1, 0.25))
	draw_line(jump + Vector2(-15, 7), jump + Vector2(0, -10), Color.WHITE, 3, true)
	draw_line(jump + Vector2(0, -10), jump + Vector2(15, 7), Color.WHITE, 3, true)
