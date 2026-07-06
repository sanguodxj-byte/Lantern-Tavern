shader_type spatial;
// 明确声明渲染模式：参与完整 PBR 光照（含 OmniLight 火把效果）
// 不加 unshaded，所以 Godot 会自动计算所有光源的漫反射+高光
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx;

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
	SPECULAR = specular;     // 轻微高光，让火把能在墙上留下亮点
}
