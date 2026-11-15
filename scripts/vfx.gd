class_name Vfx
extends Node3D
## Pooled, mobile-friendly visual effects for Drift Station. Add one as a child
## of the World. Everything is additive/soft emissive so it feeds the glow pass;
## no per-particle lights, a tiny shared light pool for flashes only.
##
## Pools are fixed-size: a burst that finds no free emitter steals the oldest one,
## so the node count never grows past pool_capacity().
##
## Conventions for burst(at, direction):
##   pickup / drop / footstep_dust: at = floor point under the item / foot.
##   insert_cell / countdown_pulse: at = socket origin (floor); effects climb it.
##   shove_impact: at = target position (floor), direction = shove direction.
##   power_wave: at = reactor floor centre.   blackout_flicker: at = room centre.
##   launch: at = engine nozzle, direction = where the craft goes (exhaust opposite).
##   alarm_strobe: at = beacon position (a floor point is lifted to 2.5 m).
##   muzzle_flash: at = muzzle, direction = aim.   impact: direction = surface normal
##     (or back towards the shooter).   downed / revive: at = player floor position.
##   airlock_vent: at = inner door, direction = towards the outer door.
##   spaced: at = body position, direction = drift direction (ice trail streams back).
## color == Color.WHITE means "use the kind's own palette".

const KINDS: Array[String] = ["pickup", "drop", "insert_cell", "shove_impact", "footstep_dust",
	"power_wave", "blackout_flicker", "launch", "alarm_strobe", "muzzle_flash", "impact", "downed",
	"revive", "airlock_vent", "spaced"]
const CELL_COLOR := Color(1.0, 0.6, 0.14)
const CORE_COLOR := Color(0.28, 0.92, 1.0)
const HIGHLIGHT_COLOR := Color(0.37, 0.83, 1.0)
const POWER_COLOR := Color(0.5, 0.85, 1.0)
const ALARM_COLOR := Color(1.0, 0.08, 0.04)
const SPARK_COLOR := Color(1.0, 0.48, 0.14)
const BOLT_COLOR := Color(1.0, 0.45, 0.3)
const REVIVE_COLOR := Color(0.35, 1.0, 0.55)
const FROST_COLOR := Color(0.72, 0.9, 1.0)
const GHOST_COLOR := Color(0.62, 0.8, 1.0)
const MAX_TRAILS := 4
const TRAIL_POINTS := 14
const CEILING_Y := StationLayout.WALL_HEIGHT - 0.12
## Reactor column centre (matches StationBuilder's reactor dressing).
const REACTOR_CORE := Vector3(62.0, 0.0, 19.3)
const POWER_WAVE_RADIUS := 90.0
const POWER_WAVE_TIME := 1.6

## Particle emitter pools: preset -> how many emitters may exist.
const EMITTER_POOLS := {
	"sparkle": 3, "spark": 4, "skitter": 3, "puff": 3, "step": 6,
	"shower": 4, "rise": 2, "exhaust": 2, "smoke": 2, "frost": 3, "debris": 2, "fog": 2,
}
## Mesh / light effect pools: kind -> slot count.
const SLOT_POOLS := {"ring": 10, "tube": 4, "flare": 6, "dash": 6, "arc": 2, "beacon": 2, "light": 3}


class FxSlot:
	extends RefCounted
	var kind := ""
	var node: Node3D
	var mat: ShaderMaterial
	var parts: Array = []
	var active := false
	var t := 0.0
	var dur := 1.0
	var started := 0.0
	var update := Callable()
	var data := {}


# --- shaders -------------------------------------------------------------------------------

const _BILLBOARD_VERTEX := """
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float ra = INSTANCE_CUSTOM.x;
	mw = mw * mat4(vec4(cos(ra), -sin(ra), 0.0, 0.0), vec4(sin(ra), cos(ra), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
"""

const _NOISE := """
float vfx_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vfx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(vfx_hash(i), vfx_hash(i + vec2(1.0, 0.0)), u.x), mix(vfx_hash(i + vec2(0.0, 1.0)), vfx_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
"""

const SHADERS := {
	# Camera-facing additive glow dot / four-point glint. Particle colour * energy,
	# with a white-hot centre.
	"glow_particle": """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float energy = 3.0;
uniform float hot = 0.7;
uniform float falloff = 2.2;
uniform float star = 0.0;
void vertex() {
%BILLBOARD%
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float dot_a = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	float glint = max(exp(-abs(p.y) * 14.0) * (1.0 - abs(p.x)), exp(-abs(p.x) * 14.0) * (1.0 - abs(p.y)));
	float shape = mix(dot_a, max(dot_a * 0.55, glint * 1.2), star);
	float core = clamp(pow(clamp(1.0 - r * 1.7, 0.0, 1.0), 2.0) * hot, 0.0, 1.0);
	ALBEDO = mix(COLOR.rgb, vec3(1.0), core) * energy;
	ALPHA = clamp(shape * COLOR.a, 0.0, 1.0);
}
""",
	# Velocity-aligned spark streak: the quad's Y axis follows MODEL_MATRIX Y (set by
	# particle_flag_align_y or by a node's basis), the X axis turns to face the camera.
	"streak": """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float energy = 4.0;
uniform float alpha = 1.0;
uniform vec3 tint = vec3(1.0);
void vertex() {
	vec3 pos = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - pos);
	vec3 side = cross(normalize(ax + vec3(0.0, 1e-5, 0.0)), to_cam);
	side = normalize(side + vec3(1e-5, 0.0, 0.0)) * sx;
	vec3 nrm = normalize(cross(side, ax) + vec3(0.0, 0.0, 1e-5));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(ax, 0.0), vec4(nrm, 0.0), vec4(pos, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	float across = clamp(1.0 - abs(UV.x * 2.0 - 1.0), 0.0, 1.0);
	float along = pow(1.0 - UV.y, 1.3) * smoothstep(0.0, 0.12, UV.y);
	float core = pow(across, 5.0) * smoothstep(0.7, 0.05, UV.y);
	ALBEDO = mix(COLOR.rgb * tint, vec3(1.0), core * 0.85) * energy;
	ALPHA = clamp(pow(across, 2.6) * along * COLOR.a * alpha, 0.0, 1.0);
}
""",
	# Soft noisy smoke / dust / steam puff, alpha blended and lightly lit.
	"smoke": """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;
uniform float opacity = 1.0;
uniform float self_glow = 0.0;
uniform vec3 glow_color = vec3(1.0, 0.5, 0.2);
uniform float ambient_emit = 0.0;
varying float v_seed;
varying float v_life;
%NOISE%
void vertex() {
	v_seed = float(INSTANCE_ID) * 1.618;
	v_life = INSTANCE_CUSTOM.y;
%BILLBOARD%
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = vfx_noise(p * 2.2 + vec2(v_seed, v_seed * 0.7) + v_life * 0.8) * 0.65 + vfx_noise(p * 5.0 - v_seed) * 0.35;
	float mask = smoothstep(1.0, 0.15, r + (n - 0.5) * 0.55);
	ALBEDO = COLOR.rgb;
	EMISSION = glow_color * self_glow * (1.0 - v_life) * (1.0 - v_life) + COLOR.rgb * ambient_emit;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.5);
	ALPHA = clamp(mask * mask * COLOR.a * opacity, 0.0, 1.0);
}
""",
	# Ambient floating dust: additive but LIT, so motes only show where room light is.
	"mote": """
shader_type spatial;
render_mode blend_add, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;
uniform float energy = 2.0;
void vertex() {
%BILLBOARD%
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = pow(clamp(1.0 - length(p), 0.0, 1.0), 2.0);
	ALBEDO = COLOR.rgb * energy;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(1.0);
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
""",
	# Flat ring on a 2x2 plane (normal +Y): gaussian front, optional fill, trail and dashes.
	"ring": """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color = vec3(1.0);
uniform float energy = 3.0;
uniform float radius = 0.5;
uniform float width = 0.05;
uniform float alpha = 1.0;
uniform float fill = 0.0;
uniform float trail = 0.0;
uniform float dashes = 0.0;
uniform float spin = 0.0;
uniform float hot = 0.6;
uniform sampler2D floor_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(0.0);
varying vec3 v_wp;
float vfx_mask(vec3 wp) {
	if (mask_rect.z <= 0.0) {
		return 1.0;
	}
	vec2 muv = (wp.xz - mask_rect.xy) / mask_rect.zw;
	if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) {
		return 0.0;
	}
	return texture(floor_mask, muv).r;
}
void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float d = (r - radius) / max(width, 1e-4);
	float ring = exp(-d * d * 2.0);
	float inside = step(r, radius);
	float tail = trail > 0.0 ? exp((r - radius) / trail) * inside : 0.0;
	float body = fill * inside * smoothstep(0.0, radius, r);
	float a = ring + tail * 0.45 + body;
	if (dashes > 0.0) {
		float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
		float seg = smoothstep(0.42, 0.5, abs(fract(ang * dashes + TIME * spin) - 0.5) * 2.0 * 0.5 + 0.25);
		a *= mix(1.0, 0.25 + seg, 0.75);
	}
	a *= smoothstep(1.0, 0.97, r) * vfx_mask(v_wp);
	ALBEDO = mix(color, vec3(1.0), pow(ring, 6.0) * hot) * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
""",
	# Open cylinder of height 1 centred at the origin (scaled per use): light walls,
	# climbing rings, loot pillar and reactor haze.
	"tube": """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color = vec3(1.0);
uniform float energy = 3.0;
uniform float alpha = 1.0;
uniform float fade_pow = 1.5;
uniform float bottom_soft = 0.05;
uniform float top_soft = 0.0;
uniform float rim = 0.0;
uniform float band_count = 0.0;
uniform float band_speed = 0.0;
uniform float band_amt = 0.0;
uniform float wobble = 0.0;
uniform float hot = 0.3;
uniform float near_fade = 0.0;
uniform sampler2D floor_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(0.0);
varying float h;
varying vec3 v_wn;
varying vec3 v_wp;
%NOISE%
float vfx_mask(vec3 wp) {
	if (mask_rect.z <= 0.0) {
		return 1.0;
	}
	vec2 muv = (wp.xz - mask_rect.xy) / mask_rect.zw;
	if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) {
		return 0.0;
	}
	return texture(floor_mask, muv).r;
}

void vertex() {
	h = VERTEX.y + 0.5;
	v_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float vert = pow(clamp(1.0 - h, 0.0, 1.0), fade_pow) * smoothstep(0.0, max(bottom_soft, 1e-4), h);
	if (top_soft > 0.0) {
		vert = smoothstep(0.0, max(bottom_soft, 1e-4), h) * smoothstep(1.0, 1.0 - top_soft, h) * pow(clamp(1.0 - h, 0.0, 1.0), fade_pow);
	}
	float bands = 1.0;
	if (band_count > 0.0) {
		bands = 1.0 - band_amt + band_amt * (0.5 + 0.5 * sin((h * band_count - TIME * band_speed) * 6.2831853));
	}
	float shimmer = 1.0;
	if (wobble > 0.0) {
		shimmer = mix(1.0, vfx_noise(vec2(UV.x * 24.0, h * 6.0 - TIME * 1.5)) * 1.6, wobble);
	}
	float facing = abs(dot(normalize(v_wn), normalize(INV_VIEW_MATRIX[3].xyz - v_wp)));
	float edge = mix(1.0, pow(1.0 - facing, 1.6) * 1.6, rim);
	float a = vert * bands * shimmer * edge * vfx_mask(v_wp);
	if (near_fade > 0.0) {
		a *= 0.3 + 0.7 * smoothstep(1.5, near_fade, distance(INV_VIEW_MATRIX[3].xyz, v_wp));
	}
	ALBEDO = mix(color, vec3(1.0), clamp(pow(vert, 4.0) * hot, 0.0, 1.0)) * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
""",
	# Camera-facing flare: soft glow, anamorphic streak, hot core and an optional
	# wobbling ring (heat-shimmer halo). Pulled towards the camera so it is not
	# swallowed by the geometry it sits in.
	"flare": """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color = vec3(1.0);
uniform float energy = 3.0;
uniform float alpha = 1.0;
uniform float falloff = 5.0;
uniform float streak = 0.0;
uniform float core = 1.0;
uniform float ring = 0.0;
uniform float ring_radius = 0.65;
uniform float ring_width = 0.06;
uniform float wobble = 0.0;
uniform float pull = 0.0;
%NOISE%
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz += normalize(-vp.xyz) * pull;
	POSITION = PROJECTION_MATRIX * vp;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float glow = max(exp(-r * r * falloff) - exp(-falloff), 0.0);
	float st = exp(-abs(p.y) * 38.0) * pow(clamp(1.0 - abs(p.x), 0.0, 1.0), 2.5) * streak;
	float c = exp(-r * r * 60.0) * core;
	float rg = 0.0;
	if (ring > 0.0) {
		float ang = atan(p.y, p.x);
		float rr = ring_radius + wobble * (vfx_noise(vec2(ang * 2.0 + 10.0, TIME * 2.3)) - 0.5) + wobble * 0.5 * (vfx_noise(vec2(ang * 5.0, -TIME * 3.1)) - 0.5);
		float d = (r - rr) / ring_width;
		rg = exp(-d * d) * ring * (0.75 + 0.25 * sin(ang * 3.0 + TIME * 4.0));
	}
	float a = glow + st + c + rg;
	a *= smoothstep(1.0, 0.92, max(abs(p.x), abs(p.y)));
	ALBEDO = mix(color, vec3(1.0), clamp(c + st * 0.4, 0.0, 1.0)) * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
""",
	# Ribbon (electric arc): UV.y runs across the ribbon.
	"beam": """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color = vec3(0.6, 0.8, 1.0);
uniform float energy = 4.0;
uniform float alpha = 1.0;
void fragment() {
	float across = clamp(1.0 - abs(UV.y * 2.0 - 1.0), 0.0, 1.0);
	ALBEDO = mix(color, vec3(1.0), pow(across, 3.0)) * energy;
	ALPHA = clamp(pow(across, 1.3) * alpha * COLOR.a, 0.0, 1.0);
}
""",
	# Fake volumetric cone (alarm beacon beam). Apex at local +Y of a CylinderMesh.
	"cone": """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color = vec3(1.0, 0.1, 0.05);
uniform float energy = 1.0;
uniform float alpha = 1.0;
varying float h;
varying vec3 v_wn;
varying vec3 v_wp;
void vertex() {
	h = VERTEX.y + 0.5;
	v_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float face = pow(abs(dot(normalize(v_wn), normalize(INV_VIEW_MATRIX[3].xyz - v_wp))), 2.0);
	float a = pow(h, 1.8) * face * smoothstep(1.0, 0.93, h);
	ALBEDO = mix(color, vec3(1.0), pow(h, 12.0) * 0.6) * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
""",
	# Interact highlight, pass 1: inverted hull outline.
	"outline": """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec3 color = vec3(0.37, 0.83, 1.0);
uniform float width = 0.022;
uniform float energy = 2.4;
void vertex() {
	VERTEX += normalize(NORMAL) * width * (1.0 + 0.2 * sin(TIME * 6.0));
}
void fragment() {
	ALBEDO = color * energy * (0.85 + 0.15 * sin(TIME * 6.0));
}
""",
	# Interact highlight, pass 2: fresnel rim plus a rising scan line.
	"rim": """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform vec3 color = vec3(0.37, 0.83, 1.0);
uniform float energy = 1.6;
varying vec3 world_pos;
varying vec3 world_n;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(normalize(world_n), normalize(INV_VIEW_MATRIX[3].xyz - world_pos))), 0.0, 1.0), 3.0);
	float scan = smoothstep(0.92, 1.0, fract(world_pos.y * 0.9 - TIME * 0.7));
	float pulse = 0.8 + 0.2 * sin(TIME * 6.0);
	ALBEDO = color * energy;
	ALPHA = clamp(fres * 0.8 * pulse + scan * 0.18, 0.0, 1.0);
}
""",
}

static var _shader_cache := {}
static var _mesh_cache := {}

var _time := 0.0
var _emitters := {}  # preset -> Array[CPUParticles3D]
var _slots := {}  # kind -> Array[FxSlot]
var _stops: Array = []  # [{"e": CPUParticles3D, "at": float}]
var _items: Array = []  # attached item fx records
var _highlights := {}  # target instance id -> record
var _ambient_root: Node3D
var _ambient: Array = []  # timed ambient emitters
var _trails: Array = []  # thrown-item ribbon trails
var _movers: Array = []  # emitters drifting with a body
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for preset in EMITTER_POOLS:
		_emitters[preset] = []
	for kind in SLOT_POOLS:
		var pool: Array = []
		for i in range(int(SLOT_POOLS[kind])):
			pool.append(_build_slot(kind))
		_slots[kind] = pool


# --- public API ----------------------------------------------------------------------------

func burst(kind: String, at: Vector3, direction := Vector3.UP, color := Color.WHITE) -> void:
	if not is_inside_tree():
		return
	var tint := color
	var custom := color != Color.WHITE
	var dir := direction.normalized() if direction.length_squared() > 1e-6 else Vector3.UP
	match kind:
		"pickup":
			_pickup(at, dir, tint if custom else Color(0.6, 0.92, 1.0))
		"drop":
			_drop(at, tint if custom else Color(0.62, 0.6, 0.58))
		"insert_cell":
			_insert_cell(at, tint if custom else CELL_COLOR)
		"shove_impact":
			_shove(at, dir, tint if custom else Color(0.4, 0.78, 1.0))
		"footstep_dust":
			_footstep(at, dir, tint if custom else Color(0.6, 0.59, 0.57))
		"power_wave":
			_power_wave(at, tint if custom else POWER_COLOR)
		"blackout_flicker":
			_blackout(at, tint if custom else SPARK_COLOR)
		"launch":
			_launch(at, dir, tint if custom else Color(1.0, 0.55, 0.18))
		"alarm_strobe":
			_alarm(at, tint if custom else ALARM_COLOR)
		"muzzle_flash":
			_muzzle(at, dir, tint if custom else BOLT_COLOR)
		"impact":
			_impact(at, dir, tint if custom else BOLT_COLOR)
		"downed":
			_downed(at, tint if custom else Color(1.0, 0.42, 0.25))
		"revive":
			_revive(at, tint if custom else REVIVE_COLOR)
		"airlock_vent":
			_airlock_vent(at, dir, tint if custom else FROST_COLOR)
		"spaced":
			_spaced(at, direction, tint if custom else FROST_COLOR)
		_:
			push_warning("Vfx.burst: unknown kind " + kind)


func countdown_pulse(at: Vector3, color: Color) -> void:
	if not is_inside_tree():
		return
	var ring := _ring(at + Vector3(0, 0.04, 0), Vector3.UP, 1.7, color, 0.75)
	ring.update = func(s: FxSlot, k: float) -> void:
		var e := _ease_out(k)
		s.mat.set_shader_parameter("radius", lerpf(0.12, 0.96, e))
		s.mat.set_shader_parameter("width", lerpf(0.09, 0.02, e))
		s.mat.set_shader_parameter("alpha", (1.0 - k) * (1.0 - k))
		s.mat.set_shader_parameter("dashes", 18.0)
		s.mat.set_shader_parameter("spin", 0.4)
	ring.update.call(ring, 0.0)
	var tube := _acquire_slot("tube", 0.6)
	tube.node.global_transform = Transform3D(Basis.IDENTITY, at)
	_tube_params(tube, color, 1.5, 4.0, 0.03)
	tube.mat.set_shader_parameter("hot", 0.7)
	tube.update = func(s: FxSlot, k: float) -> void:
		var e := _ease_out(k)
		s.node.scale = Vector3(lerpf(0.55, 0.62, e), 0.28, lerpf(0.55, 0.62, e))
		s.node.global_position = at + Vector3(0, lerpf(0.05, 1.3, e), 0)
		s.mat.set_shader_parameter("alpha", (1.0 - k) * minf(1.0, k * 8.0))
	tube.update.call(tube, 0.0)


## Energy bolt from `from` to `to` (~0.15 s) plus an "impact" burst at `to`.
func tracer(from: Vector3, to: Vector3, color := BOLT_COLOR) -> void:
	if not is_inside_tree() or from.is_equal_approx(to):
		return
	var dir := (to - from).normalized()
	var total := from.distance_to(to)
	var bolt := _acquire_slot("dash", 0.16)
	bolt.mat.set_shader_parameter("tint", _vec(color))
	bolt.mat.set_shader_parameter("energy", 3.0)
	bolt.update = func(s: FxSlot, k: float) -> void:
		var head := minf(1.0, k / 0.3)
		var tail := clampf((k - 0.15) / 0.85, 0.0, 1.0)
		tail = maxf(tail, head - minf(1.0, 6.0 / maxf(total, 0.1)))
		var a := from.lerp(to, tail)
		var b := from.lerp(to, head)
		var length := maxf(a.distance_to(b), 0.05)
		s.node.global_transform = Transform3D(_basis_y(dir) * Basis.from_scale(Vector3(0.26 * (1.0 - 0.5 * k), length, 1.0)), (a + b) * 0.5)
		s.mat.set_shader_parameter("alpha", 1.0 - k * k)
	bolt.update.call(bolt, 0.0)
	_impact(to, -dir, color)


## Ribbon trail that follows `node` (thrown items). At most MAX_TRAILS at once.
func attach_trail(node: Node3D, color: Color) -> void:
	if node == null or not is_instance_valid(node) or not is_inside_tree():
		return
	for tr: Dictionary in _trails:
		if tr.node == node and not tr.detached:
			(tr.mat as ShaderMaterial).set_shader_parameter("color", _vec(color))
			return
	if _trails.size() >= MAX_TRAILS:
		var old: Dictionary = _trails.pop_front()
		if is_instance_valid(old.mi):
			old.mi.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "Trail"
	mi.top_level = true
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 200, 1000))
	var mat := _material("beam", {"color": _vec(color), "energy": 3.0})
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	var pts: Array[Vector3] = [node.global_position]
	_trails.append({"node": node, "mi": mi, "mat": mat, "points": pts, "detached": false, "pop": 0.0})


func detach_trail(node: Node3D) -> void:
	for tr: Dictionary in _trails:
		if tr.node == node:
			tr.detached = true


func trail_count() -> int:
	return _trails.size()


func attach_item_fx(item: Node3D, kind: String) -> void:
	if item == null or not is_instance_valid(item):
		return
	_detach_item_fx(item)
	var root := Node3D.new()
	root.name = "VfxItemFx"
	root.set_meta("vfx_skip", true)
	item.add_child(root)
	var rec := {"item": item, "root": root, "kind": kind, "t": _rng.randf() * 10.0, "floor": 0.0}
	var core := kind == "core"
	var ghost := kind == "ghost"
	var color := CORE_COLOR if core else (GHOST_COLOR if ghost else CELL_COLOR)
	# Motes with two-ghost comet trails, driven from script (cheap MultiMesh).
	var motes := 14 if core else (8 if ghost else 7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _quad_mesh()
	mm.instance_count = motes * 3
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Motes"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = _material("glow_particle", {"energy": 3.0, "hot": 0.8, "falloff": 2.4})
	mmi.custom_aabb = AABB(Vector3(-0.8, -0.2, -0.8), Vector3(1.6, 2.6, 1.6))
	root.add_child(mmi)
	rec["mm"] = mm
	rec["motes"] = motes
	rec["color"] = color
	var seeds: Array[float] = []
	for i in range(motes):
		seeds.append(_rng.randf())
	rec["seeds"] = seeds
	# Soft pulsing glow / shimmer halo around the item.
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = _quad_mesh()
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo_mat := _material("flare", {"color": _vec(color), "energy": 1.6, "falloff": 3.2, "core": 0.0, "alpha": 0.35})
	if ghost:
		halo_mat.set_shader_parameter("ring", 0.25)
		halo_mat.set_shader_parameter("wobble", 0.2)
		halo_mat.set_shader_parameter("falloff", 4.0)
		halo.scale = Vector3.ONE * 2.4
		halo.position = Vector3(0, 1.0, 0)
	elif core:
		halo_mat.set_shader_parameter("ring", 0.55)
		halo_mat.set_shader_parameter("ring_radius", 0.62)
		halo_mat.set_shader_parameter("ring_width", 0.07)
		halo_mat.set_shader_parameter("wobble", 0.14)
		halo.scale = Vector3.ONE * 0.95
		halo.position = Vector3(0, 0.38, 0)
	else:
		halo.scale = Vector3.ONE * 0.95
		halo.position = Vector3(0, 0.32, 0)
	halo.material_override = halo_mat
	root.add_child(halo)
	rec["halo"] = halo_mat
	if core:
		# Loot beam + floor marker, shown only while the core lies on the floor.
		var pillar := MeshInstance3D.new()
		pillar.name = "Pillar"
		pillar.mesh = _tube_mesh()
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar.scale = Vector3(0.08, 9.0, 0.08)
		pillar.position = Vector3(0, 4.5, 0)
		var pm := _material("tube", {"color": _vec(color), "energy": 2.0, "alpha": 0.0, "fade_pow": 1.3,
			"bottom_soft": 0.08, "rim": 0.6, "band_count": 6.0, "band_speed": 0.6, "band_amt": 0.35, "hot": 0.25, "near_fade": 9.0})
		pillar.material_override = pm
		pillar.visible = false
		root.add_child(pillar)
		var marker := MeshInstance3D.new()
		marker.name = "Marker"
		marker.mesh = _plane_mesh()
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.scale = Vector3.ONE * 0.8
		marker.position = Vector3(0, 0.03, 0)
		var mk := _material("ring", {"color": _vec(color), "energy": 1.8, "radius": 0.82, "width": 0.035,
			"alpha": 0.0, "fill": 0.06, "dashes": 3.0, "spin": 0.25, "hot": 0.2})
		marker.material_override = mk
		marker.visible = false
		root.add_child(marker)
		rec["pillar"] = pillar
		rec["pillar_mat"] = pm
		rec["marker"] = marker
		rec["marker_mat"] = mk
	_items.append(rec)
	_update_item(rec, 0.0)


func set_interact_highlight(target: Node3D, on: bool, color := HIGHLIGHT_COLOR) -> void:
	if target == null or not is_instance_valid(target):
		return
	var key := target.get_instance_id()
	if not on:
		_clear_highlight(key)
		return
	if _highlights.has(key):
		var rec: Dictionary = _highlights[key]
		var hull: ShaderMaterial = rec.mat
		hull.set_shader_parameter("color", _vec(color))
		(hull.next_pass as ShaderMaterial).set_shader_parameter("color", _vec(color))
		return
	var hull_mat := _material("outline", {"color": _vec(color)})
	hull_mat.render_priority = 1
	var rim_mat := _material("rim", {"color": _vec(color)})
	rim_mat.render_priority = 2
	hull_mat.next_pass = rim_mat
	var meshes: Array = []
	var prev: Array = []
	for mi in _collect_meshes(target):
		meshes.append(mi)
		prev.append(mi.material_overlay)
		mi.material_overlay = hull_mat
	_highlights[key] = {"target": target, "meshes": meshes, "prev": prev, "mat": hull_mat}


func ambient_station(root: Node3D) -> void:
	if root == null:
		return
	if _ambient_root != null and is_instance_valid(_ambient_root):
		_ambient_root.queue_free()
	_ambient.clear()
	_ambient_root = Node3D.new()
	_ambient_root.name = "VfxAmbient"
	_ambient_root.set_meta("vfx_skip", true)
	root.add_child(_ambient_root)
	_ambient_root.global_transform = Transform3D.IDENTITY
	# Dust motes hanging in every room's light (lit additive: they vanish in the dark).
	for room_id in StationLayout.ROOMS:
		var spec: Dictionary = StationLayout.ROOMS[room_id]
		var size: Vector2 = spec.size
		var dust := _new_emitter("ambient_dust")
		dust.emission_box_extents = Vector3(size.x * 0.5 - 0.6, 1.1, size.y * 0.5 - 0.6)
		dust.color = Color(1.0, 0.95, 0.88).lerp(spec.color, 0.25)
		dust.position = StationLayout.to_world(spec.center, 1.45)
		dust.name = "Dust_" + room_id
		_ambient_root.add_child(dust)
		dust.emitting = true
	var eng: Dictionary = StationLayout.ROOMS["engineering"]
	var north: float = eng.center.y - eng.size.y * 0.5
	for vent in [
		{"pos": Vector3(eng.center.x - 1.7, 2.3, north + 0.42), "dir": Vector3(0.1, 0.15, 1.0)},
		{"pos": Vector3(eng.center.x + 3.5, 0.85, north + 0.45), "dir": Vector3(-0.2, 0.55, 1.0)},
	]:
		var steam := _new_emitter("steam")
		steam.name = "Steam"
		steam.position = vent.pos
		steam.direction = (vent.dir as Vector3).normalized()
		_ambient_root.add_child(steam)
		_ambient.append({"e": steam, "kind": "steam", "next": _rng.randf_range(1.0, 4.0), "off": -1.0})
	var cargo: Dictionary = StationLayout.ROOMS["cargo"]
	var conduit := Vector3(cargo.center.x - 1.5, 2.85, cargo.center.y - cargo.size.y * 0.5 + 0.12)
	var zap := _new_emitter("conduit")
	zap.name = "ConduitSparks"
	zap.position = conduit
	_ambient_root.add_child(zap)
	var zap_glow := MeshInstance3D.new()
	zap_glow.mesh = _quad_mesh()
	zap_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zap_glow.position = conduit
	zap_glow.scale = Vector3.ONE * 1.2
	var zap_mat := _material("flare", {"color": _vec(Color(0.6, 0.75, 1.0)), "energy": 3.0, "alpha": 0.0, "streak": 0.6, "pull": 0.2})
	zap_glow.material_override = zap_mat
	_ambient_root.add_child(zap_glow)
	_ambient.append({"e": zap, "kind": "zap", "mat": zap_mat, "next": _rng.randf_range(0.5, 2.0), "off": -1.0})
	# Reactor: rising energy motes and a faint shimmering plume above the column.
	var violet: Color = (StationLayout.ROOMS["reactor"].color as Color).lerp(Color(0.85, 0.8, 1.0), 0.35)
	var plume := _new_emitter("plume")
	plume.name = "ReactorPlume"
	plume.position = REACTOR_CORE + Vector3(0, 4.8, 0)
	plume.color = violet
	_ambient_root.add_child(plume)
	plume.emitting = true
	var haze := MeshInstance3D.new()
	haze.name = "ReactorHaze"
	haze.mesh = _tube_mesh()
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.position = REACTOR_CORE + Vector3(0, 4.75 + 1.8, 0)
	haze.scale = Vector3(0.5, 3.6, 0.5)
	haze.material_override = _material("tube", {"color": _vec(violet), "energy": 1.1, "alpha": 0.16, "fade_pow": 2.0,
		"bottom_soft": 0.08, "rim": 0.9, "band_count": 5.0, "band_speed": 0.7, "band_amt": 0.5, "wobble": 0.7, "hot": 0.0})
	_ambient_root.add_child(haze)


## Emitter nodes currently allocated across all burst pools.
func emitter_count() -> int:
	var n := 0
	for preset in _emitters:
		n += (_emitters[preset] as Array).size()
	return n


## Upper bound of emitter_count().
func pool_capacity() -> int:
	var n := 0
	for preset in EMITTER_POOLS:
		n += int(EMITTER_POOLS[preset])
	return n


## Mesh/light effect slots (fixed size, preallocated).
func slot_count() -> int:
	var n := 0
	for kind in _slots:
		n += (_slots[kind] as Array).size()
	return n


func active_slot_count() -> int:
	var n := 0
	for kind in _slots:
		for s in _slots[kind]:
			if (s as FxSlot).active:
				n += 1
	return n


func item_fx_count() -> int:
	return _items.size()


# --- per-kind bursts -----------------------------------------------------------------------

func _pickup(at: Vector3, up: Vector3, color: Color) -> void:
	var ring := _ring(at + up * 0.06, up, 1.0, color, 0.42)
	ring.update = func(s: FxSlot, k: float) -> void:
		var e := _ease_out(k)
		s.mat.set_shader_parameter("radius", lerpf(0.15, 0.95, e))
		s.mat.set_shader_parameter("width", lerpf(0.1, 0.025, e))
		s.mat.set_shader_parameter("fill", 0.18 * (1.0 - k))
		s.mat.set_shader_parameter("alpha", 1.0 - k * k)
	ring.update.call(ring, 0.0)
	var flare := _flare(at + up * 0.55, 0.9, color, 0.28)
	flare.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("alpha", (1.0 - k) * (1.0 - k))
		s.node.scale = Vector3.ONE * lerpf(0.5, 1.1, _ease_out(k))
	flare.update.call(flare, 0.0)
	var e := _emit("sparkle", at + up * 0.4, up, color)
	e.spread = 75.0


func _drop(at: Vector3, color: Color) -> void:
	_emit("puff", at + Vector3(0, 0.08, 0), Vector3.UP, color)
	var sk := _emit("skitter", at + Vector3(0, 0.05, 0), Vector3.UP, SPARK_COLOR)
	sk.spread = 82.0
	var ring := _ring(at + Vector3(0, 0.03, 0), Vector3.UP, 0.9, Color(0.85, 0.8, 0.72), 0.3)
	ring.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("radius", lerpf(0.2, 0.95, _ease_out(k)))
		s.mat.set_shader_parameter("width", 0.08)
		s.mat.set_shader_parameter("energy", 0.9)
		s.mat.set_shader_parameter("hot", 0.0)
		s.mat.set_shader_parameter("alpha", 0.6 * (1.0 - k))
	ring.update.call(ring, 0.0)


func _insert_cell(at: Vector3, color: Color) -> void:
	var seat := at + Vector3(0, 0.78, 0)
	var arc_color := color.lerp(Color(0.75, 0.88, 1.0), 0.55)
	var arc := _acquire_slot("arc", 0.55)
	arc.node.global_transform = Transform3D(Basis.IDENTITY, seat)
	arc.mat.set_shader_parameter("color", _vec(arc_color))
	arc.data = {"next": 0.0}
	arc.update = func(s: FxSlot, k: float) -> void:
		if s.t >= float(s.data.next):
			s.data.next = s.t + 0.045
			_draw_arcs(s, 0.32, 0.5 + 0.6 * (1.0 - k))
		var flick := 0.55 + 0.45 * _rng.randf()
		s.mat.set_shader_parameter("alpha", flick * (1.0 - k * k))
	arc.update.call(arc, 0.0)
	for i in range(2):
		var delay := 0.14 * float(i)
		var tube := _acquire_slot("tube", 0.75 + delay)
		tube.node.global_transform = Transform3D(Basis.IDENTITY, at)
		_tube_params(tube, color, 1.6, 4.0, 0.03)
		tube.mat.set_shader_parameter("hot", 0.7)
		tube.node.visible = false
		tube.update = func(s: FxSlot, k: float) -> void:
			var local := clampf((s.t - delay) / 0.75, 0.0, 1.0)
			s.node.visible = s.t >= delay
			var e := _ease_out(local)
			s.node.scale = Vector3(0.36 + 0.05 * e, 0.34, 0.36 + 0.05 * e)
			s.node.global_position = at + Vector3(0, lerpf(0.05, 1.6, e), 0)
			s.mat.set_shader_parameter("alpha", 0.8 * (1.0 - local) * minf(1.0, local * 10.0))
		tube.update.call(tube, 0.0)
	var ring := _ring(seat, Vector3.UP, 0.85, color, 0.4)
	ring.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("radius", lerpf(0.2, 0.95, _ease_out(k)))
		s.mat.set_shader_parameter("width", lerpf(0.12, 0.03, k))
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	ring.update.call(ring, 0.0)
	var sp := _emit("spark", seat, Vector3.UP, arc_color)
	sp.spread = 180.0
	sp.initial_velocity_min = 1.5
	sp.initial_velocity_max = 3.8
	var flare := _flare(seat, 1.1, arc_color, 0.35)
	flare.mat.set_shader_parameter("streak", 0.8)
	flare.mat.set_shader_parameter("falloff", 9.0)
	flare.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("alpha", (1.0 - k) * (0.6 + 0.4 * _rng.randf()))
	flare.update.call(flare, 0.0)
	_flash(seat, color, 3.0, 4.0, 0.45)


func _shove(at: Vector3, dir: Vector3, color: Color) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 1e-4:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var chest := at + Vector3(0, 1.05, 0)
	var ring := _ring(chest + flat * 0.25, flat, 1.25, color, 0.32)
	ring.update = func(s: FxSlot, k: float) -> void:
		var e := _ease_out(k)
		s.node.global_position = chest + flat * lerpf(0.2, 0.75, e)
		s.mat.set_shader_parameter("radius", lerpf(0.12, 0.95, e))
		s.mat.set_shader_parameter("width", lerpf(0.16, 0.03, e))
		s.mat.set_shader_parameter("fill", 0.14 * (1.0 - k))
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	ring.update.call(ring, 0.0)
	var ground := _ring(at + Vector3(0, 0.04, 0), Vector3.UP, 1.6, color, 0.36)
	ground.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("radius", lerpf(0.1, 0.95, _ease_out(k)))
		s.mat.set_shader_parameter("width", 0.05)
		s.mat.set_shader_parameter("energy", 1.6)
		s.mat.set_shader_parameter("alpha", 0.8 * (1.0 - k))
	ground.update.call(ground, 0.0)
	var dash := _acquire_slot("dash", 0.2)
	dash.mat.set_shader_parameter("tint", _vec(color))
	dash.update = func(s: FxSlot, k: float) -> void:
		var e := _ease_out(k)
		var length := lerpf(1.8, 0.4, e)
		var center := chest - flat * 0.6 + flat * lerpf(0.0, 1.6, e)
		s.node.global_transform = Transform3D(_basis_y(flat) * Basis.from_scale(Vector3(0.26, length, 1.0)), center)
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	dash.update.call(dash, 0.0)
	var sp := _emit("spark", chest + flat * 0.2, (flat + Vector3(0, 0.25, 0)).normalized(), Color(1.0, 0.85, 0.6).lerp(color, 0.3))
	sp.spread = 38.0
	sp.initial_velocity_min = 3.5
	sp.initial_velocity_max = 7.5
	var flare := _flare(chest + flat * 0.35, 0.8, color, 0.12)
	flare.mat.set_shader_parameter("falloff", 10.0)
	flare.mat.set_shader_parameter("streak", 0.7)
	flare.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	flare.update.call(flare, 0.0)
	_flash(chest, color, 1.8, 3.0, 0.14)


func _footstep(at: Vector3, dir: Vector3, color: Color) -> void:
	var back := Vector3(-dir.x, 0, -dir.z)
	var d := (Vector3.UP + back * 0.6).normalized() if back.length_squared() > 1e-4 else Vector3.UP
	_emit("step", at + Vector3(0, 0.04, 0), d, color)


func _power_wave(at: Vector3, color: Color) -> void:
	var floor_at := Vector3(at.x, 0.05, at.z)
	var ring := _ring(floor_at, Vector3.UP, 1.0, color, POWER_WAVE_TIME)
	_apply_floor_mask(ring.mat)
	ring.update = func(s: FxSlot, k: float) -> void:
		var r := maxf(POWER_WAVE_RADIUS * _ease_out_quad(k), 0.5)
		var sc := r * 1.04 + 0.5
		s.node.scale = Vector3(sc, 1.0, sc)
		s.mat.set_shader_parameter("radius", r / sc)
		s.mat.set_shader_parameter("width", 0.5 / sc)
		s.mat.set_shader_parameter("trail", minf(7.0, r * 0.25) / sc)
		s.mat.set_shader_parameter("energy", 2.6)
		s.mat.set_shader_parameter("hot", 0.5)
		s.mat.set_shader_parameter("alpha", (1.0 - k * k) * minf(1.0, k * 20.0))
	ring.update.call(ring, 0.0)
	var wall := _acquire_slot("tube", POWER_WAVE_TIME)
	_tube_params(wall, color, 2.2, 1.6, 0.02)
	wall.mat.set_shader_parameter("band_count", 3.0)
	wall.mat.set_shader_parameter("band_speed", 2.0)
	wall.mat.set_shader_parameter("band_amt", 0.35)
	wall.mat.set_shader_parameter("wobble", 0.35)
	_apply_floor_mask(wall.mat)
	wall.update = func(s: FxSlot, k: float) -> void:
		var r := maxf(POWER_WAVE_RADIUS * _ease_out_quad(k), 0.5)
		var hgt := lerpf(3.4, 1.6, k)
		s.node.global_transform = Transform3D(Basis.from_scale(Vector3(r, hgt, r)), floor_at + Vector3(0, hgt * 0.5 - 0.04, 0))
		s.mat.set_shader_parameter("alpha", (1.0 - k) * minf(1.0, k * 14.0))
	wall.update.call(wall, 0.0)
	var core := Vector3(at.x, 0, at.z)
	var rise := _emit("rise", core + Vector3(0, 4.6, 0), Vector3.UP, color)
	rise.spread = 30.0
	var flare := _flare(core + Vector3(0, 2.6, 0), 7.0, color, 0.9)
	flare.mat.set_shader_parameter("streak", 1.0)
	flare.mat.set_shader_parameter("falloff", 8.0)
	flare.mat.set_shader_parameter("pull", 1.6)
	flare.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("alpha", 0.8 * pow(1.0 - k, 2.0))
		s.node.scale = Vector3.ONE * lerpf(4.0, 8.0, _ease_out(k))
	flare.update.call(flare, 0.0)
	_flash(core + Vector3(0, 3.0, 0), color, 3.0, 16.0, 1.1)


func _blackout(at: Vector3, color: Color) -> void:
	var offsets := [Vector2.ZERO, Vector2(_rng.randf_range(2.0, 3.6), _rng.randf_range(-2.5, 2.5)), Vector2(_rng.randf_range(-3.6, -2.0), _rng.randf_range(-2.5, 2.5))]
	for off: Vector2 in offsets:
		var p := Vector3(at.x + off.x, CEILING_Y, at.z + off.y)
		var e := _emit("shower", p, Vector3.DOWN, color)
		e.spread = 55.0
		var flare := _flare(p, 1.2, color.lerp(Color(0.8, 0.9, 1.0), 0.5), 0.35)
		flare.mat.set_shader_parameter("streak", 0.7)
		flare.mat.set_shader_parameter("pull", 0.2)
		flare.update = func(s: FxSlot, k: float) -> void:
			s.mat.set_shader_parameter("alpha", (1.0 - k) * (0.3 + 0.7 * float(_rng.randf() > 0.35)))
		flare.update.call(flare, 0.0)
	var light := _flash(Vector3(at.x, CEILING_Y - 0.3, at.z), Color(1.0, 0.8, 0.6), 2.5, 7.0, 0.8)
	light.update = func(s: FxSlot, k: float) -> void:
		var l := s.node as OmniLight3D
		l.light_energy = 2.5 * (1.0 - k) * float(_rng.randf() > 0.45)


func _launch(at: Vector3, dir: Vector3, color: Color) -> void:
	var exhaust_dir := -dir
	var burn := 2.6
	var ex := _emit("exhaust", at, exhaust_dir, color, burn)
	ex.spread = 9.0
	var sm := _emit("smoke", at + exhaust_dir * 0.8, exhaust_dir, Color(0.46, 0.45, 0.45), burn + 0.2)
	sm.spread = 40.0
	var flare := _flare(at, 2.6, color, burn + 0.3)
	flare.mat.set_shader_parameter("streak", 1.0)
	flare.mat.set_shader_parameter("falloff", 9.0)
	flare.mat.set_shader_parameter("pull", 0.8)
	flare.update = func(s: FxSlot, k: float) -> void:
		var fade := minf(1.0, s.t * 6.0) * clampf((s.dur - s.t) / 0.5, 0.0, 1.0)
		s.mat.set_shader_parameter("alpha", fade * (0.82 + 0.18 * _rng.randf()))
		s.node.scale = Vector3.ONE * (2.4 + 0.4 * _rng.randf())
	flare.update.call(flare, 0.0)
	var plume := _acquire_slot("tube", burn + 0.3)
	_tube_params(plume, color, 2.4, 2.2, 0.02)
	plume.mat.set_shader_parameter("rim", 0.7)
	plume.mat.set_shader_parameter("band_count", 5.0)
	plume.mat.set_shader_parameter("band_speed", 6.0)
	plume.mat.set_shader_parameter("band_amt", 0.3)
	plume.mat.set_shader_parameter("wobble", 0.8)
	plume.mat.set_shader_parameter("hot", 0.5)
	plume.update = func(s: FxSlot, k: float) -> void:
		var fade := minf(1.0, s.t * 5.0) * clampf((s.dur - s.t) / 0.5, 0.0, 1.0)
		var length := 2.6 * (0.9 + 0.1 * _rng.randf())
		var b := _basis_y(exhaust_dir) * Basis.from_scale(Vector3(0.26, length, 0.26))
		s.node.global_transform = Transform3D(b, at + exhaust_dir * length * 0.5)
		s.mat.set_shader_parameter("alpha", fade * 0.8)
	plume.update.call(plume, 0.0)
	var ground := Vector3(at.x, 0.05, at.z)
	var ring := _ring(ground, Vector3.UP, 4.5, color, 1.0)
	ring.update = func(s: FxSlot, k: float) -> void:
		var e := _ease_out(k)
		s.mat.set_shader_parameter("radius", lerpf(0.05, 0.95, e))
		s.mat.set_shader_parameter("width", lerpf(0.04, 0.012, e))
		s.mat.set_shader_parameter("energy", 1.6)
		s.mat.set_shader_parameter("alpha", (1.0 - k) * 0.8)
	ring.update.call(ring, 0.0)
	var light := _flash(at + exhaust_dir * 0.6, color, 5.0, 12.0, burn + 0.3)
	light.update = func(s: FxSlot, k: float) -> void:
		var fade := minf(1.0, s.t * 6.0) * clampf((s.dur - s.t) / 0.5, 0.0, 1.0)
		(s.node as OmniLight3D).light_energy = 5.0 * fade * (0.75 + 0.25 * _rng.randf())


func _alarm(at: Vector3, color: Color) -> void:
	var pos := at if at.y > 0.4 else at + Vector3(0, 2.5, 0)
	var slot := _acquire_slot("beacon", 2.4)
	slot.node.global_transform = Transform3D(Basis.IDENTITY, pos)
	var spot: SpotLight3D = slot.parts[0]
	spot.light_color = color
	for m: ShaderMaterial in [slot.parts[2], slot.parts[3], slot.mat]:
		m.set_shader_parameter("color", _vec(color))
	slot.data = {"yaw": _rng.randf() * TAU}
	slot.update = func(s: FxSlot, k: float) -> void:
		var fade := minf(1.0, s.t * 8.0) * clampf((s.dur - s.t) / 0.35, 0.0, 1.0)
		var arm: Node3D = s.parts[1]
		arm.rotation.y = float(s.data.yaw) - s.t * TAU * 0.9
		(s.parts[0] as SpotLight3D).light_energy = 6.0 * fade
		(s.parts[2] as ShaderMaterial).set_shader_parameter("alpha", 0.45 * fade)
		(s.parts[3] as ShaderMaterial).set_shader_parameter("alpha", 0.45 * fade)
		s.mat.set_shader_parameter("alpha", fade * (0.7 + 0.3 * absf(sin(s.t * TAU * 1.8))))
	slot.update.call(slot, 0.0)


func _muzzle(at: Vector3, dir: Vector3, color: Color) -> void:
	var flare := _flare(at + dir * 0.08, 0.75, color, 0.07)
	flare.mat.set_shader_parameter("streak", 0.9)
	flare.mat.set_shader_parameter("falloff", 8.0)
	flare.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	flare.update.call(flare, 0.0)
	var cone := _acquire_slot("dash", 0.08)
	cone.mat.set_shader_parameter("tint", _vec(color))
	cone.mat.set_shader_parameter("energy", 2.2)
	cone.update = func(s: FxSlot, k: float) -> void:
		var length := lerpf(0.55, 0.3, k)
		s.node.global_transform = Transform3D(_basis_y(dir) * Basis.from_scale(Vector3(0.22, length, 1.0)), at + dir * (length * 0.5 + 0.04))
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	cone.update.call(cone, 0.0)
	_emit("step", at + dir * 0.15, (dir + Vector3(0, 0.4, 0)).normalized(), Color(0.7, 0.7, 0.72))
	_flash(at + dir * 0.2, color, 1.6, 3.5, 0.07)


func _impact(at: Vector3, normal: Vector3, color: Color) -> void:
	var sp := _emit("spark", at + normal * 0.03, normal, color.lerp(Color(1, 0.9, 0.7), 0.4))
	sp.spread = 60.0
	sp.initial_velocity_min = 2.0
	sp.initial_velocity_max = 5.0
	var flare := _flare(at + normal * 0.05, 0.7, color, 0.12)
	flare.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	flare.update.call(flare, 0.0)
	var ring := _ring(at + normal * 0.02, normal, 0.45, color, 0.22)
	ring.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("radius", lerpf(0.1, 0.95, _ease_out(k)))
		s.mat.set_shader_parameter("width", 0.1)
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	ring.update.call(ring, 0.0)


func _downed(at: Vector3, color: Color) -> void:
	_emit("puff", at + Vector3(0, 0.08, 0), Vector3.UP, Color(0.6, 0.59, 0.57))
	var sk := _emit("skitter", at + Vector3(0, 0.06, 0), Vector3.UP, SPARK_COLOR)
	sk.spread = 85.0
	var ring := _ring(at + Vector3(0, 0.04, 0), Vector3.UP, 1.5, color, 0.5)
	ring.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("radius", lerpf(0.15, 0.95, _ease_out(k)))
		s.mat.set_shader_parameter("width", lerpf(0.045, 0.015, k))
		s.mat.set_shader_parameter("dashes", 14.0)
		s.mat.set_shader_parameter("energy", 1.7)
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	ring.update.call(ring, 0.0)


func _revive(at: Vector3, color: Color) -> void:
	# Two heal-scan rings climbing the body, rising motes and a floor halo.
	for i in range(2):
		var delay := 0.22 * float(i)
		var tube := _acquire_slot("tube", 1.0 + delay)
		tube.node.global_transform = Transform3D(Basis.IDENTITY, at)
		_tube_params(tube, color, 1.6, 4.0, 0.03)
		tube.mat.set_shader_parameter("hot", 0.6)
		tube.mat.set_shader_parameter("rim", 0.6)
		tube.node.visible = false
		tube.update = func(s: FxSlot, k: float) -> void:
			var local := clampf((s.t - delay) / 1.0, 0.0, 1.0)
			s.node.visible = s.t >= delay
			var e := _ease_out(local)
			var r := lerpf(0.75, 0.5, e)
			s.node.global_transform = Transform3D(Basis.from_scale(Vector3(r, 0.4, r)), at + Vector3(0, lerpf(0.1, 2.1, e), 0))
			s.mat.set_shader_parameter("alpha", 0.8 * (1.0 - local) * minf(1.0, local * 8.0))
		tube.update.call(tube, 0.0)
	var sp := _emit("sparkle", at + Vector3(0, 0.9, 0), Vector3.UP, color)
	sp.spread = 25.0
	var rise := _emit("rise", at + Vector3(0, 0.3, 0), Vector3.UP, color)
	rise.spread = 10.0
	rise.initial_velocity_min = 0.8
	rise.initial_velocity_max = 2.4
	var ring := _ring(at + Vector3(0, 0.04, 0), Vector3.UP, 1.2, color, 1.0)
	ring.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("radius", lerpf(0.95, 0.4, _ease_out(k)))
		s.mat.set_shader_parameter("width", 0.04)
		s.mat.set_shader_parameter("fill", 0.15)
		s.mat.set_shader_parameter("dashes", 10.0)
		s.mat.set_shader_parameter("spin", -0.5)
		s.mat.set_shader_parameter("alpha", sin(k * PI))
	ring.update.call(ring, 0.0)
	_flash(at + Vector3(0, 1.2, 0), color, 2.0, 4.0, 0.9)


func _airlock_vent(at: Vector3, dir: Vector3, color: Color) -> void:
	var fog := _emit("fog", at + Vector3(0, 1.1, 0) + dir * 0.5, dir, Color(0.82, 0.88, 0.94), 1.1)
	fog.spread = 20.0
	var deb := _emit("debris", at + Vector3(0, 1.0, 0), dir, Color(0.7, 0.75, 0.8))
	deb.spread = 18.0
	var fr := _emit("frost", at + Vector3(0, 1.2, 0), dir, color, 0.9)
	fr.initial_velocity_min = 6.0
	fr.initial_velocity_max = 12.0
	var ring := _ring(at + Vector3(0, 1.4, 0) + dir * 0.3, dir, 2.6, color, 0.4)
	ring.update = func(s: FxSlot, k: float) -> void:
		var e := _ease_out(k)
		s.node.global_position = at + Vector3(0, 1.4, 0) + dir * lerpf(0.3, 2.5, e)
		s.mat.set_shader_parameter("radius", lerpf(0.95, 0.2, e))
		s.mat.set_shader_parameter("width", 0.08)
		s.mat.set_shader_parameter("fill", 0.15)
		s.mat.set_shader_parameter("energy", 1.8)
		s.mat.set_shader_parameter("alpha", 1.0 - k)
	ring.update.call(ring, 0.0)
	for i in range(2):
		var side := Vector3(dir.z, 0, -dir.x).normalized() * (0.7 if i == 0 else -0.7)
		var streak := _acquire_slot("dash", 0.5)
		streak.mat.set_shader_parameter("tint", _vec(color))
		streak.mat.set_shader_parameter("energy", 1.6)
		var base := at + Vector3(0, 0.6 + 0.9 * float(i), 0) + side
		streak.update = func(s: FxSlot, k: float) -> void:
			var e := _ease_out(k)
			s.node.global_transform = Transform3D(_basis_y(dir) * Basis.from_scale(Vector3(0.12, 2.4, 1.0)), base + dir * lerpf(0.5, 5.0, e))
			s.mat.set_shader_parameter("alpha", (1.0 - k) * 0.8)
		streak.update.call(streak, 0.0)
	_flash(at + Vector3(0, 1.5, 0), color, 2.0, 6.0, 0.5)


## velocity: the body's drift in m/s (a unit vector means 3 m/s). The emitter
## travels with it for 1.4 s, leaving an ice-crystal wake.
func _spaced(at: Vector3, velocity: Vector3, color: Color) -> void:
	var vel := velocity
	if vel.length_squared() < 1e-6:
		vel = Vector3.UP
	if absf(vel.length() - 1.0) < 0.01:
		vel *= 3.0
	var dir := vel.normalized()
	var fr := _emit("frost", at + Vector3(0, 0.9, 0), -dir, color, 1.4)
	_movers.append({"e": fr, "vel": vel, "until": _time + 1.4})
	fr.spread = 25.0
	fr.initial_velocity_min = 0.4
	fr.initial_velocity_max = 1.5
	fr.explosiveness = 0.0
	var flare := _flare(at + Vector3(0, 0.9, 0), 1.6, color, 0.5)
	flare.update = func(s: FxSlot, k: float) -> void:
		s.mat.set_shader_parameter("alpha", 0.5 * (1.0 - k))
	flare.update.call(flare, 0.0)


# --- frame update --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	for kind in _slots:
		for s: FxSlot in _slots[kind]:
			if not s.active:
				continue
			s.t += delta
			if s.t >= s.dur:
				_release(s)
			elif s.update.is_valid():
				s.update.call(s, s.t / s.dur)
	for i in range(_stops.size() - 1, -1, -1):
		var stop: Dictionary = _stops[i]
		if _time >= float(stop.at):
			var e: CPUParticles3D = stop.e
			if is_instance_valid(e):
				e.emitting = false
			_stops.remove_at(i)
	for i in range(_movers.size() - 1, -1, -1):
		var mv: Dictionary = _movers[i]
		if _time >= float(mv.until) or not is_instance_valid(mv.e):
			_movers.remove_at(i)
		else:
			(mv.e as CPUParticles3D).global_position += (mv.vel as Vector3) * delta
	for i in range(_items.size() - 1, -1, -1):
		var rec: Dictionary = _items[i]
		if not is_instance_valid(rec.item) or not is_instance_valid(rec.root):
			_items.remove_at(i)
			continue
		_update_item(rec, delta)
	for key in _highlights.keys():
		if not is_instance_valid(_highlights[key].target):
			_highlights.erase(key)
	_update_ambient(delta)
	_update_trails(delta)


func _update_trails(delta: float) -> void:
	for i in range(_trails.size() - 1, -1, -1):
		var tr: Dictionary = _trails[i]
		var pts: Array[Vector3] = tr.points
		var live: bool = not tr.detached and is_instance_valid(tr.node) and (tr.node as Node3D).is_inside_tree()
		var moved := false
		if live:
			var p: Vector3 = (tr.node as Node3D).global_position
			if pts.is_empty() or pts[0].distance_squared_to(p) > 0.0009:
				pts.push_front(p)
				moved = true
			if pts.size() > TRAIL_POINTS:
				pts.resize(TRAIL_POINTS)
		# The tail retracts while the node rests or after detach.
		tr.pop = float(tr.pop) + delta
		if tr.pop >= 0.025:
			tr.pop = 0.0
			if not moved and pts.size() > 1:
				pts.pop_back()
		if not live and pts.size() < 2:
			if is_instance_valid(tr.mi):
				tr.mi.queue_free()
			_trails.remove_at(i)
			continue
		_draw_trail(tr)


func _draw_trail(tr: Dictionary) -> void:
	var mi: MeshInstance3D = tr.mi
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var pts: Array[Vector3] = tr.points
	if pts.size() < 2:
		return
	var cam := Vector3(0, 10, 10)
	var vp := get_viewport()
	if vp != null and vp.get_camera_3d() != null:
		cam = vp.get_camera_3d().global_position
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, tr.mat)
	var n := pts.size()
	for i in range(n - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var fa := 1.0 - float(i) / float(TRAIL_POINTS - 1)
		var fb := 1.0 - float(i + 1) / float(TRAIL_POINTS - 1)
		var seg := b - a
		if seg.length_squared() < 1e-8:
			continue
		var sa := seg.cross(cam - a).normalized() * 0.07 * fa
		var sb := seg.cross(cam - b).normalized() * 0.07 * fb
		for v in [[a - sa, 0.0, fa], [a + sa, 1.0, fa], [b + sb, 1.0, fb], [a - sa, 0.0, fa], [b + sb, 1.0, fb], [b - sb, 0.0, fb]]:
			im.surface_set_color(Color(1, 1, 1, float(v[2]) * float(v[2])))
			im.surface_set_uv(Vector2(0.0, v[1]))
			im.surface_add_vertex(v[0])
	im.surface_end()


func _update_item(rec: Dictionary, delta: float) -> void:
	rec.t = float(rec.t) + delta
	var t: float = rec.t
	var mm: MultiMesh = rec.mm
	var color: Color = rec.color
	var motes: int = rec.motes
	var seeds: Array = rec.seeds
	var core: bool = rec.kind == "core"
	var ghost: bool = rec.kind == "ghost"
	for i in range(motes):
		var sd: float = seeds[i]
		for g in range(3):
			var lag := float(g) * 0.07
			var pos: Vector3
			var a := 1.0
			if ghost:
				var s := fposmod(sd + (t - lag * 2.0) * 0.16, 1.0)
				var ang := sd * TAU + s * TAU * 1.2 + (t - lag * 2.0) * 0.9
				var rad := 0.42 + 0.12 * sin(sd * 11.0 + t)
				pos = Vector3(cos(ang) * rad, 0.15 + s * 1.85, sin(ang) * rad)
				a = sin(s * PI) * 0.85
			elif core:
				var strand := float(i % 2)
				var s := fposmod(sd + (t - lag) * 0.32, 1.0)
				var ang := strand * PI + s * TAU * 1.6 + (t - lag) * 1.9 + sd * 2.0
				var rad := 0.34 * (1.0 - 0.55 * s)
				pos = Vector3(cos(ang) * rad, 0.06 + s * 0.85, sin(ang) * rad)
				a = sin(s * PI)
			else:
				var speed := 2.0 + sd * 1.4
				var ang := sd * TAU + (t - lag) * speed
				var rad := 0.25 + 0.05 * sin(sd * 17.0)
				var tilt := (sd - 0.5) * 1.1
				var y := 0.32 + sin(ang) * tilt * rad + 0.14 * sin(t * 0.9 + sd * 9.0)
				pos = Vector3(cos(ang) * rad, y, sin(ang) * rad)
				a = 0.65 + 0.35 * sin(t * 3.0 + sd * 20.0)
			var size := (0.055 if core else 0.06) * (1.0 - float(g) * 0.3)
			var fade := a * (1.0 - float(g) * 0.38)
			mm.set_instance_transform(i * 3 + g, Transform3D(Basis.from_scale(Vector3.ONE * size), pos))
			mm.set_instance_color(i * 3 + g, Color(color.r, color.g, color.b, clampf(fade, 0.0, 1.0)))
	var halo: ShaderMaterial = rec.halo
	if ghost:
		halo.set_shader_parameter("alpha", 0.1 + 0.04 * sin(t * 1.7))
	elif core:
		halo.set_shader_parameter("alpha", 0.3 + 0.08 * sin(t * 2.4))
	else:
		var pulse := 0.5 + 0.5 * sin(t * 3.2)
		halo.set_shader_parameter("alpha", 0.22 + 0.22 * pulse * pulse)
	if core:
		var target := 1.0 if _on_floor(rec.item) else 0.0
		rec.floor = move_toward(float(rec.floor), target, delta * 2.5)
		var f: float = rec.floor
		var pillar: MeshInstance3D = rec.pillar
		var marker: MeshInstance3D = rec.marker
		pillar.visible = f > 0.001
		marker.visible = f > 0.001
		if pillar.visible:
			# Keep the beam vertical even if the core is tilted.
			pillar.global_transform = Transform3D(Basis.from_scale(Vector3(0.08, 9.0, 0.08)), (rec.item as Node3D).global_position + Vector3(0, 4.5, 0))
			marker.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.8), (rec.item as Node3D).global_position + Vector3(0, 0.03, 0))
			(rec.pillar_mat as ShaderMaterial).set_shader_parameter("alpha", f * (0.22 + 0.05 * sin(t * 2.0)))
			(rec.marker_mat as ShaderMaterial).set_shader_parameter("alpha", f * (0.7 + 0.3 * sin(t * 3.0)))


func _update_ambient(delta: float) -> void:
	for a: Dictionary in _ambient:
		var e: CPUParticles3D = a.e
		if not is_instance_valid(e):
			continue
		a.next = float(a.next) - delta
		match a.kind:
			"steam":
				if float(a.off) >= 0.0:
					a.off = float(a.off) - delta
					if float(a.off) < 0.0:
						e.emitting = false
				if float(a.next) <= 0.0:
					e.emitting = true
					a.off = _rng.randf_range(0.8, 1.6)
					a.next = _rng.randf_range(4.0, 8.0)
			"zap":
				var m: ShaderMaterial = a.mat
				if float(a.off) >= 0.0:
					a.off = float(a.off) - delta
					m.set_shader_parameter("alpha", maxf(0.0, float(a.off)) * 6.0 * float(_rng.randf() > 0.3))
				if float(a.next) <= 0.0:
					e.restart()
					a.off = 0.16
					a.next = _rng.randf_range(1.2, 4.5)


# --- emitter pools -------------------------------------------------------------------------

func _emit(preset: String, at: Vector3, dir: Vector3, color: Color, continuous := -1.0) -> CPUParticles3D:
	var e := _acquire_emitter(preset)
	if continuous > 0.0:
		e.one_shot = false
	e.global_position = at
	e.direction = dir
	e.color = color
	e.restart()
	var busy := e.lifetime * (1.0 + e.lifetime_randomness) + 0.1
	if continuous > 0.0:
		_stops.append({"e": e, "at": _time + continuous})
		busy += continuous
	e.set_meta("busy_until", _time + busy)
	e.set_meta("started", _time)
	return e


func _acquire_emitter(preset: String) -> CPUParticles3D:
	var pool: Array = _emitters[preset]
	for e: CPUParticles3D in pool:
		if _time >= float(e.get_meta("busy_until", 0.0)):
			return _reset_emitter(e, preset)
	if pool.size() < int(EMITTER_POOLS[preset]):
		var fresh := _new_emitter(preset)
		fresh.name = "Fx_%s_%d" % [preset, pool.size()]
		add_child(fresh)
		pool.append(fresh)
		return fresh
	var oldest: CPUParticles3D = pool[0]
	for e: CPUParticles3D in pool:
		if float(e.get_meta("started", 0.0)) < float(oldest.get_meta("started", 0.0)):
			oldest = e
	for i in range(_stops.size() - 1, -1, -1):
		if _stops[i].e == oldest:
			_stops.remove_at(i)
	for i in range(_movers.size() - 1, -1, -1):
		if _movers[i].e == oldest:
			_movers.remove_at(i)
	return _reset_emitter(oldest, preset)


## Per-burst code may tweak spread / velocity; put pool defaults back.
func _reset_emitter(e: CPUParticles3D, preset: String) -> CPUParticles3D:
	var d: Dictionary = e.get_meta("defaults", {})
	for key in d:
		e.set(key, d[key])
	return e


func _new_emitter(preset: String) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.emitting = false
	e.one_shot = true
	e.explosiveness = 1.0
	e.local_coords = false
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.mesh = _quad_mesh()
	e.gravity = Vector3.ZERO
	var glow := func(energy: float, star := 0.0, hot := 0.7) -> ShaderMaterial:
		return _material("glow_particle", {"energy": energy, "star": star, "hot": hot})
	match preset:
		"sparkle":
			e.amount = 14
			e.lifetime = 0.7
			e.explosiveness = 0.85
			e.lifetime_randomness = 0.45
			e.material_override = glow.call(4.0, 1.0, 0.9)
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.28
			e.spread = 75.0
			e.initial_velocity_min = 0.6
			e.initial_velocity_max = 2.0
			e.gravity = Vector3(0, -0.8, 0)
			e.damping_min = 1.5
			e.damping_max = 3.0
			e.angle_min = 0.0
			e.angle_max = 45.0
			e.angular_velocity_min = -120.0
			e.angular_velocity_max = 120.0
			e.scale_amount_min = 0.07
			e.scale_amount_max = 0.17
			e.scale_amount_curve = _curve([[0.0, 0.2], [0.12, 1.0], [0.6, 0.7], [1.0, 0.0]])
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]])
		"spark", "skitter", "shower", "conduit":
			e.amount = {"spark": 18, "skitter": 8, "shower": 24, "conduit": 14}[preset]
			e.lifetime = {"spark": 0.45, "skitter": 0.5, "shower": 1.0, "conduit": 0.7}[preset]
			e.lifetime_randomness = 0.5
			e.explosiveness = 0.18 if preset == "shower" else 1.0
			e.particle_flag_align_y = true
			var q := QuadMesh.new()
			q.size = Vector2(0.045, 0.55) if preset == "shower" else (Vector2(0.03, 0.34) if preset != "skitter" else Vector2(0.025, 0.2))
			e.mesh = q
			e.material_override = _material("streak", {"energy": 3.6})
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.06 if preset != "shower" else 0.2
			e.spread = 35.0
			e.initial_velocity_min = {"spark": 3.5, "skitter": 1.4, "shower": 1.0, "conduit": 1.2}[preset]
			e.initial_velocity_max = {"spark": 7.0, "skitter": 3.4, "shower": 4.5, "conduit": 3.0}[preset]
			e.gravity = Vector3(0, -9.8, 0)
			e.damping_min = 0.5
			e.damping_max = 2.5
			e.scale_amount_min = 0.6
			e.scale_amount_max = 1.1
			e.scale_amount_curve = _curve([[0.0, 1.0], [0.7, 0.75], [1.0, 0.0]])
			e.color_ramp = _ramp([[0.0, Color(1.2, 1.15, 1.05, 1)], [0.3, Color(1, 1, 1, 1)], [1.0, Color(0.85, 0.4, 0.25, 0)]])
			if preset == "conduit":
				e.direction = Vector3(0, -0.2, 1).normalized()
				e.spread = 45.0
				e.color = Color(0.75, 0.85, 1.0)
		"puff", "step":
			var puff := preset == "puff"
			e.amount = 10 if puff else 5
			e.lifetime = 0.9 if puff else 0.6
			e.explosiveness = 0.95
			e.lifetime_randomness = 0.35
			e.material_override = _material("smoke", {"opacity": 0.55 if puff else 0.3, "ambient_emit": 0.08})
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.18 if puff else 0.06
			e.spread = 80.0
			e.initial_velocity_min = 0.3
			e.initial_velocity_max = 1.4 if puff else 0.6
			e.radial_accel_min = 1.0 if puff else 0.8
			e.radial_accel_max = 3.0 if puff else 1.6
			e.damping_min = 2.0
			e.damping_max = 3.5
			e.gravity = Vector3(0, 0.25, 0)
			e.angle_max = 360.0
			e.angular_velocity_min = -40.0
			e.angular_velocity_max = 40.0
			e.scale_amount_min = 0.3 if puff else 0.16
			e.scale_amount_max = 0.6 if puff else 0.3
			e.scale_amount_curve = _curve([[0.0, 0.35], [0.3, 0.8], [1.0, 1.0]])
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.12, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0.0)]])
		"rise", "plume":
			var rise := preset == "rise"
			e.amount = 32 if rise else 22
			e.lifetime = 1.6 if rise else 3.4
			e.explosiveness = 0.55 if rise else 0.0
			e.one_shot = rise
			e.lifetime_randomness = 0.4
			e.material_override = glow.call(3.5 if rise else 2.4, 0.0, 0.8)
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE if rise else CPUParticles3D.EMISSION_SHAPE_RING
			e.emission_sphere_radius = 0.6
			e.emission_ring_axis = Vector3.UP
			e.emission_ring_radius = 0.55
			e.emission_ring_inner_radius = 0.2
			e.emission_ring_height = 0.1
			e.direction = Vector3.UP
			e.spread = 25.0 if rise else 8.0
			e.initial_velocity_min = 2.0 if rise else 0.45
			e.initial_velocity_max = 6.5 if rise else 1.1
			e.damping_min = 0.8 if rise else 0.0
			e.damping_max = 1.6 if rise else 0.0
			e.scale_amount_min = 0.06 if rise else 0.04
			e.scale_amount_max = 0.16 if rise else 0.09
			e.scale_amount_curve = _curve([[0.0, 0.3], [0.15, 1.0], [1.0, 0.0]])
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.12, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
			if not rise:
				e.preprocess = 3.0
		"exhaust":
			e.amount = 40
			e.lifetime = 0.42
			e.one_shot = false
			e.explosiveness = 0.0
			e.lifetime_randomness = 0.3
			e.material_override = glow.call(2.4, 0.0, 0.5)
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.18
			e.spread = 9.0
			e.initial_velocity_min = 7.0
			e.initial_velocity_max = 12.0
			e.damping_min = 6.0
			e.damping_max = 12.0
			e.angle_max = 360.0
			e.scale_amount_min = 0.45
			e.scale_amount_max = 0.8
			e.scale_amount_curve = _curve([[0.0, 0.5], [0.3, 1.0], [1.0, 1.9]])
			e.color_ramp = _ramp([[0.0, Color(1.4, 1.3, 1.1, 1)], [0.25, Color(1, 0.75, 0.45, 0.9)], [0.6, Color(0.9, 0.35, 0.12, 0.45)], [1.0, Color(0.4, 0.1, 0.05, 0)]])
		"smoke", "steam":
			var steam := preset == "steam"
			e.amount = 20 if not steam else 14
			e.lifetime = 2.4 if not steam else 1.5
			e.one_shot = false
			e.explosiveness = 0.0
			e.lifetime_randomness = 0.35
			e.material_override = _material("smoke", {"opacity": 0.7 if not steam else 0.42, "self_glow": 0.0 if steam else 1.2, "ambient_emit": 0.35 if steam else 0.05})
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.3 if not steam else 0.05
			e.spread = 40.0 if not steam else 9.0
			e.initial_velocity_min = 2.0 if not steam else 2.2
			e.initial_velocity_max = 4.5 if not steam else 3.4
			e.radial_accel_min = 0.5 if not steam else 0.0
			e.radial_accel_max = 1.5 if not steam else 0.0
			e.damping_min = 1.0 if not steam else 2.0
			e.damping_max = 2.0 if not steam else 3.0
			e.gravity = Vector3(0, 0.5, 0) if not steam else Vector3(0, 0.7, 0)
			e.angle_max = 360.0
			e.angular_velocity_min = -30.0
			e.angular_velocity_max = 30.0
			e.scale_amount_min = 0.7 if not steam else 0.12
			e.scale_amount_max = 1.2 if not steam else 0.22
			e.scale_amount_curve = _curve([[0.0, 0.3], [0.4, 1.4], [1.0, 2.6]] if not steam else [[0.0, 0.4], [1.0, 4.5]])
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 0.75)], [1.0, Color(1, 1, 1, 0)]])
			if steam:
				e.color = Color(0.82, 0.86, 0.9)
		"frost":
			e.amount = 16
			e.lifetime = 0.9
			e.explosiveness = 0.5
			e.lifetime_randomness = 0.4
			e.material_override = glow.call(2.6, 1.0, 0.8)
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.3
			e.spread = 30.0
			e.initial_velocity_min = 2.0
			e.initial_velocity_max = 6.0
			e.damping_min = 1.5
			e.damping_max = 3.0
			e.angle_max = 90.0
			e.angular_velocity_min = -200.0
			e.angular_velocity_max = 200.0
			e.scale_amount_min = 0.07
			e.scale_amount_max = 0.16
			e.scale_amount_curve = _curve([[0.0, 1.0], [1.0, 0.0]])
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
		"debris":
			e.amount = 14
			e.lifetime = 0.8
			e.lifetime_randomness = 0.4
			e.explosiveness = 0.8
			e.particle_flag_align_y = true
			var dq := QuadMesh.new()
			dq.size = Vector2(0.035, 0.55)
			e.mesh = dq
			e.material_override = _material("streak", {"energy": 3.0})
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.6
			e.spread = 22.0
			e.initial_velocity_min = 8.0
			e.initial_velocity_max = 16.0
			e.gravity = Vector3(0, -2.0, 0)
			e.damping_min = 0.5
			e.damping_max = 1.5
			e.scale_amount_min = 0.7
			e.scale_amount_max = 1.2
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
		"fog":
			e.amount = 22
			e.lifetime = 1.4
			e.one_shot = false
			e.explosiveness = 0.0
			e.lifetime_randomness = 0.35
			e.material_override = _material("smoke", {"opacity": 0.75, "ambient_emit": 0.45})
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = 0.7
			e.spread = 18.0
			e.initial_velocity_min = 6.0
			e.initial_velocity_max = 12.0
			e.damping_min = 2.0
			e.damping_max = 3.0
			e.angle_max = 360.0
			e.angular_velocity_min = -60.0
			e.angular_velocity_max = 60.0
			e.scale_amount_min = 0.8
			e.scale_amount_max = 1.4
			e.scale_amount_curve = _curve([[0.0, 0.4], [0.5, 1.6], [1.0, 3.0]])
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.08, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]])
		"ambient_dust":
			e.amount = 14
			e.lifetime = 10.0
			e.one_shot = false
			e.explosiveness = 0.0
			e.preprocess = 10.0
			e.lifetime_randomness = 0.3
			e.material_override = _material("mote", {"energy": 2.2})
			e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			e.spread = 180.0
			e.initial_velocity_min = 0.03
			e.initial_velocity_max = 0.12
			e.gravity = Vector3(0, -0.004, 0)
			e.scale_amount_min = 0.018
			e.scale_amount_max = 0.04
			e.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.2, Color(1, 1, 1, 0.9)], [0.8, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0)]])
	var defaults := {}
	for key in ["spread", "initial_velocity_min", "initial_velocity_max", "one_shot", "explosiveness", "gravity"]:
		defaults[key] = e.get(key)
	e.set_meta("defaults", defaults)
	return e


# --- mesh / light slots --------------------------------------------------------------------

func _build_slot(kind: String) -> FxSlot:
	var s := FxSlot.new()
	s.kind = kind
	match kind:
		"ring", "tube", "flare", "dash", "arc":
			var mi := MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			match kind:
				"ring":
					mi.mesh = _plane_mesh()
					s.mat = _material("ring")
				"tube":
					mi.mesh = _tube_mesh()
					s.mat = _material("tube")
				"flare":
					mi.mesh = _quad_mesh()
					s.mat = _material("flare")
				"dash":
					mi.mesh = _quad_mesh()
					s.mat = _material("streak", {"energy": 3.0})
				"arc":
					mi.mesh = ImmediateMesh.new()
					s.mat = _material("beam")
					mi.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
			mi.material_override = s.mat
			s.node = mi
		"light":
			var l := OmniLight3D.new()
			l.shadow_enabled = false
			l.omni_attenuation = 1.6
			s.node = l
		"beacon":
			var root := Node3D.new()
			var arm := Node3D.new()
			arm.name = "Arm"
			root.add_child(arm)
			var spot := SpotLight3D.new()
			spot.shadow_enabled = false
			spot.spot_range = 14.0
			spot.spot_angle = 24.0
			spot.spot_attenuation = 0.9
			spot.rotation.x = -0.32
			arm.add_child(spot)
			var cones: Array = []
			for side in [0.0, PI]:
				var holder := Node3D.new()
				holder.rotation = Vector3(-0.32, side, 0.0) if side == 0.0 else Vector3(0.32, side, 0.0)
				holder.rotation = Vector3(0.0, side, 0.0)
				var tilt := Node3D.new()
				tilt.rotation.x = -0.32
				holder.add_child(tilt)
				var cone := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.02
				cm.bottom_radius = 1.5
				cm.height = 1.0
				cm.radial_segments = 16
				cm.rings = 1
				cm.cap_top = false
				cm.cap_bottom = false
				cone.mesh = cm
				cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				cone.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1, 7.0, 1)), Vector3(0, 0, -3.5))
				var cmat := _material("cone", {"energy": 0.9})
				cone.material_override = cmat
				tilt.add_child(cone)
				arm.add_child(holder)
				cones.append(cmat)
			var bulb := MeshInstance3D.new()
			bulb.mesh = _quad_mesh()
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bulb.scale = Vector3.ONE * 1.3
			s.mat = _material("flare", {"energy": 3.5, "streak": 0.8, "pull": 0.25})
			bulb.material_override = s.mat
			root.add_child(bulb)
			s.node = root
			s.parts = [spot, arm, cones[0], cones[1]]
	s.node.name = "Slot_" + kind
	s.node.visible = false
	add_child(s.node)
	return s


func _acquire_slot(kind: String, duration: float) -> FxSlot:
	var pool: Array = _slots[kind]
	var pick: FxSlot = null
	for s: FxSlot in pool:
		if not s.active:
			pick = s
			break
	if pick == null:
		pick = pool[0]
		for s: FxSlot in pool:
			if s.started < pick.started:
				pick = s
	pick.active = true
	pick.t = 0.0
	pick.dur = maxf(duration, 0.01)
	pick.started = _time
	pick.update = Callable()
	pick.data = {}
	pick.node.visible = true
	pick.node.scale = Vector3.ONE
	return pick


func _release(s: FxSlot) -> void:
	s.active = false
	s.update = Callable()
	s.node.visible = false
	if s.kind == "light":
		(s.node as OmniLight3D).light_energy = 0.0
	elif s.kind == "beacon":
		(s.parts[0] as SpotLight3D).light_energy = 0.0
	elif s.kind == "arc":
		((s.node as MeshInstance3D).mesh as ImmediateMesh).clear_surfaces()


func _ring(at: Vector3, normal: Vector3, size: float, color: Color, duration: float) -> FxSlot:
	var s := _acquire_slot("ring", duration)
	s.node.global_transform = Transform3D(_basis_y(normal) * Basis.from_scale(Vector3(size, 1.0, size)), at)
	for p in [["color", _vec(color)], ["energy", 2.0], ["radius", 0.5], ["width", 0.05], ["alpha", 1.0],
			["fill", 0.0], ["trail", 0.0], ["dashes", 0.0], ["spin", 0.0], ["hot", 0.35], ["mask_rect", Vector4.ZERO]]:
		s.mat.set_shader_parameter(p[0], p[1])
	return s


func _flare(at: Vector3, size: float, color: Color, duration: float) -> FxSlot:
	var s := _acquire_slot("flare", duration)
	s.node.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * size), at)
	for p in [["color", _vec(color)], ["energy", 2.2], ["alpha", 1.0], ["falloff", 5.0], ["streak", 0.0],
			["core", 1.0], ["ring", 0.0], ["pull", 0.4]]:
		s.mat.set_shader_parameter(p[0], p[1])
	return s


func _tube_params(s: FxSlot, color: Color, energy: float, fade_pow: float, bottom_soft: float) -> void:
	for p in [["color", _vec(color)], ["energy", energy], ["alpha", 1.0], ["fade_pow", fade_pow],
			["bottom_soft", bottom_soft], ["top_soft", 0.0], ["rim", 0.4], ["band_count", 0.0], ["band_speed", 0.0],
			["band_amt", 0.0], ["wobble", 0.0], ["hot", 0.12], ["mask_rect", Vector4.ZERO]]:
		s.mat.set_shader_parameter(p[0], p[1])


func _flash(at: Vector3, color: Color, energy: float, light_range: float, duration: float) -> FxSlot:
	var s := _acquire_slot("light", duration)
	var l := s.node as OmniLight3D
	l.global_position = at
	l.light_color = color
	l.omni_range = light_range
	l.light_energy = energy
	s.update = func(slot: FxSlot, k: float) -> void:
		(slot.node as OmniLight3D).light_energy = energy * (1.0 - k) * (1.0 - k)
	return s


func _draw_arcs(s: FxSlot, radius: float, width_scale: float) -> void:
	var mi := s.node as MeshInstance3D
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var cam_local := Vector3(0, 2, 6)
	var vp := get_viewport()
	if vp != null and vp.get_camera_3d() != null:
		cam_local = vp.get_camera_3d().global_position - mi.global_position
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, s.mat)
	var bolts := 4
	for b in range(bolts):
		var ang := _rng.randf() * TAU
		var start := Vector3(cos(ang) * radius, _rng.randf_range(-0.2, 0.55), sin(ang) * radius)
		var end := Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(-0.05, 0.12), _rng.randf_range(-0.05, 0.05))
		var segs := 7
		var pts: Array[Vector3] = []
		for i in range(segs + 1):
			var f := float(i) / float(segs)
			var p := start.lerp(end, f)
			if i > 0 and i < segs:
				p += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.075 * sin(f * PI)
			pts.append(p)
		var w := 0.03 * width_scale * (1.0 if b % 2 == 0 else 0.6)
		for i in range(segs):
			var a := pts[i]
			var c := pts[i + 1]
			var seg := c - a
			var side := seg.cross(cam_local - a).normalized() * w
			_ribbon_vertex(im, a - side, 0.0)
			_ribbon_vertex(im, a + side, 1.0)
			_ribbon_vertex(im, c + side, 1.0)
			_ribbon_vertex(im, a - side, 0.0)
			_ribbon_vertex(im, c + side, 1.0)
			_ribbon_vertex(im, c - side, 0.0)
	im.surface_end()


func _ribbon_vertex(im: ImmediateMesh, p: Vector3, v: float) -> void:
	im.surface_set_color(Color.WHITE)
	im.surface_set_uv(Vector2(0.0, v))
	im.surface_add_vertex(p)


# --- item fx / highlight helpers -----------------------------------------------------------

func _detach_item_fx(item: Node3D) -> void:
	for i in range(_items.size() - 1, -1, -1):
		if _items[i].item == item:
			if is_instance_valid(_items[i].root):
				_items[i].root.queue_free()
			_items.remove_at(i)
	var old := item.get_node_or_null("VfxItemFx")
	if old != null:
		item.remove_child(old)
		old.queue_free()


## True unless the item is held (under a CharacterBody3D) or seated in a socket.
func _on_floor(item: Node) -> bool:
	var n := item.get_parent()
	while n != null and n != self.get_parent():
		if n is CharacterBody3D or n.has_method("get_seat_transform"):
			return false
		n = n.get_parent()
	return true


func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node.has_meta("vfx_skip"):
		return out
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_meshes(child))
	return out


func _clear_highlight(key: int) -> void:
	if not _highlights.has(key):
		return
	var rec: Dictionary = _highlights[key]
	var meshes: Array = rec.meshes
	for i in range(meshes.size()):
		var mi = meshes[i]
		if is_instance_valid(mi) and (mi as MeshInstance3D).material_overlay == rec.mat:
			(mi as MeshInstance3D).material_overlay = rec.prev[i]
	_highlights.erase(key)


# --- resources -----------------------------------------------------------------------------

static func _shader(key: String) -> Shader:
	if _shader_cache.has(key):
		return _shader_cache[key]
	var code: String = SHADERS[key]
	code = code.replace("%BILLBOARD%", _BILLBOARD_VERTEX).replace("%NOISE%", _NOISE)
	var sh := Shader.new()
	sh.code = code
	_shader_cache[key] = sh
	return sh


func _material(key: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(key)
	for p in params:
		m.set_shader_parameter(p, params[p])
	return m


static var _mask_tex: ImageTexture
static var _mask_rect := Vector4.ZERO


## Clips the power wave to the station's walkable floor (rooms + corridors), so it
## rolls through the deck instead of spilling out over open space.
static func _apply_floor_mask(m: ShaderMaterial) -> void:
	if _mask_tex == null:
		var bounds := Rect2()
		var rects: Array[Rect2] = []
		for room_id in StationLayout.ROOMS:
			rects.append(StationLayout.room_rect(room_id))
		for corridor_id in StationLayout.CORRIDORS:
			rects.append(StationLayout.corridor_rect(corridor_id))
		bounds = rects[0]
		for r in rects:
			bounds = bounds.merge(r)
		bounds = bounds.grow(2.0)
		var px_per_m := 4.0
		var img := Image.create(int(ceil(bounds.size.x * px_per_m)), int(ceil(bounds.size.y * px_per_m)), false, Image.FORMAT_L8)
		img.fill(Color.BLACK)
		for r in rects:
			# Grow slightly so the wave also licks the base of the walls.
			var g := r.grow(0.3)
			img.fill_rect(Rect2i(Vector2i((g.position - bounds.position) * px_per_m), Vector2i(g.size * px_per_m)), Color.WHITE)
		_mask_tex = ImageTexture.create_from_image(img)
		_mask_rect = Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y)
	m.set_shader_parameter("floor_mask", _mask_tex)
	m.set_shader_parameter("mask_rect", _mask_rect)


static func _quad_mesh() -> QuadMesh:
	if not _mesh_cache.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_mesh_cache["quad"] = q
	return _mesh_cache["quad"]


static func _plane_mesh() -> PlaneMesh:
	if not _mesh_cache.has("plane"):
		var p := PlaneMesh.new()
		p.size = Vector2(2, 2)
		_mesh_cache["plane"] = p
	return _mesh_cache["plane"]


static func _tube_mesh() -> CylinderMesh:
	if not _mesh_cache.has("tube"):
		var c := CylinderMesh.new()
		c.top_radius = 1.0
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = 64
		c.rings = 1
		c.cap_top = false
		c.cap_bottom = false
		_mesh_cache["tube"] = c
	return _mesh_cache["tube"]


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	return c


static func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	g.offsets = offsets
	g.colors = colors
	return g


static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Basis whose Y axis points along `up`.
static func _basis_y(up: Vector3) -> Basis:
	var y := up.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)


static func _ease_out_quad(k: float) -> float:
	var x := clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)
