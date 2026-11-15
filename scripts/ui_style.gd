class_name UiStyle
extends RefCounted
## Shared look for menus and HUD: fonts, palette, glass panels, slanted buttons.

const BG := Color("060a12")
const PANEL := Color(0.035, 0.06, 0.1, 0.82)
const PANEL_SOLID := Color("0b1220")
const LINE := Color(0.55, 0.8, 1.0, 0.22)
const ACCENT := Color("5fd4ff")
const ACCENT_DEEP := Color("1b6f9a")
const AMBER := Color("ffb547")
const DANGER := Color("ff4d5e")
const GOOD := Color("6dffb0")
const TEXT := Color("e8f1ff")
const MUTED := Color(0.75, 0.84, 0.95, 0.6)
const CREW := Color("5ab0ff")
const INFILTRATOR := Color("ff4d5e")

static var _fonts := {}


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
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
			# Latin subsets: fall back for symbols such as … · ●.
			file.fallbacks = [ThemeDB.fallback_font]
			loaded = file
	_fonts[kind] = loaded
	return loaded


static func panel_box(accent := ACCENT, alpha := 0.82, padding := 26.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, alpha)
	box.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	box.set_border_width_all(1)
	box.border_width_top = 3
	box.set_corner_radius_all(6)
	box.corner_detail = 4
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 18
	box.set_content_margin_all(padding)
	return box


static func pill_box(color: Color, alpha := 0.9) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, alpha)
	box.set_corner_radius_all(999)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


static func _button_box(fill: Color, border: Color, glow := 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.border_width_left = 4
	box.set_corner_radius_all(3)
	box.skew = Vector2(-0.18, 0)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	if glow > 0.0:
		box.shadow_color = Color(border.r, border.g, border.b, glow)
		box.shadow_size = 14
	return box


## Primary (filled accent) or secondary (outlined) button styles.
static func style_button(button: Button, primary := false, color := ACCENT) -> void:
	var fill := Color(color.r, color.g, color.b, 0.9) if primary else Color(0.06, 0.1, 0.17, 0.85)
	var text := Color("04121c") if primary else TEXT
	button.add_theme_stylebox_override("normal", _button_box(fill, color))
	button.add_theme_stylebox_override("hover", _button_box(fill.lightened(0.12), color.lightened(0.2), 0.35))
	button.add_theme_stylebox_override("pressed", _button_box(fill.darkened(0.2), color, 0.5))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", _button_box(Color(0.06, 0.08, 0.12, 0.6), Color(1, 1, 1, 0.12)))
	button.add_theme_color_override("font_color", text)
	button.add_theme_color_override("font_hover_color", text)
	button.add_theme_color_override("font_pressed_color", text)
	button.add_theme_color_override("font_focus_color", text)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	button.add_theme_font_override("font", font("bold"))
	button.add_theme_font_size_override("font_size", 28)


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font("body")
	theme.default_font_size = 26
	var sample := Button.new()
	style_button(sample)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "Button", sample.get_theme_stylebox(state))
	sample.free()
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_color", "Label", TEXT)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.02, 0.04, 0.08, 0.9)
	field.border_color = LINE
	field.set_border_width_all(1)
	field.border_width_bottom = 2
	field.set_corner_radius_all(4)
	field.content_margin_left = 16
	field.content_margin_right = 16
	field.content_margin_top = 10
	field.content_margin_bottom = 10
	var focused := field.duplicate()
	focused.border_color = ACCENT
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.35))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5)
	grabber.set_corner_radius_all(4)
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.05)
	track.content_margin_left = 4
	track.content_margin_right = 4
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_font("normal_font", "RichTextLabel", font("body"))
	theme.set_font("bold_font", "RichTextLabel", font("bold"))
	theme.set_color("default_color", "RichTextLabel", TEXT)
	return theme


static func label(text: String, kind := "body", size := 26, color := TEXT) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_override("font", font(kind))
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	return out


static func outlined(control: Label, outline := 8) -> Label:
	control.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	control.add_theme_constant_override("outline_size", outline)
	return control
