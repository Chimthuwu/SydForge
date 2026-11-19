shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Phase 6A harbour water: deep blue with slow, subtle wave shading.
// Deliberately restrained — no transparency, no scrolling textures, no
// screen-space reflections. Two slow crossing wave trains tilt the up-normal
// a few degrees so the sun glint and sky ambient break gently across the
// surface. Vertex colours carry the patchy brightness variation.

uniform vec3 water_color : source_color = vec3(0.118, 0.337, 0.471); // #1e5678 deep harbour blue
uniform float water_roughness : hint_range(0.05, 1.0) = 0.38;
uniform float water_specular : hint_range(0.0, 1.0) = 0.32;
uniform float wave_strength : hint_range(0.0, 0.3) = 0.07;
uniform float wave_scale : hint_range(0.01, 0.5) = 0.06;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.45;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	float w1 = sin(world_pos.x * wave_scale * 2.0 + t * 1.1)
			+ sin(world_pos.z * wave_scale * 1.35 - t * 0.8);
	float w2 = sin((world_pos.x + world_pos.z) * wave_scale * 0.8 + t * 0.6);
	vec2 slope = vec2(w1 * 0.5 + w2 * 0.35, w2 * 0.5 - w1 * 0.25) * wave_strength;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = water_color * COLOR.rgb;
	METALLIC = 0.0;
	ROUGHNESS = water_roughness;
	SPECULAR = water_specular;
}
