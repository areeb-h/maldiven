class_name HudAmmo
extends Control
## The gun's three charges as pips in the gun's charge colour (production plan
## U6). Firing pops a pip: one white frame at 1.4× scale, then it drops back
## hollow. Lit pips breathe a little so they read as live energy, even as the
## only light on a black frame.
##
## Standalone: `HudAmmo.create({ammo, max, height})`, then `set_ammo(n)`; time
## from _process, or `step(delta)` / `set_progress(t)` (switches to manual).
## `plate` adds the in-game glass plate with the gun glyph and a count.

const CHARGE := Color(0.32, 1.0, 0.78)  # GunVisual.CHARGE
const POP_TIME := 0.16

var ammo := 3
var max_ammo := 3
var pip_height := 30.0:
	set(value):
		pip_height = value
		update_minimum_size()
var plate := false:
	set(value):
		plate = value
		update_minimum_size()
var manual := false

var _clock := 0.0
var _popped := {}  # pip index -> clock time it popped


static func create(data := {}) -> HudAmmo:
	var out := HudAmmo.new()
	out.present(data)
	return out


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func present(data: Dictionary) -> void:
	max_ammo = int(data.get("max", max_ammo))
	ammo = clampi(int(data.get("ammo", max_ammo)), 0, max_ammo)
	pip_height = float(data.get("height", pip_height))
	plate = bool(data.get("plate", plate))
	_popped.clear()
	queue_redraw()


## Set the count; a drop pops the spent pips (unless animate is false).
func set_ammo(n: int, animate := true) -> void:
	n = clampi(n, 0, max_ammo)
	if animate:
		for i in range(n, ammo):
			_popped[i] = _clock
	if n > ammo:
		for i in range(ammo, n):
			_popped.erase(i)
	ammo = n
	queue_redraw()


func set_progress(t: float) -> void:
	manual = true
	_clock = t
	queue_redraw()


func step(delta: float) -> void:
	manual = true
	_clock += delta
	queue_redraw()


func _process(delta: float) -> void:
	if not manual:
		_clock += delta
		queue_redraw()


func _gap() -> float:
	return pip_height * 0.55


func _pip_width() -> float:
	return pip_height * 0.46


func _get_minimum_size() -> Vector2:
	var pips := Vector2(_pip_width() * max_ammo + _gap() * (max_ammo - 1), pip_height * 1.4)
	if plate:
		return pips + Vector2(pip_height * 3.4, pip_height * 0.9)
	return pips


func _draw() -> void:
	var h := pip_height
	var start := Vector2((size.x - (_pip_width() * max_ammo + _gap() * (max_ammo - 1))) * 0.5, size.y * 0.5)
	if plate:
		var box := UiStyle.panel_box(UiStyle.ACCENT, 0.62, 0, 10)
		box.skew = Vector2(-0.12, 0)
		box.border_color = Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.35)
		box.border_width_left = 4
		box.shadow_size = 8
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		UiIcons.draw(self, "gun", Vector2(h * 0.95, size.y * 0.5), h * 1.05, Color(1, 1, 1, 0.92))
		start.x = h * 1.9
		var font := UiStyle.font("title")
		var count := str(ammo)
		var count_size := int(h * 0.95)
		draw_string(font, Vector2(size.x - h * 1.05, size.y * 0.5 + count_size * 0.36), count, HORIZONTAL_ALIGNMENT_LEFT, -1,
			count_size, UiStyle.TEXT if ammo > 0 else UiStyle.DANGER)
	var breathe := 0.85 + 0.15 * sin(_clock * 3.0)
	for i in range(max_ammo):
		var center := start + Vector2(_pip_width() * 0.5 + i * (_pip_width() + _gap()), 0)
		var lit := i < ammo
		var scale := 1.0
		var white := false
		if _popped.has(i):
			var age := _clock - float(_popped[i])
			if age < 1.0 / 30.0:
				scale = 1.4
				white = true
			elif age < POP_TIME:
				scale = lerpf(1.4, 1.0, UiType.ease_out((age - 1.0 / 30.0) / (POP_TIME - 1.0 / 30.0)))
		var w := _pip_width() * scale
		var ph := h * scale
		var rect := Rect2(center - Vector2(w, ph) * 0.5, Vector2(w, ph))
		var corner := w * 0.32
		var pip := _pip(rect, corner)
		if white:
			draw_colored_polygon(_pip(rect.grow(w * 0.5), corner * 2.0), Color(1, 1, 1, 0.35))
			draw_colored_polygon(pip, Color.WHITE)
		elif lit:
			draw_colored_polygon(_pip(rect.grow(w * 0.42), corner * 2.0), Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.2 * breathe))
			draw_colored_polygon(pip, Color(CHARGE.r, CHARGE.g, CHARGE.b, breathe))
			draw_colored_polygon(_pip(Rect2(rect.position + Vector2(w * 0.22, ph * 0.1), Vector2(w * 0.22, ph * 0.5)), 1.0),
				Color(1, 1, 1, 0.55))
		else:
			var outline := pip
			outline.append(pip[0])
			draw_polyline(outline, Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.4), maxf(1.5, h * 0.06), true)


## A chamfered pip (cell-like: cut corners top and bottom).
func _pip(rect: Rect2, corner: float) -> PackedVector2Array:
	var c := minf(corner, rect.size.x * 0.45)
	return PackedVector2Array([
		Vector2(rect.position.x + c, rect.position.y), Vector2(rect.end.x - c, rect.position.y),
		Vector2(rect.end.x, rect.position.y + c), Vector2(rect.end.x, rect.end.y - c),
		Vector2(rect.end.x - c, rect.end.y), Vector2(rect.position.x + c, rect.end.y),
		Vector2(rect.position.x, rect.end.y - c), Vector2(rect.position.x, rect.position.y + c)])
