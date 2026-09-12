shader_type canvas_item;
render_mode unshaded, blend_mul;

// Multiplied over the frame: vignette plus a night-time cool shift. Keeps the
// eye on the middle of the screen without touching the pixel art itself.

uniform float vignette : hint_range(0.0, 1.0) = 0.45;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 night_tint : source_color = vec3(0.80, 0.86, 1.05);
uniform float storm : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d * vec2(1.05, 0.82)) * 1.42;
	float v = 1.0 - smoothstep(0.52, 1.15, r) * vignette;
	vec3 tint = mix(vec3(1.0), night_tint, night * 0.55);
	tint *= 1.0 - storm * 0.12;
	COLOR = vec4(tint * v, 1.0);
}
