extends SceneTree
## Headless bot checks (run with --fixed-fps 60, so simulated time runs at a
## fixed 60 Hz as fast as the machine allows):
##   - the waypoint graph (layout-only and physics-checked) connects every room
##     and reaches every socket approach point from Commons;
##   - a real StationWorld on a host with 1 stationary "human" (the host's own
##     player) plus 3 bots: the bots deliver all 3 cells, power comes back, and
##     the round reaches a result within 6 simulated minutes; no NaN positions,
##     no bot stuck for more than 5 s, and nothing is ever sent to a bot id.
## User args (after --): --seeds=11,23 (one round per seed), --skill=normal.

const DT := 1.0 / 60.0
const POWER_LIMIT := 240.0  # s of round time
const RESULT_LIMIT := 360.0
const STUCK_LIMIT := 5.0

var failures := 0
var checks := 0
var Net: Node  # the autoload (globals for autoloads don't exist yet when a --script compiles)


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)


func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			out[parts[0]] = parts[1] if parts.size() > 1 else "1"
	return out


func _run() -> void:
	var args := _args()
	Net = root.get_node("Net")
	test_layout_graph()
	if not _host():
		print("FAIL: could not open a local ENet host")
		quit(1)
		return
	test_roster()
	var seeds: PackedStringArray = str(args.get("seeds", "11")).split(",")
	for seed_text in seeds:
		await test_round(int(seed_text), str(args.get("skill", "normal")))
	Net.leave()
	if failures == 0:
		print("PASS: bots (%d checks)" % checks)
	quit(1 if failures else 0)


## Host on a free private port (never the game's 24600, so this can run next
## to networked tests). No client ever connects: any RPC aimed at a bot id
## would print an "unknown peer" error, which tools/test_station.py rejects.
func _host() -> bool:
	for attempt in range(20):
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(25100 + randi() % 800, 8) == OK:
			root.multiplayer.multiplayer_peer = peer
			Net.roster = {1: {"name": "Tester", "color": Net.PALETTE[0]}}
			Net.in_round = false
			return true
	return false


func test_layout_graph() -> void:
	var nav := BotNav.new()
	nav.build(null)
	_check_graph(nav, "layout graph")


func _check_graph(nav: BotNav, label: String) -> void:
	check(nav.points.size() > 100, "%s: only %d points" % [label, nav.points.size()])
	check(nav.rooms_connected(), "%s: some room is unreachable" % label)
	for room_id in StationLayout.ROOMS:
		check(nav.room_point.get(room_id, -1) >= 0, "%s: room %s has no point" % [label, room_id])
	var commons: Vector3 = nav.points[nav.room_point.commons]
	for socket_id in StationLayout.SOCKETS:
		var target := BotNav.approach_of(socket_id)
		var route := nav.path(commons, target)
		check(not route.is_empty() and route[route.size() - 1].distance_to(target) < 0.01,
			"%s: no path from Commons to the %s approach point" % [label, socket_id])
		var length := nav.route_length(commons, target)
		var straight := Vector2(target.x - commons.x, target.z - commons.z).length()
		check(length < straight * 2.6 + 12.0, "%s: path to %s is %.0f m (straight %.0f m)" % [label, socket_id, length, straight])
	for item_id in StationLayout.ITEMS:
		if StationLayout.ITEMS[item_id].has("pos"):
			var at := StationLayout.to_world(StationLayout.ITEMS[item_id].pos)
			check(not nav.path(commons, at).is_empty(), "%s: no path to %s" % [label, item_id])
	var bad := 0
	for p in nav.points:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			bad += 1
	check(bad == 0, "%s: %d non-finite points" % [label, bad])


func test_roster() -> void:
	for i in range(3):
		check(Net.add_bot("normal") >= Net.BOT_ID_BASE, "add_bot %d" % i)
	check(Net.bot_ids().size() == 3 and Net.human_count() == 1, "roster: 1 human + 3 bots")
	var names := {}
	var colors := {}
	for id in Net.roster:
		names[Net.roster[id].name] = true
		colors[Net.roster[id].color] = true
	check(names.size() == 4 and colors.size() == 4, "bots get unique names and colours")
	# Seats: bots count toward the limit, and come off again.
	var extra := []
	while true:
		var id: int = Net.add_bot()
		if id == 0:
			break
		extra.append(id)
	check(Net.roster.size() == Net.max_players, "bots fill up to max_players (%d)" % Net.roster.size())
	for id in extra:
		check(Net.remove_bot(id), "remove_bot %d" % id)
	check(Net.roster.size() == 4, "roster back to 4 after removals")
	check(Net.peer_rtt(Net.bot_ids()[0]) == 0.0, "peer_rtt of a bot is 0")


func test_round(seed_value: int, skill_name: String) -> void:
	for id in Net.bot_ids():
		Net.roster[id].skill = skill_name
	Net.in_round = true
	# Scripts that use the Net autoload load only now (see the Net var above).
	var world: Node3D = load("res://scripts/world.gd").new(seed_value)
	root.add_child(world)
	await physics_frame
	var bots: Node = world.bots
	check(bots != null and bots.brains.size() == 3, "seed %d: a bot controller with 3 brains" % seed_value)
	if bots == null:
		return
	bots.debug = true
	var roles := []
	for id in world.rules.players:
		roles.append(world.rules.role_of(id))
	check(roles.count(StationRules.INFILTRATOR) == 1, "seed %d: exactly one infiltrator" % seed_value)
	var infiltrator: int = world.rules.infiltrator_id()
	print("seed %d: infiltrator is %s" % [seed_value, world.rules.players[infiltrator].name])
	var power_at := -1.0
	var anchors := {}  # id -> [position, rules time] of the last real progress
	var worst_stuck := 0.0
	var nan_seen := false
	var report_at := 30.0
	var started := Time.get_ticks_msec()
	var human: Node3D = world.local
	while world.rules.phase != StationRules.Phase.RESULT and world.rules.elapsed < RESULT_LIMIT:
		await physics_frame
		var t: float = world.rules.elapsed
		if power_at < 0.0 and world.rules.phase >= StationRules.Phase.EXTRACTION:
			power_at = t
			print("  power restored at %.1f s" % t)
		for id in bots.brains:
			var brain: RefCounted = bots.brains[id]
			var at: Vector3 = brain.avatar.global_position
			if not (is_finite(at.x) and is_finite(at.y) and is_finite(at.z)):
				nan_seen = true
			var travelling: bool = brain.wants_progress() and world.rules.state_of(id) == StationRules.OK \
				and float(world.rules.players[id].stunned_until) <= t
			if not anchors.has(id) or not travelling or Vector2(at.x - anchors[id][0].x, at.z - anchors[id][0].z).length() > 1.5:
				anchors[id] = [at, t]
			else:
				var stuck: float = t - float(anchors[id][1])
				if stuck > worst_stuck:
					worst_stuck = stuck
				if stuck > STUCK_LIMIT:
					print("  STUCK: %s at %s %s core=%s/%s" % [world.rules.players[id].name, at, brain.debug_line(),
						world.rules.items.core.pos, world.rules.items.core.holder])
					anchors[id] = [at, t]
		if human != null:
			human.move_input = Vector2.ZERO  # the stationary human
		if t >= report_at:
			report_at += 30.0
			_report(world, t)
	var wall := (Time.get_ticks_msec() - started) / 1000.0
	_report(world, world.rules.elapsed)
	print("  result after %.1f s (%.0f s wall): winner=%s reason=%s" % [world.rules.elapsed, wall,
		world.rules.winner, world.rules.reason])
	check(power_at >= 0.0 and power_at <= POWER_LIMIT, "seed %d: power restored within %.0f s (at %.1f)" % [seed_value, POWER_LIMIT, power_at])
	check(world.rules.powered_cells() == 3, "seed %d: all 3 cells delivered" % seed_value)
	check(world.rules.phase == StationRules.Phase.RESULT, "seed %d: a result within %.0f s" % [seed_value, RESULT_LIMIT])
	check(world.rules.winner in [StationRules.CREW, StationRules.INFILTRATOR],
		"seed %d: crew shuttle or infiltrator pod (got %s: %s)" % [seed_value, world.rules.winner, world.rules.reason])
	check(not nan_seen, "seed %d: no NaN positions" % seed_value)
	check(worst_stuck <= STUCK_LIMIT, "seed %d: no bot stuck for more than %.0f s (worst %.1f s)" % [seed_value, STUCK_LIMIT, worst_stuck])
	_check_graph(bots.nav, "physics graph")
	for id in world.rules.players:
		var p: Vector3 = world.rules.players[id].pos
		check(is_finite(p.x) and is_finite(p.z), "seed %d: finite rules pose for %d" % [seed_value, id])
	for line in world.rules.timeline:
		print("    ", line)
	world.queue_free()
	Net.world = null
	Net.in_round = false
	await process_frame
	await process_frame


func _report(world: Node3D, t: float) -> void:
	var parts := []
	for id in world.bots.brains:
		var brain: RefCounted = world.bots.brains[id]
		var p: Dictionary = world.rules.players[id]
		parts.append("%s[%s %s %s held=%s stuck=%.1f unsticks=%d]" % [p.name, world.rules.role_of(id).substr(0, 3), p.state,
			brain.goal.get("kind"), p.holding, brain.max_stuck, brain.unsticks])
	print("  t=%5.1f phase=%d cells=%d core=%s/%d  %s" % [t, world.rules.phase, world.rules.powered_cells(),
		world.rules.items.core.socket, world.rules.items.core.holder, " ".join(parts)])
