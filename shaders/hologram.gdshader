shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Translucent holographic advertisement / wayfinding display. Additive,
// scan-lined and gently flickering; no shadow cost, no dynamic lights.

uniform vec3 holo_color : source_color = vec3(0.15, 0.85, 1.0);
uniform float seed = 0.0;
uniform float night_factor = 1.0;
uniform float alpha_strength = 0.42;

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
	float edge = smoothstep(0.0, 0.06, uv.x) * smoothstep(1.0, 0.94, uv.x)
		* smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.94, uv.y);

	float rows = 8.0;
	float row = floor(uv.y * rows);
	float col = floor(uv.x * 11.0);
	float r = hash21(vec2(col, row) + vec2(seed));
	float glyph = step(0.55, r) * step(0.2, fract(uv.y * rows)) * step(fract(uv.y * rows), 0.8);
	float scan = 0.55 + 0.45 * sin(uv.y * 260.0 - TIME * 9.0);
	float sweep = smoothstep(0.06, 0.0, abs(fract(uv.y * 0.5 - TIME * 0.14) - 0.5));
	float flick = 1.0 - 0.18 * step(0.96, hash21(vec2(floor(TIME * 8.0), seed)));

	float a = edge * (glyph * scan + 0.12 + sweep * 0.4) * flick * alpha_strength * (0.06 + 0.94 * night_factor);
	ALBEDO = holo_color * (0.8 + glyph * 0.6 + sweep * 0.5);
	ALPHA = clamp(a, 0.0, 1.0);
}
