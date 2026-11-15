class_name SocketVisual
extends Node3D
## Visual state for an interaction socket built by Props.make_socket(). Front
## faces local +Z; origin is on the floor at the socket position.
##   filled: item seated   locked: unusable (vault cage/forcefield shown)
##   active: countdown running (fast warning strobe + alarm light)

const LOCKED := Color(1.0, 0.16, 0.1)
const WAITING := Color(1.0, 0.72, 0.25)
const FILLED := Color(0.25, 1.0, 0.6)
const ACTIVE := Color(1.0, 0.42, 0.04)

var kind := ""
var seat: Marker3D
var status_mat: ShaderMaterial
var field: Node3D
var field_mat: ShaderMaterial
var alarm: OmniLight3D
var filled := false
var locked := false
var active := false
var _t := 0.0


func set_state(p_filled: bool, p_locked: bool, p_active: bool) -> void:
	filled = p_filled
	locked = p_locked
	active = p_active
	if field != null:
		field.visible = locked
	if alarm != null:
		alarm.visible = active
	_apply()


func get_seat_transform() -> Transform3D:
	if seat != null:
		return seat.transform
	return Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0))


func _process(delta: float) -> void:
	_t += delta
	_apply()


func _status_color() -> Color:
	if active:
		return ACTIVE
	if locked:
		return LOCKED
	if filled:
		return FILLED
	return WAITING


func _apply() -> void:
	var energy := 2.5
	if active:
		energy = 1.0 + 7.0 * pow(maxf(0.0, sin(_t * TAU * 2.2)), 2.0)
	elif locked:
		energy = 1.2 + 0.4 * sin(_t * 2.0)
	elif filled:
		energy = 3.0
	else:
		energy = 1.6 + 1.2 * (0.5 + 0.5 * sin(_t * 3.0))
	var c := _status_color()
	if status_mat != null:
		status_mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
		status_mat.set_shader_parameter("energy", energy)
	if field_mat != null and locked:
		field_mat.set_shader_parameter("energy", 0.8 + 0.2 * sin(_t * 5.0))
	if alarm != null and active:
		alarm.light_energy = energy * 0.35
