class_name HudMarkers
extends Control
## World markers: a small pin over the target while it's on screen, or an
## edge-of-screen badge with an arrow pointing at it while it isn't (or is
## behind the camera). Fades in and out per marker; never hides the centre.
##
## markers: Array of {pos: Vector3, kind: String, label: String}
## kinds: "core", "shuttle", "pod", "downed", "cell", "gun", "medbay"

const EDGE := Vector2(64, 64)  # inset from the safe area for edge badges
const TOP_CLEAR := 120.0  # keep below the top bar
const BOTTOM_CLEAR := 56.0

var camera: Camera3D
var origin := Vector3.ZERO  # distances are measured from here (the local player)
var insets := Rect2()  # safe-area margins: position = left/top, size = right/bottom

var _markers: Array = []
var _alpha := {}  # key -> 0..1
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func set_markers(markers: Array) -> void:
	_markers = markers


func _process(delta: float) -> void:
	_time += delta
	var live := {}
	for marker in _markers:
		live[_key(marker)] = true
	for key in live:
		_alpha[key] = minf(1.0, float(_alpha.get(key, 0.0)) + delta / 0.25)
	for key in _alpha.keys():
		if not live.has(key):
			_alpha[key] = float(_alpha[key]) - delta / 0.2
			if _alpha[key] <= 0.0:
				_alpha.erase(key)
	queue_redraw()


func _key(marker: Dictionary) -> String:
	return "%s|%s" % [marker.get("kind", ""), marker.get("label", "")]


static func icon_for(kind: String) -> String:
	return {"core": "core", "shuttle": "shuttle", "pod": "pod", "downed": "downed", "cell": "cell",
		"gun": "gun", "medbay": "medbay"}.get(kind, "info")


static func color_for(kind: String) -> Color:
	match kind:
		"core":
			return UiStyle.ACCENT
		"shuttle":
			return UiStyle.CREW
		"pod":
			return UiStyle.INFILTRATOR
		"downed", "cell", "gun":
			return UiStyle.AMBER
		"medbay":
			return UiStyle.GOOD
	return UiStyle.TEXT


func _draw() -> void:
	var cam := camera if camera != null and is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam == null or _markers.is_empty():
		return
	var area := Rect2(insets.position + EDGE + Vector2(0, TOP_CLEAR - EDGE.y),
		size - insets.position - insets.size - EDGE * 2.0 - Vector2(0, TOP_CLEAR - EDGE.y + BOTTOM_CLEAR))
	var center := area.get_center()
	var font := UiStyle.font("bold")
	for marker in _markers:
		var alpha := float(_alpha.get(_key(marker), 0.0))
		if alpha <= 0.0:
			continue
		var pos: Vector3 = marker.get("pos", Vector3.ZERO)
		var kind := str(marker.get("kind", ""))
		var color := color_for(kind)
		var label := str(marker.get("label", "")).to_upper()
		var meters := int(round(origin.distance_to(pos))) if origin != Vector3.ZERO else -1
		var behind := cam.is_position_behind(pos)
		var point := cam.unproject_position(pos)
		var on_screen := not behind and area.grow(EDGE.x * 0.5).has_point(point)
		var eased := 1.0 - pow(1.0 - alpha, 3.0)
		if on_screen:
			_draw_pin(point, kind, color, label, meters, eased, font)
			continue
		var direction := point - center
		if behind:
			direction = -direction
			if direction.length() < 1.0:
				direction = Vector2(0, 1)
		var edge := _to_edge(center, direction, area)
		_draw_edge(edge, direction.angle(), kind, color, label, meters, eased, font)


## Where the ray from the centre leaves the rectangle.
func _to_edge(center: Vector2, direction: Vector2, area: Rect2) -> Vector2:
	var d := direction.normalized()
	var half := area.size * 0.5
	var tx := INF if absf(d.x) < 0.0001 else half.x / absf(d.x)
	var ty := INF if absf(d.y) < 0.0001 else half.y / absf(d.y)
	return center + d * minf(tx, ty)


func _draw_badge(at: Vector2, kind: String, color: Color, radius: float, alpha: float) -> void:
	draw_circle(at, radius + 3.0, Color(0, 0, 0, 0.35 * alpha))
	draw_circle(at, radius, Color(0.03, 0.05, 0.1, 0.82 * alpha))
	draw_arc(at, radius, 0.0, TAU, 48, UiStyle.with_alpha(color, 0.95 * alpha), 2.5, true)
	UiIcons.draw(self, icon_for(kind), at, radius * 1.15, UiStyle.with_alpha(color, alpha))


func _draw_caption(at: Vector2, label: String, meters: int, alpha: float, font: Font) -> void:
	var text := label if meters < 0 else ("%s  %d m" % [label, meters] if label != "" else "%d m" % meters)
	if text == "":
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var base := at + Vector2(-width * 0.5, 0)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.7 * alpha))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiStyle.with_alpha(UiStyle.TEXT, alpha))


func _draw_pin(point: Vector2, kind: String, color: Color, label: String, meters: int, alpha: float, font: Font) -> void:
	var bob := sin(_time * 3.0) * 2.0
	var at := point + Vector2(0, -34.0 + bob)
	# Stem pointing down at the target.
	draw_colored_polygon(PackedVector2Array([at + Vector2(-7, 14), at + Vector2(7, 14), at + Vector2(0, 26)]),
		UiStyle.with_alpha(color, 0.9 * alpha))
	_draw_badge(at, kind, color, 17.0, alpha)
	_draw_caption(at + Vector2(0, -26.0), label, meters, alpha * 0.95, font)


func _draw_edge(at: Vector2, angle: float, kind: String, color: Color, label: String, meters: int, alpha: float, font: Font) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_circle(at, 26.0 + pulse * 6.0, UiStyle.with_alpha(color, 0.12 * alpha * (1.0 - pulse)))
	_draw_badge(at, kind, color, 21.0, alpha)
	var tip := at + Vector2.from_angle(angle) * (31.0 + pulse * 3.0)
	UiIcons.draw(self, "dart", tip, 20.0, UiStyle.with_alpha(color, alpha), angle)
	# Caption on the inward side of the badge so it never leaves the screen.
	var inward := -Vector2.from_angle(angle)
	var caption_at := at + Vector2(0, 42.0) if inward.y >= -0.3 else at + Vector2(0, -30.0)
	_draw_caption(caption_at, label, meters, alpha * 0.9, font)
