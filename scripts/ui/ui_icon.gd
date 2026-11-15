class_name UiIcon
extends Control
## A tinted vector icon that sits in containers like a Label. Changing `icon`
## cross-fades (120 ms) instead of jump-cutting.

@export var icon := "info":
	set(value):
		if value == icon:
			return
		_previous = icon
		icon = value
		_fade = 0.0 if is_inside_tree() and _previous != "" else 1.0
		set_process(_fade < 1.0)
		queue_redraw()
@export var color := Color.WHITE:
	set(value):
		color = value
		queue_redraw()

var _previous := ""
var _fade := 1.0


static func make(icon_name: String, tint := Color.WHITE, size := 24.0) -> UiIcon:
	var out := UiIcon.new()
	out.icon = icon_name
	out.color = tint
	out.custom_minimum_size = Vector2(size, size)
	out.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return out


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)


func _process(delta: float) -> void:
	_fade = minf(1.0, _fade + delta / 0.12)
	if _fade >= 1.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var center := size * 0.5
	if _fade < 1.0 and _previous != "":
		UiIcons.draw(self, _previous, center, side * (1.0 - 0.2 * _fade), UiStyle.with_alpha(color, color.a * (1.0 - _fade)))
	var eased := 1.0 - pow(1.0 - _fade, 3.0)
	UiIcons.draw(self, icon, center, side * (0.8 + 0.2 * eased), UiStyle.with_alpha(color, color.a * eased))
