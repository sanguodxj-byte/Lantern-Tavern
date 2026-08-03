class_name SpellWorldExecutor
extends Node

## 服务端/单机世界法术实体执行器。
## 负责 ray/area/ground/summon 的生命周期、目标查询和效果应用；FX 只由 visual_event 驱动。
##
## 架构审查 P0-3：伤害不再直接打在可见节点上——当目标节点携带 entity_id meta 且
## damage_entity_port 已接线时，经端口写回 SessionRoot 权威实体仓（生命/死亡/掉落复制）。
## 联机会话由 SessionRoot 预注入端口并挂树；单机（无端口）保持节点直伤回退。

const MAX_ACTIVE_FIELDS := 24
const MAX_ACTIVE_SUMMONS := 8
const FIELD_TICK_SEC := 0.35

## 权威实体仓伤害端口：func(entity_id:int, damage:int, caster_peer:int) -> Dictionary。
## SessionRoot 注入后，field/summon/ray 的命中伤害写回服务器实体仓并产出复制事件。
var damage_entity_port: Callable = Callable()

## P0-1-C：异步实体事件 outbox（field/summon tick 产生的 entity_snapshot/despawn/spawn）。
## 由 SessionRoot.poll_spell_world_events() 定期排空并经 NetworkManager 广播。
var _pending_events: Array = []

var _fields: Array[Node3D] = []
var _summons: Array[Node3D] = []

## caster_peer: 施法者服务器 peer_id（写回端口时用于击杀归属/掉落）。
func execute(caster: Node3D, request: Dictionary, world: Node = null, caster_peer: int = 0) -> Dictionary:
	if caster == null or request.is_empty():
		return {"ok": false, "reason": "invalid_world_request"}
	var kind := String(request.get("type", ""))
	match kind:
		"ray": return _execute_ray(caster, request, world, caster_peer)
		"area": return _spawn_field(caster, request, world, false, caster_peer)
		"ground": return _spawn_field(caster, request, world, true, caster_peer)
		"summon": return _spawn_summon(caster, request, world, caster_peer)
	return {"ok": false, "reason": "unsupported_world_request"}

func _execute_ray(caster: Node3D, request: Dictionary, world: Node, caster_peer: int) -> Dictionary:
	var origin := Vector3(request.get("origin", caster.global_position))
	var direction := Vector3(request.get("direction", -caster.global_transform.basis.z)).normalized()
	var target := _ray_target(caster, origin, direction, 18.0)
	var damage := int(Dictionary(request.get("params", {})).get("damage", 12))
	var target_entity_id := 0
	if target != null and target.has_meta("entity_id"):
		target_entity_id = int(target.get_meta("entity_id"))
	# P0-1-D：_apply_damage 已收敛为【单次】伤害应用——目标带 entity_id 且端口有效时
	# 由端口写回（返回 port_result），否则退化为节点直伤。此处绝不再二次调用端口。
	var dmg_result := _apply_damage(target, caster, damage, caster_peer)
	var port_result: Dictionary = dmg_result.get("port_result", {})
	# 权威实体端口是事务边界：目标存在但 SessionRoot 拒绝写回时，ray
	# 必须失败，禁止上层在 commit 前把法力/冷却当作已完成效果提交。
	if bool(dmg_result.get("port_called", false)) and not bool(port_result.get("ok", false)):
		return {"ok": false, "type": "ray", "reason": "entity_damage_rejected",
			"target": target, "target_entity_id": target_entity_id,
			"damage_applied": 0, "port_called": true, "port_result": port_result}
	return {"ok": true, "type": "ray", "target": target, "target_entity_id": target_entity_id,
		"damage_applied": int(dmg_result.get("applied", 0)),
		"port_called": bool(dmg_result.get("port_called", false)),
		"port_result": port_result}

func _spawn_field(caster: Node3D, request: Dictionary, world: Node, ground: bool, caster_peer: int) -> Dictionary:
	_cleanup_invalid(_fields)
	if _fields.size() >= MAX_ACTIVE_FIELDS:
		return {"ok": false, "reason": "field_budget"}
	var field := SpellField.new()
	field.configure(caster, request, ground)
	field.caster_peer = caster_peer
	field.damage_port = _port_with_outbox
	(caster.get_parent() if world == null else world).add_child(field)
	_fields.append(field)
	return {"ok": true, "type": "ground" if ground else "area", "entity": field, "duration": field.duration_sec}

func _spawn_summon(caster: Node3D, request: Dictionary, world: Node, caster_peer: int) -> Dictionary:
	_cleanup_invalid(_summons)
	if _summons.size() >= MAX_ACTIVE_SUMMONS:
		return {"ok": false, "reason": "summon_budget"}
	var summon := SpellSummon.new()
	summon.configure(caster, request)
	summon.caster_peer = caster_peer
	summon.damage_port = _port_with_outbox
	(caster.get_parent() if world == null else world).add_child(summon)
	_summons.append(summon)
	return {"ok": true, "type": "summon", "entity": summon, "duration": summon.duration_sec}

## P0-1-C：field/summon 异步伤害的端口包装——写回实体仓并把返回的事件收集进 outbox，
## 由 SessionRoot 排空广播（异步 tick 不在施法命令响应窗口内，事件不能丢）。
func _port_with_outbox(entity_id: int, damage: int, caster_peer: int) -> Dictionary:
	var res: Dictionary = {}
	if damage_entity_port.is_valid():
		res = damage_entity_port.call(entity_id, damage, caster_peer)
		var events = res.get("events", [])
		if events is Array and not (events as Array).is_empty():
			for ev in events:
				if ev is Dictionary and not (ev as Dictionary).is_empty():
					_pending_events.append(ev)
	return res

## 排空异步实体事件 outbox（服务器 tick 调用）。返回事件数组。
func drain_pending_events() -> Array:
	var out: Array = _pending_events.duplicate()
	_pending_events.clear()
	return out

func pending_event_count() -> int:
	return _pending_events.size()

## 供投射物/外部路径使用的 outbox 包装端口（命中事件进 outbox，由会话统一排空）。
func make_outbox_port() -> Callable:
	return _port_with_outbox

func _ray_target(caster: Node3D, origin: Vector3, direction: Vector3, distance: float) -> Node:
	var space := caster.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance)
	query.exclude = [caster]
	var hit := space.intersect_ray(query)
	var collider: Object = hit.get("collider")
	return collider as Node

## 应用伤害（P0-1-D 单次语义）：返回 {"applied":int, "port_called":bool, "port_result":Dictionary}。
##   * 目标带 entity_id 且端口有效 → 端口写回权威实体仓（唯一一次），port_called=true；
##   * 否则退化为节点直伤（单机/无端口回退）。
func _apply_damage(target: Node, caster: Node3D, damage: int, caster_peer: int) -> Dictionary:
	if target == null:
		return {"applied": 0, "port_called": false, "port_result": {}}
	if target.has_meta("entity_id") and damage_entity_port.is_valid():
		var entity_id: int = int(target.get_meta("entity_id"))
		if entity_id != 0:
			var res: Dictionary = damage_entity_port.call(entity_id, maxi(damage, 0), caster_peer)
			return {"applied": maxi(damage, 0), "port_called": true, "port_result": res}
	if target.has_method("try_receive_hit"):
		target.try_receive_hit(caster, maxi(damage, 0))
		return {"applied": maxi(damage, 0), "port_called": false, "port_result": {}}
	if "health" in target and target.health != null and target.health.has_method("take_damage"):
		target.health.take_damage(maxi(damage, 0))
		return {"applied": maxi(damage, 0), "port_called": false, "port_result": {}}
	return {"applied": 0, "port_called": false, "port_result": {}}

func _cleanup_invalid(items: Array) -> void:
	for i in range(items.size() - 1, -1, -1):
		if not is_instance_valid(items[i]): items.remove_at(i)

class SpellField:
	extends Area3D
	var duration_sec := 3.0
	var tick_accum := 0.0
	var caster: Node3D
	var caster_peer: int = 0
	var damage_port: Callable = Callable()
	var request: Dictionary
	var imagery := "unknown"
	var is_ground := false
	func configure(owner: Node3D, data: Dictionary, ground: bool) -> void:
		caster = owner
		request = data.duplicate(true)
		imagery = String(data.get("imagery", Dictionary(data.get("params", {})).get("imagery", "unknown")))
		is_ground = ground
		duration_sec = float(Dictionary(data.get("params", {})).get("duration", 3.0))
		monitoring = true
		collision_layer = 0
		collision_mask = 1 << 2
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = float(Dictionary(data.get("params", {})).get("radius", 4.0))
		shape.shape = sphere
		add_child(shape)
		if is_ground and imagery in ["stone_wall", "earthquake", "stone_spike"]:
			var blocker := StaticBody3D.new()
			blocker.name = "SpellGroundBlocker"
			var block_shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(sphere.radius * 2.0, 1.2, 0.45)
			block_shape.shape = box
			blocker.add_child(block_shape)
			add_child(blocker)
		position = Vector3(data.get("origin", owner.global_position))
	func _physics_process(delta: float) -> void:
		duration_sec -= delta; tick_accum += delta
		if duration_sec <= 0.0: queue_free(); return
		if tick_accum < FIELD_TICK_SEC: return
		tick_accum = 0.0
		for body in get_overlapping_bodies():
			if body == caster: continue
			var damage := int(Dictionary(request.get("params", {})).get("damage", 4))
			if body.has_meta("entity_id") and damage_port.is_valid():
				damage_port.call(int(body.get_meta("entity_id")), damage, caster_peer)
			elif body.has_method("try_receive_hit"):
				body.try_receive_hit(caster, damage)

class SpellSummon:
	extends Node3D
	const ATTACK_INTERVAL := 1.0
	const ATTACK_RANGE := 7.0
	var duration_sec := 12.0
	var attack_accum := 0.0
	var caster: Node3D
	var caster_peer: int = 0
	var damage_port: Callable = Callable()
	var request: Dictionary
	func configure(owner: Node3D, data: Dictionary) -> void:
		caster = owner
		request = data.duplicate(true)
		duration_sec = float(Dictionary(data.get("params", {})).get("duration", 12.0))
		position = Vector3(data.get("origin", Vector3.ZERO))
		name = "SpellSummon_%s" % String(data.get("spell_id", "construct"))
	func _process(delta: float) -> void:
		duration_sec -= delta
		attack_accum += delta
		if duration_sec <= 0.0:
			queue_free()
			return
		if attack_accum < ATTACK_INTERVAL:
			return
		attack_accum = 0.0
		var target := _nearest_enemy()
		if target == null:
			return
		var damage := int(Dictionary(request.get("params", {})).get("damage", 6))
		if target.has_meta("entity_id") and damage_port.is_valid():
			damage_port.call(int(target.get_meta("entity_id")), damage, caster_peer)
		elif target.has_method("try_receive_hit"):
			target.try_receive_hit(caster, damage)
	func _nearest_enemy() -> Node3D:
		var nearest: Node3D = null
		var nearest_dist := ATTACK_RANGE
		for node in get_tree().get_nodes_in_group("enemies"):
			if node is Node3D and is_instance_valid(node):
				var distance := global_position.distance_to(node.global_position)
				if distance < nearest_dist:
					nearest = node
					nearest_dist = distance
		return nearest
