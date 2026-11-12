extends RefCounted
## Bounded JSON only. This admission protocol is separate from gameplay commands.
const MAX_AUTH_BYTES := 1024
const MAX_APP_BYTES := 256

static func options() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var result := {}
	if args.size() % 2 != 0:
		return {}
	for index in range(0, args.size(), 2):
		if not args[index].begins_with("--") or result.has(args[index]):
			return {}
		result[args[index]] = args[index + 1]
	return result

static func compatibility() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://compatibility.json"))

static func decode(data: PackedByteArray, limit: int) -> Dictionary:
	if data.is_empty() or data.size() > limit:
		return {}
	# Our envelope is ASCII. Avoid invalid UTF-8 decoding and object deserialisation.
	for byte in data:
		if byte > 127 or byte == 0:
			return {}
	var parser := JSON.new()
	if parser.parse(data.get_string_from_ascii()) != OK:
		return {}
	var value: Variant = parser.data
	return value if value is Dictionary else {}

static func exact_keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and value.has_all(keys)

static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func hex_token(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

static func encode(value: Dictionary) -> PackedByteArray:
	return JSON.stringify(value).to_utf8_buffer()

static func event(value: Dictionary) -> void:
	# Never pass a ticket or untrusted packet into this event/log function.
	print("NETLAB ", JSON.stringify(value))

static func write_private(path: String, value: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value) + "\n")
	file.close()
	if OS.get_name() == "Linux":
		return FileAccess.set_unix_permissions(path, 384) # 0600
	return OK
