extends "res://tools/showcase/studio.gd"
## Set 1, characters: the crew as a cast. Lineup hero, the colour roster, every
## LED face, the four suit variants, 3/4 portraits, the "one of you is lying"
## shot, a turntable and the squad selfie. Purple is the running suspect.

const FOLDER := "1_characters"
## Render order. `key` is what --only matches; `method` is the shot function.
const SHOTS: Array[Dictionary] = [
	{"key": "lineup", "method": "shot_crew_lineup"},
	{"key": "roster", "method": "shot_roster"},
	{"key": "faces", "method": "shot_faces"},
	{"key": "variants", "method": "shot_variants"},
	{"key": "portraits", "method": "shot_portraits"},
	{"key": "lying", "method": "shot_one_is_lying"},
	{"key": "turntable", "method": "shot_turntable"},
	{"key": "selfie", "method": "shot_selfie"},
]


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


## 02 Roster: all eight suit colours in a shallow arc on the floating stage, the
## gas giant behind them; numbers 1-8 on their pauldrons.
func shot_roster(out: String) -> Error:
	begin_shot("blackout", 202)
	stage_lighting()
	var c := stage(5.2)
	var order := ["red", "blue", "yellow", "green", "purple", "orange", "teal", "white"]
	var faces := ["happy", "neutral", "happy", "happy", "suspicious", "happy", "neutral", "happy"]
	var cam := c + Vector3(0.0, 1.0, 8.0)
	for i in 8:
		var k := float(i) - 3.5
		var m := crew(order[i], c + Vector3(k * 1.05, 0, -absf(k) * absf(k) * 0.06), 0.0, faces[i], i % 4, i + 1)
		face(m, Vector3(cam.x, 0, cam.z + 4.0))
		pose(m, 1.2 + 0.1 * float(i))
	spot(c + Vector3(-5.0, 4.5, 6.0), c + Vector3(0, 1.0, 0), WARM, 7.0, 40.0, 16.0, true, 0.3)
	spot(c + Vector3(5.5, 2.5, 5.0), c + Vector3(0, 1.0, 0), COOL, 2.0, 40.0, 16.0, false, 0.2)
	spot(c + Vector3(-5.5, 2.8, -3.5), c + Vector3(-1.5, 1.2, 0), Color(0.6, 0.4, 1.0), 12.0, 40.0, 12.0)
	spot(c + Vector3(5.5, 2.8, -3.5), c + Vector3(1.5, 1.2, 0), CYAN, 12.0, 40.0, 12.0)
	frame(cam, c + Vector3(0, 1.15, 0), 34.0, c + Vector3(0, 1.3, 0), 3.0, 0.05)
	return await capture(out, "02_roster_all_colours.png")


## 03 Faces: every LED expression in one class photo on the stage, front row
## standing, back row on a riser: neutral, happy, shocked, angry / suspicious,
## hurt, downed, ghost.
func shot_faces(out: String) -> Error:
	begin_shot("blackout", 303)
	stage_lighting()
	var c := stage(3.2)
	var riser := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.4, 0.42, 0.9)
	riser.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.075, 0.09)
	mat.roughness = 0.35
	riser.material_override = mat
	riser.position = c + Vector3(0, 0.21, -0.75)
	set_root.add_child(riser)
	var rows := [
		[["blue", "neutral"], ["yellow", "happy"], ["orange", "shocked"], ["red", "angry"]],
		[["purple", "suspicious"], ["green", "hurt"], ["white", "downed"], ["teal", "ghost"]],
	]
	var cam := c + Vector3(0, 1.75, 6.2)
	for r in 2:
		for i in 4:
			var spec: Array = rows[r][i]
			var pos := c + Vector3((float(i) - 1.5) * 0.78 + (0.0 if r == 0 else 0.0), 0.42 * float(r), 0.15 - 0.75 * float(r))
			var m := crew(spec[0], pos, 0.0, spec[1], (i + r) % 4, r * 4 + i + 1)
			face(m, Vector3(cam.x, 0, cam.z + 2.0))
			pose(m, 1.2)
	spot(c + Vector3(-3.0, 3.6, 4.5), c + Vector3(0, 1.6, 0), WARM, 5.0, 35.0, 12.0, true, 0.15)
	spot(c + Vector3(3.2, 2.6, 4.0), c + Vector3(0, 1.6, 0), COOL, 1.5, 35.0, 12.0, false, 0.1)
	spot(c + Vector3(0, 3.5, -3.5), c + Vector3(0, 1.8, -0.4), Color(0.6, 0.75, 1.0), 10.0, 45.0, 8.0)
	frame(cam, c + Vector3(0, 1.85, -0.3), 24.0, c + Vector3(0, 1.8, -0.3), 1.6, 0.05)
	return await capture(out, "03_expressions.png")


## 04 Variants: the four helmet and backpack styles in one colour, turned away
## over the shoulder so tops, backpacks and the glowing pack numbers read.
func shot_variants(out: String) -> Error:
	begin_shot("blackout", 404)
	stage_lighting()
	var c := stage(3.0)
	var cam := c + Vector3(-1.2, 1.9, -5.6)
	for i in 4:
		var m := crew("teal", c + Vector3((float(i) - 1.5) * 1.1, 0, 0), 0.0, "happy", i, i + 1)
		face(m, Vector3(cam.x, 0, cam.z))
		m.rotation.y += PI + deg_to_rad(-30.0)
		pose(m, 1.2 + 0.15 * float(i))
		turn_head(m, -35.0, 0.0)
	spot(c + Vector3(-3.0, 3.6, -4.5), c + Vector3(0, 1.3, 0), WARM, 6.0, 40.0, 12.0, true, 0.3)
	spot(c + Vector3(3.5, 2.4, 3.0), c + Vector3(0, 1.4, 0), CYAN, 12.0, 40.0, 10.0)
	spot(c + Vector3(-3.5, 2.4, 3.0), c + Vector3(0, 1.4, 0), Color(0.6, 0.4, 1.0), 10.0, 40.0, 10.0)
	frame(cam, c + Vector3(0, 1.25, 0), 30.0, c + Vector3(0, 1.4, 0), 2.5, 0.05)
	return await capture(out, "04_variants.png")


## 05 Portraits: four 3/4 helmet-and-shoulders portraits, each in a different
## room light with a coloured rim and shallow focus on the visor.
func shot_portraits(out: String) -> Error:
	var sitters := [
		# file, power, colour, variant, number, face, floor position, camera heading
		# (degrees, from the subject), 3/4 turn, rim colour, head turn, exposure
		["05a_portrait_blue_happy.png", "restored", "blue", 2, 2, "happy", Vector3(-3.6, 0, -3.8), 25.0, 32.0, COOL, -8.0, 1.0],
		["05b_portrait_purple_suspicious.png", "restored", "purple", 1, 5, "suspicious", Vector3(59.6, 0, 16.6), -139.0, -34.0, Color(0.7, 0.4, 1.0), 10.0, 0.62],
		["05c_portrait_red_angry.png", "emergency", "red", 0, 1, "angry", Vector3(40.5, 0, -20.6), -20.0, 30.0, Color(1.0, 0.25, 0.1), -6.0, 1.0],
		["05d_portrait_orange_shocked.png", "restored", "orange", 2, 6, "shocked", Vector3(22.6, 0, 1.6), 20.0, -30.0, CYAN, 6.0, 0.9],
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


## 06 "One of you is lying": five crew face the camera in Command under the red
## emergency light, the vault glowing behind. Long lens, focus pulled past them
## onto the purple crewmate in the back row, the only suspicious face.
func shot_one_is_lying(out: String) -> Error:
	begin_shot("emergency", 202)
	var cam := Vector3(0.42, 1.6, -13.75)
	var liar_pos := Vector3(0.38, 0, -20.4)
	var front := [
		["blue", Vector3(2.75, 0, -19.7), "neutral", 2, 2],
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
	frame(cam, liar_pos + Vector3(0.0, 1.32, 0), 32.0, liar_pos + Vector3(0, 1.62, 0.15), 0.6, 0.3)
	return await capture(out, "06_one_of_you_is_lying.png", 6)


## 07 Turntable trio: one blue crewmate shown front, 3/4 and back against the
## clean white Medical wall, evenly lit so the whole suit design reads.
func shot_turntable(out: String) -> Error:
	begin_shot("restored", 1212)
	var base := Vector3(3.1, 0, 16.0)
	var cam := Vector3(1.4, 1.0, 23.3)
	var yaws := [0.0, -55.0, 180.0]
	for i in 3:
		var m := crew("blue", base + Vector3(-1.25 + 1.25 * float(i), 0, 0), 0.0, "happy", 2, 2)
		face(m, Vector3(cam.x, 0, cam.z))
		m.rotation.y += deg_to_rad(yaws[i])
		pose(m, 1.4)
	spot(base + Vector3(-3.0, 3.2, 4.0), base + Vector3(0, 1.0, 0), Color(1.0, 0.96, 0.92), 5.0, 45.0, 12.0, true, 0.3)
	spot(base + Vector3(3.5, 2.0, 3.5), base + Vector3(0, 1.0, 0), COOL, 1.6, 45.0, 12.0, false, 0.2)
	spot(base + Vector3(0, 3.0, -1.5), base + Vector3(0, 1.4, 0.2), Color(0.6, 0.8, 1.0), 5.0, 60.0, 6.0)
	frame(cam, base + Vector3(0, 0.98, 0), 19.0, base + Vector3(0, 1.0, 0), 2.0, 0.04, false)
	return await capture(out, "07_turntable_trio.png")


## 08 Squad selfie: orange points straight at the lens from arm's length in
## Commons, the squad crowding in behind and purple leaning in to photobomb.
func shot_selfie(out: String) -> Error:
	begin_shot("restored", 1414)
	var lead := crew("orange", Vector3(-0.6, 0, 1.4), -12.0, "happy", 2, 6)
	lead.set_aiming(true)
	pose(lead, 1.2)
	glove(lead, 1, "point")
	glove(lead, 0, "thumbs_up")
	var arm_tip := lead.hand_anchor.global_position
	var cast := [
		["blue", Vector3(-1.45, 0, 0.6), "happy", 2, 2],
		["yellow", Vector3(0.3, 0, 0.65), "happy", 1, 3],
		["green", Vector3(-2.15, 0, -0.1), "shocked", 3, 4],
		["purple", Vector3(1.5, 0, 0.45), "suspicious", 1, 5],
	]
	for c in cast:
		var m := crew(c[0], c[1], 0.0, c[2], c[3], c[4])
		face(m, arm_tip)
		pose(m, 1.3)
	# Purple leans in from the edge of the frame (feet are well out of shot).
	var purple: CrewModel = _models[4]
	purple.rotate_object_local(Vector3.BACK, deg_to_rad(14.0))
	turn_head(purple, 12.0, 0.0)
	var cam := arm_tip + Vector3(0.05, 0.32, 0.45)
	spot(cam + Vector3(-1.4, 1.2, 0.5), Vector3(-0.3, 1.4, 0.6), WARM, 4.0, 45.0, 8.0, true, 0.3)
	spot(Vector3(-0.3, 2.6, -2.6), Vector3(-0.3, 1.5, 0.5), COOL, 8.0, 40.0, 7.0)
	frame(cam, Vector3(-0.35, 1.4, 0.3), 64.0, Vector3(-0.6, 1.6, 1.3), 1.6, 0.08)
	return await capture(out, "08_squad_selfie.png")
