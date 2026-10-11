shader_type spatial;
render_mode unshaded;

// A small procedural gas giant keeps the room self-contained without external textures.
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 sphere_normal = normalize(local_position);
	float turbulence = sin(sphere_normal.x * 17.0 + sphere_normal.z * 9.0) * 0.5;
	float bands = sin(sphere_normal.y * 42.0 + turbulence * 2.0);
	vec3 blue = vec3(0.12, 0.34, 0.49);
	vec3 pale = vec3(0.57, 0.78, 0.82);
	vec3 surface_color = mix(blue, pale, smoothstep(-0.8, 0.9, bands));
	float sunlight = max(dot(sphere_normal, normalize(vec3(-0.7, 0.4, 0.8))), 0.0);
	ALBEDO = surface_color * (0.07 + sunlight * 0.93);
}
