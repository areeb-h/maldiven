class_name ArtStationFX
extends Node3D
## Runtime half of the station art: owns the power-state look (lights, emissive
## materials, signage, environment) and animates alarm pulses. Created and wired
## by StationBuilder; StationBuilder.set_power_state() forwards here.

## Emissive energies stay <= 2.0: the Mobile renderer's RGB10A2 buffer clips
## there, so states differ by colour, area, pulse and on/off instead.
const STATES := {
	"emergency": {
		"ambient": 0.5, "ambient_color": Color(0.42, 0.42, 0.55), "sun": 0.45, "fill": 0.35,
		"light": 1.6, "light_mix": 0.0, "pulse": 1.0,
		"trim": 0.25, "door": 1.2, "emergency": 1.9, "ceiling": 0.0, "guide": 1.2, "screen": 0.5,
		"beacon": 2.0, "reactor": 0.35, "label": 0.9, "nav": 1.5,
		"sign": 0.75, "blink": 1.4, "breathe": 0.6, "flicker": 1.1, "glow": 1.3, "exposure": 1.05,
		"fog_color": Color(0.25, 0.07, 0.05), "fog_density": 0.01,
	},
	"restored": {
		"ambient": 0.7, "ambient_color": Color(0.62, 0.66, 0.76), "sun": 1.3, "fill": 0.25,
		"light": 1.4, "light_mix": 1.0, "pulse": 0.0,
		"trim": 1.6, "door": 1.9, "emergency": 0.0, "ceiling": 1.4, "guide": 0.8, "screen": 1.4,
		"beacon": 0.0, "reactor": 1.35, "label": 1.3, "nav": 1.5,
		"sign": 1.25, "blink": 1.8, "breathe": 1.5, "flicker": 1.6, "glow": 1.2, "exposure": 1.0,
		"fog_color": Color(0.08, 0.1, 0.14), "fog_density": 0.005,
	},
	"blackout": {
		"ambient": 0.05, "ambient_color": Color(0.25, 0.3, 0.45), "sun": 0.02, "fill": 0.0,
		"light": 0.0, "light_mix": 0.0, "pulse": 0.0,
		"trim": 0.0, "door": 0.25, "emergency": 0.0, "ceiling": 0.0, "guide": 1.6, "screen": 0.04,
		"beacon": 0.0, "reactor": 0.12, "label": 0.1, "nav": 0.4,
		"sign": 0.06, "blink": 0.5, "breathe": 0.0, "flicker": 0.0, "glow": 1.4, "exposure": 1.1,
		"fog_color": Color(0.01, 0.015, 0.03), "fog_density": 0.02,
	},
}
const EMERGENCY_LIGHT := Color(1.0, 0.3, 0.16)
const MATERIAL_PARAMS := ["lights", "screen", "reactor"]
## Light-strip groups (vertex alpha = index / 11) sharing the "lights" material.
## sign: painted-in glowing stencils and floor names; blink/breathe/flicker are
## animated per fixture in the shader (status LEDs, standby glow, dying panel).
const LIGHT_GROUPS := ["trim", "door", "emergency", "ceiling", "guide", "beacon", "nav", "alarm", "sign", "blink", "breathe", "flicker"]

var state := ""
var mats: Dictionary = {}  # param name -> ShaderMaterial (glow shader)
var room_lights: Array[OmniLight3D] = []
var room_light_colors: Array[Color] = []
var labels: Array[Label3D] = []
var label_colors: Array[Color] = []
var probes: Array[ReflectionProbe] = []
## Every free-standing prop the builder placed: {"name", "center", "size", "yaw"}
## (visual bounds). tests/art_smoke.gd checks each has a matching collider.
var props: Array[Dictionary] = []
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment
var current: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _blend := 1.0
var _tween: Tween
var _time := 0.0
var _probe_timer := -1.0
var _probe_frames := 0
var airlock_doors: Array[Node3D] = []
var airlock_door_closed: Array[Vector3] = []
var airlock_door_open_dir: Array[Vector3] = []
var airlock_light: OmniLight3D
var airlock_state := "idle"
var _airlock_t := 0.0
var _airlock_open := 0.0
var _alarm_energy := 0.35
var _energies := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])


func set_state(new_state: String, duration := 1.0) -> void:
	if not STATES.has(new_state):
		push_warning("Station power state unknown: " + new_state)
		return
	state = new_state
	_to = STATES[new_state]
	# Sky reflections (sun glare, planet) would keep glossy trims lit in a
	# blackout, so reflections fall back to probes/none while dark.
	if env != null:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if new_state == "blackout" else Environment.REFLECTION_SOURCE_SKY
	if current.is_empty():
		current = _to.duplicate()
	_from = current.duplicate()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duration <= 0.0 or not is_inside_tree():
		_blend = 1.0
		_update(true)
		_refresh_probes()
		return
	_blend = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "_blend", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_refresh_probes)


func set_airlock_state(new_state: String) -> void:
	if not new_state in ["idle", "warning", "venting"]:
		push_warning("Airlock state unknown: " + new_state)
		return
	airlock_state = new_state
	_airlock_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	_update_airlock(delta)
	_update(_blend < 1.0 or (_tween != null and _tween.is_running()))
	if _probe_timer >= 0.0:
		_probe_timer -= delta
		_probe_frames -= 1
		if _probe_timer < 0.0 and _probe_frames <= 0:
			for probe in probes:
				if is_instance_valid(probe):
					probe.update_mode = ReflectionProbe.UPDATE_ONCE


func _refresh_probes() -> void:
	if probes.is_empty():
		return
	for probe in probes:
		if is_instance_valid(probe):
			probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	# Re-render for at least 0.35 s and 12 frames (all six faces on slow devices).
	_probe_timer = 0.35
	_probe_frames = 12


func _update(full: bool) -> void:
	if _to.is_empty():
		return
	if full:
		for key in _to:
			if _from.has(key):
				current[key] = lerp(_from[key], _to[key], _blend)
			else:
				current[key] = _to[key]
		_apply_static()
	_apply_animated()


func _apply_static() -> void:
	if env != null:
		env.ambient_light_energy = current.ambient
		env.ambient_light_color = current.ambient_color
		env.glow_intensity = current.glow
		env.tonemap_exposure = current.exposure
	# Probe ambient/reflections follow the power state directly, so a probe
	# still holding an older capture can never light a blacked-out room.
	for probe in probes:
		if is_instance_valid(probe):
			probe.ambient_color = current.ambient_color
			probe.ambient_color_energy = current.ambient
			probe.intensity = clampf(float(current.ambient) * 0.9, 0.03, 0.7)
	if sun != null:
		sun.light_energy = current.sun
		sun.visible = current.sun > 0.01
	if fill != null:
		fill.light_energy = current.fill
		fill.visible = current.fill > 0.01
	if env != null:
		env.fog_light_color = current.fog_color
		env.fog_density = current.fog_density
	for i in range(labels.size()):
		if is_instance_valid(labels[i]):
			var c := label_colors[i] * minf(float(current.label), 1.0) + label_colors[i] * maxf(float(current.label) - 1.0, 0.0) * 0.5
			c.a = clampf(float(current.label) * 1.2, 0.15, 1.0)
			labels[i].modulate = c
			labels[i].outline_modulate = Color(0, 0, 0, clampf(float(current.label), 0.0, 0.8))
	if mats.has("screen"):
		(mats["screen"] as ShaderMaterial).set_shader_parameter("energy", float(current.screen))


func _apply_animated() -> void:
	var pulse_amount: float = current.get("pulse", 0.0)
	# Slow alarm swell (period ~2.4 s) and a faster beacon flash.
	var swell := 0.5 + 0.5 * sin(_time * TAU / 2.4)
	var flash := pow(maxf(0.0, sin(_time * TAU / 1.2)), 6.0)
	if mats.has("lights"):
		_energies[0] = current.trim
		_energies[1] = current.door
		_energies[2] = float(current.emergency) * (1.0 - pulse_amount * 0.55 * (1.0 - swell))
		_energies[3] = current.ceiling
		_energies[4] = current.guide
		_energies[5] = float(current.beacon) * (0.08 + 0.92 * flash)
		_energies[6] = float(current.nav) * (1.0 if fmod(_time * 0.7, 1.0) > 0.82 else 0.15)
		_energies[7] = _alarm_energy
		_energies[8] = current.sign
		_energies[9] = current.blink
		_energies[10] = current.breathe
		_energies[11] = current.flicker
		(mats["lights"] as ShaderMaterial).set_shader_parameter("energies", _energies)
	if mats.has("reactor"):
		(mats["reactor"] as ShaderMaterial).set_shader_parameter("energy", float(current.reactor))
	var light_energy: float = current.light
	var mix_t: float = current.light_mix
	for i in range(room_lights.size()):
		var light := room_lights[i]
		if not is_instance_valid(light):
			continue
		var e := light_energy * (1.0 - pulse_amount * 0.3 * (1.0 - swell))
		light.light_energy = e
		light.light_color = EMERGENCY_LIGHT.lerp(room_light_colors[i], mix_t)
		light.visible = e > 0.01



func _update_airlock(delta: float) -> void:
	_airlock_t += delta
	var target_open := 0.0
	var light_e := 0.0
	var light_c := Color(1.0, 0.1, 0.05)
	var lamp := 0.35
	match airlock_state:
		"warning":
			var strobe := 1.0 if fmod(_airlock_t * 2.6, 1.0) < 0.5 else 0.0
			light_e = 0.6 + 6.0 * strobe
			lamp = 0.6 + 10.0 * strobe
		"venting":
			target_open = 1.0
			var decay := exp(-_airlock_t * 1.4)
			var flicker := 0.6 + 0.4 * sin(_airlock_t * 40.0)
			light_e = 2.0 + 6.0 * decay * flicker
			light_c = Color(1.0, 0.1, 0.05).lerp(Color(0.75, 0.9, 1.0), decay)
			lamp = 3.0 + 5.0 * flicker
			if _airlock_t >= 2.0:
				set_airlock_state("idle")
	var speed := 3.2 if target_open > _airlock_open else 1.6
	_airlock_open = move_toward(_airlock_open, target_open, delta * speed)
	var eased := _airlock_open * _airlock_open * (3.0 - 2.0 * _airlock_open)
	for i in range(airlock_doors.size()):
		if is_instance_valid(airlock_doors[i]):
			airlock_doors[i].position = airlock_door_closed[i] + airlock_door_open_dir[i] * eased
	if airlock_light != null and is_instance_valid(airlock_light):
		airlock_light.visible = light_e > 0.01
		airlock_light.light_energy = light_e
		airlock_light.light_color = light_c
	_alarm_energy = lamp

