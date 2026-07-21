shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 atlas_region_tiles = vec4(0.0, 0.0, 32.0, 8.0);
uniform float meters_per_tile = 1.0;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float material_roughness = 0.85;
uniform float material_metallic = 0.0;
// Subtle deterministic variation keeps the pixel atlas crisp while breaking up large repeated surfaces.
uniform float noise_strength = 0.06;
uniform float noise_scale = 0.9;
// Procedural decal stains act as a material-specific overlay without requiring a tavern atlas rewrite.
uniform vec4 decal_tint : source_color = vec4(0.62, 0.44, 0.28, 1.0);
uniform float decal_strength = 0.12;
uniform float decal_scale = 0.8;
uniform float decal_threshold = 0.74;
uniform float roughness_variation = 0.08;

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

float hash12(vec2 value) {
	value = fract(value * vec2(123.34, 456.21));
	value += dot(value, value + 45.32);
	return fract(value.x * value.y);
}

float value_noise(vec2 value) {
	vec2 cell = floor(value);
	vec2 local = fract(value);
	local = local * local * (3.0 - 2.0 * local);
	float lower = mix(hash12(cell), hash12(cell + vec2(1.0, 0.0)), local.x);
	float upper = mix(hash12(cell + vec2(0.0, 1.0)), hash12(cell + vec2(1.0, 1.0)), local.x);
	return mix(lower, upper, local.y);
}

float sample_surface_noise(vec2 meter_coord) {
	float broad = value_noise(meter_coord * noise_scale);
	float medium = value_noise(meter_coord * noise_scale * vec2(1.8, 0.75) + vec2(7.0, 13.0));
	float grain = value_noise(meter_coord * noise_scale * 3.2 + vec2(19.0, 7.0));
	return mix(mix(broad, medium, 0.45), grain, 0.28);
}

float sample_decal_mask(vec2 meter_coord) {
	vec2 scaled = meter_coord * decal_scale;
	vec2 cell = floor(scaled);
	vec2 local = fract(scaled) - vec2(0.5);
	float selection = hash12(cell + vec2(31.0, 17.0));
	vec2 offset = vec2(
		hash12(cell + vec2(53.0, 11.0)),
		hash12(cell + vec2(7.0, 97.0))
	) * 0.32 - vec2(0.16);
	float radius = mix(0.16, 0.38, hash12(cell + vec2(3.0, 71.0)));
	float shape = 1.0 - smoothstep(radius, radius + 0.06, length(local - offset));
	float chosen = smoothstep(decal_threshold, min(decal_threshold + 0.12, 1.0), selection);
	float decal_broad = smoothstep(0.46, 0.72, value_noise(meter_coord * decal_scale * 0.55 + vec2(13.0, 41.0)));
	return clamp(max(shape * chosen, decal_broad * 0.36), 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 blend = pow(abs(n), vec3(4.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);

	vec4 x_sample = sample_atlas(world_pos.zy);
	vec4 y_sample = sample_atlas(world_pos.xz);
	vec4 z_sample = sample_atlas(world_pos.xy);
	vec4 atlas_color = x_sample * blend.x + y_sample * blend.y + z_sample * blend.z;
	float x_noise = sample_surface_noise(world_pos.zy);
	float y_noise = sample_surface_noise(world_pos.xz);
	float z_noise = sample_surface_noise(world_pos.xy);
	float surface_noise = x_noise * blend.x + y_noise * blend.y + z_noise * blend.z;
	float x_decal = sample_decal_mask(world_pos.zy);
	float y_decal = sample_decal_mask(world_pos.xz);
	float z_decal = sample_decal_mask(world_pos.xy);
	float decal_mask = x_decal * blend.x + y_decal * blend.y + z_decal * blend.z;

	vec3 base_color = (atlas_color * albedo_tint).rgb;
	base_color *= 1.0 + (surface_noise - 0.5) * 2.0 * noise_strength;
	vec3 decal_color = mix(vec3(1.0), decal_tint.rgb, decal_strength);
	ALBEDO = base_color * mix(vec3(1.0), decal_color, decal_mask);
	ROUGHNESS = clamp(material_roughness + (surface_noise - 0.5) * 2.0 * roughness_variation + decal_mask * 0.04, 0.05, 1.0);
	METALLIC = material_metallic;
}
