class_name ArtStationFX
extends Node3D
## Runtime half of the station art: owns the power-state look (lights, emissive
## materials, signage, environment) and animates alarm pulses. Created and wired
## by StationBuilder; StationBuilder.set_power_state() forwards here.

const STATES := {
	"emergency": {
		"ambient": 0.5, "ambient_color": Color(0.62, 0.36, 0.34), "sun": 0.3,
		"light": 1.7, "light_mix": 0.0, "pulse": 1.0,
		"trim": 0.18, "door": 1.6, "emergency": 3.2, "ceiling": 0.0, "guide": 1.3, "screen": 0.35,
		"beacon": 6.0, "reactor": 0.55, "label": 0.9, "nav": 2.0, "glow": 0.85, "exposure": 1.05,
	},
	"restored": {
		"ambient": 0.75, "ambient_color": Color(0.6, 0.65, 0.74), "sun": 1.25,
		"light": 1.5, "light_mix": 1.0, "pulse": 0.0,
		"trim": 2.6, "door": 3.2, "emergency": 0.0, "ceiling": 3.2, "guide": 0.9, "screen": 2.0,
		"beacon": 0.0, "reactor": 5.0, "label": 1.5, "nav": 2.0, "glow": 0.75, "exposure": 1.0,
	},
	"blackout": {
		"ambient": 0.05, "ambient_color": Color(0.25, 0.3, 0.45), "sun": 0.02,
		"light": 0.0, "light_mix": 0.0, "pulse": 0.0,
		"trim": 0.0, "door": 0.25, "emergency": 0.0, "ceiling": 0.0, "guide": 1.8, "screen": 0.04,
		"beacon": 0.0, "reactor": 0.12, "label": 0.1, "nav": 0.4, "glow": 0.9, "exposure": 1.0,
	},
}
const EMERGENCY_LIGHT := Color(1.0, 0.3, 0.16)
const MATERIAL_PARAMS := ["trim", "door", "emergency", "ceiling", "guide", "screen", "beacon", "reactor", "nav"]

var state := ""
var mats: Dictionary = {}  # param name -> ShaderMaterial (glow shader)
var room_lights: Array[OmniLight3D] = []
var room_light_colors: Array[Color] = []
var labels: Array[Label3D] = []
var label_colors: Array[Color] = []
var probes: Array[ReflectionProbe] = []
var sun: DirectionalLight3D
var env: Environment
var current: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _blend := 1.0
var _tween: Tween
var _time := 0.0
var _probe_timer := -1.0


func set_state(new_state: String, duration := 1.0) -> void:
	if not STATES.has(new_state):
		push_warning("Station power state unknown: " + new_state)
		return
	state = new_state
	_to = STATES[new_state]
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


func _process(delta: float) -> void:
	_time += delta
	_update(_blend < 1.0 or (_tween != null and _tween.is_running()))
	if _probe_timer >= 0.0:
		_probe_timer -= delta
		if _probe_timer < 0.0:
			for probe in probes:
				if is_instance_valid(probe):
					probe.update_mode = ReflectionProbe.UPDATE_ONCE


func _refresh_probes() -> void:
	if probes.is_empty():
		return
	for probe in probes:
		if is_instance_valid(probe):
			probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	_probe_timer = 0.35


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
	if sun != null:
		sun.light_energy = current.sun
		sun.visible = current.sun > 0.01
	for i in range(labels.size()):
		if is_instance_valid(labels[i]):
			var c := label_colors[i] * float(current.label)
			c.a = clampf(float(current.label) * 1.2, 0.15, 1.0)
			labels[i].modulate = c
			labels[i].outline_modulate = Color(0, 0, 0, clampf(float(current.label), 0.0, 0.8))
	for key in ["trim", "door", "ceiling", "guide", "screen", "nav"]:
		if mats.has(key):
			(mats[key] as ShaderMaterial).set_shader_parameter("energy", float(current[key]))


func _apply_animated() -> void:
	var pulse_amount: float = current.get("pulse", 0.0)
	# Slow alarm swell (period ~2.4 s) and a faster beacon flash.
	var swell := 0.5 + 0.5 * sin(_time * TAU / 2.4)
	var flash := pow(maxf(0.0, sin(_time * TAU / 1.2)), 6.0)
	if mats.has("emergency"):
		(mats["emergency"] as ShaderMaterial).set_shader_parameter("energy", float(current.emergency) * (1.0 - pulse_amount * 0.55 * (1.0 - swell)))
	if mats.has("beacon"):
		(mats["beacon"] as ShaderMaterial).set_shader_parameter("energy", float(current.beacon) * (0.08 + 0.92 * flash))
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
