class_name UiIcons
extends RefCounted
## Hand-drawn vector icons for the HUD and menus. Each glyph is SVG on a 24-unit
## grid (2-unit round strokes or solid fills, white), rasterised once at runtime
## with mipmaps so it stays crisp from 16 px chips to 96 px banners at any
## screen scale. Tint with the draw colour / modulate.
##
## Draw in a CanvasItem with texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
##   UiIcons.draw(self, "cell", center, 32.0, UiStyle.AMBER)

const RASTER := 128  # px per icon; mipmaps cover everything smaller

const STROKE := "fill=\"none\" stroke=\"#fff\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
const LINES := "fill=\"none\" stroke=\"#fff\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
const FILL := "fill=\"#fff\" stroke=\"none\""
const HOLES := "fill=\"#fff\" fill-rule=\"evenodd\" stroke=\"none\""

## name -> SVG body (elements only).
const GLYPHS := {
	# --- Verbs -------------------------------------------------------------------
	"hand": "<path %s d=\"M8 13V6.5a1.5 1.5 0 0 1 3 0V12M11 11.5V4.5a1.5 1.5 0 0 1 3 0V11M14 11V5.5a1.5 1.5 0 0 1 3 0V12M17 12V8.5a1.5 1.5 0 0 1 3 0V14c0 4.5-3 8-7.5 8-3 0-5-1.4-6.4-3.6L3.3 15a1.6 1.6 0 0 1 2.6-1.8L8 15.5\"/>" % STROKE,
	"shove": "<path %s d=\"M1.5 8.5h4M1 12.5h4.5M1.5 16.5h4\"/><g transform=\"translate(5.2 1.4) scale(.82)\"><path %s stroke-width=\"2.4\" d=\"M8 13V6.5a1.5 1.5 0 0 1 3 0V12M11 11.5V4.5a1.5 1.5 0 0 1 3 0V11M14 11V5.5a1.5 1.5 0 0 1 3 0V12M17 12V8.5a1.5 1.5 0 0 1 3 0V14c0 4.5-3 8-7.5 8-3 0-5-1.4-6.4-3.6L3.3 15a1.6 1.6 0 0 1 2.6-1.8L8 15.5\"/></g>" % [STROKE, LINES],
	"throw": "<circle cx=\"5\" cy=\"18.5\" r=\"2.6\" %s/><path %s d=\"M6.5 14C8 8.5 12.5 5 19.5 5.5\"/><path %s d=\"M16 2.5l3.8 3-3.2 3.6\"/><path %s d=\"M10 20.5h2M15 20.5h5\"/>" % [FILL, STROKE, STROKE, STROKE],
	"crosshair": "<circle cx=\"12\" cy=\"12\" r=\"7.5\" %s/><path %s d=\"M12 1.5v5M12 17.5v5M1.5 12h5M17.5 12h5\"/><circle cx=\"12\" cy=\"12\" r=\"1.8\" %s/>" % [STROKE, STROKE, FILL],
	"jump": "<path %s d=\"M6.5 11.5L12 6l5.5 5.5M6.5 17L12 11.5l5.5 5.5\"/><path %s d=\"M4.5 21.5h15\"/>" % [STROKE, STROKE],
	"blackout": "<path %s d=\"M9 18.5h6M10.2 21.5h3.6M8.6 13.6A6.2 6.2 0 1 1 18 9.2M15.6 15.6l-.2.3V16H9.6v-.6c0-.6-.3-1.1-.7-1.5\"/><path %s d=\"M3 3l18 18\"/>" % [STROKE, STROKE],
	"drop": "<path %s d=\"M12 3v11.5M7 10l5 5 5-5M5 20.5h14\"/>" % STROKE,
	"menu": "<path %s d=\"M4 6.5h16M4 12h16M4 17.5h16\"/>" % STROKE,
	# --- Items and places ----------------------------------------------------------
	"cell": "<rect x=\"6.5\" y=\"4\" width=\"11\" height=\"18\" rx=\"2.5\" %s/><path %s d=\"M9.5 1.8h5\"/><path %s d=\"M13 7.5l-4 6h3l-1 4.5 4-6h-3z\"/>" % [STROKE, STROKE, FILL],
	"core": "<path %s d=\"M12 2l8.7 5v10L12 22l-8.7-5V7z\"/><circle cx=\"12\" cy=\"12\" r=\"3.6\" %s/>" % [STROKE, FILL],
	"ammo": "<path %s d=\"M8.5 9.5C8.5 5.5 10 3 12 1.5c2 1.5 3.5 4 3.5 8V19h-7z\"/><rect x=\"7.5\" y=\"20\" width=\"9\" height=\"2.5\" rx=\"1\" %s/>" % [FILL, FILL],
	"gun": "<path %s d=\"M2.5 7.5H19a2.5 2.5 0 0 1 2.5 2.5v1.5h-8l-1 2.5h-2.6L8.3 20.5H4l1.7-9H2.5z\"/>" % FILL,
	"shuttle": "<path %s d=\"M12 2c3 2.4 4.6 6 4.6 10.2V17H7.4v-4.8C7.4 8 9 4.4 12 2z\"/><path %s d=\"M7.4 12.5l-3.2 3.3V19h3.2M16.6 12.5l3.2 3.3V19h-3.2M10 20v2M14 20v2\"/><circle cx=\"12\" cy=\"9.5\" r=\"1.7\" %s/>" % [STROKE, STROKE, FILL],
	"pod": "<rect x=\"2.5\" y=\"6.5\" width=\"19\" height=\"14\" rx=\"2.5\" %s/><path %s d=\"M9 6.5V3.8h6v2.7M2.5 11h19\"/><path %s d=\"M6.5 20.5l4.5-6.5M12 20.5l4.5-6.5\"/>" % [STROKE, STROKE, STROKE],
	"airlock": "<circle cx=\"12\" cy=\"12\" r=\"9.5\" %s/><circle cx=\"12\" cy=\"12\" r=\"3.5\" %s/><path %s d=\"M12 2.5v6M12 15.5v6M2.5 12h6M15.5 12h6\"/>" % [STROKE, STROKE, STROKE],
	"medbay": "<rect x=\"3\" y=\"3\" width=\"18\" height=\"18\" rx=\"4.5\" %s/><path %s d=\"M10 6.8h4v3.2h3.2v4H14v3.2h-4V14H6.8v-4H10z\"/>" % [STROKE, FILL],
	"vault": "<rect x=\"3\" y=\"3\" width=\"18\" height=\"18\" rx=\"3\" %s/><circle cx=\"12\" cy=\"12\" r=\"4.5\" %s/><path %s d=\"M12 7.5v2M12 14.5v2M7.5 12h2M14.5 12h2\"/>" % [STROKE, STROKE, STROKE],
	"lock": "<rect x=\"4.5\" y=\"10.5\" width=\"15\" height=\"11\" rx=\"2.5\" %s/><path %s d=\"M8 10.5V7.5a4 4 0 0 1 8 0v3\"/><circle cx=\"12\" cy=\"16\" r=\"1.6\" %s/>" % [STROKE, STROKE, FILL],
	"unlock": "<rect x=\"4.5\" y=\"10.5\" width=\"15\" height=\"11\" rx=\"2.5\" %s/><path %s d=\"M8 10.5V7.5a4 4 0 0 1 7.6-1.8\"/><circle cx=\"12\" cy=\"16\" r=\"1.6\" %s/>" % [STROKE, STROKE, FILL],
	# --- People and states --------------------------------------------------------
	"downed": "<path %s d=\"M12 2a8.2 8.2 0 0 0-8.2 8.2c0 2.7 1.3 4.8 3.2 6V19a1 1 0 0 0 1 1h1v2.2h2V20h2v2.2h2V20h1a1 1 0 0 0 1-1v-2.8c1.9-1.2 3.2-3.3 3.2-6A8.2 8.2 0 0 0 12 2zM8.8 9.2a2.1 2.1 0 1 0 0 4.2a2.1 2.1 0 1 0 0-4.2zM15.2 9.2a2.1 2.1 0 1 0 0 4.2a2.1 2.1 0 1 0 0-4.2zM12 14.2l-1.3 2.3h2.6z\"/>" % HOLES,
	"ghost": "<path %s d=\"M4.8 21.5V11a7.2 7.2 0 0 1 14.4 0v10.5l-2.4-1.9-2.4 1.9-2.4-1.9-2.4 1.9-2.4-1.9zM9.6 9.4a1.6 1.9 0 1 0 0 3.8a1.6 1.9 0 1 0 0-3.8zM14.4 9.4a1.6 1.9 0 1 0 0 3.8a1.6 1.9 0 1 0 0-3.8z\"/>" % HOLES,
	"shield": "<path %s d=\"M12 1.8l8.5 3.2v6.2c0 5.2-3.6 9.5-8.5 11-4.9-1.5-8.5-5.8-8.5-11V5zM7.6 9.4l4.4 3.2 4.4-3.2v3.1L12 15.7l-4.4-3.2z\"/>" % HOLES,
	"mask": "<path %s d=\"M1.8 9.2C1.8 7.4 3.2 6 5 6c2.8 0 4.4 1.6 7 1.6S16.2 6 19 6c1.8 0 3.2 1.4 3.2 3.2v.8c0 4.2-2.5 7.6-5.7 7.6-2.1 0-3.4-1.5-4.5-3.1-1.1 1.6-2.4 3.1-4.5 3.1-3.2 0-5.7-3.4-5.7-7.6zM5 11.4c1-1.6 3.1-2 4.6-.7-.6 1.7-3 2.4-4.6.7zM19 11.4c-1-1.6-3.1-2-4.6-.7.6 1.7 3 2.4 4.6.7z\"/>" % HOLES,
	"face": "<path %s d=\"M12 1.8c5.3 0 9.2 3.8 9.2 9.4v3.6c0 3.9-2.7 6.7-6.5 6.7H9.3c-3.8 0-6.5-2.8-6.5-6.7v-3.6c0-5.6 3.9-9.4 9.2-9.4zM7.4 9.2h9.2a2.4 2.4 0 0 1 2.4 2.4v1.6a3.3 3.3 0 0 1-3.3 3.3H8.3A3.3 3.3 0 0 1 5 13.2v-1.6a2.4 2.4 0 0 1 2.4-2.4z\"/><rect x=\"7.9\" y=\"11.3\" width=\"2.6\" height=\"2.2\" rx=\".6\" %s/><rect x=\"13.5\" y=\"11.3\" width=\"2.6\" height=\"2.2\" rx=\".6\" %s/>" % [HOLES, FILL, FILL],
	"crown": "<path %s d=\"M3 7.5l4.6 4.2L12 4.5l4.4 7.2L21 7.5 19.2 19H4.8z\"/>" % FILL,
	"users": "<circle cx=\"9\" cy=\"8\" r=\"3.6\" %s/><path %s d=\"M2.5 20.5c.8-3.6 3.3-5.6 6.5-5.6s5.7 2 6.5 5.6M16 4.6a3.6 3.6 0 0 1 0 6.9M18.4 15.2c1.7.8 2.8 2.5 3.2 5.3\"/>" % [STROKE, STROKE],
	"trophy": "<path %s d=\"M8 21.5h8M12 16.5v5M7 3h10v6a5 5 0 0 1-10 0zM7 5.5H3.5v1.2A3.4 3.4 0 0 0 7 10.1M17 5.5h3.5v1.2a3.4 3.4 0 0 1-3.5 3.4\"/>" % STROKE,
	# --- Status and UI ----------------------------------------------------------
	"bolt": "<path %s d=\"M13.5 1.5L3.8 13.6h7l-1.3 8.9 9.7-12.1h-7z\"/>" % FILL,
	"warning": "<path %s d=\"M12 2.2c.6 0 1.1.3 1.4.8l9.2 16.3c.6 1.1-.2 2.4-1.4 2.4H2.8c-1.2 0-2-1.3-1.4-2.4L10.6 3c.3-.5.8-.8 1.4-.8zM10.8 8.5h2.4l-.3 6.5h-1.8zM12 16.6a1.4 1.4 0 1 0 0 2.8a1.4 1.4 0 1 0 0-2.8z\"/>" % HOLES,
	"check": "<path %s d=\"M4.5 12.5l5 5L19.5 7\"/>" % STROKE,
	"info": "<circle cx=\"12\" cy=\"12\" r=\"9.5\" %s/><path %s d=\"M12 11v5.5\"/><circle cx=\"12\" cy=\"7.6\" r=\"1.4\" %s/>" % [STROKE, STROKE, FILL],
	"abort": "<circle cx=\"12\" cy=\"12\" r=\"9.5\" %s/><path %s d=\"M5.3 5.3l13.4 13.4\"/>" % [STROKE, STROKE],
	"clock": "<circle cx=\"12\" cy=\"12\" r=\"9.5\" %s/><path %s d=\"M12 6.5V12l3.5 2.2\"/>" % [STROKE, STROKE],
	"copy": "<rect x=\"8.5\" y=\"8.5\" width=\"12.5\" height=\"12.5\" rx=\"2.5\" %s/><path %s d=\"M15.5 8.5V5.5A2.5 2.5 0 0 0 13 3H5.5A2.5 2.5 0 0 0 3 5.5V13a2.5 2.5 0 0 0 2.5 2.5h3\"/>" % [STROKE, STROKE],
	"wifi": "<path %s d=\"M2 9a14.5 14.5 0 0 1 20 0M5.2 12.6a10 10 0 0 1 13.6 0M8.6 16a5 5 0 0 1 6.8 0\"/><circle cx=\"12\" cy=\"19.5\" r=\"1.7\" %s/>" % [STROKE, FILL],
	"play": "<path %s d=\"M7 3.8c0-.9 1-1.4 1.7-.9l11.6 8.2c.6.4.6 1.3 0 1.8L8.7 21.1c-.7.5-1.7 0-1.7-.9z\"/>" % FILL,
	"leave": "<path %s d=\"M10 3.5H6A2.5 2.5 0 0 0 3.5 6v12A2.5 2.5 0 0 0 6 20.5h4M15.5 7.5l4.5 4.5-4.5 4.5M20 12H9\"/>" % STROKE,
	"close": "<path %s d=\"M6 6l12 12M18 6L6 18\"/>" % STROKE,
	"chevron": "<path %s d=\"M9 4.5l7.5 7.5L9 19.5\"/>" % STROKE,
	"flag": "<path %s d=\"M5 21.5V3M5 4h12.5l-2.5 4.2 2.5 4.3H5\"/>" % STROKE,
	"user": "<circle cx=\"12\" cy=\"8\" r=\"4\" %s/><path %s d=\"M4 21c.9-4 4-6.3 8-6.3s7.1 2.3 8 6.3\"/>" % [STROKE, STROKE],
	"signal": "<path %s d=\"M4 20v-3M9 20v-7M14 20V9M19 20V4\"/>" % STROKE,
	## Off-screen marker arrow: a dart pointing right (+x).
	"dart": "<path %s d=\"M3 4.2c0-.8.9-1.3 1.6-.9l15.6 7.8c.7.4.7 1.4 0 1.8L4.6 20.7c-.7.4-1.6-.1-1.6-.9l3-7.8z\"/>" % FILL,
}

static var _cache := {}


static func has(name: String) -> bool:
	return GLYPHS.has(name)


static func svg(name: String, px := RASTER) -> String:
	return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 24 24\">%s</svg>" % [px, px, GLYPHS.get(name, GLYPHS.info)]


## White icon texture with mipmaps (cached).
static func texture(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var image := Image.new()
	var error := image.load_svg_from_string(svg(name, 24), float(RASTER) / 24.0)
	if error != OK or image.is_empty():
		image = Image.create(RASTER, RASTER, false, Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	var out := ImageTexture.create_from_image(image)
	_cache[name] = out
	return out


## Draw an icon centred on a point. `angle` rotates around the centre.
static func draw(canvas: CanvasItem, name: String, center: Vector2, size: float, color: Color, angle := 0.0) -> void:
	if color.a <= 0.003 or size <= 0.5:
		return
	var tex := texture(name)
	if angle == 0.0:
		canvas.draw_texture_rect(tex, Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)), false, color)
		return
	canvas.draw_set_transform(center, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-Vector2(size, size) * 0.5, Vector2(size, size)), false, color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
