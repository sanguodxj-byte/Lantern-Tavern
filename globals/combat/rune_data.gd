extends RefCounted
## 符文数据与技能修饰器。
## 符文可挂载到主动/被动技能槽，修改数值并附加机制标签。

const RUNES: Dictionary = {
	"ember": {
		"id": "ember",
		"name": "余烬符文",
		"runic_name": "ᛖᛗᛒᛖᚱ",
		"rarity": "common",
		"mods": {"damage_mult": {"mul": 1.20}},
		"mechanics": {"burn_chance": 25, "burn_sec": 3.0},
		"desc": "提高伤害，并附加燃烧概率。",
	},
	"quick": {
		"id": "quick",
		"name": "迅捷符文",
		"runic_name": "ᚲᚹᛁᚲ",
		"rarity": "common",
		"mods": {"cooldown": {"mul": 0.80}, "cast_time": {"mul": 0.80}},
		"mechanics": {"quickened": true},
		"desc": "降低冷却与前摇。",
	},
	"force": {
		"id": "force",
		"name": "冲击符文",
		"runic_name": "ᚠᛟᚱᚲᛖ",
		"rarity": "uncommon",
		"mods": {"knockback_m": {"mul": 1.50}, "stun_sec": {"add": 0.2}},
		"mechanics": {"impact_bonus": true},
		"desc": "强化击退与短暂硬直。",
	},
	"surge": {
		"id": "surge",
		"name": "奔涌符文",
		"runic_name": "ᛋᚢᚱᚷᛖ",
		"rarity": "uncommon",
		"mods": {"dash_speed_mps": {"add": 2.0}, "physical_impact_damage_mult": {"add": 0.18}},
		"mechanics": {"charge_impulse_bonus": true},
		"desc": "提高冲撞位移冲量，并强化后续地形撞击伤害。",
	},
	"launch": {
		"id": "launch",
		"name": "抛掷符文",
		"runic_name": "ᛚᚨᚢᚾᚲᚺ",
		"rarity": "uncommon",
		"mods": {"knockback_m": {"mul": 1.35}, "physical_impact_damage_mult": {"add": 0.20}},
		"mechanics": {"launch_distance_bonus": true},
		"desc": "提高踢击给予的位移距离，并强化落点撞击伤害。",
	},
	"echo": {
		"id": "echo",
		"name": "回响符文",
		"runic_name": "ᛖᚲᚺᛟ",
		"rarity": "rare",
		"mods": {"cooldown": {"mul": 1.10}},
		"mechanics": {"extra_projectiles": 1, "repeat_count": 1},
		"desc": "额外触发一次机制，但略微增加冷却。",
	},
	"guardian": {
		"id": "guardian",
		"name": "守护符文",
		"runic_name": "ᚷᚢᚨᚱᛞ",
		"rarity": "uncommon",
		"mods": {"buff_value": {"mul": 1.20}, "buff_sec": {"add": 1.0}},
		"mechanics": {"passive_guard": true},
		"desc": "强化被动或增益类技能的数值与持续时间。",
	},
}

const SOURCE_WEIGHTS: Dictionary = {
	"chest": {"ember": 28.0, "quick": 24.0, "force": 16.0, "surge": 12.0, "launch": 12.0, "guardian": 6.0, "echo": 2.0},
	"elite": {"ember": 16.0, "quick": 16.0, "force": 20.0, "surge": 16.0, "launch": 16.0, "guardian": 10.0, "echo": 6.0},
	"boss": {"force": 18.0, "surge": 18.0, "launch": 18.0, "guardian": 16.0, "echo": 30.0},
}

static func get_rune(rune_id: String) -> Dictionary:
	return RUNES.get(rune_id, {}).duplicate(true)

static func has_rune(rune_id: String) -> bool:
	return RUNES.has(rune_id)

static func get_all_rune_ids() -> Array:
	return RUNES.keys()

static func get_rune_name(rune_id: String) -> String:
	var rune := get_rune(rune_id)
	return String(rune.get("runic_name", rune.get("name", rune_id)))

static func apply_runes(skill: Dictionary, rune_ids: Array) -> Dictionary:
	if skill.is_empty():
		return {}
	var result: Dictionary = skill.duplicate(true)
	var applied: Array = []
	var mechanics: Dictionary = result.get("rune_effects", {}).duplicate(true)
	for raw_id in rune_ids:
		var rune_id := String(raw_id)
		var rune := get_rune(rune_id)
		if rune.is_empty():
			continue
		applied.append(rune_id)
		var mods: Dictionary = rune.get("mods", {})
		for key in mods.keys():
			_apply_mod(result, String(key), mods[key])
		var rune_mechanics: Dictionary = rune.get("mechanics", {})
		for key in rune_mechanics.keys():
			mechanics[key] = rune_mechanics[key]
	result["rune_ids"] = applied
	result["rune_effects"] = mechanics
	return result

static func roll_rune(source: String = "chest") -> Dictionary:
	var weights: Dictionary = SOURCE_WEIGHTS.get(source, SOURCE_WEIGHTS["chest"])
	var total := 0.0
	for rune_id in weights.keys():
		total += float(weights[rune_id])
	if total <= 0.0:
		return {}
	var roll := randf() * total
	var cursor := 0.0
	for rune_id in weights.keys():
		cursor += float(weights[rune_id])
		if roll <= cursor:
			return get_rune(String(rune_id))
	return get_rune(String(weights.keys()[0]))

static func _apply_mod(skill: Dictionary, key: String, mod: Dictionary) -> void:
	var current = skill.get(key, 0)
	if typeof(current) == TYPE_DICTIONARY:
		var updated: Dictionary = current.duplicate(true)
		for child_key in updated.keys():
			if typeof(updated[child_key]) == TYPE_INT or typeof(updated[child_key]) == TYPE_FLOAT:
				updated[child_key] = _apply_number(float(updated[child_key]), mod)
		skill[key] = updated
	elif typeof(current) == TYPE_INT or typeof(current) == TYPE_FLOAT:
		skill[key] = _apply_number(float(current), mod)

static func _apply_number(value: float, mod: Dictionary) -> float:
	var result := value
	if mod.has("mul"):
		result *= float(mod["mul"])
	if mod.has("add"):
		result += float(mod["add"])
	return result
