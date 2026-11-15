extends SceneTree
## Unit tests for NetAddress (what players type into Join by IP).

var failures := 0


func _initialize() -> void:
	var good := {
		"192.168.1.20": ["192.168.1.20", 24600],
		" 192.168.1.20 ": ["192.168.1.20", 24600],
		"192.168.1.20:24600": ["192.168.1.20", 24600],
		"100.92.33.25": ["100.92.33.25", 24600],
		"abc.joinmc.link:41234": ["abc.joinmc.link", 41234],
		"udp://abc.playit.gg:12345/": ["abc.playit.gg", 12345],
		"my-pc.tail1234.ts.net": ["my-pc.tail1234.ts.net", 24600],
		"localhost": ["localhost", 24600],
		"[fd7a:115c:a1e0::1]:24600": ["fd7a:115c:a1e0::1", 24600],
		"fd7a:115c:a1e0::1": ["fd7a:115c:a1e0::1", 24600],
	}
	for text in good:
		var r := NetAddress.parse(text)
		check(r.ok and r.host == good[text][0] and r.port == good[text][1], "parse %s -> %s" % [text, r])
	for text in ["", "   ", "192.168.1.300", "192.168.1", "abc:", "abc.playit.gg:0", "abc.playit.gg:70000",
			"host:port", "hello", "bad_name.example.com", "[fd7a::1", "-bad.example.com"]:
		check(not NetAddress.parse(text).ok, "reject '%s'" % text)
	check(NetAddress.explain("bad_port").contains("port"), "explain bad_port")
	if failures == 0:
		print("PASS: net address")
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", message)
