extends Control
signal talk_changed(held: bool)
var axis := Vector2.ZERO
var move_pointer := -1
var talk_pointer := -1
var knob := Vector2.ZERO
var talking := false
var talk_status := "HOLD TO TALK"

func pad_center() -> Vector2:
	return Vector2(130, size.y - 130)

func talk_center() -> Vector2:
	return Vector2(size.x - 130, size.y - 130)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if move_pointer == -1 and event.position.distance_to(pad_center()) <= 110:
				move_pointer = event.index
				move_to(event.position)
			elif talk_pointer == -1 and event.position.distance_to(talk_center()) <= 105:
				talk_pointer = event.index
				set_talking(true)
		else:
			if event.index == move_pointer:
				move_pointer = -1
				axis = Vector2.ZERO
				knob = Vector2.ZERO
			if event.index == talk_pointer:
				talk_pointer = -1
				set_talking(false)
	elif event is InputEventScreenDrag:
		if event.index == move_pointer:
			move_to(event.position)
		if event.index == talk_pointer and event.position.distance_to(talk_center()) > 125:
			talk_pointer = -1
			set_talking(false)
	elif event is InputEventKey and event.physical_keycode == KEY_SPACE and not event.echo:
		set_talking(event.pressed)
	queue_redraw()

func move_to(at: Vector2) -> void:
	knob = (at - pad_center()).limit_length(75)
	axis = knob / 75.0

func set_talking(value: bool) -> void:
	if talking != value:
		talking = value
		talk_changed.emit(value)
	queue_redraw()

func reset() -> void:
	move_pointer = -1
	talk_pointer = -1
	knob = Vector2.ZERO
	axis = Vector2.ZERO
	set_talking(false)
	queue_redraw()

func _draw() -> void:
	draw_circle(pad_center(), 95, Color(0.02, 0.06, 0.1, 0.7))
	draw_arc(pad_center(), 95, 0, TAU, 64, Color("87c6cc"), 2, true)
	draw_circle(pad_center() + knob, 35, Color(0.5, 0.9, 0.9, 0.65))
	draw_circle(talk_center(), 95, Color("247f79") if talking else Color(0.02, 0.06, 0.1, 0.85))
	draw_arc(talk_center(), 95, 0, TAU, 64, Color("87c6cc"), 2, true)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(talk_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(font, talk_center() + Vector2(-width / 2, 5), talk_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
