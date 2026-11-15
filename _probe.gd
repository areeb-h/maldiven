extends SceneTree
func _initialize():
	ItemKit.dbg = true
	for kind in ["cell", "core", "gun"]:
		print(kind)
		var it: Node3D = Props.make_item(kind)
		print(kind, " total ", ItemKit.count(it))
	quit()
