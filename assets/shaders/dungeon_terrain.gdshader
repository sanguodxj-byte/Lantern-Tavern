shader_type spatial;
// 明确声明渲染模式：参与完整 PBR 光照（含 OmniLight 火把效果）
// 不加 unshaded，所以 Godot 会自动计算所有光源的漫反射+高光
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx;

// 纹理集（128x128，4x4 网格，每格 32x32）
uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;

// 图块位置（col, row），对应纹理集中的列/行，从 0 开始
// 例：WALL=(1,0)  FLOOR=(2,0)  CEILING=(3,1)  LINTEL=(3,0)
uniform vec2 tile_col_row = vec2(1.0, 0.0);

// 物理平铺次数：= 面的物理尺寸（米）
// 3m 面 → 3.0；高 3m 墙 → 纵向 3.0
uniform vec2 tile_repeat = vec2(3.0, 3.0);

// 材质参数（影响火把光照效果的可见强度）
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float specular : hint_range(0.0, 1.0) = 0.2;

// 纹理集分区大小（4x4 → 每格占 0.25）
const float TILE_FRAC = 0.25;

void fragment() {
	// 1. 先在 [0,1] 内正确重复（不越界到其他图块）
	vec2 tiled_uv = fract(UV * tile_repeat);

	// 2. 缩放到单格大小，再加图块偏移 → 定位到 atlas 中的具体图块
	vec2 atlas_uv = tiled_uv * TILE_FRAC + tile_col_row * TILE_FRAC;

	vec4 col = texture(atlas, atlas_uv);
	ALBEDO = col.rgb;

	// 以下参数直接影响 OmniLight（火把）和场景光源的光照计算
	ROUGHNESS = roughness;   // 越高越哑光，越低越光滑反光
	METALLIC = 0.0;          // 石材非金属
	SPECULAR = specular;     // 轻微高光，让火把能在墙上留下亮点
}
