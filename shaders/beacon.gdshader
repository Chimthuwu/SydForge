shader_type spatial;
render_mode unshaded, cull_disabled;

// Cheap aircraft-warning / tower beacon. A shared material drives every roof
// light; TIME supplies the pulse so there is no per-node animation cost.

uniform vec3 beacon_color : source_color = vec3(1.0, 0.22, 0.18);
uniform float rate = 1.4;
uniform float night_factor = 1.0;

void fragment() {
	float pulse = pow(max(0.0, sin(TIME * rate)), 10.0);
	ALBEDO = beacon_color * (0.12 + pulse * 3.2) * (0.25 + 0.75 * night_factor);
	ALPHA = 1.0;
}
