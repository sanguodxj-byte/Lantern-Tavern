shader_type spatial;
// 体素/像素风地形与道具共用材质。
// 不走真实 PBR 立方体受光：自定义 light() 用半兰伯特 + 量化漫反射，
// 保留火把/玩家灯影响，但让小方块阴面不过黑、亮面不过碎。
render_mode cull_back, depth_draw_opaque, specular_disabled;

// Atlas grid is metadata-driven in code: level 0 uses 256x128, 8x4 grid, 32px tiles.
uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;

// Tile position (col, row), in 32px cells.
// 注意：hint_range 仅支持 float/int uniform，vec2 图集参数不支持范围提示。
uniform vec2 tile_col_row = vec2(1.0, 0.0);

// Tile span in 32px cells. Normal terrain is 1x1; the dungeon door is 2x1 (64x32).
uniform vec2 tile_span = vec2(1.0, 1.0);

// Atlas grid size in 32px cells.
uniform vec2 atlas_grid = vec2(8.0, 4.0);

// 物理平铺次数：= 面的物理尺寸（米）
// 3m 面 → 3.0；高 3m 墙 → 纵向 3.0
uniform vec2 tile_repeat = vec2(3.0, 3.0);

// 材质参数（影响火把漫反射效果的可见强度）。
// specular 保留为旧场景资源的兼容 uniform，但项目体素/道具规范禁止镜面高光。
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float specular : hint_range(0.0, 1.0) = 0.0;
uniform float voxel_light_wrap : hint_range(0.0, 1.0) = 0.45;
uniform float voxel_light_floor : hint_range(0.0, 1.0) = 0.22;
uniform float voxel_light_steps : hint_range(2.0, 6.0, 1.0) = 6.0;
uniform float voxel_light_quantize : hint_range(0.0, 1.0) = 0.20;
uniform float voxel_light_strength : hint_range(0.0, 2.0) = 1.0;
uniform float voxel_base_fill : hint_range(0.0, 1.0) = 0.16;

// 程序生成的 BoxMesh/ArrayMesh 使用世界坐标投影，避免同一 UV 被拉伸成纯色色块。
// 传统地形 MultiMesh 默认继续使用原有 UV 平铺路径。
uniform float world_aligned_uv_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float meters_per_tile : hint_range(0.125, 4.0) = 1.0;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 emission_tint : source_color = vec4(1.0);
uniform float emission_strength : hint_range(0.0, 3.0) = 0.0;

// 全局像素着色开关（由 VoxelLightingAdapter.apply_shader_profile 写入）。
// 1.0 = 使用半兰伯特 + 量化漫反射（像素/卡通风格）；0.0 = 标准 Lambert 漫反射。
uniform float pixel_lighting_enabled : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 sample_atlas_tile(vec2 surface_uv) {
	vec2 tiled_uv = fract(surface_uv);
	vec2 atlas_uv = (tile_col_row + tiled_uv * tile_span) / atlas_grid;
	return texture(atlas, atlas_uv);
}

void fragment() {
	vec4 col;
	if (world_aligned_uv_enabled > 0.5) {
		vec3 normal_weight = pow(abs(normalize(world_normal)), vec3(8.0));
		normal_weight /= max(normal_weight.x + normal_weight.y + normal_weight.z, 0.0001);
		float scale = max(meters_per_tile, 0.0001);
		vec4 x_sample = sample_atlas_tile(world_position.zy / scale);
		vec4 y_sample = sample_atlas_tile(world_position.xz / scale);
		vec4 z_sample = sample_atlas_tile(world_position.xy / scale);
		col = x_sample * normal_weight.x + y_sample * normal_weight.y + z_sample * normal_weight.z;
	} else {
		// UV 地形路径：先在 [0,1] 内重复，再缩放到选中的 atlas 区域。
		col = sample_atlas_tile(UV * tile_repeat);
	}

	vec3 textured_albedo = col.rgb * albedo_tint.rgb;
	ALBEDO = textured_albedo;
	// 普通地形不得靠基础填充自发光。只有被明确标记为真实光源物体的材质
	// 才能通过 emission_strength 输出自发光，并继续保留图集纹理细节。
	EMISSION = col.rgb * emission_tint.rgb * emission_strength;

	// 以下参数直接影响 OmniLight（火把）和场景光源的光照计算
	ROUGHNESS = roughness;   // 越高越哑光，越低越光滑反光
	METALLIC = 0.0;          // 石材非金属
	// render_mode 已禁用镜面项；显式置零防止未来移除 render_mode 时回归。
	SPECULAR = 0.0;
}

void light() {
	if (pixel_lighting_enabled < 0.5) {
		// 像素着色关闭：标准 Lambert 漫反射，不做半兰伯特/量化处理。
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0);
	} else {
		float wrapped = clamp((dot(NORMAL, LIGHT) + voxel_light_wrap) / (1.0 + voxel_light_wrap), 0.0, 1.0);
		float levels = max(voxel_light_steps - 1.0, 1.0);
		float banded = floor(wrapped * levels + 0.5) / levels;
		float band_mix = smoothstep(0.0, 1.0, voxel_light_quantize);
		float shaped = mix(wrapped, banded, band_mix);
		float light_amount = max(shaped, voxel_light_floor) * voxel_light_strength;
		// 多盏火光会同时进入同一像素；限制累计漫反射，避免墙面和浅色道具烧白。
		vec3 contribution = LIGHT_COLOR * ATTENUATION * light_amount;
		DIFFUSE_LIGHT = min(DIFFUSE_LIGHT + contribution, vec3(0.68));
	}
	// 垂直墙面在没有近距离火把时仍需保留最低可读性。使用 max 而不是累加，
	// 避免多盏局部灯把基础填充重复叠加成泛白；这不是材质自发光。
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(voxel_base_fill));
}
