extends SceneTree
func _initialize() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var t := Time.get_ticks_msec()
	var st := StationBuilder.build(w)
	print("BUILD ms ", Time.get_ticks_msec() - t)
	var tris := 0
	for mi in st.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		var n := 0
		for s in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		tris += n
		if n > 15000: print(mi.get_parent().name, "/", mi.name, " ", n)
	print("TRIS ", tris, " props ", (st as ArtStationFX).props.size(), " shapes ", st.find_children("*", "CollisionShape3D", true, false).size())
	quit()
