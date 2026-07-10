## DungeonGenerationConfig — 地牢生成期的可调参数集（阶段 2）。
#
# 设计原则（见地牢重构方案六）：
#   - 只描述“生成规则”，不创建场景节点、不 preload .tscn、不持 shader/material。
#   - runtime 视觉/streaming 配置（灯光能量、HUD、材质、shader、激活半径、剔除距离）
#     显式不入本配置 —— 它们属于 DungeonRuntime / DungeonStreamingController。
#   - 算法内部参数（如 isaac 的 ROOM_SHAPES 列表）通过 algorithm_params 子 Dictionary 传入，
#     保持本类顶层字段稳定。
#
# 字段来源：从 procedural_dungeon.gd / isaac_room_dungeon_generator.gd 收拢的散落 const。
class_name DungeonGenerationConfig
extends RefCounted

# ── 顶层生成参数 ─────────────────────────────────────────────
var seed: int = 0                # 生成随机种子；0 表示由 DungeonGenerator 选随机种子
var zone: int = 0                # BrewingData.Zone 枚举值，决定掉落池/敌人权重
var width: int = 42              # 网格宽（格数）
var height: int = 42             # 网格高（格数）
var tile_size: float = 3.0       # 每格物理尺寸（米）；1m = 32px voxel 标准
var algorithm: String = "isaac"  # "isaac" / "wfc" / "bsp"；DungeonGenerator 按此选择包装
var target_room_count: int = 14  # isaac 目标房间数，clamp 到 [6,18]

# ── 生成期地形规则（从 procedural_dungeon.gd 收拢）────────────
var large_room_area: int = 48                # LARGE_ROOM_AREA：超过此面积的房间触发“大型房间地形特征”
var door_surround_thickness: float = 0.2    # DOOR_SURROUND_THICKNESS：门墙包围厚度（米）
var ceiling_thickness: float = 0.1          # CEILING_THICKNESS：天花板厚度（米）
var ceiling_transition_gap: float = 0.015   # CEILING_TRANSITION_GAP：相邻格高度差接缝间隙（米）
var standard_door_size_meters := Vector2(1.0, 2.0)  # STANDARD_DOOR_SIZE_METERS
var boss_door_size_meters := Vector2(2.0, 2.0)      # BOSS_DOOR_SIZE_METERS
var ceiling_height_base: float = 3.4         # isaac _make_height_grid 的基准高度（米）

# ── 功能开关 ─────────────────────────────────────────────────
var enable_hazards: bool = true              # 是否规划危险地形（阶段 5）
var enable_spawn_planning: bool = true       # 是否规划敌人/掉落/宝箱（阶段 6）
var enable_connectivity_check: bool = true   # 是否在生成后做连通性验证（阶段 4）
var enable_extraction_room: bool = true      # 是否尝试 assign extraction role（0.2 概率）

# ── 算法内部参数（保持顶层字段稳定）──────────────────────────
# isaac 算法参数。null 表示用 isaac 生成器内 const 默认值。
var isaac_params: Dictionary = {
	"room_size": 5,
	"room_spacing": 8,
	"macro_radius": 2,
	"extraction_room_probability": 0.2,
	"shortcut_connector_size": 5,
	"merged_room_connection_width": 5,
	"room_center_jitter": 2,
}

# bsp/wfc 当前无外暴露的可调参数；保留 Dictionary 占位，避免阶段 3 包装时再改本类签名。
var bsp_params: Dictionary = {}
var wfc_params: Dictionary = {}


## 创建一份与 procedural_dungeon.gd 默认值一致的配置（迁移期兼容用）。
## 调用方可在此基础上覆写字段后传给 DungeonGenerator。
static func default_for_zone(zone: int) -> DungeonGenerationConfig:
	var cfg := DungeonGenerationConfig.new()
	cfg.zone = zone
	return cfg

## 浅拷贝：顶层字段复制，isaac_params/bsp_params/wfc_params Dictionary 单独 duplicate。
func duplicate_config() -> DungeonGenerationConfig:
	var copy := DungeonGenerationConfig.new()
	copy.seed = seed
	copy.zone = zone
	copy.width = width
	copy.height = height
	copy.tile_size = tile_size
	copy.algorithm = algorithm
	copy.target_room_count = target_room_count
	copy.large_room_area = large_room_area
	copy.door_surround_thickness = door_surround_thickness
	copy.ceiling_thickness = ceiling_thickness
	copy.ceiling_transition_gap = ceiling_transition_gap
	copy.standard_door_size_meters = standard_door_size_meters
	copy.boss_door_size_meters = boss_door_size_meters
	copy.ceiling_height_base = ceiling_height_base
	copy.enable_hazards = enable_hazards
	copy.enable_spawn_planning = enable_spawn_planning
	copy.enable_connectivity_check = enable_connectivity_check
	copy.enable_extraction_room = enable_extraction_room
	copy.isaac_params = isaac_params.duplicate(true)
	copy.bsp_params = bsp_params.duplicate(true)
	copy.wfc_params = wfc_params.duplicate(true)
	return copy

## 校验配置内部一致性。返回 Dictionary 报告 {valid:bool, errors:Array[String]}。
## 不修改自身。
func validate() -> Dictionary:
	var errors: Array = []
	if width <= 0 or height <= 0:
		errors.append("grid dimensions must be positive (w=%d, h=%d)" % [width, height])
	if tile_size <= 0.0:
		errors.append("tile_size must be positive (%f)" % tile_size)
	if not algorithm in ["isaac", "wfc", "bsp"]:
		errors.append("unknown algorithm '%s' (expected isaac/wfc/bsp)" % algorithm)
	if target_room_count < 6 or target_room_count > 18:
		errors.append("target_room_count %d out of [6,18] clamp range" % target_room_count)
	if standard_door_size_meters.x <= 0.0 or standard_door_size_meters.y <= 0.0:
		errors.append("standard_door_size_meters must be positive")
	if boss_door_size_meters.x <= 0.0 or boss_door_size_meters.y <= 0.0:
		errors.append("boss_door_size_meters must be positive")
	if ceiling_thickness <= 0.0:
		errors.append("ceiling_thickness must be positive")
	if ceiling_height_base <= 0.0:
		errors.append("ceiling_height_base must be positive")
	# isaac_params 类型与范围抽查
	if isaac_params.has("room_size") and int(isaac_params["room_size"]) <= 0:
		errors.append("isaac_params.room_size must be positive")
	if isaac_params.has("extraction_room_probability"):
		var p: float = float(isaac_params["extraction_room_probability"])
		if p < 0.0 or p > 1.0:
			errors.append("isaac_params.extraction_room_probability %f out of [0,1]" % p)
	return {"valid": errors.is_empty(), "errors": errors}

## 默认值是否与 procedural_dungeon.gd 现存 const 一致（迁移期回归锚）。
## 任一字段偏离 procedural_dungeon.gd 的现存 const 即返回 false。
func matches_procedural_dungeon_defaults() -> bool:
	return tile_size == 3.0 \
		and large_room_area == 48 \
		and door_surround_thickness == 0.2 \
		and ceiling_thickness == 0.1 \
		and ceiling_transition_gap == 0.015 \
		and standard_door_size_meters == Vector2(1.0, 2.0) \
		and boss_door_size_meters == Vector2(2.0, 2.0) \
		and target_room_count == 14
