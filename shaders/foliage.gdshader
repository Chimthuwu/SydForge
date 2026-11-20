shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Foliage for the shared MultiMesh canopy. Vertex colour carries the
// up-facing brightness gradient; the MultiMesh instance colour carries the
// per-tree green. The fragment layer adds broken tonal clusters and a little
// leaf backlight without any texture fetches.

varying vec3 world_position;
varying vec3 leaf_tint;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	leaf_tint = COLOR.rgb;
}

void fragment() {
	vec3 tint = leaf_tint;
	float grain = hash21(floor(world_position.xz * 8.0 + world_position.y * 5.0));
	float clusters = sin(world_position.x * 2.9 + world_position.z * 2.1)
		* sin(world_position.y * 3.7 + world_position.x * 1.3) * 0.5 + 0.5;
	vec3 color = tint * (0.84 + grain * 0.24);
	color = mix(color, color * vec3(0.78, 1.03, 0.80), clusters * 0.2);
	color *= 0.95 + smoothstep(0.0, 8.0, world_position.y) * 0.08;

	ALBEDO = color;
	ROUGHNESS = 0.91;
	SPECULAR = 0.2;
	BACKLIGHT = color * vec3(0.13, 0.18, 0.09);
	NORMAL = normalize(NORMAL + vec3(
		sin(world_position.x * 4.1 + world_position.y * 3.0),
		cos(world_position.z * 3.7),
		sin(world_position.z * 2.9 + world_position.y * 1.7)
	) * 0.11);
}
