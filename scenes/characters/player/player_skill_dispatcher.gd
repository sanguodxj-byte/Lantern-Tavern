class_name PlayerSkillDispatcher
## 玩家技能分发器（从 player.gd 提取）
## 负责技能释放后的效果分发：动作技能→位移/状态切换；武器技能→CombatBridge 结算
extends RefCounted

const AS_DB := preload("res://globals/combat/action_skills.gd")
const SD_DB := preload("res://globals/combat/skill_data.gd")
const CB_LIB := preload("res://globals/combat/combat_bridge.gd")
const CE_LIB := preload("res://globals/combat/combat_engine.gd")
const Service := preload("res://globals/core/service.gd")

## 技能释放完成后触发实际游戏内效果
static func on_skill_released(player: Player, skill_id: String) -> void:
	var sr: Node = Service.skill_runtime()
	var skill: Dictionary = sr.get_effective_skill_definition(skill_id) if sr != null and sr.has_method("get_effective_skill_definition") else {}
	if skill.is_empty():
		skill = AS_DB.get_skill_by_id(skill_id)
	if skill.is_empty():
		skill = SD_DB.get_skill_by_id(skill_id)
	var action_skill: Dictionary = AS_DB.get_skill_by_id(skill_id)
	if not action_skill.is_empty():
		dispatch_action_skill(player, skill)
		return
	if not skill.is_empty():
		dispatch_weapon_skill(player, skill)

## 动作技能分发：踢击/冲撞/抓取投掷/滑铲/战术滑步
static func dispatch_action_skill(player: Player, skill: Dictionary) -> void:
	var enum_val: int = int(skill.get("enum", -1))
	match enum_val:
		AS_DB.ActionSkill.KICK:
			player.switch_state(Player.State.KICKING)
		AS_DB.ActionSkill.CHARGE:
			if Input.is_action_pressed("run"):
				player.switch_state(Player.State.CHARGING)
			else:
				print("[Player] 冲撞需要先按 Shift 跑起来")
		AS_DB.ActionSkill.GRAB_THROW:
			var grab_target := _find_grab_target(player)
			if grab_target != null:
				var data := PlayerStateData.new().set_grabbed_enemy(grab_target)
				player.switch_state(Player.State.GRABBING, data)
			else:
				print("[Player] 抓取未命中敌人")
		AS_DB.ActionSkill.SLIDE:
			apply_dash(player, int(skill.get("range_m", 4.0)), 8.0)
		AS_DB.ActionSkill.TACTICAL_STEP:
			apply_dash(player, int(skill.get("range_m", 3.0)), 6.0)

## 武器流派技能分发：远程/法术流派生成投射物，近战流派走 raycast 结算
static func dispatch_weapon_skill(player: Player, skill: Dictionary) -> void:
	var weapon = player.equipment.weapon_data if player.equipment.has_weapon() else null
	var attrs := _get_player_attrs()
	var level := _get_player_level()
	var main_type := CB_LIB.get_weapon_class(weapon)
	var off_type := "shield" if player.equipment.has_shield() else ""
	_apply_self_skill_buff(player, skill)
	# 远程/法术技能：生成投射物（投射物命中时结算伤害 + debuff）
	var ps: Node = Service.projectile_service()
	if ps != null:
		var projectile_id: String = ps.get_projectile_id_for_skill(skill, weapon)
		if projectile_id != "":
			_spawn_skill_projectile(player, skill, weapon, projectile_id, ps)
			return
	# 近战技能：raycast 前方敌人结算
	if player._raycast_is_colliding(player.weapon_reach_raycast):
		var collider := player.weapon_reach_raycast.get_collider() as Node
		var enemy := collider as Enemy
		if enemy != null:
			_apply_enemy_skill_debuff(enemy, skill)
			if float(skill.get("damage_mult", 0.0)) <= 0.0:
				return
			var atk_forward := -player.global_transform.basis.z.normalized()
			var def_forward := -enemy.global_transform.basis.z.normalized()
			var is_back: bool = CB_LIB.is_backstab(atk_forward, def_forward)
			var result = CB_LIB.resolve_player_attack(player, enemy, weapon, main_type, off_type, attrs, level, is_back, skill)
			if result.hit:
				enemy.try_receive_hit_result(player, result)
				_apply_lifesteal(player, result)
		elif collider != null and collider.has_method("try_receive_hit"):
			var object_damage := int(max(1.0, float(skill.get("damage_mult", 1.0)) * 4.0))
			collider.try_receive_hit(player, object_damage)

## 生成技能投射物（支持双发/齐射/单体）
static func _spawn_skill_projectile(player: Player, skill: Dictionary, weapon, projectile_id: String, ps: Node) -> void:
	var spawn_transform := _get_skill_spawn_transform(player)
	var skill_id := String(skill.get("id", ""))
	match skill_id:
		"双发连射":
			ps.spawn_double(projectile_id, spawn_transform, player, weapon, skill, 3.0)
		"压制齐射":
			ps.spawn_spread(projectile_id, spawn_transform, player, 3, 15.0, weapon, skill)
		"弩箭齐射":
			ps.spawn_spread(projectile_id, spawn_transform, player, 5, 20.0, weapon, skill)
		_:
			ps.spawn(projectile_id, spawn_transform, player, weapon, skill)
	# 武器耐久磨损（技能释放时消耗）
	if player.equipment != null and player.equipment.has_method("apply_weapon_damage"):
		player.equipment.apply_weapon_damage(2)
	# 音效
	AudioManager.play("slash", player.action_audio_stream_player)

## 获取技能投射物生成位置（朝准心方向）
static func _get_skill_spawn_transform(player: Player) -> Transform3D:
	var eq := player.equipment
	var muzzle_pos: Vector3
	if eq != null and eq.weapon_spawn_position != null and is_instance_valid(eq.weapon_spawn_position):
		muzzle_pos = eq.weapon_spawn_position.global_position
	else:
		muzzle_pos = player.global_position + (-player.global_transform.basis.z * 1.0)
	return player.get_aim_transform(muzzle_pos)

## 向前冲刺位移（冲撞/滑铲/战术滑步通用）
static func apply_dash(player: Player, distance_m: int, speed_mps: float) -> void:
	var forward := -player.global_transform.basis.z.normalized()
	player.pushback_force += forward * speed_mps

## 对敌人施加动作技能伤害
static func apply_action_skill_hit(player: Player, enemy: Enemy, skill: Dictionary) -> void:
	if enemy == null or skill.is_empty():
		return
	var knockback_m: float = float(skill.get("knockback_m", 0.0))
	var stun_sec: float = float(skill.get("stun_sec", 0.0))
	var forward := -player.global_transform.basis.z.normalized()
	var damage_mult := 1.0
	var knockback_mult := 1.0
	var sr: Node = Service.skill_runtime()
	if sr != null and sr.has_method("consume_momentum_context"):
		var ctx = sr.consume_momentum_context()
		if ctx != null and ctx.has_method("build_bonus"):
			var bonus: Dictionary = ctx.build_bonus(skill, forward)
			damage_mult = float(bonus.get("damage_multiplier", 1.0))
			knockback_mult = float(bonus.get("knockback_multiplier", 1.0))
	var result := CE_LIB.DamageResult.new()
	result.hit = true
	result.final_damage = int(max(1.0, float(skill.get("damage_mult", 0.5)) * 4.0 * damage_mult))
	result.knockback_force = knockback_m * 2.0 * knockback_mult
	result.knockback_impulse = forward * knockback_m * knockback_mult
	result.stun_duration = stun_sec
	result.physical_impact_enabled = bool(skill.get("physical_impact_enabled", false))
	result.physical_impact_damage_mult = float(skill.get("physical_impact_damage_mult", 1.0))
	result.physical_impact_min_speed = float(skill.get("physical_impact_min_speed", 4.0))
	result.physical_impact_full_speed = float(skill.get("physical_impact_full_speed", 14.0))
	if bool(skill.get("breaks_shield", false)) and enemy.equipment != null and enemy.equipment.has_shield():
		enemy.equipment.drop_shield()
		result.ignores_block = true
	enemy.try_receive_hit_result(player, result)

static func apply_kick_hit(player: Player, enemy: Enemy) -> void:
	var skill := AS_DB.get_skill_by_id("踢击")
	var sr: Node = Service.skill_runtime()
	if sr != null and sr.has_method("get_effective_skill_definition"):
		var effective: Dictionary = sr.get_effective_skill_definition("踢击")
		if not effective.is_empty():
			skill = effective
	apply_action_skill_hit(player, enemy, skill)

static func _apply_self_skill_buff(player: Player, skill: Dictionary) -> void:
	var buff_type := String(skill.get("buff_type", ""))
	var duration := float(skill.get("buff_sec", 0.0))
	match buff_type:
		"def_and_evade_up", "damage_absorb", "slow_and_haste":
			player.add_combat_buff(buff_type, duration, skill.get("buff_value", 0))

static func _apply_enemy_skill_debuff(enemy: Enemy, skill: Dictionary) -> void:
	var buff_type := String(skill.get("buff_type", ""))
	var duration := float(skill.get("buff_sec", 0.0))
	if duration <= 0.0 or enemy == null or not enemy.has_method("apply_combat_debuff"):
		return
	match buff_type:
		"def_down", "slow", "evade_down", "ground_ice", "root_and_dmg_down", "slow_and_haste":
			enemy.apply_combat_debuff(buff_type, duration, skill.get("buff_value", 0))

static func _apply_lifesteal(player: Player, result) -> void:
	if result.lifesteal_amount <= 0 or player.health == null:
		return
	if player.health.has_method("heal"):
		player.health.heal(result.lifesteal_amount)
	else:
		player.health.current_life = clampi(player.health.current_life + result.lifesteal_amount, 0, player.health.max_life)
	FxHelper.create_heal_number(player.global_position, result.lifesteal_amount)

static func _get_player_attrs() -> Dictionary:
	var ap: Node = Service.attr_panel()
	if ap != null:
		return ap.get_player_attrs()
	return {"str": 10, "dex": 10, "agi": 10, "con": 10, "per": 10, "mag": 10}

static func _get_player_level() -> int:
	var ap: Node = Service.attr_panel()
	if ap != null:
		return ap.get_level()
	return 1

## 查找抓取目标：优先使用 kick_raycast，未命中时使用球形查询检测前方近距离敌人。
## 解决敌人贴近玩家（<0.5m）时 raycast 射线起点在碰撞体内部导致无法命中的问题。
static func _find_grab_target(player: Player) -> Enemy:
	# 1. 优先用 kick_raycast 探测
	if player._raycast_is_colliding(player.kick_raycast):
		var target := player.kick_raycast.get_collider() as Enemy
		if target != null:
			return target
	# 2. 后备：球形查询前方 2m 内最近的敌人
	var grab_range := 2.0
	var origin := player.global_position + Vector3(0, 1.0, 0)
	var forward := -player.global_transform.basis.z.normalized()
	# 从玩家中心向前方延伸的球形查询
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = SphereShape3D.new()
	query.shape.radius = grab_range
	query.transform = Transform3D(Basis.IDENTITY, origin + forward * grab_range * 0.5)
	query.collision_mask = 4  # LAYER_ENEMY
	query.exclude = [player.get_rid()]
	var results := space.intersect_shape(query, 32)
	var best_enemy: Enemy = null
	var best_dist := grab_range + 1.0
	for result in results:
		var enemy := result.collider as Enemy
		if enemy == null:
			continue
		# 检查敌人在玩家前方（而非身后）
		var to_enemy := enemy.global_position - player.global_position
		to_enemy.y = 0.0
		if to_enemy.length() < 0.01:
			return enemy  # 几乎重合，直接抓取
		var dot := forward.dot(to_enemy.normalized())
		if dot < 0.0:
			continue  # 在身后，跳过
		var dist := to_enemy.length()
		if dist < best_dist:
			best_dist = dist
			best_enemy = enemy
	return best_enemy
