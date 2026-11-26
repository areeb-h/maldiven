extends "res://tools/showcase/studio.gd"
## The Drift Station trailer cut: a timeline of beats, each a method that dresses
## its set on the first frame and then animates crew, camera, VFX and title cards
## from the beat-local time. Built on the showcase studio rig (station, crew,
## lights, depth of field). trailer.gd drives it one fixed-length frame at a time
## and collects the audio cues this script fires into a cue sheet for ffmpeg.

## Beat list: [method, seconds]. Times are cumulative; total ~80 s.
const BEATS: Array = [
	["beat_cold_open", 7.0],
	["beat_title_sting", 2.5],
	["beat_assemble", 7.5],
	["beat_reactor", 1.52],
	["beat_lights_on", 4.98],
	["beat_vault", 4.5],
	["beat_lying", 5.5],
	["beat_gun", 5.0],
	["beat_betrayal", 6.0],
	["beat_chase", 4.0],
	["beat_drag", 4.0],
	["beat_console", 2.5],
	["beat_spaced", 4.0],
	["beat_countdown", 8.0],
	["beat_launch", 5.5],
	["beat_end_card", 8.0],
]
## Letterbox height as a share of the frame (2.39:1 inside 16:9).
const BARS := 0.128
## Beats that keep near-field depth of field (close portraits); elsewhere only a
## light far blur is used so the frame stays crisp.
const NEAR_BLUR_BEATS := ["beat_lying", "beat_console"]
## Far-blur strength relative to the stills.
const DOF_SCALE := 0.5

var fps := 30.0
var dt := 1.0 / 30.0
## Audio cue sheet: [{t, sound, gain_db}], written out by trailer.gd.
var cues: Array[Dictionary] = []

var _beat := -1
var _beat_start := 0.0
var _prev_lt := -1.0
var _cast: Dictionary = {}  # name -> CrewModel for the current beat
var _carry: Dictionary = {}  # CrewModel -> bool (carrying), for idle driving
var _driven: Dictionary = {}
var _vars: Dictionary = {}  # per-beat scratch values
var _overlay: CanvasLayer
var _shade: ColorRect
var _bars: Array[ColorRect] = []
var _title: Label
var _sub: Label
var _small: Label
var _big: Label


static func total_seconds() -> float:
	var t := 0.0
	for b: Array in BEATS:
		t += float(b[1])
	return t


# --- frame driver -------------------------------------------------------------------

## Start time (seconds) of the beat that contains `t`.
static func beat_start_for(t: float) -> float:
	var start := 0.0
	for b: Array in BEATS:
		if t < start + float(b[1]):
			return start
		start += float(b[1])
	return start


## Builds the world and the title-card overlay. Call once before update().
func setup_cut(p_fps: float) -> void:
	fps = p_fps
	dt = 1.0 / fps
	setup()
	dof_scale = DOF_SCALE
	_build_overlay()


## Forgets the current beat and the cue sheet (after a warm-up pass).
func restart() -> void:
	_beat = -1
	cues.clear()


## Advances the cut to absolute time `t` (seconds). Call once per rendered frame.
func update(t: float) -> void:
	var index := 0
	var start := 0.0
	while index < BEATS.size() - 1 and t >= start + float(BEATS[index][1]):
		start += float(BEATS[index][1])
		index += 1
	var first := index != _beat
	if first:
		_beat = index
		_beat_start = start
		allow_near_blur = String(BEATS[index][0]) in NEAR_BLUR_BEATS
		_prev_lt = -1.0
		_cast.clear()
		_carry.clear()
		_vars.clear()
	var lt := t - start
	_driven.clear()
	_reset_overlay()
	call(BEATS[index][0], lt, first)
	for m: CrewModel in _cast.values():
		if is_instance_valid(m) and not _driven.has(m):
			m.set_motion(0.0, true, bool(_carry.get(m, false)), false, dt)
	_after_motion(lt)
	_prev_lt = lt


## Fires a sound once when the beat-local time crosses `at`.
func cue(lt: float, at: float, sound: String, gain_db := 0.0) -> void:
	if _prev_lt < at and lt >= at:
		cues.append({"t": snappedf(_beat_start + at, 0.001), "sound": sound, "gain_db": gain_db})


## True on the frame where beat-local time crosses `at`.
func crossed(lt: float, at: float) -> bool:
	return _prev_lt < at and lt >= at


# --- cast and motion helpers ---------------------------------------------------------

func actor(key: String, color_key: String, pos: Vector3, yaw_deg: float, face_name := "neutral", variant := 0, number := 0) -> CrewModel:
	var m := crew(color_key, pos, yaw_deg, face_name, variant, number)
	_cast[key] = m
	return m


func get_actor(key: String) -> CrewModel:
	return _cast.get(key) as CrewModel


## One animation step for `m` this frame.
func drive(m: CrewModel, speed: float, carrying := false, stunned := false, on_floor := true) -> void:
	_carry[m] = carrying
	_driven[m] = true
	m.set_motion(speed, on_floor, carrying, stunned, dt)


## Walks `m` from `a` to `b` at `speed` m/s starting at beat time `t0`; faces the
## way it walks and idles once it arrives. Returns progress 0..1.
func walk(m: CrewModel, a: Vector3, b: Vector3, speed: float, t0: float, lt: float, carrying := false) -> float:
	var length := a.distance_to(b)
	var k := clampf((lt - t0) * speed / maxf(length, 0.001), 0.0, 1.0)
	m.position = a.lerp(b, k)
	if length > 0.01 and k < 1.0:
		var d := b - a
		m.rotation.y = lerp_angle(m.rotation.y, atan2(d.x, d.z), 0.35)
	drive(m, speed if (k > 0.0 and k < 1.0) else 0.0, carrying)
	return k


## Smoothstep ease.
static func smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## Camera move from (a, ta) to (b, tb) over k with easing; depth of field keeps
## `focus` sharp.
func cam_move(a: Vector3, b: Vector3, ta: Vector3, tb: Vector3, k: float, fov: float, focus: Vector3, depth := 2.0, blur := 0.06) -> void:
	var e := smooth(k)
	frame(a.lerp(b, e), ta.lerp(tb, e), fov, focus, depth, blur)


## Catmull-Rom point on `pts` at u in 0..1 (eased), for curved camera paths.
static func spline(pts: Array[Vector3], u: float) -> Vector3:
	var n := pts.size() - 1
	var x := smooth(u) * float(n)
	var i := clampi(int(floor(x)), 0, n - 1)
	var f := x - float(i)
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, n)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f)


## Per-beat pose overrides that must follow set_motion every frame.
func _after_motion(_lt: float) -> void:
	for key: String in _vars.get("wave", []):
		var m := get_actor(key)
		if m != null:
			raise_arm(m, 1)
	for key: String in _vars.get("hands_up", []):
		var m := get_actor(key)
		if m != null:
			hands_up(m)


# --- overlay ------------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 10
	add_child(_overlay)
	_shade = ColorRect.new()
	_shade.color = Color.BLACK
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_shade)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - BARS
		bar.anchor_bottom = BARS if top else 1.0
		_overlay.add_child(bar)
		_bars.append(bar)
	_title = _label("title", 0.105, Color(0.93, 0.96, 1.0))
	_sub = _label("bold", 0.046, Color(0.8, 0.88, 1.0))
	_small = _label("head", 0.033, Color(1.0, 0.82, 0.45))
	_big = _label("title", 0.3, Color(1.0, 0.45, 0.2))


func _label(font_kind: String, size_share: float, color: Color) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiStyle.font(font_kind))
	l.add_theme_font_size_override("font_size", int(get_viewport().get_visible_rect().size.y * size_share))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 3)
	_overlay.add_child(l)
	return l


func _reset_overlay() -> void:
	_shade.color = Color(0, 0, 0, 0)
	for l in [_title, _sub, _small, _big]:
		(l as Label).visible = false
		(l as Label).modulate.a = 1.0
		(l as Label).position.y = 0.0
	for bar in _bars:
		bar.visible = true


## Shows a title card. `shade` darkens the picture; texts fade in by their alphas.
func card(shade: float, title := "", title_a := 1.0, sub := "", sub_a := 1.0, small := "", small_a := 1.0) -> void:
	_shade.color.a = shade
	var h := get_viewport().get_visible_rect().size.y
	for spec in [[_title, title, title_a, -0.06], [_sub, sub, sub_a, 0.06], [_small, small, small_a, 0.16]]:
		var l: Label = spec[0]
		l.visible = String(spec[1]) != "" and float(spec[2]) > 0.0
		l.text = spec[1]
		l.modulate.a = clampf(spec[2], 0.0, 1.0)
		l.position.y = h * float(spec[3])


## Soft white flash over the picture (alpha 0..1).
func flash(alpha: float) -> void:
	_shade.color = Color(1, 1, 1, clampf(alpha, 0.0, 1.0))


## Brings the power back like StationBuilder.set_power_state(station, "restored")
## but with the reactor core and glow eased off for the camera (at full energy
## the core blooms to a flat white shape in close shots).
func restore_power_soft() -> void:
	StationBuilder.set_power_state(station, "restored")
	var target: Dictionary = (station.get("_to") as Dictionary).duplicate()
	target["reactor"] = 0.75
	target["glow"] = 0.85
	station.set("_to", target)


## Big centred countdown digit.
func digit(text: String, alpha: float, color := Color(1.0, 0.45, 0.2)) -> void:
	_big.visible = alpha > 0.0
	_big.text = text
	_big.modulate = Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


# --- beats --------------------------------------------------------------------------

## Cold open: Cargo in total blackout. Flashlight beams sweep as three crew edge
## forward; behind them, in the dark, a red visor flicks on with an angry face.
func beat_cold_open(lt: float, first: bool) -> void:
	if first:
		begin_shot("blackout", 9001)
		station.env.fog_density = 0.008
		var specs := [["white", Vector3(40.2, 0, -2.2)], ["blue", Vector3(38.7, 0, -3.6)], ["orange", Vector3(41.8, 0, -3.9)]]
		var lights: Array[SpotLight3D] = []
		for i in 3:
			var m := actor("walker%d" % i, specs[i][0], specs[i][1], 6.0, ["suspicious", "shocked", "neutral"][i], (i + 2) % 4, [8, 2, 6][i])
			lights.append(flashlight(m, m.position + Vector3(0, 0, 4.0), 0.07))
		_vars["lights"] = lights
		var red := actor("red", "red", Vector3(39.6, 0, -5.4), 0.0, "neutral", 0, 1)
		red.visor.visible = false
	var lights: Array = _vars["lights"]
	for i in 3:
		var m := get_actor("walker%d" % i)
		var start: Vector3 = [Vector3(40.2, 0, -2.2), Vector3(38.7, 0, -3.6), Vector3(41.8, 0, -3.9)][i]
		walk(m, start, start + Vector3(0.15 * float(i - 1), 0, 2.4), 0.55, 0.3 * float(i), lt)
		var sweep := sin(lt * 0.9 + float(i) * 2.1) * 1.6
		var aim := m.position + m.global_transform.basis.z * 4.0 + Vector3(sweep, 0.0, 0.0)
		(lights[i] as SpotLight3D).look_at_from_position(m.global_transform * Vector3(-0.08, 1.38, 0.32), aim, Vector3.UP)
		if lt > 0.45 * float(i):
			cue(lt, 0.45 * float(i) + 0.05, "footstep_%d" % (i + 1), -10.0)
	# The red visor wakes at 4.6 s with an angry face and blinks once.
	var red := get_actor("red")
	if crossed(lt, 4.6):
		red.set_expression("angry")
	red.visor.visible = lt >= 4.6 and not (lt >= 5.35 and lt < 5.5)
	cue(lt, 0.0, "power_down", -6.0)
	cue(lt, 4.6, "countdown_tick", -2.0)
	var k := lt / 7.0
	var focus := Vector3(40.2, 1.6, -1.0) if lt < 4.4 else Vector3(39.6, 1.65, -5.4)
	cam_move(Vector3(40.4, 0.9, 4.6), Vector3(40.3, 1.15, 2.6), Vector3(40.2, 1.3, -1.0), Vector3(39.8, 1.5, -3.5), k, 40.0, focus, 2.0, 0.1)
	card(clampf(1.0 - lt / 1.2, 0.0, 1.0))


## Title sting on black.
func beat_title_sting(lt: float, first: bool) -> void:
	if first:
		begin_shot("blackout", 9002)
		frame(Vector3(0, 200, 0), Vector3(0, 200, -10), 40.0, Vector3(0, 200, -10), 2.0, 0.0)
	cue(lt, 0.15, "insert_cell", 0.0)
	var a := clampf(lt / 0.25, 0.0, 1.0) * clampf((2.5 - lt) / 0.4, 0.0, 1.0)
	card(1.0, "DRIFT STATION", a, "", 0.0, "TRUST NO ONE", clampf((lt - 0.8) / 0.4, 0.0, 1.0) * a)


## The crew assembles in Commons under emergency light: six walk in from the
## doorways, gather in a ring, one waves, one taps their helmet.
func beat_assemble(lt: float, first: bool) -> void:
	var paths := {
		"yellow": [Vector3(0.0, 0, 6.6), Vector3(0.1, 0, 2.3), 0.0, "happy", 1, 3],
		"blue": [Vector3(7.6, 0, 0.3), Vector3(2.1, 0, 1.1), 0.3, "happy", 2, 2],
		"red": [Vector3(7.6, 0, -0.7), Vector3(2.0, 0, -1.0), 0.7, "neutral", 0, 1],
		"green": [Vector3(0.0, 0, -6.6), Vector3(-0.3, 0, -2.0), 0.15, "happy", 3, 4],
		"purple": [Vector3(-6.8, 0, 0.6), Vector3(-2.2, 0, 0.3), 1.0, "suspicious", 1, 5],
		"orange": [Vector3(0.9, 0, 6.6), Vector3(-1.5, 0, 2.0), 0.5, "happy", 2, 6],
	}
	if first:
		begin_shot("emergency", 9003)
		for key: String in paths:
			var p: Array = paths[key]
			actor(key, key, p[0], 0.0, p[3], p[4], p[5])
	var centre := Vector3(0.0, 0, 0.3)
	for key: String in paths:
		var p: Array = paths[key]
		var m := get_actor(key)
		var k := walk(m, p[0], p[1], 2.3, p[2], lt)
		if k >= 1.0:
			var d := centre - m.position
			m.rotation.y = lerp_angle(m.rotation.y, atan2(d.x, d.z), 0.12)
	if lt > 5.2:
		_vars["wave"] = ["blue"]
	if crossed(lt, 5.0):
		get_actor("red").play_fidget(1)
	cue(lt, 0.0, "ambience_emergency", -14.0)
	cue(lt, 5.2, "ui_click", -8.0)
	var ang := deg_to_rad(lerpf(205.0, 250.0, smooth(lt / 7.5)))
	var cam := Vector3(sin(ang), 0, cos(ang)) * -5.0 + Vector3(0, lerpf(1.9, 1.35, smooth(lt / 7.5)), 0.3)
	frame(cam, Vector3(0, 1.15, 0.3), 46.0, Vector3(0, 1.4, 0.3), 3.0, 0.05)


## Power restored, part 1: in the Reactor the last cell slots home and the
## power wave bursts from the core.
func beat_reactor(lt: float, first: bool) -> void:
	if first:
		begin_shot("emergency", 9004)
		attrs.exposure_multiplier = 0.85
		var w := actor("worker", "yellow", Vector3(58.0, 0, 21.85), 0.0, "neutral", 1, 3)
		_vars["cell"] = hold(w, "cell")
		for id in ["reactor_2", "reactor_3"]:
			(sockets[id] as SocketVisual).set_state(true, false, false)
	var w := get_actor("worker")
	if crossed(lt, 1.0):
		var cell: Node3D = _vars["cell"]
		var socket := sockets["reactor_1"] as SocketVisual
		cell.reparent(socket, false)
		cell.transform = socket.get_seat_transform()
		socket.set_state(true, false, false)
		w.set_held_item("")
		w.set_expression("happy")
		vfx.burst("insert_cell", socket.global_transform * socket.get_seat_transform().origin)
	if crossed(lt, 1.5):
		vfx.burst("power_wave", Vfx.REACTOR_CORE)
		restore_power_soft()
	# The beat cuts on the power hit, before the wave's bright wall sweeps
	# through the lens; a soft white ramp carries the hit across the cut.
	flash(0.3 * smooth((lt - 1.38) / 0.14))
	drive(w, 0.0, lt < 1.0)
	cue(lt, 1.0, "insert_cell", 0.0)
	cue(lt, 1.5, "power_up", 0.0)
	cam_move(Vector3(56.2, 0.7, 18.6), Vector3(56.6, 0.55, 17.6), Vector3(59.5, 1.3, 22.5), Vector3(61.0, 2.2, 20.5), lt / 3.5, 50.0, Vector3(58.0, 1.2, 22.4), 3.0, 0.05)


## Power restored, part 2 (cut on the power hit): the white of the hit fades,
## the wave rolls through Commons in emergency red, then the lights come up on
## the crew (20.8 s, on the score's bloom) and faces brighten.
func beat_lights_on(lt: float, first: bool) -> void:
	var ring := {"yellow": Vector3(0.1, 0, 2.3), "blue": Vector3(2.1, 0, 1.1), "red": Vector3(2.0, 0, -1.0),
		"green": Vector3(-0.3, 0, -2.0), "purple": Vector3(-2.2, 0, 0.3), "orange": Vector3(-1.5, 0, 2.0)}
	if first:
		begin_shot("emergency", 9005)
		var i := 0
		for key: String in ring:
			var m := actor(key, key, ring[key], 0.0, "neutral", i % 4, i + 1)
			face(m, Vector3(0.3, 0, 7.0))
			i += 1
		vfx.burst("power_wave", Vfx.REACTOR_CORE)
	flash(0.3 * (1.0 - smooth(lt / 0.35)))
	if crossed(lt, 2.28):
		restore_power_soft()
	if crossed(lt, 3.1):
		for key: String in ring:
			if key != "purple":
				get_actor(key).set_expression("happy")
	cam_move(Vector3(0.4, 0.45, 7.2), Vector3(0.3, 0.55, 6.0), Vector3(-0.3, 1.9, -1.0), Vector3(-0.3, 2.1, -1.0), lt / 4.98, 50.0, Vector3(0, 1.4, 1.0), 3.0, 0.04)


## The vault unlocks: its field drops and the core glows in its cage; camera
## pushes in past two silhouettes.
func beat_vault(lt: float, first: bool) -> void:
	if first:
		begin_shot("restored", 9006)
		seat_item("vault", "core")
		actor("a", "white", Vector3(-1.3, 0, -19.4), 180.0, "neutral", 3, 8)
		actor("b", "green", Vector3(1.4, 0, -19.6), 180.0, "neutral", 3, 4)
		spot(Vector3(0, 3.0, -21.0), Vector3(0, 1.0, -23.5), CYAN, 6.0, 30.0, 6.0)
	if crossed(lt, 1.6):
		(sockets["vault"] as SocketVisual).set_state(true, false, false)
	cue(lt, 1.6, "revive", 0.0)
	cam_move(Vector3(0.2, 1.5, -15.2), Vector3(0.0, 1.3, -18.6), Vector3(0, 1.3, -23.5), Vector3(0, 1.15, -23.5), lt / 4.5, 46.0, Vector3(0, 1.1, -23.5), 2.0, 0.08)


## "One of you is lying": the line over a dark frame, then snap close-ups of
## suspicious faces in coloured light, landing on purple.
func beat_lying(lt: float, first: bool) -> void:
	var faces := [["red", Vector3(-3.0, 0, -2.2), Color(1.0, 0.2, 0.1)], ["teal", Vector3(3.2, 0, -2.0), CYAN],
		["yellow", Vector3(-3.2, 0, 3.2), Color(1.0, 0.6, 0.15)], ["blue", Vector3(3.0, 0, 3.4), COOL],
		["purple", Vector3(0.0, 0, 0.6), Color(0.7, 0.4, 1.0)]]
	if first:
		begin_shot("restored", 9007)
		attrs.exposure_multiplier = 0.55
		for f: Array in faces:
			var m := actor(f[0], f[0], f[1], 0.0, "suspicious", faces.find(f) % 4, faces.find(f) + 1)
			face(m, f[1] + Vector3(0.6, 0, 2.0))
			var head: Vector3 = (f[1] as Vector3) + Vector3(0, 1.62, 0)
			spot(head + Vector3(-1.2, 0.8, -1.4), head, f[2], 10.0, 24.0, 4.0)
			spot(head + Vector3(0.9, 0.6, 1.6), head, WARM, 2.0, 22.0, 4.0, false, 0.2)
	if lt < 1.3:
		card(0.82, "ONE OF YOU IS LYING", smooth(lt / 0.3) * clampf((1.3 - lt) / 0.2, 0.0, 1.0))
		frame(Vector3(0.6, 1.7, 3.2), Vector3(0, 1.6, 0.6), 40.0, Vector3(0, 1.6, 0.6), 1.0, 0.1)
		return
	var cut := mini(int((lt - 1.3) / 0.7), faces.size() - 1)
	cue(lt, 1.3 + 0.7 * float(cut), "countdown_tick", -6.0)
	var f: Array = faces[cut]
	var m := get_actor(f[0])
	var head := m.position + Vector3(0, 1.62, 0)
	var dir := (m.global_transform.basis.z + m.global_transform.basis.x * 0.45).normalized()
	var push := (lt - 1.3 - 0.7 * float(cut)) * (0.05 if cut < 4 else 0.12)
	frame(head + dir * (1.15 - push) + Vector3(0, 0.03, 0), head + Vector3(0, -0.05, 0), 30.0, head + dir * 0.18, 0.3, 0.16)


## The gun question: orange lifts the gun from the armory rack, turns and levels
## it straight past the lens. One shot.
func beat_gun(lt: float, first: bool) -> void:
	if first:
		begin_shot("emergency", 9008)
		(sockets["armory"] as SocketVisual).set_state(false, false, false)
		_vars["rack_gun"] = seat_item("armory", "gun")
		actor("o", "orange", Vector3(37.0, 0, -22.75), 180.0, "neutral", 2, 6)
		spot(Vector3(39.8, 0.6, -18.6), Vector3(37.0, 1.5, -22.6), Color(1.0, 0.5, 0.25), 4.0, 28.0, 7.0, false, 0.3)
	var o := get_actor("o")
	if crossed(lt, 0.8):
		(_vars["rack_gun"] as Node3D).free()
		_vars["gun"] = hold(o, "gun")
		o.set_expression("angry")
	if lt > 1.2:
		var d := Vector3(38.9, 0, -19.7) - o.position
		o.rotation.y = lerp_angle(o.rotation.y, atan2(d.x, d.z), 0.12)
	if crossed(lt, 1.7):
		o.set_aiming(true)
	if crossed(lt, 3.7):
		o.on_shot()
		var tip := muzzle(_vars["gun"])
		vfx.burst("muzzle_flash", tip.origin, -tip.basis.z)
		vfx.tracer(tip.origin, tip.origin - tip.basis.z * 14.0 + Vector3(0.6, 0.3, 0))
	drive(o, 0.0)
	cue(lt, 0.8, "pickup", 0.0)
	cue(lt, 3.7, "gunshot", 2.0)
	cam_move(Vector3(38.2, 0.85, -20.3), Vector3(38.05, 0.9, -20.7), Vector3(37.0, 1.45, -22.6), Vector3(37.1, 1.5, -22.5), lt / 5.0, 46.0, Vector3(37.0, 1.6, -22.6), 1.6, 0.08)


## Betrayal in Docking: green walks beside teal, who carries the core, then
## shoves. The core flies (a real rigid body), green scoops it up and runs out
## past the lens. Camera at the east end; they walk towards it.
func beat_betrayal(lt: float, first: bool) -> void:
	if first:
		begin_shot("restored", 9009)
		var t := actor("teal", "teal", Vector3(19.4, 0, 1.6), 90.0, "happy", 0, 7)
		_vars["core"] = hold(t, "core")
		actor("green", "green", Vector3(19.2, 0, 2.55), 90.0, "neutral", 3, 4)
	var teal := get_actor("teal")
	var green := get_actor("green")
	if lt < 2.0:
		walk(teal, Vector3(19.4, 0, 1.6), Vector3(22.4, 0, 1.6), 1.5, 0.0, lt, true)
		walk(green, Vector3(19.2, 0, 2.55), Vector3(22.2, 0, 2.55), 1.5, 0.0, lt)
	else:
		if crossed(lt, 2.0):
			face(green, teal.position)
			green.set_expression("angry")
			green.play_shove()
		if crossed(lt, 2.17):
			teal.play_hit()
			teal.set_expression("hurt")
			teal.set_held_item("")
			vfx.burst("shove_impact", teal.position + Vector3(0, 1.3, 0.3), Vector3(0, 0, -1))
			_vars["body"] = _launch_core(_vars["core"], Vector3(-0.8, 3.4, -2.0))
		if lt > 2.17:
			teal.position.z = lerpf(teal.position.z, 0.9, 0.12)
			clear_hit_flash(teal)
		drive(teal, 0.0, false, lt > 2.17 and lt < 3.9)
		if crossed(lt, 3.3):
			var body: RigidBody3D = _vars["body"]
			_vars["g0"] = green.position
			_vars["g_to"] = Vector3(body.global_position.x + 0.5, 0, body.global_position.z + 0.3)
		if lt < 3.3:
			drive(green, 0.0)
		elif lt < 4.2:
			walk(green, _vars["g0"], _vars["g_to"], 4.0, 3.3, lt)
		else:
			if crossed(lt, 4.2):
				var core: Node3D = _vars["core"]
				core.reparent(green.carry_anchor, false)
				core.transform = Transform3D.IDENTITY
				(_vars["body"] as Node).queue_free()
				green.set_held_item("core")
				_vars["g1"] = green.position
			walk(green, _vars["g1"], Vector3(27.5, 0, 0.3), 5.4, 4.2, lt, true)
		if crossed(lt, 3.9):
			teal.set_expression("angry")
	cue(lt, 2.17, "shove", 0.0)
	cue(lt, 2.7, "drop", -2.0)
	cue(lt, 4.2, "pickup", -2.0)
	cam_move(Vector3(26.0, 1.35, 2.6), Vector3(25.6, 1.3, 3.0), Vector3(21.0, 1.15, 1.9), Vector3(22.0, 1.05, 1.0), lt / 6.0, 46.0, teal.position + Vector3(0, 1.3, 0), 3.0, 0.04)


## Turns a held core into a free rigid body with the given launch velocity.
func _launch_core(core: Node3D, velocity: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 1
	body.mass = 9.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.235
	shape.shape = sphere
	shape.position = Vector3(0, 0.36, 0)
	body.add_child(shape)
	set_root.add_child(body)
	body.global_transform = core.global_transform
	core.reparent(body, true)
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(4.0, 2.0, -3.0)
	return body


## The chase: green sprints down the Command-Security corridor with the core,
## teal hard behind; the camera runs backwards ahead of them.
func beat_chase(lt: float, first: bool) -> void:
	if first:
		begin_shot("emergency", 9010)
		var g := actor("green", "green", Vector3(30.5, 0, -19.6), -90.0, "angry", 3, 4)
		hold(g, "core")
		actor("teal", "teal", Vector3(33.4, 0, -20.3), -92.0, "angry", 0, 7)
		station.env.glow_intensity = 0.7
	var g := get_actor("green")
	var t := get_actor("teal")
	g.position.x = 30.5 - 5.4 * lt
	t.position.x = 33.4 - 5.6 * lt
	drive(g, 5.4, true)
	drive(t, 5.6)
	if int(lt * 3.6) != int(_prev_lt * 3.6):
		cue(lt, lt, "footstep_%d" % (int(lt * 3.6) % 3 + 1), -8.0)
	var cam := Vector3(g.position.x - 3.4 + 0.4 * lt, 1.35, -20.6)
	frame(cam, g.position + Vector3(1.0, 1.25, 0.1), 46.0, g.position + Vector3(0, 1.5, 0), 2.0, 0.08)


## The drag: purple carries a limp red crewmate across Commons towards the
## airlock. Seen from inside the airlock corridor as they come.
func beat_drag(lt: float, first: bool) -> void:
	if first:
		begin_shot("restored", 9011)
		var p := actor("purple", "purple", Vector3(-1.0, 0, 0.6), -90.0, "angry", 1, 5)
		var body := crew("red", Vector3.ZERO, 0.0, "downed", 0, 1)
		body.get_parent().remove_child(body)
		p.carry_anchor.add_child(body)
		body.transform = Transform3D.IDENTITY
		body.set_carried(true)
		_vars["body"] = body
	var p := get_actor("purple")
	walk(p, Vector3(-1.0, 0, 0.6), Vector3(-8.2, 0, 0.2), 2.1, 0.0, lt, true)
	(_vars["body"] as CrewModel).set_motion(0.0, true, false, false, dt)
	if int(lt * 2.4) != int(_prev_lt * 2.4):
		cue(lt, lt, "footstep_%d" % (int(lt * 2.4) % 3 + 1), -10.0)
	cam_move(Vector3(-11.6, 0.95, -0.6), Vector3(-11.2, 1.0, -0.7), Vector3(-4.0, 1.3, 0.6), Vector3(-7.0, 1.2, 0.4), lt / 4.0, 44.0, p.position + Vector3(0, 1.4, 0), 2.5, 0.05)


## The console: purple's hand on the cycle lever, face lit red from below as
## the airlock warning strobes.
func beat_console(lt: float, first: bool) -> void:
	if first:
		begin_shot("restored", 9012)
		var p := actor("purple", "purple", Vector3(-5.8, 0, 3.2), 0.0, "angry", 1, 5)
		face(p, Vector3(-7.4, 0, 2.2))
		(sockets["airlock_console"] as SocketVisual).set_state(false, false, true)
		spot(Vector3(-6.5, 0.5, 2.6), Vector3(-5.8, 1.65, 3.2), Color(1.0, 0.2, 0.08), 7.0, 32.0, 3.0)
		station.set_airlock_state("warning")
	cue(lt, 0.0, "airlock_warning", 0.0)
	var p := get_actor("purple")
	cam_move(Vector3(-7.4, 1.45, 2.0), Vector3(-7.15, 1.5, 2.25), p.position + Vector3(0, 1.55, 0), p.position + Vector3(0, 1.6, 0), lt / 2.5, 34.0, p.position + Vector3(0, 1.62, 0), 0.6, 0.12)


## Spaced: the outer door blows, frost streams out and the red crewmate tumbles
## away into the stars past the gas giant: a weightless Jolt ragdoll (the
## gameplay CrewRagdoll), not a scripted spin.
func beat_spaced(lt: float, first: bool) -> void:
	var dir := Vector3(-2.2, 0.45, 1.0)
	if first:
		begin_shot("restored", 9013)
		var r := actor("red", "red", Vector3(-14.4, 0.4, 0.0), -90.0, "shocked", 0, 1)
		r.set_motion(0.0, false, false, true, dt)
		station.set_airlock_state("venting")
		vfx.burst("airlock_vent", Vector3(-15.2, 1.2, 0.0), Vector3(-1, 0, 0))
		var rd := CrewRagdoll.spawn(r, set_root, dir, false, 8)
		if rd != null:
			rd.autonomous = true
			rd.follow_root = true
			rd.weightless()
			for bone in rd.parts:
				(rd.parts[bone] as RigidBody3D).linear_velocity = dir
			rd.spin(Vector3(0.8, 0.3, -0.6).normalized() * 3.2)
		_vars["rd"] = rd
	var r := get_actor("red")
	var rd: CrewRagdoll = _vars.get("rd")
	if rd != null and is_instance_valid(rd):
		_driven[r] = true  # the ragdoll poses the model
	else:
		r.position = Vector3(-14.4, 0.4, 0.0) + dir * lt
		drive(r, 0.0, false, true, false)
	var pelvis := rd.pelvis_position() if rd != null and is_instance_valid(rd) else r.position + Vector3(0, 1.0, 0)
	if crossed(lt, 0.5):
		vfx.burst("spaced", pelvis, dir)
	cue(lt, 0.05, "airlock_vent", 2.0)
	cue(lt, 1.6, "ghost_drift", -4.0)
	cam_move(Vector3(-16.6, 1.0, 6.4), Vector3(-17.4, 1.4, 6.2), Vector3(-17.0, 1.8, -1.0), Vector3(-21.0, 3.0, -1.6), lt / 4.0, 46.0, pelvis, 4.0, 0.03)


## Climax: the infiltrator's pod countdown in Cargo against the crew's shuttle
## countdown in Docking, cross-cut faster and faster under a big countdown.
func beat_countdown(lt: float, first: bool) -> void:
	if first:
		begin_shot("restored", 9014)
		var p := actor("purple", "purple", Vector3(42.15, 0, 4.5), 90.0, "angry", 1, 5)
		hold(p, "core")
		(sockets["pod"] as SocketVisual).set_state(false, false, true)
		var y := actor("yellow", "yellow", Vector3(20.0, 0, -0.62), 180.0, "happy", 1, 3)
		hold(y, "core")
		actor("blue", "blue", Vector3(17.6, 0, 1.4), 20.0, "shocked", 2, 2)
		(sockets["shuttle"] as SocketVisual).set_state(false, false, true)
		spot(Vector3(40.4, 2.6, 6.3), Vector3(42.2, 1.4, 4.5), Color(1.0, 0.25, 0.08), 9.0, 34.0, 6.0)
		spot(Vector3(22.6, 2.6, 2.4), Vector3(20.0, 1.4, -0.6), CYAN, 8.0, 34.0, 6.0)
	_carry[get_actor("purple")] = true
	_carry[get_actor("yellow")] = true
	var cuts := [0.0, 1.1, 2.1, 3.0, 3.8, 4.5, 5.1, 5.6, 6.05, 6.45, 6.8, 7.1, 7.4]
	var index := 0
	while index < cuts.size() - 1 and lt >= cuts[index + 1]:
		index += 1
	var pod := index % 2 == 0
	var local := lt - float(cuts[index])
	if crossed(lt, cuts[index]):
		station.set_state("emergency" if pod else "restored", 0.0)
		vfx.countdown_pulse(Vector3(43.4, 0.0, 4.5) if pod else Vector3(20.0, 0.0, -1.5), Color(1.0, 0.3, 0.1) if pod else Color(1.0, 0.6, 0.2))
	if pod:
		frame(Vector3(39.9, 0.9 + local * 0.1, 6.6), Vector3(42.6, 1.45, 4.5), 40.0, Vector3(42.15, 1.6, 4.5), 1.6, 0.08)
	else:
		frame(Vector3(22.6, 0.75 + local * 0.1, 2.6), Vector3(20.0, 1.5, -0.8), 42.0, Vector3(20.0, 1.6, -0.7), 1.6, 0.08)
	var n := 5 - int(floor(lt / 1.5))
	if n >= 1 and lt < 7.5:
		var frac := fmod(lt, 1.5) / 1.5
		digit(str(n), (1.0 - frac) * 0.85, Color(1.0, 0.4, 0.15) if pod else Color(0.5, 0.95, 1.0))
	for i in 5:
		cue(lt, 1.5 * float(i), "countdown_tick", 0.0)
	cue(lt, 0.0, "alarm_pod", -6.0)
	cue(lt, 7.5, "shuttle_launch_start", 0.0)


## Resolution: the shuttle climbs away from the station towards the gas giant.
func beat_launch(lt: float, first: bool) -> void:
	if first:
		begin_shot("restored", 9015)
		_vars["ship"] = _build_shuttle()
		vfx.burst("launch", Vector3(20.0, 1.0, -4.2), Vector3.UP)
		vfx.attach_trail(_vars["ship"], Color(1.0, 0.6, 0.25))
	var ship: Node3D = _vars["ship"]
	var dir := Vector3(-0.32, 0.42, -0.85).normalized()
	var s := 3.0 * lt + 2.6 * lt * lt
	ship.position = Vector3(20.0, 4.2, -4.2) + dir * s
	ship.basis = Basis.looking_at(dir, Vector3.UP)
	cue(lt, 0.0, "win_crew", -2.0)
	var cam := Vector3(22.0, 8.5, 13.0)
	frame(cam, ship.position.lerp(Vector3(-280, 170, -990), clampf(lt / 5.5, 0.0, 0.2)), 50.0, ship.position, 30.0, 0.0)
	card(clampf((lt - 4.7) / 0.8, 0.0, 1.0))


## A small stand-in shuttle (the docked hull is static station geometry).
func _build_shuttle() -> Node3D:
	var root := Node3D.new()
	set_root.add_child(root)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	white.roughness = 0.35
	var teal := StandardMaterial3D.new()
	teal.albedo_color = Color(0.25, 0.78, 0.65)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.75, 0.4) * 2.0
	var hull := CapsuleMesh.new()
	hull.radius = 1.0
	hull.height = 7.2
	var body := MeshInstance3D.new()
	body.mesh = hull
	body.material_override = white
	body.rotation.x = PI / 2.0
	root.add_child(body)
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 1.02
	band_mesh.bottom_radius = 1.02
	band_mesh.height = 0.8
	band.mesh = band_mesh
	band.material_override = teal
	band.rotation.x = PI / 2.0
	band.position.z = 0.6
	root.add_child(band)
	for sx in [-1.0, 1.0]:
		var pod := MeshInstance3D.new()
		var pod_mesh := CapsuleMesh.new()
		pod_mesh.radius = 0.42
		pod_mesh.height = 2.2
		pod.mesh = pod_mesh
		pod.material_override = white
		pod.rotation.x = PI / 2.0
		pod.position = Vector3(sx * 1.1, -0.2, 2.4)
		root.add_child(pod)
		var nozzle := MeshInstance3D.new()
		var nozzle_mesh := SphereMesh.new()
		nozzle_mesh.radius = 0.36
		nozzle_mesh.height = 0.5
		nozzle.mesh = nozzle_mesh
		nozzle.material_override = glow
		nozzle.position = Vector3(sx * 1.1, -0.2, 3.5)
		root.add_child(nozzle)
	var flame := OmniLight3D.new()
	flame.light_color = Color(1.0, 0.6, 0.3)
	flame.light_energy = 6.0
	flame.omni_range = 8.0
	flame.position = Vector3(0, 0, 4.0)
	root.add_child(flame)
	return root


## End card over the drifting station: title, tagline, platforms.
func beat_end_card(lt: float, first: bool) -> void:
	if first:
		begin_shot("restored", 9016)
	var k := lt / 8.0
	cam_move(Vector3(52.0, 16.0, 44.0), Vector3(50.0, 15.0, 41.0), Vector3(22.0, 0.0, -6.0), Vector3(20.0, 2.0, -8.0), k, 46.0, Vector3(0, 0, -600.0), 10.0, 0.12)
	card(0.62, "DRIFT STATION", smooth(lt / 0.8), "Restore the power. Save the core. Trust no one.", smooth((lt - 1.4) / 0.8), "2–8 FRIENDS  ·  ANDROID", smooth((lt - 2.8) / 0.8))
	if lt > 7.2:
		_shade.color.a = lerpf(0.62, 1.0, (lt - 7.2) / 0.8)
