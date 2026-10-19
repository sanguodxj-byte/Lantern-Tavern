class_name SessionCombatService
extends RefCounted

## 战斗命令编排服务（ADR-003 渐进拆分：SessionRoot 第二刀）。
## 从 SessionRoot 迁出 combat 命令族：attack / cast_spell / skill 事务，
## 以及战斗副作用（实体击杀/掉落、法术世界执行器装配、技能/法术伤害端口、
## 权威安全位移、自目标效果）。
##
## 依赖约定：共享状态容器与保留 API 经 `_r`（SessionRoot 引用）访问——
## _ctx_peer/_seq_tracker/_live_state/_entities/_attack_cd_until/_stagger/_loot_seq、
## registry/world/combat_auth/spell_auth/skill_auth/loot_auth/movement_motor、
## _reject/_weapon_registry/remove_entity/update_entity/set_entity/set_player_position/
## track_projectile/_progression_event/server_roll_loot/broadcast_player_combat_state。

const NP := preload("res://globals/multiplayer/network_protocol.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")
const AttackContextFactoryClass := preload("res://globals/combat/attack_context_factory.gd")
const DamageResolverClass := preload("res://globals/combat/damage_resolver.gd")
const AttackCadencePolicyClass := preload("res://globals/combat/attack_cadence_policy.gd")
const SpellRecipeDataClass := preload("res://globals/combat/spell_recipe_data.gd")
const SpellAuthorityClass := preload("res://globals/combat/spell_authority.gd")
const SpellAccessPolicyClass := preload("res://globals/combat/spell_access_policy.gd")
const SpellWorldExecutorClass := preload("res://globals/combat/spell_world_executor.gd")
const SkillAuthorityClass := preload("res://globals/multiplayer/skill_authority.gd")
const CombatAuthorityClass := preload("res://globals/multiplayer/combat_authority.gd")
const ProgressionAuthorityClass := preload("res://globals/multiplayer/progression_authority.gd")
const ServiceClass := preload("res://globals/core/service.gd")

## SessionRoot 引用（无类型：避免循环 preload 与 Node 静态成员限制）。
var _r = null

## 攻击意图允许携带的字段（P0-2：拒绝任何攻击类型/伤害/射程自报字段）。
const ATTACK_INTENT_FIELDS := ["type", "protocol_version", "world_revision", "client_tick", "sequence", "hand", "charge_ratio", "target_hint"]
const ATTACK_SECTOR_HALF_COS := 0.259

func _init(root: Node) -> void:
	_r = root

# ============================================================================
# 普通攻击事务
# ============================================================================

## 从权威 PlayerContext 构造唯一 AttackContext（AttackContextFactory）：
## 武器骰/倍率/流派/射程全部来自服务器权威 loadout + 属性，不接受客户端自报。
func build_attack_context(ctx: PlayerContextClass, command: Dictionary, registry: Object) -> Dictionary:
	var hand: String = String(command.get("hand", "primary"))
	if hand != "primary" and hand != "secondary":
		hand = "primary"
	var charge_ratio: float = clampf(float(command.get("charge_ratio", 1.0)), 0.0, 1.0)
	var attrs: Dictionary = ctx.attributes.get_player_attrs() if ctx.attributes != null else {}
	var level: int = ctx.attributes.get_level() if ctx.attributes != null else 1
	var actx = AttackContextFactoryClass.build_from_player_state(
		attrs, level, ctx.loadout, registry, hand, charge_ratio, command.get("target_hint", 0))
	return {
		"context": actx,
		"hand": hand,
		"charge_ratio": charge_ratio,
		"attack_input": AttackContextFactoryClass.to_attack_input(actx),
		"range": actx.attack_range(),
	}

## 客户端请求攻击（CMD_ATTACK）：权威事务——意图字段白名单 → 目标/朝向/冷却/硬直
## 校验 → 唯一 AttackContext → 武器归属 → 结算 → 冷却提交 → 实体血写回/击杀/掉落。
func handle_combat(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	var live: Dictionary = _r.live_state().get(peer_id, {})
	# P0-2：攻击意图只允许携带上述字段（拒绝任何攻击类型/伤害/射程自报字段，防伪报 ranged）。
	for key in command.keys():
		if not (key in ATTACK_INTENT_FIELDS):
			return {"success": false, "event": {}, "error_code": NP.ERR_INVALID_STATE}
	var err: String = _r.combat_auth.validate_attack_request(command, live, _r.world.world_revision, _r.seq_tracker())
	if err != "":
		return {"success": false, "event": {}, "error_code": err}
	var current_time: float = _r.current_time
	# Phase 3：攻击权威目标/朝向/状态校验（存活/射程/朝向/冷却/硬直）——全部基于服务器权威数据。
	var defender_entity_id: int = int(command.get("target_hint", 0))
	var target_data: Dictionary = _r.entities().get(defender_entity_id, {})
	var attacker_snapshot := {
		"position": live.get("position", Vector3.ZERO),
		"facing": live.get("facing", Vector3(0, 0, -1)),
		"cooldown_remaining": float(_r.attack_cd_until().get(peer_id, -1.0)) - current_time,
		"stagger_remaining": float(_r.stagger().get(peer_id, 0.0)),
	}
	var target_snapshot := {
		"exists": _r.entities().has(defender_entity_id),
		"position": target_data.get("position", Vector3.ZERO),
		"los_ok": bool(target_data.get("los_ok", true)),
	}
	# 装备唯一来源：AttackContextFactory（武器/流派/射程/伤害全部来自权威 loadout）。
	var built: Dictionary = build_attack_context(ctx, command, _r.weapon_registry())
	var actx = built["context"]
	var atk_cfg := {
		"max_range": float(built["range"]),
		"sector_half_cos": ATTACK_SECTOR_HALF_COS,
		"allow_missing_target": true,
	}
	var terr: String = _r.combat_auth.validate_attack_targeting(attacker_snapshot, target_snapshot, atk_cfg)
	if terr != "":
		return {"success": false, "event": {}, "error_code": terr}
	# 武器归属校验：攻击者必须实际持有该武器（仍在其权威 loadout 内）。
	var owned_weapons: Array = []
	for raw_id in ctx.loadout.weapon_slots:
		owned_weapons.append(String(raw_id))
	if not CombatAuthorityClass.validate_weapon_ownership(actx.weapon_id(), owned_weapons):
		return {"success": false, "event": {}, "error_code": NP.ERR_INVALID_TARGET}
	var ai: DamageResolverClass.AttackInput = built["attack_input"]
	var defender_data: Dictionary = _r.entities().get(defender_entity_id, {})
	var forward: Vector3 = Vector3(0, 0, -1)
	var out: Dictionary = _r.combat_auth.resolve_attack(ai, defender_data, forward, peer_id, defender_entity_id)
	# 权威攻击冷却唯一入口：AttackCadencePolicy（与单机 PlayerCombatRuntime/HUD 同一公式）。
	var cd: float = AttackCadencePolicyClass.compute_attack_cd(actx, false, 0)
	_r.attack_cd_until()[peer_id] = current_time + cd
	# 权威血写回实体仓（entity_snapshot 广播 / entity_despawned 击杀事件）。
	var extra: Array = []
	if defender_entity_id != 0 and _r.entities().has(defender_entity_id):
		var new_life: int = int(out.get("defender_life", 0))
		if new_life <= 0:
			var loot_events: Array = on_entity_killed(defender_entity_id, peer_id)
			var dres: Dictionary = _r.remove_entity(defender_entity_id)
			if bool(dres.get("success", false)):
				extra.append(dres["event"])
			for le in loot_events:
				extra.append(le)
		else:
			var ures: Dictionary = _r.update_entity(defender_entity_id, {"current_life": new_life})
			if bool(ures.get("success", false)):
				extra.append(ures["event"])
	return {"success": true, "event": out["event"], "error_code": "", "extra_events": extra}

## 实体被击杀：按击杀者权威归属发放经验（不写全局 current_player）+ 掉落物生成。
func on_entity_killed(entity_id: int, killer_peer: int) -> Array:
	var events: Array = []
	var enemy: Dictionary = _r.entities().get(entity_id, {})
	# P1-4：击杀经验归属 killer 的权威 PlayerContext（不写全局 current_player）。
	var killer_ctx: PlayerContextClass = _r.registry.get_context(killer_peer)
	if killer_ctx != null and killer_ctx.attributes != null:
		var reward: int = ProgressionAuthorityClass.compute_kill_reward(
			int(enemy.get("max_life", 0)),
			bool(enemy.get("is_elite", false)),
			bool(enemy.get("is_boss", false)))
		var levels_gained: int = ProgressionAuthorityClass.award_kill_experience(killer_ctx.attributes, reward)
		if levels_gained > 0 or reward > 0:
			var prog_evt: Dictionary = _r.progression_service.progression_event(killer_peer, killer_ctx)
			events.append(prog_evt)
	var table: Dictionary = enemy.get("loot_table", {})
	if table.is_empty():
		return events
	# 击杀者权威掉落（跟随可拾取位置）。
	var drop_pos: Vector3 = Vector3.ZERO
	var ls: Dictionary = _r.live_state().get(killer_peer, {})
	if not ls.is_empty():
		drop_pos = ls.get("position", Vector3.ZERO)
	# 确定性种子（entity_id + 掉落序号），保证同一击杀重复结算产出相同（与 LootAuthority 一致）。
	var rolled: Dictionary = _r.server_roll_loot(table, (entity_id * 2654435761 + _r.loot_seq()) & 0x7FFFFFFF, 4)
	var idx: int = 0
	for item_id in rolled.keys():
		var amount: int = int(rolled[item_id])
		if amount <= 0:
			continue
		var lid: int = _r.next_loot_seq()
		# 掉落物在击杀点附近确定性散开（避免全局重叠）。
		var off: Vector3 = Vector3(float(idx) * 0.4, 0.0, float(idx) * 0.4)
		var data: Dictionary = {
			"kind": "loot",
			"label": String(item_id),
			"position": drop_pos + off,
			"item_id": String(item_id),
			"item_kind": String(table[item_id].get("kind", "material")),
			"amount": amount,
			"current_life": 0,
			"max_life": 0,
			"consumed": false,
		}
		var res: Dictionary = _r.set_entity(lid, data)
		if bool(res.get("success", false)) and res.has("event"):
			events.append(res["event"])
		idx += 1
	return events

# ============================================================================
# 法术事务
# ============================================================================

## 客户端请求施法（CMD_CAST_SPELL）：权威事务——槽位固定配方 → 施法资格 →
## caster 绑定 → 法力/冷却 → 世界执行 → 失败不 commit → 广播 EVT_SPELL_RESOLVED。
func handle_cast_spell(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if not _r.seq_tracker().accept(peer_id, int(command.get("sequence", 0))):
		return _r.reject(NP.ERR_INVALID_SEQUENCE)
	var slot_index := clampi(int(command.get("slot_index", -1)), 0, 4)
	# 法术只从 per-peer PlayerContext 权威 SpellLoadout 取（不信任客户端 spell_id）。
	if ctx.spell_loadout == null:
		return _r.reject(NP.ERR_INVALID_STATE)
	var spell: Dictionary = ctx.spell_loadout.get_spell(slot_index)
	if spell.is_empty() or SpellRecipeDataClass.resolve(spell.get("recipe", [])).is_empty():
		return _r.reject(NP.ERR_INVALID_TARGET)
	# P0-5：施法资格按 SpellAccessPolicy 纯逻辑校验（权威 loadout 武器 + 奥法之剑被动），
	# 独立于 UI——直接提交施法命令也会被拒绝。
	if not validate_spell_access(ctx):
		return _r.reject(NP.ERR_INVALID_TARGET)
	# P0-4：caster 必须已绑定真实 Player 实体，否则在任何资源 commit 前拒绝。
	if ctx.player_node == null or not is_instance_valid(ctx.player_node):
		return _r.reject(NP.ERR_PLAYER_NOT_READY)
	var mana_cost := ctx.spell_runtime.mana_cost_for(spell)
	if ctx.spell_mana < mana_cost:
		return _r.reject(NP.ERR_INSUFFICIENT_RESOURCE)
	var spell_id := String(spell.get("id", ""))
	# 冷却只做预检（commit_authoritative_cooldown 在提交时确认）。
	if ctx.spell_runtime.is_on_cooldown(spell_id):
		return _r.reject(NP.ERR_COOLDOWN_ACTIVE)
	# 世界执行可行性预检（commit 前不支持的实施类型不扣资源）。
	var implementation := String(spell.get("implementation", "projectile"))
	if not SpellAuthorityClass.supports_implementation(implementation):
		return _r.reject(NP.ERR_INVALID_TARGET)
	# ---- execute → verify（commit 前）→ commit → publish ----
	# P0-3：会话级世界执行器由 SessionRoot 拥有（本服务装配端口）；实体伤害经
	# damage_entity_port 写回 _entities 权威路径。
	ensure_spell_world_executor()
	var live: Dictionary = _r.live_state().get(peer_id, {})
	var origin: Vector3 = live.get("position", Vector3.ZERO)
	var direction: Vector3 = live.get("facing", Vector3(0, 0, -1))
	var effect_plan := ctx.spell_runtime._effect_plan({"implementation": implementation, "spell": spell})
	var authority_execution: Dictionary = _r.spell_auth.execute(ctx.player_node, {"ok": true, "spell_id": spell_id, "imagery": spell.get("imagery", "unknown"), "origin": origin, "direction": direction, "target_hint": command.get("target_hint"), "effect_plan": effect_plan, "visual_event": {}}, ctx.player_node.get_parent(), peer_id)
	# P0-3：世界执行失败（预检/实施不支持/效果缺失）→ 拒绝，不提交法力与冷却。
	if not bool(authority_execution.get("ok", false)):
		return _r.reject(NP.ERR_INVALID_STATE)
	# P0-1-A：movement 位移由 caster 权威（含碰撞）实体实际位置为准，同步 _live_state。
	if implementation == "movement" and ctx.player_node != null and is_instance_valid(ctx.player_node):
		_r.set_player_position(peer_id, ctx.player_node.global_position)
	# verify/ray 等实施的世界端口事件（snapshot/despawn/掉落）作为 extra_events 广播。
	var extra: Array = []
	var world_execution: Dictionary = authority_execution.get("world_execution", {})
	var port_result: Dictionary = world_execution.get("port_result", {})
	var port_events = port_result.get("events", [])
	if port_events is Array:
		for ev in port_events:
			if ev is Dictionary and not (ev as Dictionary).is_empty():
				extra.append(ev)
	# P1（2124 审查）：会话登记投射物（会话销毁时统一回收，不依赖全局池）。
	if implementation == "projectile" and authority_execution.has("projectile"):
		_r.track_projectile(authority_execution["projectile"] as Node)
	# ---- commit：执行成功后才扣资源 ----
	ctx.spell_mana -= mana_cost
	ctx.spell_runtime.commit_authoritative_cooldown(spell)
	var evt := {
		"event": NP.EVT_SPELL_RESOLVED,
		"peer_id": peer_id,
		"slot_index": slot_index,
		"spell_id": spell_id,
		"imagery": String(spell.get("imagery", "unknown")),
		"implementation": implementation,
		"origin": origin,
		"direction": direction,
		"color": spell.get("color", Color.WHITE),
		"mana_spent": mana_cost,
		"mana_remaining": ctx.spell_mana,
		"cooldown_ms": ctx.spell_runtime.remaining_cooldown_ms(spell_id),
		"authority_execution": authority_execution,
		"world_execution": world_execution,
		"effects": {
			"healed": int(authority_execution.get("healed", 0)),
			"absorb": int(authority_execution.get("absorb", 0)),
			"duration": float(authority_execution.get("duration", 0.0)),
			"distance": float(authority_execution.get("distance", 0.0)),
		},
	}
	# ---- publish ----
	_r.session_event.emit(evt)
	return {"success": true, "event": evt, "error_code": "", "extra_events": extra}

## 施法资格校验（纯逻辑 SpellAccessPolicy，权威 loadout 武器 + 奥法之剑被动）。
func validate_spell_access(ctx: PlayerContextClass) -> bool:
	var reg: Object = _r.weapon_registry()
	if reg == null:
		return true
	var weapon_id: String = ctx.loadout.get_weapon_slot(ctx.loadout.active_weapon_slot)
	var weapon = reg.get_weapon_data(weapon_id) if not weapon_id.is_empty() else null
	if weapon == null:
		return false
	var has_arcane_sword := false
	if ctx.skills != null and ctx.skills.has_method("has_mechanism_passive"):
		has_arcane_sword = ctx.skills.has_mechanism_passive(SpellAccessPolicyClass.ARCANE_SWORD_PASSIVE_ID)
	return SpellAccessPolicyClass.can_use_spell_interface(weapon, has_arcane_sword)

# ============================================================================
# 技能事务
# ============================================================================

## 客户端请求释放技能（CMD_SKILL，2251 审查 P0-1 权威事务）：
## owned → 定义解析 → 冷却校验 → 端口装配 → 效果执行（伤害/位移/自buff）→
## 失败拒绝且不提交冷却 → 位移同步 live position → 广播 + 实体事件。
func handle_skill(command: Dictionary, ctx: PlayerContextClass) -> Dictionary:
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	if not _r.seq_tracker().accept(peer_id, int(command.get("sequence", 0))):
		return _r.reject(NP.ERR_INVALID_SEQUENCE)
	var skill_id: String = String(command.get("skill_id", ""))
	if skill_id.is_empty():
		return _r.reject(NP.ERR_INVALID_TARGET)
	# 1. 所有权校验：服务器校验该玩家确实已绑定此技能（不信任客户端自报）。
	var owned := false
	var sk = ctx.skills
	if sk != null:
		var bound: Array = sk.get_bound_active_skills() + sk.get_bound_passive_skills()
		owned = skill_id in bound
	if not owned:
		return _r.reject(NP.ERR_INVALID_TARGET)
	# 2. 定义解析：无定义的技能 id（伪造/测试占位）拒绝——技能必须来自权威数据表。
	var definition: Dictionary = SkillAuthorityClass.get_skill_definition(skill_id)
	if definition.is_empty():
		return _r.reject(NP.ERR_INVALID_TARGET)
	# P1-1（0304 审查）：被动技能禁止经主动命令触发（被动由装备/机制层生效）。
	if String(definition.get("type", "")) == "passive":
		return _r.reject(NP.ERR_INVALID_TARGET)
	# 3. 权威冷却校验：冷却中拒绝，不产生任何世界状态。
	if _r.skill_auth.is_on_cooldown(peer_id, skill_id):
		return _r.reject(NP.ERR_COOLDOWN_ACTIVE)
	# 4. 装配技能权威端口（位移/伤害；与法术同一世界执行器装配，幂等）。
	ensure_spell_world_executor()
	# 5. 权威效果执行：目标伤害/位移/自buff；失败（无有效目标/超距/执行失败）→ 拒绝且不 commit。
	var live: Dictionary = _r.live_state().get(peer_id, {})
	var execution: Dictionary = _r.skill_auth.execute(ctx, skill_id, definition, live, command.get("target_hint"))
	if not bool(execution.get("ok", false)):
		return _r.reject(NP.ERR_INVALID_TARGET)
	# 6. commit：提交权威冷却（服务器可断言状态变化）。
	var cooldown_sec: float = float(definition.get("cooldown", 0.0))
	_r.skill_auth.commit_cooldown(peer_id, skill_id, cooldown_sec)
	# 位移效果同步权威 live position（headless 无物理 body 时同样成立，客户端可预测）。
	var effects: Dictionary = execution.get("effects", {}) if execution.get("effects") is Dictionary else {}
	var dash_m: float = float(effects.get("dash_m", 0.0))
	if dash_m > 0.0:
		var live2: Dictionary = _r.live_state().get(peer_id, {})
		var fwd: Vector3 = live2.get("facing", Vector3(0, 0, -1)) if live2.get("facing") is Vector3 else Vector3(0, 0, -1)
		var pos: Vector3 = live2.get("position", Vector3.ZERO) if live2.get("position") is Vector3 else Vector3.ZERO
		live2["position"] = pos + fwd.normalized() * dash_m
		_r.live_state()[peer_id] = live2
	var extra: Array = execution.get("events", []) if execution.get("events") is Array else []
	var evt := {
		"event": NP.EVT_SKILL_STATE_CHANGED,
		"peer_id": peer_id,
		"skill_id": skill_id,
		"triggered": true,
		"cooldown_ms": _r.skill_auth.remaining_cooldown_ms(peer_id, skill_id),
		"effects": effects,
	}
	_r.session_event.emit(evt)
	for e in extra:
		if e is Dictionary:
			_r.session_event.emit(e)
	return {"success": true, "event": evt, "extra_events": extra, "error_code": ""}

# ============================================================================
# 战斗副作用端口（法术/技能世界执行装配）
# ============================================================================

## 确保会话世界执行器存在并装配全部权威端口（幂等；SessionRoot 拥有生命周期）。
func ensure_spell_world_executor() -> void:
	var ex: Node = _r.spell_auth.get_world_executor()
	if ex == null or not is_instance_valid(ex):
		var executor := SpellWorldExecutorClass.new()
		executor.name = "SpellWorldExecutor"
		_r.add_child(executor)
		_r.spell_auth.set_world_executor(executor)
		ex = executor
	if "damage_entity_port" in ex:
		ex.damage_entity_port = spell_damage_entity
	# P0（2218 审查）：会话权威目标查询端口（召唤物自动寻敌——查实体仓而非表现组）。
	if "query_targets_port" in ex:
		ex.query_targets_port = query_spell_targets
	_r.spell_auth.set_self_effect_port(apply_self_effect)
	# P0-2（2251 审查）：movement 法术接入碰撞安全位移端口（禁止穿墙）。
	_r.spell_auth.set_movement_port(apply_authoritative_movement)
	# P1-4（0643 审查）：投射物生成经 Service 定位注入（不再由 SpellAuthority 直接
	# 查 /root/ProjectileService）；服务缺失时端口返回 null，由执行器报
	# projectile_spawn_failed 拒绝——不猜测全局单例，多会话装配不再脆弱。
	_r.spell_auth.set_projectile_spawn_port(_projectile_spawn)
	# P0-1（2251 审查）：技能权威执行端口（位移 + 目标伤害）。
	_r.skill_auth.set_movement_port(apply_authoritative_movement)
	_r.skill_auth.set_damage_port(skill_damage)

## P1-4（0643 审查）：权威投射物生成端口实现——经 Service 定位 ProjectileService。
## 签名与 ProjectileService.spawn 一致：func(projectile_id, transform, caster, target,
## skill_data, world) -> Node。服务不可用时返回 null（调用方整体拒绝，不部分成功）。
func _projectile_spawn(projectile_id: String, transform: Transform3D, caster: Node3D,
		target: Node, skill_data: Dictionary, world: Node) -> Node:
	var ps: Node = ServiceClass.projectile_service()
	if ps == null or not ps.has_method("spawn"):
		return null
	return ps.spawn(projectile_id, transform, caster, target, skill_data, world)

## P0-2（2251 审查）：权威安全位移——movement 法术/位移技能经 ServerCharacterMotor
## 分步碰撞移动；无物理 body（headless 纯逻辑/未绑定 caster）回退确定性积分。
func apply_authoritative_movement(caster: Node3D, direction: Vector3, distance: float) -> Dictionary:
	if distance <= 0.0:
		return {"moved_distance": 0.0, "collided": false}
	var dir := direction.normalized()
	var body := caster as CharacterBody3D
	if body != null and is_instance_valid(body) and body.is_inside_tree():
		var dir2 := Vector2(dir.x, dir.z)
		if dir2.length_squared() > 1.0:
			dir2 = dir2.normalized()
		var start := body.global_position
		var steps := maxi(1, int(ceil(distance / 0.1)))
		var step_m := distance / float(steps)
		var collided := false
		for i in range(steps):
			var res: Dictionary = _r.movement_motor.move_body(body, dir2, false, 1.0 / 60.0, step_m * 60.0)
			if bool(res.get("collided", false)):
				collided = true
				break
		return {"moved_distance": body.global_position.distance_to(start), "collided": collided}
	# headless / 未绑定实体：确定性积分（与 MovementAuthority.integrate_position 一致）。
	return {"moved_distance": distance, "collided": false}

## P0-1（2251 审查）+ 2026-08-07（0643/0952 审查）：技能目标伤害端口——权威
## AttackContext（主手武器）× 技能 damage_mult → combat_auth 结算 → 实体生命写回/
## 击杀处理。距离超 range 拒绝。
## 2026-08-07 完整兑现声明字段（拒绝表已清空）：
##   ignore_def → AttackInput.ignore_def_percent；ignore_block → AttackInput.ignore_block；
##   lifesteal → AttackInput.lifesteal_percent（DamageResult.lifesteal_amount 回写 caster）；
##   stun_sec → AttackInput.bonus_stun_duration（DamageResolver 对 melee/ranged 输出
##     stun_duration → 实体 stun_until 绝对毫秒；spell 类由 DamageResolver 语义天然忽略，
##     概率眩晕类 buff_type 属后续概率系统，不在此叠加）；
##   breaks_shield → 目标实体 shield 清零（entity_snapshot 广播）；
##   aoe_shape/aoe_radius → 多目标几何过滤（cone/circle/line）逐个结算；
##   skill_family=grapple → 目标拉近到 caster 面前 1.0m（抓取）后结算（投掷眩晕由
##     stun_sec 承担），位置随 entity_snapshot 广播。
func skill_damage(ctx, skill: Dictionary, target_entity_id: Variant) -> Dictionary:
	var tid := int(target_entity_id) if target_entity_id != null else 0
	var peer_id: int = int(_r.ctx_peer().get(ctx.get_instance_id(), 0))
	var live: Dictionary = _r.live_state().get(peer_id, {})
	var is_aoe: bool = String(skill.get("aoe_shape", "none")) != "none" or float(skill.get("aoe_radius", 0.0)) > 0.0
	var targets: Array = []
	if is_aoe:
		targets = _query_skill_aoe_targets(live, skill)
	elif tid == 0 or not _r.entities().has(tid):
		return {"ok": false, "reason": "no_valid_target"}
	else:
		targets = [tid]
	if targets.is_empty():
		return {"ok": false, "reason": "no_valid_target"}
	var all_events: Array = []
	# 权威伤害：AttackContextFactory（per-peer 属性/loadout）→ AttackInput → 技能倍率。
	var attrs := {}
	if ctx.attributes != null and ctx.attributes.has_method("get_attr"):
		for k in ["str", "dex", "mag", "per", "agi"]:
			attrs[k] = ctx.attributes.get_attr(k)
	var level := int(ctx.attributes.get_level()) if ctx.attributes != null and ctx.attributes.has_method("get_level") else 1
	var caster_pos: Vector3 = live.get("position", Vector3.ZERO) if live.get("position") is Vector3 else Vector3.ZERO
	var forward: Vector3 = live.get("facing", Vector3(0, 0, -1)) if live.get("facing") is Vector3 else Vector3(0, 0, -1)
	# 2026-08-07：抓取投掷——先拉近目标到 caster 面前 1.0m（权威位置 + 广播）。
	var is_grapple: bool = String(skill.get("skill_family", "")) == "grapple"
	if is_grapple and not targets.is_empty():
		var grab_target: Dictionary = _r.entities()[targets[0]]
		grab_target["position"] = caster_pos + forward.normalized() * 1.0
		var gres: Dictionary = _r.update_entity(targets[0], {"position": grab_target["position"]})
		if bool(gres.get("success", false)) and gres.has("event"):
			all_events.append(gres["event"])
	var total_damage := 0
	var max_knockback := 0.0
	var first_event := {}
	var applied_stun := 0.0
	var broken_shield := false
	for t in targets:
		var tdata: Dictionary = _r.entities()[t]
		var range_m := float(skill.get("range_m", 1.5))
		var tpos: Vector3 = tdata.get("position", caster_pos) if tdata.get("position") is Vector3 else caster_pos
		# 单目标路径保留射程校验；AoE 目标已按 aoe_radius 几何过滤，跳过单目标射程。
		if not is_aoe and caster_pos.distance_to(tpos) > range_m:
			return {"ok": false, "reason": "target_out_of_range"}
		var actx = AttackContextFactoryClass.build_from_player_state(attrs, level, ctx.loadout, _r.weapon_registry(), "primary", 1.0, t)
		var ai: DamageResolverClass.AttackInput = AttackContextFactoryClass.to_attack_input(actx)
		ai.weapon_damage_mult = ai.weapon_damage_mult * float(skill.get("damage_mult", 1.0))
		# 2026-08-07：穿透/吸血/眩晕注入（DamageResolver 原生字段）。
		ai.ignore_def_percent = maxf(ai.ignore_def_percent, float(skill.get("ignore_def", 0.0)))
		ai.ignore_block = ai.ignore_block or bool(skill.get("ignore_block", false))
		ai.lifesteal_percent += float(skill.get("lifesteal", 0.0))
		ai.bonus_stun_duration = maxf(ai.bonus_stun_duration, float(skill.get("stun_sec", 0.0)))
		# P1-1（1727 审查）：目标击退（knockback_m）——沿攻击方向权威偏移实体位置
		# 并随 update_entity 广播 entity_snapshot（实体为权威逻辑位置，无需物理碰撞）。
		var knockback_m := float(skill.get("knockback_m", 0.0))
		if knockback_m > 0.0:
			var kb_dir: Vector3 = (tpos - caster_pos).normalized() if tpos != caster_pos else forward
			tdata["position"] = tpos + kb_dir * knockback_m
			max_knockback = maxf(max_knockback, knockback_m)
		# 2026-08-07：breaks_shield——目标权威 shield 清零（entity_snapshot 广播）。
		if bool(skill.get("breaks_shield", false)) and int(tdata.get("shield", 0)) > 0:
			tdata["shield"] = 0
			broken_shield = true
		var out: Dictionary = _r.combat_auth.resolve_attack(ai, tdata, forward, peer_id, t)
		var new_life: int = int(out.get("defender_life", 0))
		var damage: int = maxi(0, int(tdata.get("current_life", 0)) - new_life)
		total_damage += damage
		# 2026-08-07：stun 写实体权威状态（绝对毫秒，与 PlayerContext.buffs 同契约）。
		var stun_sec: float = float(out.get("result", {}).stun_duration) if out.get("result") != null else 0.0
		if stun_sec > 0.0:
			applied_stun = maxf(applied_stun, stun_sec)
			tdata["stun_until"] = Time.get_ticks_msec() + roundi(stun_sec * 1000.0)
		var events: Array = []
		if new_life <= 0:
			events = on_entity_killed(t, peer_id)
			var dres: Dictionary = _r.remove_entity(t)
			if bool(dres.get("success", false)):
				events.append(dres["event"])
		else:
			var partial: Dictionary = {"current_life": new_life, "position": tdata.get("position", tpos)}
			if tdata.has("stun_until"):
				partial["stun_until"] = int(tdata["stun_until"])
			if tdata.has("shield"):
				partial["shield"] = int(tdata["shield"])
			var ures: Dictionary = _r.update_entity(t, partial)
			if bool(ures.get("success", false)):
				events.append(ures["event"])
		if first_event.is_empty():
			first_event = out.get("event", {})
		for e in events:
			all_events.append(e)
	# 2026-08-07：lifesteal——按总伤害 × 技能吸血百分比回写 caster 权威生命。
	if total_damage > 0 and float(skill.get("lifesteal", 0.0)) > 0.0:
		var heal_amt: int = int(round(float(total_damage) * float(skill.get("lifesteal", 0.0)) * 0.01))
		if heal_amt > 0 and ctx != null and ctx.has_method("record_spell_effect"):
			var life_before: int = ctx.current_life
			ctx.record_spell_effect("heal", heal_amt, 0.0)
			_r.broadcast_player_combat_state(peer_id)
			var node: Node = ctx.player_node
			if node != null and is_instance_valid(node) and "health" in node and node.health != null \
					and node.health.has_method("heal") and ctx.current_life > life_before:
				node.health.heal(ctx.current_life - life_before)
	return {"ok": true, "damage": total_damage, "knockback_m": max_knockback,
		"stun_sec": applied_stun, "shield_broken": broken_shield,
		"event": first_event, "events": all_events}

## 2026-08-07：AoE 技能目标查询——权威实体仓内存活敌人，按 aoe_shape 几何过滤：
##   circle：半径内全部；cone：半径内 + 前方 60° 锥角；line：前方投影 ≤ radius 且横向 ≤ 1.5m。
func _query_skill_aoe_targets(live: Dictionary, skill: Dictionary) -> Array:
	var origin: Vector3 = live.get("position", Vector3.ZERO) if live.get("position") is Vector3 else Vector3.ZERO
	var facing: Vector3 = live.get("facing", Vector3(0, 0, -1)) if live.get("facing") is Vector3 else Vector3(0, 0, -1)
	var radius := float(skill.get("aoe_radius", 0.0))
	var shape := String(skill.get("aoe_shape", "circle"))
	var fwd := facing.normalized()
	var out: Array = []
	for eid in _r.entities().keys():
		var data: Dictionary = _r.entities()[eid]
		if String(data.get("kind", "")) != "enemy":
			continue
		if int(data.get("current_life", 0)) <= 0:
			continue
		var pos: Vector3 = data.get("position", Vector3.ZERO) if data.get("position") is Vector3 else Vector3.ZERO
		var delta: Vector3 = pos - origin
		var dist := delta.length()
		if dist > radius:
			continue
		match shape:
			"cone":
				if dist > 1e-6 and fwd.dot(delta / dist) < 0.5:  # 60° 半锥
					continue
			"line":
				var proj: float = delta.dot(fwd)
				if proj < 0.0 or proj > radius:
					continue
				if (delta - fwd * proj).length() > 1.5:
					continue
			_:  # circle / none：仅半径过滤
				pass
		out.append(int(eid))
	return out

## P0（2218 审查）：会话权威法术目标查询——返回范围内可受击敌人（kind=enemy 且存活）。
## 供召唤物/范围法术选择目标；位置来自服务器权威实体仓（不依赖表现层 group）。
func query_spell_targets(origin: Vector3, range: float) -> Array:
	var out: Array = []
	for eid in _r.entities().keys():
		var data: Dictionary = _r.entities()[eid]
		if String(data.get("kind", "")) != "enemy":
			continue
		if int(data.get("current_life", 0)) <= 0:
			continue
		var pos: Vector3 = data.get("position", Vector3.ZERO)
		if origin.distance_to(pos) <= range:
			out.append({"entity_id": int(eid), "position": pos})
	return out

## P0（2124 审查）：per-peer 自目标效果（heal/barrier/buff）权威状态写 PlayerContext，
## 并同步可见节点组件（远端 avatar 无组件时仅权威状态生效）。
func apply_self_effect(peer_id: int, effect_type: String, amount: int, duration: float) -> void:
	var ctx: PlayerContextClass = _r.registry.get_context(peer_id)
	if ctx == null:
		return
	var life_before: int = ctx.current_life
	ctx.record_spell_effect(effect_type, amount, duration)
	# P0（2331 审查）：自目标法术改变战斗状态 → 立即广播（客户端 HUD/角色面板）。
	_r.broadcast_player_combat_state(peer_id)
	var node: Node = ctx.player_node
	if node == null or not is_instance_valid(node):
		return
	match effect_type:
		"heal":
			# 与单机同语义：heal 同时作用于可见真实 Player。
			var healed: int = ctx.current_life - life_before
			if healed > 0 and "health" in node and node.health != null and node.health.has_method("heal"):
				node.health.heal(healed)
		"barrier":
			if "buffs" in node and node.buffs != null and node.buffs.has_method("add"):
				var max_life := int(node.health.max_life) if "health" in node and node.health != null else 100
				var absorb_pct := float(amount) / float(maxi(max_life, 1)) * 100.0
				node.buffs.add("damage_absorb", duration, {"percent": absorb_pct})
		"buff":
			if "buffs" in node and node.buffs != null and node.buffs.has_method("add"):
				node.buffs.add("spell_power", duration, {"percent": 20.0})

## P0（2218 审查）：对实体施加权威法术伤害（经世界执行器 damage_entity_port）。
## 法术伤害受 caster 权威 spell_power buff 影响；生命写回 _entities + 击杀/掉落处理。
func spell_damage_entity(entity_id: int, damage: int, caster_peer: int) -> Dictionary:
	var out := {"ok": false, "killed": false, "events": []}
	if damage <= 0 or not _r.entities().has(entity_id):
		return out
	# P0（2218 审查）：法术权威 buff（spell_power）影响法术伤害——来自 PlayerContext 权威值。
	var ctx: PlayerContextClass = _r.registry.get_context(caster_peer)
	if ctx != null:
		damage = int(round(float(damage) * ctx.spell_power_mult()))
	if damage <= 0:
		return out
	var data: Dictionary = _r.entities()[entity_id]
	var new_life: int = int(data.get("current_life", 0)) - damage
	var events: Array = []
	if new_life <= 0:
		var loot_events: Array = on_entity_killed(entity_id, caster_peer)
		var dres: Dictionary = _r.remove_entity(entity_id)
		if bool(dres.get("success", false)):
			events.append(dres["event"])
		for le in loot_events:
			events.append(le)
		out["killed"] = true
	else:
		var ures: Dictionary = _r.update_entity(entity_id, {"current_life": new_life})
		if bool(ures.get("success", false)):
			events.append(ures["event"])
	out["ok"] = true
	out["events"] = events
	return out
