shader_type canvas_item;
// Sniper scope overlay: blacks out everything outside a circular lens,
// draws a dark lens ring and a thin crosshair with a center gap.

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 center = res * 0.5;
	float dist = distance(FRAGCOORD.xy, center);
	float r = res.y * 0.43;

	float outside = smoothstep(r, r + 1.5, dist);
	float ring = (1.0 - smoothstep(r - 6.0, r - 3.0, dist)) * smoothstep(r - 10.0, r - 6.0, dist);

	float cross = 0.0;
	if (dist < r - 3.0 && dist > 7.0) {
		if (abs(FRAGCOORD.x - center.x) < 1.0) cross = 1.0;
		if (abs(FRAGCOORD.y - center.y) < 1.0) cross = 1.0;
	}

	float alpha = outside;
	if (ring > 0.5) alpha = 1.0;
	if (cross > 0.5) alpha = 1.0;
	COLOR = vec4(vec3(0.0), alpha);
}
