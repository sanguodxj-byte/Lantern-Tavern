class_name StatusEffectSystem
extends RefCounted

## 状态效果系统 — 管理敌人身上的所有状态效果
## 包括 DoT（持续伤害）、控制效果、属性削弱等
##
## 与 enemy.gd 的 combat_debuffs 字典兼容：
## 新状态效果使用 "se_" 前缀避免与既有 debuff 冲突。
## 既有 debuff（slow, def_down 等）保持原 key 不变。

## ── 状态效果定义 ──
const STATUS_DEFS: Dictionary = {
	# ── DoT 类（持续伤害）──
	"se_burn": {
		"display_name": "燃烧",
		"is_dot": true,
		"dot_damage_per_sec": 4.0,
		"dot_element": "fire",
		"tick_interval": 1.0,
		"color": Color(1.0, 0.4, 0.1),
		"icon_abbr": "BURN",
	},
	"se_poison": {
		"display_name": "中毒",
		"is_dot": true,
		"dot_damage_per_sec": 3.0,
		"dot_element": "poison",
		"tick_interval": 1.0,
		"color": Color(0.3, 0.8, 0.2),
		"icon_abbr": "PSN",
	},
	"se_corrupt": {
		"display_name": "腐蚀",
		"is_dot": true,
		"dot_damage_per_sec": 4.0,
		"dot_element": "dark",
		"tick_interval": 1.0,
		"color": Color(0.5, 0.1, 0.15),
		"icon_abbr": "CRRPT",
	},
	"se_choke": {
		"display_name": "窒息",
		"is_dot": true,
		"dot_damage_per_sec": 2.0,
		"dot_element": "physical",
		"tick_interval": 1.5,
		"color": Color(0.4, 0.4, 0.4),
		"icon_abbr": "CHKE",
	},
	# ── 控制类 ──
	"se_slow": {
		"display_name": "减速",
		"is_dot": false,
		"color": Color(0.3, 0.5, 1.0),
		"icon_abbr": "SLOW",
	},
	"se_root": {
		"display_name": "定身",
		"is_dot": false,
		"color": Color(0.6, 0.4, 0.2),
		"icon_abbr": "ROOT",
	},
	"se_ensnare": {
		"display_name": "束缚",
		"is_dot": false,
		"color": Color(0.6, 0.4, 0.2),
		"icon_abbr": "ENSN",
	},
	"se_fear": {
		"display_name": "恐惧",
		"is_dot": false,
		"color": Color(0.9, 0.9, 0.9),
		"icon_abbr": "FEAR",
	},
	"se_terror": {
		"display_name": "惊骇",
		"is_dot": false,
		"color": Color(0.4, 0.2, 0.5),
		"icon_abbr": "TRRR",
	},
	"se_tremor": {
		"display_name": "震颤",
		"is_dot": false,
		"color": Color(0.7, 0.5, 0.3),
		"icon_abbr": "TRMR",
	},
	# ── 属性削弱类 ──
	"se_blind": {
		"display_name": "致盲",
		"is_dot": false,
		"color": Color(0.6, 0.3, 0.8),
		"icon_abbr": "BLND",
	},
	"se_wet": {
		"display_name": "浸湿",
		"is_dot": false,
		"color": Color(0.2, 0.6, 0.9),
		"icon_abbr": "WET",
	},
	"se_armor_break": {
		"display_name": "破甲",
		"is_dot": false,
		"color": Color(0.8, 0.6, 0.3),
		"icon_abbr": "BRKN",
	},
	"se_sunder": {
		"display_name": "粉碎",
		"is_dot": false,
		"color": Color(0.9, 0.5, 0.2),
		"icon_abbr": "SNDR",
	},
}

## DoT 状态效果集合（快速查询）
const DOT_TYPES: Array = ["se_burn", "se_poison", "se_corrupt", "se_choke"]

## 状态效果 aura 类型映射（用于 VFX）
const AURA_TYPE_MAP: Dictionary = {
	"se_burn": "burn",
	"se_poison": "poison",
	"se_slow": "slow",
	"se_blind": "blind",
	"se_fear": "fear",
	"se_corrupt": "corrupt",
	"se_ensnare": "ensnare",
	"se_wet": "wet",
	"se_choke": "choke",
	"se_tremor": "tremor",
	"se_terror": "terror",
	"se_armor_break": "armor_break",
	"se_sunder": "sunder",
}

## ── 核心接口 ──

## 施加状态效果到敌人（若已存在则刷新持续时间，取较长者）
## value 参数用途：
##   se_burn/se_poison/se_corrupt/se_choke: 自定义 DoT 伤害/秒
##   se_slow: 减速乘数 (0.0-1.0)，默认 0.5
##   se_armor_break: 护甲削减值，默认 5
##   se_sunder: 无 value（护甲归零）
static func apply_status(enemy: Node, status_type: String, duration: float, value: Variant = null) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if status_type.is_empty() or duration <= 0.0:
		return
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return
	var existing: Dictionary = debuffs.get(status_type, {})
	var new_entry: Dictionary = {"remaining": duration, "value": value}
	# 已存在则取较长的持续时间
	if not existing.is_empty():
		new_entry["remaining"] = maxf(duration, float(existing.get("remaining", 0.0)))
		# value 取新值（如果提供了），否则保留旧值
		if value == null:
			new_entry["value"] = existing.get("value", null)
	debuffs[status_type] = new_entry
	enemy.set("combat_debuffs", debuffs)

## 批量处理敌人状态效果 tick（每帧调用）
static func process_tick(enemy: Node, delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return
	var keys_to_remove: Array = []
	for status_type in debuffs.keys():
		var entry: Dictionary = debuffs[status_type]
		var remaining := float(entry.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			keys_to_remove.append(status_type)
			continue
		entry["remaining"] = remaining
		debuffs[status_type] = entry
		# DoT 处理
		if DOT_TYPES.has(status_type):
			_process_dot(enemy, status_type, entry, delta)
	# 移除过期状态
	for key in keys_to_remove:
		debuffs.erase(key)
	enemy.set("combat_debuffs", debuffs)

## 处理 DoT 伤害
static func _process_dot(enemy: Node, status_type: String, entry: Dictionary, delta: float) -> void:
	var def: Dictionary = STATUS_DEFS.get(status_type, {})
	if def.is_empty():
		return
	var tick_interval: float = float(def.get("tick_interval", 1.0))
	# 累积 tick 计时器
	var accumulator: float = float(entry.get("_dot_acc", 0.0)) + delta
	if accumulator < tick_interval:
		entry["_dot_acc"] = accumulator
		return
	# 触发 DoT
	entry["_dot_acc"] = accumulator - tick_interval
	var base_dps: float = float(def.get("dot_damage_per_sec", 0.0))
	# 如果 entry 中有自定义伤害值，使用它
	var custom_val: Variant = entry.get("value", 0.0)
	var custom_dps: float = float(custom_val) if custom_val != null else 0.0
	if custom_dps > 0.0:
		base_dps = custom_dps
	var damage := int(round(base_dps * tick_interval))
	if damage <= 0:
		return
	# 应用伤害
	var health = enemy.get("health")
	if health == null or not is_instance_valid(health):
		return
	health.call("take_damage", damage)
	# VFX: 飘字
	var enemy3d := enemy as Node3D
	if enemy3d != null and enemy3d.is_inside_tree():
		var pos := enemy3d.global_position + Vector3(0, 1.5, 0)
		var fx: Node = Engine.get_main_loop().root.get_node_or_null("FxHelper")
		if fx != null:
			fx.call_deferred("create_damage_number_flags", pos, damage, false, false, false, false)
	# 检查死亡
	if health.get("is_dead") != null and health.call("is_dead"):
		if enemy.has_method("request_death"):
			enemy.call_deferred("request_death")

## 获取敌人的状态效果速度修正（乘数）
static func get_speed_multiplier(enemy: Node) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 1.0
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return 1.0
	var mult := 1.0
	# 定身/束缚/粉碎：速度归零
	if debuffs.has("se_root") or debuffs.has("se_ensnare"):
		return 0.0
	# 减速
	if debuffs.has("se_slow"):
		var entry: Dictionary = debuffs["se_slow"]
		var slow_mult: float = float(entry.get("value", 0.5))
		mult *= slow_mult
	# 窒息：速度 ×0.7
	if debuffs.has("se_choke"):
		mult *= 0.7
	# 震颤：速度 ×0.8
	if debuffs.has("se_tremor"):
		mult *= 0.8
	# 恐惧：速度 ×1.2（逃跑更快）
	if debuffs.has("se_fear") or debuffs.has("se_terror"):
		mult *= 1.2
	return clampf(mult, 0.0, 2.0)

## 获取敌人的状态效果防御修正（固定值）
static func get_defense_penalty(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return 0
	var penalty := 0
	# 破甲：削减固定护甲值
	if debuffs.has("se_armor_break"):
		var entry: Dictionary = debuffs["se_armor_break"]
		penalty += int(entry.get("value", 5))
	# 粉碎：护甲归零（返回一个很大的值确保护甲被减到0）
	if debuffs.has("se_sunder"):
		penalty += 999
	return penalty

## 获取敌人的闪避修正
static func get_evade_penalty(enemy: Node) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 0.0
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return 0.0
	# 致盲：闪避归零
	if debuffs.has("se_blind"):
		return 1.0  # 100% 闪避惩罚
	return 0.0

## 检查敌人是否有指定状态
static func has_status(enemy: Node, status_type: String) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return false
	return debuffs.has(status_type)

## 获取状态效果的伤害加成修正（如致盲敌人受到额外伤害）
static func get_incoming_damage_mult(enemy: Node) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 1.0
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return 1.0
	var mult := 1.0
	# 致盲：受到 +25% 伤害
	if debuffs.has("se_blind"):
		mult += 0.25
	# 震颤：受到 +15% 物理伤害（简化为全伤害）
	if debuffs.has("se_tremor"):
		mult += 0.15
	# 恐惧/惊骇：受到 +30% 伤害
	if debuffs.has("se_fear"):
		mult += 0.30
	if debuffs.has("se_terror"):
		mult += 0.30
	return mult

## 获取对特定元素类型的伤害加成修正
static func get_elemental_damage_mult(enemy: Node, element: String) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 1.0
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return 1.0
	var mult := 1.0
	# 浸湿：受到 +50% 电属性伤害
	if debuffs.has("se_wet") and element == "electric":
		mult += 0.50
	# 浸湿：受到 +25% 冰属性伤害
	if debuffs.has("se_wet") and element == "ice":
		mult += 0.25
	return mult

## 获取状态效果的暴击加成
static func get_crit_bonus_vs_enemy(enemy: Node) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 0.0
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return 0.0
	var bonus := 0.0
	# 致盲敌人：暴击率 +10%
	if debuffs.has("se_blind"):
		bonus += 0.10
	# 恐惧敌人：暴击率 +15%
	if debuffs.has("se_fear"):
		bonus += 0.15
	return bonus

## 清除敌人所有状态效果
static func clear_all_statuses(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return
	# 只清除 se_ 前缀的状态
	var keys_to_remove: Array = []
	for key in debuffs.keys():
		if String(key).begins_with("se_"):
			keys_to_remove.append(key)
	for key in keys_to_remove:
		debuffs.erase(key)
	enemy.set("combat_debuffs", debuffs)

## 获取敌人所有活跃状态（供UI显示）
static func get_active_statuses(enemy: Node) -> Array:
	if enemy == null or not is_instance_valid(enemy):
		return []
	var debuffs = enemy.get("combat_debuffs")
	if not (debuffs is Dictionary):
		return []
	var result: Array = []
	for key in debuffs.keys():
		if String(key).begins_with("se_"):
			var entry: Dictionary = debuffs[key]
			var def: Dictionary = STATUS_DEFS.get(String(key), {})
			result.append({
				"type": String(key),
				"display_name": String(def.get("display_name", key)),
				"remaining": float(entry.get("remaining", 0.0)),
				"color": def.get("color", Color.WHITE),
				"icon_abbr": String(def.get("icon_abbr", "???")),
				"aura_type": String(AURA_TYPE_MAP.get(String(key), "")),
			})
	return result

## 获取状态的 aura 类型（用于生成 VFX 光环）
static func get_aura_type(status_type: String) -> String:
	return String(AURA_TYPE_MAP.get(status_type, ""))

## 检查是否为 DoT 状态
static func is_dot_status(status_type: String) -> bool:
	return DOT_TYPES.has(status_type)

## 获取 DoT 伤害/秒
static func get_dot_dps(status_type: String) -> float:
	var def: Dictionary = STATUS_DEFS.get(status_type, {})
	return float(def.get("dot_damage_per_sec", 0.0))

## 获取 DoT 元素类型
static func get_dot_element(status_type: String) -> String:
	var def: Dictionary = STATUS_DEFS.get(status_type, {})
	return String(def.get("dot_element", "physical"))
