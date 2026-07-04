extends Node
## 区域选择管理器（autoload: ZoneManager）。
## 保存玩家选定的探险区域，供 procedural_dungeon 读取以配置宝箱 zone 与散落材料池。
## 同时承载四区的显示名/描述/推荐等级等元数据，供区域选择 UI 渲染。

# 当前选定区域（BrewingData.Zone 枚举值），-1 表示未选定
var selected_zone: int = 0

# 四区元数据（策划案 10：森林/洞窟/墓园/火山）
const ZONE_META: Dictionary = {
	0: {"name": "幽暗森林", "desc": "新手友好区。盛产黑莓、蓝光菇、月光草等温和材料。", "difficulty": 1, "color": Color(0.2, 0.5, 0.2)},
	1: {"name": "深邃洞窟", "desc": "盛产黑麦根、深岩苔藓、独眼巨人胡须。盲鱼与碎岩虫出没。", "difficulty": 2, "color": Color(0.3, 0.3, 0.4)},
	2: {"name": "荒芜墓园", "desc": "灵魂薄荷、月露花、曼德拉根生长之地。亡灵徘徊。", "difficulty": 3, "color": Color(0.4, 0.4, 0.5)},
	3: {"name": "熔岩火山", "desc": "高危区。火焰葡萄、熔岩麦芽、爆裂椒等炽热材料，火蜥蜴横行。", "difficulty": 4, "color": Color(0.6, 0.2, 0.1)},
}

# 各区域散落采集材料池（与 LootTable.ZONE_MATERIAL_WEIGHTS 对齐，供地牢散落点使用）
const ZONE_SCATTER_MATERIALS: Dictionary = {
	0: {"blackberry": 15, "glowshroom": 12, "moongrass": 10, "goblin_nail": 8, "mistflower": 8, "wolfear_herb": 8, "pixie_dust": 5, "poison_berry": 4},
	1: {"deeprock_moss": 12, "black_rye_root": 12, "cyclops_beard": 8, "stalactite_sap": 8, "geothermal_ear": 8, "luminous_fern": 8, "quartz_dust": 5, "blindfish_jerky": 4},
	2: {"soulmint": 12, "moon_lily": 10, "mandrake_root": 8, "tomb_moss": 8, "ghost_tear": 8, "grave_truffle": 6, "bone_nectar": 5, "forgotten_ash": 4},
	3: {"firegrape": 12, "lava_malt": 10, "salamander_skin": 8, "ash_lotus": 8, "burst_pepper": 8, "charred_root": 8, "firebird_dust": 5, "lava_jelly": 3},
}

func set_zone(zone: int) -> void:
	selected_zone = clampi(zone, 0, 3)

func get_zone() -> int:
	return selected_zone

func get_zone_name(zone: int = -1) -> String:
	var z: int = zone if zone >= 0 else selected_zone
	return ZONE_META.get(z, {}).get("name", "未知区域")

func get_zone_desc(zone: int = -1) -> String:
	var z: int = zone if zone >= 0 else selected_zone
	return ZONE_META.get(z, {}).get("desc", "")

func get_zone_difficulty(zone: int = -1) -> int:
	var z: int = zone if zone >= 0 else selected_zone
	return ZONE_META.get(z, {}).get("difficulty", 1)

func get_zone_color(zone: int = -1) -> Color:
	var z: int = zone if zone >= 0 else selected_zone
	return ZONE_META.get(z, {}).get("color", Color.WHITE)

## 获取当前区域的散落材料池 {material_id: weight}
func get_scatter_materials(zone: int = -1) -> Dictionary:
	var z: int = zone if zone >= 0 else selected_zone
	return ZONE_SCATTER_MATERIALS.get(z, {}).duplicate()

func all_zones() -> Array:
	return [0, 1, 2, 3]
