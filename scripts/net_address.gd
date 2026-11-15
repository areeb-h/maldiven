class_name NetAddress
extends RefCounted
## Parses what a player types into "Join by IP": a LAN IP, a Tailscale IP or
## MagicDNS name, or a public tunnel address such as playit.gg's
## "name.playit.gg:12345". Accepts an optional ":port" and tolerates pasted
## junk like "udp://", whitespace or a trailing slash.
##
##   NetAddress.parse("192.168.1.20")            -> {ok, host "192.168.1.20", port 24600}
##   NetAddress.parse("abc.joinmc.link:41234")   -> {ok, host "abc.joinmc.link", port 41234}
##   NetAddress.parse("[fd7a::1]:24600")         -> {ok, host "fd7a::1", port 24600}

const DEFAULT_PORT := 24600


## Returns {ok: bool, host: String, port: int, error: String}.
static func parse(text: String, default_port := DEFAULT_PORT) -> Dictionary:
	var clean := text.strip_edges()
	for prefix in ["udp://", "enet://", "http://", "https://"]:
		if clean.to_lower().begins_with(prefix):
			clean = clean.substr(prefix.length())
	clean = clean.trim_suffix("/").strip_edges()
	if clean.is_empty():
		return _fail("empty")
	var host := clean
	var port := default_port
	if clean.begins_with("["):
		# Bracketed IPv6, optionally with a port: [addr]:port
		var close := clean.find("]")
		if close < 0:
			return _fail("bad_ipv6")
		host = clean.substr(1, close - 1)
		var rest := clean.substr(close + 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return _fail("bad_port")
			var parsed := _port(rest.substr(1))
			if parsed < 0:
				return _fail("bad_port")
			port = parsed
	elif clean.count(":") == 1:
		var parts := clean.split(":")
		host = parts[0]
		var parsed := _port(parts[1])
		if parsed < 0:
			return _fail("bad_port")
		port = parsed
	elif clean.count(":") > 1:
		host = clean  # bare IPv6 without a port
	if host.is_empty():
		return _fail("empty")
	if host.is_valid_ip_address() or _is_hostname(host):
		return {"ok": true, "host": host, "port": port, "error": ""}
	return _fail("bad_host")


## Friendly sentence for a parse error code.
static func explain(error: String) -> String:
	match error:
		"empty":
			return "Type the host's address. It's on their lobby screen or the server panel."
		"bad_port":
			return "The port after the colon must be a number from 1 to 65535, like abc.playit.gg:12345."
		"bad_ipv6":
			return "That IPv6 address is missing its closing bracket."
		_:
			return "Use an IP like 192.168.1.20, or a name with a port like abc.playit.gg:12345."


static func _port(text: String) -> int:
	if not text.is_valid_int():
		return -1
	var value := int(text)
	return value if value >= 1 and value <= 65535 else -1


static func _is_hostname(host: String) -> bool:
	if host.length() > 253 or host == "localhost":
		return host == "localhost"
	# A dotted all-numeric string that isn't a valid IP (e.g. 192.168.1.300)
	# is a typo, not a hostname.
	var numeric := true
	for part in host.split("."):
		if not part.is_valid_int():
			numeric = false
	if numeric:
		return false
	var labels := host.split(".")
	if labels.size() < 2:
		return false  # single words are almost always typos; LAN names use IPs here
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789-"
	for label in labels:
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return false
		for character in label.to_lower():
			if not allowed.contains(character):
				return false
	return true


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "host": "", "port": 0, "error": error}
