shader_type spatial;
render_mode unshaded, cull_disabled;

// Animated neon signage panel. Procedural glyph blocks, scanlines and flicker
// keep this cheap (one quad) while reading as a lit advertising display.
// night_factor dims emissive content by day; the dark panel stays visible.

uniform vec3 panel_color : source_color = vec3(0.05, 0.92, 1.0);
uniform vec3 accent_color : source_color = vec3(1.0, 0.10, 0.55);
uniform float seed = 0.0;
uniform float flicker = 0.10;
uniform float night_factor = 1.0;
uniform float glow_strength = 1.0;
// Distant skyline elements use a solid glow: fine glyph strokes alias away at
// 1+ km, leaving the tower unlit. Nearby signs keep the animated glyph grid.
uniform float solid_glow = 0.0;

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

	// Dark physical panel with a thin illuminated frame.
	float frame = step(0.012, uv.x) * step(uv.x, 0.988) * step(0.018, uv.y) * step(uv.y, 0.982);
	float inner = step(0.035, uv.x) * step(uv.x, 0.965) * step(0.055, uv.y) * step(uv.y, 0.945);

	// Procedural glyph grid: each cell is either lit or dark, with segment bars
	// so the silhouette reads as typography rather than random noise.
	float rows = 5.0;
	float cols = 9.0;
	float row = floor(uv.y * rows);
	float col = floor(uv.x * cols);
	vec2 cell = vec2(col, row);
	float r = hash21(cell + vec2(seed, seed * 1.73));
	float on = step(0.18, r);
	vec2 f = fract(vec2(uv.x * cols, uv.y * rows));
	float stroke = step(0.16, f.x) * step(f.x, 0.84) * step(0.16, f.y) * step(f.y, 0.84);
	float bar = step(0.26, f.y) * step(f.y, 0.40) + step(0.62, f.y) * step(f.y, 0.76);
	float glyph = on * max(stroke * step(0.48, r), bar * 0.72);

	float scan = 0.78 + 0.22 * sin(uv.y * 210.0 - TIME * 6.5);
	float fl = 1.0 - flicker * step(0.945, hash21(cell + floor(TIME * 7.0)));
	vec3 tint = mix(panel_color, accent_color, step(0.84, r));

	vec3 backing = vec3(0.055, 0.062, 0.070);
	float pattern = mix(glyph, 1.0, clamp(solid_glow, 0.0, 1.0));
	// Push glyph luminance above 1.0 so the scene's glow/bloom picks it up.
	vec3 glow = tint * pattern * scan * fl * inner * glow_strength * 2.4;
	vec3 border = tint * (frame - inner) * 1.1 * glow_strength;
	// Emissive content is night-only. The previous 0.18 daylight floor left a
	// visibly lit cyan/green rectangle on every dressed tower at midday.
	vec3 col3 = mix(backing, backing + glow + border, night_factor);
	ALBEDO = col3;
	ALPHA = 1.0;
}
