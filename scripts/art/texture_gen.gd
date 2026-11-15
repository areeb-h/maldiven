extends SceneTree
## Offline generator for the station's tileable PBR texture sets. Writes PNGs
## into res://assets/textures/. Everything is original and procedural (no
## downloaded assets). Re-run with:
##   godot --headless --path . --script res://scripts/art/texture_gen.gd
## then `--headless --path . --editor --import --quit` to import them.
##
## Sets (each: _albedo.png, _normal.png, _orm.png with R=AO, G=rough, B=metal):
##   floor_plate  1024px = 2 m: four bevelled tread plates with bolts and grime.
##   wall_panel   1024px = 2 m: two bevelled painted panels, screws, vent, chips.
##   metal_paint   512px = 1 m: painted metal with scratches for props.
## Plus grime_decal.png (RGBA smudge) for Decal nodes.

const OUT := "res://assets/textures/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var started := Time.get_ticks_msec()
	_floor_plate(1024)
	_wall_panel(1024)
	_metal_paint(512)
	_grime_decal(512)
	print("textures generated in %d ms" % (Time.get_ticks_msec() - started))
	quit()


# --- helpers -----------------------------------------------------------------

func _noise(size: int, period_px: float, octaves: int, seed_value: int, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.noise_type = kind
	noise.seed = seed_value
	noise.frequency = 1.0 / period_px
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	var image := noise.get_seamless_image(size, size, false, false, 0.1, true)
	image.convert(Image.FORMAT_L8)
	var bytes := image.get_data()
	var out := PackedFloat32Array()
	out.resize(size * size)
	for i in range(size * size):
		out[i] = float(bytes[i]) / 255.0
	return out


func _sstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _normal_from_height(height: PackedFloat32Array, size: int, strength: float) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	for y in range(size):
		var ym := ((y - 1 + size) % size) * size
		var yp := ((y + 1) % size) * size
		var row := y * size
		for x in range(size):
			var xm := (x - 1 + size) % size
			var xp := (x + 1) % size
			var dx := (height[row + xp] - height[row + xm]) * strength
			var dy := (height[yp + x] - height[ym + x]) * strength
			var n := Vector3(-dx, dy, 1.0).normalized()
			var i := (row + x) * 3
			bytes[i] = int((n.x * 0.5 + 0.5) * 255.0)
			bytes[i + 1] = int((n.y * 0.5 + 0.5) * 255.0)
			bytes[i + 2] = int((n.z * 0.5 + 0.5) * 255.0)
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)


func _save(name: String, size: int, albedo: PackedByteArray, orm: PackedByteArray, height: PackedFloat32Array, normal_strength: float) -> void:
	Image.create_from_data(size, size, false, Image.FORMAT_RGB8, albedo).save_png(OUT + name + "_albedo.png")
	Image.create_from_data(size, size, false, Image.FORMAT_RGB8, orm).save_png(OUT + name + "_orm.png")
	_normal_from_height(height, size, normal_strength).save_png(OUT + name + "_normal.png")


func _put(bytes: PackedByteArray, i: int, c: Color) -> void:
	bytes[i * 3] = clampi(int(c.r * 255.0), 0, 255)
	bytes[i * 3 + 1] = clampi(int(c.g * 255.0), 0, 255)
	bytes[i * 3 + 2] = clampi(int(c.b * 255.0), 0, 255)


func _bytes(size: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size * size * 3)
	return b


# --- floor plate ---------------------------------------------------------------

func _floor_plate(size: int) -> void:
	var plate := size / 2
	var cell := 40.0
	var big := _noise(size, 260.0, 4, 11)
	var fine := _noise(size, 18.0, 3, 12)
	var blot := _noise(size, 90.0, 4, 13)
	var height := PackedFloat32Array()
	height.resize(size * size)
	var albedo := _bytes(size)
	var orm := _bytes(size)
	for y in range(size):
		for x in range(size):
			var i := y * size + x
			var px := x % plate
			var py := y % plate
			var plate_id := (x / plate) + 2 * (y / plate)
			var edge := float(mini(mini(px, plate - 1 - px), mini(py, plate - 1 - py)))
			var seam := 1.0 - _sstep(2.0, 4.0, edge)
			var bevel := _sstep(3.0, 12.0, edge)
			# Diamond tread lozenges, alternating orientation per checker cell.
			var cx := floorf(float(x) / cell)
			var cy := floorf(float(y) / cell)
			var u := float(x) / cell - cx - 0.5
			var v := float(y) / cell - cy - 0.5
			var sgn := 1.0 if int(cx + cy) % 2 == 0 else -1.0
			var ru := (u + sgn * v) * 0.7071
			var rv := (v - sgn * u) * 0.7071
			var d := absf(ru) / 0.36 + absf(rv) / 0.12
			var tread := _sstep(1.0, 0.65, d) * _sstep(14.0, 24.0, edge)
			# Bolts near each plate corner.
			var bolt := 0.0
			for corner in [Vector2(22, 22), Vector2(plate - 23, 22), Vector2(22, plate - 23), Vector2(plate - 23, plate - 23)]:
				var bd := Vector2(px, py).distance_to(corner)
				bolt = maxf(bolt, _sstep(8.0, 4.0, bd))
			var h := bevel * 0.55 + tread * 0.35 + bolt * 0.4 + fine[i] * 0.03
			height[i] = h
			var variation := 0.94 + 0.12 * fmod(float(plate_id) * 0.37 + 0.2, 1.0)
			var grime := clampf(_sstep(0.7, 0.95, blot[i]) * 0.3 + seam * 0.8 + (1.0 - bevel) * 0.35 + (1.0 - tread) * 0.15 * big[i], 0.0, 1.0)
			var steel := Color(0.40, 0.415, 0.43) * variation * (0.86 + 0.28 * big[i])
			var worn := Color(0.66, 0.67, 0.68)
			var dirt := Color(0.12, 0.11, 0.1)
			var c := steel.lerp(worn, tread * 0.7 + bolt * 0.5)
			c = c.lerp(dirt, grime * 0.55)
			_put(albedo, i, c)
			var ao := (0.45 + 0.55 * bevel) * (1.0 - seam * 0.5)
			var rough := clampf(0.48 - tread * 0.18 + grime * 0.35 + fine[i] * 0.1, 0.12, 1.0)
			var metal := clampf(0.85 - grime * 0.6, 0.0, 1.0)
			_put(orm, i, Color(ao, rough, metal))
	_save("floor_plate", size, albedo, orm, height, 6.0)


# --- wall panel ----------------------------------------------------------------

func _wall_panel(size: int) -> void:
	var panel_h := size / 2
	var chips := _noise(size, 40.0, 4, 21)
	var mottle := _noise(size, 140.0, 4, 22)
	var fine := _noise(size, 10.0, 2, 23)
	var streak_src := _noise(size, 30.0, 3, 24)
	var height := PackedFloat32Array()
	height.resize(size * size)
	var albedo := _bytes(size)
	var orm := _bytes(size)
	for y in range(size):
		for x in range(size):
			var i := y * size + x
			var py := y % panel_h
			var edge := float(mini(mini(x, size - 1 - x), mini(py, panel_h - 1 - py)))
			var seam := 1.0 - _sstep(2.0, 4.0, edge)
			var outer := _sstep(3.0, 7.0, edge)
			# Recessed centre with a 45-degree bevel between frame and recess.
			var recess := _sstep(34.0, 42.0, edge)
			var h := outer * 0.8 - recess * 0.35
			# Screws in the frame corners.
			var screw := 0.0
			for corner in [Vector2(18, 18), Vector2(size - 19, 18), Vector2(18, panel_h - 19), Vector2(size - 19, panel_h - 19)]:
				var sd := Vector2(x, py).distance_to(corner)
				screw = maxf(screw, _sstep(7.0, 4.5, sd))
			h += screw * 0.25
			# Vent grille on the lower panel's right side.
			var vent := 0.0
			if y >= panel_h and x > size - 260 and x < size - 80 and py > 300 and py < 440:
				var slot := fmod(float(py), 18.0)
				vent = 1.0 if slot < 9.0 else 0.0
				h -= vent * 0.3
			# Thin pinstripe groove across each panel's recess.
			var stripe := 1.0 - _sstep(0.0, 2.0, absf(float(py) - 120.0))
			h -= stripe * 0.12 * recess
			h += fine[i] * 0.015
			height[i] = h
			# Paint chips concentrate on the raised frame edges.
			var edge_zone := (1.0 - _sstep(6.0, 16.0, edge)) * 0.6 + (1.0 - _sstep(36.0, 46.0, edge)) * _sstep(30.0, 36.0, edge) * 0.5
			var chip := _sstep(0.9, 0.95, chips[i] + edge_zone * 0.4) * (1.0 - seam)
			# Vertical grime streaks running down from the seams.
			var streak := streak_src[x] * 0.7 + streak_src[(y / 4) * size + x] * 0.3
			var drip := _sstep(0.5, 0.8, streak) * pow(float(py) / float(panel_h), 3.0) * 0.18
			var paint := Color(0.88, 0.87, 0.85) * (0.97 + 0.04 * mottle[i])
			var bare := Color(0.62, 0.63, 0.64)
			var dirt := Color(0.25, 0.23, 0.21)
			var c := paint.lerp(bare, chip)
			c = c.lerp(dirt, clampf(drip + seam * 0.85 + vent * 0.7 + (1.0 - recess) * outer * 0.04, 0.0, 1.0))
			c = c.lerp(Color(0.62, 0.62, 0.63), screw * 0.8)
			_put(albedo, i, c)
			var ao := (0.5 + 0.5 * outer) * (1.0 - vent * 0.4) * (1.0 - 0.25 * (1.0 - _sstep(34.0, 52.0, edge)) * recess)
			var rough := clampf(0.48 + mottle[i] * 0.08 - chip * 0.15 + drip * 0.2 + seam * 0.3, 0.15, 1.0)
			var metal := clampf(chip * 0.55 + screw * 0.6, 0.0, 1.0)
			_put(orm, i, Color(ao, rough, metal))
	_save("wall_panel", size, albedo, orm, height, 5.0)


# --- painted metal for props -------------------------------------------------------

func _metal_paint(size: int) -> void:
	var mottle := _noise(size, 80.0, 4, 31)
	var fine := _noise(size, 6.0, 2, 32)
	var chips := _noise(size, 22.0, 4, 33)
	var scratch := PackedFloat32Array()
	scratch.resize(size * size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 34
	for s in range(160):
		var start := Vector2(rng.randf() * size, rng.randf() * size)
		var angle := rng.randf() * TAU
		var length := rng.randf_range(10.0, 70.0)
		var dir := Vector2(cos(angle), sin(angle))
		var steps := int(length)
		for t in range(steps):
			var p := start + dir * float(t) + Vector2(0, sin(float(t) * 0.1) * 2.0)
			var ix := posmod(int(p.x), size)
			var iy := posmod(int(p.y), size)
			scratch[iy * size + ix] = maxf(scratch[iy * size + ix], rng.randf_range(0.5, 1.0))
	var height := PackedFloat32Array()
	height.resize(size * size)
	var albedo := _bytes(size)
	var orm := _bytes(size)
	for i in range(size * size):
		var chip := _sstep(0.8, 0.85, chips[i])
		var sc := scratch[i]
		height[i] = fine[i] * 0.04 - sc * 0.05 - chip * 0.12
		var paint := Color(0.84, 0.84, 0.84) * (0.9 + 0.14 * mottle[i])
		var c := paint.lerp(Color(0.62, 0.63, 0.64), maxf(chip, sc * 0.35))
		_put(albedo, i, c)
		_put(orm, i, Color(1.0 - chip * 0.3, clampf(0.55 + mottle[i] * 0.2 - sc * 0.25 - chip * 0.15, 0.15, 1.0), clampf(maxf(chip, sc), 0.0, 1.0)))
	_save("metal_paint", size, albedo, orm, height, 3.0)


# --- grime decal ---------------------------------------------------------------

func _grime_decal(size: int) -> void:
	var blot := _noise(size, 60.0, 5, 41)
	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var i := y * size + x
			var r := Vector2(x - half, y - half).length() / half
			var a := _sstep(0.42, 0.75, blot[i]) * _sstep(1.0, 0.45, r)
			bytes[i * 4] = 38
			bytes[i * 4 + 1] = 33
			bytes[i * 4 + 2] = 28
			bytes[i * 4 + 3] = clampi(int(a * 220.0), 0, 255)
	Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes).save_png(OUT + "grime_decal.png")
