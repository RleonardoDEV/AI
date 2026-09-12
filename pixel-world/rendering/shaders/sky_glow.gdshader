shader_type canvas_item;
render_mode unshaded, blend_add;

// Added on top of the frame: rain sheets, drifting snow, lightning flash and
// a warm bloom near sunrise/sunset. Screen-space, so it costs one pass no
// matter how heavy the weather is.

uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float time_s = 0.0;
uniform vec2 wind = vec2(0.2, 0.0);
uniform float golden : hint_range(0.0, 1.0) = 0.0;
uniform vec3 golden_color : source_color = vec3(1.0, 0.62, 0.30);
uniform float aspect = 0.5625;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 col = vec3(0.0);
	vec2 uv = UV;

	// --- Rain: layered diagonal sheets -----------------------------------
	if (rain > 0.01) {
		vec2 dir = normalize(vec2(wind.x * 1.4 + 0.18, 1.0));
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float scale = 90.0 + fi * 55.0;
			float speed = 1.6 + fi * 0.7;
			vec2 p = uv * vec2(aspect, 1.0) * scale;
			p -= dir * time_s * speed * scale * 0.05;
			vec2 cell = floor(p);
			float h = hash(cell + fi * 17.0);
			// Thin streaks: only a few cells per row carry a drop.
			float streak = step(0.965 - rain * 0.045, h);
			vec2 f = fract(p);
			float line = smoothstep(0.5, 0.0, abs(f.x - 0.5) * 6.0)
				* smoothstep(0.0, 0.45, f.y) * smoothstep(1.0, 0.55, f.y);
			col += vec3(0.42, 0.55, 0.72) * streak * line * rain * (0.22 - fi * 0.05);
		}
	}

	// --- Snow: slow drifting specks --------------------------------------
	if (snow > 0.01) {
		for (int i = 0; i < 2; i++) {
			float fi = float(i);
			float scale = 55.0 + fi * 48.0;
			vec2 p = uv * vec2(aspect, 1.0) * scale;
			p.y -= time_s * (0.35 + fi * 0.25) * scale * 0.04;
			p.x += sin(time_s * 0.5 + fi * 2.0 + uv.y * 6.0) * 0.8 + wind.x * time_s * 2.0;
			vec2 cell = floor(p);
			float h = hash(cell + fi * 31.0);
			float flake = step(0.982 - snow * 0.02, h);
			vec2 f = fract(p) - 0.5;
			float dot_a = smoothstep(0.34, 0.0, length(f));
			col += vec3(0.92, 0.95, 1.0) * flake * dot_a * snow * 0.55;
		}
	}

	// --- Golden hour bloom from the horizon ------------------------------
	if (golden > 0.01) {
		float band = smoothstep(0.65, 0.0, uv.y) * 0.6 + smoothstep(0.4, 1.0, uv.y) * 0.25;
		col += golden_color * band * golden * 0.16;
	}

	// --- Lightning / impact flash ----------------------------------------
	col += flash_color * flash * 0.55;

	COLOR = vec4(col, 1.0);
}
