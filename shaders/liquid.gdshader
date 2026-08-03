shader_type spatial;

uniform sampler2D liquid_texture : filter_nearest, repeat_enable;
// 注意：hint_range 仅支持 float/int uniform，vec2 滚动速度不支持范围提示。
uniform vec2 texture_scroll_speed = vec2(0.05, 0.03);
uniform float wave_amplitude : hint_range(0.01, 1.0) = 0.2;
uniform float wave_frequency : hint_range(0.05, 2.0) = 0.15;
uniform float wave_speed : hint_range(0.1, 5.0) = 1.0;
uniform vec4 liquid_color : source_color = vec4(0.03, 0.68, 0.025, 1.0);
uniform float texture_blend : hint_range(0.0, 1.0, 0.05) = 0.25;

void vertex() {
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave1 = sin(world_vertex.x * wave_frequency + TIME * wave_speed);
	float wave2 = cos(world_vertex.z * wave_frequency * 0.8 + TIME * wave_speed * 1.2);
	VERTEX.y = wave_amplitude * (wave1 + wave2);
}

void fragment() {
	vec4 tex_color = texture(liquid_texture, UV + TIME * texture_scroll_speed);
	vec3 acid_color = liquid_color.rgb;
	ALBEDO = acid_color * mix(vec3(1.0), tex_color.rgb, texture_blend);
	EMISSION = vec3(0.0);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
}
