class_name RuneWordPassiveHooks
extends RefCounted

## 符文之语机制被动实现。
## 28 个未落地的符文之语被动效果，按触发时机分组：
##
##   on_player_hit_enemy()   — 命中后触发（爆炸/减速/处决/风暴/致盲/汲取/陷阱/蔓延/震颤/猛击/击退/粉碎/雷电/恐惧增伤/业力递增）
##   on_player_take_damage() — 受伤时触发（大地护甲/闪避/狂暴/勇咒/解脱/不朽）
##   on_player_tick()        — 每帧触发（神圣恢复/生力/知苦/构造体）
##   on_enemy_killed()       — 击杀时触发（腐蚀区域）
##   get_outgoing_damage_mult() — 攻击伤害倍率查询（生力/勇咒/恐惧增伤/业力）
##   try_dodge()             — 闪避检定
##   has_cc_immune()         — 控制免疫检定
##
## 所有效果通过 player.has_mechanism_passive(id) 检查是否激活。
## VFX 通过 RuneEffectHooks.spawn_hit_burst() 生成。

const RD := preload("res://globals/combat/rune_data.gd")
const SES := preload("res://globals/combat/status_effect_system.gd")
const REH := preload("res://globals/combat/rune_effect_hooks.gd")
const Service := preload("res://globals/core/service.gd")

## 业力递增：记录每个敌人的连续命中层数
## key = enemy.get_instance_id(), value = stack_count
static var _karma_stacks: Dictionary = {}

## 构造体引用（同时只允许一个）
static var _construct_node: Node3D = null

## 腐蚀区域持续时间
const CORRUPT_ZONE_DURATION := 5.0
## 腐蚀区域半径
const CORRUPT_ZONE_RADIUS := 2.5
## 腐蚀区域每秒伤害
const CORRUPT_ZONE_DPS := 5.0
## 构造体攻击间隔
const CONSTRUCT_ATTACK_INTERVAL := 1.5
## 构造体攻击范围
const CONSTRUCT_ATTACK_RANGE := 4.0
## 构造体攻击伤害
const CONSTRUCT_DAMAGE := 6
## 风暴/爆炸/震颤 AoE 半径
const AOE_RADIUS := 3.0
## 连锁雷电最大跳跃数
const LIGHTNING_MAX_CHAIN := 3
## 连锁雷电衰减率
const LIGHTCHAIN_FALLOFF := 0.7

# ============================================================================
# 1. 命中后触发
# ============================================================================

## 玩家命中敌人后调用。
## context: { "is_kick": bool, "is_throw": bool, "is_charging": bool }
static func on_player_hit_enemy(player: Node, enemy: Node, hit_position: Vector3, damage_dealt: int, context: Dictionary = {}) -> void:
	if player == null or not is_instance_valid(player):
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if not player.has_method("has_mechanism_passive"):
		return

	# 1. 焰投之语：踢击/投掷命中时产生火焰爆炸
	if player.has_mechanism_passive("rune_word_throw_explosion"):
		if bool(context.get("is_kick", false)) or bool(context.get("is_throw", false)):
			_throw_explosion(player, enemy, hit_position, damage_dealt)

	# 2. 霜时之语：命中时减缓敌人
	if player.has_mechanism_passive("rune_word_hit_slow"):
		SES.apply_status(enemy, "se_slow", 2.0, 0.5)

	# 3. 死投之语：低血量敌人概率处决
	if player.has_mechanism_passive("rune_word_execute"):
		_execute_low_hp(enemy, 0.15)

	# 4. 风暴之语：概率产生范围击退与减速风暴
	if player.has_mechanism_passive("rune_word_storm"):
		if _roll(25):
			_storm_burst(player, enemy, hit_position)

	# 5. 炫光之语：概率致盲
	if player.has_mechanism_passive("rune_word_blinding_light"):
		if _roll(30):
			SES.apply_status(enemy, "se_blind", 3.0)
			REH.spawn_hit_burst(hit_position, 6, Color(1.0, 0.85, 0.3))  # HOLY_LIGHT

	# 6. 暗渊之语：对致盲敌人汲取生命
	if player.has_mechanism_passive("rune_word_dark_drain"):
		if SES.has_status(enemy, "se_blind") and damage_dealt > 0:
			var drain := maxi(2, int(damage_dealt * 0.15))
			_heal_player(player, drain)
			REH.spawn_hit_burst(enemy.global_position if enemy is Node3D else hit_position, 5, Color(0.5, 0.15, 0.6))  # DARK_DRAIN

	# 7. 烟泥之语：概率产生烟雾陷阱束缚敌人
	if player.has_mechanism_passive("rune_word_smoke_trap"):
		if _roll(20):
			SES.apply_status(enemy, "se_ensnare", 2.0)
			SES.apply_status(enemy, "se_choke", 2.0, 2.0)
			REH.spawn_hit_burst(hit_position, 3, Color(0.4, 0.4, 0.4))  # SMOKE_TRAP

	# 8. 毒流之语：毒素效果蔓延至周围敌人
	if player.has_mechanism_passive("rune_word_poison_spread"):
		if SES.has_status(enemy, "se_poison"):
			_spread_poison(enemy)

	# 9. 穿透之语：无视大量护甲（pre-hit modifier 已在 get_outgoing_damage_mult 中处理）
	# 此处仅生成 VFX 反馈
	if player.has_mechanism_passive("rune_word_armor_pierce"):
		pass  # 伤害倍率由 get_outgoing_damage_mult 处理

	# 10. 流震之语：攻击产生范围震颤伤害
	if player.has_mechanism_passive("rune_word_tremor"):
		if _roll(35):
			_tremor_aoe(player, enemy, hit_position, damage_dealt)

	# 11. 冲猛之语：冲刺攻击造成范围猛击
	if player.has_mechanism_passive("rune_word_charge_smash"):
		if bool(context.get("is_charging", false)):
			_charge_smash_aoe(player, enemy, hit_position, damage_dealt)

	# 12. 击推之语：命中产生强力击退
	if player.has_mechanism_passive("rune_word_impact_knockback"):
		_apply_impact_knockback(player, enemy)

	# 13. 猛破之语：概率直接粉碎敌人护甲
	if player.has_mechanism_passive("rune_word_sunder_smash"):
		if _roll(25):
			SES.apply_status(enemy, "se_sunder", 4.0)
			REH.spawn_hit_burst(hit_position, 4, Color(0.7, 0.5, 0.3))  # TREMOR

	# 14. 冲推之语：冲刺攻击大幅强化击退
	if player.has_mechanism_passive("rune_word_charge_knockback"):
		if bool(context.get("is_charging", false)):
			_apply_impact_knockback(player, enemy, 2.0)

	# 15. 雷穿之语：雷电穿透+连锁雷电
	if player.has_mechanism_passive("rune_word_thunder_stream"):
		if _roll(30):
			_thunder_chain(player, enemy, hit_position, damage_dealt)

	# 16. 怖毁之语：对恐惧状态敌人造成毁灭性额外伤害
	if player.has_mechanism_passive("rune_word_dreadful_destruction"):
		if SES.has_status(enemy, "se_fear") or SES.has_status(enemy, "se_terror"):
			_deal_bonus_damage(enemy, damage_dealt, 0.50)

	# 17. 业法之语：连续命中同一敌人伤害递增
	if player.has_mechanism_passive("rune_word_karmic_justice"):
		_apply_karma_stack(player, enemy, damage_dealt)

# ============================================================================
# 2. 受伤时触发
# ============================================================================

## 玩家受伤时调用，返回修正后的伤害值。
static func on_player_take_damage(player: Node, damage: int, enemy: Node) -> int:
	if player == null or not is_instance_valid(player):
		return damage
	if not player.has_method("has_mechanism_passive"):
		return damage
	var modified := damage

	# 大地护甲：减免固定伤害
	if player.has_mechanism_passive("rune_word_earth_armor"):
		modified = maxi(0, modified - 4)

	# 不朽之语：生命值不会低于1
	if player.has_mechanism_passive("rune_word_immortal_life"):
		var health = player.get("health")
		if health != null and is_instance_valid(health):
			var current := _get_int_prop(health, "current_life", 0)
			if current - modified < 1:
				modified = maxi(0, current - 1)

	# 狂暴状态：受伤增加（terrible_rage）
	if player.has_mechanism_passive("rune_word_terrible_rage"):
		modified = int(round(modified * 1.15))

	return modified

## 闪避检定：返回 true 表示闪避成功（完全免伤）
static func try_dodge(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("has_mechanism_passive"):
		return false
	if player.has_mechanism_passive("rune_word_dodge"):
		return _roll(20)
	return false

## 控制免疫检定
static func has_cc_immune(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("has_mechanism_passive"):
		return false
	return player.has_mechanism_passive("rune_word_perfect_liberation")

## 恐惧免疫检定
static func has_fear_immune(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("has_mechanism_passive"):
		return false
	return player.has_mechanism_passive("rune_word_brave_spell")

## 获取伤害减免比例
static func get_damage_reduce_pct(player: Node) -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	if not player.has_method("has_mechanism_passive"):
		return 0.0
	var reduce := 0.0
	if player.has_mechanism_passive("rune_word_perfect_liberation"):
		reduce += 0.15
	return reduce

# ============================================================================
# 3. 每帧触发
# ============================================================================

## 玩家每帧调用：处理持续型被动（恢复/构造体等）
static func on_player_tick(player: Node, delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("has_mechanism_passive"):
		return

	# 明护之语：持续恢复生命
	if player.has_mechanism_passive("rune_word_holy_bonus"):
		_regen_hp(player, 3.0 * delta)

	# 不朽之语：持续恢复生命
	if player.has_mechanism_passive("rune_word_immortal_life"):
		_regen_hp(player, 5.0 * delta)

	# 知苦之语：每秒消耗生命换取暴击加成
	if player.has_mechanism_passive("rune_word_arcane_focus"):
		_self_damage_tick(player, 1.0 * delta)

	# 构造体：自动攻击附近敌人
	if player.has_mechanism_passive("rune_word_construct_mind"):
		_update_construct(player, delta)

# ============================================================================
# 4. 击杀时触发
# ============================================================================

## 玩家击杀敌人后调用
static func on_enemy_killed(player: Node, enemy: Node, death_position: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("has_mechanism_passive"):
		return

	# 腐死之语：击杀时产生腐蚀区域
	if player.has_mechanism_passive("rune_word_corrupt_death"):
		_create_corrupt_zone(player, death_position)

	# 清理业力层数
	_clear_karma_stack(enemy)

	# 狂暴之语：击杀后使周围敌人恐惧
	if player.has_mechanism_passive("rune_word_terrible_rage"):
		_fear_nearby_enemies(player, death_position, AOE_RADIUS, 2.0)

# ============================================================================
# 5. 伤害倍率查询（攻击前调用）
# ============================================================================

## 获取玩家对指定敌人的额外伤害倍率
## 在 CombatBridge 结算前调用，乘到 skill.damage_mult 上
static func get_outgoing_damage_mult(player: Node, enemy: Node) -> float:
	if player == null or not is_instance_valid(player):
		return 1.0
	if not player.has_method("has_mechanism_passive"):
		return 1.0
	var mult := 1.0

	# 生力之语：生命值越高伤害越高（满血 +30%）
	if player.has_mechanism_passive("rune_word_vital_power"):
		var hp_ratio := _get_player_hp_ratio(player)
		mult *= 1.0 + 0.30 * hp_ratio

	# 勇咒之语：生命值越低伤害越高（残血 +40%）
	if player.has_mechanism_passive("rune_word_brave_spell"):
		var hp_ratio := _get_player_hp_ratio(player)
		mult *= 1.0 + 0.40 * (1.0 - hp_ratio)

	# 怖毁之语：对恐惧敌人额外 +50%
	if player.has_mechanism_passive("rune_word_dreadful_destruction"):
		if enemy != null and is_instance_valid(enemy):
			if SES.has_status(enemy, "se_fear") or SES.has_status(enemy, "se_terror"):
				mult *= 1.50

	# 业法之语：连续命中递增（每层 +5%，最高 +50%）
	if player.has_mechanism_passive("rune_word_karmic_justice"):
		if enemy != null and is_instance_valid(enemy):
			var stacks := _get_karma_stacks(enemy)
			mult *= 1.0 + 0.05 * float(stacks)

	# 穿透之语：无视大量护甲（以伤害倍率近似 +20%）
	if player.has_mechanism_passive("rune_word_armor_pierce"):
		mult *= 1.20

	# 解脱之语：全面提升属性 +15%
	if player.has_mechanism_passive("rune_word_perfect_liberation"):
		mult *= 1.15

	return mult

# ============================================================================
# 6. 内部实现 — 命中效果
# ============================================================================

## 焰投之语：火焰爆炸 AoE
static func _throw_explosion(player: Node, enemy: Node, hit_pos: Vector3, base_damage: int) -> void:
	REH.spawn_hit_burst(hit_pos, 0, Color(1.0, 0.45, 0.1))  # FIRE_EXPLOSION
	var explosion_damage := maxi(3, int(base_damage * 0.4))
	var nearby := _get_nearby_enemies(hit_pos, AOE_RADIUS, enemy)
	for target in nearby:
		if target == null or not is_instance_valid(target):
			continue
		_deal_bonus_damage(target, explosion_damage, 0.0)
		SES.apply_status(target, "se_burn", 3.0, 4.0)

## 风暴之语：范围击退与减速
static func _storm_burst(player: Node, enemy: Node, hit_pos: Vector3) -> void:
	REH.spawn_hit_burst(hit_pos, 1, Color(0.3, 0.7, 1.0))  # STORM
	var nearby := _get_nearby_enemies(hit_pos, AOE_RADIUS, null)
	for target in nearby:
		if target == null or not is_instance_valid(target):
			continue
		SES.apply_status(target, "se_slow", 2.0, 0.5)
		# 击退
		if target is CharacterBody3D and player is Node3D:
			var dir := (player as Node3D).global_position.direction_to((target as Node3D).global_position)
			(target as CharacterBody3D).velocity += dir * 4.0

## 毒素蔓延：将中毒效果传播给周围敌人
static func _spread_poison(source_enemy: Node) -> void:
	if not (source_enemy is Node3D):
		return
	var pos := (source_enemy as Node3D).global_position
	var nearby := _get_nearby_enemies(pos, AOE_RADIUS, source_enemy)
	for target in nearby:
		SES.apply_status(target, "se_poison", 3.0, 3.0)

## 流震之语：范围震颤伤害
static func _tremor_aoe(player: Node, enemy: Node, hit_pos: Vector3, base_damage: int) -> void:
	REH.spawn_hit_burst(hit_pos, 4, Color(0.7, 0.5, 0.3))  # TREMOR
	var tremor_damage := maxi(2, int(base_damage * 0.3))
	var nearby := _get_nearby_enemies(hit_pos, AOE_RADIUS, enemy)
	for target in nearby:
		_deal_bonus_damage(target, tremor_damage, 0.0)
		SES.apply_status(target, "se_tremor", 1.0)

## 冲猛之语：冲刺攻击范围猛击
static func _charge_smash_aoe(player: Node, enemy: Node, hit_pos: Vector3, base_damage: int) -> void:
	REH.spawn_hit_burst(hit_pos, 4, Color(0.7, 0.5, 0.3))  # TREMOR
	var smash_damage := maxi(3, int(base_damage * 0.5))
	var nearby := _get_nearby_enemies(hit_pos, AOE_RADIUS, enemy)
	for target in nearby:
		_deal_bonus_damage(target, smash_damage, 0.0)
		_apply_impact_knockback(player, target)

## 击退之语：强力击退
static func _apply_impact_knockback(player: Node, enemy: Node, mult: float = 1.0) -> void:
	if not (player is Node3D) or not (enemy is Node3D):
		return
	if not (enemy is CharacterBody3D):
		return
	var dir := (player as Node3D).global_position.direction_to((enemy as Node3D).global_position)
	(enemy as CharacterBody3D).velocity += dir * 5.0 * mult

## 雷穿之语：连锁雷电
static func _thunder_chain(player: Node, source_enemy: Node, hit_pos: Vector3, base_damage: int) -> void:
	REH.spawn_hit_burst(hit_pos, 2, Color(1.0, 0.9, 0.2))  # LIGHTNING_CHAIN
	var chain_damage := maxi(2, int(base_damage * 0.4))
	var current_pos := hit_pos
	var hit_set: Array = [source_enemy]
	for i in range(LIGHTNING_MAX_CHAIN):
		var next_enemy := _find_nearest_enemy(current_pos, AOE_RADIUS, hit_set)
		if next_enemy == null:
			break
		hit_set.append(next_enemy)
		var next_pos := (next_enemy as Node3D).global_position
		_deal_bonus_damage(next_enemy, chain_damage, 0.0)
		SES.apply_status(next_enemy, "se_slow", 0.5, 0.3)
		REH.spawn_hit_burst(next_pos, 2, Color(1.0, 0.9, 0.2))
		current_pos = next_pos
		chain_damage = int(chain_damage * LIGHTCHAIN_FALLOFF)

## 处决低血量敌人
static func _execute_low_hp(enemy: Node, threshold: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var health = enemy.get("health")
	if health == null or not is_instance_valid(health):
		return
	var current := _get_int_prop(health, "current_life", 0)
	var max_life := _get_int_prop(health, "max_life", 1)
	if max_life <= 0:
		return
	var hp_ratio := float(current) / float(max_life)
	if hp_ratio <= threshold:
		if enemy.has_method("request_death"):
			var data := EnemyStateData.new().set_damage(current)
			enemy.call_deferred("request_death", data)

## 业力递增：记录命中层数并施加额外伤害
static func _apply_karma_stack(player: Node, enemy: Node, base_damage: int) -> void:
	var eid := enemy.get_instance_id()
	var stacks := int(_karma_stacks.get(eid, 0))
	if stacks < 10:
		stacks += 1
		_karma_stacks[eid] = stacks
	# 额外伤害（每层 5% base_damage）
	var bonus := int(base_damage * 0.05 * float(stacks))
	if bonus > 0:
		_deal_bonus_damage(enemy, bonus, 0.0)

# ============================================================================
# 7. 内部实现 — 持续效果
# ============================================================================

## 恢复玩家生命
static func _regen_hp(player: Node, amount: float) -> void:
	var health = player.get("health")
	if health == null or not is_instance_valid(health):
		return
	var current := _get_int_prop(health, "current_life", 0)
	var max_life := _get_int_prop(health, "max_life", 1)
	if current >= max_life:
		return
	var heal_amount := int(amount)
	if heal_amount > 0:
		if health.has_method("heal"):
			health.heal(heal_amount)
		else:
			health.current_life = mini(current + heal_amount, max_life)

## 知苦之语：每秒消耗生命
static var _arcane_focus_tick_accum: float = 0.0
static func _self_damage_tick(player: Node, delta: float) -> void:
	_arcane_focus_tick_accum += delta
	if _arcane_focus_tick_accum < 1.0:
		return
	_arcane_focus_tick_accum = 0.0
	var health = player.get("health")
	if health == null or not is_instance_valid(health):
		return
	var current := _get_int_prop(health, "current_life", 0)
	if current > 5:
		if health.has_method("take_damage"):
			health.take_damage(2)
		else:
			health.current_life = maxi(1, current - 2)

## 构造体：自动攻击附近敌人
static var _construct_attack_timer: float = 0.0
static func _update_construct(player: Node, delta: float) -> void:
	if not (player is Node3D):
		return
	if not (player as Node3D).is_inside_tree():
		return
	# 构造体不存在时创建
	if _construct_node == null or not is_instance_valid(_construct_node):
		_construct_node = Node3D.new()
		_construct_node.name = "RuneConstruct"
		(player as Node3D).add_child(_construct_node)
	# 跟随玩家
	_construct_node.global_position = (player as Node3D).global_position + Vector3(0, 1.5, 0)
	# 攻击计时
	_construct_attack_timer += delta
	if _construct_attack_timer < CONSTRUCT_ATTACK_INTERVAL:
		return
	_construct_attack_timer = 0.0
	# 查找附近敌人并攻击
	var nearby := _get_nearby_enemies(_construct_node.global_position, CONSTRUCT_ATTACK_RANGE, null)
	if nearby.is_empty():
		return
	var target = nearby[0]
	if target != null and is_instance_valid(target):
		_deal_bonus_damage(target, CONSTRUCT_DAMAGE, 0.0)
		var pos := (target as Node3D).global_position if target is Node3D else _construct_node.global_position
		REH.spawn_hit_burst(pos, 2, Color(0.5, 0.7, 1.0))  # LIGHTNING_CHAIN (cyan tint)

# ============================================================================
# 8. 内部实现 — 击杀效果
# ============================================================================

## 腐蚀区域：持续伤害周围敌人
static func _create_corrupt_zone(player: Node, position: Vector3) -> void:
	if not (player is Node3D):
		return
	if not (player as Node3D).is_inside_tree():
		return
	# 创建一个临时 Area3D 作为腐蚀区域
	var zone := Area3D.new()
	zone.name = "CorruptZone"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CORRUPT_ZONE_RADIUS
	shape.shape = sphere
	zone.add_child(shape)
	zone.global_position = position
	(player as Node3D).get_parent().add_child(zone)
	# VFX
	REH.spawn_hit_burst(position, 5, Color(0.5, 0.1, 0.15))  # DARK_DRAIN
	# 使用一个 Node + _process 来驱动 DoT
	var driver := Node.new()
	driver.name = "CorruptZoneDriver"
	zone.add_child(driver)
	driver.set_script(preload("res://globals/combat/corrupt_zone_driver.gd"))
	# 传递参数（通过 meta）
	zone.set_meta("dps", CORRUPT_ZONE_DPS)
	zone.set_meta("duration", CORRUPT_ZONE_DURATION)
	zone.set_meta("radius", CORRUPT_ZONE_RADIUS)
	# 自动清理：duration 到期后 queue_free
	var timer := Timer.new()
	timer.wait_time = CORRUPT_ZONE_DURATION
	timer.one_shot = true
	timer.timeout.connect(zone.queue_free)
	zone.add_child(timer)
	timer.start()

## 使周围敌人恐惧
static func _fear_nearby_enemies(player: Node, center: Vector3, radius: float, duration: float) -> void:
	var nearby := _get_nearby_enemies(center, radius, null)
	for target in nearby:
		SES.apply_status(target, "se_fear", duration)

# ============================================================================
# 9. 辅助函数
# ============================================================================

## 概率检定
static func _roll(chance_percent: int) -> bool:
	if chance_percent <= 0:
		return false
	if chance_percent >= 100:
		return true
	return randi() % 100 < chance_percent

## 获取玩家 HP 比例 (0.0 ~ 1.0)
static func _get_player_hp_ratio(player: Node) -> float:
	var health = player.get("health")
	if health == null or not is_instance_valid(health):
		return 1.0
	var current := _get_int_prop(health, "current_life", 1)
	var max_life := _get_int_prop(health, "max_life", 1)
	if max_life <= 0:
		return 1.0
	return clampf(float(current) / float(max_life), 0.0, 1.0)

## 治疗玩家
static func _heal_player(player: Node, amount: int) -> void:
	var health = player.get("health")
	if health == null or not is_instance_valid(health):
		return
	if health.has_method("heal"):
		health.heal(amount)
	else:
		var current := _get_int_prop(health, "current_life", 0)
		var max_life := _get_int_prop(health, "max_life", 1)
		health.current_life = mini(current + amount, max_life)

## 对敌人造成额外伤害
static func _deal_bonus_damage(enemy: Node, bonus: int, mult: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var health = enemy.get("health")
	if health == null or not is_instance_valid(health):
		return
	var total := bonus + int(bonus * mult)
	if total <= 0:
		return
	health.call_deferred("take_damage", total)
	# VFX: 飘字
	var fx := _get_fx_helper()
	if fx != null and enemy is Node3D and (enemy as Node3D).is_inside_tree():
		var pos := (enemy as Node3D).global_position + Vector3(0, 1.5, 0)
		fx.call_deferred("create_damage_number_flags", pos, total, false, false, false, false)

## 获取指定位置附近的敌人列表
## exclude: 要排除的敌人（通常是主目标）
static func _get_nearby_enemies(center: Vector3, radius: float, exclude: Node) -> Array:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return []
	var enemies: Array = tree.root.find_children("*", "Enemy", true, false)
	# 如果 find_children 找不到（headless），回退到 group 查询
	if enemies.is_empty():
		enemies = tree.root.get_nodes_in_group("enemies")
	var result: Array = []
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		if e == exclude:
			continue
		if not (e is Node3D):
			continue
		var dist := (e as Node3D).global_position.distance_to(center)
		if dist <= radius:
			result.append(e)
	return result

## 查找最近的敌人（用于连锁雷电）
static func _find_nearest_enemy(center: Vector3, radius: float, exclude: Array) -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	var enemies: Array = tree.root.find_children("*", "Enemy", true, false)
	if enemies.is_empty():
		enemies = tree.root.get_nodes_in_group("enemies")
	var best: Node = null
	var best_dist := radius
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		if exclude.has(e):
			continue
		if not (e is Node3D):
			continue
		var dist := (e as Node3D).global_position.distance_to(center)
		if dist < best_dist:
			best_dist = dist
			best = e
	return best

## 获取业力层数
static func _get_karma_stacks(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	return int(_karma_stacks.get(enemy.get_instance_id(), 0))

## 清理业力层数
static func _clear_karma_stack(enemy: Node) -> void:
	if enemy == null:
		return
	_karma_stacks.erase(enemy.get_instance_id())

## 获取 FxHelper autoload
static func _get_fx_helper() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("FxHelper")

## 安全获取 Object 的 int 属性（Godot 4 的 Object.get() 不支持默认值参数）
static func _get_int_prop(obj, prop: String, default_val: int = 0) -> int:
	if obj == null:
		return default_val
	var val = obj.get(prop)
	if val == null:
		return default_val
	return int(val)

## 清理所有静态状态（测试用）
static func reset_static_state() -> void:
	_karma_stacks.clear()
	_construct_node = null
	_construct_attack_timer = 0.0
	_arcane_focus_tick_accum = 0.0
