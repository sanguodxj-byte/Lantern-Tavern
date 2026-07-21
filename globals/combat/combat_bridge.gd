class_name CombatBridge
## 战斗桥接层：把游戏内现有数据结构（WeaponData / ShieldData / Player / Enemy 状态）
## 适配为 CombatEngine 的 AttackInput / Defender，调用 resolve_attack 后输出 DamageResult。
## 避免在 player.gd / enemy.gd 主流程里直接组装 CombatEngine 内部类，保持职责分离。

const CE := preload("res://globals/combat/combat_engine.gd")
const ME := preload("res://globals/combat/milestone_effects.gd")

# 旧 ShieldData 或测试替身没有战斗字段时的兼容回退。
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
static func build_player_attack(player: Node3D, weapon, main_hand_type: String, off_hand_type: String, attacker_attrs: Dictionary, attacker_level: int, is_backstab: bool = false, skill: Dictionary = {}) -> CE.AttackInput:
	var attack := CE.AttackInput.new()
	attack.attacker_str = int(attacker_attrs.get("str", 10))
	attack.attacker_dex = int(attacker_attrs.get("dex", 10))
	attack.attacker_mag = int(attacker_attrs.get("mag", 10))
	attack.attacker_con = int(attacker_attrs.get("con", 10))
	attack.attacker_agi = int(attacker_attrs.get("agi", 10))
	attack.attacker_per = int(attacker_attrs.get("per", 10))
	attack.attacker_level = attacker_level
	main_hand_type = _resolve_main_hand_type(weapon, main_hand_type)
	attack.style = CE.determine_style(main_hand_type, off_hand_type)
	attack.attack_type = _resolve_attack_type(weapon, main_hand_type)
	attack.is_backstab = is_backstab
	if weapon != null:
		_apply_weapon_to_attack(attack, weapon)
	else:
		# 徒手：低基础伤害（确定性，正常攻击无击退）
		attack.weapon_damage_dice = {"count": 1, "sides": 4}
		attack.weapon_damage_flat = 0.0
		attack.weapon_damage_mult = 1.0
	_apply_skill_to_attack(attack, skill)
	_apply_milestones_to_attack(attack, main_hand_type, skill)
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
		_apply_weapon_to_attack(attack, weapon)
	else:
		attack.weapon_damage_dice = {"count": 1, "sides": 4}
		attack.weapon_damage_flat = 0.0
	return attack

# ============================================================================
# 2. 防方输入构造
# ============================================================================

## 从玩家状态构造防方输入。
## player: Player 节点
## defender_attrs: 6 属性字典
## has_shield: 是否持盾（信息字段，不再用于概率格挡）
## armor_def: 防具防御值
static func build_player_defender(player: Node3D, defender_attrs: Dictionary, has_shield: bool, armor_def: int = 0, shield_resource = null) -> CE.Defender:
	var defender := CE.Defender.new()
	defender.con = int(defender_attrs.get("con", 10))
	defender.agi = int(defender_attrs.get("agi", 10))
	defender.per = int(defender_attrs.get("per", 10))
	defender.armor_def = armor_def
	if player != null and player.has_method("get_combat_defense_bonus"):
		defender.armor_def += int(player.get_combat_defense_bonus())
	defender.has_shield = has_shield
	if has_shield:
		_apply_shield_to_defender(defender, shield_resource)
	return defender

## 从敌人状态构造防方输入（敌人属性用默认值）
static func build_enemy_defender(enemy: Node3D, has_shield: bool, shield_resource = null) -> CE.Defender:
	var defender := CE.Defender.new()
	defender.con = 10
	defender.agi = 10
	defender.per = 10
	defender.armor_def = 0
	if enemy != null and enemy.has_method("get_combat_defense_penalty"):
		defender.armor_def -= int(enemy.get_combat_defense_penalty())
	defender.has_shield = has_shield
	if has_shield:
		_apply_shield_to_defender(defender, shield_resource)
	return defender


static func build_player_defender_from_equipment(player: Node3D, defender_attrs: Dictionary, fallback_has_shield: bool = false) -> CE.Defender:
	var has_shield := fallback_has_shield
	var shield_resource = null
	var armor_def := 0
	if player != null and "equipment" in player and player.equipment != null:
		var eq = player.equipment
		if eq.has_method("has_shield"):
			has_shield = eq.has_shield()
		if eq.has_method("get_armor_defense"):
			armor_def = int(eq.get_armor_defense())
		if has_shield:
			shield_resource = _get_equipment_shield_resource(eq)
	return build_player_defender(player, defender_attrs, has_shield, armor_def, shield_resource)

# ============================================================================
# 3. 结算执行（封装 resolve_attack 的朝向参数）
# ============================================================================

## 玩家攻击敌人结算。
## 返回 CE.DamageResult（含 hit/crit/final_damage/knockback_impulse/stun_duration）。
static func resolve_player_attack(player: Node3D, enemy: Node3D, weapon, main_hand_type: String, off_hand_type: String, attacker_attrs: Dictionary, attacker_level: int, is_backstab: bool = false, skill: Dictionary = {}) -> CE.DamageResult:
	var attack := build_player_attack(player, weapon, main_hand_type, off_hand_type, attacker_attrs, attacker_level, is_backstab, skill)
	var has_shield := false
	var shield_resource = null
	if enemy != null and enemy.has_method("get") and "equipment" in enemy:
		var eq = enemy.get("equipment")
		if eq and eq.has_method("has_shield"):
			has_shield = eq.has_shield()
			if has_shield:
				shield_resource = _get_equipment_shield_resource(eq)
	var defender := build_enemy_defender(enemy, has_shield, shield_resource)
	var forward := Vector3(0, 0, -1)
	if player != null:
		forward = -player.global_transform.basis.z.normalized()
	return CE.resolve_attack(attack, defender, forward)

## 敌人攻击玩家结算
static func resolve_enemy_attack(enemy: Node3D, player: Node3D, weapon, defender_attrs: Dictionary, player_has_shield: bool) -> CE.DamageResult:
	var attack := build_enemy_attack(enemy, weapon, player)
	var defender := build_player_defender_from_equipment(player, defender_attrs, player_has_shield)
	var forward := Vector3(0, 0, -1)
	if enemy != null:
		forward = -enemy.global_transform.basis.z.normalized()
	return CE.resolve_attack(attack, defender, forward)

## 投射物攻击结算：以投射物飞行方向作为击退方向（非攻方朝向）。
## source: 发射者节点（用于构建 AttackInput，可为 Player 或任意 Node3D）
## attack_forward: 投射物飞行方向单位向量
## damage_mult_override: 可选伤害倍率覆盖（用于穿透衰减）
static func resolve_projectile_attack(source: Node3D, enemy: Node3D, weapon, main_hand_type: String, off_hand_type: String, attacker_attrs: Dictionary, attacker_level: int, attack_forward: Vector3, is_backstab: bool = false, skill: Dictionary = {}, damage_mult_override: float = -1.0) -> CE.DamageResult:
	var attack := build_player_attack(source, weapon, main_hand_type, off_hand_type, attacker_attrs, attacker_level, is_backstab, skill)
	if damage_mult_override >= 0.0:
		attack.weapon_damage_mult = damage_mult_override
	var has_shield := false
	var shield_resource = null
	if enemy != null and enemy.has_method("get") and "equipment" in enemy:
		var eq = enemy.get("equipment")
		if eq and eq.has_method("has_shield"):
			has_shield = eq.has_shield()
			if has_shield:
				shield_resource = _get_equipment_shield_resource(eq)
	var defender := build_enemy_defender(enemy, has_shield, shield_resource)
	var forward := attack_forward.normalized() if attack_forward.length() > 0.01 else Vector3(0, 0, -1)
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


static func _resolve_main_hand_type(weapon, fallback: String) -> String:
	if weapon != null and "weapon_class" in weapon and not String(weapon.weapon_class).is_empty():
		return String(weapon.weapon_class)
	return fallback


static func _resolve_attack_type(weapon, main_hand_type: String) -> String:
	if weapon != null and "id" in weapon and not String(weapon.id).is_empty() and "attack_type" in weapon and not String(weapon.attack_type).is_empty():
		return String(weapon.attack_type)
	return _infer_attack_type(main_hand_type)


static func get_weapon_class(weapon) -> String:
	return _resolve_main_hand_type(weapon, "one_hand_melee" if weapon != null else "")


static func get_weapon_attack_type(weapon) -> String:
	return _resolve_attack_type(weapon, get_weapon_class(weapon))


static func get_weapon_proficiency_key(weapon) -> String:
	if weapon != null and "proficiency_key" in weapon and not String(weapon.proficiency_key).is_empty():
		return String(weapon.proficiency_key)
	var weapon_class := get_weapon_class(weapon)
	return weapon_class if weapon_class != "" else "unarmed"


static func _apply_weapon_to_attack(attack: CE.AttackInput, weapon) -> void:
	if "id" in weapon and not String(weapon.id).is_empty():
		attack.weapon_damage_dice = {
			"count": max(int(weapon.damage_dice_count), 0),
			"sides": max(int(weapon.damage_dice_sides), 0),
		}
		attack.weapon_damage_flat = float(weapon.damage_flat)
		attack.crit_bonus = float(weapon.crit_bonus_percent)
		attack.crit_damage_bonus = float(weapon.crit_damage_bonus)
		attack.ignore_def_percent = float(weapon.armor_pierce_percent)
		# 策划案调整：正常攻击不施加击退，武器 knockback_m 仅作数据参考不参与结算
		# 仅踢击/冲撞等特定技能通过 skill.knockback_m 设置击退力
		attack.bonus_stun_duration = maxf(attack.bonus_stun_duration, float(weapon.stun_sec))
		# 应用词缀伤害倍率与吸血（策划案 34 实装）
		if "damage_mult" in weapon:
			attack.weapon_damage_mult *= float(weapon.damage_mult)
		if "lifesteal_percent" in weapon:
			attack.lifesteal_percent += float(weapon.lifesteal_percent)
		# 武器物理冲量倍率（大部分伤害带物理冲量，默认 1.0 恒等）
		if "impulse_mult" in weapon:
			attack.physical_impulse_multiplier *= maxf(float(weapon.impulse_mult), 0.0)
		return
	attack.weapon_damage_dice = {"count": 1, "sides": max(weapon.damage_max - weapon.damage_min + 1, 1)}
	attack.weapon_damage_flat = float(weapon.damage_min) - 1.0
	attack.weapon_damage_mult = 1.0


static func _apply_milestones_to_attack(attack: CE.AttackInput, main_hand_type: String, skill: Dictionary = {}) -> void:
	var is_melee := attack.attack_type == "melee"
	var is_ranged := attack.attack_type == "ranged"
	var is_spell := attack.attack_type == "spell"
	# 神射手（DEX T2）：远程暴击率 +10%（动作化替代原"命中率+10%"）
	attack.crit_bonus = ME.apply_sharpshooter_crit(attack.crit_bonus, is_ranged)
	# 穿透打击（DEX T3）：远程伤害 +12%（动作化替代原"无视10%物防"）
	attack.weapon_damage_mult = ME.apply_penetrating_damage(attack.weapon_damage_mult, is_ranged)
	attack.crit_bonus = ME.apply_mana_surge_crit(attack.crit_bonus, is_spell and not skill.is_empty())
	if is_melee and ME.apply_heavy_stride(100, true) > 100:
		attack.base_damage_bonus_percent += 5.0
	if main_hand_type == "two_hand":
		attack.base_damage_bonus_percent += ME.two_hand_damage_mult_bonus(true) * 100.0
	if is_spell and _has_bound_passive_skill("魔力涌动"):
		attack.base_damage_bonus_percent += 5.0


static func _apply_skill_to_attack(attack: CE.AttackInput, skill: Dictionary) -> void:
	if skill.is_empty():
		return
	var damage_mult := float(skill.get("damage_mult", 1.0))
	if damage_mult > 0.0:
		attack.weapon_damage_mult *= damage_mult
	attack.ignore_def_percent = maxf(attack.ignore_def_percent, float(skill.get("ignore_def", 0.0)))
	attack.ignore_block = bool(skill.get("ignore_block", false))
	attack.lifesteal_percent = maxf(attack.lifesteal_percent, float(skill.get("lifesteal", 0.0)))
	var knockback_m := float(skill.get("knockback_m", 0.0))
	if knockback_m > 0.0:
		attack.knockback_force = maxf(attack.knockback_force, knockback_m)
	var stun_sec := float(skill.get("stun_sec", 0.0))
	if stun_sec > 0.0:
		attack.bonus_stun_duration = maxf(attack.bonus_stun_duration, stun_sec)
	# 技能物理冲量倍率：缩放命中后的击退冲量（默认 1.0 不影响既有行为）
	var impulse_mult := float(skill.get("impulse_mult", 1.0))
	if impulse_mult > 0.0:
		attack.physical_impulse_multiplier *= impulse_mult
	if String(skill.get("id", "")) == "精准刺击":
		attack.force_crit = true


static func _apply_shield_to_defender(defender: CE.Defender, shield_resource = null) -> void:
	# 动作控制版：盾牌仅提供物理防御加成，格挡率/格挡值已移除
	# 格挡由受击方状态机（BLOCKING 状态）判定
	var phys_def := _read_int_field(shield_resource, "shield_phys_def", 0)
	if phys_def <= 0:
		var registry_shield: Variant = _get_registry_shield_data()
		phys_def = _read_int_field(registry_shield, "shield_phys_def", 0)
	defender.armor_def += phys_def


static func _get_equipment_shield_resource(eq):
	if eq != null and eq.has_method("get_active_shield_data"):
		return eq.get_active_shield_data()
	if eq != null and "shield_data" in eq:
		return eq.shield_data
	return null


static func _get_registry_shield_data():
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	var registry: Node = tree.root.get_node_or_null("WeaponRegistry")
	if registry != null and registry.has_method("get_weapon_data"):
		return registry.get_weapon_data("shield")
	return null


static func _has_bound_passive_skill(skill_id: String) -> bool:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return false
	var sr: Node = tree.root.get_node_or_null("SkillRuntime")
	return sr != null and sr.has_method("get_bound_passive_skills") and sr.get_bound_passive_skills().has(skill_id)


static func _read_int_field(source, field_name: String, fallback: int = 0) -> int:
	if source != null and field_name in source:
		return int(source.get(field_name))
	return fallback


static func _read_float_field(source, field_name: String, fallback: float = 0.0) -> float:
	if source != null and field_name in source:
		return float(source.get(field_name))
	return fallback
