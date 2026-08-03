class_name AttackContext
extends RefCounted

## 攻击上下文（AttackContext）—— 服务器权威攻击的唯一装配真相（架构审查 P0-2）。
##
## 背景：联机攻击曾经信任客户端自报的 attack_type（伪报 ranged 可拿 18m 射程），
## 且服务器用残缺默认 AttackInput（1d6/ONE_HAND）结算，与单机装备/流派/熟练度分叉。
##
## 本类把「一次攻击的全部权威输入」聚合为一个纯数据对象：
##   * 攻方属性/等级（来自 per-peer PlayerContext.attributes，服务器权威）
##   * 武器/手位/蓄力/目标提示（来自服务器权威 loadout 与命令意图）
##   * 由武器派生攻击类型、射程、风格（绝不来自客户端）
##
## 纯 RefCounted，无场景树依赖；构造入口见 AttackContextFactory，冷却真相见
## AttackCadencePolicy。

const DR := preload("res://globals/combat/damage_resolver.gd")

## 主手武器（WeaponData；null = 徒手）。
var weapon: Variant = null
## 主手武器类型 id（weapon_class，如 "one_hand_melee" / "two_hand" / "longbow" / "wand"）。
var main_hand_type: String = ""
## 副手类型 id（"one_hand_melee" 双持 / "shield" 持盾 / "" 空手）。
var off_hand_type: String = ""
## 攻击手位："primary" 主手 / "secondary" 副手（双持）。
var hand: String = "primary"
## 蓄力比例 0..1（满蓄力释放）。
var charge_ratio: float = 1.0
## 目标实体提示（服务器按权威位置/朝向重新判定）。
var target_hint: Variant = null
## 攻方六维属性 {"str","dex","mag","con","agi","per"}。
var attrs: Dictionary = {}
## 攻方等级。
var level: int = 1
## 是否背袭（由服务器按双方朝向判定）。
var is_backstab: bool = false
## 流派被动运行时状态（单机由 PlayerCombatRuntime 提供；联机侧服务端无连击栈时为 {}）。
var style_context: Dictionary = {}

## 战斗风格（由主/副手类型派生，与 DamageResolver.determine_style 同源）。
func style() -> int:
	return DR.determine_style(main_hand_type, off_hand_type)

## 攻击类型（melee/ranged/spell）：由武器数据派生，绝不接受客户端值。
## 已注册武器（带 id）以其 attack_type 为准；旧版无 id 的 .tres 武器退化为
## 主手类型推断（与 CombatBridge._resolve_attack_type 语义一致）。
func attack_type() -> String:
	if weapon != null and "id" in weapon and not String(weapon.id).is_empty() \
			and "attack_type" in weapon and not String(weapon.attack_type).is_empty():
		return String(weapon.attack_type)
	return _infer_attack_type(main_hand_type)

## 攻击有效射程（米）：远程/法术 18m（要求确已装备武器），近战 2.5m。
func attack_range() -> float:
	var atk_type := attack_type()
	if atk_type == "ranged" or atk_type == "spell":
		return 18.0 if weapon != null else 2.5
	return 2.5

## 是否双手武器（影响攻击冷却倍率）。
func is_two_handed() -> bool:
	return main_hand_type == "two_hand"

## 主手武器注册表 id（空 = 徒手/未知）。
func weapon_id() -> String:
	return String(weapon.id) if weapon != null and "id" in weapon else ""

## 由主手武器类型推断攻击类型（与 CombatBridge._infer_attack_type 同源）。
static func _infer_attack_type(main_hand_type: String) -> String:
	match main_hand_type:
		"longbow", "crossbow":
			return "ranged"
		"wand", "grimoire":
			return "spell"
		"":
			return "melee"
		_:
			return "melee"
