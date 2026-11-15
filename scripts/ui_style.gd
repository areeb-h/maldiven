class_name UiStyle
extends RefCounted
## Shared look for menus and HUD: fonts, palette, type scale, spacing, glass
## panels, slanted buttons and chips.
##
## Palette (checked with Machado 2009 CVD simulation, CIELAB ΔE, see
## docs/look-and-feel.md §7). Colour never carries meaning alone: every role,
## alert and outcome also has an icon (UiIcons) and a word.
##   CREW #4d8dff vs ACCENT #5fd4ff   ΔE 53 / 39 / 38 / 24 (normal/protan/deutan/tritan)
##   INFILTRATOR #ff4d5e vs AMBER #ffe14d   deutan 43, protan 73
##   INFILTRATOR vs GOOD #5ff0e0   deutan 49, protan 43
##   GOOD sits near ACCENT under tritanopia, so it always carries a bolt or tick.

const BG := Color("060a12")
const PANEL := Color(0.035, 0.06, 0.1, 0.82)
const PANEL_SOLID := Color("0b1220")
const INK := Color("04121c")  # text on filled accent surfaces
const LINE := Color(0.55, 0.8, 1.0, 0.22)
const ACCENT := Color("5fd4ff")
const ACCENT_DEEP := Color("1b6f9a")
const AMBER := Color("ffe14d")
const DANGER := Color("ff4d5e")
const GOOD := Color("5ff0e0")
const TEXT := Color("e8f1ff")
const MUTED := Color(0.75, 0.84, 0.95, 0.62)
const FAINT := Color(0.75, 0.84, 0.95, 0.38)
const CREW := Color("4d8dff")
const INFILTRATOR := Color("ff4d5e")
const GHOST := Color("c8b6ff")

## Type scale (logical px at 1280×720). Nothing goes below CAPTION.
const DISPLAY := 96
const H1 := 48
const H2 := 32
const H3 := 24
const BODY := 24
const LABEL := 20
const CAPTION := 18

## 8 px spacing grid.
const S1 := 8
const S2 := 16
const S3 := 24
const S4 := 32
const S6 := 48
const S8 := 64

static var _fonts := {}


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	if kind == "caps" or kind == "headcaps":
		# Tracked-out small captions ("YOUR ROLE", "NEARBY STATIONS").
		var spaced := FontVariation.new()
		spaced.base_font = font("bold" if kind == "caps" else "head")
		spaced.spacing_glyph = 2 if kind == "caps" else 1
		_fonts[kind] = spaced
		return spaced
	var files := {
		"title": "res://assets/fonts/orbitron-latin-900-normal.woff2",
		"head": "res://assets/fonts/orbitron-latin-700-normal.woff2",
		"body": "res://assets/fonts/rajdhani-latin-600-normal.woff2",
		"bold": "res://assets/fonts/rajdhani-latin-700-normal.woff2",
		"light": "res://assets/fonts/rajdhani-latin-500-normal.woff2",
	}
	var loaded: Font = ThemeDB.fallback_font
	if files.has(kind) and ResourceLoader.exists(files[kind]):
		var file := load(files[kind]) as FontFile
		if file != null:
			# Latin subsets: fall back for symbols outside them.
			file.fallbacks = [ThemeDB.fallback_font]
			loaded = file
	_fonts[kind] = loaded
	return loaded


## Alert kind -> colour and icon. One table for banners, timeline and markers.
static func kind_color(kind: String) -> Color:
	match kind:
		"power":
			return GOOD
		"pod":
			return INFILTRATOR
		"shuttle":
			return CREW
		"blackout", "gun", "down", "downed", "airlock":
			return AMBER
		"spaced", "ghost":
			return GHOST
		"abort":
			return TEXT
		"core":
			return ACCENT
	return ACCENT


static func kind_icon(kind: String) -> String:
	return {"power": "bolt", "pod": "warning", "shuttle": "shuttle", "blackout": "blackout",
		"gun": "crosshair", "down": "downed", "downed": "downed", "airlock": "airlock",
		"spaced": "ghost", "abort": "abort", "core": "core", "cell": "cell"}.get(kind, "info")


static func role_color(role: String) -> Color:
	return INFILTRATOR if role == StationRules.INFILTRATOR else CREW


static func role_icon(role: String) -> String:
	return "mask" if role == StationRules.INFILTRATOR else "shield"


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


static func panel_box(accent := ACCENT, alpha := 0.82, padding := 24.0, radius := 10) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, alpha)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.3)
	box.set_border_width_all(1)
	box.border_width_top = 2
	box.set_corner_radius_all(radius)
	box.corner_detail = 6
	box.anti_aliasing = true
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 4)
	box.set_content_margin_all(padding)
	return box


## A flat inset (rows inside a panel).
static func inset_box(alpha := 0.32, radius := 8, padding := 12.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.01, 0.03, alpha)
	box.set_corner_radius_all(radius)
	box.corner_detail = 6
	box.anti_aliasing = true
	box.set_content_margin_all(padding)
	return box


static func pill_box(color: Color, alpha := 0.9, h_pad := 14.0, v_pad := 3.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, alpha)
	box.set_corner_radius_all(999)
	box.corner_detail = 8
	box.anti_aliasing = true
	box.content_margin_left = h_pad
	box.content_margin_right = h_pad
	box.content_margin_top = v_pad
	box.content_margin_bottom = v_pad
	return box


## An outlined pill: tinted fill, coloured edge.
static func tag_box(color: Color, h_pad := 12.0, v_pad := 2.0) -> StyleBoxFlat:
	var box := pill_box(color, 0.16, h_pad, v_pad)
	box.border_color = Color(color.r, color.g, color.b, 0.75)
	box.set_border_width_all(1)
	return box


static func _button_box(fill: Color, border: Color, glow := 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.border_width_left = 4
	box.set_corner_radius_all(4)
	box.corner_detail = 4
	box.anti_aliasing = true
	box.skew = Vector2(-0.16, 0)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	if glow > 0.0:
		box.shadow_color = Color(border.r, border.g, border.b, glow)
		box.shadow_size = 12
	return box


## Primary (filled) or secondary (outlined) button styles. Text never drops
## below LABEL size; height lands on the 8 px grid via min sizes at call sites.
static func style_button(button: Button, primary := false, color := ACCENT) -> void:
	var fill := Color(color.r, color.g, color.b, 0.92) if primary else Color(0.06, 0.1, 0.17, 0.86)
	var border := color if primary else Color(color.r, color.g, color.b, 0.7)
	var text := INK if primary else TEXT
	button.add_theme_stylebox_override("normal", _button_box(fill, border))
	button.add_theme_stylebox_override("hover", _button_box(fill.lightened(0.1), color.lightened(0.15), 0.3))
	button.add_theme_stylebox_override("pressed", _button_box(fill.darkened(0.15), color, 0.45))
	button.add_theme_stylebox_override("hover_pressed", _button_box(fill.darkened(0.15), color, 0.45))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", _button_box(Color(0.06, 0.08, 0.12, 0.6), Color(1, 1, 1, 0.14)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.34))
	button.add_theme_color_override("icon_normal_color", text)
	button.add_theme_color_override("icon_hover_color", text)
	button.add_theme_color_override("icon_pressed_color", text)
	button.add_theme_color_override("icon_hover_pressed_color", text)
	button.add_theme_color_override("icon_focus_color", text)
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.34))
	button.add_theme_constant_override("h_separation", 12)
	button.add_theme_font_override("font", font("bold"))
	button.add_theme_font_size_override("font_size", 26)


## A styled button with an optional leading icon and the shared press motion.
static func button(text: String, primary := false, color := ACCENT, icon_name := "", height := 64) -> Button:
	var out := Button.new()
	out.text = text
	style_button(out, primary, color)
	out.custom_minimum_size = Vector2(0, height)
	out.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		out.icon = UiIcons.texture(icon_name)
		out.expand_icon = false
		out.add_theme_constant_override("icon_max_width", 26)
	UiMotion.attach_press(out)
	return out


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font("body")
	theme.default_font_size = BODY
	var sample := Button.new()
	style_button(sample)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "Button", sample.get_theme_stylebox(state))
	sample.free()
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_color", "Label", TEXT)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.02, 0.04, 0.08, 0.9)
	field.border_color = Color(LINE.r, LINE.g, LINE.b, 0.3)
	field.set_border_width_all(1)
	field.border_width_bottom = 2
	field.set_corner_radius_all(8)
	field.corner_detail = 6
	field.anti_aliasing = true
	field.content_margin_left = 16
	field.content_margin_right = 16
	field.content_margin_top = 10
	field.content_margin_bottom = 10
	var focused := field.duplicate() as StyleBoxFlat
	focused.border_color = ACCENT
	focused.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18)
	focused.shadow_size = 8
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.32))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3))
	theme.set_constant("caret_width", "LineEdit", 2)
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	grabber.set_corner_radius_all(4)
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.04)
	track.set_corner_radius_all(4)
	track.content_margin_left = 3
	track.content_margin_right = 3
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_font("normal_font", "RichTextLabel", font("body"))
	theme.set_font("bold_font", "RichTextLabel", font("bold"))
	theme.set_color("default_color", "RichTextLabel", TEXT)
	return theme


static func label(text: String, kind := "body", size := BODY, color := TEXT) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_override("font", font(kind))
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


static func outlined(control: Label, outline := 8) -> Label:
	control.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	control.add_theme_constant_override("outline_size", outline)
	return control


## Small caps caption with a leading icon, e.g. "NEARBY STATIONS".
static func caption(text: String, color := MUTED, icon_name := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", S1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		row.add_child(UiIcon.make(icon_name, color, 18))
	var text_label := label(text, "caps", LABEL, color)
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_label)
	return row


## A glowing round emblem with an icon (role badge, result banner).
static func emblem(icon_name: String, color: Color, diameter := 88.0) -> Control:
	var out := Control.new()
	out.custom_minimum_size = Vector2(diameter, diameter)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	out.set_meta("icon", icon_name)
	out.set_meta("color", color)
	out.draw.connect(func():
		var c: Color = out.get_meta("color")
		var r := minf(out.size.x, out.size.y) * 0.5
		var mid := out.size * 0.5
		out.draw_circle(mid, r, Color(c.r, c.g, c.b, 0.1))
		out.draw_circle(mid, r * 0.8, Color(c.r, c.g, c.b, 0.18))
		out.draw_arc(mid, r * 0.8, 0.0, TAU, 64, c, 2.5, true)
		UiIcons.draw(out, str(out.get_meta("icon")), mid, r * 0.92, c))
	return out


static func set_emblem(control: Control, icon_name: String, color: Color) -> void:
	control.set_meta("icon", icon_name)
	control.set_meta("color", color)
	control.queue_redraw()


## A pill chip: optional icon + short word. Filled for strong tags (YOU), outlined otherwise.
static func chip(text: String, color: Color, icon_name := "", filled := true) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", pill_box(color, 0.92, 12, 2) if filled else tag_box(color, 12, 2))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var ink := INK if filled else color
	if icon_name != "":
		row.add_child(UiIcon.make(icon_name, ink, 16))
	var word := label(text, "bold", CAPTION, ink)
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(word)
	return panel
