shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D facade_texture : hint_albedo;
uniform vec4 facade_tint : hint_color = vec4(1.0);
uniform vec4 roof_color : hint_color = vec4(0.17, 0.15, 0.14, 1.0);
uniform float horizontal_scale = 0.055;
uniform float vertical_scale = 0.031;
uniform float horizontal_offset = 0.0;

varying vec3 world_vertex;
varying vec3 world_surface_normal;

void vertex() {
	world_vertex = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_surface_normal = normalize(mat3(WORLD_MATRIX) * NORMAL);
}

void fragment() {
	vec3 axis_weight = abs(normalize(world_surface_normal));
	float horizontal_position = axis_weight.x > axis_weight.z
		? world_vertex.z
		: world_vertex.x;
	vec2 facade_uv = vec2(
		horizontal_position * horizontal_scale + horizontal_offset,
		world_vertex.y * vertical_scale
	);
	vec3 facade_albedo = texture(facade_texture, facade_uv).rgb * facade_tint.rgb;
	float roof_factor = smoothstep(0.55, 0.80, axis_weight.y);

	ALBEDO = mix(facade_albedo, roof_color.rgb, roof_factor);
	ROUGHNESS = mix(0.78, 0.94, roof_factor);
	METALLIC = 0.0;
}
