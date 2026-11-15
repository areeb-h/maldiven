extends "res://tools/showcase/studio.gd"
## Set 2, the station as a film set: the exterior with the gas giant, a
## tilt-shift overhead, every room's establishing shot in its signature light,
## the long corridor and the reactor's power-restore wave. Each room shot keeps
## one or two crew in frame for scale.

const FOLDER := "2_station"
## Render order. `key` is what --only matches; `method` is the shot function.
const SHOTS: Array[Dictionary] = [
	{"key": "exterior", "method": "shot_exterior"},
	{"key": "overhead", "method": "shot_overhead"},
	{"key": "commons", "method": "shot_commons"},
	{"key": "command", "method": "shot_command"},
	{"key": "security", "method": "shot_security"},
	{"key": "docking", "method": "shot_docking"},
	{"key": "cargo", "method": "shot_cargo"},
	{"key": "engineering", "method": "shot_engineering"},
	{"key": "reactor_wave", "method": "shot_reactor_wave"},
	{"key": "medical", "method": "shot_medical"},
	{"key": "observation", "method": "shot_observation"},
	{"key": "corridor", "method": "shot_corridor"},
]


## Adds idle crew for scale: each entry is [colour, position, yaw, face].
func extras(cast: Array) -> void:
	for c in cast:
		var m := crew(c[0], c[1], c[2], c[3], _models.size() % 4, _models.size() + 1)
		pose(m, 1.0 + 0.2 * float(_models.size()))


## 01 Exterior: the whole open-topped station floating in front of the gas giant,
## seen from high off its south-east corner.
func shot_exterior(out: String) -> Error:
	begin_shot("restored", 2101)
	frame(Vector3(52.0, 16.0, 44.0), Vector3(22.0, 0.0, -6.0), 46.0, Vector3(28.0, 0.0, 0.0), 30.0, 0.0)
	return await capture(out, "01_exterior_planet.png")


## 02 Overhead: a tilt-shift look down into the open-topped station with tiny
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
		if s[0] == "green":
			hold(m, "core")
		if s[3] > 0.0:
			pose_stride(m, s[3], 0.3, s[0] == "green")
		else:
			pose(m, 1.2)
	frame(Vector3(6.0, 27.0, 25.0), Vector3(16.0, 0.0, -3.0), 38.0, Vector3(12.0, 0.0, 0.5), 6.0, 0.16)
	return await capture(out, "02_overhead_tilt_shift.png")


## 03 Commons: the mess hall from its south-east corner in full power, the
## planet over the north wall, two crew chatting by the tables.
func shot_commons(out: String) -> Error:
	begin_shot("restored", 2103)
	extras([["yellow", Vector3(1.6, 0, 1.4), -120.0, "happy"], ["blue", Vector3(0.5, 0, 0.6), 60.0, "happy"]])
	frame(Vector3(6.4, 1.55, 6.1), Vector3(-1.5, 1.6, -3.0), 64.0, Vector3(1.0, 1.4, 1.0), 6.0, 0.03)
	return await capture(out, "03_commons.png")


## 04 Command: the core vault under emergency red, its field humming, one crew
## member standing guard on the dais.
func shot_command(out: String) -> Error:
	begin_shot("emergency", 2104)
	seat_item("vault", "core")
	extras([["red", Vector3(-1.6, 0, -21.4), 20.0, "suspicious"]])
	frame(Vector3(2.4, 1.5, -14.6), Vector3(-0.4, 1.5, -23.0), 58.0, Vector3(-1.6, 1.4, -21.4), 5.0, 0.03)
	return await capture(out, "04_command_vault.png")


## 05 Security: monitor wall, lockers and the armory rack in alarm red.
func shot_security(out: String) -> Error:
	begin_shot("emergency", 2105)
	seat_item("armory", "gun")
	extras([["orange", Vector3(39.6, 0, -21.8), -150.0, "neutral"]])
	frame(Vector3(45.6, 1.6, -14.8), Vector3(38.5, 1.3, -23.5), 62.0, Vector3(39.6, 1.4, -21.8), 6.0, 0.03)
	return await capture(out, "05_security.png")


## 06 Docking: the escape shuttle on its pad, ramp down, teal trim.
func shot_docking(out: String) -> Error:
	begin_shot("restored", 2106)
	extras([["green", Vector3(17.2, 0, 0.6), 160.0, "happy"]])
	frame(Vector3(26.1, 1.35, 5.1), Vector3(19.0, 1.5, -3.0), 62.0, Vector3(19.0, 1.4, -2.0), 8.0, 0.03)
	return await capture(out, "06_docking_shuttle.png")


## 07 Cargo: crate stacks, the loading dock and the escape pod in its cradle.
func shot_cargo(out: String) -> Error:
	begin_shot("restored", 2107)
	extras([["white", Vector3(41.0, 0, 1.2), 130.0, "neutral"]])
	frame(Vector3(37.8, 1.6, -6.2), Vector3(43.5, 1.2, 3.5), 62.0, Vector3(41.0, 1.4, 1.2), 8.0, 0.03)
	return await capture(out, "07_cargo_pod.png")


## 08 Engineering: generator, pipe runs and coolant tanks in sodium yellow.
func shot_engineering(out: String) -> Error:
	begin_shot("restored", 2108)
	extras([["teal", Vector3(60.4, 0, -2.6), 170.0, "neutral"]])
	frame(Vector3(66.6, 1.6, 5.4), Vector3(58.5, 1.3, -4.0), 62.0, Vector3(60.4, 1.4, -2.6), 8.0, 0.03)
	return await capture(out, "08_engineering.png")


## 09 Reactor, power restored: the third cell goes in and the power wave rolls
## out from the core. Low angle, glow tamed so the core keeps its shape.
func shot_reactor_wave(out: String) -> Error:
	begin_shot("restored", 2109)
	station.env.glow_intensity = 0.5
	station.current["reactor"] = 1.2  # full 2.0 blooms the core to a flat white shape
	attrs.exposure_multiplier = 0.85
	var worker := crew("yellow", Vector3(66.0, 0, 21.9), 0.0, "happy", 1, 3)
	hold(worker, "cell")
	pose(worker, 1.2, 0.0, true)
	for id in ["reactor_1", "reactor_2"]:
		(sockets[id] as SocketVisual).set_state(true, false, false)
	frame(Vector3(58.2, 0.55, 14.6), Vector3(62.4, 2.3, 19.6), 54.0, Vector3(62.0, 1.6, 19.3), 6.0, 0.03)
	await wait(4)
	vfx.burst("power_wave", Vfx.REACTOR_CORE)
	vfx.burst("insert_cell", Vector3(66.0, 0.9, 23.0))
	return await capture(out, "09_reactor_power_wave.png", 7)


## 10 Medical: beds, the medbay scanner and green trim, calm and clean.
func shot_medical(out: String) -> Error:
	begin_shot("restored", 2110)
	extras([["green", Vector3(2.0, 0, 21.6), 150.0, "happy"]])
	frame(Vector3(6.3, 1.6, 15.0), Vector3(-1.0, 1.0, 22.5), 62.0, Vector3(2.0, 1.4, 21.6), 8.0, 0.03)
	return await capture(out, "10_medical.png")


## 11 Observation: the lounge and its raised deck under the big windows.
func shot_observation(out: String) -> Error:
	begin_shot("restored", 2111)
	extras([["purple", Vector3(29.5, 0.24, 16.6), 180.0, "neutral"], ["blue", Vector3(32.2, 0.24, 16.8), 170.0, "happy"]])
	frame(Vector3(37.6, 1.6, 25.6), Vector3(29.0, 1.5, 16.0), 62.0, Vector3(30.8, 1.4, 16.8), 8.0, 0.03)
	return await capture(out, "11_observation.png")


## 12 Corridor: the long Command-Security run under emergency light, a single
## figure at the far end; pure leading lines.
func shot_corridor(out: String) -> Error:
	begin_shot("emergency", 2112)
	extras([["red", Vector3(27.5, 0, -20.0), -90.0, "angry"]])
	frame(Vector3(8.2, 1.4, -20.6), Vector3(30.0, 1.2, -19.9), 40.0, Vector3(27.5, 1.4, -20.0), 6.0, 0.05)
	return await capture(out, "12_corridor.png")
