class_name ArtMaterials
extends RefCounted
## Shared shaders and material factories for the station art. Shaders are
## compiled once (static cache); materials are created per owner so power-state
## tweens on one station never leak into props or another station.

const TEX := "res://assets/textures/"

static var _shaders: Dictionary = {}
static var _textures: Dictionary = {}
static var _static_mats: Dictionary = {}


# --- shader sources ---------------------------------------------------------------

## Axis-aligned world-projected PBR (floors/walls are boxes): one texture fetch
## per map instead of triplanar's three. Vertex colour and `tint` multiply albedo.
const WORLD_PBR := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tile = 2.0;
uniform float normal_strength = 1.0;
uniform float metal_scale = 1.0;
uniform float rough_offset = 0.0;
uniform float specular_level = 0.5;
varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(v_wn);
	vec2 uv;
	vec3 t;
	vec3 b;
	if (an.y >= an.x && an.y >= an.z) {
		uv = v_world.xz;
		t = vec3(1.0, 0.0, 0.0);
		b = vec3(0.0, 0.0, -1.0);
	} else if (an.x >= an.z) {
		uv = vec2(v_world.z, -v_world.y);
		t = vec3(0.0, 0.0, 1.0);
		b = vec3(0.0, 1.0, 0.0);
	} else {
		uv = vec2(v_world.x, -v_world.y);
		t = vec3(1.0, 0.0, 0.0);
		b = vec3(0.0, 1.0, 0.0);
	}
	uv /= tile;
	vec3 alb = texture(albedo_tex, uv).rgb;
	vec3 orm = texture(orm_tex, uv).rgb;
	// Normal maps may be imported RG-only (RGTC/ETC2 RG); rebuild Z.
	vec2 nxy = texture(normal_tex, uv).rg * 2.0 - 1.0;
	float nz = sqrt(clamp(1.0 - dot(nxy, nxy), 0.0, 1.0));
	nxy *= normal_strength;
	vec3 nw = normalize(t * nxy.x + b * nxy.y + v_wn * max(nz, 0.05));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = alb * tint * COLOR.rgb;
	ROUGHNESS = clamp(orm.g + rough_offset, 0.04, 1.0);
	METALLIC = orm.b * metal_scale;
	SPECULAR = specular_level;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
}
"""

## Emissive strips, screens and the reactor core. Colour comes from vertex colour.
const GLOW := """
shader_type spatial;
render_mode cull_back;
uniform float energy = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float albedo_mix = 0.12;
uniform float screen = 0.0;
uniform float flow = 0.0;
uniform float flicker = 0.0;
varying vec3 v_world;

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = COLOR.rgb * tint;
	float e = energy;
	if (screen > 0.5) {
		vec2 uv = UV;
		float row = floor(uv.y * 9.0);
		float len = 0.15 + 0.8 * h11(row * 7.0 + floor(TIME * 0.35 + row * 0.37) * 13.0 + floor(v_world.x * 3.0 + v_world.z * 5.0));
		float bar = step(fract(uv.y * 9.0), 0.5) * step(uv.x, len) * step(0.08, uv.x);
		float border = max(max(step(uv.x, 0.03), step(0.97, uv.x)), max(step(uv.y, 0.04), step(0.96, uv.y)));
		float scan = 0.85 + 0.15 * sin(uv.y * 140.0 - TIME * 5.0);
		e *= (0.22 + 0.78 * clamp(bar + border, 0.0, 1.0)) * scan;
	}
	if (flow > 0.0) {
		float w = 0.5 + 0.5 * sin(v_world.y * 5.0 - TIME * 3.5);
		float w2 = 0.5 + 0.5 * sin(v_world.y * 11.0 + TIME * 2.1 + v_world.x);
		e *= 1.0 - flow + flow * (0.45 + 0.4 * w + 0.25 * w2);
	}
	if (flicker > 0.0) {
		float f = h11(floor(TIME * 14.0));
		e *= 1.0 - flicker * step(0.75, f) * 0.75;
	}
	ALBEDO = c * albedo_mix;
	ROUGHNESS = 0.35;
	EMISSION = c * e;
}
"""

const GLASS := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, %s, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(0.55, 0.75, 0.95);
uniform float base_alpha = 0.1;
uniform float rim = 0.55;
uniform float glow = 0.15;

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tint * 0.25;
	METALLIC = 0.0;
	ROUGHNESS = 0.04;
	SPECULAR = 1.0;
	EMISSION = tint * (fres * glow);
	ALPHA = clamp(base_alpha + fres * rim, 0.0, 0.92);
}
"""

const FORCEFIELD := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(0.3, 0.7, 1.0);
uniform float energy = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float bands = 0.5 + 0.5 * sin(UV.y * 48.0 - TIME * 4.0);
	float grid = max(step(0.93, fract(UV.x * 28.0)), step(0.9, fract(UV.y * 10.0 + TIME * 0.4)));
	float a = (0.06 + fres * 0.7 + bands * 0.1 + grid * 0.22) * energy;
	ALBEDO = color * a;
}
"""

const HAZARD := """
shader_type spatial;
uniform vec3 color_a : source_color = vec3(0.95, 0.68, 0.08);
uniform vec3 color_b : source_color = vec3(0.05, 0.05, 0.06);
uniform float freq = 1.6;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float s = fract((v_world.x + v_world.z + v_world.y) * freq);
	float m = smoothstep(0.47, 0.53, s);
	vec3 an = abs(normalize(v_wn));
	vec2 uv = an.y > 0.5 ? v_world.xz : (an.x > an.z ? v_world.zy : v_world.xy);
	vec3 wear = texture(detail_tex, uv).rgb;
	ALBEDO = mix(color_a, color_b, m) * COLOR.rgb * (0.65 + 0.4 * wear.r);
	ROUGHNESS = 0.55 + 0.3 * (1.0 - wear.r);
	METALLIC = 0.1;
}
"""

const SKY := """
shader_type sky;
uniform vec3 sun_dir = vec3(0.5, 0.7, -0.4);
uniform vec3 neb_a : source_color = vec3(0.32, 0.1, 0.5);
uniform vec3 neb_b : source_color = vec3(0.04, 0.3, 0.48);
uniform vec3 neb_c : source_color = vec3(0.6, 0.18, 0.25);
uniform float star_gain = 1.0;
uniform float nebula_gain = 1.0;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(i);
	float b = hash13(i + vec3(1.0, 0.0, 0.0));
	float c = hash13(i + vec3(0.0, 1.0, 0.0));
	float d = hash13(i + vec3(1.0, 1.0, 0.0));
	float e = hash13(i + vec3(0.0, 0.0, 1.0));
	float g = hash13(i + vec3(1.0, 0.0, 1.0));
	float h = hash13(i + vec3(0.0, 1.0, 1.0));
	float k = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

vec3 stars(vec3 d, float scale, float threshold, float size) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	vec3 f = fract(p);
	float h = hash13(c);
	if (h < threshold) {
		return vec3(0.0);
	}
	vec3 o = hash33(c) * 0.5 + 0.25;
	float dist = length(f - o);
	float b = (h - threshold) / (1.0 - threshold);
	float core = smoothstep(size, 0.0, dist);
	vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.65), hash13(c + 7.0));
	return tint * core * core * (0.35 + 2.6 * b * b);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 band_n = normalize(vec3(0.35, 0.85, 0.4));
	float band = exp(-pow(dot(d, band_n) / 0.42, 2.0));
	float n = fbm(d * 2.4 + vec3(3.0));
	float n2 = fbm(d * 5.5 + vec3(11.0));
	float neb = smoothstep(0.38, 0.85, n) * band;
	vec3 neb_col = mix(neb_a, neb_b, smoothstep(0.35, 0.7, n2));
	neb_col = mix(neb_col, neb_c, smoothstep(0.6, 0.85, n) * 0.5);
	float dust = smoothstep(0.45, 0.7, n2) * band;
	vec3 col = vec3(0.004, 0.006, 0.014);
	col += neb_col * neb * 0.55 * nebula_gain;
	col *= 1.0 - dust * 0.6;
	col += neb_col * band * 0.025 * nebula_gain;
	vec3 st = stars(d, 180.0, 0.965, 0.28) * (0.6 + band * 0.8);
	st += stars(d, 70.0, 0.985, 0.18) * 1.6;
	st += stars(d, 330.0, 0.95, 0.3) * band * 0.5;
	col += st * star_gain * (1.0 - dust * 0.7);
	float sd = dot(d, normalize(sun_dir));
	col += vec3(1.0, 0.92, 0.8) * (smoothstep(0.99955, 0.9997, sd) * 30.0 + pow(max(sd, 0.0), 900.0) * 3.0 + pow(max(sd, 0.0), 40.0) * 0.08);
	COLOR = col;
}
"""

const PLANET := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 sun_dir = vec3(0.5, 0.7, -0.4);
uniform vec3 col_a : source_color = vec3(0.85, 0.72, 0.55);
uniform vec3 col_b : source_color = vec3(0.55, 0.36, 0.24);
uniform vec3 col_c : source_color = vec3(0.25, 0.42, 0.55);
uniform vec3 atmo : source_color = vec3(0.35, 0.6, 1.0);
varying vec3 v_obj;
varying vec3 v_wn;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.1 + vec3(3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_obj = normalize(VERTEX);
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = v_obj;
	float warp = fbm(p * 3.0 + vec3(0.0, 0.0, 2.0));
	float lat = p.y + (warp - 0.5) * 0.22;
	float b1 = 0.5 + 0.5 * sin(lat * 24.0);
	float b2 = 0.5 + 0.5 * sin(lat * 9.0 + 1.3);
	float b3 = smoothstep(0.3, 0.8, fbm(vec3(lat * 14.0, p.x * 2.0, p.z * 2.0)));
	vec3 col = mix(col_a, col_b, b1 * 0.8);
	col = mix(col, col_c, b2 * b3 * 0.55);
	vec3 spot_c = normalize(vec3(0.45, -0.28, 0.85));
	float spot = smoothstep(0.2, 0.0, length((p - spot_c) * vec3(1.0, 2.4, 1.0)));
	col = mix(col, vec3(0.78, 0.33, 0.18), spot * 0.85);
	float ndl = dot(normalize(v_wn), normalize(sun_dir));
	float day = smoothstep(-0.1, 0.55, ndl);
	vec3 lit = col * (0.015 + 1.15 * day);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	lit += atmo * fres * smoothstep(-0.25, 0.6, ndl) * 1.1;
	ALBEDO = lit;
}
"""

const ATMOSPHERE := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 sun_dir = vec3(0.5, 0.7, -0.4);
uniform vec3 atmo : source_color = vec3(0.35, 0.6, 1.0);
uniform float edge = 0.31;
uniform float intensity = 1.2;
varying vec3 v_wn;

void vertex() {
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float a = ndv < edge ? pow(ndv / edge, 2.2) : pow((1.0 - ndv) / (1.0 - edge), 5.0);
	float lit = smoothstep(-0.35, 0.5, dot(normalize(v_wn), normalize(sun_dir)));
	ALBEDO = atmo * a * lit * intensity;
}
"""


# --- caches ------------------------------------------------------------------------

static func shader(key: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var code := ""
	match key:
		"world_pbr":
			code = WORLD_PBR
		"glow":
			code = GLOW
		"glass":
			code = GLASS % "cull_disabled"
		"visor":
			code = GLASS % "cull_back"
		"forcefield":
			code = FORCEFIELD
		"hazard":
			code = HAZARD
		"sky":
			code = SKY
		"planet":
			code = PLANET
		"atmosphere":
			code = ATMOSPHERE
	var s := Shader.new()
	s.code = code
	_shaders[key] = s
	return s


static func texture(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	var path := TEX + name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("ArtMaterials: missing texture " + path)
	_textures[name] = tex
	return tex


# --- factories ---------------------------------------------------------------------

static func world_pbr(set_name: String, tint: Color, tile: float, normal_strength := 1.0, metal_scale := 1.0, rough_offset := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("world_pbr")
	m.set_shader_parameter("albedo_tex", texture(set_name + "_albedo"))
	m.set_shader_parameter("normal_tex", texture(set_name + "_normal"))
	m.set_shader_parameter("orm_tex", texture(set_name + "_orm"))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("normal_strength", normal_strength)
	m.set_shader_parameter("metal_scale", metal_scale)
	m.set_shader_parameter("rough_offset", rough_offset)
	return m


static func glow(energy: float, screen := false, flow := 0.0, flicker := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("glow")
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("screen", 1.0 if screen else 0.0)
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("flicker", flicker)
	return m


static func glass(tint := Color(0.55, 0.75, 0.95), base_alpha := 0.1, double_sided := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("glass" if double_sided else "visor")
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("base_alpha", base_alpha)
	return m


static func forcefield(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("forcefield")
	m.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	return m


static func hazard() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("hazard")
	m.set_shader_parameter("detail_tex", texture("metal_paint_albedo"))
	return m


## Painted (vertex-coloured) metal with world triplanar PBR detail. Shared and
## immutable, so props and stations can all batch on the same instance.
static func painted() -> StandardMaterial3D:
	return _pbr_static("painted", true)


## Bare/gunmetal finish: more metallic, colour from vertex colour.
static func metal() -> StandardMaterial3D:
	return _pbr_static("metal", false)


static func _pbr_static(key: String, paint: bool) -> StandardMaterial3D:
	if _static_mats.has(key):
		return _static_mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture("metal_paint_albedo")
	m.normal_enabled = true
	m.normal_texture = texture("metal_paint_normal")
	m.normal_scale = 0.8
	m.roughness_texture = texture("metal_paint_orm")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	if paint:
		m.roughness = 1.0
		m.metallic = 1.0
		m.metallic_texture = texture("metal_paint_orm")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic_specular = 0.5
	else:
		m.roughness = 0.75
		m.metallic = 0.65
		m.metallic_specular = 0.6
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3(1.4, 1.4, 1.4)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_static_mats[key] = m
	return m


## Soft, slightly glossy plastic/fabric for mattresses, cushions, plants.
static func soft() -> StandardMaterial3D:
	if _static_mats.has("soft"):
		return _static_mats["soft"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	_static_mats["soft"] = m
	return m


static func sky_material(sun_dir: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("sky")
	m.set_shader_parameter("sun_dir", sun_dir)
	return m


static func planet_material(sun_dir: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("planet")
	m.set_shader_parameter("sun_dir", sun_dir)
	return m


static func atmosphere_material(sun_dir: Vector3, edge: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("atmosphere")
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("edge", edge)
	return m
