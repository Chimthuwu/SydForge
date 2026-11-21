shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Architectural facade shader for the vertical-slice upgrade.
// Replaces the purely procedural window grid with a material system that
// distinguishes wall / glass / frame / trim via vertex-colour channels:
//   R,G,B = base tint; A encodes material family:
//     0.10-0.19 = glass curtain wall
//     0.30-0.39 = structural frame / mullion
//     0.50-0.59 = stone / masonry
//     0.70-0.79 = metal trim / equipment
//     0.90-0.99 = concrete / parapet
//
// The geometry already contains real window bays and fins, so this shader only
// supplies surface variation and selective night emission — no fake windows.

uniform float night_factor = 0.0;
uniform float wetness = 0.0;
uniform vec3 lit_warm : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 lit_cool : source_color = vec3(0.62, 0.82, 1.0);
uniform vec3 neon_cyan : source_color = vec3(0.10, 0.90, 1.0);

varying vec3 v_world;
varying vec3 v_normal;
varying vec4 v_color;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR;
}

void fragment() {
	float family = v_color.a;
	bool glass = family < 0.20;
	bool frame = family >= 0.30 && family < 0.40;
	bool stone = family >= 0.50 && family < 0.60;
	bool metal = family >= 0.70 && family < 0.80;
	bool concrete = family >= 0.90;

	vec3 base = v_color.rgb;

	// Surface variation keyed to world space, with distance fade so fine grain
	// does not alias at the long-range harbour viewpoints.
	float dist = distance(v_world, CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(160.0, 600.0, dist);
	float grain = hash21(floor(v_world.xz * 4.0 + v_world.y * 0.5));
	if (stone) {
		base *= 0.90 + grain * 0.16 * detail;
		// Weather streaks below window sills.
		float streak = hash21(vec2(floor(v_world.x * 1.4), 7.0));
		base *= 1.0 - smoothstep(0.7, 1.0, streak) * 0.12;
	} else if (concrete) {
		base *= 0.94 + grain * 0.10 * detail;
	} else if (metal) {
		base *= 0.90 + grain * 0.18 * detail;
	}

	// Walls darken at night; glazing remains dark but lit bays emit.
	vec3 color = base * mix(1.0, 0.82, night_factor);
	float emission = 0.0;
	vec3 emit_color = lit_warm;
	if (glass) {
		// Glazing stays dark by day; only a minority of bays emit at night.
		float cell = hash21(floor(v_world.xz * 0.7 + vec2(v_world.y * 0.15, 0.0)));
		bool lit = cell > 0.48;
		emit_color = mix(lit_warm, lit_cool, step(0.86, cell));
		emission = mix(0.0, 0.95, float(lit));
		color = base * 0.48;
	} else if (frame && night_factor > 0.3) {
		// Selective architectural edge lighting on structural fins.
		emit_color = neon_cyan;
		emission = step(0.82, hash21(floor(v_world.xz * 0.06))) * 0.32;
	}

	float wet = clamp(wetness, 0.0, 1.0);
	color = mix(color, color * 0.78, wet * 0.5);
	ALBEDO = color;
	float dry_rough = mix(0.88, 0.22, float(glass));
	ROUGHNESS = mix(dry_rough, 0.20, wet * 0.6);
	METALLIC = mix(mix(0.0, 0.55, float(metal)), 0.32, float(glass));
	SPECULAR = mix(0.18, 0.7, wet * 0.7);
	EMISSION = emit_color * emission * night_factor;
}
