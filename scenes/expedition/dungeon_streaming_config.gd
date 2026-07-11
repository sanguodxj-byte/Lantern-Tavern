## DungeonStreamingConfig — streaming 配置模块（评审建议 E 阶段）。
#
# 收拢 procedural 顶散落的 streaming 相关 const，让 streaming 配置有唯一定义来源。
# 评审约束：禁止继续在 ProceduralDungeon 添加新的地牢配置常量。
class_name DungeonStreamingConfig
extends RefCounted

# chunk 尺寸（格数）
var chunk_size_cells: int = 8

# chunk 激活半径（按类型）
var light_chunk_radius: int = 2
var physics_chunk_radius: int = 1
var visual_chunk_radius: int = 1
var terrain_chunk_radius: int = 1

# streaming 更新间隔（秒）
var update_interval: float = 0.25

# 可见局部灯光预算
var visible_local_light_budget: int = 12

## 默认配置（与 procedural 旧 const 值一致，保旧行为）
static func default() -> DungeonStreamingConfig:
	var cfg := DungeonStreamingConfig.new()
	cfg.chunk_size_cells = 8
	cfg.light_chunk_radius = 2
	cfg.physics_chunk_radius = 1
	cfg.visual_chunk_radius = 1
	cfg.terrain_chunk_radius = 1
	cfg.update_interval = 0.25
	cfg.visible_local_light_budget = 12
	return cfg
