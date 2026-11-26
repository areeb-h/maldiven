class_name TitleCard
extends Control
## Title cards for the trailer and the game's own title moments. They use the
## game's fonts (UiStyle), type motion (UiType) and logo (UiLogo), so a card
## in the trailer is the same family as the game's UI (production plan U9/U10).
##
## Standalone and deterministic: plain data in, time from `set_progress(t)` or
## `step(delta)` (or `play()` for real time). Fills its parent; lays out from
## the frame size (1280×720 to 2560×1440, portrait too). Text stays inside the
## letterboxed picture (`picture`, default the trailer's 2.39:1 bars) with 8 %
## side margins. Text snaps in over three frames and cuts off; nothing fades
## slowly except the slate's final fade to black.
##
##   var card := UiStyle.card_statement("ONE OF YOU IS LYING.")
##   overlay.add_child(card)
##   card.set_progress(lt)        # every frame
##
## Kinds and their spec keys (all optional unless starred):
##   "statement"  centred title font, 10 % of frame height, off-white, tracking
##                +4 %, at most five words [text*, height (share), y (share of
##                the picture, 0.5 = centre)]
##   "line"       body bold, 4 % height [text*, height, y, color]
##   "lockup"     the logo lands; at `flip` s the visor eyes snap to the red V;
##                at `line_at` s a card line appears beneath
##                [flip (1.2, <0 = never), line (text), line_at (1.8), height]
##   "slate"      one-line logo small at the top, the real primary button
##                (PLAY AGAIN) pulsing once a second, the platform line in
##                amber, fade to black over [fade_from, fade_to]
##                [button, platforms, fade_from (2.0), fade_to (2.5)]
##   "lower"      lower-third caption with an accent bar [kicker, text*]
## Common: hold (s before it cuts off; <= 0 = stays), picture (bar share,
## default 0.128), margin (side share, default 0.08), shade (0..1 black).

signal finished

const SNAP := 0.1  # three frames at 30 fps
const OFF_WHITE := Color(0.93, 0.96, 1.0)

var kind := "statement"
var spec := {}
var time := 0.0:
	set(value):
		time = value
		_sync_children()
		queue_redraw()
var playing := false
var _button: Button


static func create(card_kind: String, card_spec := {}) -> TitleCard:
	var card := TitleCard.new()
	card.kind = card_kind
	card.spec = card_spec
	return card


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if kind == "slate":
		_button = UiStyle.button(str(spec.get("button", "PLAY AGAIN")), true, UiStyle.ACCENT, "play", 80)
		_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_button)
	resized.connect(_sync_children)
	_sync_children()


## Seconds until the card cuts off (or fades out, for the slate).
func duration() -> float:
	if kind == "slate":
		return float(spec.get("fade_to", 2.5))
	return float(spec.get("hold", 0.0))


func set_progress(t: float) -> void:
	playing = false
	set_process(false)
	time = t


func seek(t: float) -> void:
	set_progress(t)


func step(delta: float) -> void:
	time += delta


func play(from := 0.0) -> void:
	time = from
	playing = true
	set_process(true)


func _process(delta: float) -> void:
	time += delta
	var end := duration()
	if end > 0.0 and time >= end:
		playing = false
		set_process(false)
		finished.emit()


func _gone() -> bool:
	var hold: float = spec.get("hold", 0.0)
	return kind != "slate" and hold > 0.0 and time >= hold


## The letterboxed picture the text must stay inside.
func picture() -> Rect2:
	var bars := size.y * float(spec.get("picture", 0.128))
	var margin := size.x * float(spec.get("margin", 0.08))
	return Rect2(margin, bars, size.x - margin * 2.0, size.y - bars * 2.0)


func _fade() -> float:
	if kind != "slate":
		return 0.0
	var fade_from: float = spec.get("fade_from", 2.0)
	var fade_to: float = spec.get("fade_to", 2.5)
	return clampf((time - fade_from) / maxf(0.01, fade_to - fade_from), 0.0, 1.0)


func _snap() -> float:
	return clampf(time / SNAP, 0.0, 1.0)


func _with(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(a, 0.0, 1.0))


func _sync_children() -> void:
	if _button == null or size.y <= 0.0:
		return
	var h := size.y
	var font_size := int(h * 0.036)
	_button.add_theme_font_size_override("font_size", font_size)
	_button.add_theme_constant_override("icon_max_width", int(font_size * 1.0))
	_button.custom_minimum_size = Vector2(h * 0.36, h * 0.085)
	_button.reset_size()
	_button.size = _button.get_combined_minimum_size()
	_button.position = Vector2((size.x - _button.size.x) * 0.5, h * 0.5 - _button.size.y * 0.5)
	_button.pivot_offset = _button.size * 0.5
	# Pulse once a second: a quick swell that settles (deterministic in time).
	var beat := fmod(maxf(time - 0.3, 0.0), 1.0)
	var swell := exp(-beat * 7.0) if time > 0.3 else 0.0
	_button.scale = Vector2.ONE * (1.0 + 0.06 * swell)
	_button.modulate = Color(1.0 + 0.25 * swell, 1.0 + 0.25 * swell, 1.0 + 0.25 * swell, _snap() * (1.0 - _fade()))


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _gone():
		return
	var shade: float = spec.get("shade", 0.0)
	if shade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, shade))
	match kind:
		"line":
			_draw_line_card()
		"lockup":
			_draw_lockup()
		"slate":
			_draw_slate()
		"lower":
			_draw_lower()
		_:
			_draw_statement()


## Centred text that snaps in: alpha and a 4 % scale settle over three frames.
func _draw_snapped(text: String, font: Font, font_size: int, color: Color, center_y: float, tracking: float) -> void:
	var k := _snap()
	if k <= 0.0 or text == "":
		return
	var width := UiType.tracked_width(font, text, font_size, tracking)
	var grow := 1.0 + 0.04 * (1.0 - k)
	var center := Vector2(size.x * 0.5, center_y)
	draw_set_transform(center, 0.0, Vector2.ONE * grow)
	var x := -width * 0.5
	var baseline := font_size * 0.36
	for i in range(text.length()):
		var ch := text[i]
		draw_string(font, Vector2(x, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _with(color, k))
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + tracking
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_statement() -> void:
	var area := picture()
	var text := str(spec.get("text", spec.get("title", ""))).to_upper()
	var font := UiStyle.font("title")
	var font_size := int(size.y * float(spec.get("height", 0.10)))
	font_size = UiType.fit_size(font, text, font_size, area.size.x, font_size * 0.04)
	var y := area.position.y + area.size.y * float(spec.get("y", 0.5))
	_draw_snapped(text, font, font_size, spec.get("color", OFF_WHITE), y, font_size * 0.04)


func _draw_line_card() -> void:
	var area := picture()
	var text := str(spec.get("text", ""))
	var font := UiStyle.font("bold")
	var font_size := int(size.y * float(spec.get("height", 0.04)))
	font_size = UiType.fit_size(font, text, font_size, area.size.x)
	var y := area.position.y + area.size.y * float(spec.get("y", 0.5))
	_draw_snapped(text, font, font_size, spec.get("color", OFF_WHITE), y, 0.0)


func _draw_lockup() -> void:
	var area := picture()
	var height := minf(size.y * float(spec.get("height", 0.26)), area.size.x / UiLogo.aspect("lockup"))
	var logo_size := Vector2(height * UiLogo.aspect("lockup"), height)
	var line := str(spec.get("line", ""))
	var line_at: float = spec.get("line_at", 1.8)
	var line_size := int(size.y * 0.04)
	var block := logo_size.y + (line_size * 2.4 if line != "" else 0.0)
	var top := Vector2((size.x - logo_size.x) * 0.5, area.get_center().y - block * 0.5)
	var k := _snap()
	# The flip: two glitch frames, then the V.
	var flip: float = spec.get("flip", 1.2)
	var blend := 0.0
	if flip >= 0.0 and time >= flip:
		blend = 0.5 if time < flip + 2.0 / 30.0 else 1.0
	UiLogo.draw(self, "lockup", top, height, str(spec.get("palette", "dark")), k, 1.0, 0.05 * (1.0 - k), blend, time)
	if line != "" and time >= line_at:
		var font := UiStyle.font("bold")
		var font_size := UiType.fit_size(font, line, line_size, area.size.x)
		var lk := clampf((time - line_at) / SNAP, 0.0, 1.0)
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2((size.x - width) * 0.5, top.y + logo_size.y + line_size * 1.9), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _with(OFF_WHITE, lk))


func _draw_slate() -> void:
	var area := picture()
	var k := _snap()
	var height := size.y * 0.07
	var width := height * UiLogo.aspect("wordmark")
	UiLogo.draw(self, "wordmark", Vector2((size.x - width) * 0.5, area.position.y + size.y * 0.05), height, "dark", k)
	var platforms := str(spec.get("platforms", "ANDROID  ·  PC"))
	var font := UiStyle.font("head")
	var font_size := int(size.y * 0.032)
	var text_width := UiType.tracked_width(font, platforms, font_size, font_size * 0.12)
	var y := size.y * 0.5 + size.y * 0.085 * 0.5 + size.y * 0.075
	var x := (size.x - text_width) * 0.5
	for i in range(platforms.length()):
		draw_string(font, Vector2(x, y), platforms[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _with(UiStyle.AMBER, k))
		x += font.get_string_size(platforms[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + font_size * 0.12
	# The film's only slow fade (the button child fades with it).
	var fade := _fade()
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, fade))


func _draw_lower() -> void:
	var area := picture()
	var x := area.position.x
	var bottom := area.end.y - area.size.y * 0.08
	var font := UiStyle.font("head")
	var text := str(spec.get("text", spec.get("title", ""))).to_upper()
	var font_size := UiType.fit_size(font, text, int(size.y * 0.045), area.size.x, 3.0)
	var k := _snap()
	draw_rect(Rect2(x, bottom - font_size * 2.2, maxf(3.0, size.y * 0.006), font_size * 2.2), _with(spec.get("accent", UiStyle.ACCENT), k))
	var tx := x + size.y * 0.03
	var kicker := str(spec.get("kicker", "")).to_upper()
	if kicker != "":
		draw_string(UiStyle.font("caps"), Vector2(tx, bottom - font_size * 1.35), kicker, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(size.y * 0.022), _with(spec.get("accent", UiStyle.ACCENT), k))
	draw_string_outline(font, Vector2(tx, bottom - font_size * 0.1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		maxi(2, int(font_size * 0.15)), _with(Color(0, 0, 0, 0.55), k))
	draw_string(font, Vector2(tx, bottom - font_size * 0.1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _with(OFF_WHITE, k))
