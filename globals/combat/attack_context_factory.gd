class_name AttackContextFactory
extends RefCounted

## 攻击上下文工厂（AttackContextFactory）—— 攻击装配的唯一纯逻辑构造器（架构审查 P0-2）。
##
## 设计基线：攻击类型、射程、风格、冷却、伤害输入全部由【服务器权威状态】派生：
##   * 联机：per-peer PlayerContext（attributes + loadout）→ build_from_player_state()
##   * 单机：CombatBridge 复用同一构造器 → build_from_components()
## 客户端命令只携带手位/蓄力/目标提示，绝不携带 attack_type（可伪报 ranged 骗射程）。
##
## 纯 RefCounted、无场景树依赖；WeaponRegistry 经参数注入（缺省回退 /root/WeaponRegistry），
## 便于 headless 单测。

const AttackContextScript := preload("res://globals/combat/attack_context.gd")
const DR := preload("res://globals/combat/damage_resolver.gd")

## 从服务器权威玩家状态构建唯一 AttackContext。
## attrs: 六维属性字典；level: 等级；loadout: EquipmentLoadout（含武器槽与激活槽）；
## registry: WeaponRegistry 对象（null 时回退 autoload /root/WeaponRegistry，单测可注入 stub）；
## hand: "primary"/"secondary"；charge_ratio: 0..1；target_hint: 目标实体提示。
static func build_from_player_state(attrs: Dictionary, level: int, loadout: Object, registry: Object = null, hand: String = "primary", charge_ratio: float = 1.0, target_hint: Variant = null) -> AttackContextScript:
	var ctx := AttackContextScript.new()
	ctx.attrs = attrs.duplicate()
	ctx.level = level
	ctx.hand = hand
	ctx.charge_ratio = charge_ratio
	ctx.target_hint = target_hint
	var reg := _resolve_registry(registry)
	var active_slot: int = int(loadout.active_weapon_slot) if "active_weapon_slot" in loadout else 0
	var main_id := ""
	if loadout.has_method("get_weapon_slot"):
		main_id = String(loadout.get_weapon_slot(active_slot))
	ctx.weapon = reg.get_weapon_data(main_id) if reg != null and not main_id.is_empty() else null
	ctx.main_hand_type = _resolve_main_hand_type(ctx.weapon, main_id, reg)
	ctx.off_hand_type = _resolve_off_hand_type(loadout, ctx.main_hand_type, hand, reg)
	return ctx

## 从已解析的部件构建 AttackContext（单机 CombatBridge 复用入口，保证单机/联机同一装配逻辑）。
## weapon: WeaponData（null = 徒手）；main_hand_type/off_hand_type: 装备槽类型 id。
static func build_from_components(weapon: Variant, main_hand_type: String, off_hand_type: String, attrs: Dictionary, level: int, hand: String = "primary", charge_ratio: float = 1.0, target_hint: Variant = null) -> AttackContextScript:
	var ctx := AttackContextScript.new()
	ctx.weapon = weapon
	ctx.main_hand_type = _resolve_main_hand_type(weapon, main_hand_type, null)
	ctx.off_hand_type = off_hand_type
	ctx.attrs = attrs.duplicate()
	ctx.level = level
	ctx.hand = hand
	ctx.charge_ratio = charge_ratio
	ctx.target_hint = target_hint
	return ctx

## 把 AttackContext 转换为 DamageResolver.AttackInput（武器骰/平伤/倍率/暴击/元素/被动字段）。
## 与 CombatBridge._apply_weapon_to_attack 保持同一套武器属性语义（单机/联机伤害输入一致）。
static func to_attack_input(ctx: AttackContextScript) -> DR.AttackInput:
	var ai := DR.AttackInput.new()
	ai.attacker_str = int(ctx.attrs.get("str", 10))
	ai.attacker_dex = int(ctx.attrs.get("dex", 10))
	ai.attacker_mag = int(ctx.attrs.get("mag", 10))
	ai.attacker_per = int(ctx.attrs.get("per", 10))
	ai.attacker_agi = int(ctx.attrs.get("agi", 10))
	ai.attacker_con = int(ctx.attrs.get("con", 10))
	ai.attacker_level = ctx.level
	ai.style = ctx.style()
	ai.attack_type = ctx.attack_type()
	ai.is_backstab = ctx.is_backstab
	if ctx.weapon != null:
		_apply_weapon(ai, ctx.weapon)
	else:
		# 徒手：低基础伤害（与 CombatBridge 徒手分支一致）。
		ai.weapon_damage_dice = {"count": 1, "sides": 4}
		ai.weapon_damage_flat = 0.0
		ai.weapon_damage_mult = 1.0
	# P1-3：流派武器伤害倍率唯一真相（STYLE_META.damage_mult），只作用于武器伤害；
	# 法术卡伤害不经过 AttackInput 路径（SpellRuntime 独立结算），天然不乘。
	ai.weapon_damage_mult *= float(DR.STYLE_META.get(ai.style, {}).get("damage_mult", 1.0))
	return ai

## 解析注册表：优先注入对象，缺省回退 autoload（无场景树时返回 null）。
static func _resolve_registry(registry: Object) -> Object:
	if registry != null:
		return registry
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("WeaponRegistry")

## 主手类型：武器自带 weapon_class 优先，其次传入 fallback，最后注册表元数据。
static func _resolve_main_hand_type(weapon: Variant, fallback: String, registry: Object) -> String:
	if weapon != null and "weapon_class" in weapon and not String(weapon.weapon_class).is_empty():
		return String(weapon.weapon_class)
	if not fallback.is_empty():
		return fallback
	if registry != null and registry.has_method("get_weapon_class") and not fallback.is_empty():
		return String(registry.get_weapon_class(fallback))
	return ""

## 副手类型（服务器权威 loadout 派生）：
##   * secondary 手位且主手单手近战 + 另一槽位单手近战 → 双持 "one_hand_melee"
##   * 任意武器槽装备盾 → "shield"
##   * 否则空手。
static func _resolve_off_hand_type(loadout: Object, main_hand_type: String, hand: String, registry: Object) -> String:
	if hand == "secondary" and main_hand_type == "one_hand_melee":
		var other := _other_one_hand_slot(loadout, registry)
		if not other.is_empty():
			return "one_hand_melee"
	if _has_shield_slot(loadout):
		return "shield"
	return ""

## 除激活槽外是否存在另一把单手近战武器（双持判定）。
static func _other_one_hand_slot(loadout: Object, registry: Object) -> String:
	if not loadout.has_method("get_weapon_slot") or not ("weapon_slots" in loadout):
		return ""
	var active: int = int(loadout.active_weapon_slot) if "active_weapon_slot" in loadout else 0
	var reg := _resolve_registry(registry)
	for i in range(int(loadout.weapon_slots.size())):
		if i == active:
			continue
		var slot_id := String(loadout.get_weapon_slot(i))
		if slot_id.is_empty():
			continue
		var wclass := ""
		if reg != null and reg.has_method("get_weapon_class"):
			wclass = String(reg.get_weapon_class(slot_id))
		if wclass == "one_hand_melee":
			return slot_id
	return ""

## loadout 任意武器槽是否装备盾牌。
static func _has_shield_slot(loadout: Object) -> bool:
	if not ("weapon_slots" in loadout):
		return false
	for raw_id in loadout.weapon_slots:
		if String(raw_id) == "shield":
			return true
	return false

## 应用武器属性到 AttackInput（与 CombatBridge._apply_weapon_to_attack 同语义）。
static func _apply_weapon(ai: DR.AttackInput, weapon: Variant) -> void:
	if not ("id" in weapon) or String(weapon.id).is_empty():
		# 旧 .tres WeaponData（无 id）兼容分支。
		ai.weapon_damage_dice = {"count": 1, "sides": max(int(weapon.damage_max) - int(weapon.damage_min) + 1, 1)}
		ai.weapon_damage_flat = float(weapon.damage_min) - 1.0
		ai.weapon_damage_mult = 1.0
		return
	ai.weapon_damage_dice = {
		"count": max(int(weapon.damage_dice_count), 0),
		"sides": max(int(weapon.damage_dice_sides), 0),
	}
	ai.weapon_damage_flat = float(weapon.damage_flat)
	ai.crit_bonus = float(weapon.crit_bonus_percent)
	ai.crit_damage_bonus = float(weapon.crit_damage_bonus)
	ai.ignore_def_percent = float(weapon.armor_pierce_percent)
	ai.bonus_stun_duration = maxf(ai.bonus_stun_duration, float(weapon.stun_sec))
	if "damage_mult" in weapon:
		ai.weapon_damage_mult *= float(weapon.damage_mult)
	if "lifesteal_percent" in weapon:
		ai.lifesteal_percent += float(weapon.lifesteal_percent)
	if "impulse_mult" in weapon:
		ai.physical_impulse_multiplier *= maxf(float(weapon.impulse_mult), 0.0)
