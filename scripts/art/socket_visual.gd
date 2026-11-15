class_name SocketVisual
extends Node3D
## Runtime half of an interaction socket built by Props.make_socket() (geometry in
## scripts/art/items/sockets/). Front faces local +Z; origin on the floor.
##   filled: item seated   locked: unusable (forcefield, cage or closed door)
##   active: countdown / warning running (strobing lamps, rotating beacon, alarm light)
## Every socket shows the same language: an amber seat ring with chevrons flowing
## into the seat while it waits, steady green once filled, a red forcefield while
## locked and an orange strobe with a sweeping beacon while active, plus a
## holographic name / status label. set_state() only sets targets; transitions
## (cage lifting, doors sliding, glow ramps) ease in over ~0.3-0.9 s.

const LOCKED := Color(1.0, 0.16, 0.1)
const WAITING := Color(1.0, 0.68, 0.2)
const FILLED := Color(0.25, 1.0, 0.55)
const ACTIVE := Color(1.0, 0.36, 0.05)
const FIELD := Color(1.0, 0.22, 0.14)

## Per kind: title and status lines (waiting, filled, locked, active).
const TEXT := {
	"vault": ["CORE VAULT", "VAULT EMPTY", "CORE SECURED", "LOCKED - NO POWER", "ALERT"],
	"reactor": ["REACTOR", "INSERT CELL", "ONLINE", "OFFLINE", "OVERLOAD"],
	"shuttle": ["SHUTTLE", "LOAD CORE", "CORE LOADED", "LOCKED", "LAUNCHING"],
	"pod": ["CARGO POD", "LOAD CORE", "CORE LOADED", "LOCKED", "POD ARMED"],
	"armory": ["ARMORY", "RACK EMPTY", "WEAPON STORED", "LOCKED - NO POWER", "ALERT"],
	"medbay": ["MEDBAY", "REVIVE STATION", "REVIVING", "OFFLINE", "REVIVING"],
	"airlock_console": ["AIRLOCK", "CYCLE READY", "CYCLE READY", "LOCKED", "WARNING - VENTING"],
}

var kind := ""
var seat: Marker3D
var body_mat: ShaderMaterial
var fx_mat: ShaderMaterial
var title_label: Label3D
var status_label: Label3D
var alarm: OmniLight3D
## Moving parts: {node, a: Transform3D (rest), b: Transform3D (moved), driver: "unlock" | "fill" | "active", sweep: Vector3}
var parts: Array[Dictionary] = []
var number := 0
var filled := false
var locked := false
var active := false

var _lock_w := 0.0
var _fill_w := 0.0
var _act_w := 0.0
var _snap := true
var _t := 0.0
var _status := ""


func set_state(p_filled: bool, p_locked: bool, p_active: bool) -> void:
	filled = p_filled
	locked = p_locked
	active = p_active
	if _snap or not is_inside_tree():
		_lock_w = 1.0 if locked else 0.0
		_fill_w = 1.0 if filled else 0.0
		_act_w = 1.0 if active else 0.0
		_snap = false
	_apply(0.0)


func get_seat_transform() -> Transform3D:
	if seat != null:
		return seat.transform
	return Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0))


func _enter_tree() -> void:
	# World names sockets "Socket_<id>" (e.g. Socket_reactor_2): number the title.
	var parts_of_name := String(name).split("_")
	var last := parts_of_name[parts_of_name.size() - 1] if parts_of_name.size() > 0 else ""
	number = int(last) if last.is_valid_int() else 0
	if body_mat != null:
		body_mat.set_shader_parameter("decal_number", maxi(number, 1))
	_apply(0.0)


func _process(delta: float) -> void:
	_t += delta
	_lock_w = move_toward(_lock_w, 1.0 if locked else 0.0, delta / 0.9)
	_fill_w = move_toward(_fill_w, 1.0 if filled else 0.0, delta / 0.35)
	_act_w = move_toward(_act_w, 1.0 if active else 0.0, delta / 0.3)
	_apply(delta)


func _status_color() -> Color:
	if active:
		return ACTIVE
	if locked:
		return LOCKED
	if filled:
		return FILLED
	return WAITING


func _apply(_delta: float) -> void:
	var c := _status_color()
	var energy := 1.5
	var chase := 0.0
	if active:
		energy = 0.5 + 1.3 * pow(maxf(0.0, sin(_t * TAU * 2.0)), 2.0)
	elif locked:
		energy = 0.9 + 0.25 * sin(_t * 2.2)
	elif filled:
		energy = 1.35 + 0.15 * sin(_t * 1.6)
	else:
		energy = 1.3
		chase = 1.0
	var lock := _ease(_lock_w)
	var fill := _ease(_fill_w)
	var act := _ease(_act_w)
	if body_mat != null:
		body_mat.set_shader_parameter("status_color", ItemMaterials.vec(c))
		body_mat.set_shader_parameter("status_energy", energy)
		body_mat.set_shader_parameter("status_chase", chase)
		body_mat.set_shader_parameter("warn", act)
		body_mat.set_shader_parameter("led_color", ItemMaterials.vec(c))
	if fx_mat != null:
		fx_mat.set_shader_parameter("status_color", ItemMaterials.vec(c))
		fx_mat.set_shader_parameter("status_energy", clampf(energy, 0.6, 1.5))
		fx_mat.set_shader_parameter("field", lock * (0.85 + 0.15 * sin(_t * 5.0)))
		fx_mat.set_shader_parameter("warn", act)
		fx_mat.set_shader_parameter("seat", (1.0 - fill) * (1.0 - lock) * (1.0 - act) * 0.9 + fill * 0.35)
		fx_mat.set_shader_parameter("scan", maxf(fill, act) * 0.9 + 0.25)
	for p in parts:
		var node: Node3D = p.node
		var w := 0.0
		match String(p.driver):
			"unlock":
				w = 1.0 - lock
			"fill":
				w = fill
			"active":
				w = act
		var xf: Transform3D = (p.a as Transform3D).interpolate_with(p.b, w)
		if p.has("sweep"):
			# Sweeping part (medbay scanner): oscillates along `sweep` while engaged.
			xf.origin += (p.sweep as Vector3) * sin(_t * 1.15) * w
		node.transform = xf
	if alarm != null:
		alarm.visible = act > 0.01
		alarm.light_energy = act * (0.35 + 1.1 * pow(maxf(0.0, sin(_t * TAU * 2.0)), 2.0))
	_update_labels(c)


func _update_labels(c: Color) -> void:
	if title_label == null:
		return
	var lines: Array = TEXT.get(kind, ["SOCKET", "", "", "LOCKED", "ACTIVE"])
	var title: String = lines[0]
	if kind == "reactor" and number > 0:
		title = "%s %d" % [title, number]
	var s: String = lines[1]
	if active:
		s = lines[4]
	elif locked:
		s = lines[3]
	elif filled:
		s = lines[2]
	if title_label.text != title:
		title_label.text = title
	if s != _status:
		_status = s
		status_label.text = s
	# Holographic flicker: brief dips, never hiding the text.
	var flick := 0.92 + 0.08 * sin(_t * 23.0) * sin(_t * 3.1)
	title_label.modulate = Color(0.82, 0.95, 1.0, 0.95 * flick)
	var sc := c.lerp(Color.WHITE, 0.2)
	if active:
		sc.a = 0.6 + 0.4 * pow(maxf(0.0, sin(_t * TAU * 2.0)), 0.5)
	else:
		sc.a = 0.95 * flick
	status_label.modulate = sc


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
