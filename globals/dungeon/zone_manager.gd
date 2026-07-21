extends Node
## 区域选择管理器（autoload: ZoneManager）。
## 保存玩家选定的探险区域，供 procedural_dungeon 读取以配置宝箱 zone 与散落材料池。
## 同时承载六区的显示名/描述/推荐等级等元数据，供区域选择 UI 渲染。
##
## 散落材料池已统一至 LootTable.ZONE_SCATTER_WEIGHTS（单一数据源），
## 本模块通过 get_scatter_materials() 委托查询。

const Service := preload("res://globals/core/service.gd")

# 当前选定区域（BrewingData.Zone 枚举值），-1 表示未选定
var selected_zone: int = 0

# 六区元数据（地牢/森林/洞窟/墓园/火山/古代遗迹）
const ZONE_META: Dictionary = {
	0: {"name": "幽暗地牢", "desc": "初始区域。潮湿的石砌地牢，老鼠横行，适合新手熟悉战斗与采集。", "difficulty": 1, "color": Color(0.3, 0.25, 0.2)},
	1: {"name": "寂静之森", "desc": "新手友好区。盛产黑莓、蓝光菇、月光草等温和材料。", "difficulty": 2, "color": Color(0.2, 0.5, 0.2)},
	2: {"name": "深邃洞窟", "desc": "盛产黑麦根、深岩苔藓、独眼巨人胡须。盲鱼与碎岩虫出没。", "difficulty": 3, "color": Color(0.3, 0.3, 0.4)},
	3: {"name": "荒芜墓园", "desc": "灵魂薄荷、月露花、曼德拉根生长之地。亡灵徘徊。", "difficulty": 4, "color": Color(0.4, 0.4, 0.5)},
	4: {"name": "熔岩火山", "desc": "高危区。火焰葡萄、熔岩麦芽、爆裂椒等炽热材料，火蜥蜴横行。", "difficulty": 5, "color": Color(0.6, 0.2, 0.1)},
	5: {"name": "古代遗迹", "desc": "极危区。水晶泪滴、远古符文碎、星光苔等灵界材料。幽灵守卫徘徊。", "difficulty": 6, "color": Color(0.35, 0.25, 0.55)},
}

func set_zone(zone: int) -> void:
	selected_zone = clampi(zone, 0, 5)

func get_zone() -> int:
	return selected_zone

func get_zone_name(zone: int = -1) -> String:
	var z: int = zone if zone >= 0 else selected_zone
	return TranslationServer.translate(ZONE_META.get(z, {}).get("name", "未知区域"))

func get_zone_desc(zone: int = -1) -> String:
	var z: int = zone if zone >= 0 else selected_zone
	return TranslationServer.translate(ZONE_META.get(z, {}).get("desc", ""))

func get_zone_difficulty(zone: int = -1) -> int:
	var z: int = zone if zone >= 0 else selected_zone
	return ZONE_META.get(z, {}).get("difficulty", 1)

func get_zone_color(zone: int = -1) -> Color:
	var z: int = zone if zone >= 0 else selected_zone
	return ZONE_META.get(z, {}).get("color", Color.WHITE)

## 获取当前区域的散落材料池 {material_id: weight}。
## 委托 LootTable.get_scatter_materials()，确保区域材料映射单一数据源。
func get_scatter_materials(zone: int = -1) -> Dictionary:
	var z: int = zone if zone >= 0 else selected_zone
	var lt: Node = Service.loot_table()
	if lt != null and lt.has_method("get_scatter_materials"):
		return lt.get_scatter_materials(z)
	return {}

func all_zones() -> Array:
	return [0, 1, 2, 3, 4, 5]
