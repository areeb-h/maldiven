extends "res://tools/showcase/studio.gd"
## The key-art shot list. Each shot function dresses the set, lights it, frames
## the camera and captures one or more PNGs into `out`.

## Render order. `key` is what --only matches; `method` is the shot function.
const SHOTS: Array[Dictionary] = [
	{"key": "lineup", "method": "shot_crew_lineup"},
]


## 01 Crew lineup hero: the whole crew in a confident V in Commons, power
## restored, low camera, gas giant hanging over the north wall.
func shot_crew_lineup(out: String) -> Error:
	begin_shot("restored", 101)
	var c := Vector3(0, 0, -1.5)
	var spots := [
		["yellow", Vector3(0.0, 0, 0.6), "happy", 1, 3],
		["red", Vector3(-1.1, 0, -0.3), "happy", 0, 1],
		["blue", Vector3(1.1, 0, -0.3), "happy", 2, 2],
		["green", Vector3(-2.2, 0, -1.1), "happy", 3, 4],
		["purple", Vector3(2.2, 0, -1.1), "suspicious", 1, 5],
		["orange", Vector3(-3.3, 0, -1.9), "happy", 2, 6],
		["teal", Vector3(3.3, 0, -1.9), "neutral", 0, 7],
	]
	var cam := Vector3(0.0, 0.55, 5.4)
	for s in spots:
		var m := crew(s[0], c + s[1], 0.0, s[2], s[3], s[4])
		face(m, Vector3(cam.x, 0, cam.z + 2.0))
		pose(m, 1.4)
	frame(cam, c + Vector3(0, 1.75, 0), 50.0, c + Vector3(0, 1.2, 0.6), 4.0, 0.06)
	return await capture(out, "01_crew_lineup.png")
