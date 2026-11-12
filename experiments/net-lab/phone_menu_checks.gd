extends "res://phone_client.gd"
func start() -> void:
	super.start()
	call_deferred("exercise_menu")

func exercise_menu() -> void:
	assert(interactive and menu_layer != null and audio == null and peer == null)
	invite_text.text = "bad invite"
	connect_invite()
	assert(menu_message.text.begins_with("Invalid invite"))
	assert(parse_invite("MDV1.====").is_empty())
	var payload := {"host": "127.0.0.1", "port": 24567, "certificate": "unused", "credential": {}}
	var complete := "MDV1." + Marshalls.raw_to_base64(Common.encode(payload))
	invite_text.text = complete
	assert(not load_pasted_invite(""))
	assert(invite_text.text == complete) # A blocked clipboard must not erase typed/imported text.
	var wrapped := "\ufeff```\n" + complete.substr(0, 60) + "\r\n" + complete.substr(60) + "\n```"
	assert(not parse_invite(wrapped).is_empty())
	assert(load_pasted_invite(wrapped))
	assert(invite_feedback.text.begins_with("Invite ready"))
	assert(parse_invite(complete.trim_suffix("=").trim_suffix("=")) == parse_invite(complete))
	var file := FileAccess.open("user://menu-test-invite.txt", FileAccess.WRITE)
	file.store_string(complete + "\n")
	file.close()
	load_invite_file("user://menu-test-invite.txt")
	assert(menu_message.text.begins_with("Invite file loaded"))
	assert(invite_text.text == complete)
	load_invite_file("user://menu-test-missing-invite.txt")
	assert(invite_text.text == complete)
	assert(invite_picker.use_native_dialog and invite_picker.access == FileDialog.ACCESS_FILESYSTEM)
	assert(audio == null and peer == null)
	DirAccess.remove_absolute("user://menu-test-invite.txt")
	invite_text.text = complete
	connect_invite() # Invalid embedded credential fails before making a network peer.
	await process_frame
	await process_frame
	await process_frame
	assert(menu_layer != null and invite.is_empty() and not finished and audio == null)
	assert(menu_message.text.begins_with("invalid ticket file"))
	print("FRIENDS_MENU_CHECKS_OK")
	quit()
