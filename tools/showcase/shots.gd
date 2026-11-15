extends "res://tools/showcase/studio.gd"
## The key-art shot list. Each shot function dresses the set, lights it, frames
## the camera and captures one or more PNGs into `out`, returning the save error.
##
## Coordinates are station metres (see scripts/station_layout.gd); crew yaw 0
## faces +Z. Purple is the running "suspicious" character across the set.

## Render order. `key` is what --only matches; `method` is the shot function.
const SHOTS: Array[Dictionary] = [
	{"key": "lineup", "method": "shot_crew_lineup"},
	{"key": "lying", "method": "shot_one_is_lying"},
	{"key": "portraits", "method": "shot_portraits"},
	{"key": "core_run", "method": "shot_core_run"},
	{"key": "shove", "method": "shot_shove"},
	{"key": "gun", "method": "shot_gun_question"},
	{"key": "rescue", "method": "shot_rescue"},
	{"key": "airlock", "method": "shot_airlock"},
	{"key": "ghost", "method": "shot_ghost"},
	{"key": "blackout", "method": "shot_blackout"},
	{"key": "shuttle", "method": "shot_shuttle"},
	{"key": "turntable", "method": "shot_turntable"},
	{"key": "overhead", "method": "shot_overhead"},
	{"key": "selfie", "method": "shot_selfie"},
]

const WARM := Color(1.0, 0.86, 0.68)
const COOL := Color(0.55, 0.75, 1.0)
const CYAN := Color(0.3, 0.9, 1.0)


## 01 Crew lineup hero: seven crew in a confident V in Commons, power restored,
## camera low in the south doorway, the gas giant rising over the north wall.
## Mostly happy faces; purple, on the right wing, is already suspicious.
func shot_crew_lineup(out: String) -> Error:
	begin_shot("restored", 101)
	var cam := Vector3(0.35, 0.42, 7.3)
	var tip := Vector3(0.0, 0, 3.4)
	var cast := [
		# colour, offset from the tip, face, variant, number, fidget (-1 none), extra yaw
		["yellow", Vector3(0.0, 0, 0.0), "happy", 1, 3, -1, 0.0],
		["red", Vector3(-1.05, 0, -0.75), "happy", 0, 1, 1, 8.0],
		["blue", Vector3(1.05, 0, -0.75), "happy", 2, 2, -1, -8.0],
		["green", Vector3(-2.1, 0, -1.5), "happy", 3, 4, 2, 14.0],
		["purple", Vector3(2.1, 0, -1.5), "suspicious", 1, 5, -1, -24.0],
		["orange", Vector3(-3.15, 0, -2.25), "happy", 2, 6, -1, 18.0],
		["teal", Vector3(3.15, 0, -2.25), "happy", 0, 7, -1, -16.0],
	]
	for c in cast:
		var m := crew(c[0], tip + c[1], 0.0, c[2], c[3], c[4])
		face(m, Vector3(cam.x, 0, cam.z))
		m.rotation.y += deg_to_rad(c[6])
		if c[5] >= 0:
			pose(m, 0.6)
			m.play_fidget(c[5])
			pose(m, 1.0)
		else:
			pose(m, 1.6)
	var purple: CrewModel = _models[4]
	turn_head(purple, 22.0, 4.0)
	# Warm key from camera left, cool planet-side rims behind the wings, soft fill.
	spot(tip + Vector3(-3.5, 3.4, 3.2), tip + Vector3(0, 1.0, -1.0), WARM, 5.0, 40.0, 12.0, true)
	spot(tip + Vector3(-4.5, 2.4, -4.0), tip + Vector3(-1.5, 1.2, -1.0), COOL, 7.0, 35.0, 10.0)
	spot(tip + Vector3(4.5, 2.4, -4.0), tip + Vector3(1.5, 1.2, -1.0), Color(0.75, 0.6, 1.0), 7.0, 35.0, 10.0)
	spot(cam + Vector3(1.5, 1.0, 0.0), tip + Vector3(0, 1.0, -1.0), COOL, 1.2, 45.0, 14.0)
	frame(cam, tip + Vector3(-0.35, 1.72, -1.2), 48.0, tip + Vector3(0, 1.4, 0), 2.8, 0.05)
	return await capture(out, "01_crew_lineup.png")


## 02 "One of you is lying": five crew face the camera in Command under the red
## emergency light, the vault glowing behind. Long lens, focus pulled past them
## onto the purple crewmate in the back row, the only suspicious face.
func shot_one_is_lying(out: String) -> Error:
	begin_shot("emergency", 202)
	var cam := Vector3(0.45, 1.62, -11.2)
	var liar_pos := Vector3(0.38, 0, -20.4)
	var front := [
		["blue", Vector3(-2.4, 0, -19.0), "neutral", 2, 2],
		["yellow", Vector3(-1.5, 0, -18.1), "happy", 1, 3],
		["green", Vector3(-0.58, 0, -17.6), "neutral", 3, 4],
		["orange", Vector3(1.34, 0, -17.6), "happy", 2, 6],
		["red", Vector3(2.3, 0, -18.4), "neutral", 0, 1],
	]
	for f in front:
		var m := crew(f[0], f[1], 0.0, f[2], f[3], f[4])
		face(m, Vector3(cam.x, 0, cam.z))
		pose(m, 1.5)
	var liar := crew("purple", liar_pos, 0.0, "suspicious", 1, 5)
	face(liar, Vector3(cam.x, 0, cam.z))
	pose(liar, 1.5)
	turn_head(liar, 14.0, 6.0)
	# The vault core glows in its cage behind them.
	seat_item("vault", "core")
	# Narrow cold key isolates the liar's visor; red rims from the vault side.
	spot(liar_pos + Vector3(1.6, 2.6, 2.4), liar_pos + Vector3(0, 1.55, 0), Color(0.75, 0.85, 1.0), 6.0, 14.0, 6.0)
	spot(liar_pos + Vector3(-1.8, 2.2, -2.6), liar_pos + Vector3(0, 1.5, 0), Color(1.0, 0.18, 0.08), 9.0, 30.0, 6.0)
	spot(Vector3(-3.5, 2.6, -21.5), Vector3(-1.5, 1.4, -18.0), Color(1.0, 0.2, 0.1), 7.0, 40.0, 7.0)
	spot(Vector3(4.5, 2.6, -21.5), Vector3(1.8, 1.4, -18.0), Color(1.0, 0.2, 0.1), 7.0, 40.0, 7.0)
	spot(cam + Vector3(0, 0.6, 0), Vector3(0.4, 1.4, -18.0), Color(1.0, 0.55, 0.45), 0.9, 30.0, 12.0)
	frame(cam, liar_pos + Vector3(0.0, 1.38, 0), 28.0, liar_pos + Vector3(0, 1.62, 0.15), 0.6, 0.32)
	return await capture(out, "02_one_of_you_is_lying.png", 6)


## 03 Portraits: four 3/4 helmet-and-shoulders portraits, each in a different
## room light with a coloured rim and shallow focus on the visor.
func shot_portraits(out: String) -> Error:
	var sitters := [
		# file, power, colour, variant, number, face, floor position, camera heading
		# (degrees, from the subject), 3/4 turn, rim colour, head turn, exposure
		["03a_portrait_blue_happy.png", "restored", "blue", 2, 2, "happy", Vector3(-3.6, 0, -3.8), 25.0, 32.0, COOL, -8.0, 1.0],
		["03b_portrait_purple_suspicious.png", "restored", "purple", 1, 5, "suspicious", Vector3(59.6, 0, 16.6), -139.0, -34.0, Color(0.7, 0.4, 1.0), 10.0, 0.62],
		["03c_portrait_red_angry.png", "emergency", "red", 0, 1, "angry", Vector3(40.5, 0, -20.6), -20.0, 30.0, Color(1.0, 0.25, 0.1), -6.0, 1.0],
		["03d_portrait_orange_shocked.png", "restored", "orange", 2, 6, "shocked", Vector3(22.6, 0, 1.6), 20.0, -30.0, CYAN, 6.0, 0.9],
	]
	var err := OK
	for i in sitters.size():
		var p: Array = sitters[i]
		begin_shot(p[1], 300 + i)
		var pos: Vector3 = p[6]
		var head := pos + Vector3(0, 1.62, 0)
		var heading := deg_to_rad(p[7])
		var cam := head + Vector3(sin(heading), 0.02, cos(heading)) * 1.95
		var m := crew(p[2], pos, 0.0, p[5], p[3], p[4])
		face(m, Vector3(cam.x, 0, cam.z))
		m.rotation.y += deg_to_rad(p[8])
		pose(m, 1.4)
		turn_head(m, p[10], 2.0)
		var to_cam := Vector3(cam.x - pos.x, 0, cam.z - pos.z).normalized()
		var side := to_cam.cross(Vector3.UP) * signf(p[8])
		# Key high and wide so its highlight misses the visor; rim from behind.
		spot(head + to_cam * 1.6 + side * 2.0 + Vector3(0, 1.4, 0), head, WARM, 3.0, 22.0, 6.0, true, 0.25)
		spot(head - to_cam * 1.6 - side * 1.3 + Vector3(0, 0.6, 0), head + Vector3(0, -0.1, 0), p[9], 9.0, 26.0, 5.0)
		spot(head + to_cam * 2.2 - side * 1.8 + Vector3(0, -0.3, 0), head, COOL, 0.7, 30.0, 6.0, false, 0.1)
		attrs.exposure_multiplier = p[11]
		# Subject sits on a third, looking into the open side of the frame.
		var aim := head - side * 0.16 + Vector3(0, -0.12, 0)
		frame(cam, aim, 26.0, head + to_cam * 0.18, 0.35, 0.2)
		err = await capture(out, p[0], 5)
		if err != OK:
			return err
	return err


## 04 Core run: a crewmate sprints down the Reactor-Medical corridor with the
## glowing core clutched to their chest, an angry chaser close behind, under
## emergency red. Low camera ahead of the runner, mid-stride.
func shot_core_run(out: String) -> Error:
	begin_shot("emergency", 404)
	var runner := crew("teal", Vector3(25.4, 0, 20.35), -90.0, "shocked", 0, 7)
	var chaser := crew("red", Vector3(28.3, 0, 19.6), -96.0, "angry", 0, 1)
	pose_stride(runner, 5.4, 0.12, true)
	pose_stride(chaser, 6.2, 0.62, false)
	var core := hold(runner.carry_anchor, "core")
	core.name = "Core"
	turn_head(runner, 0.0, -4.0)
	vfx.attach_trail(core, CYAN)
	# Cyan spill from the core plus warm emergency key and a hard red back rim.
	omni(runner.global_transform * Vector3(0, 1.3, 0.9), CYAN, 0.5, 1.6)
	spot(Vector3(23.0, 2.9, 21.2), Vector3(25.4, 1.3, 20.3), Color(1.0, 0.6, 0.4), 3.0, 30.0, 8.0, true, 0.3)
	spot(Vector3(31.5, 2.4, 20.0), Vector3(26.5, 1.3, 20.2), Color(1.0, 0.12, 0.06), 8.0, 25.0, 9.0)
	var cam := Vector3(22.5, 0.5, 19.35)
	frame(cam, Vector3(26.4, 1.25, 20.05), 46.0, Vector3(25.2, 1.45, 20.35), 1.4, 0.12)
	# Slide both runners in along the corridor so the core's trail lays down.
	var ends := [runner.position, chaser.position]
	for i in 9:
		var back := 0.42 * float(8 - i)
		runner.position = ends[0] + Vector3(back, 0, 0)
		chaser.position = ends[1] + Vector3(back, 0, 0)
		await get_tree().process_frame
	vfx.burst("footstep_dust", runner.global_transform * Vector3(0.1, 0.02, -0.35), Vector3(1, 0, 0))
	return await capture(out, "04_core_run.png", 3)


## 05 Shove: green shoves yellow at the peak of the thrust in Cargo; yellow
## recoils with a hurt face and loses the power cell, which spins away.
func shot_shove(out: String) -> Error:
	begin_shot("restored", 505)
	var attacker := crew("green", Vector3(38.55, 0, 0.55), 90.0, "angry", 3, 4)
	var victim := crew("yellow", Vector3(39.5, 0, 0.55), -90.0, "hurt", 1, 3)
	pose(attacker, 0.8, 1.2)
	pose(attacker, 0.4)
	attacker.play_shove()
	pose_overlay(attacker, 0.17)
	pose(victim, 1.0)
	victim.play_hit()
	pose_overlay(victim, 0.1)
	clear_hit_flash(victim)
	turn_head(attacker, -10.0, 4.0)
	var cell := place_item("cell", Transform3D(Basis.IDENTITY, Vector3(39.7, 1.05, 0.6)))
	vfx.attach_trail(cell, Color(1.0, 0.6, 0.15))
	spot(Vector3(42.2, 3.0, 3.6), Vector3(39.2, 1.3, 0.6), Color(1.0, 0.95, 0.88), 4.5, 34.0, 9.0, true, 0.3)
	spot(Vector3(41.6, 2.6, -2.4), Vector3(39.5, 1.4, 0.6), Color(1.0, 0.7, 0.25), 9.0, 30.0, 8.0)
	spot(Vector3(36.0, 2.4, -1.8), Vector3(38.5, 1.4, 0.6), Color(0.3, 1.0, 0.6), 7.0, 30.0, 8.0)
	frame(Vector3(41.7, 1.05, 3.7), Vector3(39.35, 1.3, 0.45), 40.0, Vector3(39.4, 1.45, 0.55), 1.3, 0.1)
	await wait(3)
	# The cell spins up and away behind the victim; the impact fires mid-flight.
	var from := cell.position
	var to := Vector3(40.75, 1.85, -0.35)
	for i in 6:
		var k := float(i + 1) / 6.0
		cell.position = from.lerp(to, k) + Vector3(0, 0.3 * 4.0 * k * (1.0 - k), 0)
		cell.rotation = Vector3(3.2, 5.0, 1.6) * k
		if i == 3:
			vfx.burst("shove_impact", Vector3(39.2, 1.3, 0.55), Vector3(1, 0, 0))
		await get_tree().process_frame
	return await capture(out, "05_shove.png", 1)


## 06 The gun question: over orange's shoulder, the gun from the armory is
## levelled at blue, who throws their hands up, shocked. A warning bolt cracks
## past their helmet into the lockers.
func shot_gun_question(out: String) -> Error:
	begin_shot("emergency", 606)
	var shooter := crew("orange", Vector3(38.2, 0, -22.0), 0.0, "angry", 2, 6)
	var target := crew("blue", Vector3(40.9, 0, -19.6), 0.0, "shocked", 2, 2)
	face(shooter, target.position)
	face(target, shooter.position)
	shooter.set_aiming(true)
	pose(shooter, 1.2)
	pose(target, 1.2)
	hands_up(target)
	var gun := hold(shooter.hand_anchor, "gun")
	gun.name = "Gun"
	(sockets["armory"] as SocketVisual).set_state(false, false, true)
	var d := (target.position - shooter.position).normalized()
	var right := d.cross(Vector3.UP)
	var cam := shooter.position - d * 1.05 + right * 0.62 + Vector3(0, 1.62, 0)
	spot(target.position + d * 1.2 - right * 2.4 + Vector3(0, 2.6, 0), target.position + Vector3(0, 1.3, 0), COOL, 6.0, 30.0, 8.0, true, 0.3)
	spot(target.position + d * 2.2 + right * 1.2 + Vector3(0, 2.0, 0), target.position + Vector3(0, 1.4, 0), Color(1.0, 0.2, 0.08), 12.0, 30.0, 6.0)
	spot(shooter.position - right * 1.5 + Vector3(0, 2.4, 0), shooter.position + Vector3(0, 1.4, 0), Color(1.0, 0.5, 0.2), 4.0, 35.0, 5.0)
	frame(cam, target.position + Vector3(0, 1.32, 0) - right * 0.35, 36.0, target.position + Vector3(0, 1.6, 0), 1.0, 0.14)
	await wait(4)
	var muzzle := gun.global_transform * Vector3(0, 0.235, -0.42)
	var forward := (gun.global_transform.basis * Vector3(0, 0, -1)).normalized()
	vfx.burst("muzzle_flash", muzzle, forward)
	vfx.tracer(muzzle, target.position + Vector3(0, 1.95, 0) + right * 0.45 + d * 5.0)
	return await capture(out, "06_gun_question.png", 1)


## 07 Rescue: white carries a downed green crewmate towards the medbay, which
## already glows with the revive field. Camera low by the bay, looking back.
func shot_rescue(out: String) -> Error:
	begin_shot("restored", 707)
	var cam := Vector3(0.55, 0.95, 24.75)
	var carrier := crew("white", Vector3(1.9, 0, 20.5), 0.0, "neutral", 3, 8)
	face(carrier, Vector3(3.0, 0, 23.0))
	var body := crew("green", Vector3.ZERO, 0.0, "downed", 3, 4)
	body.get_parent().remove_child(body)
	carrier.carry_anchor.add_child(body)
	body.transform = Transform3D.IDENTITY
	body.set_carried(true)
	pose(body, 1.5)
	pose_stride(carrier, 2.1, 0.3, true)
	(sockets["medbay"] as SocketVisual).set_state(false, false, true)
	spot(Vector3(-1.2, 2.9, 23.0), Vector3(1.9, 1.1, 20.6), WARM, 4.0, 36.0, 9.0, true, 0.3)
	spot(Vector3(3.6, 2.4, 17.4), Vector3(1.9, 1.3, 20.5), COOL, 9.0, 30.0, 7.0)
	omni(Vector3(3.3, 1.1, 22.7), Color(0.35, 1.0, 0.55), 1.6, 4.0)
	frame(cam, Vector3(2.25, 1.15, 20.6), 42.0, Vector3(1.95, 1.3, 20.9), 1.6, 0.1)
	await wait(4)
	vfx.burst("revive", Vector3(3.5, 0.75, 23.5))
	return await capture(out, "07_rescue.png", 3)


## 08 Airlock: from inside the airlock, red pleads with hands up while, framed
## by the inner doorway, purple works the cycle console with a sinister face.
func shot_airlock(out: String) -> Error:
	begin_shot("emergency", 808)
	var cam := Vector3(-12.9, 1.5, -0.95)
	var victim := crew("red", Vector3(-11.5, 0, -1.45), 0.0, "shocked", 0, 1)
	var operator := crew("purple", Vector3(-5.8, 0, 2.35), 0.0, "angry", 1, 5)
	face(victim, Vector3(cam.x, 0, cam.z))
	face(operator, Vector3(cam.x, 0, cam.z))
	pose(victim, 1.2)
	hands_up(victim)
	pose(operator, 1.4)
	turn_head(operator, 0.0, 10.0)
	(sockets["airlock_console"] as SocketVisual).set_state(false, false, true)
	# Under-lighting from the console makes the operator sinister.
	spot(Vector3(-6.4, 0.5, 2.0), Vector3(-5.8, 1.65, 2.35), Color(1.0, 0.25, 0.1), 7.0, 35.0, 3.0)
	spot(Vector3(-3.8, 2.8, 0.6), Vector3(-5.8, 1.5, 2.35), Color(1.0, 0.55, 0.2), 4.0, 25.0, 5.0)
	spot(Vector3(-10.4, 2.6, -2.0), Vector3(-11.5, 1.3, -1.45), Color(1.0, 0.12, 0.05), 6.0, 35.0, 4.0)
	spot(cam + Vector3(0.2, 0.6, 0.3), Vector3(-11.5, 1.5, -1.45), Color(1.0, 0.75, 0.6), 1.2, 30.0, 4.0, false, 0.2)
	frame(cam, Vector3(-7.4, 1.35, 1.15), 40.0, Vector3(-5.8, 1.65, 2.35), 2.5, 0.08)
	station.set_airlock_state("warning")
	await wait(4)
	station.set_airlock_state("warning")
	return await capture(out, "08_airlock.png", 2)


## 09 Ghost: a crewmate's ghost drifts past the Reactor as a living crewmate
## slots the last cell and the power wave rolls out. Glow is tamed so the core
## reads as light rather than a white-out.
func shot_ghost(out: String) -> Error:
	begin_shot("restored", 909)
	station.env.glow_intensity = 0.55
	attrs.exposure_multiplier = 0.72
	var cam := Vector3(61.0, 1.05, 14.45)
	var ghost := crew("blue", Vector3(58.7, 0, 17.1), 0.0, "ghost", 2, 2)
	ghost.set_ghost(true)
	face(ghost, Vector3(cam.x + 0.6, 0, cam.z))
	pose(ghost, 2.6)
	turn_head(ghost, -8.0, -6.0)
	vfx.attach_item_fx(ghost, "ghost")
	var worker := crew("yellow", Vector3(58.0, 0, 22.05), 0.0, "neutral", 1, 3)
	pose(worker, 1.2, 0.0, true)
	hold(worker.carry_anchor, "cell")
	for id in ["reactor_2", "reactor_3"]:
		(sockets[id] as SocketVisual).set_state(true, false, false)
	spot(Vector3(60.4, 2.6, 15.2), Vector3(58.7, 1.4, 17.1), COOL, 2.0, 30.0, 6.0, false, 0.3)
	spot(Vector3(56.4, 2.4, 19.4), Vector3(58.7, 1.4, 17.1), Color(0.7, 0.5, 1.0), 8.0, 35.0, 6.0)
	frame(cam, Vector3(59.9, 1.75, 18.6), 44.0, Vector3(58.7, 1.55, 17.1), 1.6, 0.1)
	await wait(4)
	vfx.burst("power_wave", Vfx.REACTOR_CORE)
	vfx.burst("insert_cell", Vector3(58.0, 0.9, 23.0))
	return await capture(out, "09_ghost.png", 8)


## 10 Blackout: three crew sweep Cargo with flashlights in total darkness; the
## LED visors are the only light on their faces. Side-on, so the beams cross
## the frame instead of flaring into the lens.
func shot_blackout(out: String) -> Error:
	begin_shot("blackout", 1010)
	var cast := [
		["white", Vector3(40.4, 0, -0.6), 4.0, "suspicious", 3, 8, Vector3(40.2, 0.0, 3.4)],
		["blue", Vector3(38.9, 0, -2.3), 14.0, "shocked", 2, 2, Vector3(38.6, 0.0, 1.6)],
		["orange", Vector3(42.0, 0, -2.6), -16.0, "neutral", 2, 6, Vector3(43.6, 0.3, 1.2)],
	]
	for c in cast:
		var m := crew(c[0], c[1], c[2], c[3], c[4], c[5])
		pose_stride(m, 1.1, 0.05 + 0.3 * float(_models.size()), false)
		flashlight(m, c[6])
	frame(Vector3(35.6, 1.05, 2.4), Vector3(40.6, 1.2, -1.6), 42.0, Vector3(40.4, 1.6, -0.5), 1.8, 0.1)
	return await capture(out, "10_blackout.png", 5)


## 11 Shuttle escape: in Docking the crew slot the core into the shuttle as the
## launch countdown pulses; blue and green stand guard. Low heroic angle off the
## shuttle's nose.
func shot_shuttle(out: String) -> Error:
	begin_shot("restored", 1111)
	attrs.exposure_multiplier = 0.9
	var cam := Vector3(15.7, 0.42, 4.1)
	var loader := crew("yellow", Vector3(20.0, 0, -0.62), 180.0, "happy", 1, 3)
	pose(loader, 1.4, 0.0, true)
	hold(loader.carry_anchor, "core")
	var guard_a := crew("blue", Vector3(18.1, 0, 0.9), 0.0, "happy", 2, 2)
	var guard_b := crew("green", Vector3(21.8, 0, 1.15), 0.0, "angry", 3, 4)
	face(guard_a, Vector3(cam.x + 1.0, 0, cam.z))
	face(guard_b, Vector3(25.5, 0, 4.5))
	pose(guard_a, 1.4)
	guard_b.set_aiming(true)
	pose(guard_b, 1.4)
	hold(guard_b.hand_anchor, "gun")
	(sockets["shuttle"] as SocketVisual).set_state(false, false, true)
	spot(Vector3(15.0, 1.6, 2.6), Vector3(19.5, 1.3, 0.2), Color(1.0, 0.72, 0.45), 5.0, 40.0, 10.0, true, 0.3)
	spot(Vector3(23.5, 3.0, -1.6), Vector3(20.5, 1.4, 0.4), CYAN, 9.0, 40.0, 8.0)
	spot(Vector3(16.0, 3.0, -1.2), Vector3(18.1, 1.4, 0.9), CYAN, 6.0, 30.0, 6.0)
	frame(cam, Vector3(20.0, 1.75, -1.3), 46.0, Vector3(19.4, 1.5, 0.3), 3.0, 0.06)
	await wait(3)
	vfx.countdown_pulse(Vector3(20.0, 0.0, -1.5), Color(1.0, 0.55, 0.15))
	return await capture(out, "11_shuttle_escape.png", 5)


## 12 Turntable trio: one blue crewmate shown front, 3/4 and back against the
## clean white Medical wall, evenly lit so the whole suit design reads.
func shot_turntable(out: String) -> Error:
	begin_shot("restored", 1212)
	var base := Vector3(3.4, 0, 16.0)
	var cam := Vector3(1.7, 1.0, 24.3)
	var yaws := [0.0, -40.0, 180.0]
	for i in 3:
		var m := crew("blue", base + Vector3(-1.25 + 1.25 * float(i), 0, 0), 0.0, "happy", 2, 2)
		face(m, Vector3(cam.x, 0, cam.z))
		m.rotation.y += deg_to_rad(yaws[i])
		pose(m, 1.4)
	spot(base + Vector3(-3.0, 3.2, 4.0), base + Vector3(0, 1.0, 0), Color(1.0, 0.96, 0.92), 5.0, 45.0, 12.0, true, 0.3)
	spot(base + Vector3(3.5, 2.0, 3.5), base + Vector3(0, 1.0, 0), COOL, 1.6, 45.0, 12.0, false, 0.2)
	spot(base + Vector3(0, 3.0, -1.5), base + Vector3(0, 1.4, 0.2), Color(0.6, 0.8, 1.0), 5.0, 60.0, 6.0)
	frame(cam, base + Vector3(0, 0.98, 0), 17.0, base + Vector3(0, 1.0, 0), 2.0, 0.04, false)
	return await capture(out, "12_turntable_trio.png")


## 13 Overhead: a tilt-shift look down into the open-topped station with tiny
## crew busy in Commons, Docking and Cargo.
func shot_overhead(out: String) -> Error:
	begin_shot("restored", 1313)
	var spots := [
		["red", Vector3(-1.0, 0, 0.5), 40.0, 0.0], ["blue", Vector3(0.6, 0, -0.4), -120.0, 0.0],
		["yellow", Vector3(0.9, 0, 1.4), 200.0, 0.0], ["green", Vector3(11.0, 0, 0.2), 90.0, 6.0],
		["purple", Vector3(19.6, 0, -0.7), 180.0, 0.0], ["orange", Vector3(23.5, 0, 2.5), -60.0, 3.4],
		["teal", Vector3(38.0, 0, 1.0), -90.0, 1.2], ["white", Vector3(4.0, 0, 3.4), 0.0, 0.0],
	]
	for s in spots:
		var m := crew(s[0], s[1], s[2], "happy", 0, 0)
		if s[3] > 0.0:
			pose_stride(m, s[3], 0.3, s[0] == "green")
		else:
			pose(m, 1.2)
	hold(_models[3].carry_anchor, "core")
	frame(Vector3(6.0, 27.0, 25.0), Vector3(16.0, 0.0, -3.0), 38.0, Vector3(12.0, 0.0, 0.5), 6.0, 0.16)
	return await capture(out, "13_overhead_station.png")


## 14 Squad selfie: orange holds the "camera" at arm's length in Commons with
## the squad crowding in behind and purple leaning in to photobomb, suspicious.
func shot_selfie(out: String) -> Error:
	begin_shot("restored", 1414)
	var lead := crew("orange", Vector3(-0.6, 0, 1.4), -12.0, "happy", 2, 6)
	lead.set_aiming(true)
	pose(lead, 1.2)
	var arm_tip := lead.hand_anchor.global_position
	var cast := [
		["blue", Vector3(-1.45, 0, 0.6), "happy", 2, 2],
		["yellow", Vector3(0.3, 0, 0.65), "happy", 1, 3],
		["green", Vector3(-2.15, 0, -0.1), "shocked", 3, 4],
		["purple", Vector3(1.2, 0, -0.05), "suspicious", 1, 5],
	]
	for c in cast:
		var m := crew(c[0], c[1], 0.0, c[2], c[3], c[4])
		face(m, arm_tip)
		pose(m, 1.3)
	# Purple leans in from the edge of the frame (feet are well out of shot).
	var purple: CrewModel = _models[4]
	purple.rotate_object_local(Vector3.BACK, deg_to_rad(12.0))
	turn_head(purple, 12.0, 0.0)
	var cam := arm_tip + Vector3(0.05, 0.32, 0.45)
	spot(cam + Vector3(-1.4, 1.2, 0.5), Vector3(-0.3, 1.4, 0.6), WARM, 4.0, 45.0, 8.0, true, 0.3)
	spot(Vector3(-0.3, 2.6, -2.6), Vector3(-0.3, 1.5, 0.5), COOL, 8.0, 40.0, 7.0)
	frame(cam, Vector3(-0.35, 1.4, 0.3), 64.0, Vector3(-0.6, 1.6, 1.3), 1.6, 0.08)
	return await capture(out, "14_squad_selfie.png")
