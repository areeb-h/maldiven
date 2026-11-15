class_name BotController
extends Node
## Host only: runs the bot players of one round.
##
## StationWorld adds this node when Net.roster holds bots. Each bot's avatar is a
## normal CrewMember in "bot_driven" mode (it simulates physics like a local
## player, without camera, HUD or input) and a BotBrain sets its move_input and
## facing and presses buttons through world.host_request(), exactly like a phone
## would. Poses go into the rules through world.host_pose() and reach the
## clients with everybody else's. Bots are never sent an RPC.

## Difficulty knobs. react: reaction delay range (s); aim_error: shot spread
## (radians, standard deviation; the gun's aim assist covers ±0.38); aggression:
## 0..1 chance to shove/shoot when a chance comes; mistakes: chance of a
## distracted pause or a sloppy choice; revive: chance to drag a downed crewmate
## to the medbay; gun: chance a crew bot fetches the gun after power returns;
## eject: chance to haul a downed suspect to the airlock; shove_reach: how
## close (m) a bot gets before it shoves (the rules allow 2.2).
const SKILLS := {
	"easy": {"react": Vector2(0.6, 1.2), "aim_error": 0.34, "aggression": 0.35, "mistakes": 0.25,
		"revive": 0.3, "gun": 0.25, "eject": 0.5, "shove_reach": 1.5},
	"normal": {"react": Vector2(0.3, 0.8), "aim_error": 0.2, "aggression": 0.65, "mistakes": 0.12,
		"revive": 0.55, "gun": 0.45, "eject": 0.85, "shove_reach": 1.75},
	"hard": {"react": Vector2(0.18, 0.45), "aim_error": 0.09, "aggression": 0.9, "mistakes": 0.04,
		"revive": 0.8, "gun": 0.7, "eject": 1.0, "shove_reach": 1.9},
}
const NAV_DELAY_FRAMES := 3  # let the station's colliders reach the physics space first

var world: StationWorld
var rules: StationRules
var nav: BotNav
var brains := {}  # bot id -> BotBrain
var claims := {}  # "item:cell_1", "socket:reactor_2", "core", "gun", "revive:<id>", ... -> bot id
var debug := false  # tests: print decisions worth checking
var nav_ms := 0.0  # how long fetching (first time: building) the waypoint graph took
var _frames := 0
var _seed := -1


## Adds the controller for this world's bots, or returns null if it has none.
static func attach(p_world: StationWorld, round_seed := -1) -> BotController:
	var ids := []
	for id in p_world.rules.players:
		if Net.is_bot(id) and p_world.avatars.has(id):
			ids.append(id)
	if ids.is_empty():
		return null
	var controller := BotController.new()
	controller.name = "Bots"
	controller.world = p_world
	controller.rules = p_world.rules
	controller._seed = round_seed
	ids.sort()
	for id in ids:
		var entry: Dictionary = Net.roster[id]
		var brain := BotBrain.new()
		brain.setup(id, controller, p_world.avatars[id], str(entry.get("skill", "normal")),
			round_seed * 7919 + id if round_seed >= 0 else -1)
		controller.brains[id] = brain
	p_world.add_child(controller)
	return controller


func _physics_process(delta: float) -> void:
	_frames += 1
	if nav == null:
		if _frames < NAV_DELAY_FRAMES:
			return
		var started := Time.get_ticks_usec()
		nav = BotNav.shared(world.get_world_3d().direct_space_state)
		nav_ms = (Time.get_ticks_usec() - started) / 1000.0
	for id in brains.keys():
		var brain: BotBrain = brains[id]
		if not rules.players.has(id) or not is_instance_valid(brain.avatar):
			release_all(id)
			brains.erase(id)
			continue
		brain.physics_step(delta)


## Every host event (shoves, shots, revives...) passes through here.
func on_event(event: Dictionary) -> void:
	for id in brains:
		(brains[id] as BotBrain).on_event(event)


## Claims let bots split the work (one bot per cell, one fetches the core...).
func claim(key: String, id: int) -> bool:
	var owner: int = claims.get(key, 0)
	if owner != 0 and owner != id and brains.has(owner):
		return false
	claims[key] = id
	return true


func claimed_by_other(key: String, id: int) -> bool:
	var owner: int = claims.get(key, 0)
	return owner != 0 and owner != id and brains.has(owner)


func release_all(id: int, keep := []) -> void:
	for key in claims.keys():
		if claims[key] == id and not keep.has(key):
			claims.erase(key)


func skill(name_of_skill: String) -> Dictionary:
	return SKILLS.get(name_of_skill, SKILLS.normal)
