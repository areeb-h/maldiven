extends SceneTree

var proxy: PlayerProxy
var t := 0

func _initialize() -> void:
	var n := Node3D.new()
	root.add_child(n)
	proxy = PlayerProxy.new()
	n.add_child(proxy)
	proxy.global_position = Vector3(5, 0, 5)
	proxy.report(Vector3(5, 0, 5), Vector3.ZERO)
	physics_frame.connect(_step)

func _step() -> void:
	t += 1
	proxy.report(Vector3(5 + t * 0.05, 0, 5), Vector3(3, 0, 0))
	proxy.step(1.0 / 60.0, 0.1, 0.0, null)
	if t % 10 == 0:
		print(t, " ", proxy.global_position, " layer ", proxy.collision_layer)
	if t > 40:
		quit()
