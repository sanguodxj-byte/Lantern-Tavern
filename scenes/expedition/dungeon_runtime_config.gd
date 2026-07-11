## DungeonRuntimeConfig — runtime 配置模块（评审建议 E 阶段）。
#
# 收拢 procedural 顶散落的 runtime 相关 const（材料/装饰/批装饰场景/视野等），
# 让 runtime 配置有唯一定义来源。
# 评审约束：禁止继续在 ProceduralDungeon 添加新的地牢配置常量。
class_name DungeonRuntimeConfig
extends RefCounted

# 材料掉落配置（item_id -> weight）
var materials_config: Dictionary = {
	"blackberry": 15, "glowshroom": 12, "moongrass": 10, "goblin_nail": 8,
	"mistflower": 8, "wolfear_herb": 8, "pixie_dust": 5, "poison_berry": 4
}

# 装饰场景配置（scene_path -> weight）
var decor_config: Dictionary = {
	"res://scenes/props/decor/bones.tscn": 20,
	"res://scenes/props/decor/lit_candles.tscn": 15,
	"res://scenes/props/decor/floor_candelabrum.tscn": 9,
	"res://scenes/props/decor/wall_candelabrum.tscn": 8,
	"res://scenes/props/decor/iron_bar_grate.tscn": 7,
	"res://scenes/props/decor/spiderweb.tscn": 15,
	"res://scenes/props/decor/bench.tscn": 10,
	"res://scenes/props/decor/chair.tscn": 10,
	"res://scenes/props/decor/table.tscn": 10,
	"res://scenes/props/crates/small_crate.tscn": 10,
	"res://scenes/props/barrel/barrel.tscn": 10
}

# 可批处理装饰场景（scene_path -> true）
var batched_decor_scenes: Dictionary = {
	"res://scenes/props/decor/bones.tscn": true,
	"res://scenes/props/decor/bench.tscn": true,
	"res://scenes/props/decor/chair.tscn": true,
	"res://scenes/props/decor/table.tscn": true,
	"res://scenes/props/crates/small_crate.tscn": true,
	"res://scenes/props/decor/iron_bar_grate.tscn": true,
	"res://scenes/props/structures/pillar.tscn": true,
}

## 默认配置（与 procedural 旧 const 值一致，保旧行为）
static func default() -> DungeonRuntimeConfig:
	return DungeonRuntimeConfig.new()
