extends SceneTree
## Headless audio smoke test: every generated WAV loads through Sfx, loops are
## configured, and each Sfx API call runs without errors on the dummy driver.
## Unknown sound names must be a silent no-op (the run's output should hold no warnings).

const LENGTHS := {
	"ambience_station": [8.0, 12.0], "ambience_emergency": [8.0, 12.0], "alarm_pod": [1.0, 1.4],
	"power_up": [2.2, 2.8], "power_down": [1.7, 2.3], "pickup": [0.15, 0.35], "drop": [0.2, 0.6],
	"insert_cell": [0.6, 1.0], "shuttle_launch_start": [1.2, 1.8], "countdown_tick": [0.08, 0.16],
	"abort": [0.45, 0.75], "shove": [0.25, 0.45], "footstep_1": [0.12, 0.25],
	"footstep_2": [0.12, 0.25], "footstep_3": [0.12, 0.25], "ui_click": [0.05, 0.12],
	"win_crew": [3.0, 4.0], "win_infiltrator": [3.0, 4.0],
	"gunshot": [0.25, 0.45], "downed": [0.55, 0.85], "revive": [0.85, 1.15], "throw": [0.2, 0.4],
	"airlock_warning": [1.3, 1.7], "airlock_vent": [2.2, 2.8], "ghost_drift": [5.5, 6.5],
}
const LOOPS := ["ambience_station", "ambience_emergency", "alarm_pod", "airlock_warning", "ghost_drift"]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var sfx := Sfx.new()
	root.add_child(sfx)
	await _frames(2)

	_check(sfx.preload_all() == Sfx.SOUNDS.size(), "not every sound loaded")
	for sound in Sfx.SOUNDS:
		var stream := sfx.get_stream(sound)
		_check(stream is AudioStreamWAV, "%s is not an AudioStreamWAV" % sound)
		if stream == null:
			continue
		var length := stream.get_length()
		var bounds: Array = LENGTHS.get(sound, [0.01, 20.0])
		_check(length >= bounds[0] and length <= bounds[1], "%s length %.3f s out of range" % [sound, length])
	_check(LENGTHS.size() == Sfx.SOUNDS.size(), "test and Sfx.SOUNDS disagree")

	for sound in LOOPS:
		var looped := sfx.get_loop_stream(sound) as AudioStreamWAV
		_check(looped != null, "%s has no loop stream" % sound)
		if looped != null:
			_check(looped.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s does not loop forward" % sound)
			_check(looped.loop_end > looped.loop_begin, "%s has an empty loop" % sound)
			_check(absf(float(looped.loop_end) / float(looped.mix_rate) - looped.get_length()) < 0.01,
				"%s loop_end %d does not cover the file" % [sound, looped.loop_end])
	var one_shot := sfx.get_stream("alarm_pod") as AudioStreamWAV
	_check(one_shot != null and one_shot.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"one-shot alarm resource must stay non-looping")

	sfx.play("ui_click")
	sfx.play("drop", Vector3(4.0, 0.0, -2.0), -3.0)
	sfx.play("footstep")
	for i in 30:  # more than both pools hold: exercises round-robin stealing
		sfx.play(Sfx.SOUNDS[i % Sfx.SOUNDS.size()] if i % 2 else "footstep", Vector3(i, 0, 0) if i % 3 else null)
	for unknown in ["no_such_sound", "", "../project", "footstep_9"]:
		sfx.play(unknown)
		sfx.play(unknown, Vector3(1.0, 0.0, 1.0), 6.0)
		_check(sfx.get_stream(unknown) == null, "unknown sound '%s' resolved to a stream" % unknown)
	sfx.set_ambience("emergency")
	await _frames(3)
	_check(sfx.get_ambience_state() == "emergency", "ambience state not stored")
	sfx.set_ambience("blackout")
	await _frames(3)
	sfx.set_ambience("restored")
	await _frames(3)
	_check(sfx.get_ambience_state() == "restored", "ambience did not switch to restored")
	sfx.start_alarm()
	sfx.start_alarm()  # idempotent
	await _frames(3)
	_check(sfx.is_alarm_playing(), "alarm is not playing after start_alarm()")
	sfx.stop_alarm()
	await _frames(5)

	sfx.set_ghost_mode(true)
	sfx.set_ghost_mode(true)  # idempotent
	await _frames(3)
	_check(sfx.is_ghost_mode(), "ghost mode did not turn on")
	_check("ghost_drift" in sfx._amb_sound, "ghost mode did not start the ghost_drift loop")
	sfx.play("gunshot", Vector3(2.0, 0.0, 0.0))
	sfx.play("throw")
	sfx.set_ambience("emergency")  # remembered under the ghost pad
	await _frames(3)
	_check("ghost_drift" in sfx._amb_sound, "set_ambience() replaced the ghost loop")
	sfx.set_ghost_mode(false)
	await _frames(3)
	_check(not sfx.is_ghost_mode(), "ghost mode did not turn off")
	_check("ambience_emergency" in sfx._amb_sound, "leaving ghost mode did not restore the ambience")
	sfx.set_ambience("off")
	await _frames(3)

	sfx.stop_all()
	_check(not sfx.is_alarm_playing() and sfx.get_ambience_state() == "", "stop_all() left audio running")
	# Give the audio thread real time to release stopped playbacks before freeing.
	await create_timer(0.25).timeout
	sfx.queue_free()
	await _frames(2)
	await create_timer(0.1).timeout
	if _failures.is_empty():
		print("PASS: audio smoke (%d sounds)" % Sfx.SOUNDS.size())
		quit(0)
	else:
		for failure in _failures:
			printerr("  ", failure)
		print("FAIL: audio smoke (%d problems)" % _failures.size())
		quit(1)
