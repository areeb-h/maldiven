class_name HudNameTags
extends Control
## Name tags over crewmates (production plan U5), drawn as a 2D overlay so they
## stay a constant, readable size: a small dark pill with a suit-colour dot and
## the name, 2.2 % of the frame height (18 px minimum in the game). They fade
## with distance, hide behind walls (one ray per tag, 10 times a second), and
## never overlap: tags that would collide are pushed apart vertically. The gun
## holder's tag carries a small blaster glyph ("the most trusted or most feared
## person aboard"), a downed player's a downed glyph.
##
## Blackout: `set_dark(true)` makes the tags stutter and go out one by one,
## 40 ms apart; `set_dark(false)` brings them back the same way.
##
## Two ways to feed it:
##   set_tags([{id, name, color, pos: Vector3, armed, state}])  every frame (the HUD)
##   track(node: Node3D, name, color, height := 2.25)           once (the trailer)
## Time comes from _process, or from step(delta) / set_progress(t) when the
## owner drives it (call set_manual(true) first).

const NEAR := 9.0  # m: full opacity inside this
const FAR := 24.0  # m: gone beyond this
const STAGGER := 0.04
const RAY_INTERVAL := 0.1
const WORLD_MASK := 1

var camera: Camera3D
## Frame-height share for the font (the trailer's 2.2 %); the game floors it.
var height_share := 0.022
var min_font := 18
var occlusion := true
var manual := false

var _tags := {}  # key -> {name, color, pos, armed, state, node, height, alpha, seen, ray_in}
var _dark := false
var _dark_age := 99.0
var _order: Array = []  # keys, left to right, frozen when the dark starts
var _clock := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## A standalone tag Control (for menus, the trailer, or attaching anywhere).
static func make_name_tag(player_name: String, color: Color, font_size := 18) -> Control:
	var tag := Tag.new()
	tag.player_name = player_name
	tag.color = color
	tag.font_size = font_size
	return tag


func set_manual(on: bool) -> void:
	manual = on


func set_progress(t: float) -> void:
	manual = true
	_advance(t - _clock)


func step(delta: float) -> void:
	manual = true
	_advance(delta)


## Replace the tag list (keys are ids). pos is the body's feet position.
func set_tags(list: Array) -> void:
	var seen := {}
	for entry in list:
		var key := str(entry.get("id", entry.get("name", "")))
		seen[key] = true
		var tag: Dictionary = _tags.get(key, {"alpha": 0.0, "visible_ray": true, "ray_in": 0.0, "node": null})
		tag.name = str(entry.get("name", ""))
		tag.color = entry.get("color", Color.WHITE)
		tag.pos = entry.get("pos", Vector3.ZERO)
		tag.armed = bool(entry.get("armed", false))
		tag.state = str(entry.get("state", "ok"))
		tag.height = float(entry.get("height", 2.25))
		_tags[key] = tag
	for key in _tags.keys():
		if not seen.has(key) and _tags[key].node == null:
			_tags.erase(key)


## Follow a 3D node (e.g. a CrewModel in the trailer).
func track(node: Node3D, player_name: String, color: Color, height := 2.25, armed := false) -> void:
	_tags[player_name] = {"name": player_name, "color": color, "pos": Vector3.ZERO, "armed": armed, "state": "ok",
		"height": height, "node": node, "alpha": 1.0, "visible_ray": true, "ray_in": 0.0}


func untrack(player_name: String) -> void:
	_tags.erase(player_name)


func set_armed(key: String, armed: bool) -> void:
	if _tags.has(key):
		_tags[key].armed = armed


func set_dark(on: bool) -> void:
	if on == _dark:
		return
	_dark = on
	_dark_age = 0.0
	# Freeze the order the tags go out in: left to right across the screen.
	var keyed := []
	for key in _tags:
		var at: Variant = _project(_tags[key])
		keyed.append([key, (at as Vector2).x if at != null else 0.0])
	keyed.sort_custom(func(a, b): return a[1] < b[1])
	_order = keyed.map(func(entry): return entry[0])


func _process(delta: float) -> void:
	if not manual:
		_advance(delta)


func _advance(delta: float) -> void:
	_clock += delta
	_dark_age += delta
	var cam := _camera()
	for key in _tags:
		var tag: Dictionary = _tags[key]
		var node: Node3D = tag.node
		if node != null:
			if not is_instance_valid(node):
				continue
			tag.pos = node.global_position
		tag.ray_in = float(tag.ray_in) - delta
		if occlusion and cam != null and tag.ray_in <= 0.0 and cam.is_inside_tree():
			tag.ray_in = RAY_INTERVAL
			tag.visible_ray = _clear_line(cam, tag.pos + Vector3(0, tag.height - 0.3, 0))
		var target := 1.0 if tag.visible_ray else 0.0
		tag.alpha = move_toward(float(tag.alpha), target, delta / 0.15)
	queue_redraw()


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _clear_line(cam: Camera3D, head: Vector3) -> bool:
	var world := cam.get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, head, WORLD_MASK)
	return world.direct_space_state.intersect_ray(query).is_empty()


func _project(tag: Dictionary) -> Variant:
	var cam := _camera()
	if cam == null:
		return null
	var head: Vector3 = tag.pos + Vector3(0, float(tag.height), 0)
	if cam.is_position_behind(head):
		return null
	return cam.unproject_position(head)


## 0..1 visibility of the tag at `index` in the blackout order.
func _dark_alpha(index: int) -> float:
	var local := _dark_age - index * STAGGER
	if local < 0.0:
		return 0.0 if not _dark else 1.0
	# Two stutter frames, then settled.
	var stutter := [1.0, 0.0, 1.0, 0.0]
	var frame := int(local * 30.0)
	if frame < stutter.size():
		return stutter[frame] if _dark else 1.0 - stutter[frame]
	return 0.0 if _dark else 1.0


func _draw() -> void:
	var cam := _camera()
	if cam == null:
		return
	var font := UiStyle.font("bold")
	var font_size := maxi(min_font, int(size.y * height_share))
	var placed: Array[Rect2] = []
	var items := []
	for key in _tags:
		var tag: Dictionary = _tags[key]
		var at: Variant = _project(tag)
		if at == null or float(tag.alpha) <= 0.01:
			continue
		var distance := cam.global_position.distance_to(tag.pos)
		var fade := 1.0 - clampf((distance - NEAR) / (FAR - NEAR), 0.0, 1.0)
		var index := _order.find(key)
		var dark := _dark_alpha(index if index >= 0 else 0) if (_dark or _dark_age < 1.0) else 1.0
		var alpha := float(tag.alpha) * fade * dark * (0.55 if tag.state == "dead" else 1.0)
		if alpha <= 0.01:
			continue
		items.append([at, tag, alpha])
	# Nearest (lowest on screen) first, so far tags get pushed, not near ones.
	items.sort_custom(func(a, b): return (a[0] as Vector2).y > (b[0] as Vector2).y)
	for item in items:
		var tag: Dictionary = item[1]
		var tag_size := Tag.measure(str(tag.name), font_size, bool(tag.armed) or tag.state == "downed")
		var rect := Rect2(item[0] - Vector2(tag_size.x * 0.5, tag_size.y), tag_size)
		for _pass in range(8):
			var moved := false
			for other in placed:
				if rect.grow(2.0).intersects(other):
					rect.position.y = other.position.y - rect.size.y - 3.0
					moved = true
			if not moved:
				break
		placed.append(rect)
		var glyph := "gun" if bool(tag.armed) else ("downed" if tag.state == "downed" else "")
		Tag.paint(self, rect, str(tag.name), tag.color, font_size, float(item[2]), glyph)


## The pill itself, usable as a Control or painted onto any canvas.
class Tag extends Control:
	var player_name := "":
		set(value):
			player_name = value
			update_minimum_size()
			queue_redraw()
	var color := Color.WHITE:
		set(value):
			color = value
			queue_redraw()
	var font_size := 18:
		set(value):
			font_size = value
			update_minimum_size()
			queue_redraw()
	var glyph := "":
		set(value):
			glyph = value
			update_minimum_size()
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _get_minimum_size() -> Vector2:
		return measure(player_name, font_size, glyph != "")

	func _draw() -> void:
		paint(self, Rect2(Vector2.ZERO, size), player_name, color, font_size, 1.0, glyph)

	static func measure(text: String, px: int, with_glyph: bool) -> Vector2:
		var font := UiStyle.font("bold")
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var height := px * 1.5
		return Vector2(height * 0.5 + px * 0.5 + px * 0.45 + width + height * 0.45 + (px * 1.1 if with_glyph else 0.0), height)

	static func paint(canvas: CanvasItem, rect: Rect2, text: String, tint: Color, px: int, alpha: float, icon := "") -> void:
		var box := UiStyle.pill_box(Color(0.02, 0.035, 0.07), 0.62 * alpha, 0, 0)
		box.border_color = Color(tint.r, tint.g, tint.b, 0.55 * alpha)
		box.set_border_width_all(1)
		canvas.draw_style_box(box, rect)
		var mid := rect.position.y + rect.size.y * 0.5
		var dot := Vector2(rect.position.x + rect.size.y * 0.5, mid)
		canvas.draw_circle(dot, px * 0.3, Color(tint.r, tint.g, tint.b, alpha))
		var font := UiStyle.font("bold")
		var x := dot.x + px * 0.3 + px * 0.45
		canvas.draw_string(font, Vector2(x, mid + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.93, 0.96, 1.0, alpha))
		if icon != "":
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			UiIcons.draw(canvas, icon, Vector2(x + width + px * 0.75, mid), px * 1.05,
				Color(1.0, 0.54, 0.29, alpha) if icon == "gun" else Color(UiStyle.AMBER.r, UiStyle.AMBER.g, UiStyle.AMBER.b, alpha))
