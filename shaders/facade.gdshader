shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Procedural facade detail for the merged Sydney building mesh. The mesh stays
// footprint-exact and inexpensive; this layer supplies punched windows, frames,
// sills, shopfronts, curtain-wall mullions and lit windows at night.
//
// Vertex colour supplies the per-building wall tint. Its alpha marks the
// facade family: < 0.35 is a glass curtain wall, everything else is masonry.

uniform float night_factor = 0.0;
uniform vec3 lit_color : source_color = vec3(1.0, 0.70, 0.38);
uniform vec3 cool_lit_color : source_color = vec3(0.72, 0.84, 1.0);
uniform float lit_chance = 0.16;

varying vec3 world_position;
varying vec3 world_normal;
varying vec4 vertex_color;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vertex_color = COLOR;
}

void fragment() {
	vec3 wall = vertex_color.rgb;
	float family = vertex_color.a;
	vec3 normal = normalize(world_normal);
	bool roof = abs(normal.y) > 0.55;

	vec2 uv = abs(normal.x) > abs(normal.z)
		? vec2(world_position.z, world_position.y)
		: vec2(world_position.x, world_position.y);

	float floor_height = 3.35;
	float row = floor(uv.y / floor_height);
	float fy = fract(uv.y / floor_height);
	float cell_width = family < 0.35 ? 1.55 : 2.65;
	float cell = floor(uv.x / cell_width);
	float cx = fract(uv.x / cell_width);
	float window_random = hash21(vec2(cell, row));
	float window_glass = 0.0;
	float frame = 0.0;
	float shop = 0.0;

	if (!roof) {
		if (family < 0.35) {
			// Curtain wall: continuous glazing with vertical and floor mullions.
			float gx = smoothstep(0.045, 0.085, cx) * smoothstep(0.955, 0.915, cx);
			float gy = smoothstep(0.10, 0.15, fy) * smoothstep(0.94, 0.89, fy);
			window_glass = gx * gy;
			frame = clamp(gx * gy * 0.0 + (1.0 - gx) * gy, 0.0, 1.0) * 0.6;
		} else if (uv.y < 4.5) {
			// Street level: broad shop glazing and an awning/fascia band.
			float gx = smoothstep(0.055, 0.10, cx) * smoothstep(0.945, 0.90, cx);
			float gy = smoothstep(0.10, 0.16, fy) * smoothstep(0.70, 0.63, fy);
			shop = gx * gy;
			window_glass = shop;
			float awning = smoothstep(0.73, 0.76, fy) * smoothstep(0.86, 0.82, fy);
			frame = max(frame, awning);
		} else {
			// Punched windows: glass with a proud frame and a sill shadow.
			float gx = smoothstep(0.20, 0.235, cx) * smoothstep(0.80, 0.765, cx);
			float gy = smoothstep(0.24, 0.275, fy) * smoothstep(0.82, 0.785, fy);
			window_glass = gx * gy;
			float outer_x = smoothstep(0.145, 0.18, cx) * smoothstep(0.855, 0.82, cx);
			float outer_y = smoothstep(0.185, 0.22, fy) * smoothstep(0.875, 0.84, fy);
			frame = clamp(outer_x * outer_y - window_glass, 0.0, 1.0);
			frame += smoothstep(0.145, 0.18, fy) * smoothstep(0.22, 0.19, fy) * 0.5;
		}
	}

	// Weathering: restrained grain, dirt streaks and a darker base course.
	float grain = hash21(floor(uv * vec2(2.4, 3.2)));
	float streak = hash21(vec2(floor(uv.x * 1.7), 9.0));
	vec3 base = wall * (0.86 + grain * 0.16);
	base *= 1.0 - streak * 0.055;
	base *= 0.92 + smoothstep(0.0, 1.2, uv.y) * 0.08;
	base *= 0.94 + smoothstep(0.0, 1.0, fy) * 0.06;

	// Glass reflects a cool sky and is much darker than the masonry.
	vec3 sky_reflection = mix(vec3(0.05, 0.075, 0.095), vec3(0.30, 0.42, 0.50),
		clamp(normal.y * 0.5 + 0.5, 0.0, 1.0));
	vec3 glass = mix(vec3(0.035, 0.055, 0.070), sky_reflection, 0.45);
	float lit_roll = hash21(vec2(cell + 31.0, row + 7.0));
	bool lit = lit_roll > (1.0 - lit_chance);
	vec3 lit_tint = mix(lit_color, cool_lit_color, step(0.86, lit_roll));
	// Most occupied rooms read as a warm interior, not a white neon square.
	float glow = lit ? (0.16 + hash21(vec2(cell, row + 13.0)) * 0.24) : 0.02;

	vec3 color = mix(base, glass, window_glass);
	color = mix(color, base * 1.06 + vec3(0.02), frame * (1.0 - window_glass) * 0.85);
	// Ground-floor interiors read warm even before streetlights come on.
	color = mix(color, vec3(0.09, 0.075, 0.055), shop * 0.35);

	ALBEDO = color;
	ROUGHNESS = mix(0.92, 0.16, window_glass);
	METALLIC = mix(0.0, 0.42, window_glass);
	SPECULAR = mix(0.25, 0.6, window_glass);

	float emission_strength = night_factor * window_glass * glow;
	// Shopfronts stay brighter than offices but below a blown-out glow.
	emission_strength *= mix(1.0, 1.35, shop);
	EMISSION = lit_tint * emission_strength * 0.62;
}
