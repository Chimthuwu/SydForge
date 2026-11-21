shader_type canvas_item;
render_mode unshaded;

// NOS tunnel-vision: radial chromatic separation, peripheral warp, speed
// streaks and ghosting. One full-screen pass, driven by a single uniform.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float intensity = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5);
	vec2 dir = uv - center;
	float r = length(dir);
	float amt = clamp(intensity, 0.0, 1.0);

	// Radial warp pushes sampling outward toward the edges.
	vec2 warped = center + dir * (1.0 - amt * 0.12 * r * r);

	// Chromatic aberration grows toward the periphery.
	float sep = amt * (0.002 + r * r * 0.012);
	vec2 ox = normalize(dir + vec2(0.0001)) * sep;
	float cr = texture(screen_tex, warped + ox).r;
	float cg = texture(screen_tex, warped).g;
	float cb = texture(screen_tex, warped - ox).b;
	vec3 col = vec3(cr, cg, cb);

	// Speed streaks: angular noise stretched radially.
	float ang = atan(dir.y, dir.x);
	float streak = sin(ang * 90.0 + r * 40.0) * 0.5 + 0.5;
	streak = pow(streak, 18.0) * smoothstep(0.2, 0.9, r);
	col += vec3(0.55, 0.78, 1.0) * streak * amt * 0.28;

	// Subtle ghosting from a slightly lagged sample.
	vec3 ghost = texture(screen_tex, warped - dir * amt * 0.012).rgb;
	col = mix(col, ghost, amt * 0.16);

	// Vignette tunnel, restrained so the road stays readable.
	float vign = smoothstep(0.35, 0.95, r) * amt * 0.42;
	col *= 1.0 - vign;
	col += vec3(0.10, 0.30, 0.45) * vign * 0.5;

	// Activation pulse.
	col += vec3(0.35, 0.65, 0.95) * pulse * 0.10;

	COLOR = vec4(col, 1.0);
}
