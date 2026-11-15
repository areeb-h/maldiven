class_name CrewMaterials
extends RefCounted
## Shaders and materials for the crew suit. The body shader skins vertices on the
## GPU from a per-character bone palette (see CrewModel), and picks one of several
## PBR looks per vertex from a material id, so the whole suit is a single draw call.

enum { PRIMARY, SECONDARY, FABRIC, METAL, ACCENT, RUBBER, STATUS, LAMP, TRIM }

const BONE_COUNT := 17

const _SKIN := """
uniform mat4 bones[17];
varying flat float v_id;

void vertex() {
	int a = int(CUSTOM0.x + 0.5);
	int b = int(CUSTOM0.y + 0.5);
	mat4 m = bones[a] * (1.0 - CUSTOM0.z) + bones[b] * CUSTOM0.z;
	VERTEX = (m * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((m * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize((m * vec4(TANGENT, 0.0)).xyz);
	BINORMAL = normalize((m * vec4(BINORMAL, 0.0)).xyz);
	v_id = CUSTOM0.w;
}
"""

const _COMMON := """
uniform vec3 primary : source_color = vec3(0.8, 0.35, 0.1);
uniform vec3 secondary : source_color = vec3(0.075, 0.08, 0.09);
uniform vec3 fabric : source_color = vec3(0.13, 0.135, 0.15);
uniform vec3 accent : source_color = vec3(1.0, 0.6, 0.2);
uniform vec3 trim : source_color = vec3(0.72, 0.74, 0.76);
uniform float accent_energy = 3.2;
uniform float lamp_energy = 0.3;
uniform float distress = 0.0;
uniform float hit_flash = 0.0;
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
"""

const _SUIT_FRAGMENT := """
void fragment() {
	float id = v_id;
	float ao = COLOR.r;
	float edge = COLOR.g;
	float shade = COLOR.b;
	float nlo = texture(detail_noise, UV * 1.3).r;
	float nhi = texture(detail_noise, UV * 9.0).r;
	vec3 nmap = texture(detail_normal, UV * 4.0).rgb;
	vec3 alb = fabric;
	float met = 0.0;
	float rough = 0.8;
	float cc = 0.0;
	float nd = 0.25;
	float rim = 0.0;
	vec3 emi = vec3(0.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (id < 0.5) {
		// Painted composite armour: clearcoat, edge-worn to bare alloy.
		float wear = smoothstep(0.5, 0.95, edge * (0.45 + nhi * 0.9));
		alb = primary * shade * (0.9 + 0.2 * nlo);
		alb = mix(alb, mix(primary, vec3(0.9), 0.6), clamp(edge * 0.35, 0.0, 1.0));
		alb = mix(alb, vec3(0.55, 0.56, 0.58), wear * 0.7);
		met = mix(0.08, 0.85, wear);
		rough = 0.32 + 0.14 * nlo + wear * 0.05;
		cc = 0.7 * (1.0 - wear);
		nd = 0.18;
	} else if (id < 1.5) {
		// Graphite composite.
		alb = secondary * shade * (0.8 + 0.4 * nlo);
		alb = mix(alb, vec3(0.32, 0.33, 0.35), edge * 0.55 * smoothstep(0.3, 0.8, nhi));
		met = 0.5;
		rough = 0.38 + 0.2 * nhi;
		cc = 0.25;
		nd = 0.3;
	} else if (id < 2.5) {
		// Woven pressure-suit fabric with a soft sheen.
		vec2 w = UV * 150.0;
		nmap = vec3(0.5 + 0.22 * cos(w.x) * sin(w.y * 0.5), 0.5 + 0.22 * sin(w.x * 0.5) * cos(w.y), 1.0);
		alb = fabric * shade * (0.85 + 0.3 * nlo);
		rough = 0.82;
		rim = 0.35;
		nd = 0.5;
	} else if (id < 3.5) {
		alb = vec3(0.6, 0.62, 0.66) * shade;
		met = 1.0;
		rough = 0.22 + 0.16 * nhi;
		nd = 0.1;
	} else if (id < 4.5) {
		alb = accent * 0.5;
		emi = accent * accent_energy * (0.92 + 0.08 * sin(TIME * 2.0 + UV.y * 6.0));
		rough = 0.25;
		nd = 0.0;
	} else if (id < 5.5) {
		alb = vec3(0.03, 0.03, 0.032) * shade;
		rough = 0.9;
		nd = 0.45;
	} else if (id < 6.5) {
		float pulse = 0.6 + 0.4 * sin(TIME * 3.2);
		float slow = 0.15 + 0.85 * pow(0.5 + 0.5 * sin(TIME * 2.6), 3.0);
		vec3 c = mix(accent * pulse, vec3(1.0, 0.1, 0.04) * slow * 2.0, distress);
		alb = c * 0.3;
		emi = c * accent_energy * 1.4;
		rough = 0.1;
		nd = 0.0;
	} else if (id < 7.5) {
		alb = vec3(0.9);
		emi = vec3(1.0, 0.93, 0.78) * lamp_energy;
		rough = 0.1;
		nd = 0.0;
	} else {
		float wear2 = smoothstep(0.5, 0.95, edge * (0.45 + nhi * 0.9));
		alb = trim * shade * (0.9 + 0.15 * nlo);
		alb = mix(alb, vec3(0.5), wear2 * 0.6);
		met = 0.15 + wear2 * 0.6;
		rough = 0.36 + 0.12 * nlo;
		cc = 0.5;
		nd = 0.15;
	}
	float occl = mix(1.0, ao, 0.65);
	ALBEDO = alb * occl;
	METALLIC = met;
	ROUGHNESS = rough;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.18;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = nd;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	RIM = rim;
	RIM_TINT = 0.4;
	EMISSION = emi + vec3(1.0, 0.25, 0.18) * hit_flash * (0.4 + 2.5 * pow(1.0 - ndv, 2.0));
}
"""

const _GHOST_FRAGMENT := """
uniform float ghost_alpha = 1.0;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.2);
	float id = v_id;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scan = 0.5 + 0.5 * sin(wpos.y * 38.0 - TIME * 5.0);
	float band = smoothstep(0.92, 1.0, sin(wpos.y * 3.0 - TIME * 2.2));
	float glow_part = (id > 3.5 && id < 4.5) || (id > 5.5 && id < 6.5) ? 1.0 : 0.0;
	vec3 c = mix(accent, vec3(0.85, 0.95, 1.0), 0.25);
	ALBEDO = c * 0.08;
	ROUGHNESS = 0.4;
	SPECULAR = 0.2;
	EMISSION = c * (fres * 2.6 + 0.12 + scan * 0.12 + band * 0.9 + glow_part * 2.5);
	ALPHA = clamp((0.07 + fres * 0.75 + band * 0.25 + glow_part * 0.5) * ghost_alpha, 0.0, 1.0);
}
"""

const _VISOR := """
shader_type spatial;
render_mode cull_back;
uniform vec3 tint : source_color = vec3(0.03, 0.04, 0.06);
uniform vec3 accent : source_color = vec3(1.0, 0.6, 0.2);
uniform float hud = 1.0;
uniform float glitch = 0.0;
uniform float reflect_strength = 0.65;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float fres = 0.06 + 0.94 * pow(1.0 - ndv, 4.0);
	vec3 r = normalize((INV_VIEW_MATRIX * vec4(reflect(-VIEW, n), 0.0)).xyz);
	// Studio / station environment: dark floor, cool horizon band, soft overhead, two softboxes.
	vec3 env = mix(vec3(0.012, 0.014, 0.02), vec3(0.06, 0.08, 0.12), smoothstep(-0.25, 0.05, r.y));
	env = mix(env, vec3(0.16, 0.2, 0.28), smoothstep(0.1, 0.8, r.y));
	env += vec3(0.5, 0.62, 0.8) * exp(-pow((r.y - 0.06) * 10.0, 2.0)) * 0.55;
	env += vec3(1.6, 1.55, 1.45) * smoothstep(0.93, 0.985, dot(r, normalize(vec3(-0.55, 0.62, 0.55))));
	env += vec3(0.7, 0.85, 1.2) * smoothstep(0.95, 0.99, dot(r, normalize(vec3(0.7, 0.35, -0.2))));
	// Inner HUD glow: scanlines, a sweep and a couple of side readouts.
	vec2 uv = UV;
	float edge_mask = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x) * smoothstep(0.0, 0.15, uv.y) * smoothstep(1.0, 0.8, uv.y);
	float lines = 0.5 + 0.5 * sin(uv.y * 220.0);
	float sweep = exp(-pow((fract(uv.y * 0.6 - TIME * 0.35) - 0.5) * 18.0, 2.0));
	float side = step(abs(uv.x - 0.5), 0.36) * step(0.3, abs(uv.x - 0.5));
	float bars = side * step(0.42, uv.y) * step(uv.y, 0.62) * step(0.45, fract(uv.y * 18.0));
	float reticle = smoothstep(0.012, 0.0, abs(length((uv - vec2(0.5, 0.52)) * vec2(2.4, 1.0)) - 0.09)) * 0.6;
	float hud_v = (0.05 + 0.07 * lines + 0.35 * sweep) * edge_mask + bars * 0.45 + reticle * 0.4;
	vec3 hud_c = mix(accent, vec3(0.7, 0.95, 1.0), 0.25);
	float g = hash(vec2(floor(uv.y * 40.0), floor(TIME * 24.0)));
	hud_c = mix(hud_c, vec3(1.0, 0.15, 0.08), glitch);
	hud_v *= mix(1.0, step(0.35, g) * (0.5 + g * 1.5), glitch);
	ALBEDO = tint;
	METALLIC = 0.0;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
	EMISSION = env * fres * reflect_strength * 2.0 + hud_c * hud_v * ndv * hud * 1.4;
}
"""

const _GHOST_VISOR := """
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_always, shadows_disabled;
uniform vec3 accent : source_color = vec3(1.0, 0.6, 0.2);
void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.0);
	ALBEDO = vec3(0.0);
	EMISSION = mix(accent, vec3(1.0), 0.4) * (0.4 + fres * 2.5);
	ALPHA = 0.25 + fres * 0.6;
}
"""

static var _shaders := {}
static var _textures := {}
static var _templates := {}


static func shader(key: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var code := ""
	match key:
		"suit":
			code = "shader_type spatial;\nrender_mode cull_back, depth_draw_opaque;\n" + _SKIN + _COMMON + _SUIT_FRAGMENT
		"ghost":
			code = "shader_type spatial;\nrender_mode cull_back, blend_mix, depth_prepass_alpha, shadows_disabled;\n" + _SKIN + _COMMON + _GHOST_FRAGMENT
		"visor":
			code = _VISOR
		"ghost_visor":
			code = _GHOST_VISOR
	var s := Shader.new()
	s.code = code
	_shaders[key] = s
	return s


static func noise_texture(as_normal: bool) -> Texture2D:
	var key := "normal" if as_normal else "noise"
	if _textures.has(key):
		return _textures[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	noise.seed = 7
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.generate_mipmaps = true
	if as_normal:
		tex.as_normal_map = true
		tex.bump_strength = 4.0
		noise.frequency = 0.03
	_textures[key] = tex
	return tex


## Primary paint, neutral secondary and an emissive accent derived from the suit colour.
static func palette(color: Color) -> Dictionary:
	var c := color
	var primary := Color.from_hsv(c.h, clampf(c.s * 0.92, 0.0, 0.9), clampf(c.v, 0.25, 0.86))
	var accent: Color
	if c.s < 0.15:
		accent = Color(0.75, 0.92, 1.0)
	else:
		accent = Color.from_hsv(c.h, clampf(c.s * 0.85 + 0.1, 0.0, 0.85), 1.0)
	return {
		"primary": primary,
		"secondary": Color(0.085, 0.09, 0.1),
		"fabric": Color(0.16, 0.165, 0.18).lerp(primary, 0.06),
		"accent": accent,
		"trim": Color(0.74, 0.75, 0.77),
	}


static func _template(kind: String, color: Color) -> ShaderMaterial:
	var key := "%s:%s" % [kind, color.to_html()]
	if _templates.has(key):
		return _templates[key]
	var pal := palette(color)
	var m := ShaderMaterial.new()
	match kind:
		"suit", "ghost":
			m.shader = shader(kind)
			for p in ["primary", "secondary", "fabric", "accent", "trim"]:
				m.set_shader_parameter(p, pal[p])
			m.set_shader_parameter("detail_noise", noise_texture(false))
			m.set_shader_parameter("detail_normal", noise_texture(true))
		"visor":
			m.shader = shader("visor")
			m.set_shader_parameter("accent", pal["accent"])
			m.set_shader_parameter("tint", Color(0.035, 0.045, 0.06).lerp(pal["primary"], 0.06))
		"ghost_visor":
			m.shader = shader("ghost_visor")
			m.set_shader_parameter("accent", pal["accent"])
	_templates[key] = m
	return m


## Per-character instance (bone palette and state uniforms are per character;
## shader, textures and colour parameters come from the per-colour template).
static func instance(kind: String, color: Color) -> ShaderMaterial:
	return _template(kind, color).duplicate() as ShaderMaterial
