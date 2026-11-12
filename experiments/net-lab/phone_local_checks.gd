extends SceneTree
const Wire = preload("res://voice_wire.gd")
const Touch = preload("res://phone_controls.gd")
const Audio = preload("res://voice_audio.gd")

func _initialize() -> void:
	call_deferred("exercise")

func exercise() -> void:
	var touch := Touch.new()
	root.add_child(touch)
	touch.size = Vector2(1280, 720)
	var left := InputEventScreenTouch.new()
	left.index = 2
	left.position = touch.pad_center() + Vector2(60, 0)
	left.pressed = true
	touch._input(left)
	var right := InputEventScreenTouch.new()
	right.index = 7
	right.position = touch.talk_center()
	right.pressed = true
	touch._input(right)
	assert(touch.axis.x > 0.7 and touch.talking and touch.move_pointer == 2 and touch.talk_pointer == 7)
	left.pressed = false
	touch._input(left)
	assert(touch.axis == Vector2.ZERO and touch.talking)
	touch.reset()
	assert(not touch.talking and touch.talk_pointer == -1 and touch.move_pointer == -1)
	var samples := PackedFloat32Array()
	samples.resize(Wire.SAMPLES)
	samples[0] = -1
	samples[1] = 1
	var frame := Wire.frame("room.1", 0, 1, 1, samples)
	assert(frame.size() == 664 and Wire.valid(frame, "room.1") and not Wire.valid(frame, "room.2"))
	assert(absf(Wire.samples(frame)[0].x + 1.0) < 0.0001 and Wire.samples(frame)[1].x > 0.999)
	var audio := Audio.new()
	root.add_child(audio)
	assert(not audio.recording and audio.microphone == null)
	audio.start_capture() # Dummy input in CI; executes native adapter lifecycle without a real microphone.
	assert(audio.recording and audio.microphone.playing)
	audio.stop_capture()
	assert(not audio.recording and not audio.microphone.playing and audio.pending.is_empty())
	audio.start_capture()
	audio.stop_capture()
	frame[12] = 1
	for index in range(30):
		frame.encode_u32(18, index + 1)
		audio.receive(frame)
	assert(audio.speakers[1]["queue"].size() == 10)
	audio.clear_playback()
	assert(audio.speakers[1]["queue"].is_empty())
	audio.queue_free()
	touch.queue_free()
	await process_frame
	print("FRIENDS_LOCAL_CHECKS_OK")
	quit()
