extends GdUnitTestSuite
const Executor := preload("res://globals/combat/spell_world_executor.gd")
const Authority := preload("res://globals/combat/spell_authority.gd")
const PlayerContextScript := preload("res://globals/core/player_context.gd")

func test_area_ground_and_summon_create_bounded_entities() -> void:
	var world := Node3D.new(); add_child(world)
	var caster := Node3D.new(); world.add_child(caster)
	var executor := Executor.new(); world.add_child(executor)
	for kind in ["area","ground","summon"]:
		var request := {"type":kind,"origin":Vector3.ZERO,"direction":Vector3.FORWARD,"params":{"duration":1.0,"radius":2.0}}
		var result := executor.execute(caster,request,world)
		assert_bool(bool(result.ok)).is_true()
		assert_object(result.entity).is_not_null()
	assert_int(executor._fields.size()).is_equal(2)
	assert_int(executor._summons.size()).is_equal(1)
	world.queue_free()

func test_world_executor_has_budgets_and_cleanup() -> void:
	var source := (load("res://globals/combat/spell_world_executor.gd") as GDScript).source_code
	assert_bool(source.contains("MAX_ACTIVE_FIELDS")).is_true()
	assert_bool(source.contains("MAX_ACTIVE_SUMMONS")).is_true()
	assert_bool(source.contains("queue_free()")).is_true()
	assert_bool(source.contains("FIELD_TICK_SEC")).is_true()

func test_player_context_owns_per_peer_spell_state() -> void:
	var source := (load("res://globals/core/player_context.gd") as GDScript).source_code
	assert_bool(source.contains("var spell_loadout")).is_true()
	assert_bool(source.contains("var spell_runtime")).is_true()
	assert_bool(source.contains("var spell_mana")).is_true()
	var session_source := (load("res://globals/multiplayer/session_root.gd") as GDScript).source_code
	var section := session_source.substr(session_source.find("func _handle_cast_spell"), 1800)
	assert_bool(section.contains("ctx.spell_loadout")).is_true()
	assert_bool(section.contains("ctx.spell_mana")).is_true()
	assert_bool(not section.contains("GameState")).is_true()

func test_spell_authority_connects_world_executor() -> void:
	var source := (load("res://globals/combat/spell_authority.gd") as GDScript).source_code
	assert_bool(source.contains("SpellWorldExecutorScript")).is_true()
	# P0-3：世界执行器为会话实例（非 static 共享）；执行经 _ensure_executor 获取并调用。
	assert_bool(source.contains("_ensure_executor")).is_true()
	assert_bool(source.contains("executor.execute(caster, execution.world_request, world, caster_peer)")).is_true()
	assert_bool(source.contains("ProjectileService")).is_true()

# ---------------------------------------------------------------------------
# P0-1-D 回归：实体伤害端口单次调用语义（ray 双重扣血根防）
# ---------------------------------------------------------------------------

func test_apply_damage_calls_port_exactly_once_for_entity_target() -> void:
	var world := Node3D.new(); add_child(world)
	var executor := Executor.new(); world.add_child(executor)
	var target := Node3D.new(); target.set_meta("entity_id", 1001); world.add_child(target)
	var calls: Array = []
	executor.damage_entity_port = func(eid: int, dmg: int, caster_peer: int) -> Dictionary:
		calls.append([eid, dmg, caster_peer])
		return {"ok": true, "killed": false, "events": [{"event": "entity_snapshot", "entity_id": eid}]}
	var res: Dictionary = executor._apply_damage(target, null, 5, 1)
	# 端口恰好调用一次（旧实现 _execute_ray 会二次调用 → 双重扣血/重复击杀）。
	assert_int(calls.size()) \
		.override_failure_message("实体目标伤害端口必须恰好调用一次").is_equal(1)
	assert_int(calls[0][0]).is_equal(1001)
	assert_int(int(res["applied"])).is_equal(5)
	assert_bool(bool(res["port_called"])).is_true()
	assert_bool(bool(res["port_result"]["ok"])).is_true()
	# 端口拒绝会原样返回给 ray 的事务校验层，不能伪装成已写回。
	executor.damage_entity_port = func(_eid: int, _dmg: int, _caster_peer: int) -> Dictionary:
		return {"ok": false, "events": []}
	var rejected: Dictionary = executor._apply_damage(target, null, 5, 1)
	assert_bool(bool(rejected["port_called"])).is_true()
	assert_bool(bool(rejected["port_result"]["ok"])).is_false()
	# 无 entity_id 的目标不触发端口（port_called=false）。
	var plain := Node3D.new(); world.add_child(plain)
	var res2: Dictionary = executor._apply_damage(plain, null, 3, 1)
	assert_bool(bool(res2["port_called"])).is_false()
	assert_int(calls.size()).is_equal(1)
	world.queue_free()

func test_apply_damage_null_target_is_noop() -> void:
	var world := Node3D.new(); add_child(world)
	var executor := Executor.new(); world.add_child(executor)
	var res: Dictionary = executor._apply_damage(null, null, 5, 1)
	assert_int(int(res["applied"])).is_equal(0)
	assert_bool(bool(res["port_called"])).is_false()
	world.queue_free()

# ---------------------------------------------------------------------------
# P0-1-C：field/summon 异步事件 outbox
# ---------------------------------------------------------------------------

func test_port_with_outbox_collects_events_and_drains() -> void:
	var world := Node3D.new(); add_child(world)
	var executor := Executor.new(); world.add_child(executor)
	executor.damage_entity_port = func(eid: int, dmg: int, caster_peer: int) -> Dictionary:
		return {"ok": true, "killed": true, "events": [
			{"event": "entity_despawned", "entity_id": eid},
			{"event": "entity_spawned", "entity_id": 5001},
		]}
	var r: Dictionary = executor._port_with_outbox(1001, 5, 1)
	assert_bool(bool(r["killed"])).is_true()
	# 异步 tick 的事件进入 outbox（不丢），可被会话排空广播。
	assert_int(executor.pending_event_count()).is_equal(2)
	var drained: Array = executor.drain_pending_events()
	assert_int(drained.size()).is_equal(2)
	assert_str(drained[0].get("event", "")).is_equal("entity_despawned")
	assert_int(executor.pending_event_count()).is_equal(0)
	world.queue_free()

func test_port_with_outbox_ignores_empty_events() -> void:
	var world := Node3D.new(); add_child(world)
	var executor := Executor.new(); world.add_child(executor)
	executor.damage_entity_port = func(eid: int, dmg: int, caster_peer: int) -> Dictionary:
		return {"ok": true, "killed": false}
	var r: Dictionary = executor._port_with_outbox(1001, 5, 1)
	assert_bool(bool(r["ok"])).is_true()
	assert_int(executor.pending_event_count()).is_equal(0)
	world.queue_free()
