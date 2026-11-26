class_name TitleCard
extends Control
## Title-card system for the trailer, the splash and in-game moments. It uses
## the game's own type (UiStyle fonts, UiType motion) and logo (UiLogo), so a
## title card in the trailer looks exactly like the game's UI.
##
## Deterministic: everything is a pure function of `time`, so a frame renderer
## can call `seek(t)` once per frame; `play()` advances it in real time.
##
##   var card := TitleCard.create("title", {"kicker": "A GAME FOR 2–8 FRIENDS",
##       "title": "ONE OF YOU IS LYING", "sub": "Restore the power. Save the core."})
##   overlay.add_child(card)        # fills its parent (full rect)
##   card.seek(beat_time)           # or card.play()
##
## Kinds (spec keys in brackets, all optional unless noted):
##   "title"   kicker types on, headline builds letter by letter, rule draws
##             out, sub rises [kicker, title*, sub, accent, align]
##   "logo"    the logo lockup sting: wipe + drift settle, tagline types on
##             [layout (lockup|stacked|wordmark|mark), tagline, palette]
##   "chapter" big outlined index + headline [index ("01"), title*, sub, accent]
##   "lower"   lower-third caption with an accent bar [kicker, title*, accent]
##   "end"     end card: logo, tagline, call-to-action pill, small print
##             [tagline, cta, small, layout]
## Common spec keys: hold (s, default 2.0), out (s fade-out, default 0.45;
## 0 keeps it on screen), shade (0..1 black behind), letterbox (share of the
## height for bars, 0 = none), accent (Color), safe (share of the frame kept
## clear at each edge, default 0.07), color (text colour).

signal finished

const IN_TIME := {"title": 1.3, "logo": 1.6, "chapter": 1.1, "lower": 0.8, "end": 2.6}

var kind := "title"
var spec := {}
var time := 0.0:
	set(value):
		time = value
		queue_redraw()
var playing := false


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
	if get_parent() is Control or get_parent() is CanvasLayer or get_parent() is Window:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Seconds from the start to the end of the fade-out.
func duration() -> float:
	return IN_TIME.get(kind, 1.2) + float(spec.get("hold", 2.0)) + float(spec.get("out", 0.45))


func seek(t: float) -> void:
	time = t


func play(from := 0.0) -> void:
	time = from
	playing = true
	set_process(true)


func _process(delta: float) -> void:
	time += delta
	var out: float = spec.get("out", 0.45)
	if out > 0.0 and time >= duration():
		playing = false
		set_process(false)
		finished.emit()


## 0..1 visibility envelope for the fade-out at the end.
func _out_alpha() -> float:
	var out: float = spec.get("out", 0.45)
	if out <= 0.0:
		return 1.0
	var start := duration() - out
	return 1.0 - UiType.ease_in_out((time - start) / out)


## Unit scale: 1.0 at 1280×720; portrait frames scale with the width.
func _base() -> float:
	if size.x >= size.y:
		return minf(size.x / 1280.0, size.y / 720.0)
	return size.x / 760.0


func _accent() -> Color:
	return spec.get("accent", UiStyle.ACCENT)


func _text_color() -> Color:
	return spec.get("color", UiStyle.TEXT)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var alpha := _out_alpha()
	if alpha <= 0.0:
		return
	var shade: float = spec.get("shade", 0.0)
	if shade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, shade * minf(1.0, time / 0.3) * alpha))
	var bars: float = spec.get("letterbox", 0.0)
	if bars > 0.0:
		var h := size.y * bars * UiType.ease_out(time / 0.5)
		draw_rect(Rect2(0, 0, size.x, h), Color.BLACK)
		draw_rect(Rect2(0, size.y - h, size.x, h), Color.BLACK)
	match kind:
		"logo":
			_draw_logo(alpha)
		"chapter":
			_draw_chapter(alpha)
		"lower":
			_draw_lower(alpha)
		"end":
			_draw_end(alpha)
		_:
			_draw_title(alpha)


func _with(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(a, 0.0, 1.0))


func _width_limit() -> float:
	return size.x * (1.0 - 2.0 * float(spec.get("safe", 0.07)))


func _draw_title(alpha: float) -> void:
	var b := _base()
	var center := size * 0.5
	var align := str(spec.get("align", "center"))
	var x := center.x if align == "center" else size.x * float(spec.get("safe", 0.07))
	var head_font := UiStyle.font("title")
	var title := str(spec.get("title", "")).to_upper()
	var head_size := UiType.fit_size(head_font, title, int(84 * b), _width_limit(), 6.0 * b)
	var accent := _accent()
	var kicker := str(spec.get("kicker", "")).to_upper()
	if kicker != "":
		var caps := UiStyle.font("caps")
		var kicker_size := int(22 * b)
		UiType.draw_type_on(self, caps, kicker, Vector2(x, center.y - head_size * 0.72), kicker_size,
			_with(accent, alpha), time, 40.0, align, 4.0 * b)
	var width := UiType.draw_build(self, head_font, title, Vector2(x, center.y + head_size * 0.36), head_size,
		_with(_text_color(), 1.0), time - 0.25, {"align": align, "tracking": 6.0 * b, "spread": head_size * 0.5,
		"total": 0.7, "dur": 0.34, "scramble": true, "seed": title.hash(), "alpha": alpha,
		"glow": _with(accent, 0.16)})
	var rule_y := center.y + head_size * 0.36 + 22.0 * b
	var rule_x := x if align == "center" else x + width * 0.5
	UiType.draw_rule(self, Vector2(rule_x, rule_y), width * 0.7 if align == "center" else width, _with(accent, 0.85 * alpha),
		(time - 0.85) / 0.45, maxf(2.0, 2.0 * b))
	var sub := str(spec.get("sub", ""))
	if sub != "":
		var body := UiStyle.font("light")
		var sub_size := UiType.fit_size(body, sub, int(34 * b), _width_limit())
		var k := UiType.ease_out((time - 1.0) / 0.5)
		var sub_width := body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		var sx := x - sub_width * 0.5 if align == "center" else x
		draw_string(body, Vector2(sx, rule_y + 26.0 * b + sub_size * 0.8 + (1.0 - k) * 12.0 * b), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, _with(UiStyle.MUTED.lightened(0.25), k * alpha))


func _draw_logo(alpha: float) -> void:
	var b := _base()
	var layout := str(spec.get("layout", "lockup"))
	var palette := str(spec.get("palette", "dark"))
	var aspect := UiLogo.aspect(layout)
	var height := minf(float(spec.get("height", 220.0)) * b, _width_limit() / aspect)
	var size_logo := Vector2(height * aspect, height)
	var tagline := str(spec.get("tagline", "TRUST NO ONE")).to_upper()
	var caps := UiStyle.font("headcaps")
	var tag_size := int(26 * b)
	var block := size_logo.y + (tag_size * 2.2 if tagline != "" else 0.0)
	var top := Vector2((size.x - size_logo.x) * 0.5, (size.y - block) * 0.5)
	var reveal := UiType.ease_out(time / 0.75)
	var slide := 1.4 * (1.0 - UiType.ease_out((time - 0.35) / 0.9))
	# Hit frame: a short bright flash band on the drift line as it locks.
	UiLogo.draw(self, layout, top, height, palette, alpha, reveal, slide)
	var lock := clampf((time - 0.95) / 0.3, 0.0, 1.0)
	if lock > 0.0 and lock < 1.0:
		var line_y := top.y + height * (UiLogo.CAP + UiLogo.LINE_GAP + UiLogo.CUT_Y - UiLogo.bounds(layout).position.y) / UiLogo.bounds(layout).size.y
		if layout == "wordmark":
			line_y = top.y + height * (UiLogo.CUT_Y - UiLogo.bounds(layout).position.y) / UiLogo.bounds(layout).size.y
		var glow := sin(lock * PI)
		draw_rect(Rect2(top.x - 40.0 * b, line_y - 1.0, size_logo.x + 80.0 * b, 3.0), _with(_accent(), glow * 0.9 * alpha))
	if tagline != "":
		UiType.draw_type_on(self, caps, tagline, Vector2(size.x * 0.5, top.y + size_logo.y + tag_size * 1.9), tag_size,
			_with(UiStyle.AMBER, alpha), time - 1.15, 30.0, "center", 10.0 * b)


func _draw_chapter(alpha: float) -> void:
	var b := _base()
	var x := size.x * float(spec.get("safe", 0.07))
	var cy := size.y * 0.5
	var index := str(spec.get("index", "01"))
	var head := UiStyle.font("title")
	var big := int(180 * b)
	var k := UiType.ease_out(time / 0.6)
	draw_string_outline(head, Vector2(x - (1.0 - k) * 30.0 * b, cy + big * 0.36), index, HORIZONTAL_ALIGNMENT_LEFT, -1, big,
		maxi(2, int(3 * b)), _with(_accent(), 0.55 * k * alpha))
	var index_width := head.get_string_size(index, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var tx := x + index_width + 36.0 * b
	var title := str(spec.get("title", "")).to_upper()
	var limit := size.x - tx - size.x * float(spec.get("safe", 0.07))
	var size_head := UiType.fit_size(head, title, int(64 * b), limit, 4.0 * b)
	draw_rect(Rect2(tx - 18.0 * b, cy - size_head * 0.9, maxf(2.0, 3.0 * b), size_head * 1.9 * UiType.ease_out((time - 0.15) / 0.4)),
		_with(_accent(), alpha))
	UiType.draw_build(self, head, title, Vector2(tx, cy + size_head * 0.2), size_head, _text_color(), time - 0.25,
		{"tracking": 4.0 * b, "total": 0.5, "dur": 0.3, "alpha": alpha, "spread": size_head * 0.3})
	var sub := str(spec.get("sub", ""))
	if sub != "":
		var body := UiStyle.font("light")
		var sub_size := UiType.fit_size(body, sub, int(30 * b), limit)
		draw_string(body, Vector2(tx, cy + size_head * 0.2 + sub_size * 1.5), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size,
			_with(UiStyle.MUTED.lightened(0.25), UiType.ease_out((time - 0.7) / 0.4) * alpha))


func _draw_lower(alpha: float) -> void:
	var b := _base()
	var x := size.x * float(spec.get("safe", 0.07))
	var bottom := size.y * (1.0 - float(spec.get("letterbox", 0.0))) - size.y * 0.12
	var head := UiStyle.font("head")
	var title := str(spec.get("title", "")).to_upper()
	var size_head := UiType.fit_size(head, title, int(40 * b), _width_limit(), 3.0 * b)
	var k := UiType.ease_out(time / 0.35)
	draw_rect(Rect2(x, bottom - size_head * 2.2, maxf(3.0, 5.0 * b), size_head * 2.2 * k), _with(_accent(), alpha))
	var tx := x + 22.0 * b
	var kicker := str(spec.get("kicker", "")).to_upper()
	if kicker != "":
		UiType.draw_type_on(self, UiStyle.font("caps"), kicker, Vector2(tx, bottom - size_head * 1.35), int(18 * b),
			_with(_accent(), alpha), time - 0.1, 44.0, "left", 3.0 * b)
	UiType.draw_build(self, head, title, Vector2(tx, bottom - size_head * 0.1), size_head, _text_color(), time - 0.2,
		{"tracking": 3.0 * b, "total": 0.35, "dur": 0.25, "alpha": alpha, "spread": size_head * 0.2,
		"outline": maxi(2, int(6 * b)), "outline_color": Color(0, 0, 0, 0.55)})


func _draw_end(alpha: float) -> void:
	var b := _base()
	var layout := str(spec.get("layout", "lockup"))
	var aspect := UiLogo.aspect(layout)
	var height := minf(170.0 * b, _width_limit() / aspect)
	var logo_size := Vector2(height * aspect, height)
	var tagline := str(spec.get("tagline", "Restore the power. Save the core. Trust no one."))
	var cta := str(spec.get("cta", "PLAY WITH 2–8 FRIENDS")).to_upper()
	var small := str(spec.get("small", "ANDROID  ·  PC  ·  SAME WI-FI OR ONLINE")).to_upper()
	var body := UiStyle.font("light")
	var tag_size := UiType.fit_size(body, tagline, int(34 * b), _width_limit())
	var cta_size := int(26 * b)
	var block := logo_size.y + tag_size * 2.4 + cta_size * 3.4 + 40.0 * b
	var y := (size.y - block) * 0.5
	var reveal := UiType.ease_out(time / 0.8)
	var slide := 1.2 * (1.0 - UiType.ease_out((time - 0.4) / 0.9))
	UiLogo.draw(self, layout, Vector2((size.x - logo_size.x) * 0.5, y), height, "dark", alpha, reveal, slide)
	y += logo_size.y + tag_size * 1.7
	var tag_k := UiType.ease_out((time - 1.2) / 0.6)
	var tag_width := body.get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size).x
	draw_string(body, Vector2((size.x - tag_width) * 0.5, y + (1.0 - tag_k) * 10.0 * b), tagline, HORIZONTAL_ALIGNMENT_LEFT,
		-1, tag_size, _with(UiStyle.TEXT, tag_k * alpha))
	y += tag_size * 0.7 + 30.0 * b
	if cta != "":
		var bold := UiStyle.font("bold")
		var cta_width := UiType.tracked_width(bold, cta, cta_size, 3.0 * b)
		var pill := Rect2((size.x - cta_width) * 0.5 - 30.0 * b, y, cta_width + 60.0 * b, cta_size * 2.0)
		var k := UiType.ease_back((time - 1.7) / 0.45)
		if k > 0.0:
			var box := UiStyle.pill_box(_accent(), 0.95 * alpha * clampf(k, 0.0, 1.0))
			var grow := pill.grow_individual(0, 0, 0, 0)
			grow = Rect2(grow.get_center() - grow.size * 0.5 * k, grow.size * k)
			draw_style_box(box, grow)
			if k > 0.6:
				UiType.draw_build(self, bold, cta, Vector2(size.x * 0.5, pill.get_center().y + cta_size * 0.36), cta_size,
					UiStyle.INK, time - 1.85, {"align": "center", "tracking": 3.0 * b, "spread": 0.0, "total": 0.3,
					"dur": 0.2, "alpha": alpha, "rise": 0.0})
		y += pill.size.y + 22.0 * b
	if small != "":
		UiType.draw_type_on(self, UiStyle.font("caps"), small, Vector2(size.x * 0.5, y + 18.0 * b), int(18 * b),
			_with(UiStyle.MUTED, alpha), time - 2.2, 60.0, "center", 3.0 * b, 0.0)
