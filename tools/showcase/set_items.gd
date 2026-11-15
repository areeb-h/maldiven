extends "res://tools/showcase/studio.gd"
## Set 3, product shots: the gun, power cell and core as hero objects on the
## floating stage with dramatic product lighting (warm key, two coloured rims,
## the gas giant as backdrop), the three together, and every socket.

const FOLDER := "3_items"
## Render order. `key` is what --only matches; `method` is the shot function.
const SHOTS: Array[Dictionary] = [
	{"key": "gun_hero", "method": "shot_gun"},
	{"key": "cell_hero", "method": "shot_cell"},
	{"key": "core_hero", "method": "shot_core"},
	{"key": "items_trio", "method": "shot_trio"},
	{"key": "sockets", "method": "shot_sockets"},
]


## Product rig around `subject`: soft warm key high on the left, two hard
## coloured rims behind, a faint fill, and a pool of light on the stage.
func product_lights(subject: Vector3, rim_a: Color, rim_b: Color, scale := 1.0) -> void:
	spot(subject + Vector3(-1.6, 2.0, 2.2) * scale, subject, WARM, 4.0, 30.0, 6.0 * scale, true, 0.6)
	spot(subject + Vector3(-1.8, 0.9, -1.6) * scale, subject, rim_a, 10.0, 26.0, 5.0 * scale)
	spot(subject + Vector3(1.8, 1.1, -1.5) * scale, subject, rim_b, 10.0, 26.0, 5.0 * scale)
	spot(subject + Vector3(1.8, 0.2, 2.0) * scale, subject, COOL, 0.6, 35.0, 6.0 * scale, false, 0.2)
	spot(subject + Vector3(0, 3.0, 0.3) * scale, subject - Vector3(0, 0.4, 0), Color(0.8, 0.9, 1.0), 2.0, 22.0, 5.0 * scale)


## 01 The gun: the chunky toy blaster floating at a hero angle over the stage,
## muzzle towards the lens, charge cells glowing.
func shot_gun(out: String) -> Error:
	begin_shot("blackout", 3101)
	stage_lighting()
	var c := stage(1.1)
	var xf := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-8.0), deg_to_rad(35.0), deg_to_rad(12.0))), c + Vector3(0, 0.42, 0))
	var gun := stage_item("gun", xf)
	product_lights(gun.global_position + Vector3(0, 0.1, 0), Color(1.0, 0.45, 0.15), CYAN, 0.6)
	frame(c + Vector3(0.35, 0.62, 1.25), c + Vector3(0.0, 0.5, 0), 30.0, gun.global_position + Vector3(0, 0.1, 0.1), 0.35, 0.12)
	return await capture(out, "01_gun.png", 5)


## 02 The power cell: standing on the stage, amber core glowing through its
## shell, low hero angle.
func shot_cell(out: String) -> Error:
	begin_shot("blackout", 3102)
	stage_lighting()
	var c := stage(1.1, Vector3.ZERO, Color(1.0, 0.6, 0.15))
	var cell := stage_item("cell", Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), c))
	product_lights(c + Vector3(0, 0.3, 0), Color(1.0, 0.55, 0.15), Color(0.6, 0.4, 1.0), 0.7)
	frame(c + Vector3(0.45, 0.22, 1.5), c + Vector3(0.05, 0.36, 0), 30.0, cell.global_position + Vector3(0, 0.3, 0.1), 0.45, 0.12)
	return await capture(out, "02_power_cell.png", 6)


## 03 The core: the station's heart on the stage, rings turning, motes rising.
func shot_core(out: String) -> Error:
	begin_shot("blackout", 3103)
	stage_lighting()
	var c := stage(1.1)
	var core := stage_item("core", Transform3D(Basis.IDENTITY, c))
	product_lights(c + Vector3(0, 0.36, 0), CYAN, Color(0.6, 0.4, 1.0), 0.7)
	frame(c + Vector3(-0.4, 0.3, 1.55), c + Vector3(0.0, 0.42, 0), 30.0, core.global_position + Vector3(0, 0.36, 0.1), 0.5, 0.12)
	return await capture(out, "03_core.png", 8)


## 04 The trio: gun, cell and core together, the "what you fight over" shot.
func shot_trio(out: String) -> Error:
	begin_shot("blackout", 3104)
	stage_lighting()
	var c := stage(1.7)
	stage_item("cell", Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), c + Vector3(-0.75, 0, -0.1)))
	stage_item("core", Transform3D(Basis.IDENTITY, c + Vector3(0.05, 0, -0.35)))
	stage_item("gun", Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(-60.0), deg_to_rad(90.0))), c + Vector3(0.75, 0.05, 0.15)))
	product_lights(c + Vector3(0, 0.3, 0), Color(1.0, 0.5, 0.15), CYAN, 1.0)
	frame(c + Vector3(0.0, 0.75, 2.6), c + Vector3(0, 0.3, -0.1), 32.0, c + Vector3(0, 0.3, 0), 1.2, 0.08)
	return await capture(out, "04_items_trio.png", 6)


## 05 Sockets: every interaction fixture in one arc on a wide stage: reactor
## socket, vault, shuttle and pod launch sockets, armory rack, medbay and the
## airlock console.
func shot_sockets(out: String) -> Error:
	begin_shot("blackout", 3105)
	stage_lighting()
	var c := stage(6.4, Vector3(0, 0, -3.0))
	var kinds := ["reactor", "vault", "shuttle", "pod", "armory", "medbay", "airlock_console"]
	var states := [[true, false, false], [true, true, false], [false, false, true], [false, false, true], [false, false, false], [false, false, true], [false, false, true]]
	for i in kinds.size():
		var a := deg_to_rad((float(i) - 3.0) * 16.0)
		var socket: Node3D = Props.make_socket(kinds[i])
		set_root.add_child(socket)
		socket.global_position = c + Vector3(sin(a) * 5.2, 0, 3.6 - cos(a) * 5.2)
		socket.rotation.y = -a * 0.6
		(socket as SocketVisual).set_state(states[i][0], states[i][1], states[i][2])
		if kinds[i] == "vault":
			var core := Props.make_item("core")
			socket.add_child(core)
			core.transform = (socket as SocketVisual).get_seat_transform()
			vfx.attach_item_fx(core, "core")
		spot(socket.global_position + Vector3(0, 3.2, 1.6), socket.global_position + Vector3(0, 0.6, 0), WARM, 4.0, 28.0, 6.0, i % 2 == 0, 0.4)
	spot(c + Vector3(-7.0, 3.0, -2.0), c + Vector3(-2.0, 0.8, 0), Color(0.6, 0.4, 1.0), 10.0, 40.0, 14.0)
	spot(c + Vector3(7.0, 3.0, -2.0), c + Vector3(2.0, 0.8, 0), CYAN, 10.0, 40.0, 14.0)
	frame(c + Vector3(0, 2.4, 9.2), c + Vector3(0, 0.6, -0.3), 40.0, c + Vector3(0, 0.8, -1.4), 4.0, 0.04)
	return await capture(out, "05_sockets.png", 6)
