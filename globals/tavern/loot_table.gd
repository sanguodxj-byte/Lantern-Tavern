extends Node
## 宝箱掉落表（autoload: LootTable）。
## 统一管理地图宝箱的武器与材料掉落，对接：
## - WeaponRegistry：按 tier 阶位（一/二/三阶）随机抽取武器
## - BrewingData：从 40 种正式酿酒材料按区域权重抽取
## 替代 chest.gd 内的旧虚构材料池（wild_glowcap 等）。

# 用 preload 脚本类访问静态常量（autoload 名在编译期不可用）
const BD := preload("res://globals/tavern/brewing_data.gd")
const RD := preload("res://globals/combat/rune_data.gd")

# 掉落概率配置（策划案宝箱设计：高品质稀有）
const WEAPON_DROP_CHANCE: float = 1.0       # 100% 掉一把武器
const TIER_WEIGHTS: Dictionary = {
	0: 60.0,  # 一阶 60%
	1: 30.0,  # 二阶 30%
	2: 10.0,  # 三阶 10%
}
const MATERIAL_DROP_MIN: int = 2
const MATERIAL_DROP_MAX: int = 3
const RUNE_DROP_CHANCE_CHEST: float = 0.35

# 区域材料权重（策划案 10：宝箱应掉落当前探索区域的材料为主）
# zone → {material_id: weight}；权重为 0 表示该区域不掉此材料
const ZONE_MATERIAL_WEIGHTS: Dictionary = {
 BD.Zone.DUNGEON: {
  "rat_tail": 3, "moldy_bread": 3, "rusty_nail": 2,
  "dungeon_moss": 2, "bone_shard": 2, "stale_water": 1,
 },
 BD.Zone.FOREST: {
		"blackberry": 3, "glowshroom": 3, "moongrass": 2, "goblin_nail": 2,
		"mistflower": 2, "wolfear_herb": 2, "pixie_dust": 1,
	},
	BD.Zone.CAVES: {
		"deeprock_moss": 3, "black_rye_root": 3, "cyclops_beard": 2,
		"stalactite_sap": 2, "geothermal_ear": 2, "luminous_fern": 2, "quartz_dust": 1,
	},
	BD.Zone.GRAVEYARD: {
		"soulmint": 3, "moon_lily": 3, "mandrake_root": 2, "tomb_moss": 2,
		"ghost_tear": 2, "grave_truffle": 2, "bone_nectar": 1,
	},
	BD.Zone.VOLCANO: {
	 "firegrape": 3, "lava_malt": 3, "salamander_skin": 2,
	 "ash_lotus": 2, "burst_pepper": 2, "charred_root": 2, "firebird_dust": 1,
	},
	BD.Zone.RUINS: {
	 "crystal_tear": 3, "ancient_rune": 3, "starlight_moss": 2,
	 "ethereal_essence": 2, "phantom_petal": 2, "ruin_honey": 2, "arcane_dust": 1,
	},
}

# 跨区域稀有材料（任何区域宝箱小概率掉落）
const RARE_CROSS_ZONE_MATERIALS: Dictionary = {
	"poison_berry": 1, "oak_lichen": 1, "blindfish_jerky": 1, "guano_crystal": 1,
	"rockworm_slime": 1, "forgotten_ash": 1, "wraith_ash": 1, "shroud_shred": 1,
	"lava_jet": 1, "sulfur_flower": 1, "lava_jelly": 1,
}
const RARE_CROSS_ZONE_CHANCE: float = 0.15  # 15% 概率从稀有池抽

# 各区域散落采集材料池（地牢地面散落点使用，比宝箱池种类更多、权重更高）
# 单一数据源：ZoneManager.get_scatter_materials() 委托此常量。
const ZONE_SCATTER_WEIGHTS: Dictionary = {
	0: {"rat_tail": 15, "moldy_bread": 12, "rusty_nail": 10, "dungeon_moss": 10, "bone_shard": 8, "stale_water": 8, "prison_lichen": 5, "cellar_mushroom": 4},
	1: {"blackberry": 15, "glowshroom": 12, "moongrass": 10, "goblin_nail": 8, "mistflower": 8, "wolfear_herb": 8, "pixie_dust": 5, "poison_berry": 4},
	2: {"deeprock_moss": 12, "black_rye_root": 12, "cyclops_beard": 8, "stalactite_sap": 8, "geothermal_ear": 8, "luminous_fern": 8, "quartz_dust": 5, "blindfish_jerky": 4},
	3: {"soulmint": 12, "moon_lily": 10, "mandrake_root": 8, "tomb_moss": 8, "ghost_tear": 8, "grave_truffle": 6, "bone_nectar": 5, "forgotten_ash": 4},
	4: {"firegrape": 12, "lava_malt": 10, "salamander_skin": 8, "ash_lotus": 8, "burst_pepper": 8, "charred_root": 8, "firebird_dust": 5, "lava_jelly": 3},
	5: {"crystal_tear": 12, "ancient_rune": 10, "starlight_moss": 10, "ethereal_essence": 8, "phantom_petal": 8, "ruin_honey": 6, "ghost_mushroom": 5, "arcane_dust": 4},
}

# ============================================================================
# 散落材料池查询（单一数据源）
# ============================================================================

## 获取指定区域的散落材料池 {material_id: weight}。
## ZoneManager.get_scatter_materials() 委托此方法，确保区域材料映射只在此维护。
func get_scatter_materials(zone: int) -> Dictionary:
	return ZONE_SCATTER_WEIGHTS.get(zone, {}).duplicate()

# ============================================================================
# 武器掉落
# ============================================================================

## 抽取一件装备。返回 {id, tier_index, tier_name, weapon_data}，空字典表示注册表未就绪。
## 包含武器、盾牌、防具和饰品，按类别权重随机抽取。
## 装备属性按阶位 (tier) 正确应用，并附带随机词缀。
## 区域对应的阶位权重映射（策划案 33：阶位与层级深度强相关，前期禁止高阶）
const ZONE_TIER_WEIGHTS: Dictionary = {
	0: {0: 100.0, 1: 0.0, 2: 0.0},   # Zone 0 (地牢一层): 100% 只能生成一阶 Tier 0
	1: {0: 80.0, 1: 20.0, 2: 0.0},   # Zone 1 (森林): 80% 一阶，20% 二阶
	2: {0: 50.0, 1: 50.0, 2: 0.0},   # Zone 2 (洞穴): 50% 一阶，50% 二阶
	3: {0: 20.0, 1: 60.0, 2: 20.0},  # Zone 3 (墓园): 解锁 20% 三阶 Tier 2
	4: {0: 0.0, 1: 50.0, 2: 50.0},   # Zone 4 (火山): 50% 二阶，50% 三阶
	5: {0: 0.0, 1: 20.0, 2: 80.0},   # Zone 5 (废墟): 80% 三阶 Tier 2
}

## 抽取一件装备（常用于环境宝箱或废迹生成）。
## zone: 地牢探索区域深度 (BrewingData.Zone，默认为 0 地牢一层)。
## 装备阶位严格由 zone 限制，绝不可能在前期爆出高阶神兵。
func roll_weapon(zone: int = 0) -> Dictionary:
	var wr: Node = _get_weapon_registry()
	if wr == null:
		return {}
	# 构建掉落池：武器 + 盾牌 + 防具 + 饰品
	var categories: Dictionary = wr.get_by_category()
	var pool: Array[String] = []
	for cat in ["weapons", "shields", "armor_light", "armor_heavy", "accessories"]:
		if categories.has(cat):
			pool.append_array(categories[cat])
	if pool.is_empty():
		return {}
	var pick_id: String = pool[randi() % pool.size()]
	var tiers: Array = wr.get_tiers(pick_id)
	var tier_idx: int = _pick_tier_index_for_zone(zone, tiers.size())
	# 使用 build_weapon_data_with_tier 创建独立副本并应用阶位属性
	var weapon_data = wr.build_weapon_data_with_tier(pick_id, tier_idx)
	if weapon_data == null:
		return {}
	var tier_name: String = weapon_data.tier_name
	if tier_name.is_empty():
		tier_name = wr.get_display_name(pick_id)
	# Roll 词缀并应用
	var affix_system: Node = _get_affix_system()
	if affix_system != null:
		var affixes: Array[String] = affix_system.roll_affixes()
		if not affixes.is_empty():
			affix_system.apply_affixes(weapon_data, affixes)
	return {
		"id": pick_id,
		"tier_index": tier_idx,
		"tier_name": tier_name,
		"weapon_data": weapon_data,
	}

func _pick_tier_index_for_zone(zone: int, max_tiers: int) -> int:
	if max_tiers <= 0:
		return 0
	var weights: Dictionary = ZONE_TIER_WEIGHTS.get(zone, ZONE_TIER_WEIGHTS[0])
	var total: float = 0.0
	for i in range(min(max_tiers, 3)):
		total += weights.get(i, 0.0)
	if total <= 0.0:
		return 0
	var roll: float = randf() * total
	var cumul: float = 0.0
	for i in range(min(max_tiers, 3)):
		cumul += weights.get(i, 0.0)
		if roll <= cumul:
			return i
	return 0

# ============================================================================
# 材料掉落
# ============================================================================

## 抽取 2-3 个材料。zone 为 BrewingData.Zone 枚举值。
## 返回 [{material_id, name}, ...]
func roll_materials(zone: int) -> Array:
	var result: Array = []
	var count: int = randi_range(MATERIAL_DROP_MIN, MATERIAL_DROP_MAX)
	for i in range(count):
		var mat_id: String = _pick_material(zone)
		if mat_id == "":
			continue
		result.append({"material_id": mat_id, "name": BD.get_material_name(mat_id)})
	return result

func _pick_material(zone: int) -> String:
	# 15% 概率从跨区域稀有池抽
	if randf() < RARE_CROSS_ZONE_CHANCE:
		var rare_keys: Array = RARE_CROSS_ZONE_MATERIALS.keys()
		return rare_keys[randi() % rare_keys.size()]
	# 85% 从当前区域权重池抽
	var weights: Dictionary = ZONE_MATERIAL_WEIGHTS.get(zone, {})
	if weights.is_empty():
		# 区域无配置则从全部材料随机
		var all_ids: Array = BD.MATERIALS_DB.keys()
		return all_ids[randi() % all_ids.size()]
	var total: float = 0.0
	for mat_id in weights:
		total += weights[mat_id]
	var roll: float = randf() * total
	var cumul: float = 0.0
	for mat_id in weights:
		cumul += weights[mat_id]
		if roll <= cumul:
			return mat_id
	# fallback：取第一个
	return weights.keys()[0]

# ============================================================================
# 完整掉落包
# ============================================================================

class LootDrop:
	var weapon: Dictionary = {}      # roll_weapon() 结果
	var materials: Array = []         # roll_materials() 结果
	var runes: Array = []             # RuneData 结果

## 生成完整掉落包。zone 为 BrewingData.Zone 枚举值。
func generate_loot(zone: int) -> LootDrop:
	var drop := LootDrop.new()
	if randf() < WEAPON_DROP_CHANCE:
		drop.weapon = roll_weapon()
	drop.materials = roll_materials(zone)
	if randf() < RUNE_DROP_CHANCE_CHEST:
		var rune := roll_rune("chest")
		if not rune.is_empty():
			drop.runes.append(rune)
	return drop

func roll_rune(source: String = "chest") -> Dictionary:
	return RD.roll_rune(source)

# ============================================================================
# 工具
# ============================================================================

func _get_weapon_registry() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("WeaponRegistry")

func _get_affix_system() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("AffixSystem")
