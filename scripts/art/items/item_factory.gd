class_name ItemFactory
extends RefCounted
## Builds the carried gameplay items for Props.make_item():
##   "cell" -> CellVisual, "core" -> CoreVisual, "gun" -> GunVisual (set_ammo 0-3).
## Every item's origin is its bottom centre (the gun's is its grip, barrel +Z).


static func make(kind: String) -> Node3D:
	match kind:
		"gun":
			return GunVisual.build()
		"core":
			return CoreVisual.build()
		"cell":
			return CellVisual.build()
	push_warning("ItemFactory: unknown item kind " + kind)
	return CellVisual.build()
