class_name CrewMaterials
extends RefCounted
## Shaders and materials for the crew suit. The body shader skins vertices on the
## GPU from a per-character bone palette (see CrewModel) and picks one of several
## looks per vertex from a material id, so the whole suit is a single draw call.
## Surface detail (panel seams, rivets, scratches, weave, fold creases, decals) is
## procedural in the shader rather than in triangles.

enum { PRIMARY, SECONDARY, FABRIC, METAL, ACCENT, RUBBER, STATUS, LAMP, TRIM, DECAL, BLINK, VENT, GAUGE, SOLE }

const BONE_COUNT := 23
const EXPRESSIONS: Array[String] = ["neutral", "happy", "shocked", "angry", "suspicious", "hurt", "downed", "ghost"]

const _SKIN := """
uniform mat4 bones[23];
varying flat float v_id;
varying flat float v_bone;

void vertex() {
	int a = int(CUSTOM0.x + 0.5);
	int b = int(CUSTOM0.y + 0.5);
	mat4 m = bones[a] * (1.0 - CUSTOM0.z) + bones[b] * CUSTOM0.z;
	VERTEX = (m * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((m * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize((m * vec4(TANGENT, 0.0)).xyz);
	BINORMAL = normalize((m * vec4(BINORMAL, 0.0)).xyz);
	v_id = CUSTOM0.w;
	v_bone = CUSTOM0.x;
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
uniform int decal_number = 0;
uniform vec2 sole_pulse = vec2(0.0);
uniform float vent_puff = 0.0;
uniform float oxygen = 1.0;
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;

float sd_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// Rounded stencil seven-segment digit in a unit-height box; 0 draws the crew emblem.
float glyph(vec2 p, int n) {
	if (n <= 0) {
		float c = min(sd_seg(p, vec2(-0.26, -0.05), vec2(0.0, 0.2), 0.075), sd_seg(p, vec2(0.0, 0.2), vec2(0.26, -0.05), 0.075));
		return min(c, length(p - vec2(0.0, -0.27)) - 0.085);
	}
	int m = 111;
	if (n == 1) { m = 6; } else if (n == 2) { m = 91; } else if (n == 3) { m = 79; } else if (n == 4) { m = 102; }
	else if (n == 5) { m = 109; } else if (n == 6) { m = 125; } else if (n == 7) { m = 7; } else if (n == 8) { m = 127; }
	float w = 0.25;
	float h = 0.42;
	float e = 0.085;
	float r = 0.07;
	float d = 1e3;
	if ((m & 1) != 0) { d = min(d, sd_seg(p, vec2(-w + e, h), vec2(w - e, h), r)); }
	if ((m & 2) != 0) { d = min(d, sd_seg(p, vec2(w, h - e), vec2(w, e), r)); }
	if ((m & 4) != 0) { d = min(d, sd_seg(p, vec2(w, -e), vec2(w, -h + e), r)); }
	if ((m & 8) != 0) { d = min(d, sd_seg(p, vec2(-w + e, -h), vec2(w - e, -h), r)); }
	if ((m & 16) != 0) { d = min(d, sd_seg(p, vec2(-w, -e), vec2(-w, -h + e), r)); }
	if ((m & 32) != 0) { d = min(d, sd_seg(p, vec2(-w, h - e), vec2(-w, e), r)); }
	if ((m & 64) != 0) { d = min(d, sd_seg(p, vec2(-w + e, 0.0), vec2(w - e, 0.0), r)); }
	return d;
}
"""

const _SUIT_FRAGMENT := """
// Inset panel seam + corner rivets on box faces (UV centred, UV2 = half extents).
vec2 panel_detail(vec2 uv, vec2 hx, float fade, out float cav) {
	cav = 0.0;
	vec2 tilt = vec2(0.0);
	if (min(hx.x, hx.y) > 0.024 && fade > 0.0) {
		vec2 q = abs(uv) - (hx - 0.017);
		float box = max(q.x, q.y);
		float g = (1.0 - smoothstep(0.0005, 0.0017, abs(box))) * fade;
		vec2 dv = q.x > q.y ? vec2(sign(uv.x), 0.0) : vec2(0.0, sign(uv.y));
		tilt += dv * sign(box) * g * 0.7;
		cav += g * 0.55;
		if (min(hx.x, hx.y) > 0.034) {
			vec2 d = uv - sign(uv) * (hx - 0.028);
			float rl = length(d);
			float head = (1.0 - smoothstep(0.0026, 0.0034, rl)) * fade;
			tilt += d / 0.003 * 0.45 * head;
			cav += (1.0 - smoothstep(0.0, 0.0007, abs(rl - 0.0034))) * 0.5 * fade;
		}
	}
	return tilt;
}

void fragment() {
	float id = v_id;
	float ao = COLOR.r;
	float edge = COLOR.g;
	float shade = COLOR.b;
	float crease = COLOR.a;
	vec2 nuv = UV + UV2 * 7.13;
	float nlo = texture(detail_noise, nuv * 1.3).r;
	float nhi = texture(detail_noise, nuv * 9.0).r;
	float scratch = texture(detail_noise, nuv * vec2(2.0, 55.0)).r;
	vec3 nmap = texture(detail_normal, nuv * 4.0).rgb;
	float fade = 1.0 - smoothstep(0.0015, 0.004, max(fwidth(UV.x), fwidth(UV.y)));
	vec3 alb = fabric;
	float met = 0.0;
	float rough = 0.8;
	float cc = 0.0;
	float nd = 0.25;
	float rim = 0.0;
	float gloss_rim = 0.0;
	vec2 tilt = vec2(0.0);
	vec3 emi = vec3(0.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (id < 0.5 || (id > 7.5 && id < 8.5)) {
		// Glossy composite shell: clearcoat, micro scratches, lighter worn edges, seams, rivets.
		vec3 base = id < 0.5 ? primary : trim;
		float cav;
		tilt = panel_detail(UV, UV2, fade, cav);
		float wear = smoothstep(0.62, 0.95, edge * (0.5 + nhi * 0.7));
		float scr = smoothstep(0.62, 0.8, scratch) * fade;
		alb = base * shade * (0.95 + 0.1 * nlo);
		alb = mix(alb, mix(base, vec3(0.95), 0.45), clamp(edge * 0.3, 0.0, 1.0));
		alb = mix(alb, vec3(0.6, 0.61, 0.63), wear * 0.55);
		alb *= 1.0 - cav * 0.6;
		met = mix(0.04, 0.85, wear);
		rough = 0.22 + 0.06 * nlo + scr * 0.14 + cav * 0.3;
		cc = 0.9 * (1.0 - wear);
		nd = 0.04;
		gloss_rim = 0.22;
	} else if (id < 1.5) {
		// Satin graphite composite.
		float cav2;
		tilt = panel_detail(UV, UV2, fade, cav2) * 0.8;
		alb = secondary * shade * (0.93 + 0.14 * nlo) * (1.0 - cav2 * 0.5);
		alb = mix(alb, vec3(0.2, 0.21, 0.23), edge * 0.18);
		met = 0.4;
		rough = 0.4 + 0.12 * nhi + smoothstep(0.65, 0.8, scratch) * 0.1 * fade;
		cc = 0.35;
		nd = 0.08;
		gloss_rim = 0.08;
	} else if (id < 2.5) {
		// Satin undersuit: ripstop weave and soft fold creases at the joints.
		vec2 w = UV * 520.0;
		float wf = 1.0 - smoothstep(0.6, 2.0, length(fwidth(w)));
		float fold = cos(UV.y * 115.0 + sin(UV.x * 24.0) * 1.6);
		tilt = vec2(0.22 * wf * cos(w.x) * sin(w.y * 0.5), 0.22 * wf * sin(w.x * 0.5) * cos(w.y));
		tilt.y += crease * 0.55 * sin(UV.y * 115.0 + sin(UV.x * 24.0) * 1.6);
		alb = fabric * shade * (0.92 + 0.16 * nlo) * (1.0 - crease * 0.22 * (0.5 + 0.5 * fold));
		rough = 0.66;
		rim = 0.35;
		nd = 0.0;
	} else if (id < 3.5) {
		// Brushed metal.
		float streak = texture(detail_noise, nuv * vec2(1.5, 90.0)).r;
		alb = vec3(0.62, 0.64, 0.68) * shade * (0.88 + 0.24 * streak);
		met = 0.92;
		rough = 0.24 + 0.14 * streak;
		nd = 0.06;
	} else if (id < 4.5) {
		alb = accent * 0.5;
		emi = accent * accent_energy * (0.92 + 0.08 * sin(TIME * 2.0 + UV.y * 6.0));
		rough = 0.25;
		nd = 0.0;
	} else if (id < 5.5) {
		// Rubber with chunky lug grooves.
		vec2 lug = abs(fract(UV * vec2(28.0, 28.0)) - 0.5);
		float groove = (1.0 - smoothstep(0.32, 0.42, max(lug.x, lug.y))) * fade;
		alb = vec3(0.03, 0.03, 0.032) * shade * (1.0 - groove * 0.4);
		rough = 0.88;
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
	} else if (id < 9.5) {
		// Decals: UV 0..1, UV2 = (style, aspect).
		int style = int(UV2.x + 0.5);
		vec2 dp = (UV - 0.5) * vec2(UV2.y, 1.0);
		float aa = max(fwidth(dp.y), 0.002) * 1.2;
		if (style == 2) {
			float st = step(0.5, fract((dp.x + dp.y) * 3.2));
			alb = mix(vec3(0.05), vec3(0.95, 0.7, 0.08), st);
			rough = 0.45;
			cc = 0.4;
		} else if (style == 3) {
			alb = secondary * 0.7;
			float gx = (UV.x - 0.12) * UV2.y;
			float num = 1.0 - smoothstep(-aa, aa, glyph(vec2(gx, UV.y - 0.5) / 0.8, decal_number));
			float row = step(0.28, UV.x) * step(UV.x, 0.92) * step(0.3, UV.y) * step(UV.y, 0.7);
			float dash = step(0.35, fract(UV.x * 9.0 + floor(UV.y * 3.0) * 0.37)) * row;
			emi = accent * accent_energy * 0.6 * max(num, dash * 0.35);
			rough = 0.35;
			cc = 0.6;
		} else {
			float gd = glyph(dp / 0.78, decal_number);
			float ink = 1.0 - smoothstep(-aa, aa, gd);
			if (style == 1) {
				alb = secondary * 0.8;
				float halo = exp(-max(gd, 0.0) * 18.0) * 0.25;
				emi = accent * accent_energy * (ink + halo);
				rough = 0.35;
				cc = 0.6;
			} else {
				float lum = dot(primary, vec3(0.3, 0.55, 0.15));
				vec3 paint = lum > 0.45 ? vec3(0.06, 0.065, 0.07) : vec3(0.93, 0.94, 0.95);
				alb = mix(primary, paint, ink);
				rough = 0.24 + ink * 0.1;
				cc = 0.8;
				gloss_rim = 0.22;
			}
		}
		nd = 0.0;
	} else if (id < 10.5) {
		// Antenna tip: short beacon flash.
		float f = smoothstep(0.0, 0.05, fract(TIME * 0.7)) * (1.0 - smoothstep(0.08, 0.2, fract(TIME * 0.7)));
		alb = accent * 0.4;
		emi = accent * accent_energy * (0.35 + 2.5 * f);
		nd = 0.0;
	} else if (id < 11.5) {
		// Vents: idle shimmer, puff of glow while running.
		float flick = 0.85 + 0.15 * sin(TIME * 11.0 + UV.x * 40.0);
		alb = accent * 0.4;
		emi = accent * accent_energy * flick * (0.8 + 1.8 * vent_puff);
		nd = 0.0;
	} else if (id < 12.5) {
		// Oxygen gauge: segmented fill.
		float seg = step(0.16, fract(UV.x * 10.0)) * step(0.2, UV.y) * step(UV.y, 0.8);
		float fill = step(UV.x, oxygen);
		vec3 c2 = mix(vec3(1.0, 0.45, 0.05), accent, smoothstep(0.35, 0.6, oxygen));
		alb = vec3(0.03);
		emi = c2 * accent_energy * seg * mix(0.06, 1.0, fill);
		rough = 0.3;
		nd = 0.0;
	} else {
		// Magnetic sole ring: pulses on each footstep.
		float pulse2 = v_bone < 14.5 ? sole_pulse.x : sole_pulse.y;
		alb = accent * 0.5;
		emi = accent * accent_energy * (0.55 + 2.4 * pulse2);
		nd = 0.0;
	}
	float occl = mix(1.0, ao, 0.65);
	ALBEDO = alb * occl;
	METALLIC = met;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.08;
	vec3 n2 = normalize(vec3((nmap.xy * 2.0 - 1.0) * nd + tilt, 1.0));
	NORMAL_MAP = n2 * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	RIM = rim;
	RIM_TINT = 0.4;
	float fres = pow(1.0 - ndv, 4.0);
	EMISSION = emi + alb * fres * gloss_rim * ao + vec3(1.0, 0.25, 0.18) * hit_flash * (0.4 + 2.5 * pow(1.0 - ndv, 2.0));
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
	float glow_part = (id > 3.5 && id < 4.5) || (id > 5.5 && id < 6.5) || id > 9.5 ? 1.0 : 0.0;
	vec3 c = mix(accent, vec3(0.85, 0.95, 1.0), 0.25);
	ALBEDO = c * 0.08;
	ROUGHNESS = 0.4;
	SPECULAR = 0.2;
	EMISSION = c * (fres * 2.6 + 0.12 + scan * 0.12 + band * 0.9 + glow_part * 2.5);
	ALPHA = clamp((0.07 + fres * 0.75 + band * 0.25 + glow_part * 0.5) * ghost_alpha, 0.0, 1.0);
}
"""

## LED face visor. UV is metres on the glass (x across, y up, origin at the visor middle).
const _VISOR := """
shader_type spatial;
render_mode %s;
uniform vec3 tint : source_color = vec3(0.012, 0.016, 0.024);
uniform vec3 eye_color : source_color = vec3(0.6, 0.95, 1.0);
uniform float eye_energy = 5.0;
uniform int expr_a = 0;
uniform int expr_b = 0;
uniform float expr_mix = 1.0;
uniform float blink = 0.0;
uniform vec2 look = vec2(0.0);
uniform float glitch = 0.0;
uniform float reflect_strength = 0.65;
uniform float eye_depth = 0.012;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float sd_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// One eye, centred at the origin. side = +1 for the eye on +x; inward = -side.
float eye_sd(vec2 p, int e, float side, float bl) {
	float inw = -side;
	if (e == 1) {
		return min(sd_seg(p, vec2(-0.018, -0.008), vec2(0.0, 0.01), 0.0058), sd_seg(p, vec2(0.0, 0.01), vec2(0.018, -0.008), 0.0058));
	} else if (e == 2) {
		return abs(length(p) - 0.019) - 0.0055;
	} else if (e == 3) {
		float d = sd_seg(p, vec2(0.0, -0.013), vec2(0.0, 0.01), 0.013);
		return max(d, dot(p - vec2(0.0, 0.001), normalize(vec2(inw * 0.8, 1.0))));
	} else if (e == 4) {
		if (side > 0.0) {
			return sd_seg(p, vec2(-0.014, 0.0), vec2(0.014, 0.0), 0.005);
		}
		return max(sd_seg(p, vec2(0.0, -0.012), vec2(0.0, 0.008), 0.013), p.y - 0.004);
	} else if (e == 5) {
		vec2 tip = vec2(inw * 0.012, 0.0);
		return min(sd_seg(p, vec2(-inw * 0.012, 0.016), tip, 0.0052), sd_seg(p, tip, vec2(-inw * 0.012, -0.016), 0.0052));
	} else if (e == 6) {
		return min(sd_seg(p, vec2(-0.015, -0.015), vec2(0.015, 0.015), 0.005), sd_seg(p, vec2(-0.015, 0.015), vec2(0.015, -0.015), 0.005));
	} else if (e == 7) {
		return abs(length(p) - 0.017) - 0.003;
	}
	float h = 0.014 * (1.0 - bl);
	return sd_seg(p, vec2(0.0, -h), vec2(0.0, h), 0.0128 * (1.0 - bl * 0.4));
}

float face(vec2 uv, int e, float bl) {
	vec2 c = vec2(0.057, 0.008);
	vec2 q = uv - look;
	return min(eye_sd(q - c, e, 1.0, bl), eye_sd(q + vec2(c.x, -c.y), e, -1.0, bl));
}

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
	// LED face behind the glass (parallax so it sits inside the helmet).
	vec2 vt = vec2(dot(VIEW, TANGENT), dot(VIEW, BINORMAL));
	vec2 puv = UV - vt / max(dot(VIEW, n), 0.35) * eye_depth;
	float gl = glitch * (hash(vec2(floor(UV.y * 70.0), floor(TIME * 22.0))) - 0.5);
	puv.x += gl * 0.012;
	float aa = max(max(fwidth(puv.x), fwidth(puv.y)), 0.0003) * 1.1;
	float da = face(puv, expr_a, blink);
	float db = face(puv, expr_b, blink);
	float core = mix(1.0 - smoothstep(-aa, aa, da), 1.0 - smoothstep(-aa, aa, db), expr_mix);
	float halo = mix(exp(-max(da, 0.0) * 140.0), exp(-max(db, 0.0) * 140.0), expr_mix);
	float scan = 0.88 + 0.12 * sin(puv.y * 900.0);
	float flick = mix(1.0, step(0.3, hash(vec2(floor(TIME * 18.0), 3.0))), glitch);
	vec3 led = mix(eye_color, vec3(1.0, 0.2, 0.1), glitch * 0.7);
	float eyes = (core * scan + halo * 0.3) * flick;
	// Soft inner glow: the LEDs light the glass and the rim of the frame.
	vec2 qn = UV / vec2(0.17, 0.09);
	float rimg = smoothstep(0.6, 1.05, max(abs(qn.x), abs(qn.y)));
	vec3 inner = led * (0.012 + 0.05 * rimg) * flick;
	%s
}
"""

const _VISOR_OPAQUE := """
	ALBEDO = tint;
	METALLIC = 0.0;
	ROUGHNESS = 0.05;
	SPECULAR = 1.0;
	EMISSION = env * fres * reflect_strength * 2.4 + led * eyes * eye_energy + inner;
"""

const _VISOR_GHOST := """
	ALBEDO = vec3(0.0);
	EMISSION = mix(eye_color, vec3(1.0), 0.3) * (0.4 + pow(1.0 - ndv, 2.0) * 2.5) + led * eyes * eye_energy;
	ALPHA = clamp(0.22 + pow(1.0 - ndv, 2.0) * 0.6 + eyes, 0.0, 1.0);
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
			code = _VISOR % ["cull_back", _VISOR_OPAQUE]
		"ghost_visor":
			code = _VISOR % ["cull_back, blend_mix, depth_draw_always, shadows_disabled", _VISOR_GHOST]
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
		accent = Color.from_hsv(c.h, clampf(c.s * 0.85 + 0.1, 0.0, 0.85), 1.0).lerp(Color.WHITE, 0.18)
	return {
		"primary": primary,
		"secondary": Color(0.085, 0.09, 0.1),
		"fabric": Color(0.17, 0.175, 0.19).lerp(primary, 0.04),
		"accent": accent,
		"trim": Color(0.74, 0.75, 0.77),
		"eye": accent.lerp(Color(0.85, 0.97, 1.0), 0.45),
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
		"visor", "ghost_visor":
			m.shader = shader(kind)
			m.set_shader_parameter("eye_color", pal["eye"])
	_templates[key] = m
	return m


## Per-character instance (bone palette and state uniforms are per character;
## shader, textures and colour parameters come from the per-colour template).
static func instance(kind: String, color: Color) -> ShaderMaterial:
	return _template(kind, color).duplicate() as ShaderMaterial
