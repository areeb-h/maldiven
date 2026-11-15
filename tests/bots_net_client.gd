extends SceneTree
## Client side of the networked bot check (tools/test_bots.py). Runs the normal
## app (the main scene, so `--bot=client` joins and plays through
## scripts/dev/bot_driver.gd exactly like the other networked tests) and watches
## the round from this phone's point of view:
##   BOTS_ROSTER <n> <names>   the bots are in this client's roster, flagged
##   BOTS_MOVED <k>/<n> max=<m> how many bot avatars moved on this screen
##   BOTS_NAN <count>          non-finite bot positions seen (must be 0)
## Usage: godot --headless --path . --script res://tests/bots_net_client.gd -- --bot=client ...

var Net: Node  # the autoload (looked up at run time; see tests/bots_test.gd)
var _start := {}  # bot id -> first position seen
var _moved := {}  # bot id -> furthest distance from it
var _nan := 0
var _roster_reported := false
var _result_reported := false


func _initialize() -> void:
	call_deferred("_begin")


func _begin() -> void:
	Net = root.get_node("Net")
	root.add_child(load("res://scenes/main.tscn").instantiate())
	process_frame.connect(_watch)


func _watch() -> void:
	if not _roster_reported and Net.is_online() and not Net.is_host():
		var bots: Array = Net.bot_ids()
		if not bots.is_empty():
			_roster_reported = true
			var names := []
			for id in bots:
				names.append(str(Net.roster[id].name))
			print("BOTS_ROSTER %d %s" % [bots.size(), ",".join(names)])
	var world: Node = Net.world
	if world == null:
		return
	for id in Net.bot_ids():
		if not world.avatars.has(id):
			continue
		var at: Vector3 = world.avatars[id].global_position
		if not (is_finite(at.x) and is_finite(at.y) and is_finite(at.z)):
			_nan += 1
			continue
		if not _start.has(id):
			_start[id] = at
		_moved[id] = maxf(float(_moved.get(id, 0.0)), Vector2(at.x - _start[id].x, at.z - _start[id].z).length())
	if not _result_reported and world.rules.phase == StationRules.Phase.RESULT:
		_result_reported = true
		var moved := 0
		var furthest := 0.0
		for id in _moved:
			if float(_moved[id]) > 3.0:
				moved += 1
			furthest = maxf(furthest, float(_moved[id]))
		print("BOTS_MOVED %d/%d max=%.1f" % [moved, Net.bot_ids().size(), furthest])
		print("BOTS_NAN %d" % _nan)
