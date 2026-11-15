class_name BotBrain
extends RefCounted
## One bot player's mind (host only). Every few tenths of a second it picks a
## goal from what a player could see (the public round state, plus its own
## secret role), then steers its CrewMember there through the waypoint graph
## and presses Interact / Shove / Shoot / Blackout through world.host_request,
## the same entry point a phone's buttons reach. Goals change only after a
## human-like reaction delay; difficulty tunes delays, aim and aggression.
##
## Goal kinds (dictionaries with "kind" plus a target):
##   idle, wander, guard {pos}, ghost, pickup {item}, insert {socket}, drop,
##   drop_body, follow {target, dist}, follow_item {item, dist}, shove {target},
##   shoot {target}, drag {target}, revive (body to the medbay), eject (body
##   into the airlock), cycle (the airlock), sabotage.

const THINK_INTERVAL := 0.25
const ARRIVE := 0.7
const REPATH_SECONDS := 2.5
const LOOKAHEAD_SECONDS := 0.25
const STUCK_WINDOW := 1.5  # s without 0.5 m of progress counts as stuck
const BACKOFF_SECONDS := 0.65
const AVOID_RANGE := 1.3
const AVOID_MASK := PhysicsLayers.WORLD | PhysicsLayers.REMOTE_PLAYER | PhysicsLayers.LOCAL_PLAYER | PhysicsLayers.PROP
const PERSONAL_SPACE := 1.05
const SHOOT_RANGE := 12.0
const STRONG_SUSPICION := 5.0  # seen doing something only the infiltrator would do
const POD_GUARD := Vector3(40.0, 0.0, 3.0)  # Cargo, between the doors and the pod
const SHUTTLE_GUARD := Vector3(20.0, 0.0, 2.2)

var id := 0
var ctl: BotController
var avatar: CrewMember
var rules: StationRules
var rng := RandomNumberGenerator.new()
var skill_name := "normal"
var skill: Dictionary

var goal := {"kind": "idle"}
var _pending := {}
var _pending_left := 0.0
var _think_left := 0.0

# Steering state.
var _move_target: Variant = null  # Vector3 or null
var _move_speed := 1.0
var _arrive := ARRIVE
var _face_yaw: Variant = null  # float or null
var _aim_yaw: Variant = null  # float (gun aim) or null
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _path_age := 0.0
var _lookahead_left := 0.0
var _avoid_side := 1.0
var _backoff_left := 0.0
var _backoff_dir := Vector2.ZERO
var _anchor := Vector3.ZERO
var _anchor_age := 0.0
var _unstick_count := 0
var _arrived := false
var _last_stuck_at := Vector3.INF
var _detour: Variant = null  # Vector3: a side step around a spot we keep sticking at
var _detour_left := 0.0
var _step_round_since := 0.0
var _step_round_last := -10.0
var _last_block := ""  # what the avoidance probe last hit (debugging)
var _last_block_id := 0  # the player the probe last ran into, if any

# Action pacing.
var _act_cooldown := 0.0
var _act_ready_at := -1.0  # rules.elapsed when an in-range action may fire (reaction)

# Personality and memory.
var plan := ""  # infiltrator: rush / ambush / gun
var _plan_set_at := 0.0
var _helped_cells := 0
var _wants_gun := false
var _distracted_until := 0.0
var _idle_spot: Variant = null
var _idle_spot_left := 0.0
var _wander_target: Variant = null
var _suspect := {}  # player id -> suspicion (decays)
var _last_core_holder := 0
var _core_was := ""
var _pod_armer := 0
var _revive_rolls := {}  # downed id -> bool (decided once per fall)
var _eject_rolls := {}  # downed suspect id -> bool (decided once per fall)
var _social_left := 0.0
var _aim_error := 0.0
var _trusted_until := {}  # player id -> rules time: just saved the core, don't chase them
var _pod_dist := {}  # player id -> distance to the pod at the last think
var _pod_trend := {}  # player id -> smoothed change of that distance (m/s, negative: closing in)
var _holder_since := 0.0  # rules time the current core carrier picked it up
var _gun_mission := false  # committed to fetching the gun for a suspect
var _eject_target := 0  # downed suspect this bot is carrying to the airlock
var _cycle_until := -1.0  # rules time until which this bot tries to cycle the airlock

## Test/diagnostic counters.
var stuck_time := 0.0  # current continuous seconds trying to move without progress
var max_stuck := 0.0
var actions := 0
var unsticks := 0


func setup(p_id: int, controller: BotController, p_avatar: CrewMember, p_skill: String, seed_value := -1) -> void:
	id = p_id
	ctl = controller
	avatar = p_avatar
	rules = controller.rules
	skill_name = p_skill if BotController.SKILLS.has(p_skill) else "normal"
	skill = controller.skill(skill_name)
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_wants_gun = rng.randf() < float(skill.gun)
	_think_left = rng.randf_range(0.0, THINK_INTERVAL)
	_anchor = avatar.global_position


# --- Frame update --------------------------------------------------------------

func physics_step(delta: float) -> void:
	var me: Dictionary = rules.players.get(id, {})
	if me.is_empty():
		return
	_sync_avatar(me)
	_act_cooldown = maxf(0.0, _act_cooldown - delta)
	var state: String = me.state
	if state == StationRules.DOWNED or rules.phase == StationRules.Phase.BRIEFING and rules.elapsed < 0.5:
		_halt()
		_reset_stuck()
		return
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_INTERVAL
		_think(me)
	if not _pending.is_empty():
		_pending_left -= delta
		if _pending_left <= 0.0:
			_switch(_pending)
	_execute(me, delta)
	_steer(me, delta)
	if state != StationRules.DOWNED:
		ctl.world.host_pose(id, avatar.global_position, avatar.facing_yaw(), avatar.velocity)


## The avatar mirrors the rules like StationWorld does for the local player.
func _sync_avatar(me: Dictionary) -> void:
	avatar.speed_factor = rules.speed_factor(id)
	avatar.stunned = float(me.stunned_until) > rules.elapsed
	avatar.aiming = rules.holds_gun(id)
	var downed: bool = me.state == StationRules.DOWNED
	avatar.forced_position = me.pos if downed else null
	avatar.external_push = ctl.world.physics.airlock_push(avatar.global_position) if not downed and ctl.world.physics != null else Vector3.ZERO


func _halt() -> void:
	avatar.move_input = Vector2.ZERO
	_move_target = null


func on_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"shoved":
			var by_item: bool = event.get("item", false)
			if int(event.target) == id:
				avatar.knockback(event.dir, 0.6 if by_item else 1.0)
				avatar.express("angry", 1.2)
				var by := int(event.by)
				if by != id and _sees(by):
					# Knocking the core out of my hands is a tell; a stray shove barely is.
					_suspect[by] = float(_suspect.get(by, 0.0)) + (3.0 if _last_core_holder == id else 0.4)
				_pending_left += rng.randf_range(0.2, 0.5)  # shaken for a moment
			else:
				var target := int(event.target)
				var by := int(event.by)
				# Shoving an innocent-looking core carrier is suspicious; stopping a
				# suspicious one is what crew do.
				if by != id and target == _last_core_holder and int(rules.items.core.holder) == 0 \
						and not _looks_hostile(target) and _sees(by):
					_suspect[by] = float(_suspect.get(by, 0.0)) + 1.5
		"bumped":
			if int(event.target) == id:
				avatar.knockback(event.dir, float(event.get("strength", 0.5)))
		"revived":
			if int(event.target) == id:
				avatar.position = event.at
				avatar.velocity = Vector3.ZERO
				avatar.snap_smoothing()
				_repath_now()
		"shot":
			var by := int(event.by)
			var target := int(event.target)
			if target != 0 and _sees(by):
				if target == _last_core_holder and _hostile(target):
					_suspect[target] = float(_suspect.get(target, 0.0)) + 4.0  # stopped running for the pod
				elif by != id and float(_suspect.get(target, 0.0)) < 2.0:
					_suspect[by] = float(_suspect.get(by, 0.0)) + 1.5  # shot someone who looked innocent
			if target == id:
				avatar.express("shocked", 1.0)


## What this bot could see with its own eyes: in line of sight and not too far
## (in a blackout, only flashlights nearby). Alerts tell everyone *what*
## happened; only witnesses know *who*.
func _sees(pid: int) -> bool:
	if pid == id:
		return true
	var at := _target_pos(pid)
	var d := _flat_dist(at, _pos())
	if d < 3.0:
		return true
	if d > (8.0 if rules.is_blackout() else 22.0):
		return false
	return _line_clear(_pos() + Vector3(0, 1.5, 0), at + Vector3(0, 1.5, 0))


func _looks_hostile(pid: int) -> bool:
	return float(_suspect.get(pid, 0.0)) >= 2.0 or (rules.players.has(pid) and _hostile(pid))


# --- Thinking ----------------------------------------------------------------------

func _think(me: Dictionary) -> void:
	_observe()
	var next := _choose(me)
	var keep: Array = next.get("claims", [])
	ctl.release_all(id, keep)
	if _same(next, goal):
		goal = next  # refresh targets (positions move)
		_pending = {}
		return
	if not _pending.is_empty() and _same(next, _pending):
		_pending = next
		return
	_pending = next
	var react: Vector2 = skill.react
	_pending_left = rng.randf_range(react.x, react.y) * (0.5 if bool(next.get("urgent", false)) else 1.0)


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("kind") == b.get("kind") and a.get("item", "") == b.get("item", "") \
		and a.get("socket", "") == b.get("socket", "") and int(a.get("target", 0)) == int(b.get("target", 0))


func _switch(next: Dictionary) -> void:
	goal = next
	_pending = {}
	_act_ready_at = -1.0
	_idle_spot = null
	_repath_now()


## What everyone can see: who carries the core and where it went.
func _observe() -> void:
	for pid in _suspect.keys():
		_suspect[pid] = maxf(0.0, float(_suspect[pid]) - THINK_INTERVAL * 0.02)
	var core: Dictionary = rules.items.core
	var where := "held" if int(core.holder) != 0 else str(core.socket)
	if where == "pod" and _core_was != "pod" and _last_core_holder != 0:
		_pod_armer = _last_core_holder
		if _sees(_pod_armer):  # in a blackout only the alarm gives it away, not who
			_suspect[_pod_armer] = 10.0
	if where == "held" and _core_was == "shuttle" and _sees(int(core.holder)):
		_suspect[int(core.holder)] = float(_suspect.get(int(core.holder), 0.0)) + 7.0  # pulled it out of the shuttle
	if where == "held" and _core_was == "pod":
		_suspect[int(core.holder)] = maxf(0.0, float(_suspect.get(int(core.holder), 0.0)) - 5.0)  # saved it
		_trusted_until[int(core.holder)] = rules.elapsed + 20.0
	if where == "shuttle" and _core_was != "shuttle" and _last_core_holder != 0:
		_suspect[_last_core_holder] = maxf(0.0, float(_suspect.get(_last_core_holder, 0.0)) - 3.0)  # loaded it
		_trusted_until[_last_core_holder] = rules.elapsed + 20.0
	# Who is heading for the pod (m/s towards it, smoothed).
	var pod := StationLayout.to_world(StationLayout.SOCKETS.pod.pos)
	for pid in rules.players:
		var d := _flat_dist(rules.players[pid].pos, pod)
		var before: float = _pod_dist.get(pid, d)
		_pod_trend[pid] = lerpf(float(_pod_trend.get(pid, 0.0)), (d - before) / THINK_INTERVAL, 0.35)
		_pod_dist[pid] = d
	if int(core.holder) != 0:
		if int(core.holder) != _last_core_holder or _core_was != "held":
			_holder_since = rules.elapsed
			_pod_trend[int(core.holder)] = 0.0  # judge where they go from here
		_last_core_holder = int(core.holder)
	_core_was = where
	for pid in _revive_rolls.keys():
		if rules.state_of(pid) != StationRules.DOWNED:
			_revive_rolls.erase(pid)
	for pid in _eject_rolls.keys():
		if rules.state_of(pid) != StationRules.DOWNED:
			_eject_rolls.erase(pid)


func _choose(me: Dictionary) -> Dictionary:
	if rules.phase == StationRules.Phase.RESULT:
		return {"kind": "idle"}
	if me.state == StationRules.DEAD:
		return {"kind": "ghost"}
	if rules.phase == StationRules.Phase.BRIEFING:
		return {"kind": "idle"}
	if rules.elapsed < _distracted_until:
		return goal if goal.get("kind") in ["wander", "idle"] else {"kind": "wander"}
	var role := rules.role_of(id)
	var next := _choose_infiltrator(me) if role == StationRules.INFILTRATOR else _choose_crew(me)
	# Imperfection: now and then a non-urgent bot gets distracted and looks around.
	if not bool(next.get("urgent", false)) and next.get("kind") in ["follow", "guard", "idle", "wander"] \
			and rng.randf() < float(skill.mistakes) * 0.04:
		_distracted_until = rules.elapsed + rng.randf_range(1.5, 3.5)
	return next


func _held_kind(pid: int) -> String:
	var holding: String = rules.players[pid].holding if rules.players.has(pid) else ""
	return str(rules.items[holding].kind) if holding != "" and rules.items.has(holding) else ""


func _pos() -> Vector3:
	return avatar.global_position


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _loose(item_id: String) -> bool:
	var item: Dictionary = rules.items[item_id]
	return int(item.holder) == 0 and item.socket == "" and float(item.lost) < 0.0


# --- Crew --------------------------------------------------------------------------

func _choose_crew(me: Dictionary) -> Dictionary:
	if int(me.body) != 0:
		if int(me.body) == _eject_target:
			return {"kind": "eject", "claims": ["eject:%d" % _eject_target], "urgent": true}
		return {"kind": "revive", "claims": ["revive:%d" % int(me.body)], "urgent": true}
	if _cycle_until > rules.elapsed:
		if rules.airlock_ready() and rules.players.has(_eject_target) \
				and rules.players[_eject_target].state == StationRules.DOWNED and rules.in_airlock(rules.players[_eject_target].pos):
			return {"kind": "cycle", "urgent": true}
		_cycle_until = -1.0
	var held := _held_kind(id)
	if rules.phase == StationRules.Phase.STABILISE:
		if held == "cell":
			return _deliver_cell()
		if held != "":
			return {"kind": "drop"}
		var revive := _consider_revive()
		if not revive.is_empty():
			return revive
		var cell := _claim_cell()
		if cell != "":
			return {"kind": "pickup", "item": cell, "claims": ["item:" + cell]}
		return _support_cells()
	# Extraction.
	var core: Dictionary = rules.items.core
	var core_holder := int(core.holder)
	if held == "core":
		return {"kind": "insert", "socket": "shuttle", "urgent": true, "claims": ["core"]}
	if held == "cell" or (held == "gun" and rules.gun_ammo() <= 0):
		return {"kind": "drop"}  # an empty gun is just weight
	var gun := held == "gun"
	var culprit := _strong_suspect()
	# Sent for the gun: stick with it (only shove a suspect carrier who is right here).
	if _gun_mission:
		if gun or not _gun_free() or culprit == 0:
			_gun_mission = false
		else:
			if core_holder != 0 and core_holder != id and _hostile(core_holder) \
					and _flat_dist(_target_pos(core_holder), _pos()) < 4.0:
				return {"kind": "shove", "target": core_holder, "urgent": true, "claims": ["gun"]}
			return {"kind": "pickup", "item": "gun", "claims": ["gun"], "urgent": true}
	# Armed: shoot whoever gave themselves away, or carries the core for the pod.
	if gun:
		var mark := culprit
		if core_holder != 0 and core_holder != id and _hostile(core_holder) and (float(_suspect.get(core_holder, 0.0)) >= 4.0 \
				or (StationLayout.room_at(rules.players[core_holder].pos) == "cargo" and rules.elapsed - _holder_since > 2.5
					and float(_pod_trend.get(core_holder, 0.0)) < -1.0)):
			mark = core_holder  # shoot only the clear cases (carrying it into Cargo); shove the rest
		if mark == 0 and core.socket == "pod":
			mark = _pod_threat()
		if mark != 0 and _can_shoot(mark):
			return {"kind": "shoot", "target": mark, "urgent": true, "claims": ["gun"]}
	# The pod is armed: pull the core out (a teammate closer to it does it instead).
	if core.socket == "pod":
		if gun:
			if _closer_friend(BotNav.approach_of("pod")):
				return {"kind": "follow_item", "item": "core", "dist": 4.0, "urgent": true, "claims": ["gun"]}
			return {"kind": "drop", "urgent": true}
		var guard := _pod_threat()
		if guard != 0 and _flat_dist(rules.players[guard].pos, _pos()) < 3.0 and rng.randf() < float(skill.aggression):
			return {"kind": "shove", "target": guard, "urgent": true}
		return {"kind": "pickup", "item": "core", "urgent": true}
	# A downed suspect can be put out of the game for good (unless this bot
	# is the one nearest a loose core: that comes first).
	var core_loose: bool = core.socket == "" and core_holder == 0 and float(core.lost) < 0.0
	if not gun and (not core_loose or _closer_friend(rules.item_position("core"))):
		var eject := _consider_eject()
		if not eject.is_empty():
			return eject
	if core_holder != 0 and core_holder != id:
		if rules.is_blackout() and not _sees(core_holder):
			# Lost in the dark: the pod is where a thief would go.
			return {"kind": "guard", "pos": POD_GUARD + _jitter(1.5), "urgent": true, "claims": ["gun"] if gun else []}
		if _hostile(core_holder):
			if not gun and rng.randf() < float(skill.aggression) + 0.25:
				return {"kind": "shove", "target": core_holder, "urgent": true}
			return {"kind": "follow", "target": core_holder, "dist": 2.0 if not gun else 6.0, "urgent": true}
		var revive_c := _consider_revive()
		if not revive_c.is_empty():
			return revive_c
		return {"kind": "follow", "target": core_holder, "dist": 3.2}
	# Someone gave themselves away: arm up (unless this bot is the one on the core).
	if culprit != 0 and not gun and _gun_free() and int(ctl.claims.get("core", 0)) != id and ctl.claim("gun", id):
		_gun_mission = true
		return {"kind": "pickup", "item": "gun", "claims": ["gun"], "urgent": true}
	if core.socket == "shuttle":
		# Launch countdown: guard it, and keep suspects away from it.
		# Keep a known suspect well away (the shuttle needs 30 quiet seconds).
		var threat := _suspect_near(BotNav.approach_of("shuttle"), 9.0, 4.0)
		if threat != 0 and not gun:
			return {"kind": "shove", "target": threat, "urgent": true}
		var eject_s := _consider_eject()
		if not eject_s.is_empty():
			return eject_s
		var revive_s := _consider_revive()
		if not revive_s.is_empty():
			return revive_s
		return {"kind": "guard", "pos": SHUTTLE_GUARD + _jitter(1.5), "claims": ["gun"] if gun else []}
	if core.socket == "" and core_holder == 0 and float(core.lost) < 0.0:
		# Loose: everyone nearby goes for it; an armed bot covers a closer teammate.
		var at := rules.item_position("core")
		if gun:
			if _flat_dist(at, _pos()) < 6.0 and not _closer_friend(at):
				return {"kind": "drop", "urgent": true}
			return {"kind": "follow_item", "item": "core", "dist": 3.0, "claims": ["gun"]}
		ctl.claim("core", id)
		return {"kind": "pickup", "item": "core", "urgent": true, "claims": ["core"]}
	# The core is still in the vault.
	var eject_v := _consider_eject()
	if not eject_v.is_empty():
		return eject_v
	var revive_v := _consider_revive()
	if not revive_v.is_empty():
		return revive_v
	if gun:
		return {"kind": "guard", "pos": POD_GUARD, "claims": ["gun", "guard:pod"]}
	if core.socket == "vault" and ctl.claim("core", id):
		return {"kind": "pickup", "item": "core", "claims": ["core"]}
	var gun_item: Dictionary = rules.items.gun
	if _wants_gun and gun_item.socket == "armory" and ctl.claim("gun", id):
		return {"kind": "pickup", "item": "gun", "claims": ["gun"]}
	if ctl.claim("guard:pod", id):
		return {"kind": "guard", "pos": POD_GUARD, "claims": ["guard:pod"]}
	var fetcher: int = ctl.claims.get("core", 0)
	if fetcher != 0 and rules.players.has(fetcher):
		return {"kind": "follow", "target": fetcher, "dist": 3.5}
	return {"kind": "pickup", "item": "core"}


## Is someone who looks trustworthy (and is up) nearer to this spot than me?
func _closer_friend(at: Vector3) -> bool:
	var mine := _flat_dist(at, _pos())
	for pid in rules.players:
		if pid == id or rules.players[pid].state != StationRules.OK or float(_suspect.get(pid, 0.0)) >= 2.0:
			continue
		if float(rules.players[pid].stunned_until) > rules.elapsed:
			continue
		if _flat_dist(_target_pos(pid), at) < mine - 1.0:
			return true
	return false


func _claim_cell() -> String:
	var best := ""
	var best_d := INF
	for item_id in rules.items:
		if rules.items[item_id].kind != "cell" or not _loose(item_id):
			continue
		if ctl.claimed_by_other("item:" + item_id, id):
			continue
		var d := _flat_dist(rules.items[item_id].pos, _pos())
		if rng.randf() < float(skill.mistakes) * 0.3:
			d *= 1.6  # a sloppy pick now and then
		if d < best_d:
			best_d = d
			best = item_id
	if best != "":
		ctl.claim("item:" + best, id)
	return best


func _deliver_cell() -> Dictionary:
	var best := ""
	var best_d := INF
	for socket_id in StationLayout.SOCKETS:
		if StationLayout.SOCKETS[socket_id].kind != "reactor" or rules.socket_items[socket_id] != "":
			continue
		if ctl.claimed_by_other("socket:" + socket_id, id):
			continue
		var d := _flat_dist(BotNav.approach_of(socket_id), _pos())
		if d < best_d:
			best_d = d
			best = socket_id
	if best == "":
		for socket_id in StationLayout.SOCKETS:
			if StationLayout.SOCKETS[socket_id].kind == "reactor" and rules.socket_items[socket_id] == "":
				best = socket_id
	if best == "":
		return {"kind": "drop"}
	ctl.claim("socket:" + best, id)
	return {"kind": "insert", "socket": best, "claims": ["socket:" + best, "item:" + str(rules.players[id].holding)]}


## No free cell to fetch: walk with a cell carrier, or wait by the Reactor.
func _support_cells() -> Dictionary:
	var best := 0
	var best_d := INF
	for pid in rules.players:
		if pid == id or _held_kind(pid) != "cell":
			continue
		var d := _flat_dist(rules.players[pid].pos, _pos())
		if d < best_d:
			best_d = d
			best = pid
	if best != 0 and best_d < 25.0:
		return {"kind": "follow", "target": best, "dist": 4.0}
	return {"kind": "guard", "pos": StationLayout.to_world(StationLayout.ROOMS.reactor.center) + Vector3(0, 0, -2.5)}


## Whoever armed the pod (if this bot saw it) or a suspect standing guard by
## it; never just anyone near it (that's usually crew pulling the core out).
func _pod_threat() -> int:
	var pod := BotNav.approach_of("pod")
	var best := 0
	var best_score := 2.0
	for pid in rules.players:
		if pid == id or rules.players[pid].state != StationRules.OK:
			continue
		var d := _flat_dist(rules.players[pid].pos, pod)
		var score := float(_suspect.get(pid, 0.0))
		if d < 6.0 and score >= best_score:
			best_score = score
			best = pid
	return best


## A crew bot doesn't know roles; it judges a core carrier by where they go.
func _hostile(pid: int) -> bool:
	if not rules.players.has(pid):
		return false
	var at: Vector3 = rules.players[pid].pos
	if float(_suspect.get(pid, 0.0)) >= 4.0:
		return true
	if float(_trusted_until.get(pid, -1.0)) > rules.elapsed:
		return false
	if pid == int(rules.items.core.holder) and rules.elapsed - _holder_since < 1.5:
		return false  # just picked it up: wait and see where they take it
	var closing := float(_pod_trend.get(pid, 0.0))  # negative: getting nearer the pod
	var room := StationLayout.room_at(at)
	var to_pod := _flat_dist(at, StationLayout.to_world(StationLayout.SOCKETS.pod.pos))
	var to_shuttle := _flat_dist(at, StationLayout.to_world(StationLayout.SOCKETS.shuttle.pos))
	if room == "cargo" or room == "engineering":
		return closing < -0.4 or to_pod < 3.0
	return (to_pod < 14.0 and closing < -1.0) or (at.x > 26.0 and to_pod < to_shuttle and closing < -0.5)


func _can_shoot(pid: int) -> bool:
	if not rules.players.has(pid) or rules.players[pid].state != StationRules.OK:
		return false
	return _flat_dist(rules.players[pid].pos, _pos()) < SHOOT_RANGE + 6.0


## Someone who looked guilty enough (pulled the core from the shuttle, armed the
## pod) is down: drag them into the airlock and cycle it, if there's time.
## Too far to make it before they wake up? Hauling them away from the core
## still buys the crew time, so the trip only has to start in time.
func _consider_eject() -> Dictionary:
	if _held_kind(id) != "" or not rules.airlock_ready():
		return {}
	for pid in rules.players:
		var p: Dictionary = rules.players[pid]
		if pid == id or p.state != StationRules.DOWNED or int(p.carried_by) != 0:
			continue
		if float(_suspect.get(pid, 0.0)) < STRONG_SUSPICION or ctl.claimed_by_other("eject:%d" % pid, id):
			continue
		var left := float(p.down_until) - rules.elapsed
		if _flat_dist(p.pos, _pos()) / 5.5 > left - 5.0:
			continue
		if not _eject_rolls.has(pid):
			_eject_rolls[pid] = rng.randf() < float(skill.eject)
		if _eject_rolls[pid] and ctl.claim("eject:%d" % pid, id):
			_eject_target = pid
			return {"kind": "drag", "target": pid, "claims": ["eject:%d" % pid], "urgent": true}
	return {}


func _strong_suspect() -> int:
	var best := 0
	var best_score := STRONG_SUSPICION
	for pid in rules.players:
		if pid == id or rules.players[pid].state != StationRules.OK:
			continue
		var score := float(_suspect.get(pid, 0.0))
		if score >= best_score:
			best_score = score
			best = pid
	return best


func _gun_free() -> bool:
	var gun_item: Dictionary = rules.items.gun
	return int(gun_item.holder) == 0 and float(gun_item.lost) < 0.0 and int(gun_item.ammo) > 0


func _suspect_near(at: Vector3, radius: float, at_least := 2.0) -> int:
	var best := 0
	var best_score := at_least
	for pid in rules.players:
		if pid == id or rules.players[pid].state != StationRules.OK:
			continue
		var score := float(_suspect.get(pid, 0.0))
		if score >= best_score and _flat_dist(_target_pos(pid), at) < radius:
			best_score = score
			best = pid
	return best


## Sometimes drag a downed crewmate to the medbay (once per fall, by chance).
func _consider_revive() -> Dictionary:
	if _held_kind(id) != "":
		return {}
	var medbay := BotNav.approach_of("medbay")
	for pid in rules.players:
		var p: Dictionary = rules.players[pid]
		if pid == id or p.state != StationRules.DOWNED or int(p.carried_by) != 0:
			continue
		if ctl.claimed_by_other("revive:%d" % pid, id):
			continue
		if rules.role_of(id) != StationRules.INFILTRATOR and float(_suspect.get(pid, 0.0)) >= 4.0:
			continue  # not reviving the one who armed the pod
		var left := float(p.down_until) - rules.elapsed
		var trip := (_flat_dist(p.pos, _pos()) / 5.5) + (_flat_dist(p.pos, medbay) * 1.3 / 3.6)
		if trip > left - 2.0:
			continue
		if not _revive_rolls.has(pid):
			_revive_rolls[pid] = rng.randf() < float(skill.revive)
		if _revive_rolls[pid] and ctl.claim("revive:%d" % pid, id):
			return {"kind": "drag", "target": pid, "claims": ["revive:%d" % pid]}
	return {}


# --- Infiltrator ---------------------------------------------------------------------

func _choose_infiltrator(me: Dictionary) -> Dictionary:
	var held := _held_kind(id)
	if int(me.body) != 0:
		return {"kind": "drop_body"}
	if rules.phase == StationRules.Phase.STABILISE:
		# Blend in: help with the cells (the pod needs power too), a little slower.
		if held == "cell":
			var g := _deliver_cell()
			g["speed"] = 0.9
			return g
		if held != "":
			return {"kind": "drop"}
		var wants_more := _helped_cells < 1 or rules.elapsed > 120.0
		if wants_more:
			var cell := _claim_cell()
			if cell != "":
				return {"kind": "pickup", "item": cell, "claims": ["item:" + cell], "speed": 0.9}
		return _support_cells()
	if plan == "":
		_pick_plan()
	var core: Dictionary = rules.items.core
	var core_holder := int(core.holder)
	if held == "core":
		if rules.socket_items.pod == "":
			return {"kind": "insert", "socket": "pod", "urgent": true}
		return {"kind": "drop"}
	if held == "gun" and rules.gun_ammo() <= 0:
		return {"kind": "drop"}
	var gun := held == "gun"
	if core.socket == "pod":
		# Armed: keep crew off the pod until it launches.
		var threat := _nearest_crew(BotNav.approach_of("pod"), 3.2)
		if threat != 0:
			if gun:
				return {"kind": "shoot", "target": threat, "urgent": true}
			return {"kind": "shove", "target": threat, "urgent": true}
		return {"kind": "guard", "pos": BotNav.approach_of("pod") + Vector3(-1.2, 0, 0) + _jitter(0.8)}
	if core.socket == "shuttle":
		if _sabotage_ready():
			return {"kind": "sabotage", "urgent": true}
		var dark_in := rules.sabotage_cooldown()
		if not rules.is_blackout() and dark_in > 0.0 and dark_in < 7.0 and rules.shuttle_left > dark_in + 9.0:
			# The lights go out soon: lurk nearby and strike in the dark.
			return {"kind": "guard", "pos": BotNav.approach_of("shuttle") + Vector3(3.0, 0, 3.5)}
		if gun:
			var guard := _nearest_crew(BotNav.approach_of("shuttle"), 4.0)
			if guard != 0 and _can_shoot(guard):
				return {"kind": "shoot", "target": guard, "urgent": true}
			return {"kind": "drop", "urgent": true}
		var blocker := _nearest_crew(BotNav.approach_of("shuttle"), 2.0)
		if blocker != 0 and _flat_dist(rules.players[blocker].pos, _pos()) < 2.5 and rng.randf() < float(skill.aggression):
			return {"kind": "shove", "target": blocker, "urgent": true}
		return {"kind": "pickup", "item": "core", "urgent": true}
	if core_holder != 0 and core_holder != id:
		if _sabotage_ready() and _flat_dist(rules.players[core_holder].pos, _pos()) < 30.0:
			return {"kind": "sabotage", "urgent": true}
		if gun and _can_shoot(core_holder):
			return {"kind": "shoot", "target": core_holder, "urgent": true}
		# Pick the moment: close in, then shove (eager bots don't wait for the dark).
		var d := _flat_dist(rules.players[core_holder].pos, _pos())
		if rules.is_blackout() or d < 6.0 or rng.randf() < float(skill.aggression) * 0.5:
			return {"kind": "shove", "target": core_holder, "urgent": true}
		return {"kind": "follow", "target": core_holder, "dist": 3.0, "urgent": true}
	if core.socket == "" and core_holder == 0 and float(core.lost) < 0.0:
		if gun:
			return {"kind": "drop", "urgent": true}
		return {"kind": "pickup", "item": "core", "urgent": true}
	# A gun left lying around is too good to pass up.
	if not gun and _gun_free() and rules.items.gun.socket == "" \
			and _flat_dist(rules.item_position("gun"), _pos()) < 10.0 and rng.randf() < float(skill.aggression):
		return {"kind": "pickup", "item": "gun"}
	# Core in the vault.
	var since := rules.elapsed - _plan_set_at
	match plan:
		"gun":
			if not gun and rules.items.gun.socket == "armory":
				return {"kind": "pickup", "item": "gun"}
			if gun and since > 35.0:
				return {"kind": "drop"}  # nobody came for the core: go take it
			if gun:
				var fetcher: int = ctl.claims.get("core", 0)
				if fetcher != 0 and rules.players.has(fetcher) and fetcher != id:
					return {"kind": "follow", "target": fetcher, "dist": 5.0}
				return {"kind": "guard", "pos": StationLayout.to_world(StationLayout.ROOMS.command.center) + Vector3(0, 0, 3)}
			return {"kind": "pickup", "item": "core"}
		"ambush":
			if since < 25.0:
				var fetcher: int = ctl.claims.get("core", 0)
				var near_vault := _nearest_crew(BotNav.approach_of("vault"), 14.0)
				var watch := fetcher if fetcher != 0 and fetcher != id else near_vault
				if watch != 0 and rules.players.has(watch):
					return {"kind": "follow", "target": watch, "dist": 4.5}
				return {"kind": "guard", "pos": StationLayout.to_world(StationLayout.ROOMS.command.center) + Vector3(2, 0, 4)}
			return {"kind": "pickup", "item": "core"}
	if gun:
		return {"kind": "drop"}
	return {"kind": "pickup", "item": "core", "urgent": true}


## A fixed per-bot offset, so bots guarding the same spot spread out.
func _jitter(radius: float) -> Vector3:
	var a := float(id % 97) * 2.399
	return Vector3(cos(a), 0, sin(a)) * radius


func _pick_plan() -> void:
	_plan_set_at = rules.elapsed
	var roll := rng.randf()
	var aggression := float(skill.aggression)
	if roll < 0.38 * aggression:
		plan = "gun"
	elif roll < 0.55:
		plan = "rush"
	else:
		plan = "ambush"


func _sabotage_ready() -> bool:
	return rules.sabotage_cooldown() <= 0.0 and not rules.is_blackout() and rng.randf() < 0.5 + 0.5 * float(skill.aggression)


func _nearest_crew(at: Vector3, radius: float) -> int:
	var best := 0
	var best_d := radius
	for pid in rules.players:
		if pid == id or rules.players[pid].state != StationRules.OK:
			continue
		var d := _flat_dist(rules.players[pid].pos, at)
		if d < best_d:
			best_d = d
			best = pid
	return best


# --- Doing -----------------------------------------------------------------------------

func _execute(me: Dictionary, delta: float) -> void:
	_move_target = null
	_face_yaw = null
	_aim_yaw = null
	_move_speed = float(goal.get("speed", 1.0))
	_arrive = ARRIVE
	var kind: String = goal.get("kind", "idle")
	match kind:
		"idle":
			_do_idle(delta, false)
		"wander":
			_do_wander(delta)
		"ghost":
			_do_ghost(delta)
		"guard":
			_do_guard(delta)
		"pickup":
			_do_pickup()
		"follow_item":
			_go(rules.item_position(goal.item), float(goal.get("dist", 3.0)))
		"insert":
			_do_insert()
		"drop", "drop_body":
			if not _try_interact(func(a: Dictionary) -> bool: return a.get("action") in ["drop", "drop_body"]):
				_do_idle(delta, true)
		"follow":
			_do_follow()
		"shove":
			_do_shove()
		"shoot":
			_do_shoot()
		"drag":
			_do_drag()
		"revive":
			_do_revive()
		"eject":
			_do_eject()
		"cycle":
			if not _try_interact(func(a: Dictionary) -> bool: return a.get("action") == "airlock"):
				_go(BotNav.approach_of("airlock_console"), 0.5)
			if rules.airlock_state != "idle":
				_cycle_until = -1.0
		"sabotage":
			_press("sabotage")
			_do_idle(delta, true)
			goal = {"kind": "idle"}


func _go(target: Vector3, arrive := ARRIVE, speed := -1.0) -> void:
	_move_target = target
	_arrive = arrive
	if speed > 0.0:
		_move_speed = speed


func _face_point(at: Vector3) -> void:
	var d := at - _pos()
	if Vector2(d.x, d.z).length() > 0.05:
		_face_yaw = atan2(d.x, d.z)


## Press Interact when the button would do what we want (after a short reaction).
func _try_interact(wanted: Callable) -> bool:
	var action := rules.available_action(id)
	if action.is_empty() or not wanted.call(action):
		_act_ready_at = -1.0
		return false
	if _act_ready_at < 0.0:
		_act_ready_at = rules.elapsed + rng.randf_range(0.08, 0.25) * (2.0 if skill_name == "easy" else 1.0)
	if rules.elapsed < _act_ready_at or _act_cooldown > 0.0:
		return true
	_press("interact")
	_act_ready_at = -1.0
	return true


func _press(action: String) -> void:
	if _act_cooldown > 0.0:
		return
	_act_cooldown = 0.45
	actions += 1
	ctl.world.host_request(id, action, avatar.global_position, avatar.facing_yaw())


func _do_pickup() -> void:
	var item_id: String = goal.item
	if not rules.items.has(item_id):
		return
	var kind: String = rules.items[item_id].kind
	var accepted := func(a: Dictionary) -> bool:
		if a.get("action") != "pickup":
			return false
		var other: String = a.get("item", "")
		# Never undo our own side's work, even with a stale goal.
		var from: String = a.get("socket", "")
		if from == ("pod" if rules.role_of(id) == StationRules.INFILTRATOR else "shuttle"):
			return false
		if other == item_id:
			return true
		# Another cell within reach works as well, unless a teammate is after it.
		return kind == "cell" and rules.items[other].kind == "cell" and not ctl.claimed_by_other("item:" + other, id)
	if _try_interact(accepted):
		_face_point(rules.item_position(item_id))
		return
	# In reach, but the button would grab something else (a body lying on it,
	# another item): step round to the far side so ours is the nearest.
	if int(rules.items[item_id].holder) == 0 and _step_round(rules.item_position(item_id)):
		return
	var at: Vector3 = rules.items[item_id].pos if rules.items[item_id].socket == "" else BotNav.approach_of(rules.items[item_id].socket)
	if int(rules.items[item_id].holder) != 0:
		at = rules.item_position(item_id)
	_go(at, 0.9 if rules.items[item_id].socket == "" else 0.5)


func _action_position(action: Dictionary) -> Variant:
	match str(action.get("action", "")):
		"pickup":
			return rules.item_position(action.item)
		"drag":
			return rules.players[action.target].pos if rules.players.has(action.target) else null
		"airlock":
			return StationLayout.to_world(StationLayout.SOCKETS.airlock_console.pos)
	return null


func _do_insert() -> void:
	var socket_id: String = goal.socket
	var kind: String = StationLayout.SOCKETS[socket_id].kind
	var accepted := func(a: Dictionary) -> bool:
		return a.get("action") == "insert" and StationLayout.SOCKETS[str(a.get("socket"))].kind == kind
	var cells_before := rules.powered_cells()
	if _try_interact(accepted):
		_face_point(StationLayout.to_world(StationLayout.SOCKETS[socket_id].pos))
		if rules.powered_cells() > cells_before:
			_helped_cells += 1
		return
	_go(BotNav.approach_of(socket_id), 0.45)


func _target_pos(pid: int) -> Vector3:
	if ctl.world.avatars.has(pid):
		return (ctl.world.avatars[pid] as CrewMember).global_position
	return rules.players[pid].pos if rules.players.has(pid) else _pos()


func _do_follow() -> void:
	var pid := int(goal.target)
	if not rules.players.has(pid):
		return
	var at := _target_pos(pid)
	var dist := float(goal.get("dist", 3.0))
	if _flat_dist(at, _pos()) > dist:
		_go(at, dist, 1.0 if _flat_dist(at, _pos()) > dist + 3.0 else 0.75)
	else:
		_face_point(at)


func _do_shove() -> void:
	var pid := int(goal.target)
	if not rules.players.has(pid) or rules.players[pid].state != StationRules.OK:
		return
	if _held_kind(id) != "":
		_try_interact(func(a: Dictionary) -> bool: return a.get("action") == "drop")
		return
	var at := _target_pos(pid)
	var d := _flat_dist(at, _pos())
	_face_point(at)
	var ready := float(rules.players[id].shove_ready) <= rules.elapsed
	if d <= float(skill.shove_reach) and ready:
		var facing := avatar.facing_yaw()
		var want: float = _face_yaw if _face_yaw != null else facing
		if (absf(wrapf(want - facing, -PI, PI)) < 0.5 or d < 0.6) and _shove_would_hit() == pid:
			if _act_ready_at < 0.0:
				_act_ready_at = rules.elapsed + rng.randf_range(0.05, 0.2)
			if rules.elapsed >= _act_ready_at:
				_press("shove")
				_act_ready_at = -1.0
		return
	_go(at, 1.0)


## Who a shove would hit right now (the rules take the nearest one in front).
func _shove_would_hit() -> int:
	var me: Dictionary = rules.players[id]
	var forward := Vector3(sin(avatar.facing_yaw()), 0, cos(avatar.facing_yaw()))
	var best := StationRules.SHOVE_RANGE
	var target := 0
	for pid in rules.players:
		if pid == id or rules.players[pid].state != StationRules.OK:
			continue
		var offset: Vector3 = rules.players[pid].pos - me.pos
		offset.y = 0.0
		var d := offset.length()
		if d > best or (d > 0.6 and forward.dot(offset.normalized()) < 0.2):
			continue
		best = d
		target = pid
	return target


func _do_shoot() -> void:
	var pid := int(goal.target)
	if not rules.holds_gun(id) or not rules.players.has(pid) or rules.players[pid].state != StationRules.OK:
		return
	var at := _target_pos(pid)
	var d := _flat_dist(at, _pos())
	var eye := _pos() + Vector3(0, 1.3, 0)
	var sight := _line_clear(eye, at + Vector3(0, 1.2, 0))
	if d > SHOOT_RANGE or not sight:
		_go(at, SHOOT_RANGE * 0.6)
		return
	var true_yaw := atan2(at.x - _pos().x, at.z - _pos().z)
	if _act_ready_at < 0.0:
		var react: Vector2 = skill.react
		_act_ready_at = rules.elapsed + rng.randf_range(react.x, react.y) * 0.8
		_aim_error = rng.randfn(0.0, float(skill.aim_error))
	_aim_yaw = true_yaw + _aim_error
	var facing := avatar.facing_yaw()
	if rules.elapsed >= _act_ready_at and absf(wrapf(float(_aim_yaw) - facing, -PI, PI)) < 0.08 \
			and rules.gun_ready <= rules.elapsed:
		var hit := _shot_would_hit(pid)
		if hit != 0 and hit != pid:
			# Someone else is in the line of fire: step aside instead.
			_go(_pos() + Vector3(cos(true_yaw), 0, -sin(true_yaw)) * 2.0 * _avoid_side, 0.3, 0.6)
			return
		if rng.randf() < 0.6 + 0.4 * float(skill.aggression):
			if ctl.debug:
				print("BOTDBG %s shoots at %d (predicted %d) suspicion=%s" % [rules.players[id].name, pid, hit, _suspect])
			_press("shoot")
		_act_ready_at = -1.0  # next shot gets a fresh aim (and reaction)


## Who a shot would hit right now (the rules' aim assist picks the best one in
## the cone), or 0 for a miss. With `wanted`, anyone else nearly as well placed
## counts as the hit too: bodies move between this check and the shot.
func _shot_would_hit(wanted := 0) -> int:
	var shooter: Vector3 = rules.players[id].pos
	var forward := Vector3(sin(avatar.facing_yaw()), 0, cos(avatar.facing_yaw()))
	var eye := shooter + Vector3(0, 1.3, 0)
	var target := 0
	var best_score := INF
	for pid in rules.players:
		if pid == id or rules.players[pid].state != StationRules.OK:
			continue
		var offset: Vector3 = rules.players[pid].pos - shooter
		offset.y = 0.0
		var d := offset.length()
		if d > StationRules.GUN_RANGE or d < 0.01 or forward.angle_to(offset.normalized()) > StationRules.GUN_CONE:
			continue
		if not _line_clear(eye, rules.players[pid].pos + Vector3(0, 1.2, 0)):
			continue
		var score := forward.angle_to(offset.normalized()) * 10.0 + d * 0.1
		if pid != wanted:
			score -= 1.5  # margin: a teammate close to the line of fire blocks the shot
		if score < best_score:
			best_score = score
			target = pid
	return target


func _line_clear(a: Vector3, b: Vector3) -> bool:
	var space := avatar.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(a, b, PhysicsLayers.WORLD)
	return space.intersect_ray(query).is_empty()


func _do_drag() -> void:
	var pid := int(goal.target)
	if not rules.players.has(pid):
		return
	var at: Vector3 = rules.players[pid].pos
	if _try_interact(func(a: Dictionary) -> bool: return a.get("action") == "drag" and int(a.get("target", 0)) == pid):
		_face_point(at)
		return
	if _step_round(at):
		return
	_go(at, 1.0)


## In reach of `at`, but Interact would act on something nearer (a socket's
## item, another body): step round to the far side. True while doing that.
func _step_round(at: Vector3) -> bool:
	if _flat_dist(at, _pos()) >= StationRules.INTERACT_RANGE - 0.3:
		return false
	var other: Variant = _action_position(rules.available_action(id))
	if other == null:
		return false
	if rules.elapsed - _step_round_last > 0.5:
		_step_round_since = rules.elapsed
	_step_round_last = rules.elapsed
	if rules.elapsed - _step_round_since > 2.5:
		# Can't get round it (a crate, the pod hull): knock things apart with a shove.
		_face_point(at)
		if _held_kind(id) == "" and _shove_would_hit() == 0 and float(rules.players[id].shove_ready) <= rules.elapsed \
				and (_face_yaw == null or absf(wrapf(float(_face_yaw) - avatar.facing_yaw(), -PI, PI)) < 0.4):
			_press("shove")
			_step_round_since = rules.elapsed
		return true
	var away := Vector3(at.x - other.x, 0.0, at.z - other.z)
	away = away.normalized() if away.length() > 0.05 else Vector3(1, 0, 0).rotated(Vector3.UP, float(id))
	_go(at + away * 0.5, 0.2, 0.5)
	return true


func _do_revive() -> void:
	if _try_interact(func(a: Dictionary) -> bool: return a.get("action") == "revive"):
		return
	_go(BotNav.approach_of("medbay"), 0.5)


## Carry the body into the middle of the chamber, put it down, then go cycle.
func _do_eject() -> void:
	var chamber := StationLayout.to_world(StationLayout.ROOMS.airlock.center)
	if _flat_dist(chamber, _pos()) < 1.0 and rules.in_airlock(_pos()):
		if _try_interact(func(a: Dictionary) -> bool: return a.get("action") == "drop_body"):
			_cycle_until = rules.elapsed + 15.0
		return
	_go(chamber, 0.6)


func _do_guard(delta: float) -> void:
	var at: Vector3 = goal.pos
	if _flat_dist(at, _pos()) > 3.0:
		_go(at, 1.2, 1.0)
		return
	_do_idle(delta, false, at)


## Never stand still for long: amble between nearby spots and face people.
func _do_idle(delta: float, quiet: bool, around: Variant = null) -> void:
	_idle_spot_left -= delta
	_social_left -= delta
	if _idle_spot_left <= 0.0:
		_idle_spot_left = rng.randf_range(2.5, 5.5)
		var base: Vector3 = around if around != null else _pos()
		var spot := base + Vector3(rng.randf_range(-2.2, 2.2), 0, rng.randf_range(-2.2, 2.2))
		var nav := ctl.nav
		_idle_spot = spot if nav == null or nav.clear_line(_pos(), spot) else null
	if _idle_spot != null and not quiet and _flat_dist(_idle_spot, _pos()) > 0.6:
		_go(_idle_spot, 0.5, 0.45)
		return
	var friend := _nearest_player(6.0)
	if friend != 0:
		_face_point(_target_pos(friend))
		if _social_left <= 0.0:
			_social_left = rng.randf_range(6.0, 14.0)
			if rules.phase == StationRules.Phase.RESULT:
				var won := rules.winner == rules.role_of(id)
				avatar.express("happy" if won else "hurt", 2.0)
			elif not Net.is_bot(friend) and rng.randf() < 0.5:
				avatar.express("happy", 1.2)
			elif rules.phase == StationRules.Phase.EXTRACTION and rng.randf() < 0.4:
				avatar.express("suspicious", 1.2)


func _nearest_player(radius: float) -> int:
	var best := 0
	var best_d := radius
	for pid in rules.players:
		if pid == id or rules.players[pid].state == StationRules.DEAD:
			continue
		var d := _flat_dist(_target_pos(pid), _pos())
		if d < best_d:
			best_d = d
			best = pid
	return best


func _do_wander(delta: float) -> void:
	if _wander_target == null or _flat_dist(_wander_target, _pos()) < 1.5:
		var rooms := StationLayout.ROOMS.keys()
		rooms.erase("airlock")  # nobody loiters in the airlock
		var room: String = StationLayout.room_at(_pos())
		if room == "" or rng.randf() < 0.5:
			room = rooms[rng.randi_range(0, rooms.size() - 1)]
		_wander_target = ctl.nav.random_point(room, rng) if ctl.nav != null else _pos()
	_go(_wander_target, 1.0, 0.7)
	if rules.elapsed < _distracted_until:
		_do_idle(delta, true)  # look around instead of walking


## Ghosts drift slowly from room to room (they float through walls anyway).
func _do_ghost(delta: float) -> void:
	_do_wander(delta)
	_move_speed = 0.4


# --- Steering --------------------------------------------------------------------------

func _repath_now() -> void:
	_path = PackedVector3Array()
	_path_goal = Vector3.INF


func _reset_stuck() -> void:
	_anchor = _pos()
	_anchor_age = 0.0
	stuck_time = 0.0


func _steer(me: Dictionary, delta: float) -> void:
	var pos := _pos()
	var aiming := rules.holds_gun(id)
	var stunned := float(me.stunned_until) > rules.elapsed
	_arrived = false
	if _move_target == null or ctl.nav == null:
		_stand(pos, aiming, delta)
		return
	var target: Vector3 = _move_target
	if _flat_dist(target, pos) <= _arrive:
		_arrived = true
		_stand(pos, aiming, delta)
		return
	_path_age += delta
	if _path.is_empty() or _flat_dist(_path_goal, target) > 1.2 or _path_age > REPATH_SECONDS:
		_path = ctl.nav.path(pos, target)
		_path_index = 0
		_path_goal = target
		_path_age = 0.0
		if _path.is_empty():
			_path.append(target)  # no route known: head straight for it
	else:
		_path[_path.size() - 1] = target
	while _path_index < _path.size() - 1 and _flat_dist(_path[_path_index], pos) < 0.9:
		_path_index += 1
	_lookahead_left -= delta
	if _lookahead_left <= 0.0:
		_lookahead_left = LOOKAHEAD_SECONDS
		for k in range(3):
			if _path_index < _path.size() - 1 and ctl.nav.clear_line(pos, _path[_path_index + 1]):
				_path_index += 1
			else:
				break
	var waypoint := _path[_path_index]
	if _detour != null:
		_detour_left -= delta
		if _detour_left <= 0.0 or _flat_dist(_detour, pos) < 0.6:
			_detour = null
			_repath_now()
		else:
			waypoint = _detour
	var to := Vector2(waypoint.x - pos.x, waypoint.z - pos.z)
	var dir := to.normalized() if to.length() > 0.01 else Vector2.ZERO
	var speed := _move_speed
	if _path_index == _path.size() - 1 and to.length() < 2.0:
		speed = minf(speed, 0.7)  # ease in
	if _backoff_left > 0.0:
		_backoff_left -= delta
		dir = _backoff_dir
		speed = 0.8
	else:
		dir = _avoid(pos, dir)
		dir = _separate(pos, dir)
	_set_move(dir, speed, aiming)
	_track_stuck(pos, dir, stunned, delta)


## Standing: face what we want to face, but step aside for anyone walking
## straight into us (a bot waiting in a doorway must not block it).
func _stand(pos: Vector3, aiming: bool, delta: float) -> void:
	_reset_stuck()
	var dodge := Vector2.ZERO
	for other in CrewMember.registry:
		if other == avatar or not other.is_inside_tree() or other.life_state != "ok":
			continue
		var vel := Vector2(other.velocity.x, other.velocity.z)
		if other.bot_driven:
			# Another bot: where it wants to go counts, even while something blocks it.
			var wish := Basis(Vector3.UP, other.yaw) * Vector3(other.move_input.x, 0.0, other.move_input.y)
			vel = Vector2(wish.x, wish.z) * CrewMember.RUN_SPEED
		var offset := Vector2(pos.x - other.global_position.x, pos.z - other.global_position.z)
		if vel.length() < 1.0 or offset.length() > 2.2 or offset.length() < 0.01:
			continue
		var heading := vel.normalized()
		if heading.dot(offset.normalized()) > 0.6:
			var side := Vector2(-heading.y, heading.x)
			dodge += side * (1.0 if side.dot(offset) >= 0.0 else -1.0)
	if dodge != Vector2.ZERO:
		_set_move(dodge.normalized(), 0.6, aiming)
		return
	avatar.move_input = Vector2.ZERO
	_turn_to(_aim_yaw if _aim_yaw != null else _face_yaw, aiming, delta)


func _set_move(dir: Vector2, amount: float, aiming: bool) -> void:
	if aiming:
		var aim: float = _aim_yaw if _aim_yaw != null else (atan2(dir.x, dir.y) if dir.length() > 0.1 else avatar.facing_yaw())
		avatar.yaw = aim - PI  # aiming crew face the camera's look direction
	else:
		avatar.yaw = 0.0
	var local := Basis(Vector3.UP, avatar.yaw).inverse() * Vector3(dir.x, 0.0, dir.y)
	avatar.move_input = Vector2(local.x, local.z) * clampf(amount, 0.0, 1.0)


## Standing still: turn smoothly to a yaw (or keep facing). Aiming turns the
## camera yaw instead; the avatar follows it.
func _turn_to(yaw_wanted: Variant, aiming: bool, delta: float) -> void:
	if yaw_wanted == null:
		return
	var want: float = yaw_wanted
	if aiming:
		avatar.yaw = want - PI
		return
	var now := avatar.facing_yaw()
	avatar.snap_facing(lerp_angle(now, want, minf(1.0, delta * 9.0)))


## Local avoidance: probe ahead at knee and chest height; if blocked, take the
## first clear heading to one side (sticking with the side that worked).
func _avoid(pos: Vector3, dir: Vector2) -> Vector2:
	if dir.length() < 0.01:
		return dir
	if _probe_clear(pos, dir):
		return dir
	var straight_block := _last_block
	var straight_id := _last_block_id
	for step in [0.5, 0.9, 1.3, 1.75]:
		for side in [_avoid_side, -_avoid_side]:
			var turned := dir.rotated(step * side)
			if _probe_clear(pos, turned):
				_avoid_side = side
				_last_block = straight_block
				_last_block_id = straight_id
				return turned
	return dir


func _probe_clear(pos: Vector3, dir: Vector2) -> bool:
	var space := avatar.get_world_3d().direct_space_state
	var ahead := Vector3(dir.x, 0, dir.y) * AVOID_RANGE
	var side := Vector3(-dir.y, 0, dir.x) * 0.32  # the shoulders, not just the middle
	for probe in [Vector3(0, 0.35, 0), Vector3(0, 1.0, 0), side + Vector3(0, 0.6, 0), -side + Vector3(0, 0.6, 0)]:
		var from: Vector3 = pos + probe
		var query := PhysicsRayQueryParameters3D.create(from, from + ahead, AVOID_MASK, [avatar.get_rid()])
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var collider: Object = hit.get("collider")
			# Walking into the one we chase or shove is the point.
			if collider is CrewMember and goal.get("kind") in ["shove", "follow", "drag"] \
					and (collider as CrewMember).peer_id == int(goal.get("target", 0)):
				continue
			_last_block = "%s@%s" % [collider.get("name") if collider != null else "?", hit.get("position")]
			_last_block_id = (collider as CrewMember).peer_id if collider is CrewMember else 0
			return false
	return true


## Keep a little personal space from other crew (bodies never stack).
func _separate(pos: Vector3, dir: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for other in CrewMember.registry:
		if other == avatar or not other.is_inside_tree() or other.life_state != "ok":
			continue
		var offset := Vector2(pos.x - other.global_position.x, pos.z - other.global_position.z)
		var d := offset.length()
		if d < PERSONAL_SPACE and d > 0.001:
			push += offset / d * (PERSONAL_SPACE - d)
	if push == Vector2.ZERO:
		return dir
	return (dir + push * 1.2).normalized()


## No progress for a while: back off at an angle, maybe hop, then re-route.
func _track_stuck(pos: Vector3, dir: Vector2, stunned: bool, delta: float) -> void:
	if stunned or dir.length() < 0.01 or avatar.life_state != "ok":
		_reset_stuck()
		return
	_anchor_age += delta
	stuck_time += delta
	if _flat_dist(pos, _anchor) > 0.5:
		_anchor = pos
		_anchor_age = 0.0
		stuck_time = 0.0
		_unstick_count = maxi(0, _unstick_count - 1) if _backoff_left <= 0.0 else _unstick_count
		return
	max_stuck = maxf(max_stuck, stuck_time)
	if _anchor_age > STUCK_WINDOW and _backoff_left <= 0.0:
		_anchor_age = 0.0
		_unstick_count += 1
		unsticks += 1
		# Someone stands in an infiltrator's way: out of the way with them.
		if _last_block_id != 0 and rules.role_of(id) == StationRules.INFILTRATOR and _held_kind(id) == "" \
				and float(rules.players[id].shove_ready) <= rules.elapsed and _shove_would_hit() == _last_block_id:
			_press("shove")
		_avoid_side = -_avoid_side
		_backoff_dir = (-dir).rotated(rng.randf_range(0.6, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0))
		_backoff_left = BACKOFF_SECONDS
		if _unstick_count >= 2:
			avatar.jump_pending = true  # a small prop or a deck edge: hop it
		if ctl.nav != null:
			_detour = _detour_point(pos)  # then walk round it another way
			_detour_left = 2.0 if _flat_dist(pos, _last_stuck_at) < 1.5 else 1.2
		_last_stuck_at = pos
		_repath_now()


## A graph point 2-5 m away, reachable in a straight line, off to one side.
func _detour_point(pos: Vector3) -> Variant:
	var nav := ctl.nav
	var options := []
	for index in nav._near(pos, 5.0):
		var p: Vector3 = nav.points[index]
		var d := _flat_dist(p, pos)
		if d > 2.0 and d < 5.0 and nav.clear_line(pos, p):
			options.append(p)
	if options.is_empty():
		return null
	return options[rng.randi_range(0, options.size() - 1)]


## For tests: this bot means to get somewhere (or is at a spot but can't do
## what it came for yet), so standing still there counts as stuck.
func wants_progress() -> bool:
	if _move_target == null:
		return false
	return not _arrived or goal.get("kind") in ["pickup", "insert", "drag", "revive", "eject", "cycle"]


## One line for logs and tests: what this bot is doing and where it's heading.
func debug_line() -> String:
	var waypoint: Variant = _path[_path_index] if _path_index < _path.size() else null
	return "goal=%s target=%s waypoint=%s/%d arrive=%.1f backoff=%.1f stuck=%.1f input=%s block=%s" % [goal.get("kind"),
		_move_target, waypoint, _path.size(), _arrive, _backoff_left, stuck_time, avatar.move_input, _last_block]
