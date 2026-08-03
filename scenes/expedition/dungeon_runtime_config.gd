## DungeonRuntimeConfig — runtime 配置模块（评审建议 E 阶段）。
#
# 收拢 procedural 顶散落的 runtime 相关 const（材料/装饰/批装饰场景/视野等），
# 让 runtime 配置有唯一定义来源。
# 评审约束：禁止继续在 ProceduralDungeon 添加新的地牢配置常量。
class_name DungeonRuntimeConfig
extends RefCounted

# 地牢场景物体目录。这里是地牢生成的唯一白名单；酒馆家具与酒馆装饰
# 即使同样位于 scenes/props/ 下，也不能通过地牢生成链路进入地牢。
const DUNGEON_DECOR_SCENES := {
	"bones": "res://scenes/props/dungeon/decor/bones.tscn",
	"rubble": "res://scenes/props/dungeon/decor/rubble.tscn",
	"plank": "res://scenes/props/dungeon/decor/plank.tscn",
	"small_crate": "res://scenes/props/dungeon/dungeon_crate.tscn",
	"barrel": "res://scenes/props/dungeon/dungeon_barrel.tscn",
	"floor_candelabrum": "res://scenes/props/dungeon/decor/floor_candelabrum.tscn",
	"wall_candelabrum": "res://scenes/props/dungeon/decor/wall_candelabrum.tscn",
	"iron_bar_grate": "res://scenes/props/dungeon/decor/iron_bar_grate.tscn",
	"spiderweb": "res://scenes/props/dungeon/decor/spiderweb.tscn",
	"ruble": "res://scenes/props/dungeon/decor/rubble.tscn",
	"ritual_totem": "res://scenes/props/dungeon/decor/ritual_totem.tscn",
	"stalagmite_cluster": "res://scenes/props/dungeon/decor/stalagmite_cluster.tscn",
	"sarcophagus": "res://scenes/props/dungeon/decor/sarcophagus.tscn",
	"wall_chain": "res://scenes/props/dungeon/decor/wall_chain.tscn",
	"fungus_patch": "res://scenes/props/dungeon/decor/fungus_patch.tscn",
}

const DUNGEON_DECOR_CONFIG := {
	"res://scenes/props/dungeon/decor/bones.tscn": 20,
	"res://scenes/props/dungeon/decor/rubble.tscn": 10,
	"res://scenes/props/dungeon/decor/plank.tscn": 10,
	"res://scenes/props/dungeon/decor/floor_candelabrum.tscn": 9,
	"res://scenes/props/dungeon/decor/wall_candelabrum.tscn": 8,
	"res://scenes/props/dungeon/decor/iron_bar_grate.tscn": 7,
	"res://scenes/props/dungeon/decor/spiderweb.tscn": 15,
	"res://scenes/props/dungeon/dungeon_crate.tscn": 10,
	"res://scenes/props/dungeon/dungeon_barrel.tscn": 10,
	"res://scenes/props/dungeon/decor/ritual_totem.tscn": 5,
	"res://scenes/props/dungeon/decor/stalagmite_cluster.tscn": 8,
	"res://scenes/props/dungeon/decor/sarcophagus.tscn": 4,
	"res://scenes/props/dungeon/decor/wall_chain.tscn": 7,
	"res://scenes/props/dungeon/decor/fungus_patch.tscn": 9,
}

# 摆放策略由规划器消费：wall 会贴邻墙并按墙向旋转，edge 偏向房间边缘，
# anchor 用于需要留出中心焦点的重型陈设，floor 只占普通地面格。
const DUNGEON_DECOR_PLACEMENT := {
	"bones": "floor",
	"rubble": "edge",
	"plank": "edge",
	"small_crate": "edge",
	"barrel": "edge",
	"floor_candelabrum": "floor",
	"wall_candelabrum": "wall",
	"iron_bar_grate": "wall",
	"spiderweb": "wall",
	"ruble": "edge",
	"ritual_totem": "anchor",
	"stalagmite_cluster": "edge",
	"sarcophagus": "anchor",
	"wall_chain": "wall",
	"fungus_patch": "edge",
}

const DUNGEON_CONTAINER_CONFIG := {
	"res://scenes/props/dungeon/dungeon_barrel.tscn": 50,
	"res://scenes/props/dungeon/dungeon_crate.tscn": 50,
}

const DUNGEON_BATCHED_DECOR_SCENES := {
	"res://scenes/props/dungeon/decor/bones.tscn": true,
	"res://scenes/props/dungeon/decor/plank.tscn": true,
	"res://scenes/props/dungeon/dungeon_crate.tscn": true,
	"res://scenes/props/dungeon/decor/iron_bar_grate.tscn": true,
	"res://scenes/props/dungeon/pillar.tscn": true,
}

# 材料掉落配置（item_id -> weight）
var materials_config: Dictionary = {
	"blackberry": 15, "glowshroom": 12, "moongrass": 10, "goblin_nail": 8,
	"mistflower": 8, "wolfear_herb": 8, "pixie_dust": 5, "poison_berry": 4
}

# 装饰场景配置（scene_path -> weight）
var decor_config: Dictionary = DUNGEON_DECOR_CONFIG.duplicate()

# 容器配置与装饰配置分开，但共享同一地牢场景白名单。
var container_config: Dictionary = DUNGEON_CONTAINER_CONFIG.duplicate()

# 可批处理装饰场景（scene_path -> true）
var batched_decor_scenes: Dictionary = DUNGEON_BATCHED_DECOR_SCENES.duplicate()

static func dungeon_decor_scene_path(kind: String) -> String:
	return String(DUNGEON_DECOR_SCENES.get(kind, ""))

static func is_allowed_dungeon_scene_path(path: String) -> bool:
	if path.is_empty():
		return false
	return DUNGEON_DECOR_SCENES.values().has(path) \
		or DUNGEON_CONTAINER_CONFIG.has(path) \
		or DUNGEON_BATCHED_DECOR_SCENES.has(path)

func dungeon_decor_scene_path_for(kind: String) -> String:
	return dungeon_decor_scene_path(kind)

static func dungeon_decor_placement_for(kind: String) -> String:
	return String(DUNGEON_DECOR_PLACEMENT.get(kind, "floor"))

static func dungeon_decor_placement_for_path(path: String) -> String:
	for kind in DUNGEON_DECOR_SCENES.keys():
		if String(DUNGEON_DECOR_SCENES[kind]) == path:
			return dungeon_decor_placement_for(String(kind))
	return "floor"

func is_dungeon_scene_path_allowed(path: String) -> bool:
	return is_allowed_dungeon_scene_path(path)

## 默认配置（与 procedural 旧 const 值一致，保旧行为）
static func default() -> DungeonRuntimeConfig:
	return DungeonRuntimeConfig.new()
