shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Coarse, weathered asphalt / concrete. Breaks up the flat single-colour road
// ribbons with aggregate noise, patches and subtle damp variation.

uniform vec3 base_color : source_color = vec3(0.115, 0.125, 0.135);
uniform float roughness_base = 0.86;
uniform float patch_strength = 0.18;
uniform float wetness = 0.0;

varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float aggregate = hash21(floor(world_position.xz * 6.0));
	float fine = hash21(floor(world_position.xz * 22.0));
	float patch = hash21(floor(world_position.xz * 0.09));
	vec3 color = base_color;
	color *= 0.82 + aggregate * 0.26;
	color *= 1.0 - fine * 0.05;
	color *= mix(1.0 - patch_strength, 1.0 + patch_strength, patch);
	color *= 0.95 + smoothstep(-2.0, 40.0, world_position.y) * 0.05;
	// Wet road response: darkened surface, water pooling in micro-depressions
	float puddles = smoothstep(0.45, 0.75, hash21(floor(world_position.xz * 0.35)));
	float wet_factor = clamp(wetness, 0.0, 1.0);
	color = mix(color, color * 0.52, wet_factor * 0.75);
	ALBEDO = color;
	float dry_roughness = clamp(roughness_base + aggregate * 0.09 - patch * 0.07, 0.55, 1.0);
	ROUGHNESS = mix(dry_roughness, mix(0.24, 0.08, puddles), wet_factor * 0.9);
	SPECULAR = mix(mix(0.20, 0.45, patch), 0.85, wet_factor * 0.8);
}
