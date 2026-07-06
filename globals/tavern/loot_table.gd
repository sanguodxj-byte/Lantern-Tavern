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

# ============================================================================
# 武器掉落
# ============================================================================

## 抽取一件装备。返回 {id, tier_index, tier_name, weapon_data}，空字典表示注册表未就绪。
## 包含武器、盾牌、防具和饰品，按类别权重随机抽取。
## 装备属性按阶位 (tier) 正确应用，并附带随机词缀。
func roll_weapon() -> Dictionary:
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
	var tier_idx: int = _pick_tier_index(tiers.size())
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

func _pick_tier_index(max_tiers: int) -> int:
	if max_tiers <= 0:
		return 0
	# 按权重抽取 tier
	var total: float = 0.0
	for i in range(min(max_tiers, 3)):
		total += TIER_WEIGHTS.get(i, 0.0)
	var roll: float = randf() * total
	var cumul: float = 0.0
	for i in range(min(max_tiers, 3)):
		cumul += TIER_WEIGHTS.get(i, 0.0)
		if roll <= cumul:
			return i
	return min(max_tiers - 1, 2)

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
