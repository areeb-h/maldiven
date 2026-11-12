extends SceneTree
## Called locally by the PC launcher. Private key never enters an invite.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var now := int(Time.get_unix_time_from_system())
	var from_date := Time.get_datetime_string_from_unix_time(now - 86400).replace("-", "").replace(":", "").replace("T", "")
	var to_date := Time.get_datetime_string_from_unix_time(now + 365 * 86400).replace("-", "").replace(":", "").replace("T", "")
	var certificate := crypto.generate_self_signed_certificate(key, "CN=maldiven.local,O=Maldiven Friends Lab,C=MV", from_date, to_date)
	if certificate == null or key.save(args[0]) != OK or certificate.save(args[1]) != OK:
		quit(2)
		return
	if OS.get_name() == "Linux":
		FileAccess.set_unix_permissions(args[0], 384)
		FileAccess.set_unix_permissions(args[1], 384)
	quit()
