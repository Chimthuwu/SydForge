shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Ground cover for the OSM park polygons. The mesh is one flat triangulated
// plane per park, so all variation has to come from the material: broad clumps,
// mowing bands, dry patches and a low-amplitude world-space bump.

uniform vec3 grass_deep : source_color = vec3(0.035, 0.105, 0.020);
uniform vec3 grass_light : source_color = vec3(0.080, 0.255, 0.045);
uniform vec3 grass_dry : source_color = vec3(0.225, 0.205, 0.075);

varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.0, 9.0);
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float broad = fbm(p * 0.032);
	float clump = fbm(p * 0.21 + vec2(19.0, 7.0));
	float fine = hash21(floor(p * 5.0));
	float dry = smoothstep(0.61, 0.86, fbm(p * 0.055 + vec2(43.0, 11.0)));

	vec3 color = mix(grass_deep, grass_light, clamp(broad * 0.62 + clump * 0.30 + 0.08, 0.0, 1.0));
	color = mix(color, grass_dry, dry * 0.34);
	color *= 0.87 + fine * 0.22;
	// Broad mowing bands, deliberately soft so they do not look like stripes.
	float mow = sin(p.x * 0.16 + value_noise(p * 0.018) * 5.0) * 0.5 + 0.5;
	color *= 0.95 + mow * 0.075;
	color *= 0.79 + smoothstep(0.14, 0.86, clump) * 0.27;
	// Closer to the camera, individual blade-scale speckle breaks up the plane.
	float near_fade = 1.0 - smoothstep(18.0, 80.0, distance(world_position, CAMERA_POSITION_WORLD));
	color *= 1.0 + (hash21(floor(p * 13.0)) - 0.5) * 0.22 * near_fade;

	ALBEDO = color;
	ROUGHNESS = 0.99;
	SPECULAR = 0.10;
	AO = 0.66 + clump * 0.34;

	// Cheap world-space relief: low-frequency clump normals rather than a
	// normal map, so the 5 km park mesh needs no extra texture memory.
	vec3 bump = normalize(vec3(
		(fbm(p * 0.48 + vec2(3.0, 8.0)) - 0.5) * 0.34,
		1.0,
		(fbm(p * 0.48 + vec2(27.0, 2.0)) - 0.5) * 0.34
	));
	NORMAL = normalize((VIEW_MATRIX * vec4(bump, 0.0)).xyz);
}
