class_name CameraFx
extends Node
## Camera juice for the local player: trauma shake, FOV kicks, run FOV, hit stop
## and haptics. Add as a child of the Camera3D (or anywhere) and call setup().
## Shake uses Camera3D.h_offset / v_offset for translation (never moves the camera
## into walls) and a small additive rotation; it runs on real time so hit stop
## does not freeze it. Tuned subtle for a social game.

## Global comfort multiplier (0 = no shake / FOV kicks, 1 = default) for settings.
static var intensity := 1.0
## Set false to silence vibrate() regardless of platform.
static var haptics := true

const MAX_OFFSET := 0.25  # metres at full trauma
const MAX_ANGLE := 0.0436332  # 2.5 degrees
const NOISE_SPEED := 22.0
const RUN_FOV_BONUS := 6.0  # 70 -> 76
const RUN_FOV_RATE := 5.0
const MAX_HIT_STOP := 0.2

var camera: Camera3D
var base_fov := 70.0
var trauma := 0.0
var _decay := 1.5
var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _applied_rot := Vector3.ZERO
var _written_rot := Vector3.ZERO
var _written_fov := -1.0
var _run_target := 0.0
var _run_bonus := 0.0
var _kick_amount := 0.0
var _kick_time := 0.0
var _kick_dur := 0.0
var _stop_until_ms := 0
var _stop_active := false
var _saved_time_scale := 1.0
var _last_us := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()


func _ready() -> void:
	if camera == null and get_parent() is Camera3D:
		setup(get_parent() as Camera3D)


func setup(p_camera: Camera3D) -> void:
	camera = p_camera
	if camera != null:
		base_fov = camera.fov
		_written_fov = camera.fov
		_written_rot = camera.rotation
	_applied_rot = Vector3.ZERO
	_last_us = Time.get_ticks_usec()


## Adds trauma (0..1) that decays to zero over `duration` seconds.
func shake(strength: float, duration: float) -> void:
	trauma = clampf(maxf(trauma, 0.0) + clampf(strength, 0.0, 1.0), 0.0, 1.0)
	_decay = trauma / maxf(duration, 0.02)


## Quick FOV punch (degrees) that eases back over `duration`.
func kick_fov(amount: float, duration: float) -> void:
	_kick_amount = amount
	_kick_dur = maxf(duration, 0.02)
	_kick_time = 0.0


## Brief slow-motion dip, restored on real time (also restored if this node leaves).
func hit_stop(seconds: float, time_scale := 0.15) -> void:
	var length := clampf(seconds, 0.0, MAX_HIT_STOP)
	if length <= 0.0:
		return
	if not _stop_active:
		_saved_time_scale = Engine.time_scale
		_stop_active = true
	Engine.time_scale = minf(Engine.time_scale, clampf(time_scale, 0.01, 1.0))
	_stop_until_ms = maxi(_stop_until_ms, Time.get_ticks_msec() + int(length * 1000.0))


func vibrate(ms: int) -> void:
	if not haptics or ms <= 0:
		return
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		Input.vibrate_handheld(ms)


func set_run_fov(running: bool) -> void:
	_run_target = RUN_FOV_BONUS if running else 0.0


func is_hit_stopped() -> bool:
	return _stop_active


func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	var dt := 0.0 if _last_us == 0 else clampf(float(now_us - _last_us) / 1000000.0, 0.0, 0.1)
	_last_us = now_us
	if _stop_active and Time.get_ticks_msec() >= _stop_until_ms:
		_restore_time_scale()
	if camera == null or not is_instance_valid(camera):
		return
	trauma = maxf(0.0, trauma - _decay * dt)
	_noise_t += dt * NOISE_SPEED
	var amount := trauma * trauma * clampf(intensity, 0.0, 1.0)
	var rot := Vector3.ZERO
	if amount > 0.0001:
		camera.h_offset = MAX_OFFSET * amount * _noise.get_noise_2d(11.0, _noise_t)
		camera.v_offset = MAX_OFFSET * amount * _noise.get_noise_2d(37.0, _noise_t)
		rot = Vector3(
			MAX_ANGLE * 0.5 * amount * _noise.get_noise_2d(73.0, _noise_t),
			MAX_ANGLE * 0.5 * amount * _noise.get_noise_2d(101.0, _noise_t),
			MAX_ANGLE * amount * _noise.get_noise_2d(149.0, _noise_t))
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	# Additive rotation: if something else rewrote the rotation since our last
	# frame (e.g. a SpringArm), treat its value as the clean base.
	var base_rot := camera.rotation
	if base_rot.is_equal_approx(_written_rot):
		base_rot -= _applied_rot
	camera.rotation = base_rot + rot
	_written_rot = camera.rotation
	_applied_rot = rot
	# FOV: base + smoothed run bonus + kick envelope (fast attack, eased release).
	if _written_fov >= 0.0 and not is_equal_approx(camera.fov, _written_fov):
		base_fov = camera.fov - _run_bonus - _kick_value()
	_run_bonus = lerpf(_run_bonus, _run_target, 1.0 - exp(-RUN_FOV_RATE * dt))
	if _kick_dur > 0.0:
		_kick_time += dt
		if _kick_time >= _kick_dur:
			_kick_dur = 0.0
	camera.fov = clampf(base_fov + _run_bonus + _kick_value(), 1.0, 179.0)
	_written_fov = camera.fov


func _kick_value() -> float:
	if _kick_dur <= 0.0:
		return 0.0
	var k := clampf(_kick_time / _kick_dur, 0.0, 1.0)
	var attack := 0.15
	var env := k / attack if k < attack else pow(1.0 - (k - attack) / (1.0 - attack), 2.0)
	return _kick_amount * env * clampf(intensity, 0.0, 1.0)


func _restore_time_scale() -> void:
	if _stop_active:
		Engine.time_scale = _saved_time_scale
		_stop_active = false


func _exit_tree() -> void:
	_restore_time_scale()
	if camera != null and is_instance_valid(camera):
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		if camera.rotation.is_equal_approx(_written_rot):
			camera.rotation -= _applied_rot
		_applied_rot = Vector3.ZERO
		camera.fov = base_fov
