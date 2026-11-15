class_name ItemMaterials
extends RefCounted
## Shaders for the gameplay items and sockets, in the crew suit's visual language:
## glossy clear-coated toy shells, satin graphite, brushed metal, rubber and
## emissive accents. One opaque "body" shader picks a look per vertex from the
## ItemKit material id (CUSTOM0.w), so an item is a single draw call; one
## premultiplied-alpha "fx" shader draws glass, forcefields, holograms and beams.
## Surface detail (panel seams, rivets, scratches, stencils, charge bars, plasma)
## is procedural. Emission stays <= 2.0: the Mobile renderer's buffer clips there.

const BODY := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 shell_a : source_color = vec3(0.88, 0.89, 0.88);
uniform vec3 shell_b : source_color = vec3(0.98, 0.5, 0.12);
uniform vec3 graphite : source_color = vec3(0.075, 0.08, 0.09);
uniform vec3 glow_a : source_color = vec3(1.0, 0.62, 0.15);
uniform vec3 glow_b : source_color = vec3(0.3, 0.92, 1.0);
uniform float glow_energy = 1.7;
uniform vec3 led_color : source_color = vec3(0.3, 1.0, 0.45);
uniform vec3 status_color : source_color = vec3(1.0, 0.72, 0.25);
uniform float status_energy = 1.6;
uniform float status_chase = 0.0;
uniform vec3 warn_color : source_color = vec3(1.0, 0.32, 0.06);
uniform float warn = 0.0;
uniform float ammo = 3.0;
uniform float charge = 1.0;
uniform vec2 charge_span = vec2(0.1, 0.45);
uniform vec3 orb_center = vec3(0.0, 0.36, 0.0);
uniform int decal_number = 0;
uniform float phase = 0.0;
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying flat float v_id;
varying flat float v_group;
varying vec3 v_obj;
varying vec3 v_objn;

void vertex() {
	v_id = CUSTOM0.w;
	v_group = CUSTOM0.x;
	v_obj = VERTEX;
	v_objn = NORMAL;
}

float sd_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// Rounded stencil seven-segment digit 0..9 in a unit-height box.
float glyph(vec2 p, int n) {
	int m = 111;
	if (n == 0) { m = 63; } else if (n == 1) { m = 6; } else if (n == 2) { m = 91; } else if (n == 3) { m = 79; } else if (n == 4) { m = 102; }
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

float sd_tri(vec2 p, float r) {
	const float k = 1.7320508;
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) { p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0; }
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}

float bolt(vec2 p) {
	float d = sd_seg(p, vec2(0.07, 0.3), vec2(-0.09, 0.0), 0.045);
	d = min(d, sd_seg(p, vec2(-0.09, 0.0), vec2(0.09, 0.02), 0.045));
	d = min(d, sd_seg(p, vec2(0.09, 0.02), vec2(-0.06, -0.3), 0.045));
	return d;
}

// Engraved panel line inset from the rounded-box face edge, plus corner rivets.
// UV is centred on the face (metres), UV2 = its half extents.
vec2 panel_detail(vec2 uv, vec2 hx, float fade, float flatness, out float cav) {
	cav = 0.0;
	vec2 tilt = vec2(0.0);
	float m = min(hx.x, hx.y);
	if (m > 0.018 && fade > 0.0) {
		float inset = clamp(m * 0.22, 0.004, 0.011);
		float rc = max(clamp(m * 0.4, 0.006, 0.035) - inset, 0.002);
		vec2 q = abs(uv) - (hx - inset - rc);
		float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rc;
		vec2 gq = (q.x > 0.0 && q.y > 0.0) ? normalize(q) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
		vec2 grad = gq * sign(uv);
		float w = 0.0006 + fwidth(sd);
		float groove = (1.0 - smoothstep(0.0, w, abs(sd))) * fade * flatness;
		float lip = smoothstep(w, w * 2.2, sd) * (1.0 - smoothstep(w * 2.2, w * 3.5, sd)) * fade * flatness;
		tilt += grad * sign(sd) * groove * 0.55;
		cav += groove * 0.55 - lip * 0.25;
		if (m > 0.03) {
			vec2 d = uv - sign(uv) * (hx - inset - rc);
			float rl = length(d);
			float head = (1.0 - smoothstep(0.0022, 0.003, rl)) * fade * flatness;
			tilt += d / 0.003 * 0.4 * head;
			cav += (1.0 - smoothstep(0.0, 0.0007, abs(rl - 0.003))) * 0.4 * fade * flatness;
		}
	}
	return tilt;
}

// Cheap studio / station reflection for glassy parts.
vec3 fake_env(vec3 r) {
	vec3 env = mix(vec3(0.01, 0.012, 0.018), vec3(0.06, 0.08, 0.11), smoothstep(-0.25, 0.05, r.y));
	env = mix(env, vec3(0.16, 0.2, 0.27), smoothstep(0.1, 0.8, r.y));
	env += vec3(0.5, 0.6, 0.78) * exp(-pow((r.y - 0.06) * 10.0, 2.0)) * 0.5;
	env += vec3(1.5, 1.45, 1.35) * smoothstep(0.93, 0.985, dot(r, normalize(vec3(-0.55, 0.62, 0.55))));
	return env;
}

void fragment() {
	float id = v_id;
	float ao = COLOR.r;
	float edge = COLOR.g;
	float shade = COLOR.b;
	vec2 nuv = UV + UV2 * 7.13 + vec2(v_group * 0.37, phase);
	float nlo = texture(detail_noise, nuv * 1.3).r;
	float nhi = texture(detail_noise, nuv * 9.0).r;
	float scratch = texture(detail_noise, nuv * vec2(2.0, 55.0)).r;
	vec3 nmap = texture(detail_normal, nuv * 4.0).rgb;
	float fade = 1.0 - smoothstep(0.0015, 0.004, max(fwidth(UV.x), fwidth(UV.y)));
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 rworld = normalize((INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz);
	float t = TIME + phase * 7.0;
	vec3 alb = graphite;
	float met = 0.0;
	float rough = 0.5;
	float cc = 0.0;
	float nd = 0.1;
	float gloss_rim = 0.0;
	vec2 tilt = vec2(0.0);
	vec3 emi = vec3(0.0);
	if (id < 1.5) {
		// Glossy clear-coated toy shell: seams, rivets, worn lighter edges, micro scratches.
		vec3 base = id < 0.5 ? shell_a : shell_b;
		float cav;
		tilt = panel_detail(UV, UV2, fade, 1.0 - smoothstep(0.15, 0.4, edge), cav);
		float wear = smoothstep(0.62, 0.95, edge * (0.5 + nhi * 0.7));
		float scr = smoothstep(0.62, 0.8, scratch) * fade;
		alb = base * shade * (0.95 + 0.1 * nlo);
		alb = mix(alb, mix(base, vec3(0.95), 0.4), clamp(edge * 0.25, 0.0, 1.0));
		alb = mix(alb, vec3(0.6, 0.61, 0.63), wear * 0.3);
		alb *= 1.0 - cav * 0.6;
		met = mix(0.03, 0.6, wear * 0.5);
		rough = 0.2 + 0.06 * nlo + scr * 0.14 + cav * 0.3;
		cc = 0.9 * (1.0 - wear);
		nd = 0.012;
		gloss_rim = 0.2;
	} else if (id < 2.5) {
		// Satin graphite composite.
		float cav2;
		tilt = panel_detail(UV, UV2, fade, 1.0 - smoothstep(0.15, 0.4, edge), cav2) * 0.8;
		alb = graphite * shade * (0.93 + 0.14 * nlo) * (1.0 - cav2 * 0.5);
		alb = mix(alb, vec3(0.22, 0.23, 0.25), edge * 0.2);
		met = 0.4;
		rough = 0.38 + 0.12 * nhi + smoothstep(0.65, 0.8, scratch) * 0.1 * fade;
		cc = 0.35;
		nd = 0.08;
		gloss_rim = 0.1;
	} else if (id < 3.5 || (id > 16.5 && id < 17.5)) {
		// Brushed metal (17 = warm brass).
		float streak = texture(detail_noise, nuv * vec2(1.5, 90.0)).r;
		vec3 tint = id < 3.5 ? vec3(0.62, 0.64, 0.68) : vec3(0.86, 0.62, 0.3);
		alb = tint * shade * (0.86 + 0.26 * streak);
		alb = mix(alb, alb * 1.25, edge * 0.5);
		met = 0.92;
		rough = 0.22 + 0.14 * streak;
		nd = 0.06;
	} else if (id < 4.5) {
		// Rubber with crisp grip ridges.
		float rr = fract(UV.y * 110.0) - 0.5;
		float groove = (1.0 - smoothstep(0.18, 0.32, abs(rr))) * fade;
		alb = vec3(0.04, 0.04, 0.044) * shade * (1.0 - groove * 0.5);
		rough = 0.8 - groove * 0.1;
		nd = 0.3;
		tilt = vec2(0.0, sign(rr) * groove * 0.35);
	} else if (id < 6.5) {
		vec3 c = id < 5.5 ? glow_a : glow_b;
		alb = c * 0.4;
		emi = c * glow_energy * (0.92 + 0.08 * sin(t * 2.0 + UV.y * 6.0)) * shade;
		rough = 0.25;
		nd = 0.0;
	} else if (id < 7.5) {
		// Hazard stripes (painted, glossy, worn at the edges).
		float s = (UV.x + UV.y) * 14.0;
		float aa = fwidth(s) * 1.2 + 0.001;
		float st = smoothstep(0.5 - aa, 0.5 + aa, fract(s)) * (1.0 - smoothstep(1.0 - aa, 1.0, fract(s)));
		alb = mix(vec3(0.96, 0.68, 0.06), vec3(0.04, 0.04, 0.045), st) * shade;
		float wear2 = smoothstep(0.6, 0.95, edge * (0.5 + nhi * 0.7));
		alb = mix(alb, vec3(0.55, 0.56, 0.58), wear2 * 0.45);
		rough = 0.32 + 0.1 * nlo;
		cc = 0.6;
		nd = 0.05;
	} else if (id < 8.5) {
		// Power-cell window: four stacked charge bars behind glass, rising bubbles,
		// a charge sweep and a slow 0.8 Hz breathe.
		float h = clamp((v_obj.y - charge_span.x) / (charge_span.y - charge_span.x), 0.0, 1.0);
		float segf = fract(h * 4.0);
		float gap = smoothstep(0.0, 0.07, segf) * (1.0 - smoothstep(0.9, 0.97, segf));
		float fill = 1.0 - smoothstep(charge - 0.01, charge + 0.01, h);
		float ang = atan(v_objn.x, v_objn.z);
		float bub = smoothstep(0.6, 0.82, texture(detail_noise, vec2(ang * 0.5, v_obj.y * 2.2 - t * 0.32)).r);
		float sweep_p = fract(t * 0.35 + phase);
		float sweep = exp(-pow((h - sweep_p) * 6.0, 2.0));
		float breathe = 0.86 + 0.14 * sin(t * 5.03);
		vec3 hot = vec3(1.0, 0.9, 0.55);
		vec3 col = mix(glow_a * vec3(1.0, 0.68, 0.45), hot, clamp(h * 0.18 + sweep * 0.45 + bub * 0.3, 0.0, 1.0));
		float lit = fill * gap;
		alb = mix(vec3(0.02, 0.015, 0.01), col * 0.25, lit);
		emi = col * glow_energy * lit * breathe * (0.72 + 0.28 * bub + 0.35 * sweep);
		emi += glow_a * 0.08 * (1.0 - lit) * fill;
		emi += fake_env(rworld) * pow(1.0 - ndv, 3.0) * 0.5;
		rough = 0.06;
		cc = 1.0;
		nd = 0.0;
	} else if (id < 9.5) {
		// Core plasma: swirling filaments, hot centre, bright fresnel limb.
		vec3 d = normalize(v_obj - orb_center);
		float a = t * 0.55 + d.y * 2.4;
		mat2 rot = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
		vec3 q = d;
		q.xz = rot * q.xz;
		vec3 w = pow(abs(q), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec2 drift = vec2(t * 0.07, -t * 0.11);
		float n1 = texture(detail_noise, q.yz * 0.55 + drift).r * w.x + texture(detail_noise, q.xz * 0.55 + drift).r * w.y + texture(detail_noise, q.xy * 0.55 + drift).r * w.z;
		float n2 = texture(detail_noise, q.yz * 1.4 - drift * 1.7).r * w.x + texture(detail_noise, q.xz * 1.4 - drift * 1.7).r * w.y + texture(detail_noise, q.xy * 1.4 - drift * 1.7).r * w.z;
		float fil = pow(1.0 - abs(sin((q.y + n1 * 0.9) * 7.0 + t * 1.3)), 7.0);
		fil += pow(1.0 - abs(sin((q.x * 0.7 + q.z * 0.7 + n2 * 1.2) * 6.0 - t * 0.9)), 9.0) * 0.6;
		float limb = pow(1.0 - ndv, 2.2);
		float hot = pow(ndv, 3.5);
		vec3 deep = glow_b * vec3(0.12, 0.42, 0.8);
		vec3 col = mix(deep, glow_b, smoothstep(0.25, 0.75, n1));
		col = mix(col, vec3(0.8, 1.0, 1.0), clamp(hot * 0.3 + fil * 0.5, 0.0, 1.0));
		float pulse = 0.88 + 0.12 * sin(t * 5.03);
		alb = glow_b * 0.04;
		emi = col * glow_energy * (0.3 + 0.45 * n2 + 0.9 * fil + 0.6 * limb) * pulse;
		emi += fake_env(rworld) * pow(1.0 - ndv, 4.0) * 0.4;
		rough = 0.04;
		cc = 0.4;
		nd = 0.0;
	} else if (id < 10.5) {
		// Gun charge cell: lit while group <= ammo; the last cell throbs.
		float on = step(v_group - 0.5, ammo);
		float last = step(0.5, ammo) * (1.0 - step(1.5, ammo));
		float throb = mix(1.0, 0.55 + 0.45 * sin(t * 7.0), last);
		float core_line = 0.75 + 0.25 * smoothstep(0.2, 1.0, ndv);
		alb = mix(vec3(0.03, 0.03, 0.035), glow_b * 0.3, on);
		emi = glow_b * glow_energy * on * throb * core_line * (0.94 + 0.06 * sin(t * 3.0 + v_group * 2.0));
		emi += (1.0 - on) * vec3(0.6, 0.06, 0.03) * 0.05 * (0.6 + 0.4 * sin(t * 2.0));
		emi += fake_env(rworld) * pow(1.0 - ndv, 3.0) * 0.5;
		rough = 0.06;
		cc = 1.0;
		nd = 0.0;
	} else if (id < 11.5) {
		// Socket status light: state colour; dashes flow toward the seat while waiting.
		float dash = smoothstep(0.25, 0.55, fract(UV.x * 9.0 - t * 1.6)) * (1.0 - smoothstep(0.75, 0.95, fract(UV.x * 9.0 - t * 1.6)));
		float e = status_energy * mix(1.0, 0.35 + 0.9 * dash, status_chase);
		alb = status_color * 0.3;
		emi = status_color * e * shade;
		rough = 0.2;
		nd = 0.0;
	} else if (id < 12.5) {
		// Stencils and pictograms.
		int style = int(UV2.x + 0.5);
		vec2 dp = (UV - 0.5) * vec2(UV2.y, 1.0);
		float aa = max(fwidth(dp.y), 0.002) * 1.2;
		rough = 0.3;
		cc = 0.7;
		nd = 0.0;
		if (style == 0) {
			float tri = sd_tri(vec2(dp.x, dp.y + 0.06), 0.4);
			float ring = 1.0 - smoothstep(-aa, aa, tri);
			float inner = 1.0 - smoothstep(-aa, aa, tri + 0.07);
			float b = 1.0 - smoothstep(-aa, aa, bolt((dp - vec2(0.0, -0.03)) * 1.25));
			alb = mix(shell_a * 0.9, vec3(0.04), ring);
			alb = mix(alb, vec3(0.97, 0.7, 0.08), inner);
			alb = mix(alb, vec3(0.04), b * inner);
		} else if (style == 1) {
			float row = step(0.2, UV.y) * step(UV.y, 0.42) + step(0.58, UV.y) * step(UV.y, 0.8) * step(UV.x, 0.7);
			float ch = step(0.25, fract(UV.x * 11.0)) * step(UV.x, 0.97) * step(0.03, UV.x);
			alb = mix(shell_a * shade, vec3(0.05, 0.05, 0.055), row * ch * 0.9);
		} else if (style == 2) {
			float v = fract(UV.y * 2.0 + t * 0.9);
			float chev = 1.0 - smoothstep(0.05, 0.05 + aa * 4.0, abs(v - 0.5 - abs(dp.x) * 0.9) - 0.1);
			chev *= step(abs(dp.x), 0.42);
			alb = vec3(0.02);
			emi = status_color * status_energy * chev * (0.4 + 0.6 * UV.y);
			rough = 0.15;
		} else if (style == 3) {
			float cr = min(sd_seg(dp, vec2(-0.3, 0.0), vec2(0.3, 0.0), 0.11), sd_seg(dp, vec2(0.0, -0.3), vec2(0.0, 0.3), 0.11));
			float ink = 1.0 - smoothstep(-aa, aa, cr);
			float halo = exp(-max(cr, 0.0) * 14.0) * 0.3;
			alb = vec3(0.03);
			emi = status_color * status_energy * (ink + halo);
		} else if (style == 4) {
			float gd = glyph(dp / 0.8, decal_number);
			float ink = 1.0 - smoothstep(-aa, aa, gd);
			float halo = exp(-max(gd, 0.0) * 16.0) * 0.25;
			alb = vec3(0.03);
			emi = status_color * status_energy * (ink + halo);
		} else if (style == 5) {
			float r = length(dp);
			float an = atan(dp.y, dp.x);
			float blade = step(0.5, fract(an / 2.0943951 + 0.25)) * step(0.13, r) * step(r, 0.42);
			float hub = step(r, 0.08);
			float ink = max(blade, hub);
			alb = mix(vec3(0.97, 0.7, 0.08), vec3(0.04), ink) * shade;
		} else {
			float bars = step(0.45, fract(UV.x * 23.0 + floor(UV.x * 7.0) * 0.31)) * step(0.15, UV.y) * step(UV.y, 0.85);
			alb = mix(shell_a * shade, vec3(0.05), bars);
		}
	} else if (id < 13.5) {
		// Status LED: short double blink.
		float f = fract(t * 0.6 + v_group * 0.37);
		float blink = smoothstep(0.0, 0.02, f) * (1.0 - smoothstep(0.08, 0.12, f)) + smoothstep(0.18, 0.2, f) * (1.0 - smoothstep(0.26, 0.3, f));
		alb = led_color * 0.3;
		emi = led_color * (0.35 + 1.6 * blink);
		rough = 0.1;
		cc = 1.0;
		nd = 0.0;
	} else if (id < 14.5) {
		// Dark glossy glass.
		alb = vec3(0.012, 0.014, 0.018);
		rough = 0.05;
		met = 0.0;
		cc = 1.0;
		nd = 0.0;
		emi = fake_env(rworld) * (0.04 + 0.6 * pow(1.0 - ndv, 4.0)) * 0.6;
	} else if (id < 15.5) {
		// Rotating beacon dome: a sweeping lobe while warn > 0.
		float ang = atan(v_objn.x, v_objn.z);
		float lobe = pow(max(cos(ang - t * 7.5), 0.0), 5.0) * smoothstep(0.05, 0.4, length(v_objn.xz));
		float lobe2 = pow(max(cos(ang - t * 7.5 + 3.14159), 0.0), 5.0) * smoothstep(0.05, 0.4, length(v_objn.xz));
		alb = warn_color * 0.35;
		emi = warn_color * (0.06 + warn * (0.3 + 1.7 * max(lobe, lobe2)));
		rough = 0.12;
		cc = 1.0;
		nd = 0.0;
	} else if (id < 16.5) {
		// Status display: state-coloured frame, bars and a scanline.
		vec2 su = UV / max(UV2 * 2.0, vec2(1e-4)) + 0.5;
		float frame = 1.0 - step(0.06, min(min(su.x, 1.0 - su.x), min(su.y, 1.0 - su.y)));
		float row = floor(su.y * 5.0);
		float len = 0.25 + 0.65 * fract(sin(row * 12.9898 + floor(t * 0.7 + row * 0.37) * 78.233) * 43758.5453);
		float bars = step(0.18, fract(su.y * 5.0)) * step(fract(su.y * 5.0), 0.72) * step(su.x, 0.12 + len * 0.8) * step(0.12, su.x) * step(0.12, su.y) * step(su.y, 0.88);
		float scan = 0.85 + 0.15 * sin(su.y * 160.0 - t * 6.0);
		float flash = warn * step(0.5, fract(t * 2.0));
		vec3 c = mix(status_color, warn_color, warn);
		alb = vec3(0.012);
		emi = c * status_energy * (0.12 + frame * 0.7 + bars * 0.8 + flash * 0.5) * scan * 0.75;
		emi += fake_env(rworld) * pow(1.0 - ndv, 4.0) * 0.4;
		rough = 0.08;
		cc = 1.0;
		nd = 0.0;
	} else {
		// Warning lamp: alternating strobe while warn > 0, dim red glass otherwise.
		float strobe = pow(max(sin(t * 12.566 + v_group * 3.14159), 0.0), 3.0);
		alb = warn_color * 0.3;
		emi = warn_color * (0.05 + warn * (0.25 + 1.75 * strobe));
		rough = 0.12;
		cc = 1.0;
		nd = 0.0;
	}
	float occl = mix(1.0, ao, 0.65);
	ALBEDO = alb * occl;
	METALLIC = met;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.08;
	vec3 n2 = normalize(vec3((nmap.xy * 2.0 - 1.0) * nd + tilt, 1.0));
	NORMAL_MAP = n2 * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	float fres = pow(1.0 - ndv, 4.0);
	EMISSION = min(emi, vec3(2.0)) + alb * fres * gloss_rim * ao;
}
"""

const FX := """
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 status_color : source_color = vec3(1.0, 0.72, 0.25);
uniform float status_energy = 1.0;
uniform vec3 field_color : source_color = vec3(0.35, 0.62, 1.0);
uniform float field = 0.0;
uniform vec3 warn_color : source_color = vec3(1.0, 0.32, 0.06);
uniform float warn = 0.0;
uniform vec3 halo_color : source_color = vec3(0.3, 0.92, 1.0);
uniform float halo_energy = 1.0;
uniform float scan = 0.0;
uniform float seat = 1.0;
uniform vec3 beam_pivot = vec3(0.0, 1.8, 0.0);
uniform vec3 holo_pivot = vec3(0.0, 1.9, 0.0);
uniform vec3 scan_axis = vec3(1.0, 0.0, 0.0);
uniform float scan_range = 0.0;
uniform float phase = 0.0;

varying flat float v_id;
varying flat float v_group;
varying vec3 v_obj;

vec3 rot_y(vec3 p, float a) {
	return vec3(p.x * cos(a) + p.z * sin(a), p.y, -p.x * sin(a) + p.z * cos(a));
}

void vertex() {
	v_id = CUSTOM0.w;
	v_group = CUSTOM0.x;
	v_obj = VERTEX;
	float t = TIME + phase * 7.0;
	if (v_id > 23.5 && v_id < 24.5) {
		// Beacon beams spin around the beacon axis.
		VERTEX = beam_pivot + rot_y(VERTEX - beam_pivot, t * 7.5);
		NORMAL = rot_y(NORMAL, t * 7.5);
	} else if (v_id > 20.5 && v_id < 21.5 && v_group > 0.5) {
		// Hologram backing panel: turns about Y to face the camera.
		vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		float a = atan(cam.x - holo_pivot.x, cam.z - holo_pivot.z);
		VERTEX = holo_pivot + rot_y(VERTEX - holo_pivot, a);
		NORMAL = rot_y(NORMAL, a);
	} else if (v_id > 24.5 && v_id < 25.5) {
		// Scanner sheet sweeps along its axis.
		VERTEX += scan_axis * sin(t * 1.3) * scan_range;
	}
}

void fragment() {
	float id = v_id;
	float t = TIME + phase * 7.0;
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fres = 1.0 - ndv;
	vec3 add = vec3(0.0);
	float cover = 0.0;
	if (id < 20.5) {
		// Forcefield: hex-ish lattice, rising bands, bright fresnel, crackle.
		vec2 g = vec2(UV.x * 1.0, UV.y * 1.0) * 26.0;
		vec2 cell = abs(fract(g + vec2(0.5 * floor(g.y), 0.0)) - 0.5);
		float lat = smoothstep(0.42, 0.5, max(cell.x * 1.15, cell.y));
		float bands = 0.5 + 0.5 * sin(UV.y * 40.0 - t * 3.5);
		float flick = 0.85 + 0.15 * sin(t * 31.0 + UV.y * 7.0);
		float sweep = smoothstep(0.96, 1.0, fract(UV.y * 0.7 - t * 0.35));
		float e = (0.05 + pow(fres, 2.0) * 0.8 + lat * 0.22 + bands * 0.06 + sweep * 0.45) * flick;
		add = field_color * e * field * 1.4;
	} else if (id < 21.5) {
		// Hologram: projector cone glow and label backing panel with scanlines.
		float scanl = 0.75 + 0.25 * sin(v_obj.y * 220.0 - t * 4.0);
		float jitter = 0.9 + 0.1 * step(0.93, fract(sin(floor(t * 12.0) * 91.7) * 4375.5));
		vec2 c = abs(UV - 0.5) * 2.0;
		float border = smoothstep(0.86, 0.94, max(c.x, c.y)) * (1.0 - smoothstep(0.97, 1.0, max(c.x, c.y)));
		float inside = 1.0 - smoothstep(0.88, 1.0, max(c.x, c.y * 1.02));
		float fill = inside * 0.07;
		float panel = v_group > 0.5 ? (border * 0.9 + fill) : (pow(1.0 - UV.y, 1.6) * 0.32 * (0.6 + 0.4 * pow(fres, 0.5)));
		add = status_color * status_energy * panel * scanl * jitter;
		// The panel also darkens what is behind it so the label reads on bright walls.
		cover = v_group > 0.5 ? inside * 0.62 : 0.0;
	} else if (id < 22.5) {
		// Clear glass: fresnel sheen plus two soft streak reflections.
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 wv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float streak = smoothstep(0.82, 0.95, sin((v_obj.x + v_obj.y * 0.8) * 9.0)) * 0.5 + smoothstep(0.9, 0.98, sin((v_obj.x + v_obj.y * 0.8) * 9.0 + 2.2)) * 0.3;
		float f = pow(fres, 3.0);
		add = vec3(0.55, 0.7, 0.85) * (0.03 + f * 0.6 + streak * 0.12) + halo_color * 0.02;
		cover = 0.1 + f * 0.45;
		add *= 1.0 - 0.0 * dot(wn, wv);
	} else if (id < 23.5) {
		// Soft halo shell: bright limb fading into the body.
		float limb = pow(fres, 1.6);
		float body = pow(ndv, 1.5) * 0.25;
		add = halo_color * halo_energy * (limb * 0.9 + body) * (0.9 + 0.1 * sin(t * 5.0));
	} else if (id < 24.5) {
		// Beacon beam: bright at the lamp, fading outward.
		float along = clamp(UV.y, 0.0, 1.0);
		float core = 1.0 - smoothstep(0.0, 0.5, abs(UV.x - 0.5));
		add = warn_color * warn * pow(1.0 - along, 1.8) * core * 0.9;
	} else if (id < 25.5) {
		// Scanner curtain (UV.y 0 at the bed, 1 at the arch): bright at the emitter
		// edge, scanlines rolling down, a faint body.
		float edge_glow = pow(UV.y, 6.0) * 0.9;
		float roll = smoothstep(0.9, 1.0, fract(UV.y * 9.0 + t * 1.4)) * 0.35;
		float sides = 1.0 - smoothstep(0.42, 0.5, abs(UV.x - 0.5));
		add = status_color * status_energy * scan * (0.06 + edge_glow + roll) * sides;
	} else {
		// Seat glow: soft disc with rings converging on the seat.
		float r = length(UV - 0.5) * 2.0;
		float rings = pow(0.5 + 0.5 * sin(r * 22.0 + t * 4.0), 6.0) * (1.0 - smoothstep(0.6, 1.0, r));
		float disc = (1.0 - smoothstep(0.0, 1.0, r)) * 0.25;
		float rim = exp(-pow((r - 0.92) * 12.0, 2.0)) * 0.6;
		add = status_color * status_energy * seat * (rings * 0.45 + disc + rim);
	}
	ALBEDO = min(add, vec3(2.0));
	ALPHA = clamp(cover, 0.0, 1.0);
}
"""

static var _shaders := {}
static var _shared := {}


static func shader(key: String) -> Shader:
	if _shaders.has(key):
		return _shaders[key]
	var s := Shader.new()
	s.code = BODY if key == "body" else FX
	_shaders[key] = s
	return s


## New body material with the given uniform overrides.
static func body(params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("body")
	m.set_shader_parameter("detail_noise", CrewMaterials.noise_texture(false))
	m.set_shader_parameter("detail_normal", CrewMaterials.noise_texture(true))
	for k in params:
		m.set_shader_parameter(k, _param(params[k]))
	return m


## New fx material with the given uniform overrides.
static func fx(params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("fx")
	for k in params:
		m.set_shader_parameter(k, _param(params[k]))
	return m


## A body material shared by every instance of `key` (static looks only).
static func shared_body(key: String, params := {}) -> ShaderMaterial:
	if not _shared.has(key):
		_shared[key] = body(params)
	return _shared[key]


static func shared_fx(key: String, params := {}) -> ShaderMaterial:
	if not _shared.has(key):
		_shared[key] = fx(params)
	return _shared[key]


static func _param(v: Variant) -> Variant:
	if v is Color:
		var c: Color = v
		return Vector3(c.r, c.g, c.b)
	return v


static func vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
