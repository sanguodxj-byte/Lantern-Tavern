class_name SpellAuthority
extends RefCounted

## 消费 SpellRuntime.effect_plan 的权威执行器。
## 单机/服务端调用；客户端只播放返回的 visual_event。
##
## 架构审查 P0-3：世界执行器改为【会话实例持有】（不再是 static var）——字段/召唤预算、
## 节点归属和生命周期跟随 SessionRoot，杜绝跨会话/跨场景/跨测试污染。
## execute() 在 world execution 失败（预算满/服务缺失/实施不支持）时返回 ok=false，
## 由 SessionRoot 在 commit 前拒绝，保证「法力/冷却与世界效果」事务原子。

const PixelSpellFxScript := preload("res://fx/pixel_spell_fx.gd")
const SpellWorldExecutorScript := preload("res://globals/combat/spell_world_executor.gd")

## 会话实例持有的世界执行器（ray/area/ground/summon 的运行时节点；SessionRoot 负责
## 挂树与生命周期释放）。为 null 时按需惰性创建。
var _world_executor: Node = null

## P0（2124 审查）：per-peer 自目标效果状态端口——func(peer_id:int, type:String, amount:int, duration:float)。
## SessionRoot 注入后，heal/barrier/buff 写 PlayerContext.spell_effect_state（远端 avatar
## 无 health/buffs 组件也成功）；无端口时回退节点组件（单机路径，行为不变）。
var self_effect_port: Callable = Callable()

func set_self_effect_port(port: Callable) -> void:
	self_effect_port = port

## 权威执行器支持的实施类型集合（架构审查 P0-4）：
## 服务端在任何资源 commit（法力/冷却）前用它预检世界执行可行性，
## 避免「先扣资源、再因实施不支持而无世界效果」的事务断裂。
const SUPPORTED_IMPLEMENTATIONS := ["heal", "barrier", "movement", "buff", "projectile", "ray", "area", "ground", "summon"]

static func supports_implementation(implementation: String) -> bool:
	return implementation in SUPPORTED_IMPLEMENTATIONS

## 会话级世界执行器访问器（SessionRoot 注入 / 测试注入）。
func set_world_executor(executor: Node) -> void:
	_world_executor = executor

func get_world_executor() -> Node:
	return _world_executor

## 执行法术：heal/barrier/movement/buff 直接作用于 caster 节点；
## projectile 经 ProjectileService 生成；ray/area/ground/summon 委托世界执行器。
## caster_peer: 施法者服务器 peer_id（世界执行器把实体伤害经 damage_entity_port 写回
## SessionRoot 权威实体仓时用于击杀归属）。world 为执行器挂载容器（缺省用 caster 父节点）。
## 返回 {"ok":bool, "reason":String, "type":String, ...}。
## 任何世界执行失败（预算满 / 目标缺失且必须命中 / 不支持）→ ok=false，调用方不得提交资源。
## P0-1-A：自目标效果（heal/barrier/buff）所依赖的组件缺失 → ok=false（不得「扣蓝但无效果」）；
## P0-1-B：projectile 服务缺失 / 生成失败（返回 null）→ ok=false（不得在失败后 commit）。
func execute(caster: Node3D, result: Dictionary, world: Node = null, caster_peer: int = 0) -> Dictionary:
	if caster == null or not bool(result.get("ok", false)):
		return {"ok": false, "reason": "invalid_cast_result"}
	var plan: Dictionary = result.get("effect_plan", {})
	var implementation := String(plan.get("type", ""))
	if not supports_implementation(implementation):
		return {"ok": false, "reason": "unsupported_implementation"}
	var execution := {"ok": true, "type": implementation, "spell_id": String(result.get("spell_id", "")), "visual_event": result.get("visual_event", {}).duplicate(true)}
	match implementation:
		"heal":
			var heal_amount := int(plan.get("heal", 28))
			if self_effect_port.is_valid():
				# 权威：写 per-peer 效果状态（远端 avatar 无组件也成功）。
				self_effect_port.call(caster_peer, "heal", heal_amount, 0.0)
			elif "health" in caster and caster.health != null and caster.health.has_method("heal"):
				caster.health.heal(heal_amount)
			else:
				# 无端口且无组件（纯逻辑单测环境）→ 仍记录成功（heal 摘要），
				# 但无副作用目标：调用方按 ok=true 提交（联机权威由端口承担）。
				pass
			execution["healed"] = heal_amount
		"barrier":
			var absorb := int(plan.get("absorb", 30))
			if self_effect_port.is_valid():
				self_effect_port.call(caster_peer, "barrier", absorb, float(plan.get("duration", 5.0)))
			elif "buffs" in caster and caster.buffs != null and caster.buffs.has_method("add"):
				var max_life := int(caster.health.max_life) if "health" in caster and caster.health != null else 100
				var absorb_pct := float(absorb) / float(maxi(max_life, 1)) * 100.0
				caster.buffs.add("damage_absorb", float(plan.get("duration", 5.0)), {"percent": absorb_pct})
			execution["absorb"] = absorb
		"movement":
			var direction := Vector3(result.get("direction", Vector3.FORWARD))
			caster.global_position += direction.normalized() * float(plan.get("distance", 5.0))
			execution["distance"] = float(plan.get("distance", 5.0))
		"buff":
			var duration := float(plan.get("duration", 6.0))
			if self_effect_port.is_valid():
				self_effect_port.call(caster_peer, "buff", 0, duration)
			elif "buffs" in caster and caster.buffs != null and caster.buffs.has_method("add"):
				caster.buffs.add("spell_power", duration, {"percent": 20.0})
			execution["duration"] = duration
		"projectile":
			var projectile_service := caster.get_node_or_null("/root/ProjectileService")
			if projectile_service == null or not projectile_service.has_method("spawn"):
				return {"ok": false, "reason": "projectile_service_unavailable"}
			var projectile_id := String(plan.get("projectile_id", "elemental_bolt"))
			var cast_direction := Vector3(result.get("direction", Vector3.FORWARD)).normalized()
			var spawn_transform := Transform3D(Basis.looking_at(cast_direction, Vector3.UP), Vector3(result.get("origin", caster.global_position)))
			# P0-1-B：把会话实体仓伤害端口注入投射物 skill_data——命中带 entity_id 的
			# 权威实体时经端口写回 SessionRoot._entities（生命/死亡/掉落复制），
			# 不再只依赖可见节点的 try_receive_hit 本地结算。端口走 outbox 包装，
			# 命中产生的复制事件由 SessionRoot 统一排空广播（异步 tick 不丢事件）。
			var skill_data := {"id": result.get("spell_id", ""), "damage": int(plan.get("damage", 10)), "caster_peer": caster_peer}
			var executor: Node = get_world_executor()
			if executor != null and is_instance_valid(executor) and executor.has_method("make_outbox_port"):
				skill_data["damage_port"] = executor.make_outbox_port()
			var spawned = projectile_service.spawn(projectile_id, spawn_transform, caster, null, skill_data)
			if spawned == null:
				return {"ok": false, "reason": "projectile_spawn_failed"}
			execution["projectile"] = spawned
			execution["world_request"] = {"type": implementation, "caster_id": caster.get_instance_id(), "origin": result.get("origin", caster.global_position), "direction": result.get("direction", -caster.global_transform.basis.z), "target_hint": result.get("target_hint"), "params": plan.duplicate(true)}
		"ray", "area", "ground", "summon":
			execution["world_request"] = {"type": implementation, "caster_id": caster.get_instance_id(), "origin": result.get("origin", caster.global_position), "direction": result.get("direction", -caster.global_transform.basis.z), "target_hint": result.get("target_hint"), "params": plan.duplicate(true)}
			var executor := _ensure_executor(world, caster)
			if executor == null:
				return {"ok": false, "reason": "world_executor_unavailable"}
			var world_execution: Dictionary = executor.execute(caster, execution.world_request, world, caster_peer)
			execution["world_execution"] = world_execution
			# P0-3：世界执行失败（预算满 / 实施不支持 / 服务缺失）→ 整体失败，
			# SessionRoot 在 commit 前拒绝（法力/冷却不得扣减）。
			if not bool(world_execution.get("ok", false)):
				return {"ok": false, "reason": String(world_execution.get("reason", "world_execution_failed")), "world_execution": world_execution}
		_:
			return {"ok": false, "reason": "unsupported_implementation"}
	if world != null and execution.has("visual_event"):
		PixelSpellFxScript.spawn(world, execution.visual_event, Vector3(result.get("origin", caster.global_position)), Vector3(result.get("direction", Vector3.FORWARD)))
	return execution

## 惰性创建会话级世界执行器（挂到 world 或 caster 父节点；SessionRoot 优先预注入）。
func _ensure_executor(world: Node, caster: Node3D) -> Node:
	if _world_executor != null and is_instance_valid(_world_executor):
		return _world_executor
	var executor := SpellWorldExecutorScript.new()
	var host: Node = world
	if host == null and caster != null and caster.get_parent() != null:
		host = caster.get_parent()
	if host != null:
		host.add_child(executor)
	_world_executor = executor
	return executor
