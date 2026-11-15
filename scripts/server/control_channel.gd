extends RefCounted
## Localhost control link between the dedicated server and tools/host_station.py.
##
## Newline-delimited JSON over TCP on 127.0.0.1 only (never the LAN). One
## controller at a time; a newer connection replaces an older one, so the
## launcher can reconnect. When a token is set, the first line must be
## {"hello": "<token>"}; anything else closes the connection.
##   launcher -> server: {"id": 7, "cmd": "start_round", "args": {}}
##   server -> launcher: {"type": "status", ...} every 0.5 s and after changes,
##                       {"type": "reply", "id": 7, "ok": true} (or "error": "...")
## Writes never block the game: output is queued and sent in pieces, and a
## controller that stops reading (more than MAX_BACKLOG queued) is dropped.

const MAX_LINE := 65536
const MAX_BACKLOG := 1 << 20

var token := ""
var port := 0
var had_controller := false
var lost_ms := -1  # ticks when the last controller went away (-1: connected or never)
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _authed := false
var _inbox := PackedByteArray()
var _outbox := PackedByteArray()


func listen(at_port: int, with_token: String) -> Error:
	token = with_token
	port = at_port
	return _server.listen(at_port, "127.0.0.1")


func connected() -> bool:
	return _peer != null and _authed


## Accepts connections, reads and flushes. Returns the commands that arrived.
func poll() -> Array:
	var commands := []
	while _server.is_listening() and _server.is_connection_available():
		var incoming := _server.take_connection()
		if incoming == null:
			break
		_drop()
		_peer = incoming
		_peer.set_no_delay(true)
		_authed = token.is_empty()
		if _authed:
			_on_authed()
	if _peer == null:
		return commands
	_peer.poll()
	var status := _peer.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		if status != StreamPeerTCP.STATUS_CONNECTING:
			_lost()
		return commands
	var available := _peer.get_available_bytes()
	if available > 0:
		var chunk: Array = _peer.get_partial_data(available)
		if chunk[0] == OK:
			_inbox.append_array(chunk[1])
	while _peer != null:
		var newline := _inbox.find(10)
		if newline < 0:
			if _inbox.size() > MAX_LINE:
				_lost()
			break
		var line := _inbox.slice(0, newline).get_string_from_utf8().strip_edges()
		_inbox = _inbox.slice(newline + 1)
		if line.is_empty():
			continue
		var message: Variant = JSON.parse_string(line)
		if typeof(message) != TYPE_DICTIONARY:
			continue
		if not _authed:
			if str(message.get("hello", "")) == token:
				_authed = true
				_on_authed()
			else:
				_lost()
			continue
		if message.has("cmd"):
			commands.append(message)
	_flush()
	return commands


func send(message: Dictionary) -> void:
	if not connected():
		return
	_outbox.append_array((JSON.stringify(message) + "\n").to_utf8_buffer())
	if _outbox.size() > MAX_BACKLOG:
		_lost()
		return
	_flush()


func reply(command: Dictionary, ok: bool, error := "") -> void:
	var message := {"type": "reply", "id": command.get("id", 0), "ok": ok}
	if not error.is_empty():
		message.error = error
	send(message)


func close() -> void:
	_flush()
	_drop()
	_server.stop()


func _flush() -> void:
	if _peer == null or _outbox.is_empty():
		return
	var sent: Array = _peer.put_partial_data(_outbox)
	if sent[0] != OK:
		_lost()
		return
	_outbox = _outbox.slice(int(sent[1]))


func _on_authed() -> void:
	had_controller = true
	lost_ms = -1


func _lost() -> void:
	var was_authed := _authed
	_drop()
	if was_authed:
		lost_ms = Time.get_ticks_msec()


func _drop() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_authed = false
	_inbox = PackedByteArray()
	_outbox = PackedByteArray()
