class_name DungeonTerrainConfig
## 地牢地形渲染配置（从 procedural_dungeon.gd 提取）。
## 承载地形纹理图集布局、图块映射、以及 ShaderMaterial 构建逻辑。
## 作为纯数据+工具类，不依赖任何运行时状态。

# 地形渲染：关卡 0 使用 32px/m 的 256x128 纹理集 + 一个 Shader
const DUNGEON_TEX := preload("res://assets/textures/terrain/level0_dungeon/level0_dungeon_terrain_atlas_32px.png")
const TERRAIN_SHADER := preload("res://assets/shaders/dungeon_terrain.gdshader")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

# 每个地形类型对应纹理集中的图块位置 (col, row)。和 tools/build_level0_dungeon_atlas.py 完全对应。
const TILE_ATLAS_GRID := Vector2(8, 4)
const TILE_LAYOUT := {
	"WALL":    Vector2(4, 2),  # Barony 风格深色石砖墙面
	"FLOOR":   Vector2(5, 2),  # Barony 风格不规则原石地面
	"CEILING": Vector2(2, 3),  # 暗石板天花
	"LINTEL":  Vector2(6, 2),  # 切石高台/门楣/高度差收边
	"PILLAR":  Vector2(4, 2),  # 石柱侧面
	"DOOR":    Vector2(7, 1),  # 普通门：1m x 2m，占 1x2 个 32px UV 格
	"BOSS_DOOR": Vector2(0, 2), # Boss 房双开门：2m x 2m，占 2x2 个 32px UV 格
	"DOOR_SIDE": Vector2(2, 2),
	"DOOR_TOP": Vector2(3, 2),
	"PORTAL":  Vector2(7, 0),  # 传送门符文
	"BARONY_WALL": Vector2(4, 2),
	"BARONY_FLOOR": Vector2(5, 2),
	"BARONY_PLATFORM": Vector2(6, 2),
	"BARONY_THRESHOLD": Vector2(7, 2),
	"BARONY_CEILING": Vector2(2, 3),
	"BARONY_MOSS_FLOOR": Vector2(3, 3),
	"BARONY_BROKEN_WALL": Vector2(4, 3),
	"BARONY_BOSS_SLAB": Vector2(5, 3),
}
const TILE_SPANS := {
	"WALL":    Vector2(1, 1),
	"FLOOR":   Vector2(1, 1),
	"CEILING": Vector2(1, 1),
	"LINTEL":  Vector2(1, 1),
	"PILLAR":  Vector2(1, 1),
	"DOOR":    Vector2(1, 2),
	"BOSS_DOOR": Vector2(2, 2),
	"DOOR_SIDE": Vector2(1, 1),
	"DOOR_TOP": Vector2(1, 1),
	"PORTAL":  Vector2(1, 1),
	"BARONY_WALL": Vector2(1, 1),
	"BARONY_FLOOR": Vector2(1, 1),
	"BARONY_PLATFORM": Vector2(1, 1),
	"BARONY_THRESHOLD": Vector2(1, 1),
	"BARONY_CEILING": Vector2(1, 1),
	"BARONY_MOSS_FLOOR": Vector2(1, 1),
	"BARONY_BROKEN_WALL": Vector2(1, 1),
	"BARONY_BOSS_SLAB": Vector2(1, 1),
}

const CEILING_THICKNESS := 0.1
const CEILING_TRANSITION_GAP := 0.015

## 创建地形/程序化道具共用 ShaderMaterial。
## tile_name: TILE_LAYOUT 中的键（"WALL"/"FLOOR"/"CEILING"等）
## tile_repeat: 每轴平铺次数， = 该面的物理尺寸（米），1m = 1次 = 32px
## surface_profile: 可选材质变化；world_aligned_uv 用于 BoxMesh/ArrayMesh，避免 UV 拉伸。
static func make_terrain_mat(tile_name: String, tile_repeat: Vector2,
		surface_profile: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	var tile_pos: Vector2 = TILE_LAYOUT.get(tile_name, Vector2(0, 0))
	var span: Vector2 = TILE_SPANS.get(tile_name, Vector2(1, 1))
	# dungeon_terrain.gdshader 的 uniform 契约：tile_col_row / tile_span 以「32px 图块格」为单位，
	# shader 内部按 (tile_col_row + tiled_uv * tile_span) / atlas_grid 采样，因此这里必须传原始格值，勿预除；
	# 纹理 sampler 名为 atlas（不是 base_texture）。旧实现误设 " atlas_offset"/"atlas_size"/"base_texture"
	# 三个 shader 根本不存在的 uniform，导致 atlas sampler 从未绑定纹理 → 地形全部采样成黑色（墙/地/天花板一片黑）。
	mat.set_shader_parameter("atlas", DUNGEON_TEX)
	mat.set_shader_parameter("tile_col_row", tile_pos)
	mat.set_shader_parameter("tile_span", span)
	mat.set_shader_parameter("atlas_grid", TILE_ATLAS_GRID)
	mat.set_shader_parameter("tile_repeat", tile_repeat)
	mat.set_shader_parameter("roughness", float(surface_profile.get("roughness", 0.9)))
	mat.set_shader_parameter("specular", 0.0)
	mat.set_shader_parameter("voxel_base_fill", float(surface_profile.get("voxel_base_fill", 0.16)))
	mat.set_shader_parameter("world_aligned_uv_enabled", 1.0 if bool(surface_profile.get("world_aligned_uv", false)) else 0.0)
	mat.set_shader_parameter("meters_per_tile", maxf(float(surface_profile.get("meters_per_tile", 1.0)), 0.125))
	mat.set_shader_parameter("albedo_tint", surface_profile.get("albedo_tint", Color.WHITE))
	mat.set_shader_parameter("emission_tint", surface_profile.get("emission_tint", Color.WHITE))
	mat.set_shader_parameter("emission_strength", maxf(float(surface_profile.get("emission_strength", 0.0)), 0.0))
	# 同步全局像素着色开关：开启时写入 toon 光照参数，关闭时设置
	# pixel_lighting_enabled=0.0 使 shader 的 light() 回退到标准 Lambert。
	VOXEL_LIGHTING.apply_shader_profile(mat, VOXEL_LIGHTING.DEFAULT_SHADER_PROFILE)
	return mat
