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
		"damage_mult_add": 0.10,   # 物理伤害 +10%
		"crit_bonus_add": 3.0,     # 暴击率 +3%
	},
	"lightweight": {
		"name_zh": "轻盈的",
		"evade_bonus_add": 5.0,    # 闪避率 +5%
		"carry_weight_mult_mul": 0.7,  # 负重扣减 30%
	},
	"focused": {
		"name_zh": "专注的",
		"hit_bonus_add": 10.0,     # 命中率 +10%
	},
	"furious": {
		"name_zh": "狂暴的",
		"crit_bonus_add": 8.0,     # 暴击率 +8%
		"crit_damage_bonus_add": 15.0,  # 暴击伤害 +15%
	},
	"sturdy": {
		"name_zh": "坚固的",
		"armor_phys_def_add": 4,   # 物理防御 +4
	},
	"blessed": {
		"name_zh": "受洗的",
		"damage_mult_add": 0.10,   # 法术伤害 +10%（与 sharp 叠加于 damage_mult）
		"crit_bonus_add": 5.0,     # 暴击率 +5%
	},
}

const NEGATIVE_AFFIXES: Dictionary = {
	"rusty": {
		"name_zh": "生锈的",
		"damage_mult_add": -0.15,  # 物理伤害 -15%
	},
	"clunky": {
		"name_zh": "笨重的",
		"evade_bonus_add": -5.0,   # 闪避率 -5%
		"carry_weight_mult_mul": 1.25,  # 负重增加 25%
	},
	"worn": {
		"name_zh": "磨损的",
		"hit_bonus_add": -10.0,    # 命中率 -10%
	},
	"inferior": {
		"name_zh": "劣质的",
		"crit_bonus_add": -5.0,    # 暴击率 -5%
		"max_condition_mult": 0.8, # 最大耐久 -20%
	},
	"cracked": {
		"name_zh": "碎裂的",
		"armor_phys_def_add": -3,  # 物理防御 -3
	},
	"dim": {
		"name_zh": "黯淡的",
		"damage_mult_add": -0.15,  # 法术伤害 -15%
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
		# 命中率
		if config.has("hit_bonus_add"):
			data.hit_bonus_percent += float(config["hit_bonus_add"])
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
		# 闪避率
		if config.has("evade_bonus_add"):
			data.armor_evade_percent += float(config["evade_bonus_add"])
		# 负重倍率
		if config.has("carry_weight_mult_mul"):
			data.carry_weight_mult *= float(config["carry_weight_mult_mul"])
		# 最大耐久
		if config.has("max_condition_mult"):
			var mult: float = float(config["max_condition_mult"])
			data.max_condition = maxi(int(round(float(data.max_condition) * mult)), 1)
			data.condition = mini(data.condition, data.max_condition)
	# 确保 damage_mult 不为负
	data.damage_mult = maxf(data.damage_mult, 0.0)

func _get_affix_config(affix_id: String) -> Dictionary:
	if POSITIVE_AFFIXES.has(affix_id):
		return POSITIVE_AFFIXES[affix_id]
	if NEGATIVE_AFFIXES.has(affix_id):
		return NEGATIVE_AFFIXES[affix_id]
	return {}

# ============================================================================
# 4. 工具
# ============================================================================

## 获取词缀中文名
func get_affix_name(affix_id: String) -> String:
	var config: Dictionary = _get_affix_config(affix_id)
	return config.get("name_zh", affix_id)

## 判断词缀是否为正向
func is_positive(affix_id: String) -> bool:
	return POSITIVE_AFFIXES.has(affix_id)

## 判断词缀是否为负向
func is_negative(affix_id: String) -> bool:
	return NEGATIVE_AFFIXES.has(affix_id)
