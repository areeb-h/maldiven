class_name HudTicker
extends Control
## Live event ticker (production plan U1): the round's timeline, one row at a
## time, as it happens. Each row is the result screen's own row
## (HudResult.make_row: time in amber, icon, names in suit colour): it slides
## in (0.2 s), holds (2.5 s), fades (0.4 s). At most two rows show; a new one
## pushes the oldest out. Rows that would reveal a role arrive anonymised
## ("Someone triggered a blackout"); the result screen names them.
##
## In the game the HUD feeds it public events. In the trailer the same
## component is the lower third: `HudTicker.create({font_share: 0.033,
## origin: Vector2(0.08, 0.80), snap: true})`, then `push(...)` and
## `set_progress(t)` / `step(delta)` (manual time; `snap` cuts rows in and
## out instead of sliding).

const SLIDE := 0.2
const FADE := 0.4

var hold := 2.5
var max_rows := 2
var snap := false
## Font size as a share of the frame height (0 = use font_size).
var font_share := 0.0
var font_size := 22
## Where the newest row's baseline sits: shares of the frame, or px when
## origin_px is set (x >= 0).
var origin := Vector2(0.08, 0.80)
var origin_px := Vector2(-1, -1)
## Newest row at the origin; older rows stack upward (true) or downward.
var grow_up := true
var plate := true
var manual := false

var _clock := 0.0
var _rows: Array = []  # {node, born, leave_at}


static func create(opts := {}) -> HudTicker:
	var ticker := HudTicker.new()
	for key in opts:
		ticker.set(key, opts[key])
	return ticker


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if get_parent() is Control or get_parent() is CanvasLayer:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _font_px() -> int:
	return maxi(12, int(size.y * font_share)) if font_share > 0.0 else font_size


## Push a sentence: names coloured from `colors` (name -> Color), icon from
## the sentence unless given. time_s is the round clock (seconds).
func push(time_s: float, text: String, colors := {}, icon := "") -> Control:
	var kind := HudResult.timeline_kind(text)
	var icon_name := icon if icon != "" else HudResult.row_icon(kind)
	return push_row(time_s, icon_name, HudResult.colorize_names(text, colors), HudResult.kind_tint(kind))


func push_row(time_s: float, icon: String, bbcode: String, tint := UiStyle.TEXT) -> Control:
	var row := HudResult.make_row(time_s, icon, bbcode, _font_px(), false, tint, plate)
	add_child(row)
	row.modulate.a = 0.0
	_rows.push_front({"node": row, "born": _clock, "leave_at": _clock + hold})
	var live := 0
	for entry in _rows:
		if _clock < float(entry.leave_at):
			live += 1
			if live > max_rows:
				entry.leave_at = _clock
	_layout()
	return row


func clear() -> void:
	for entry in _rows:
		(entry.node as Control).queue_free()
	_rows.clear()


func set_progress(t: float) -> void:
	manual = true
	_clock = t
	_layout()


func step(delta: float) -> void:
	manual = true
	_clock += delta
	_layout()


func _process(delta: float) -> void:
	if not manual:
		_clock += delta
		_layout()


func _layout() -> void:
	var base := origin_px if origin_px.x >= 0.0 else Vector2(size.x * origin.x, size.y * origin.y)
	var px := _font_px()
	var line := px * 1.75
	var slot := 0
	for entry in _rows.duplicate():
		var node: Control = entry.node
		var age := _clock - float(entry.born)
		var gone := _clock - float(entry.leave_at)
		if gone >= (0.0 if snap else FADE) and age >= 0.0:
			_rows.erase(entry)
			node.queue_free()
			continue
		var alpha := 1.0
		var shift := 0.0
		if snap:
			alpha = 1.0 if age >= 0.0 and gone < 0.0 else 0.0
		else:
			var k := UiType.ease_out(age / SLIDE)
			var out := 1.0 - clampf(gone / FADE, 0.0, 1.0) if gone > 0.0 else 1.0
			alpha = k * out
			shift = (1.0 - k) * -px
		node.modulate.a = clampf(alpha, 0.0, 1.0)
		node.reset_size()
		var y := base.y - line * 0.72 - (slot * line if grow_up else -slot * line)
		node.position = Vector2(base.x + shift, y)
		if gone < 0.0:
			slot += 1
