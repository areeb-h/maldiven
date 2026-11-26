extends Node
## Headless test bot. Started by main.gd when launched with user args such as:
##   godot --headless --path . -- --bot=host --bot-players=3 --bot-plan=crew
##   godot --headless --path . -- --bot=client --bot-name=B
## Bots play a real networked round through the same RPCs a phone uses, then
## print BOT_* lines for tools/test_station.py and quit.

var args := {}
var main: Node
var _done := false
var _shot_index := 0


func _ready() -> void:
	var timeout := float(args.get("bot-timeout", "120"))
	get_tree().create_timer(timeout).timeout.connect(func():
		if not _done:
			print("BOT_TIMEOUT")
			get_tree().quit(2))
	Net.session_ended.connect(func(message):
		if not _done:
			print("BOT_SESSION_ENDED ", message))
	_run()


## Optional: --bot-shots=/abs/dir saves PNG frames at key moments (needs a
## rendering, non-headless run, e.g. under xvfb-run).
func _shot(label: String) -> void:
	var directory: String = args.get("bot-shots", "")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _wait(0.6)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [directory, _shot_index, label]
	_shot_index += 1
	image.save_png(path)
	print("BOT_SHOT ", path)


## Bots press buttons through the same path as the HUD (pose rides along).
func _act(action: String) -> void:
	var world: StationWorld = main.current_world()
	world._on_action(action)


func _say(text: String) -> void:
	print("BOT[%s] %s" % [args.get("bot-name", "?"), text])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var player_name: String = args.get("bot-name", "Bot")
	main._name_edit.text = player_name
	if args.get("bot") == "host":
		await _wait(1.5)
		await _shot("home")
		main._on_host()
		var expected := int(args.get("bot-players", "1"))
		while Net.roster.size() < expected:
			await _wait(0.2)
		await _wait(0.5)
		await _shot("lobby")
		Net.start_round()
	else:
		await _wait(float(args.get("bot-join-delay", "1.0")))
		# Keep trying for the whole bot timeout: a rendered or loaded host can
		# take much longer than usual to open its lobby.
		var give_up := Time.get_ticks_msec() + int(float(args.get("bot-timeout", "120")) * 900.0)
		while Time.get_ticks_msec() < give_up:
			main._join("127.0.0.1")
			var started := Time.get_ticks_msec()
			while not Net.is_online() and Time.get_ticks_msec() - started < 3000:
				await _wait(0.1)
			if Net.is_online():
				break
			await _wait(0.5)
	while main.current_world() == null:
		await _wait(0.1)
	await _wait(1.5)
	await _shot("briefing")
	var world: StationWorld = main.current_world()
	world.event_seen.connect(_on_world_event)
	while world.role == "" or world.rules.phase == StationRules.Phase.BRIEFING:
		await _wait(0.2)
	print("BOT_ROLE ", world.role)
	await _shot("spawn_commons")
	var ids := Net.roster.keys()
	ids.sort()
	var my_index := ids.find(Net.my_id())
	var plan: String = args.get("bot-plan", "crew")
	# Everyone restores power: cell i goes to reactor socket i.
	var cells := ["cell_1", "cell_2", "cell_3"]
	var throw_check: bool = plan == "crew" and ids.size() >= 2
	if throw_check and my_index != 1:
		_observe_throw(world, "cell_2")  # runs alongside this bot's own deliveries
	for index in range(cells.size()):
		if index % ids.size() == my_index:
			if throw_check and cells[index] == "cell_2":
				await _throw_and_check(world, "cell_2")
			await _deliver(world, cells[index], "reactor_%d" % (index + 1))
	while world.rules.phase < StationRules.Phase.EXTRACTION:
		await _wait(0.2)
	_say("power restored")
	await _shot("power_restored")
	if plan == "crew" and my_index == 0:
		await _pick_from_socket(world, "core", "vault")
		await _insert(world, "core", "shuttle")
	if plan == "crew":
		await _accuse_and_tap(world, ids, my_index)
	elif plan == "eject":
		# Needs --bot-host-infiltrator. Crew shoot the host, drag them into the
		# airlock and cycle it: exercises gun, downed bodies, drag and airlock.
		if world.role == StationRules.INFILTRATOR:
			await _teleport(world, Vector3(0, 0, 0), 0.0)
		elif my_index == 1:
			await _pick_from_socket(world, "gun", "armory")
			await _teleport(world, Vector3(0, 0, -5), PI)
			world.local.yaw = PI
			await _wait(0.5)
			await _shot("aiming")
			_act("shoot")
			var hit: bool = await _until(func(): return world.rules.state_of(1) == StationRules.DOWNED)
			print("BOT_SHOT_HIT ", hit)
			await _shot("target_down")
			_act("interact")  # drop the gun
			await _until(func(): return not world.rules.holds_gun(Net.my_id()))
			await _teleport(world, Vector3(0, 0, -1.4), PI)
			_act("interact")  # drag
			var dragging: bool = await _until(func(): return world.rules.players[Net.my_id()].body == 1)
			print("BOT_DRAG ", dragging)
			await _teleport(world, StationLayout.to_world(StationLayout.ROOMS.airlock.center), -PI / 2)
			await _wait(0.4)
			await _shot("dragging_to_airlock")
			_act("interact")  # drop body
			await _until(func(): return world.rules.players[Net.my_id()].body == 0)
			await _teleport(world, _approach("airlock_console"), StationLayout.SOCKETS.airlock_console.facing)
			_act("interact")  # cycle
			await _wait(1.5)
			await _shot("airlock_warning")
	elif plan == "infiltrator":
		if world.role == StationRules.INFILTRATOR:
			if args.has("bot-shots"):
				while world.rules.sabotage_cooldown() > 0.0:
					await _wait(0.2)
				await _teleport(world, StationLayout.to_world(StationLayout.ROOMS.command.center), PI)
				_act("sabotage")
				await _until(func(): return world.rules.is_blackout())
				await _wait(1.6)
				await _shot("blackout")
				while world.rules.is_blackout():
					await _wait(0.2)
			await _pick_from_socket(world, "core", "vault")
			var waited := 0.0
			while world.rules.items.core.holder == Net.my_id() and waited < 6.0:
				await _wait(0.2)
				waited += 0.2
			if world.rules.items.core.holder == 0:
				_say("was shoved, recovering core")
				await _wait(StationRules.STUN_SECONDS + 0.5)
				# The core flew out of their hands: let it come to rest first.
				var rested: bool = await _until(func(): return not world.rules.items.core.moving, 6.0)
				_say("core at rest: %s at %s" % [rested, world.rules.items.core.pos])
				await _pickup_floor(world, "core")
			await _insert(world, "core", "pod")
		else:
			var shover: int = await _first_crew_index(world, ids)
			if shover == my_index:
				await _shove_core_carrier(world)
	while world.rules.phase != StationRules.Phase.RESULT:
		await _wait(0.2)
	await _wait(1.0)
	await _shot("result")
	_done = true
	print("BOT_RESULT winner=%s infiltrator=%s reason=%s" % [world.rules.winner, world.rules.infiltrator_name, world.rules.reason])
	print("BOT_TIMELINE_LINES ", world.rules.timeline.size())
	await _wait(3.0 if Net.is_host() else 1.0)
	get_tree().quit(0)


## Every printed public event the test checks for (each peer prints its own).
func _on_world_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"accuse":
			print("BOT_ACCUSE by=%d target=%d" % [int(event.by), int(event.target)])
		"gesture":
			print("BOT_GESTURE %s by=%d" % [str(event.gesture), int(event.by)])


## Social verbs, replicated: while the shuttle counts down everyone gathers in
## Docking; the second peer accuses the host (every peer must see the event and
## the SUSPECT accusation in its mirror), then the infiltrator triggers the
## blackout in plain sight (every peer must see the helmet-tap gesture).
func _accuse_and_tap(world: StationWorld, ids: Array, my_index: int) -> void:
	await _until(func(): return world.rules.items.core.socket == "shuttle", 30.0)
	if my_index > 0:
		var spot: Vector3 = [Vector3(17.5, 0, 2.8), Vector3(22.0, 0, 2.8)][(my_index - 1) % 2]
		var to: Vector3 = world.rules.players[ids[0]].pos - spot
		await _teleport(world, spot, atan2(to.x, to.z) + PI)
	await _wait(1.0)
	if my_index == 1:
		world.request_accuse(ids[0])
	var marked: bool = await _until(func(): return world.rules.accusations.any(
		func(entry: Dictionary) -> bool: return int(entry.target) == int(ids[0])), 6.0)
	print("BOT_ACCUSE_MARK ", marked)
	if world.role == StationRules.INFILTRATOR:
		await _until(func(): return world.rules.sabotage_cooldown() <= 0.0, 20.0)
		_act("sabotage")
	var dark: bool = await _until(func(): return world.rules.is_blackout(), 22.0)
	print("BOT_DARK ", dark)


func _first_crew_index(world: StationWorld, ids: Array) -> int:
	# Crew bots don't know roles; the first bot that isn't the core carrier acts.
	while world.rules.items.core.holder == 0 or world.rules.items.core.socket != "":
		await _wait(0.1)
		if world.rules.phase == StationRules.Phase.RESULT:
			return -1
	var holder: int = world.rules.items.core.holder
	for index in range(ids.size()):
		if ids[index] != holder:
			return index
	return -1


func _teleport(world: StationWorld, pos: Vector3, look_yaw := INF) -> void:
	world.local.position = Vector3(pos.x, 0.15, pos.z)
	world.local.velocity = Vector3.ZERO
	world.local.snap_smoothing()
	if look_yaw != INF:
		world.local.yaw = look_yaw
		world.local._facing = look_yaw + PI
	await _wait(0.45)


func _approach(socket_id: String) -> Vector3:
	var spec: Dictionary = StationLayout.SOCKETS[socket_id]
	var front := Vector3(sin(spec.facing), 0, cos(spec.facing))
	return StationLayout.to_world(spec.pos) + front * 1.2


func _until(condition: Callable, seconds := 4.0) -> bool:
	var waited := 0.0
	while not condition.call() and waited < seconds:
		await _wait(0.1)
		waited += 0.1
	return condition.call()


func _pickup_floor(world: StationWorld, item_id: String) -> void:
	await _until(func(): return not world.rules.items[item_id].moving and world.rules.items[item_id].flight.is_empty(), 6.0)
	var at: Vector3 = world.rules.item_position(item_id)
	var room := StationLayout.room_at(at)
	var look := INF
	if room != "":
		var center: Vector2 = StationLayout.ROOMS[room].center
		# Stand on the room-centre side of the item, camera looking at it.
		var away := Vector2(at.x, at.z) - center
		look = atan2(away.x, away.y) + PI if away.length() > 0.1 else 0.0
	await _teleport(world, at, look)
	await _shot("near_" + item_id)
	_act("interact")
	var ok: bool = await _until(func(): return world.rules.items[item_id].holder == Net.my_id())
	_say("picked %s: %s" % [item_id, ok])
	await _shot("carrying_" + item_id)


func _pick_from_socket(world: StationWorld, item_id: String, socket_id: String) -> void:
	await _teleport(world, _approach(socket_id), StationLayout.SOCKETS[socket_id].facing)
	await _shot("at_" + socket_id)
	_act("interact")
	var ok: bool = await _until(func(): return world.rules.items[item_id].holder == Net.my_id())
	_say("took %s from %s: %s" % [item_id, socket_id, ok])


func _insert(world: StationWorld, item_id: String, socket_id: String) -> void:
	await _teleport(world, _approach(socket_id), StationLayout.SOCKETS[socket_id].facing)
	await _shot("before_" + socket_id)
	_act("interact")
	var ok: bool = await _until(func(): return world.rules.items[item_id].socket == socket_id)
	_say("inserted %s into %s: %s" % [item_id, socket_id, ok])
	await _wait(1.5)
	await _shot("after_" + socket_id)


func _deliver(world: StationWorld, item_id: String, socket_id: String) -> void:
	await _pickup_floor(world, item_id)
	await _insert(world, item_id, socket_id)


func _shove_core_carrier(world: StationWorld) -> void:
	var holder: int = world.rules.items.core.holder
	if holder == 0 or not world.avatars.has(holder):
		return
	await _wait(0.6)
	var target: Vector3 = world.avatars[holder].position
	world.local.position = target + Vector3(1.2, 0.15, 0)
	world.local.velocity = Vector3.ZERO
	world.local._facing = -PI / 2  # face -x, towards the carrier
	await _wait(0.45)
	world.local._facing = -PI / 2
	_act("shove")
	var ok: bool = await _until(func(): return world.rules.items.core.holder == 0)
	print("BOT_SHOVE ", "ok" if ok else "missed")


## Physics replication check: this bot picks the item up, throws it across the
## room and reports where it came to rest on its own screen.
func _throw_and_check(world: StationWorld, item_id: String) -> void:
	await _pickup_floor(world, item_id)
	var from: Vector3 = world.local.position
	var toward := Vector3(1.0, 0.0, -0.75).normalized()
	await _teleport(world, from, atan2(toward.x, toward.z) - PI)
	_act("shove")
	var thrown: bool = await _until(func(): return world.rules.items[item_id].holder == 0, 3.0)
	_say("threw %s: %s" % [item_id, thrown])
	await _wait(0.5)
	await _report_rest(world, item_id)
	await _wait(1.6)  # give the other bots time to report before picking it up again


## Every other bot watches the same throw from its own view.
func _observe_throw(world: StationWorld, item_id: String) -> void:
	var started := Time.get_ticks_msec()
	while world.rules.items[item_id].flight.is_empty() and Time.get_ticks_msec() - started < 60000:
		await _wait(0.05)
	await _report_rest(world, item_id)


func _report_rest(world: StationWorld, item_id: String) -> void:
	var item_rest := func() -> bool:
		var item: Dictionary = world.rules.items[item_id]
		return item.holder == 0 and item.flight.is_empty() and not item.moving
	var rested: bool = await _until(item_rest, 8.0)
	await _wait(0.6)  # the client's 100 ms interpolation buffer and the settle burst
	var at: Vector3 = world.rules.items[item_id].pos
	print("BOT_THROW_REST %s %.3f %.3f %.3f %s" % [item_id, at.x, at.y, at.z, rested])
