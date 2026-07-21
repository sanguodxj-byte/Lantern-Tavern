shader_type spatial;
// 体素/像素风地形与道具共用材质。
// 不走真实 PBR 立方体受光：自定义 light() 用半兰伯特 + 量化漫反射，
// 保留火把/玩家灯影响，但让小方块阴面不过黑、亮面不过碎。
render_mode cull_back, depth_draw_opaque, specular_disabled;

// Atlas grid is metadata-driven in code: level 0 uses 256x128, 8x4 grid, 32px tiles.
uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;

// Tile position (col, row), in 32px cells.
uniform vec2 tile_col_row = vec2(1.0, 0.0);

// Tile span in 32px cells. Normal terrain is 1x1; the dungeon door is 2x1 (64x32).
uniform vec2 tile_span = vec2(1.0, 1.0);

// Atlas grid size in 32px cells.
uniform vec2 atlas_grid = vec2(8.0, 4.0);

// 物理平铺次数：= 面的物理尺寸（米）
// 3m 面 → 3.0；高 3m 墙 → 纵向 3.0
uniform vec2 tile_repeat = vec2(3.0, 3.0);

// 材质参数（影响火把光照效果的可见强度）
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float specular : hint_range(0.0, 1.0) = 0.2;
uniform float voxel_light_wrap : hint_range(0.0, 1.0) = 0.45;
uniform float voxel_light_floor : hint_range(0.0, 1.0) = 0.22;
uniform float voxel_light_steps : hint_range(2.0, 6.0, 1.0) = 6.0;
uniform float voxel_light_quantize : hint_range(0.0, 1.0) = 0.20;
uniform float voxel_light_strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	// 1. 先在 [0,1] 内正确重复（不越界到其他图块）
	vec2 tiled_uv = fract(UV * tile_repeat);

	// 2. Scale into the selected atlas span. A 2x1 door samples 64x32px as one region.
	vec2 atlas_uv = (tile_col_row + tiled_uv * tile_span) / atlas_grid;

	vec4 col = texture(atlas, atlas_uv);
	ALBEDO = col.rgb;

	// 以下参数直接影响 OmniLight（火把）和场景光源的光照计算
	ROUGHNESS = roughness;   // 越高越哑光，越低越光滑反光
	METALLIC = 0.0;          // 石材非金属
	SPECULAR = specular;
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + voxel_light_wrap) / (1.0 + voxel_light_wrap), 0.0, 1.0);
	float levels = max(voxel_light_steps - 1.0, 1.0);
	float banded = floor(wrapped * levels + 0.5) / levels;
	float band_mix = smoothstep(0.0, 1.0, voxel_light_quantize);
	float shaped = mix(wrapped, banded, band_mix);
	float light_amount = max(shaped, voxel_light_floor) * voxel_light_strength;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * light_amount;
}
