// Copyright (c) Mark Longo 2026
// Flickering torch light around the hero: warm near the light, cool and dark further out.
shader_type canvas_item;

uniform vec2 light_pos = vec2(0.0);
uniform float radius = 300.0;
uniform float ambient = 0.36;

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	vec2 d = world_pos - light_pos;
	d.y *= 2.0;
	float r = radius * (1.0 + 0.035 * sin(TIME * 7.0) + 0.02 * sin(TIME * 13.0 + 1.3));
	float f = clamp(1.0 - length(d) / r, 0.0, 1.0);
	f = f * f * (3.0 - 2.0 * f);
	vec3 cool = vec3(0.62, 0.68, 1.0) * ambient;
	vec3 warm = vec3(1.12, 0.96, 0.78);
	vec3 lit = mix(cool, warm, f);
	COLOR = vec4(c.rgb * lit, c.a);
}
