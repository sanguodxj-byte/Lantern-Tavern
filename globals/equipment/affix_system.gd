extends Node
## 装备词缀系统（autoload: AffixSystem）。
## 实现策划案《06-装备系统》§3 战术词缀系统：
## - 6 个正向词缀 + 6 个负向词缀
## - 每件装备最多 Roll 出 2 个词缀（0/1/2 个，2 个时必为 1 正 1 负）
## - 词缀属性修正直接应用到 WeaponData 实例

# ============================================================================
# 1. 词缀定义（策划案 06 §3.1 + §3.2）
# ============================================================================

const POSITIVE_AFFIXES: Dictionary = {
	"sharp": {
		"name_zh": "锋利的",
		"damage_mult_add": 0.03,   # 物理伤害 +3%
		"crit_bonus_add": 1.0,     # 暴击率 +1%
	},
	"flamereached": {
		"name_zh": "灼热的",
		"damage_mult_add": 0.03,   # 伤害 +3%
		"element_type": "fire",    # 附加微量火元素
	},
	"frostbound": {
		"name_zh": "霜冻的",
		"damage_mult_add": 0.02,   # 伤害 +2%
		"element_type": "ice",     # 附加微量冰元素
	},
	"lightning_touched": {
		"name_zh": "闪雷的",
		"damage_mult_add": 0.02,   # 伤害 +2%
		"element_type": "lightning",
	},
	"venomous": {
		"name_zh": "淬毒的",
		"damage_mult_add": 0.02,   # 伤害 +2%
		"element_type": "poison",
	},
	"bloodthirsty": {
		"name_zh": "嗜血的",
		"lifesteal_percent": 0.5,  # 微量吸血 +0.5%
	},
	"swift": {
		"name_zh": "疾风的",
		"attack_speed_mult": 1.03, # 攻速 +3%
	},
	"lightweight": {
		"name_zh": "轻盈的",
		"carry_weight_mult_mul": 0.90, # 负重扣减 10%
	},
	"focused": {
		"name_zh": "专注的",
		"crit_bonus_add": 3.0,     # 暴击率 +3%
	},
	"furious": {
		"name_zh": "狂暴的",
		"crit_bonus_add": 2.0,     # 暴击率 +2%
		"crit_damage_bonus_add": 4.0,   # 暴击伤害 +4%
	},
	"sturdy": {
		"name_zh": "坚固的",
		"armor_phys_def_add": 1,   # 物理防御 +1
	},
	"titan": {
		"name_zh": "泰坦的",
		"reach_mult": 1.05,        # 打击半径 +5%
	},
	"blessed": {
		"name_zh": "赐福的",
		"damage_mult_add": 0.04,   # 全伤害 +4%
		"crit_bonus_add": 2.0,     # 暴击率 +2%
		"is_blessed": true,
	},
	"shining": {
		"name_zh": "辉闪的",
		"light_radius_add": 1.0,   # 照亮半径 +1 米
		"spell_def_add": 0.02,     # 法力受击防损 +2%
	},
}

const NEGATIVE_AFFIXES: Dictionary = {
	"rusty": {
		"name_zh": "生锈的",
		"damage_mult_add": -0.04,  # 物理伤害 -4%
	},
	"brittle": {
		"name_zh": "易碎的",
		"degrade_rate_mult": 1.15, # 磨损率 +15%
	},
	"dull": {
		"name_zh": "钝化的",
		"crit_bonus_add": -3.0,    # 暴击率 -3%
	},
	"clunky": {
		"name_zh": "笨重的",
		"carry_weight_mult_mul": 1.10, # 负重增加 10%
	},
	"worn": {
		"name_zh": "磨损的",
		"crit_bonus_add": -2.0,    # 暴击率 -2%
	},
	"inferior": {
		"name_zh": "劣质的",
		"crit_bonus_add": -2.0,    # 暴击率 -2%
		"max_condition_mult": 0.92, # 最大耐久 -8%
	},
	"cracked": {
		"name_zh": "碎裂的",
		"armor_phys_def_add": -1,  # 物理防御 -1
	},
	"cursed_vampiric": {
		"name_zh": "诅咒·吸髓",
		"damage_mult_add": 0.05,   # 伤害 +5%
		"self_hp_drain_per_hit": 1, # 攻击挥刀扣除自身 1 点生命值
		"is_cursed": true,          # 诅咒锁定槽位
	},
	"cursed_sloth": {
		"name_zh": "诅咒·迟钝",
		"attack_speed_mult": 0.95, # 攻速 -5%
		"is_cursed": true,          # 诅咒锁定槽位
	},
	"cursed_weight": {
		"name_zh": "诅咒·沉重",
		"carry_weight_mult_mul": 1.15, # 负重 +15%
		"move_speed_mult": 0.97,    # 移速 -3%
		"is_cursed": true,          # 诅咒锁定槽位
	},
}

const SUFFIXES: Dictionary = {
	"of_slaying": {
		"name_zh": "之 斩杀",
		"low_hp_execute_mult": 0.05, # 低血伤害 +5%
	},
	"of_parrying": {
		"name_zh": "之 格架",
		"parry_reduction_add": 0.04, # 格挡受击防损 +4%
	},
	"of_the_vanguard": {
		"name_zh": "之 先锋",
		"crit_bonus_add": 3.0,       # 满血状态暴击率 +3%
	},
	"of_tenacity": {
		"name_zh": "之 韧性",
		"low_hp_defense_add": 2,     # 残血状态物防 +2
	},
	"of_scavenger": {
		"name_zh": "之 搜刮",
		"coin_drop_mult": 1.03,      # 金币掉落概率 +3%
	},
	"of_warding": {
		"name_zh": "之 庇护",
		"spell_damage_reduce": 0.03, # 法术减伤 +3%
	},
	"of_clarity": {
		"name_zh": "之 清明",
		"mana_cost_mult": 0.97,      # 耗蓝 -3%
	},
	"of_precision": {
		"name_zh": "之 精准",
		"armor_pierce_add": 3.0,     # 穿透率 +3%
	},
}

# ============================================================================
# 2. 词缀 Roll 逻辑（策划案 06 §3：0/1/2 个，2 个时 1 正 1 负）
# ============================================================================

const AFFIX_COUNT_WEIGHTS: Dictionary = {
	0: 30.0,  # 30% 无词缀
	1: 40.0,  # 40% 1 个词缀
	2: 30.0,  # 30% 2 个词缀（1 正 1 负）
}

## Roll 词缀数量与具体词缀。返回 Array[String]（0-2 个词缀 ID）。
func roll_affixes() -> Array[String]:
	var count := _roll_affix_count()
	var result: Array[String] = []
	match count:
		0:
			pass
		1:
			# 50% 正向，50% 负向
			if randf() < 0.5:
				result.append(_pick_random_positive())
			else:
				result.append(_pick_random_negative())
		2:
			# 必为 1 正 1 负
			result.append(_pick_random_positive())
			result.append(_pick_random_negative())
	return result

func _roll_affix_count() -> int:
	var total: float = 0.0
	for key in AFFIX_COUNT_WEIGHTS:
		total += AFFIX_COUNT_WEIGHTS[key]
	var roll: float = randf() * total
	var cumul: float = 0.0
	for key in AFFIX_COUNT_WEIGHTS:
		cumul += AFFIX_COUNT_WEIGHTS[key]
		if roll <= cumul:
			return int(key)
	return 0

func _pick_random_positive() -> String:
	var keys: Array = POSITIVE_AFFIXES.keys()
	return keys[randi() % keys.size()]

func _pick_random_negative() -> String:
	var keys: Array = NEGATIVE_AFFIXES.keys()
	return keys[randi() % keys.size()]

# ============================================================================
# 3. 词缀属性修正应用
# ============================================================================

## 将词缀修正应用到 WeaponData 实例（原地修改）。
## 调用前应已完成 duplicate()，确保不影响注册表共享实例。
func apply_affixes(data: WeaponData, affix_ids: Array[String]) -> void:
	for affix_id in affix_ids:
		data.affixes.append(affix_id)
		var config: Dictionary = _get_affix_config(affix_id)
		if config.is_empty():
			continue
		# 伤害倍率
		if config.has("damage_mult_add"):
			data.damage_mult += float(config["damage_mult_add"])
		# 暴击率
		if config.has("crit_bonus_add"):
			data.crit_bonus_percent += float(config["crit_bonus_add"])
		# 暴击伤害
		if config.has("crit_damage_bonus_add"):
			data.crit_damage_bonus += float(config["crit_damage_bonus_add"])
		# 物理防御
		if config.has("armor_phys_def_add"):
			data.armor_phys_def += int(config["armor_phys_def_add"])
			data.shield_phys_def += int(config["armor_phys_def_add"])
		# 负重倍率
		if config.has("carry_weight_mult_mul"):
			data.carry_weight_mult *= float(config["carry_weight_mult_mul"])
		# 最大耐久
		if config.has("max_condition_mult"):
			var mult: float = float(config["max_condition_mult"])
			data.max_condition = maxi(int(round(float(data.max_condition) * mult)), 1)
			data.condition = mini(data.condition, data.max_condition)
		# 护甲穿透
		if config.has("armor_pierce_add"):
			data.armor_pierce_percent += float(config["armor_pierce_add"])
		# 吸血
		if config.has("lifesteal_percent"):
			data.lifesteal_percent += float(config["lifesteal_percent"])
		# 诅咒自扣血
		if config.has("self_hp_drain_per_hit"):
			data.self_hp_drain_per_hit += int(config["self_hp_drain_per_hit"])
		# 斩杀伤害加成
		if config.has("low_hp_execute_mult"):
			data.low_hp_execute_mult += float(config["low_hp_execute_mult"])
		# 诅咒/赐福标记
		if config.get("is_cursed", false):
			data.is_cursed = true
		if config.get("is_blessed", false):
			data.is_blessed = true

	# 确保 damage_mult 不为负
	data.damage_mult = maxf(data.damage_mult, 0.0)

func _get_affix_config(affix_id: String) -> Dictionary:
	if POSITIVE_AFFIXES.has(affix_id):
		return POSITIVE_AFFIXES[affix_id]
	if NEGATIVE_AFFIXES.has(affix_id):
		return NEGATIVE_AFFIXES[affix_id]
	if SUFFIXES.has(affix_id):
		return SUFFIXES[affix_id]
	return {}

# ============================================================================
# 4. 工具
# ============================================================================

## 获取词缀中文名
func get_affix_name(affix_id: String) -> String:
	var config: Dictionary = _get_affix_config(affix_id)
	return TranslationServer.translate(config.get("name_zh", affix_id))

## 判断词缀是否为正向
func is_positive(affix_id: String) -> bool:
	return POSITIVE_AFFIXES.has(affix_id)

## 判断词缀是否为负向
func is_negative(affix_id: String) -> bool:
	return NEGATIVE_AFFIXES.has(affix_id)
