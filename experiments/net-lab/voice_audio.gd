extends Node
## Native lab adapter. Headphones required for the first test: no AEC or codec.
signal frame_ready(samples: PackedFloat32Array)
const Wire = preload("res://voice_wire.gd")
var capture: AudioEffectCapture
var microphone: AudioStreamPlayer
var capture_bus := -1
var recording := false
var pending := PackedFloat32Array()
var phase := 0.0
var speakers := {}
var muted := false
var received_frames := 0
var played_frames := 0

func start_capture() -> void:
	if recording:
		return
	if capture_bus < 0:
		capture_bus = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(capture_bus, "FriendsMic")
		capture = AudioEffectCapture.new()
		capture.buffer_length = 0.12
		AudioServer.add_bus_effect(capture_bus, capture)
		# Effects run before bus volume. The microphone is never monitored.
		AudioServer.set_bus_volume_linear(capture_bus, 0.0)
		microphone = AudioStreamPlayer.new()
		microphone.stream = AudioStreamMicrophone.new()
		microphone.bus = "FriendsMic"
		add_child(microphone)
	capture.clear_buffer()
	pending.clear()
	phase = 0
	recording = true
	microphone.play()

func stop_capture() -> void:
	recording = false
	if microphone != null:
		microphone.stop()
	if capture != null:
		capture.clear_buffer()
	pending.clear()
	phase = 0

func receive(data: PackedByteArray) -> void:
	if muted:
		return
	var id := int(data[12])
	var burst := int(data.decode_u32(14))
	var seq := int(data.decode_u32(18))
	if not speakers.has(id):
		var player := AudioStreamPlayer.new()
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = 16000
		stream.buffer_length = 0.12
		player.stream = stream
		add_child(player)
		speakers[id] = {"player": player, "queue": [], "burst": 0, "seq": 0, "at": 0}
	var state: Dictionary = speakers[id]
	if burst < int(state["burst"]) or (burst == int(state["burst"]) and seq <= int(state["seq"])):
		return
	if burst != int(state["burst"]) or Time.get_ticks_msec() - int(state["at"]) > 250:
		state["queue"].clear()
		state["player"].stop()
	state["burst"] = burst
	state["seq"] = seq
	state["at"] = Time.get_ticks_msec()
	if state["queue"].size() >= 10:
		state["queue"].pop_front()
	state["queue"].append(Wire.samples(data))
	received_frames += 1

func clear_playback() -> void:
	for state in speakers.values():
		state["queue"].clear()
		state["player"].stop()

func _process(_delta: float) -> void:
	if recording:
		var frames := capture.get_frames_available()
		if frames > 0:
			var samples := capture.get_buffer(mini(frames, 8192))
			var ratio := 16000.0 / float(AudioServer.get_input_mix_rate())
			for stereo in samples:
				phase += ratio
				if phase >= 1.0:
					phase -= 1.0
					pending.append((stereo.x + stereo.y) * 0.5)
					if pending.size() == Wire.SAMPLES:
						frame_ready.emit(pending)
						pending = PackedFloat32Array()
	for state in speakers.values():
		if Time.get_ticks_msec() - int(state["at"]) > 250:
			state["queue"].clear()
			state["player"].stop()
			continue
		if not state["player"].playing and state["queue"].size() >= 2:
			state["player"].play()
		if state["player"].playing:
			var playback: AudioStreamGeneratorPlayback = state["player"].get_stream_playback()
			while not state["queue"].is_empty() and playback.can_push_buffer(Wire.SAMPLES):
				playback.push_buffer(state["queue"].pop_front())
				played_frames += 1

func _exit_tree() -> void:
	stop_capture()
	clear_playback()
	if capture_bus >= 0:
		AudioServer.remove_bus(capture_bus)
