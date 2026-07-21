extends Node
## 酿酒数据中枢（autoload: BrewingData）。
## 承载策划案《09-口味系统》《10-酿酒材料大表》《13-经典配方与酒谱大表》《12-满意度结算》
## 的全部底层风味数值，与旧 tavern_manager.gd 内的虚构材料完全隔离。

# ============================================================================
# 1. 16 种核心口味 (策划案 09-口味系统.md §1)
# 键名采用中文，便于策划核对；英文标识作为翻译键
# ============================================================================

enum Flavor {
	SWEETNESS,    # 甜美
	ACIDITY,      # 酸爽
	BITTERNESS,   # 苦涩
	SPICINESS,    # 辣口
	SALTY,        # 咸度
	AROMATIC,     # 香醇
	MALTINESS,    # 麦香
	FRUITY,       # 果香
	WARMTH,       # 温暖
	COOLNESS,     # 寒凉
	RICHNESS,     # 浓郁
	CRISPNESS,    # 清澈
	STENCH,       # 恶臭
	ROT,          # 腐败
	DECAYED,      # 死寂
	POISONOUS,    # 剧毒
}

# 中文口味名 → 枚举
const FLAVOR_NAME_TO_ENUM: Dictionary = {
	"甜美": Flavor.SWEETNESS, "酸爽": Flavor.ACIDITY, "苦涩": Flavor.BITTERNESS,
	"辣口": Flavor.SPICINESS, "咸度": Flavor.SALTY, "香醇": Flavor.AROMATIC,
	"麦香": Flavor.MALTINESS, "果香": Flavor.FRUITY, "温暖": Flavor.WARMTH,
	"寒凉": Flavor.COOLNESS, "浓郁": Flavor.RICHNESS, "清澈": Flavor.CRISPNESS,
	"恶臭": Flavor.STENCH, "腐败": Flavor.ROT, "死寂": Flavor.DECAYED,
	"剧毒": Flavor.POISONOUS,
}

# 枚举 → 中文键（数据存储与运行时统一用中文键，与策划案表格完全对齐）
const FLAVOR_ENUM_TO_NAME: Dictionary = {
	Flavor.SWEETNESS: "甜美", Flavor.ACIDITY: "酸爽", Flavor.BITTERNESS: "苦涩",
	Flavor.SPICINESS: "辣口", Flavor.SALTY: "咸度", Flavor.AROMATIC: "香醇",
	Flavor.MALTINESS: "麦香", Flavor.FRUITY: "果香", Flavor.WARMTH: "温暖",
	Flavor.COOLNESS: "寒凉", Flavor.RICHNESS: "浓郁", Flavor.CRISPNESS: "清澈",
	Flavor.STENCH: "恶臭", Flavor.ROT: "腐败", Flavor.DECAYED: "死寂",
	Flavor.POISONOUS: "剧毒",
}

# 翻译键（英文标识 → 本地化键）
const FLAVOR_TR_KEYS: Dictionary = {
	"甜美": "flavor_sweetness", "酸爽": "flavor_acidity", "苦涩": "flavor_bitterness",
	"辣口": "flavor_spiciness", "咸度": "flavor_salty", "香醇": "flavor_aromatic",
	"麦香": "flavor_maltiness", "果香": "flavor_fruity", "温暖": "flavor_warmth",
	"寒凉": "flavor_coolness", "浓郁": "flavor_richness", "清澈": "flavor_crispness",
	"恶臭": "flavor_stench", "腐败": "flavor_rot", "死寂": "flavor_decayed",
	"剧毒": "flavor_poisonous",
}

# ============================================================================
# 2. 40 种酿酒材料 (策划案 10-酿酒材料大表.md)
# 每条: id(英文标识), name(中文), zone(区域), flavors({口味: 强度})
# ============================================================================

# 区域枚举
enum Zone { DUNGEON, FOREST, CAVES, GRAVEYARD, VOLCANO, RUINS }

const ZONE_NAME_TO_ENUM: Dictionary = {
	"dungeon": Zone.DUNGEON, "forest": Zone.FOREST, "caves": Zone.CAVES, "graveyard": Zone.GRAVEYARD, "volcano": Zone.VOLCANO, "ruins": Zone.RUINS,
}

# 材料数据：键 = 英文标识（策划案表格第 3 列）
const MATERIALS_DB: Dictionary = {
 # ---- 地牢区 8 种（初始区域）----
 "rat_tail": {"name": "老鼠尾巴", "zone": Zone.DUNGEON, "flavors": {"恶臭": 2, "咸度": 1}},
 "moldy_bread": {"name": "发霉面包", "zone": Zone.DUNGEON, "flavors": {"腐败": 3, "麦香": 1}},
 "rusty_nail": {"name": "生锈铁钉", "zone": Zone.DUNGEON, "flavors": {"咸度": 2, "酸爽": 1}},
 "dungeon_moss": {"name": "地牢苔", "zone": Zone.DUNGEON, "flavors": {"苦涩": 3, "寒凉": 1}},
 "bone_shard": {"name": "碎骨片", "zone": Zone.DUNGEON, "flavors": {"死寂": 2, "咸度": 1}},
 "stale_water": {"name": "陈腐积水", "zone": Zone.DUNGEON, "flavors": {"腐败": 2, "苦涩": 2}},
 "prison_lichen": {"name": "囚室地衣", "zone": Zone.DUNGEON, "flavors": {"苦涩": 3, "寒凉": 1}},
 "cellar_mushroom": {"name": "地窖蘑菇", "zone": Zone.DUNGEON, "flavors": {"浓郁": 2, "腐败": 1}},
	# ---- 森林区 10 种 ----
	"blackberry": {"name": "黑莓", "zone": Zone.FOREST, "flavors": {"果香": 3, "甜美": 2}},
	"bloodvine": {"name": "血藤", "zone": Zone.FOREST, "flavors": {"辣口": 3, "浓郁": 2, "温暖": 2, "咸度": 1}},
	"glowshroom": {"name": "蓝光菇", "zone": Zone.FOREST, "flavors": {"寒凉": 3, "清澈": 2, "酸爽": 1}},
	"moongrass": {"name": "月光草", "zone": Zone.FOREST, "flavors": {"香醇": 3, "温暖": 2, "甜美": 1}},
	"goblin_nail": {"name": "哥布林指甲", "zone": Zone.FOREST, "flavors": {"恶臭": 4, "酸爽": 2}},
	"mistflower": {"name": "迷雾花", "zone": Zone.FOREST, "flavors": {"清澈": 3, "香醇": 2, "寒凉": 1}},
	"wolfear_herb": {"name": "狼耳草", "zone": Zone.FOREST, "flavors": {"酸爽": 3, "温暖": 2, "辣口": 1}},
	"poison_berry": {"name": "剧毒藤莓", "zone": Zone.FOREST, "flavors": {"剧毒": 4, "酸爽": 3}},
	"oak_lichen": {"name": "橡木地衣", "zone": Zone.FOREST, "flavors": {"腐败": 3, "清澈": 2}},
	"pixie_dust": {"name": "妖精粉尘", "zone": Zone.FOREST, "flavors": {"甜美": 4, "香醇": 3, "果香": 2, "温暖": 1}},
	# ---- 洞窟区 10 种 ----
	"deeprock_moss": {"name": "深岩苔藓", "zone": Zone.CAVES, "flavors": {"苦涩": 3, "寒凉": 2}},
	"black_rye_root": {"name": "黑麦根", "zone": Zone.CAVES, "flavors": {"麦香": 3, "浓郁": 2}},
	"cyclops_beard": {"name": "独眼巨人的胡须", "zone": Zone.CAVES, "flavors": {"麦香": 3, "苦涩": 2, "咸度": 1}},
	"stalactite_sap": {"name": "钟乳石髓", "zone": Zone.CAVES, "flavors": {"咸度": 3, "清澈": 3}},
	"blindfish_jerky": {"name": "盲鱼干", "zone": Zone.CAVES, "flavors": {"恶臭": 3, "咸度": 2, "腐败": 2}},
	"geothermal_ear": {"name": "地热木耳", "zone": Zone.CAVES, "flavors": {"温暖": 3, "浓郁": 2, "咸度": 1}},
	"guano_crystal": {"name": "蝙蝠粪石", "zone": Zone.CAVES, "flavors": {"腐败": 3, "咸度": 2, "恶臭": 2}},
	"rockworm_slime": {"name": "碎岩虫粘液", "zone": Zone.CAVES, "flavors": {"浓郁": 4, "咸度": 2, "剧毒": 1}},
	"luminous_fern": {"name": "荧光蕨", "zone": Zone.CAVES, "flavors": {"酸爽": 3, "寒凉": 2, "清澈": 1}},
	"quartz_dust": {"name": "石英晶粉", "zone": Zone.CAVES, "flavors": {"寒凉": 4, "清澈": 2}},
	# ---- 墓园区 10 种 ----
	"forgotten_ash": {"name": "无名者的骨灰", "zone": Zone.GRAVEYARD, "flavors": {"苦涩": 4, "浓郁": 2}},
	"soulmint": {"name": "灵魂薄荷", "zone": Zone.GRAVEYARD, "flavors": {"寒凉": 3, "香醇": 2, "酸爽": 1}},
	"moon_lily": {"name": "月露花", "zone": Zone.GRAVEYARD, "flavors": {"死寂": 3, "香醇": 2, "清澈": 1}},
	"mandrake_root": {"name": "尖叫曼德拉根", "zone": Zone.GRAVEYARD, "flavors": {"辣口": 3, "苦涩": 3, "浓郁": 2}},
	"tomb_moss": {"name": "墓穴苔藓", "zone": Zone.GRAVEYARD, "flavors": {"腐败": 3, "死寂": 2, "恶臭": 1}},
	"ghost_tear": {"name": "亡灵泪滴", "zone": Zone.GRAVEYARD, "flavors": {"酸爽": 4, "清澈": 3}},
	"wraith_ash": {"name": "怨念灰烬", "zone": Zone.GRAVEYARD, "flavors": {"死寂": 3, "浓郁": 3, "寒凉": 1}},
	"shroud_shred": {"name": "寿衣碎片", "zone": Zone.GRAVEYARD, "flavors": {"腐败": 4, "恶臭": 3, "死寂": 2, "苦涩": 1}},
	"grave_truffle": {"name": "坟地黑松露", "zone": Zone.GRAVEYARD, "flavors": {"浓郁": 3, "香醇": 2, "死寂": 1}},
	"bone_nectar": {"name": "枯骨花蜜", "zone": Zone.GRAVEYARD, "flavors": {"甜美": 3, "死寂": 2, "浓郁": 1}},
	# ---- 火山区 10 种 ----
	"firegrape": {"name": "火焰葡萄", "zone": Zone.VOLCANO, "flavors": {"辣口": 3, "果香": 2, "酸爽": 1}},
	"lava_malt": {"name": "熔岩麦芽", "zone": Zone.VOLCANO, "flavors": {"麦香": 3, "温暖": 3, "浓郁": 1}},
	"salamander_skin": {"name": "火蜥蜴的蜕皮", "zone": Zone.VOLCANO, "flavors": {"温暖": 3, "苦涩": 2, "辣口": 1}},
	"ash_lotus": {"name": "灰烬莲花", "zone": Zone.VOLCANO, "flavors": {"香醇": 3, "温暖": 2, "死寂": 1}},
	"lava_jet": {"name": "熔岩煤精", "zone": Zone.VOLCANO, "flavors": {"浓郁": 4, "温暖": 2}},
	"burst_pepper": {"name": "爆裂椒", "zone": Zone.VOLCANO, "flavors": {"辣口": 4}},
	"sulfur_flower": {"name": "硫磺花", "zone": Zone.VOLCANO, "flavors": {"恶臭": 3, "辣口": 2, "腐败": 1}},
	"charred_root": {"name": "焦木炭根", "zone": Zone.VOLCANO, "flavors": {"麦香": 2, "苦涩": 2, "温暖": 1}},
	"lava_jelly": {"name": "熔岩蜂王浆", "zone": Zone.VOLCANO, "flavors": {"甜美": 3, "温暖": 3, "浓郁": 2, "香醇": 1}},
	"firebird_dust": {"name": "烈焰鸟羽灰", "zone": Zone.VOLCANO, "flavors": {"香醇": 3, "辣口": 2, "清澈": 1}},
	# ---- 古代遗迹区 8 种 ----
	"crystal_tear": {"name": "水晶泪滴", "zone": Zone.RUINS, "flavors": {"清澈": 3, "寒凉": 2, "甜美": 1}},
	"ancient_rune": {"name": "远古符文碎", "zone": Zone.RUINS, "flavors": {"香醇": 3, "死寂": 2, "浓郁": 1}},
	"starlight_moss": {"name": "星光苔", "zone": Zone.RUINS, "flavors": {"寒凉": 3, "清澈": 2, "酸爽": 1}},
	"ethereal_essence": {"name": "灵界精华", "zone": Zone.RUINS, "flavors": {"甜美": 3, "香醇": 3, "清澈": 2}},
	"phantom_petal": {"name": "幻影花瓣", "zone": Zone.RUINS, "flavors": {"香醇": 4, "死寂": 2, "寒凉": 1}},
	"ruin_honey": {"name": "遗迹花蜜", "zone": Zone.RUINS, "flavors": {"甜美": 4, "浓郁": 2, "温暖": 1}},
	"ghost_mushroom": {"name": "幽灵菇", "zone": Zone.RUINS, "flavors": {"寒凉": 3, "死寂": 3, "清澈": 2}},
	"arcane_dust": {"name": "奥术粉尘", "zone": Zone.RUINS, "flavors": {"酸爽": 3, "清澈": 3, "香醇": 2}},
}

# ============================================================================
# 3. 10 种经典酒谱 (策划案 13-经典配方与酒谱大表.md)
# 每条: id, name(中文), target_audience(受众), ingredients({材料id: 数量}),
#        expected_flavors(策划案标定的合成口味，用于校验), price(人类标价/None)
# ============================================================================

const RECIPES_DB: Dictionary = {
	"glowberry_juice": {
		"name": "亮莓果汁", "audience": ["human", "elf"],
		"ingredients": {"blackberry": 2, "glowshroom": 1, "pixie_dust": 1},
		"expected_flavors": {"甜美": 8, "果香": 8, "寒凉": 3, "清澈": 2, "香醇": 3, "酸爽": 1, "温暖": 1},
		"price": 30,
	},
	"moonlight_ale": {
		"name": "月光艾尔啤酒", "audience": ["human", "minotaur"],
		"ingredients": {"black_rye_root": 2, "moongrass": 1, "mistflower": 1},
		"expected_flavors": {"麦香": 6, "浓郁": 4, "香醇": 5, "温暖": 2, "甜美": 1, "清澈": 3, "寒凉": 1},
		"price": 45,
	},
	"goblin_sweet_rot_mash": {
		"name": "哥布林甜腐浆", "audience": ["goblin"],
		"ingredients": {"goblin_nail": 2, "oak_lichen": 1, "pixie_dust": 1},
		"expected_flavors": {"恶臭": 8, "酸爽": 4, "腐败": 3, "清澈": 2, "甜美": 4, "香醇": 3, "果香": 2, "温暖": 1},
		"price": null,
	},
	"blindfish_rot_wine": {
		"name": "盲鱼霉烂酒", "audience": ["goblin"],
		"ingredients": {"blindfish_jerky": 2, "guano_crystal": 1, "blackberry": 1},
		"expected_flavors": {"恶臭": 8, "咸度": 6, "腐败": 7, "果香": 3, "甜美": 2},
		"price": null,
	},
	"heavyrock_charred_stout": {
		"name": "重岩焦香黑啤", "audience": ["minotaur"],
		"ingredients": {"black_rye_root": 2, "geothermal_ear": 1, "rockworm_slime": 1},
		"expected_flavors": {"麦香": 6, "浓郁": 10, "温暖": 3, "咸度": 3, "剧毒": 1},
		"price": null,
	},
	"magma_spicy_spirits": {
		"name": "岩浆燥辣烈酒", "audience": ["cyclops"],
		"ingredients": {"burst_pepper": 2, "firegrape": 1, "lava_malt": 1},
		"expected_flavors": {"辣口": 11, "温暖": 3, "果香": 2, "酸爽": 1, "麦香": 3, "浓郁": 1},
		"price": null,
	},
	"sulfur_flame_mash": {
		"name": "硫磺烈焰原浆", "audience": ["cyclops"],
		"ingredients": {"sulfur_flower": 2, "salamander_skin": 1, "charred_root": 1},
		"expected_flavors": {"恶臭": 6, "辣口": 5, "温暖": 4, "苦涩": 4, "腐败": 2, "麦香": 2},
		"price": null,
	},
	"ice_coffin_undead_call": {
		"name": "冰棺亡灵引", "audience": ["ghost"],
		"ingredients": {"moon_lily": 2, "soulmint": 1, "ghost_tear": 1},
		"expected_flavors": {"死寂": 6, "寒凉": 3, "香醇": 6, "清澈": 5, "酸爽": 5},
		"price": null,
	},
	"moonlily_honey_mead": {
		"name": "月露清醇蜜酒", "audience": ["elf"],
		"ingredients": {"moon_lily": 2, "pixie_dust": 1, "bone_nectar": 1},
		"expected_flavors": {"死寂": 8, "香醇": 7, "甜美": 7, "果香": 2, "清澈": 2, "温暖": 1, "浓郁": 1},
		"price": null,
	},
	"lava_royal_whiskey": {
		"name": "熔岩蜂皇威士忌", "audience": ["human", "minotaur", "elf"],
		"ingredients": {"lava_jelly": 2, "firebird_dust": 1, "geothermal_ear": 1},
		"expected_flavors": {"温暖": 9, "甜美": 6, "浓郁": 6, "香醇": 5, "辣口": 2, "咸度": 1, "清澈": 1},
		"price": 80,
	},
}

# ============================================================================
# 4. 种族口味期望阈值矩阵 (策划案 09-口味系统.md §2.1)
# 每条: liked({喜爱口味: 期望阈值}), hated([一票否决口味])
# ============================================================================

const RACE_PREFERENCES: Dictionary = {
	"human": {
		"liked": {"麦香": 2, "甜美": 1},
		"hated": ["恶臭", "腐败", "死寂", "剧毒"],
	},
	"goblin": {
		"liked": {"腐败": 2, "甜美": 1},
		"hated": ["苦涩"],
	},
	"minotaur": {
		"liked": {"麦香": 3, "浓郁": 2},
		"hated": ["酸爽"],
	},
	"cyclops": {
		"liked": {"辣口": 3, "温暖": 2},
		"hated": ["甜美"],
	},
	"ghost": {
		"liked": {"死寂": 3, "寒凉": 2},
		"hated": ["温暖"],
	},
	"elf": {
		"liked": {"香醇": 3, "果香": 2},
		"hated": ["恶臭", "腐败"],
	},
}

# ============================================================================
# 5. 运行时工具函数
# ============================================================================

## 按材料组合加算合成口味。输入 {material_id: count}，返回 {口味: 总强度}
static func compute_brew_flavors(ingredients: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for mat_id in ingredients:
		var count: int = ingredients[mat_id]
		var mat: Dictionary = MATERIALS_DB.get(mat_id, {})
		if mat.is_empty():
			continue
		for flavor_name in mat.flavors:
			var intensity: int = mat.flavors[flavor_name] * count
			result[flavor_name] = result.get(flavor_name, 0) + intensity
	return result

## 满意度极简判定（策划案 09 §2）：喜爱口味全达标 && 讨厌口味全为 0
## 返回 true=满意/喝爽，false=不满意
static func evaluate_satisfaction(brew_flavors: Dictionary, race_id: String) -> bool:
	var pref: Dictionary = RACE_PREFERENCES.get(race_id, {})
	if pref.is_empty():
		return false
	# 喜爱口味达标判定
	for flavor_name in pref.liked:
		var threshold: int = pref.liked[flavor_name]
		if brew_flavors.get(flavor_name, 0) < threshold:
			return false
	# 讨厌口味一票否决
	for hated_flavor in pref.hated:
		if brew_flavors.get(hated_flavor, 0) > 0:
			return false
	return true

## 经典配方匹配：若材料组合完全匹配某经典酒谱，返回 recipe_id，否则返回 ""
static func match_recipe(ingredients: Dictionary) -> String:
	for recipe_id in RECIPES_DB:
		var recipe: Dictionary = RECIPES_DB[recipe_id]
		var recipe_ings: Dictionary = recipe.ingredients
		if recipe_ings.size() != ingredients.size():
			continue
		var matched := true
		for mat_id in recipe_ings:
			if ingredients.get(mat_id, 0) != recipe_ings[mat_id]:
				matched = false
				break
		if matched:
			return recipe_id
	return ""

## 获取材料显示名（游戏内与图鉴一致）。
## 解析顺序：MATERIALS_DB → MaterialModelRegistry(name_zh) → 英文标识美化。
static func get_material_name(mat_id: String) -> String:
	if mat_id.is_empty():
		return ""
	var mat: Dictionary = MATERIALS_DB.get(mat_id, {})
	if not mat.is_empty():
		return TranslationServer.translate(String(mat.get("name", mat_id)))
	# 怪物掉落等：仅有体素模型清单时仍要本地化（只读 entry，避免与 get_display_name 循环）
	var registry: GDScript = load("res://data/material_model_registry.gd") as GDScript
	if registry != null:
		var entry: Dictionary = registry.call("get_entry", mat_id)
		if not entry.is_empty():
			var zh := String(entry.get("name_zh", ""))
			if not zh.is_empty():
				return TranslationServer.translate(zh)
	return TranslationServer.translate(mat_id.replace("_", " ").capitalize())

## 获取酒谱中文名
static func get_recipe_name(recipe_id: String) -> String:
	var recipe: Dictionary = RECIPES_DB.get(recipe_id, {})
	return TranslationServer.translate(recipe.get("name", recipe_id))
