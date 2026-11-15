extends Node3D
## Slow spin + bob for glowing pickups (the station core crystal).

@export var speed := 0.9
@export var bob := 0.025
var _base_y := 0.0
var _t := 0.0


func _ready() -> void:
	_base_y = position.y


func _process(delta: float) -> void:
	_t += delta
	rotation.y = fmod(rotation.y + delta * speed, TAU)
	position.y = _base_y + sin(_t * 2.0) * bob
