extends Node3D
## Root script of Props.make_item("gun"): lights 0-3 charge cells.

var cell_mats: Array[ShaderMaterial] = []
var ammo := 3


func set_ammo(n: int) -> void:
	ammo = clampi(n, 0, cell_mats.size())
	for i in range(cell_mats.size()):
		var on := i < ammo
		cell_mats[i].set_shader_parameter("energy", 2.0 if on else 0.1)
		cell_mats[i].set_shader_parameter("tint", Vector3(1, 1, 1) if on else Vector3(0.4, 0.4, 0.45))
