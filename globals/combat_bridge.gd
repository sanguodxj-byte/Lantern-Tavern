class_name CombatBridge
## 战斗桥接层：把游戏内现有数据结构（WeaponData / ShieldData / Player / Enemy 状态）
## 适配为 CombatEngine 的 AttackInput / Defender，调用 resolve_attack 后输出 DamageResult。
## 避免在 player.gd / enemy.gd 主流程里直接组装 CombatEngine 内部类，保持职责分离。

const CE := preload("res://globals/combat_engine.gd")

# 默认格挡概率/格挡值（ShieldData 暂无格挡数值字段，集成期用保守默认值）
const DEFAULT_SHIELD_BLOCK_CHANCE: float = 30.0
const DEFAULT_SHIELD_BLOCK_VALUE: int = 3

# ============================================================================
# 1. 攻方输入构造
# ============================================================================

## 从玩家武器与状态构造攻方输入。
## player: Player 节点（用于读取朝向）
## weapon: WeaponData（可为 null = 徒手）
## main_hand_type / off_hand_type: 装备槽类型 id（与 CombatEngine.determine_style 输入同源）
## attacker_attrs: 6 属性字典 {"str","dex","mag","con","agi","per"}
## attacker_level: 角色等级
static func build_player_attack(player: Node3D, weapon, main_hand_type: String, off_hand_type: String, attacker_attrs: Dictionary, attacker_level: int, is_backstab: bool = false) -> CE.AttackInput:
	var attack := CE.AttackInput.new()
	attack.attacker_str = int(attacker_attrs.get("str", 10))
	attack.attacker_dex = int(attacker_attrs.get("dex", 10))
	attack.attacker_mag = int(attacker_attrs.get("mag", 10))
	attack.attacker_con = int(attacker_attrs.get("con", 10))
	attack.attacker_agi = int(attacker_attrs.get("agi", 10))
	attack.attacker_per = int(attacker_attrs.get("per", 10))
	attack.attacker_level = attacker_level
	attack.style = CE.determine_style(main_hand_type, off_hand_type)
	attack.attack_type = _infer_attack_type(main_hand_type)
	attack.is_backstab = is_backstab
	if weapon != null:
		attack.weapon_damage_dice = {"count": 1, "sides": max(weapon.damage_max - weapon.damage_min + 1, 1)}
		attack.weapon_damage_flat = float(weapon.damage_min) - 1.0  # 投骰下限对齐 damage_min
		attack.weapon_damage_mult = 1.0
		attack.weapon_hit_bonus = 0.0
		attack.knockback_force = 2.0
	else:
		# 徒手：低伤害投骰
		attack.weapon_damage_dice = {"count": 1, "sides": 4}
		attack.weapon_damage_flat = 0.0
		attack.weapon_damage_mult = 1.0
		attack.knockback_force = 1.5
	return attack

## 从敌人武器构造攻方输入（敌人属性用默认值，策划案未给敌人属性面板）
static func build_enemy_attack(enemy: Node3D, weapon, target_player: Node3D) -> CE.AttackInput:
	var attack := CE.AttackInput.new()
	attack.attacker_str = 10
	attack.attacker_dex = 10
	attack.attacker_mag = 10
	attack.attacker_con = 10
	attack.attacker_agi = 10
	attack.attacker_per = 10
	attack.attacker_level = 1
	attack.style = CE.Style.ONE_HAND
	attack.attack_type = "melee"
	if weapon != null:
		attack.weapon_damage_dice = {"count": 1, "sides": max(weapon.damage_max - weapon.damage_min + 1, 1)}
		attack.weapon_damage_flat = float(weapon.damage_min) - 1.0
		attack.weapon_damage_mult = 1.0
		attack.knockback_force = 2.0
	else:
		attack.weapon_damage_dice = {"count": 1, "sides": 4}
		attack.weapon_damage_flat = 0.0
		attack.knockback_force = 1.5
	return attack

# ============================================================================
# 2. 防方输入构造
# ============================================================================

## 从玩家状态构造防方输入。
## player: Player 节点
## defender_attrs: 6 属性字典
## has_shield: 是否持盾
## armor_def: 防具防御值（暂用 0，待护甲系统接入）
## armor_evade: 防具基础闪避（暂用 0）
static func build_player_defender(player: Node3D, defender_attrs: Dictionary, has_shield: bool, armor_def: int = 0, armor_evade: float = 0.0) -> CE.Defender:
	var defender := CE.Defender.new()
	defender.con = int(defender_attrs.get("con", 10))
	defender.agi = int(defender_attrs.get("agi", 10))
	defender.per = int(defender_attrs.get("per", 10))
	defender.armor_def = armor_def
	defender.armor_evade = armor_evade
	defender.has_shield = has_shield
	if has_shield:
		defender.shield_block_chance = DEFAULT_SHIELD_BLOCK_CHANCE
		defender.shield_block_value = DEFAULT_SHIELD_BLOCK_VALUE
	return defender

## 从敌人状态构造防方输入（敌人属性用默认值）
static func build_enemy_defender(enemy: Node3D, has_shield: bool) -> CE.Defender:
	var defender := CE.Defender.new()
	defender.con = 10
	defender.agi = 10
	defender.per = 10
	defender.armor_def = 0
	defender.armor_evade = 0.0
	defender.has_shield = has_shield
	if has_shield:
		defender.shield_block_chance = DEFAULT_SHIELD_BLOCK_CHANCE
		defender.shield_block_value = DEFAULT_SHIELD_BLOCK_VALUE
	return defender

# ============================================================================
# 3. 结算执行（封装 resolve_attack 的朝向参数）
# ============================================================================

## 玩家攻击敌人结算。
## 返回 CE.DamageResult（含 hit/crit/final_damage/knockback_impulse/stun_duration）。
static func resolve_player_attack(player: Node3D, enemy: Node3D, weapon, main_hand_type: String, off_hand_type: String, attacker_attrs: Dictionary, attacker_level: int, is_backstab: bool = false) -> CE.DamageResult:
	var attack := build_player_attack(player, weapon, main_hand_type, off_hand_type, attacker_attrs, attacker_level, is_backstab)
	var has_shield := false
	if enemy.has_method("get") and "equipment" in enemy:
		var eq = enemy.get("equipment")
		if eq and eq.has_method("has_shield"):
			has_shield = eq.has_shield()
	var defender := build_enemy_defender(enemy, has_shield)
	var forward := -player.global_transform.basis.z.normalized()
	return CE.resolve_attack(attack, defender, forward)

## 敌人攻击玩家结算
static func resolve_enemy_attack(enemy: Node3D, player: Node3D, weapon, defender_attrs: Dictionary, player_has_shield: bool) -> CE.DamageResult:
	var attack := build_enemy_attack(enemy, weapon, player)
	var defender := build_player_defender(player, defender_attrs, player_has_shield)
	var forward := -enemy.global_transform.basis.z.normalized()
	return CE.resolve_attack(attack, defender, forward)

# ============================================================================
# 4. 朝向判定辅助（策划案 §4 背袭/侧击加成）
# ============================================================================

## 判定攻击是否为背袭：攻方朝向与防方朝向同向（夹角 < 60° 视为背袭）
static func is_backstab(attacker_forward: Vector3, defender_forward: Vector3) -> bool:
	var dot := attacker_forward.dot(defender_forward)
	return dot > 0.5  # cos(60°) ≈ 0.5

## 判定攻击是否为侧击：攻方朝向与防方朝向近垂直（|cos| < 0.3）
static func is_sideswipe(attacker_forward: Vector3, defender_forward: Vector3) -> bool:
	var dot := absf(attacker_forward.dot(defender_forward))
	return dot < 0.3

# ============================================================================
# 5. 内部辅助
# ============================================================================

## 根据主手武器类型推断 attack_type（melee/ranged/spell）
static func _infer_attack_type(main_hand_type: String) -> String:
	match main_hand_type:
		"longbow", "crossbow":
			return "ranged"
		"wand", "grimoire":
			return "spell"
		"", "one_hand_melee", "two_hand":
			return "melee"
		_:
			return "melee"
