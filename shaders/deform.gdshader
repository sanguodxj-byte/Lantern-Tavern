shader_type spatial;

uniform sampler2D albedo_texture : filter_nearest;
uniform sampler2D noise_texture : repeat_enable;
uniform float noise_scale : hint_range(0.01, 1.0) = 0.1;
uniform float damage_amount : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	float noise_value = texture(noise_texture, VERTEX.xy * noise_scale).r - 0.5;
	VERTEX += vec3(noise_value) * damage_amount;
}

void fragment() {
	vec3 tex_color = texture(albedo_texture, UV).rgb;
	ALBEDO = tex_color * (1.0 - damage_amount);
}
