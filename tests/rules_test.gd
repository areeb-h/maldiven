extends SceneTree
## Headless unit tests for StationRules. Prints PASS/FAIL lines; exit 1 on failure.

var failures := 0


func _initialize() -> void:
	for test in [
		"test_roles_and_snapshot_privacy", "test_crew_win", "test_infiltrator_win",
		"test_vault_locked_until_power", "test_pod_infiltrator_only", "test_shove_drops_item",
		"test_shuttle_abort", "test_timeout_station_loss", "test_blackout", "test_disconnects",
		"test_mirror_prompts", "test_solo_walkaround", "test_layout_consistency",
	]:
		call(test)
	if failures == 0:
		print("PASS: rules (13 tests)")
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", message)


func make_round(count := 4, seed := 7) -> StationRules:
	var rules := StationRules.new()
	var roster := {}
	for id in range(1, count + 1):
		roster[id] = {"name": "P%d" % id, "color": Color.WHITE}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	rules.setup(roster, rng)
	rules.tick(StationRules.BRIEFING_SECONDS + 0.1)
	return rules


func go(rules: StationRules, id: int, flat: Vector2) -> void:
	rules.set_pose(id, Vector3(flat.x, 0, flat.y), 0.0)


func socket_front(socket_id: String) -> Vector2:
	var spec: Dictionary = StationLayout.SOCKETS[socket_id]
	return spec.pos + Vector2(sin(spec.facing), cos(spec.facing)) * 1.2


func crew_ids(rules: StationRules) -> Array:
	var out := []
	for id in rules.players:
		if rules.role_of(id) == StationRules.CREW:
			out.append(id)
	out.sort()
	return out


func restore_power(rules: StationRules, id: int) -> void:
	for index in range(3):
		var cell := "cell_%d" % (index + 1)
		var pos: Vector3 = rules.items[cell].pos
		go(rules, id, Vector2(pos.x, pos.z))
		check(rules.request_interact(id), "pick up " + cell)
		go(rules, id, socket_front("reactor_%d" % (index + 1)))
		check(rules.request_interact(id), "insert " + cell)


func test_roles_and_snapshot_privacy() -> void:
	var rules := make_round(6)
	var infiltrators := 0
	for id in rules.players:
		if rules.role_of(id) == StationRules.INFILTRATOR:
			infiltrators += 1
	check(infiltrators == 1, "exactly one infiltrator")
	var text := var_to_str(rules.public_snapshot())
	check(not text.contains("infiltrator"), "snapshot must not mention roles mid-round")
	check(not rules.public_snapshot().has("timeline"), "timeline withheld mid-round")


func test_crew_win() -> void:
	var rules := make_round()
	var crew: int = crew_ids(rules)[0]
	restore_power(rules, crew)
	check(rules.phase == StationRules.Phase.EXTRACTION, "power restores after 3 cells")
	go(rules, crew, socket_front("vault"))
	check(rules.request_interact(crew), "take core from vault")
	go(rules, crew, socket_front("shuttle"))
	check(rules.available_action(crew).get("action") == "insert", "shuttle prompt")
	check(rules.request_interact(crew), "load shuttle")
	rules.tick(StationRules.SHUTTLE_SECONDS + 0.1)
	check(rules.phase == StationRules.Phase.RESULT and rules.winner == StationRules.CREW, "crew wins on launch")
	var snap := rules.public_snapshot()
	check(snap.get("infiltrator", "") != "" and snap.timeline.size() > 5, "result reveals infiltrator + timeline")


func test_infiltrator_win() -> void:
	var rules := make_round()
	var bad := rules.infiltrator_id()
	restore_power(rules, bad)
	go(rules, bad, socket_front("vault"))
	rules.request_interact(bad)
	go(rules, bad, socket_front("pod"))
	check(rules.request_interact(bad), "infiltrator arms pod")
	check(rules.pod_left > 0.0, "pod countdown running")
	rules.tick(StationRules.POD_SECONDS + 0.1)
	check(rules.winner == StationRules.INFILTRATOR, "infiltrator wins on pod launch")


func test_vault_locked_until_power() -> void:
	var rules := make_round()
	var id: int = crew_ids(rules)[0]
	go(rules, id, socket_front("vault"))
	check(rules.available_action(id).is_empty(), "no vault action before power")
	check(not rules.request_interact(id), "vault locked before power")


func test_pod_infiltrator_only() -> void:
	var rules := make_round()
	var crew: int = crew_ids(rules)[0]
	restore_power(rules, crew)
	go(rules, crew, socket_front("vault"))
	rules.request_interact(crew)
	go(rules, crew, socket_front("pod"))
	check(rules.available_action(crew).get("label") == "Pod locked", "crew sees pod locked")
	check(not rules.request_interact(crew), "crew cannot arm pod")
	check(rules.pod_left < 0.0, "no countdown from crew")


func test_shove_drops_item() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	var carrier: int = ids[0]
	var shover: int = ids[1]
	var pos: Vector3 = rules.items.cell_1.pos
	go(rules, carrier, Vector2(pos.x, pos.z))
	rules.request_interact(carrier)
	rules.set_pose(shover, Vector3(pos.x, 0, pos.z - 1.0), 0.0)  # yaw 0 faces +z
	check(rules.request_shove(shover) == carrier, "shove hits target in front")
	check(rules.items.cell_1.holder == 0, "shoved player drops cell")
	check(rules.speed_factor(carrier) == 0.0, "shoved player stunned")
	check(rules.request_shove(shover) == 0, "shove cooldown")
	rules.tick(StationRules.SHOVE_COOLDOWN)
	rules.set_pose(shover, Vector3(pos.x, 0, pos.z + 1.0), 0.0)  # target now behind
	check(rules.request_shove(shover) == 0, "cannot shove someone behind you")
	var shoves := rules.drain_events().filter(func(e): return e.type == "shoved")
	check(shoves.size() == 1, "one shove event")


func test_shuttle_abort() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	restore_power(rules, ids[0])
	go(rules, ids[0], socket_front("vault"))
	rules.request_interact(ids[0])
	go(rules, ids[0], socket_front("shuttle"))
	rules.request_interact(ids[0])
	rules.tick(5.0)
	go(rules, ids[1], socket_front("shuttle"))
	check(rules.available_action(ids[1]).get("label") == "Pull core out", "pull prompt")
	check(rules.request_interact(ids[1]), "pull core from shuttle")
	check(rules.shuttle_left < 0.0, "launch aborted")
	rules.tick(StationRules.SHUTTLE_SECONDS)
	check(rules.phase == StationRules.Phase.EXTRACTION, "no win after abort")


func test_timeout_station_loss() -> void:
	var rules := make_round()
	rules.tick(StationRules.ROUND_SECONDS)
	check(rules.phase == StationRules.Phase.RESULT and rules.winner == "none", "timeout loses station")


func test_blackout() -> void:
	var rules := make_round()
	var bad := rules.infiltrator_id()
	var crew: int = crew_ids(rules)[0]
	check(not rules.request_sabotage(bad), "blackout not ready at start")
	rules.tick(StationRules.BLACKOUT_FIRST_DELAY)
	check(not rules.request_sabotage(crew), "crew cannot sabotage")
	check(rules.request_sabotage(bad), "infiltrator blackout")
	check(rules.is_blackout(), "blackout active")
	check(not rules.request_sabotage(bad), "blackout cooldown")
	rules.tick(StationRules.BLACKOUT_SECONDS + 0.1)
	check(not rules.is_blackout(), "blackout ends")


func test_disconnects() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	var pos: Vector3 = rules.items.cell_2.pos
	go(rules, ids[0], Vector2(pos.x, pos.z))
	rules.request_interact(ids[0])
	rules.remove_player(ids[0])
	check(rules.items.cell_2.holder == 0, "leaver drops item")
	check(rules.phase != StationRules.Phase.RESULT, "round continues when crew leaves")
	rules.remove_player(rules.infiltrator_id())
	check(rules.phase == StationRules.Phase.RESULT and rules.winner == "none", "infiltrator leaving interrupts")


func test_mirror_prompts() -> void:
	var rules := make_round()
	var bad := rules.infiltrator_id()
	var mirror := StationRules.new()
	mirror.apply_snapshot(rules.public_snapshot(), bad, StationRules.INFILTRATOR)
	check(mirror.role_of(bad) == StationRules.INFILTRATOR, "mirror knows own role")
	for id in mirror.players:
		if id != bad:
			check(mirror.role_of(id) == "", "mirror doesn't know other roles")
	var pos: Vector3 = mirror.items.cell_3.pos
	mirror.set_pose(bad, pos, 0.0)
	check(mirror.available_action(bad).get("label") == "Pick up cell", "mirror prompt matches host")


func test_solo_walkaround() -> void:
	var rules := make_round(1)
	check(rules.role_of(1) == StationRules.CREW, "solo player is crew")
	restore_power(rules, 1)
	check(rules.phase == StationRules.Phase.EXTRACTION, "solo can restore power")


func test_layout_consistency() -> void:
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		check(StationLayout.room_at(StationLayout.to_world(spec.pos)) == spec.room, socket_id + " inside its room")
		check(StationLayout.is_walkable(StationLayout.to_world(socket_front(socket_id))), socket_id + " approach walkable")
	for item_id in StationLayout.ITEMS:
		var spec: Dictionary = StationLayout.ITEMS[item_id]
		if spec.has("pos"):
			check(StationLayout.is_walkable(StationLayout.to_world(spec.pos)), item_id + " spawn walkable")
	for corridor_id in StationLayout.CORRIDORS:
		var corridor: Dictionary = StationLayout.CORRIDORS[corridor_id]
		var rect := StationLayout.corridor_rect(corridor_id)
		for room_id in [corridor.a, corridor.b]:
			var room := StationLayout.room_rect(room_id)
			check(room.grow(0.01).intersects(rect), "%s touches %s" % [corridor_id, room_id])
