shader_type spatial;
render_mode unshaded, cull_disabled;

// Large facade-integrated architectural lighting panel. Unlike the small neon
// sign shader this covers a whole tower face with structural mullions, floor
// bands and lit glazing, so it reads as a building silhouette from the harbour
// instead of a floating rectangle.
//
// Light bands are deliberate architecture, not random glyph noise.

uniform vec3 shell_color : source_color = vec3(0.035, 0.055, 0.075);
uniform vec3 light_color : source_color = vec3(0.10, 0.85, 1.0);
uniform float rows = 18.0;
uniform float cols = 9.0;
uniform float lit_ratio = 0.72;
uniform float band_mode = 0.0;
uniform float night_factor = 1.0;
uniform float seed = 0.0;

varying vec2 v_uv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;
	float row = floor(uv.y * rows);
	float col = floor(uv.x * cols);
	vec2 f = fract(vec2(uv.x * cols, uv.y * rows));

	// Mullions: narrow dark structural lines between glazing bays.
	float pane = smoothstep(0.08, 0.16, f.x) * smoothstep(0.92, 0.84, f.x)
		* smoothstep(0.18, 0.28, f.y) * smoothstep(0.90, 0.80, f.y);

	float r = hash21(vec2(col, row) + vec2(seed));
	float lit = step(1.0 - lit_ratio, r);

	// Band variant: entire floor strips lit as a corporate light band.
	float band = step(0.62, hash21(vec2(row, seed + 3.0))) * step(0.2, f.y) * step(f.y, 0.85);
	float emissive = mix(lit * pane, max(pane * 0.25, band), band_mode);

	float scan = 0.86 + 0.14 * sin(uv.y * 90.0 - TIME * 2.0);
	vec3 shell = shell_color * (0.55 + 0.45 * (1.0 - night_factor));
	vec3 glow = light_color * emissive * scan * 3.2 * night_factor;
	ALBEDO = shell + glow;
}
