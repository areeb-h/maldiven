class_name UiMotion
extends RefCounted
## Motion tokens (docs/look-and-feel.md §4, Material 3 emphasised easing) and
## small helpers so every element eases in and out the same way.

const PRESS_DOWN := 0.07
const PRESS_UP := 0.14
const ENTER := 0.28
const EXIT := 0.18
const POP := 0.22
const STAGGER := 0.04
const FADE := 0.12


## Very short buzz on phones only (needs permissions/vibrate in the Android preset).
static func haptic(ms := 12) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## A one-shot UI sound from assets/audio (same files as Sfx) on the SFX bus.
## The player frees itself; missing files and headless runs are a no-op.
static func sound(owner: Node, sound_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if owner == null or not owner.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var path := "res://assets/audio/%s.wav" % sound_name
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	if AudioServer.get_bus_index("SFX") >= 0:
		player.bus = "SFX"
	owner.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Hover lift and press squash for any Control button, plus a tap haptic.
static func attach_press(control: Control, hover_scale := 1.02, press_scale := 0.95) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if OS.has_feature("mobile"):
		hover_scale = 1.0  # emulated touch "hover" never ends cleanly on phones
	var center := func(): control.pivot_offset = control.size * 0.5
	control.resized.connect(center)
	center.call()
	var state := {"tween": null, "hover": false}
	var go := func(target: float, seconds: float, trans: int):
		if state.tween != null:
			(state.tween as Tween).kill()
		var tween := control.create_tween()
		tween.tween_property(control, "scale", Vector2.ONE * target, seconds).set_trans(trans).set_ease(Tween.EASE_OUT)
		state.tween = tween
	if control is BaseButton:
		var button := control as BaseButton
		button.button_down.connect(func():
			if button.disabled:
				return
			haptic(10)
			go.call(press_scale, PRESS_DOWN, Tween.TRANS_QUAD))
		button.button_up.connect(func():
			go.call(hover_scale if state.hover else 1.0, PRESS_UP, Tween.TRANS_BACK))
	control.mouse_entered.connect(func():
		state.hover = true
		if control is BaseButton and (control as BaseButton).disabled:
			return
		go.call(hover_scale, PRESS_UP, Tween.TRANS_QUAD))
	control.mouse_exited.connect(func():
		state.hover = false
		go.call(1.0, PRESS_UP, Tween.TRANS_QUAD))


## Fade + rise in. For free-floating controls (not inside a Container).
static func enter(control: Control, delay := 0.0, rise := 24.0, seconds := ENTER) -> Tween:
	var target := control.position
	control.position = target + Vector2(0, rise)
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel()
	tween.tween_property(control, "position", target, seconds).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, seconds * 0.8).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween


## Scale stamp (1.25 -> 1.0) with a fade, for titles and badges.
static func pop(control: Control, delay := 0.0, from := 1.25, seconds := POP) -> Tween:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * from
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel()
	tween.tween_property(control, "scale", Vector2.ONE, seconds).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, seconds * 0.7).set_delay(delay)
	return tween


## Card entrance: slight scale-up and fade, never a hard cut.
static func card_in(control: Control, delay := 0.0) -> Tween:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(0.94, 0.94)
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel()
	tween.tween_property(control, "scale", Vector2.ONE, 0.32).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, 0.22).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween


static func fade(control: Control, to: float, seconds := FADE, delay := 0.0) -> Tween:
	var tween := control.create_tween()
	tween.tween_property(control, "modulate:a", to, seconds).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween


## A container slot whose child can slide without fighting the parent layout:
## tween `shift` (and modulate) while the parent keeps sorting normally.
class Slide extends Container:
	var shift := Vector2.ZERO:
		set(value):
			shift = value
			queue_sort()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for child in get_children():
				if child is Control:
					fit_child_in_rect(child, Rect2(shift, size))

	func _get_minimum_size() -> Vector2:
		var out := Vector2.ZERO
		for child in get_children():
			if child is Control and child.visible:
				out = out.max(child.get_combined_minimum_size())
		return out

	## Slide in from an offset with a fade, after a delay (stagger).
	func play_in(delay := 0.0, from := Vector2(0, 24), seconds := ENTER) -> Tween:
		shift = from
		modulate.a = 0.0
		var tween := create_tween().set_parallel()
		tween.tween_property(self, "shift", Vector2.ZERO, seconds).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "modulate:a", 1.0, seconds * 0.8).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return tween


static func slide(child: Control) -> Slide:
	var out := Slide.new()
	out.size_flags_horizontal = child.size_flags_horizontal
	out.size_flags_vertical = child.size_flags_vertical
	out.add_child(child)
	return out
