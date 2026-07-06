shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 atlas_region_tiles = vec4(0.0, 0.0, 32.0, 8.0);
uniform float meters_per_tile = 1.0;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float material_roughness = 0.85;
uniform float material_metallic = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 sample_atlas(vec2 meter_coord) {
	vec2 scaled = meter_coord / max(meters_per_tile, 0.0001);
	vec2 region_size = max(atlas_region_tiles.zw, vec2(1.0, 1.0));
	vec2 tile = mod(floor(scaled), region_size);
	tile = mod(tile + region_size, region_size);
	vec2 tile_uv = clamp(fract(scaled), vec2(0.015625), vec2(0.984375));
	vec2 atlas_uv = (atlas_region_tiles.xy + tile + tile_uv) / vec2(32.0, 32.0);
	return texture(atlas_texture, atlas_uv);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 blend = pow(abs(n), vec3(4.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);

	vec4 x_sample = sample_atlas(world_pos.zy);
	vec4 y_sample = sample_atlas(world_pos.xz);
	vec4 z_sample = sample_atlas(world_pos.xy);
	vec4 atlas_color = x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;

	ALBEDO = (atlas_color * albedo_tint).rgb;
	ROUGHNESS = material_roughness;
	METALLIC = material_metallic;
}
