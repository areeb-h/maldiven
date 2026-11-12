extends "res://phone_client.gd"
## Desktop CI driver only; excluded from the phone APK. Never opens a microphone.
var diagnostic_id := ""
var sample_at := 0
var received_before := 0

func granted(burst: int) -> void:
	Common.event({"event": "voice_grant_received", "burst": burst})

func _process(delta: float) -> bool:
	super._process(delta)
	if admitted_msec < 0 or leaving or finished:
		return false
	var command: Dictionary = control.get("voice_command", {})
	if str(command.get("id", "")) != diagnostic_id:
		diagnostic_id = str(command.get("id", ""))
		match command.get("action", ""):
			"start":
				microphone_allowed = bool(command.get("permission", true))
				voice_channel = int(command.get("channel", 0))
				talk_changed(true)
			"stop":
				stop_talking()
			"focus_out":
				_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"focus_in":
				_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			"mute":
				voice_muted = true
				ensure_audio()
				audio.muted = true
				audio.clear_playback()
				stop_talking()
			"frames":
				for count in range(mini(int(command.get("count", 1)), 180)):
					voice_sequence += 1
					var samples := PackedFloat32Array()
					samples.resize(Wire.SAMPLES)
					for index in range(Wire.SAMPLES):
						samples[index] = sin(TAU * 440.0 * float(index) / 16000.0) * 0.15
					var packet := Wire.frame(str(command.get("epoch", join["room_epoch"])), voice_channel, int(command.get("burst", voice_burst)), int(command.get("seq", voice_sequence)), samples)
					packet[12] = int(command.get("speaker", 255))
					if command.has("size"):
						packet.resize(int(command["size"]))
					api.send_bytes(packet, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE if command.get("reliable", false) else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)
			"raw_control":
				api.send_bytes(Common.encode(command["packet"]), 1)
		Common.event({"event": "voice_command_done", "id": diagnostic_id, "talk_held": talk_held, "granted": voice_granted})
	if Time.get_ticks_msec() - sample_at >= 100:
		sample_at = Time.get_ticks_msec()
		ensure_audio()
		Common.event({"event": "voice_playback", "received": audio.received_frames, "played": audio.played_frames, "capturing": audio.recording, "held": talk_held, "granted": voice_granted})
	return false
