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
	invite_text.text = "MDV1." + Marshalls.raw_to_base64(Common.encode(payload))
	connect_invite() # Invalid embedded credential fails before making a network peer.
	await process_frame
	await process_frame
	await process_frame
	assert(menu_layer != null and invite.is_empty() and not finished and audio == null)
	assert(menu_message.text.begins_with("invalid ticket file"))
	print("FRIENDS_MENU_CHECKS_OK")
	quit()
