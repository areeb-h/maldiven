extends SceneTree
func _initialize() -> void:
	print("start")
	print(UiIcons.names().size())
	for n in UiIcons.names():
		print(n)
		var s := UiIcons.svg(n, 48, "duo")
	print("svg ok")
	quit()
