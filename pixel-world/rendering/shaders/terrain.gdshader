shader_type canvas_item;
render_mode unshaded;

// Terrain look-development shader.
//
// The whole 256x256 world is one sprite, so every ambient effect below costs a
// single full-screen pass instead of per-entity work: animated water with
// depth-aware waves and shoreline foam, wind rippling over vegetation, lava
// and fire emission that survives the night grade, scrolling cloud shadows,
// rain wetness and a subtle heat shimmer.
//
// TEXTURE  : baked albedo (one texel per cell)
// data_tex : R fire, G shoreline proximity, B vegetation, A material class

uniform sampler2D data_tex : filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;

uniform vec2 world_size = vec2(256.0, 256.0);
uniform float time_s = 0.0;
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform vec3 ambient_tint : source_color = vec3(1.0);
uniform vec2 wind = vec2(0.2, 0.05);
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_scroll = 0.0;
uniform float heat : hint_range(0.0, 2.0) = 0.0;
uniform float water_level_tint : hint_range(0.0, 1.0) = 0.0;
// Opening reveal: the world materialises out of noise with a bright edge.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;

const float MAT_WATER = 0.25;
const float MAT_DEEP  = 0.35;
const float MAT_LAVA  = 0.50;
const float MAT_SNOW  = 0.65;
const float MAT_ICE   = 0.75;

float is_mat(float v, float m) {
	return 1.0 - step(0.045, abs(v - m));
}

void fragment() {
	vec2 uv = UV;
	vec4 d = texture(data_tex, uv);
	float fire = d.r;
	float shore = d.g;
	float veg = d.b;
	float mat = d.a;

	// Cell-space coordinates drive every animated pattern.
	vec2 wuv = uv * world_size;

	float water = max(is_mat(mat, MAT_WATER), is_mat(mat, MAT_DEEP));
	float deep = is_mat(mat, MAT_DEEP);
	float lava = is_mat(mat, MAT_LAVA);
	float icy = max(is_mat(mat, MAT_SNOW), is_mat(mat, MAT_ICE));

	// Heat shimmer near fire / lava: nudges the albedo lookup.
	float shimmer = (fire + lava) * heat;
	if (shimmer > 0.001) {
		float s = texture(noise_tex, wuv * 0.08 + vec2(0.0, -time_s * 0.35)).r - 0.5;
		uv += vec2(s, s * 0.4) * shimmer * 0.004;
	}
	vec3 col = texture(TEXTURE, uv).rgb;
	vec3 emis = vec3(0.0);

	// ---------------------------------------------------------------- water
	if (water > 0.5) {
		float n1 = texture(noise_tex, wuv * 0.020 + vec2(time_s * 0.011, time_s * 0.0065)).r;
		float n2 = texture(noise_tex, wuv * 0.047 - vec2(time_s * 0.016, time_s * 0.010)).g;
		float wave = n1 * 0.62 + n2 * 0.38;
		// Swell: brighter crests, darker troughs, calmer in the abyss.
		col += vec3(0.05, 0.11, 0.15) * (wave - 0.5) * 2.0 * mix(1.0, 0.55, deep);
		// Sun glitter on the crests.
		float glint = smoothstep(0.74, 0.93, wave)
			* (0.55 + 0.45 * sin(time_s * 2.1 + wuv.x * 0.9 + wuv.y * 0.5));
		emis += vec3(0.42, 0.58, 0.72) * glint * 0.30 * day_factor;
		// Shoreline foam: a moving band keyed to the baked shore distance.
		float surf = 0.5 + 0.5 * sin(time_s * 1.6 + (wuv.x + wuv.y) * 0.55 + wave * 4.0);
		float foam = shore * smoothstep(0.35, 0.85, surf) * (0.55 + 0.45 * wave);
		col = mix(col, vec3(0.86, 0.95, 1.0), clamp(foam * 0.55, 0.0, 0.7));
	} else {
		// ------------------------------------------------------------- land
		// Wind combing through grass: a travelling brightness ripple.
		vec2 wuv2 = wuv * 0.045 - wind * time_s * 0.07;
		float g = texture(noise_tex, wuv2).r;
		float g2 = texture(noise_tex, wuv * 0.13 - wind * time_s * 0.16).g;
		col *= 1.0 + ((g - 0.5) * 0.26 + (g2 - 0.5) * 0.12) * veg;
		// Snow and ice sparkle.
		if (icy > 0.5) {
			float sp = texture(noise_tex, wuv * 0.5 + vec2(time_s * 0.02, 0.0)).g;
			emis += vec3(0.55, 0.62, 0.72) * smoothstep(0.93, 1.0, sp) * 0.5 * day_factor;
		}
		// Rain darkens and saturates wet ground.
		col *= 1.0 - rain * 0.16;
	}

	// ----------------------------------------------------------------- lava
	if (lava > 0.5) {
		float p = texture(noise_tex, wuv * 0.06 + vec2(time_s * 0.02, time_s * 0.013)).r;
		float pulse = 0.55 + 0.45 * sin(time_s * 1.4 + p * 8.0);
		col = mix(col, vec3(0.98, 0.42, 0.10), 0.45 + 0.3 * pulse);
		emis += vec3(1.0, 0.45, 0.10) * (0.45 + 0.55 * pulse);
	}

	// ----------------------------------------------------------------- fire
	if (fire > 0.004) {
		float flick = 0.55 + 0.45 * sin(time_s * 13.0 + wuv.x * 2.7 + wuv.y * 1.9)
			* sin(time_s * 7.3 + wuv.y * 3.1);
		float f = clamp(fire, 0.0, 1.0);
		vec3 flame = mix(vec3(0.95, 0.32, 0.06), vec3(1.0, 0.86, 0.35), clamp(f * flick, 0.0, 1.0));
		col = mix(col, flame, clamp(f * 1.25, 0.0, 0.92));
		emis += flame * f * (0.55 + 0.45 * flick);
	}

	// -------------------------------------------------------- cloud shadows
	float cl = texture(noise_tex, wuv * 0.0055 + vec2(cloud_scroll * 0.013, cloud_scroll * 0.0075)).r;
	float shadow = smoothstep(0.52, 0.80, cl) * cloud_amount;
	col *= 1.0 - shadow * 0.30;

	// ------------------------------------------------------------ day/night
	vec3 lit = col * ambient_tint;
	// Emissive sources glow harder after dark.
	lit += emis * (0.7 + (1.0 - day_factor) * 1.3);

	// ------------------------------------------------------------- reveal
	if (reveal < 1.0) {
		float seed_n = texture(noise_tex, wuv * 0.019).r;
		// Contrast-stretched so the sweep actually crosses the noise's range
		// (simplex clusters around 0.5), and biased so coastlines surface
		// first — the island draws itself outline inwards.
		seed_n = clamp((seed_n - 0.5) * 1.9 + 0.5, 0.0, 1.0);
		seed_n = clamp(seed_n * 0.86 - shore * 0.14, 0.0, 1.0);
		float r = reveal * 1.18 - 0.09;
		float hidden = smoothstep(r, r + 0.16, seed_n);
		lit = mix(lit, vec3(0.0), hidden);
		// Bright leading edge where the world is materialising.
		float edge = exp(-abs(seed_n - r) * 34.0) * (1.0 - hidden * 0.4);
		lit += vec3(0.34, 0.66, 0.86) * edge * 1.1;
	}
	COLOR = vec4(lit, 1.0);
}
