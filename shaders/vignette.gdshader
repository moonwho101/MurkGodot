// Copyright (c) Mark Longo 2026
// Screen vignette (transparent centre, dark edges) with an optional red hit flash.
shader_type canvas_item;

uniform float flash = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p) / 1.4142;
	float v = smoothstep(0.45, 0.8, r) * 0.55 + smoothstep(0.8, 1.0, r) * 0.37;
	float f = smoothstep(0.3, 1.0, r) * 0.55 * flash;
	// Black vignette composited under a red flash into a single layer.
	float a = 1.0 - (1.0 - v) * (1.0 - f);
	vec3 rgb = a > 0.0001 ? vec3(0.8, 0.0, 0.0) * f / a : vec3(0.0);
	COLOR = vec4(rgb, a);
}
