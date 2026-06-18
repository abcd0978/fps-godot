shader_type canvas_item;
// Damage feedback: red vignette at screen edges on any hit, plus a stronger
// red arc on the side the damage came from. Driven by uniforms that the HUD
// pulses to 1 on hit and decays toward 0.

uniform float intensity = 0.0;       // overall hit flash
uniform float dir = 0.0;             // hit direction (radians, 0 = front/top)
uniform float dir_intensity = 0.0;   // directional arc strength

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 c = res * 0.5;
	vec2 d = FRAGCOORD.xy - c;
	float dist = length(d) / length(c);          // 0 center .. ~1 corner

	float vig = smoothstep(0.55, 1.0, dist) * intensity;

	float pa = atan(d.x, -d.y);                   // pixel angle: top = 0, right = +
	float adiff = abs(atan(sin(pa - dir), cos(pa - dir)));
	float arc = (1.0 - smoothstep(0.0, 1.1, adiff)) * smoothstep(0.35, 1.0, dist) * dir_intensity;

	float a = clamp(max(vig, arc), 0.0, 1.0);
	COLOR = vec4(0.85, 0.0, 0.0, a);
}
