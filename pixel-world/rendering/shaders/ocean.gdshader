shader_type canvas_item;
render_mode unshaded;

// Endless ocean backdrop behind the world sprite. Sampled in *world* cell
// space so its swell lines up with the terrain's own water, which makes the
// island read as part of a larger sea rather than a floating rectangle.

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec2 world_origin = vec2(0.0);
uniform vec2 backdrop_size = vec2(1024.0);
uniform float time_s = 0.0;
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform vec3 ambient_tint : source_color = vec3(1.0);
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_scroll = 0.0;
uniform vec3 deep_color : source_color = vec3(0.035, 0.078, 0.16);
uniform vec3 abyss_color : source_color = vec3(0.012, 0.024, 0.055);
uniform vec2 world_center = vec2(128.0, 128.0);
uniform float world_radius = 190.0;

void fragment() {
	vec2 wuv = world_origin + UV * backdrop_size;
	float n1 = texture(noise_tex, wuv * 0.018 + vec2(time_s * 0.010, time_s * 0.006)).r;
	float n2 = texture(noise_tex, wuv * 0.042 - vec2(time_s * 0.015, time_s * 0.009)).g;
	float wave = n1 * 0.6 + n2 * 0.4;

	// Fade to abyss away from the landmass: keeps focus on the world.
	float d = length((wuv - world_center) / world_radius);
	vec3 col = mix(deep_color, abyss_color, clamp((d - 0.55) * 1.15, 0.0, 1.0));
	col += vec3(0.022, 0.05, 0.075) * (wave - 0.5) * 2.0;

	float glint = smoothstep(0.80, 0.96, wave)
		* (0.5 + 0.5 * sin(time_s * 1.9 + wuv.x * 0.7));
	vec3 emis = vec3(0.22, 0.34, 0.46) * glint * 0.22 * day_factor;

	float cl = texture(noise_tex, wuv * 0.0055 + vec2(cloud_scroll * 0.013, cloud_scroll * 0.0075)).r;
	col *= 1.0 - smoothstep(0.52, 0.80, cl) * cloud_amount * 0.35;

	COLOR = vec4(col * ambient_tint + emis * (0.7 + (1.0 - day_factor) * 1.2), 1.0);
}
