shader_type canvas_item;

uniform float blur_size : hint_range(0.0, 16.0) = 6.0;

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE * blur_size;
	vec4 color = texture(TEXTURE, UV);
	color += texture(TEXTURE, UV + vec2(ps.x, 0.0));
	color += texture(TEXTURE, UV - vec2(ps.x, 0.0));
	color += texture(TEXTURE, UV + vec2(0.0, ps.y));
	color += texture(TEXTURE, UV - vec2(0.0, ps.y));
	color += texture(TEXTURE, UV + vec2(ps.x, ps.y));
	color += texture(TEXTURE, UV - vec2(ps.x, ps.y));
	color += texture(TEXTURE, UV + vec2(ps.x, -ps.y));
	color += texture(TEXTURE, UV - vec2(ps.x, -ps.y));
	color /= 9.0;
	COLOR = vec4(color.rgb, 0.7);
}
