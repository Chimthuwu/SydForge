shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float wave = sin(uv.y * 24.0 + TIME * 2.7) * 0.006
		+ sin(uv.x * 15.0 - TIME * 1.9) * 0.004;
	vec2 warped = uv + vec2(wave, wave * 0.55) * intensity;
	float aberration = 0.0045 * intensity;
	vec3 color;
	color.r = texture(screen_texture, warped + vec2(aberration, 0.0)).r;
	color.g = texture(screen_texture, warped).g;
	color.b = texture(screen_texture, warped - vec2(aberration, 0.0)).b;
	float hue_cycle = 0.5 + 0.5 * sin(TIME * 1.35 + uv.y * 5.0);
	color = mix(color, color.gbr, 0.20 * intensity * hue_cycle);
	color *= 1.0 + 0.10 * sin(TIME * 3.6) * intensity;
	float vignette = smoothstep(0.92, 0.22, length(uv - vec2(0.5)));
	color *= mix(1.0, vignette, 0.38 * intensity);
	COLOR = vec4(color, 1.0);
}
