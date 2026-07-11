## DungeonRenderingConfig — 渲染配置模块（评审建议 E 阶段）。
#
# 收拢 procedural 顶散落的渲染/材质/几何相关 const，让渲染配置有唯一定义来源。
# 评审约束：禁止继续在 ProceduralDungeon 添加新的地牢配置常量。
class_name DungeonRenderingConfig
extends RefCounted

# 大房间面积阈值（格数）
var large_room_area: int = 48

# 门墙包围厚度（米）
var door_surround_thickness: float = 0.2

# 天花板厚度（米）
var ceiling_thickness: float = 0.1

# 天花板过渡缝隙（米）
var ceiling_transition_gap: float = 0.015

# 玩家视野基础能量/范围（runtime 范畴，暂收拢供统一引用）
var player_vision_base_energy: float = 2.4
var player_vision_base_range: float = 10.0

## 默认配置（与 procedural 旧 const 值一致，保旧行为）
static func default() -> DungeonRenderingConfig:
	var cfg := DungeonRenderingConfig.new()
	cfg.large_room_area = 48
	cfg.door_surround_thickness = 0.2
	cfg.ceiling_thickness = 0.1
	cfg.ceiling_transition_gap = 0.015
	cfg.player_vision_base_energy = 2.4
	cfg.player_vision_base_range = 10.0
	return cfg
