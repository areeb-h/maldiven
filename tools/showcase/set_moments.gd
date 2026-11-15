extends "res://tools/showcase/studio.gd"
## Set 4, gameplay moments: the core run, a shove with a flying cell, the gun
## stand-off, a rescue carry, the airlock, a ghost, the blackout and the shuttle.

const FOLDER := "4_moments"
## Render order. `key` is what --only matches; `method` is the shot function.
const SHOTS: Array[Dictionary] = [
	{"key": "core_run", "method": "shot_core_run"},
	{"key": "shove", "method": "shot_shove"},
	{"key": "gun", "method": "shot_gun_question"},
	{"key": "rescue", "method": "shot_rescue"},
	{"key": "airlock", "method": "shot_airlock"},
	{"key": "ghost", "method": "shot_ghost"},
	{"key": "blackout", "method": "shot_blackout"},
	{"key": "shuttle", "method": "shot_shuttle"},
	{"key": "spaced", "method": "shot_spaced"},
]


## 01 Core run: a crewmate sprints down the long Command-Security corridor with
## the glowing core clutched to their chest, an angry chaser close behind, under
## emergency red. Camera ahead and off-axis so the visor clears the core.
func shot_core_run(out: String) -> Error:
	begin_shot("emergency", 404)
	station.env.glow_intensity = 0.7
	var runner := crew("teal", Vector3(22.4, 0, -19.45), -90.0, "shocked", 0, 7)
	var chaser := crew("red", Vector3(25.2, 0, -20.3), -94.0, "angry", 0, 1)
	var core := hold(runner, "core")
	pose_stride(runner, 5.4, 0.12, true)
	pose_stride(chaser, 6.2, 0.62, false)
	vfx.attach_trail(core, CYAN)
	omni(runner.global_transform * Vector3(0, 1.3, 0.9), CYAN, 0.4, 1.4)
	spot(Vector3(19.6, 2.9, -18.9), Vector3(22.4, 1.4, -19.45), Color(1.0, 0.62, 0.42), 3.0, 30.0, 8.0, true, 0.3)
	spot(Vector3(28.5, 2.4, -19.6), Vector3(23.5, 1.3, -19.8), Color(1.0, 0.12, 0.06), 8.0, 25.0, 9.0)
	var cam := Vector3(19.0, 1.5, -20.95)
	frame(cam, Vector3(23.2, 1.15, -19.8), 44.0, Vector3(22.3, 1.6, -19.45), 1.4, 0.12)
	# Slide both runners in along the corridor so the core's trail lays down.
	var ends := [runner.position, chaser.position]
	for i in 9:
		var back := 0.42 * float(8 - i)
		runner.position = ends[0] + Vector3(back, 0, 0)
		chaser.position = ends[1] + Vector3(back, 0, 0)
		await get_tree().process_frame
	vfx.burst("footstep_dust", runner.global_transform * Vector3(0.1, 0.02, -0.35), Vector3(1, 0, 0))
	return await capture(out, "01_core_run.png", 3)


## 02 Shove: green shoves yellow at the peak of the thrust in Cargo; yellow
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
	spot(Vector3(37.0, 3.0, 3.4), Vector3(39.4, 1.4, 0.55), Color(1.0, 0.95, 0.88), 4.5, 30.0, 9.0, true, 0.3)
	spot(Vector3(41.8, 2.6, -1.8), Vector3(39.5, 1.4, 0.55), Color(1.0, 0.7, 0.25), 9.0, 30.0, 8.0)
	spot(Vector3(36.2, 2.4, -2.0), Vector3(38.5, 1.4, 0.55), Color(0.3, 1.0, 0.6), 7.0, 30.0, 8.0)
	frame(Vector3(38.0, 1.12, 2.75), Vector3(39.55, 1.32, 0.3), 46.0, Vector3(39.5, 1.55, 0.55), 1.2, 0.1)
	await wait(3)
	# The cell spins up and away behind the victim; the impact fires mid-flight.
	var from := cell.position
	var to := Vector3(40.75, 1.85, -0.35)
	for i in 6:
		var k := float(i + 1) / 6.0
		cell.position = from.lerp(to, k) + Vector3(0, 0.3 * 4.0 * k * (1.0 - k), 0)
		cell.rotation = Vector3(3.2, 5.0, 1.6) * k
		if i == 4:
			vfx.burst("shove_impact", Vector3(39.2, 1.3, 0.55), Vector3(1, 0, 0))
		await get_tree().process_frame
	return await capture(out, "02_shove.png", 1)


## 03 The gun question: over orange's shoulder, the gun from the armory is
## levelled at blue, who throws their hands up, shocked. A warning bolt cracks
## past their helmet into the lockers.
func shot_gun_question(out: String) -> Error:
	begin_shot("emergency", 606)
	var shooter := crew("orange", Vector3(38.2, 0, -22.0), 0.0, "angry", 2, 6)
	var target := crew("blue", Vector3(40.9, 0, -19.6), 0.0, "shocked", 2, 2)
	face(shooter, target.position)
	face(target, shooter.position)
	var gun := hold(shooter, "gun")
	shooter.set_aiming(true)
	pose(shooter, 1.2)
	# Warning shot: trigger squeeze and the first instant of the recoil kick.
	shooter.on_shot()
	pose_overlay(shooter, 0.05)
	pose(target, 1.2)
	hands_up(target)
	(sockets["armory"] as SocketVisual).set_state(false, false, true)
	var d := (target.position - shooter.position).normalized()
	var right := d.cross(Vector3.UP)
	var cam := shooter.position - d * 1.5 + right * 1.3 + Vector3(0, 1.42, 0)
	spot(target.position + d * 1.2 - right * 2.4 + Vector3(0, 2.6, 0), target.position + Vector3(0, 1.3, 0), COOL, 6.0, 30.0, 8.0, true, 0.3)
	spot(target.position + d * 2.2 + right * 1.2 + Vector3(0, 2.0, 0), target.position + Vector3(0, 1.4, 0), Color(1.0, 0.2, 0.08), 12.0, 30.0, 6.0)
	spot(shooter.position - right * 1.5 + Vector3(0, 2.4, 0), shooter.position + Vector3(0, 1.4, 0), Color(1.0, 0.5, 0.2), 4.0, 35.0, 5.0)
	frame(cam, target.position + Vector3(0, 1.3, 0) - right * 0.55, 38.0, target.position + Vector3(0, 1.6, 0), 1.2, 0.12)
	await wait(4)
	var tip := muzzle(gun)
	vfx.burst("muzzle_flash", tip.origin, -tip.basis.z)
	vfx.tracer(tip.origin, target.position + Vector3(0, 1.95, 0) + right * 0.45 + d * 5.0)
	return await capture(out, "03_gun_standoff.png", 1)


## 04 Rescue: white carries a downed green crewmate along the medbay towards
## its glowing revive field. Framed from the carried crewmate's head side so the
## limp body reads across the carrier's arms.
func shot_rescue(out: String) -> Error:
	begin_shot("restored", 707)
	var cam := Vector3(2.75, 1.0, 18.85)
	var carrier := crew("white", Vector3(0.6, 0, 21.7), 90.0, "neutral", 3, 8)
	var body := crew("green", Vector3.ZERO, 0.0, "downed", 3, 4)
	body.get_parent().remove_child(body)
	carrier.carry_anchor.add_child(body)
	body.transform = Transform3D.IDENTITY
	body.set_carried(true)
	pose(body, 1.5)
	pose_stride(carrier, 2.1, 0.3, true)
	turn_head(carrier, 18.0, 4.0)
	(sockets["medbay"] as SocketVisual).set_state(false, false, true)
	spot(Vector3(3.6, 3.0, 19.6), Vector3(0.6, 1.2, 21.7), WARM, 4.0, 34.0, 9.0, true, 0.3)
	spot(Vector3(-2.0, 2.4, 23.4), Vector3(0.6, 1.3, 21.7), COOL, 9.0, 30.0, 7.0)
	omni(Vector3(3.3, 1.1, 22.8), Color(0.35, 1.0, 0.55), 2.0, 4.5)
	frame(cam, Vector3(1.55, 1.2, 22.3), 46.0, Vector3(0.75, 1.3, 21.5), 1.8, 0.1)
	await wait(4)
	vfx.burst("revive", Vector3(3.5, 0.75, 23.5))
	return await capture(out, "04_rescue.png", 3)


## 05 Airlock: from inside the airlock, red pleads with hands up while, framed
## by the inner doorway, purple works the cycle console with a sinister face.
func shot_airlock(out: String) -> Error:
	begin_shot("emergency", 808)
	var cam := Vector3(-14.6, 1.45, -2.0)
	var victim := crew("red", Vector3(-12.6, 0, -1.45), 0.0, "shocked", 0, 1)
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
	spot(Vector3(-11.2, 2.6, -2.3), Vector3(-12.6, 1.3, -1.45), Color(1.0, 0.12, 0.05), 6.0, 35.0, 4.0)
	spot(cam + Vector3(0.2, 0.6, 0.4), Vector3(-12.6, 1.5, -1.45), Color(1.0, 0.75, 0.6), 1.2, 30.0, 4.0, false, 0.2)
	frame(cam, Vector3(-8.6, 1.4, 0.75), 40.0, Vector3(-5.8, 1.65, 2.35), 2.5, 0.08)
	station.set_airlock_state("warning")
	await wait(4)
	station.set_airlock_state("warning")
	return await capture(out, "05_airlock.png", 2)


## 06 Ghost: a crewmate's ghost drifts past the Reactor as a living crewmate
## slots the last cell and the power wave rolls out. Glow is tamed so the core
## reads as light rather than a white-out.
func shot_ghost(out: String) -> Error:
	begin_shot("restored", 909)
	station.env.glow_intensity = 0.45
	station.current["reactor"] = 1.1  # the restored reactor (2.0) blooms to white at this distance
	attrs.exposure_multiplier = 0.8
	var cam := Vector3(61.4, 0.5, 13.0)
	var ghost := crew("blue", Vector3(59.3, 0, 17.0), 0.0, "ghost", 2, 2)
	ghost.set_ghost(true)
	face(ghost, Vector3(cam.x + 0.6, 0, cam.z))
	pose(ghost, 2.6)
	turn_head(ghost, -8.0, -6.0)
	vfx.attach_item_fx(ghost, "ghost")
	var worker := crew("yellow", Vector3(58.0, 0, 22.05), 0.0, "neutral", 1, 3)
	hold(worker, "cell")
	pose(worker, 1.2, 0.0, true)
	for id in ["reactor_2", "reactor_3"]:
		(sockets[id] as SocketVisual).set_state(true, false, false)
	spot(Vector3(61.0, 2.6, 14.6), Vector3(59.3, 1.4, 17.0), COOL, 2.0, 30.0, 6.0, false, 0.3)
	spot(Vector3(57.0, 2.4, 19.4), Vector3(59.3, 1.4, 17.0), Color(0.7, 0.5, 1.0), 8.0, 35.0, 6.0)
	frame(cam, Vector3(60.3, 2.15, 18.0), 44.0, Vector3(59.3, 1.6, 17.0), 1.6, 0.1)
	await wait(4)
	vfx.burst("power_wave", Vfx.REACTOR_CORE)
	vfx.burst("insert_cell", Vector3(58.0, 0.9, 23.0))
	return await capture(out, "06_ghost.png", 8)


## 07 Blackout: three crew sweep Cargo with flashlights in total darkness; the
## LED visors are the only light on their faces. Side-on, so the beams cross
## the frame instead of flaring into the lens.
func shot_blackout(out: String) -> Error:
	begin_shot("blackout", 1010)
	station.env.fog_density = 0.006
	var cast := [
		["white", Vector3(39.7, 0, 0.2), 20.0, "suspicious", 3, 8, Vector3(41.2, 0.0, 3.6)],
		["blue", Vector3(41.0, 0, -1.3), 8.0, "shocked", 2, 2, Vector3(41.9, 0.0, 2.4)],
		["orange", Vector3(42.4, 0, -2.9), 32.0, "neutral", 2, 6, Vector3(44.8, 0.3, 0.2)],
	]
	for c in cast:
		var m := crew(c[0], c[1], c[2], c[3], c[4], c[5])
		pose_stride(m, 1.1, 0.05 + 0.3 * float(_models.size()), false)
		flashlight(m, c[6], 0.07)
	frame(Vector3(37.4, 1.05, 2.6), Vector3(40.9, 1.3, -1.2), 44.0, Vector3(39.75, 1.6, 0.2), 2.2, 0.1)
	return await capture(out, "07_blackout.png", 5)


## 08 Shuttle escape: in Docking the crew slot the core into the shuttle as the
## launch countdown pulses; blue and green stand guard. Low heroic angle off the
## shuttle's nose.
func shot_shuttle(out: String) -> Error:
	begin_shot("restored", 1111)
	attrs.exposure_multiplier = 0.9
	var cam := Vector3(15.7, 0.42, 4.1)
	var loader := crew("yellow", Vector3(20.0, 0, -0.62), 180.0, "happy", 1, 3)
	hold(loader, "core")
	pose(loader, 1.4, 0.0, true)
	var guard_a := crew("blue", Vector3(17.4, 0, 1.7), 0.0, "happy", 2, 2)
	var guard_b := crew("green", Vector3(21.8, 0, 1.15), 0.0, "angry", 3, 4)
	face(guard_a, Vector3(cam.x + 1.0, 0, cam.z))
	face(guard_b, Vector3(25.5, 0, 4.5))
	pose(guard_a, 1.4)
	hold(guard_b, "gun")
	guard_b.set_aiming(true)
	pose(guard_b, 1.4)
	(sockets["shuttle"] as SocketVisual).set_state(false, false, true)
	spot(Vector3(15.0, 1.6, 2.6), Vector3(19.5, 1.3, 0.2), Color(1.0, 0.72, 0.45), 5.0, 40.0, 10.0, true, 0.3)
	spot(Vector3(23.5, 3.0, -1.6), Vector3(20.5, 1.4, 0.4), CYAN, 9.0, 40.0, 8.0)
	spot(Vector3(16.0, 3.0, -1.2), Vector3(18.1, 1.4, 0.9), CYAN, 6.0, 30.0, 6.0)
	frame(cam, Vector3(20.0, 1.75, -1.3), 46.0, Vector3(19.4, 1.5, 0.3), 3.0, 0.06)
	await wait(3)
	vfx.countdown_pulse(Vector3(20.0, 0.0, -1.5), Color(1.0, 0.55, 0.15))
	return await capture(out, "08_shuttle_escape.png", 5)


## 09 Spaced: the airlock vents; frost streams out of the open hull door and a
## red crewmate tumbles away towards the gas giant: the gameplay's weightless
## Jolt ragdoll (CrewRagdoll), caught a moment after the blast.
func shot_spaced(out: String) -> Error:
	begin_shot("restored", 4109)
	var dir := Vector3(-2.0, 0.4, 0.9)
	var body := crew("red", Vector3(-15.6, 0.5, 0.2), -90.0, "shocked", 0, 1)
	pose(body, 0.5, 0.0, false, true)
	station.set_airlock_state("venting")
	var rd := CrewRagdoll.spawn(body, set_root, dir, false, 8)
	if rd != null:
		rd.autonomous = true
		rd.follow_root = true
		rd.weightless()
		for bone in rd.parts:
			(rd.parts[bone] as RigidBody3D).linear_velocity = dir
		rd.spin(Vector3(0.8, 0.3, -0.6).normalized() * 3.0)
	spot(Vector3(-15.6, 3.0, 3.4), Vector3(-17.5, 1.4, 1.0), WARM, 5.0, 34.0, 9.0, false, 0.3)
	spot(Vector3(-20.0, 2.0, -1.5), Vector3(-17.5, 1.4, 1.0), Color(1.0, 0.2, 0.08), 8.0, 34.0, 7.0)
	frame(Vector3(-16.4, 1.0, 6.3), Vector3(-18.6, 2.2, -1.0), 44.0, Vector3(-17.6, 1.4, 1.1), 2.5, 0.05)
	vfx.burst("airlock_vent", Vector3(-15.2, 1.2, 0.0), Vector3(-1, 0, 0))
	await wait(8)
	vfx.burst("spaced", body.global_position + Vector3(0, 1.0, 0), dir)
	return await capture(out, "09_spaced.png", 6)
