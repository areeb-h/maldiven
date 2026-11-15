extends SceneTree
func _initialize():
	for kind in ["vault", "reactor", "shuttle", "pod", "armory", "medbay", "airlock_console"]:
		var s: Node3D = SocketKit.make(kind)
		root.add_child(s)
		for f in [false, true]:
			for l in [false, true]:
				for a in [false, true]:
					s.call("set_state", f, l, a)
		print(kind, " ", ItemKit.count(s), " seat ", s.call("get_seat_transform").origin)
	for kind in ["cell", "core", "gun"]:
		print(kind, " ", ItemKit.count(Props.make_item(kind)))
	quit()
