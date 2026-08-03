class_name RuneEffectHooks
extends RefCounted

## 符文机制触发系统。
## 玩家命中敌人时，检查所有已装备符文的 mechanics 字段，施加对应的状态效果与机制。
##
## 调用入口：
##   on_player_hit_enemy(player, enemy, hit_position, damage_dealt)
##     — 由 PlayerSkillDispatcher / 投射物命中 / 近战状态机在命中后调用
##
## 被动查询入口（供 player.gd tick / 受伤结算调用）：
##   get_passive_bonuses() → Dictionary（汇总所有已装备符文的被动加成）
##
## 与 StatusEffectSystem 配合：所有状态效果通过 StatusEffectSystem.apply_status 施加，
## 写入 enemy.combat_debuffs 字典（se_ 前缀），与既有 debuff 系统兼容。

const RD := preload("res://globals/combat/rune_data.gd")
const SES := preload("res://globals/combat/status_effect_system.gd")
const Service := preload("res://globals/core/service.gd")

const STATUS_AURA_SCENE := preload("res://fx/status_aura.tscn")
const RUNE_HIT_BURST_SCENE := preload("res://fx/rune_hit_burst.tscn")

## 状态效果默认持续时间（符文未显式指定时）
const DEFAULT_BLIND_SEC := 3.0
const DEFAULT_STUN_SEC := 0.5
const DEFAULT_SLOW_MULT := 0.5
const DEFAULT_ARMOR_BREAK_VALUE := 5

# ============================================================================
# 1. 命中触发入口
# ============================================================================

## 玩家命中敌人后调用：检查所有已装备符文，施加机制效果。
## player: Player 节点
## enemy: 被命中的 Enemy 节点
## hit_position: 命中世界坐标（用于 VFX 生成）
## damage_dealt: 本次命中造成的最终伤害（用于吸血/处决判定）
static func on_player_hit_enemy(player: Node, enemy: Node, hit_position: Vector3, damage_dealt: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	var runes := _collect_equipped_runes()
	if runes.is_empty():
		return
	for rune_id in runes:
		var rune: Dictionary = RD.get_rune(String(rune_id))
		if rune.is_empty():
			continue
		var mechanics: Dictionary = rune.get("mechanics", {})
		if mechanics.is_empty():
			continue
		_apply_rune_mechanics(player, enemy, String(rune_id), mechanics, hit_position, damage_dealt)

## 收集所有已装备符文 id（7 个槽位的并集，去重）。
static func _collect_equipped_runes() -> Array:
	var sr: Node = Service.skill_runtime()
	if sr == null or not sr.has_method("get_slot_runes"):
		return []
	var result: Array = []
	for i in range(sr.TOTAL_SLOTS):
		var runes: Array = sr.get_slot_runes(i)
		for r in runes:
			var rid := String(r)
			if not rid.is_empty() and not result.has(rid):
				result.append(rid)
	return result

# ============================================================================
# 2. 单个符文机制应用
# ============================================================================

static func _apply_rune_mechanics(player: Node, enemy: Node, rune_id: String, m: Dictionary, hit_pos: Vector3, damage: int) -> void:
	# ── 概率触发型状态效果 ──
	if m.has("burn_chance"):
		_try_chance_status(enemy, int(m["burn_chance"]), "se_burn", float(m.get("burn_sec", 3.0)), null, hit_pos)
	if m.has("slow_chance"):
		var slow_sec := float(m.get("slow_sec", 2.0))
		_try_chance_status(enemy, int(m["slow_chance"]), "se_slow", slow_sec, DEFAULT_SLOW_MULT, hit_pos)
	if m.has("poison_chance"):
		_try_chance_status(enemy, int(m["poison_chance"]), "se_poison", float(m.get("poison_sec", 5.0)), null, hit_pos)
	if m.has("wet_chance"):
		_try_chance_status(enemy, int(m["wet_chance"]), "se_wet", float(m.get("slow_sec", 1.5)), null, hit_pos)
	if m.has("blind_chance"):
		# tejas/krishna/dhuma/tamas 都有 blind_chance，持续时间统一 3s
		_try_chance_status(enemy, int(m["blind_chance"]), "se_blind", DEFAULT_BLIND_SEC, null, hit_pos)
	if m.has("ensnare_chance"):
		_try_chance_status(enemy, int(m["ensnare_chance"]), "se_ensnare", float(m.get("ensnare_sec", 2.0)), null, hit_pos)
	if m.has("choke_chance"):
		var choke_dps := float(m.get("corrupt_dmg_per_sec", 2.0))
		_try_chance_status(enemy, int(m["choke_chance"]), "se_choke", float(m.get("choke_sec", 1.5)), choke_dps, hit_pos)
	if m.has("tremor_chance"):
		_try_chance_status(enemy, int(m["tremor_chance"]), "se_tremor", float(m.get("tremor_sec", 1.0)), null, hit_pos)
	if m.has("armor_break_chance"):
		var ab_value := int(m.get("armor_break_value", DEFAULT_ARMOR_BREAK_VALUE))
		_try_chance_status(enemy, int(m["armor_break_chance"]), "se_armor_break", float(m.get("armor_break_sec", 3.0)), ab_value, hit_pos)
	if m.has("fear_chance"):
		_try_chance_status(enemy, int(m["fear_chance"]), "se_fear", float(m.get("fear_sec", 3.0)), null, hit_pos)
	if m.has("terror_chance"):
		_try_chance_status(enemy, int(m["terror_chance"]), "se_terror", float(m.get("terror_sec", 2.5)), null, hit_pos)
	if m.has("sunder_chance"):
		_try_chance_status(enemy, int(m["sunder_chance"]), "se_sunder", float(m.get("armor_break_sec", 4.0)), null, hit_pos)
	if m.has("corrupt_chance"):
		var corrupt_dps := float(m.get("corrupt_dmg_per_sec", 4.0))
		_try_chance_status(enemy, int(m["corrupt_chance"]), "se_corrupt", float(m.get("corrupt_sec", 5.0)), corrupt_dps, hit_pos)

	# ── 眩晕（通过 enemy 状态机）──
	if m.has("stun_chance"):
		if _roll(int(m["stun_chance"])):
			_try_stun_enemy(enemy, float(m.get("stun_sec", DEFAULT_STUN_SEC)))

	# ── 时间减速（kala）──
	if m.has("enemy_slow_pct"):
		var slow_mult := 1.0 - float(m["enemy_slow_pct"])
		SES.apply_status(enemy, "se_slow", 3.0, slow_mult)
		_spawn_status_aura(enemy, "slow")

	# ── 吸血 / 生命汲取 ──
	if m.has("lifesteal_pct") and damage > 0:
		var heal_amount := maxi(1, int(damage * float(m["lifesteal_pct"]) / 100.0))
		_heal_player(player, heal_amount)
	if m.has("life_drain_pct") and damage > 0:
		var drain_amount := maxi(1, int(damage * float(m["life_drain_pct"]) / 100.0))
		_heal_player(player, drain_amount)

	# ── 处决（mrityu）──
	if m.has("execute_threshold"):
		_try_execute(enemy, float(m["execute_threshold"]))

	# ── 风推（pavana）──
	if m.get("wind_push", false):
		_apply_wind_push(player, enemy)

	# ── 光芒射线（marichi）──
	if m.has("ray_chance"):
		if _roll(int(m["ray_chance"])):
			_apply_ray_damage(enemy, damage)

# ============================================================================
# 3. 辅助函数
# ============================================================================

## 概率检定：返回 true 的概率为 chance_percent / 100
static func _roll(chance_percent: int) -> bool:
	if chance_percent <= 0:
		return false
	if chance_percent >= 100:
		return true
	return randi() % 100 < chance_percent

## 概率触发状态效果：命中时按概率施加状态，并生成对应 VFX 光环
static func _try_chance_status(enemy: Node, chance: int, status_type: String, duration: float, value: Variant, hit_pos: Vector3) -> void:
	if not _roll(chance):
		return
	SES.apply_status(enemy, status_type, duration, value)
	# 生成状态光环 VFX
	var aura_type := SES.get_aura_type(status_type)
	if not aura_type.is_empty():
		_spawn_status_aura(enemy, aura_type)

## 尝试眩晕敌人（通过状态机切换）
static func _try_stun_enemy(enemy: Node, stun_sec: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method("try_stun"):
		enemy.try_stun()
	# 额外通过 se_slow 模拟攻击速度减慢
	SES.apply_status(enemy, "se_slow", stun_sec, 0.3)

## 尝试处决低血量敌人
static func _try_execute(enemy: Node, threshold: float) -> void:
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
		# 处决：直接造成致命伤害
		if enemy.has_method("request_death"):
			var data := EnemyStateData.new().set_damage(current)
			enemy.call_deferred("request_death", data)

## 治疗玩家
static func _heal_player(player: Node, amount: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var health = player.get("health")
	if health == null or not is_instance_valid(health):
		return
	if health.has_method("heal"):
		health.heal(amount)
	else:
		health.current_life = clampi(int(health.current_life) + amount, 0, int(health.max_life))
	# VFX: 治疗飘字
	var fx := _get_fx_helper()
	if fx != null:
		var pos := (player as Node3D).global_position if (player is Node3D and (player as Node3D).is_inside_tree()) else Vector3.ZERO
		fx.call_deferred("create_heal_number", pos, amount)

## 风推：对敌人施加额外击退
static func _apply_wind_push(player: Node, enemy: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if not (player is Node3D) or not (enemy is Node3D):
		return
	if not (player as Node3D).is_inside_tree() or not (enemy as Node3D).is_inside_tree():
		return
	var dir := (player as Node3D).global_position.direction_to((enemy as Node3D).global_position)
	(enemy as CharacterBody3D).velocity += dir * 3.0

## 光芒射线：对敌人造成额外神圣伤害
static func _apply_ray_damage(enemy: Node, base_damage: int) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var health = enemy.get("health")
	if health == null or not is_instance_valid(health):
		return
	var ray_damage := maxi(2, base_damage / 3)
	health.call_deferred("take_damage", ray_damage)

# ============================================================================
# 4. VFX 生成
# ============================================================================

## 在敌人身上生成状态光环（持续型 VFX）
static func _spawn_status_aura(enemy: Node, aura_type: String) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not (enemy is Node3D):
		return
	if not (enemy as Node3D).is_inside_tree():
		return
	# 避免重复光环：检查是否已有同类型光环
	for child in enemy.get_children():
		if child is StatusAura:
			var aura := child as StatusAura
			if aura.get("_current_status") == aura_type:
				return  # 已有同类型光环，不重复生成
	var aura: StatusAura = STATUS_AURA_SCENE.instantiate() as StatusAura
	(enemy as Node3D).add_child(aura)
	aura.setup(enemy, aura_type)

## 在指定位置生成命中爆发（一次性 VFX）
static func spawn_hit_burst(position: Vector3, burst_type: int, color: Color = Color.WHITE) -> void:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return
	var burst: RuneHitBurst = RUNE_HIT_BURST_SCENE.instantiate() as RuneHitBurst
	if burst == null:
		return
	# 挂载到 root 以避免被命中目标 queue_free 时连带销毁
	tree.root.add_child(burst)
	burst.setup(burst_type, position, color)

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

# ============================================================================
# 5. 被动加成查询（供 player.gd tick / 受伤结算使用）
# ============================================================================

## 汇总所有已装备符文的被动加成，返回字典：
##   hp_regen_per_sec: float
##   stamina_regen_per_sec: float
##   lifesteal_pct: float
##   dodge_chance: float
##   cc_immune: bool
##   damage_reduce_pct: float
##   death_save: bool
##   fear_resist: int
##   stun_resist: int
##   dark_dmg_mult: float
##   holy_dmg_mult: float
##   undead_dmg_mult: float
##   righteous_dmg_mult: float
##   fear_dmg_mult: float
static func get_passive_bonuses() -> Dictionary:
	var runes := _collect_equipped_runes()
	var bonuses: Dictionary = {
		"hp_regen_per_sec": 0.0,
		"stamina_regen_per_sec": 0.0,
		"lifesteal_pct": 0.0,
		"dodge_chance": 0.0,
		"cc_immune": false,
		"damage_reduce_pct": 0.0,
		"death_save": false,
		"fear_resist": 0,
		"stun_resist": 0,
		"dark_dmg_mult": 1.0,
		"holy_dmg_mult": 1.0,
		"undead_dmg_mult": 1.0,
		"righteous_dmg_mult": 1.0,
		"fear_dmg_mult": 1.0,
	}
	for rune_id in runes:
		var rune: Dictionary = RD.get_rune(String(rune_id))
		if rune.is_empty():
			continue
		var m: Dictionary = rune.get("mechanics", {})
		if m.is_empty():
			continue
		if m.has("hp_regen_per_sec"):
			bonuses["hp_regen_per_sec"] = float(bonuses["hp_regen_per_sec"]) + float(m["hp_regen_per_sec"])
		if m.has("stamina_regen_per_sec"):
			bonuses["stamina_regen_per_sec"] = float(bonuses["stamina_regen_per_sec"]) + float(m["stamina_regen_per_sec"])
		if m.has("lifesteal_pct"):
			bonuses["lifesteal_pct"] = float(bonuses["lifesteal_pct"]) + float(m["lifesteal_pct"])
		if m.has("dodge_chance"):
			bonuses["dodge_chance"] = float(bonuses["dodge_chance"]) + float(m["dodge_chance"])
		if m.get("cc_immune", false):
			bonuses["cc_immune"] = true
		if m.has("damage_reduce_pct"):
			bonuses["damage_reduce_pct"] = float(bonuses["damage_reduce_pct"]) + float(m["damage_reduce_pct"])
		if m.get("death_save", false):
			bonuses["death_save"] = true
		if m.has("fear_resist"):
			bonuses["fear_resist"] = maxi(int(bonuses["fear_resist"]), int(m["fear_resist"]))
		if m.has("stun_resist"):
			bonuses["stun_resist"] = maxi(int(bonuses["stun_resist"]), int(m["stun_resist"]))
		if m.has("dark_dmg_mult"):
			bonuses["dark_dmg_mult"] = float(bonuses["dark_dmg_mult"]) * float(m["dark_dmg_mult"])
		if m.has("holy_dmg_mult"):
			bonuses["holy_dmg_mult"] = float(bonuses["holy_dmg_mult"]) * float(m["holy_dmg_mult"])
		if m.has("undead_dmg_mult"):
			bonuses["undead_dmg_mult"] = float(bonuses["undead_dmg_mult"]) * float(m["undead_dmg_mult"])
		if m.has("righteous_dmg_mult"):
			bonuses["righteous_dmg_mult"] = float(bonuses["righteous_dmg_mult"]) * float(m["righteous_dmg_mult"])
		if m.has("fear_dmg_mult"):
			bonuses["fear_dmg_mult"] = float(bonuses["fear_dmg_mult"]) * float(m["fear_dmg_mult"])
	return bonuses

## 获取玩家因符文获得的额外伤害倍率（对特定类型敌人）
## enemy_meta_key: 敌人 meta 中的类型标记（如 "undead", "evil"）
static func get_damage_mult_vs_type(enemy: Node, meta_key: String) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 1.0
	if not enemy.has_meta(meta_key):
		return 1.0
	var bonuses := get_passive_bonuses()
	match meta_key:
		"undead":
			return float(bonuses.get("undead_dmg_mult", 1.0))
		"evil":
			return float(bonuses.get("righteous_dmg_mult", 1.0))
	return 1.0
