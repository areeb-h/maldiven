extends SceneTree
## Headless unit tests for StationRules. Prints PASS/FAIL lines; exit 1 on failure.

var failures := 0


func _initialize() -> void:
	for test in [
		"test_roles_and_snapshot_privacy", "test_crew_win", "test_infiltrator_win",
		"test_vault_locked_until_power", "test_pod_infiltrator_only", "test_shove_drops_item",
		"test_shuttle_abort", "test_timeout_station_loss", "test_blackout", "test_disconnects",
		"test_mirror_prompts", "test_solo_walkaround", "test_layout_consistency",
		"test_gun_locked_until_power", "test_shoot_downs_target", "test_shot_needs_aim_and_los",
		"test_drag_and_medbay_revive", "test_downed_recovers", "test_airlock_spaces_infiltrator",
		"test_airlock_spaces_last_crew", "test_airlock_respawns_items", "test_throw_hits_and_stuns",
		"test_throw_respects_walls", "test_shove_drops_body", "test_mirror_flight_and_downed",
		"test_last_crew_leaving_ends_round", "test_blackout_hides_names", "test_setup_resets_state",
		"test_shove_cooldown_in_snapshot",
	]:
		call(test)
	if failures == 0:
		print("PASS: rules (29 tests)")
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


func power_and_gun(rules: StationRules, id: int) -> void:
	restore_power(rules, id)
	go(rules, id, socket_front("armory"))
	check(rules.request_interact(id), "take gun")
	check(rules.holds_gun(id), "holding gun")


func face(rules: StationRules, id: int, at: Vector3, target: Vector3) -> void:
	var offset := target - at
	rules.set_pose(id, at, atan2(offset.x, offset.z))


func test_gun_locked_until_power() -> void:
	var rules := make_round()
	var id: int = crew_ids(rules)[0]
	go(rules, id, socket_front("armory"))
	check(not rules.request_interact(id), "armory locked before power")


func test_shoot_downs_target() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	power_and_gun(rules, ids[0])
	var shooter_at := Vector3(0, 0, 0)
	var target_at := Vector3(0, 0, 8)
	rules.set_pose(ids[1], target_at, 0.0)
	face(rules, ids[0], shooter_at, target_at)
	check(rules.request_shoot(ids[0]) == ids[1], "shot hits target in front")
	check(rules.state_of(ids[1]) == StationRules.DOWNED, "target downed")
	check(rules.gun_ammo() == StationRules.GUN_AMMO - 1, "ammo spent")
	check(rules.request_shoot(ids[0]) == -1, "gun cooldown")
	rules.tick(StationRules.GUN_COOLDOWN)
	check(rules.request_shoot(ids[0]) == 0, "no standing target -> miss")
	rules.tick(StationRules.GUN_COOLDOWN)
	rules.request_shoot(ids[0])
	rules.tick(StationRules.GUN_COOLDOWN)
	check(rules.request_shoot(ids[0]) == -1, "out of ammo")
	check(rules.speed_factor(ids[1]) == 0.0, "downed can't move")
	check(rules.available_action(ids[1]).is_empty(), "downed can't interact")


func test_shot_needs_aim_and_los() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	power_and_gun(rules, ids[0])
	rules.set_pose(ids[1], Vector3(8, 0, 0), 0.0)
	rules.set_pose(ids[0], Vector3.ZERO, 0.0)  # facing +z, target at +x
	check(rules.request_shoot(ids[0]) == 0, "target outside cone missed")
	rules.tick(StationRules.GUN_COOLDOWN)
	face(rules, ids[0], Vector3.ZERO, Vector3(8, 0, 0))
	var walls := func(_a: Vector3, _b: Vector3) -> bool: return false
	check(rules.request_shoot(ids[0], walls) == 0, "wall blocks the shot")
	check(rules.state_of(ids[1]) == StationRules.OK, "blocked target unharmed")


func test_drag_and_medbay_revive() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	power_and_gun(rules, ids[0])
	rules.set_pose(ids[1], Vector3(0, 0, 6), 0.0)
	face(rules, ids[0], Vector3.ZERO, Vector3(0, 0, 6))
	rules.request_shoot(ids[0])
	var medic: int = ids[2]
	rules.set_pose(medic, Vector3(0, 0, 5), 0.0)
	check(rules.available_action(medic).get("action") == "drag", "drag prompt")
	check(rules.request_interact(medic), "start drag")
	check(rules.players[ids[1]].carried_by == medic, "body attached")
	check(rules.speed_factor(medic) == StationRules.CARRY_SPEED.body, "dragging is slow")
	go(rules, medic, socket_front("medbay"))
	check(rules.players[ids[1]].pos.distance_to(rules.players[medic].pos) < 1.0, "body follows carrier")
	check(rules.available_action(medic).get("action") == "revive", "revive prompt at medbay")
	check(rules.request_interact(medic), "revive")
	check(rules.state_of(ids[1]) == StationRules.OK and rules.players[medic].body == 0, "revived and released")


func test_downed_recovers() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	power_and_gun(rules, ids[0])
	rules.set_pose(ids[1], Vector3(0, 0, 6), 0.0)
	face(rules, ids[0], Vector3.ZERO, Vector3(0, 0, 6))
	rules.request_shoot(ids[0])
	rules.tick(StationRules.DOWN_SECONDS + 0.1)
	check(rules.state_of(ids[1]) == StationRules.OK, "auto recovery")


func put_in_airlock(rules: StationRules, id: int) -> void:
	rules.players[id].pos = StationLayout.to_world(StationLayout.ROOMS.airlock.center)


func cycle_airlock(rules: StationRules, operator: int) -> void:
	go(rules, operator, socket_front("airlock_console"))
	check(rules.available_action(operator).get("action") == "airlock", "airlock prompt")
	check(rules.request_interact(operator), "cycle airlock")
	rules.tick(StationRules.AIRLOCK_WARNING + 0.05)


func test_airlock_spaces_infiltrator() -> void:
	var rules := make_round()
	var bad := rules.infiltrator_id()
	put_in_airlock(rules, bad)
	cycle_airlock(rules, crew_ids(rules)[0])
	check(rules.state_of(bad) == StationRules.DEAD, "infiltrator spaced")
	check(rules.winner == StationRules.CREW, "crew win by spacing infiltrator")


func test_airlock_spaces_last_crew() -> void:
	var rules := make_round(2)
	var bad := rules.infiltrator_id()
	var crew: int = crew_ids(rules)[0]
	put_in_airlock(rules, crew)
	cycle_airlock(rules, bad)
	check(rules.state_of(crew) == StationRules.DEAD, "crew spaced")
	check(rules.winner == StationRules.INFILTRATOR, "infiltrator wins when no crew left")


func test_airlock_respawns_items() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	rules.items.cell_1.pos = StationLayout.to_world(StationLayout.ROOMS.airlock.center)
	cycle_airlock(rules, ids[0])
	check(StationLayout.room_at(rules.items.cell_1.pos) == "engineering", "vented cell returns to spawn")
	check(rules.phase != StationRules.Phase.RESULT, "empty vent doesn't end round")
	check(rules.available_action(ids[0]).is_empty() or rules.available_action(ids[0]).get("action") != "airlock", "airlock on cooldown")
	rules.tick(StationRules.AIRLOCK_COOLDOWN + 0.1)
	check(rules.airlock_ready(), "airlock ready again")


func test_throw_hits_and_stuns() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	var pos: Vector3 = rules.items.cell_1.pos
	go(rules, ids[0], Vector2(pos.x, pos.z))
	rules.request_interact(ids[0])
	var thrower_at := Vector3(62, 0, -4)
	face(rules, ids[0], thrower_at, Vector3(62, 0, 4))
	rules.set_pose(ids[1], Vector3(62, 0, 0.5), 0.0)
	rules.request_shove(ids[0])
	check(rules.items.cell_1.holder == 0 and not rules.items.cell_1.flight.is_empty(), "cell in flight")
	for i in range(12):
		rules.tick(0.05)
	check(rules.items.cell_1.flight.is_empty(), "flight finished")
	check(rules.players[ids[1]].stunned_until > rules.elapsed, "hit player stunned")


func test_throw_respects_walls() -> void:
	var rules := make_round()
	var id: int = crew_ids(rules)[0]
	var pos: Vector3 = rules.items.cell_2.pos  # Medical
	go(rules, id, Vector2(pos.x, pos.z))
	rules.request_interact(id)
	face(rules, id, Vector3(-5, 0, 24), Vector3(-30, 0, 24))  # towards the outer wall
	rules.request_shove(id)
	check(StationLayout.is_walkable(rules.items.cell_2.flight.to), "landing stays inside the station")


func test_shove_drops_body() -> void:
	var rules := make_round(5)
	var ids := crew_ids(rules)
	power_and_gun(rules, ids[0])
	rules.set_pose(ids[1], Vector3(0, 0, 6), 0.0)
	face(rules, ids[0], Vector3.ZERO, Vector3(0, 0, 6))
	rules.request_shoot(ids[0])
	rules.set_pose(ids[2], Vector3(0, 0, 5), 0.0)
	rules.request_interact(ids[2])
	rules.tick(StationRules.SHOVE_COOLDOWN)
	rules.set_pose(ids[3], Vector3(0, 0, 4), 0.0)
	check(rules.request_shove(ids[3]) == ids[2], "shove the carrier")
	check(rules.players[ids[1]].carried_by == 0 and rules.players[ids[2]].body == 0, "body dropped")


func test_mirror_flight_and_downed() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	power_and_gun(rules, ids[0])
	rules.set_pose(ids[1], Vector3(0, 0, 6), 0.0)
	face(rules, ids[0], Vector3.ZERO, Vector3(0, 0, 6))
	rules.request_shoot(ids[0])
	var mirror := StationRules.new()
	mirror.apply_snapshot(rules.public_snapshot(), ids[1], StationRules.CREW)
	check(mirror.state_of(ids[1]) == StationRules.DOWNED, "mirror sees downed")
	check(mirror.gun_ammo() == StationRules.GUN_AMMO - 1, "mirror sees ammo")
	check(not var_to_str(rules.public_snapshot()).contains("infiltrator"), "still no role leak")


func test_last_crew_leaving_ends_round() -> void:
	var rules := make_round(4)
	var bad := rules.infiltrator_id()
	var crew := crew_ids(rules)
	put_in_airlock(rules, crew[0])
	put_in_airlock(rules, crew[1])
	cycle_airlock(rules, bad)
	check(rules.phase != StationRules.Phase.RESULT, "one crew still aboard")
	rules.remove_player(crew[2])
	check(rules.winner == StationRules.INFILTRATOR, "last living crew leaving ends the round")


func test_blackout_hides_names() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	power_and_gun(rules, ids[0])
	rules.set_pose(ids[1], Vector3(0, 0, 6), 0.0)
	face(rules, ids[0], Vector3.ZERO, Vector3(0, 0, 6))
	rules.blackout_until = rules.elapsed + 10.0
	rules.request_shoot(ids[0])
	var alerts := rules.drain_events().filter(func(e): return e.type == "alert" and e.kind == "down")
	check(alerts.size() == 1 and not str(alerts[0].text).contains(rules.players[ids[1]].name), "down alert anonymous in blackout")
	rules.set_pose(ids[2], Vector3(0, 0, 5), 0.0)
	check(rules.available_action(ids[2]).get("label") == "Drag someone", "drag prompt anonymous in blackout")


func test_setup_resets_state() -> void:
	var rules := make_round()
	rules.tick(StationRules.ROUND_SECONDS)
	var rng := RandomNumberGenerator.new()
	rules.setup({1: {"name": "A"}, 2: {"name": "B"}}, rng)
	check(rules.winner == "" and rules.timeline.size() == 1 and rules.airlock_state == "idle", "rematch starts clean")


func test_shove_cooldown_in_snapshot() -> void:
	var rules := make_round()
	var ids := crew_ids(rules)
	rules.request_shove(ids[0])
	var mirror := StationRules.new()
	mirror.apply_snapshot(rules.public_snapshot(), ids[0], StationRules.CREW)
	check(mirror.players[ids[0]].shove_ready > mirror.elapsed, "client sees the host's shove cooldown")
