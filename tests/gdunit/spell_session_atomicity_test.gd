extends GdUnitTestSuite

## SessionRoot 法术事务原子性测试（架构审查 P0-4/P0-5）：
##   * caster 未绑定 → 任何资源 commit 前拒绝（PLAYER_NOT_READY），法力/冷却不变；
##   * caster 已绑定 + 资格符合 → 扣法力/提交冷却/产出 EVT_SPELL_RESOLVED；
##   * 施法资格（SpellAccessPolicy）在 commit 前校验，无专注武器 → 拒绝且资源不变；
##   * 存档摘要中的 spell_state 恢复为服务器权威法术装配来源。
## 全部为真实行为测试（不读源码字符串）。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const SpellRecipeData := preload("res://globals/combat/spell_recipe_data.gd")

const ATTRS_DEFAULTS := {"str": 5, "dex": 5, "mag": 5, "con": 5, "agi": 5, "per": 5}

func _make_server() -> SR:
	var s: SR = SR.new()
	add_child(s)
	s.init_server()
	return s

## 生成带施法资格（法杖槽位 + 指定装配）的玩家：spell_state 直接构造。
## runes: 五个槽位的符文三连（默认 ember 装配）。
func _spawn_caster(s: SR, peer_id: int = 1, runes: Array = [["ember", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]]) -> void:
	var spell_state := {
		"spell_loadout": {"slot_runes": runes},
		"spell_mana": 100,
		"spell_max_mana": 100,
		"spell_runtime": {},
	}
	var save_state := {
		"loadout": {"weapon_slots": ["grimoire", "", "", ""], "armor_slots": {}, "active_weapon_slot": 0},
		"spell_state": spell_state,
	}
	s.handle_spawn_request(peer_id, save_state, "caster_%d" % peer_id)

func _cast_command(s: SR, slot_index: int = 0, sequence: int = 1) -> Dictionary:
	return {
		"type": NP.CMD_CAST_SPELL,
		"slot_index": slot_index,
		"protocol_version": 1,
		"world_revision": s.world.world_revision,
		"sequence": sequence,
	}

func _bind_caster(s: SR, peer_id: int = 1) -> Node3D:
	var caster := Node3D.new()
	caster.name = "Caster%d" % peer_id
	add_child(caster)
	s.bind_player_entity(peer_id, caster)
	return caster

func test_cast_without_bound_caster_rejects_before_any_resource_commit() -> void:
	# P0-4 核心回归：未绑定 caster 时，法力与冷却必须完全不变。
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	var ctx = s.registry.get_context(1)
	var mana_before: int = ctx.spell_mana
	var r: Dictionary = s.on_command(1, _cast_command(s))
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_PLAYER_NOT_READY)
	assert_int(ctx.spell_mana).is_equal(mana_before)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_ember_bolt")).is_false()

func test_cast_with_bound_caster_commits_mana_and_cooldown_and_resolves() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	var ctx = s.registry.get_context(1)
	var events: Array = []
	s.session_event.connect(func(evt): events.append(evt))
	var r: Dictionary = s.on_command(1, _cast_command(s))
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_SPELL_RESOLVED)
	assert_str(r["event"]["spell_id"]).is_equal("spell_ember_bolt")
	var mana_cost: int = ctx.spell_runtime.mana_cost_for(SpellRecipeData.resolve(["ember"]))
	assert_int(ctx.spell_mana).is_equal(100 - mana_cost)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_ember_bolt")).is_true()
	assert_int(int(r["event"]["mana_remaining"])).is_equal(100 - mana_cost)
	assert_bool(not events.is_empty()).is_true()

func test_cast_without_spell_focus_weapon_rejects_before_commit() -> void:
	# P0-5：绕过本地 UI 直接提交施法——无法杖/魔导书/奥法之剑 → 拒绝且资源不变。
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	var ctx = s.registry.get_context(1)
	ctx.loadout.set_weapon_slot(0, "shortsword")
	_bind_caster(s)
	var mana_before: int = ctx.spell_mana
	var r: Dictionary = s.on_command(1, _cast_command(s))
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)
	assert_int(ctx.spell_mana).is_equal(mana_before)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_ember_bolt")).is_false()

func test_cast_with_unarmed_loadout_rejects_before_commit() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	var ctx = s.registry.get_context(1)
	ctx.loadout.set_weapon_slot(0, "")
	_bind_caster(s)
	var mana_before: int = ctx.spell_mana
	var r: Dictionary = s.on_command(1, _cast_command(s))
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)
	assert_int(ctx.spell_mana).is_equal(mana_before)

func test_spell_state_restored_from_save_state_is_authoritative_source() -> void:
	# P0-5：存档摘要携带 spell_state 时，服务器权威 SpellLoadout 恢复（非空装配）。
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	var ctx = s.registry.get_context(1)
	var spell: Dictionary = ctx.spell_loadout.get_spell(0)
	assert_bool(not spell.is_empty()).is_true()
	assert_str(String(spell.get("id", ""))).is_equal("spell_ember_bolt")
	# 反例：无 spell_state 的 spawn 保持默认空装配（旧行为）。
	var s2: SR = auto_free(_make_server())
	s2.handle_spawn_request(2, {}, "plain_2")
	assert_bool(s2.registry.get_context(2).spell_loadout.get_spell(0).is_empty()).is_true()

func test_cast_insufficient_mana_rejects_before_commit() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	var ctx = s.registry.get_context(1)
	ctx.spell_mana = 1
	var r: Dictionary = s.on_command(1, _cast_command(s))
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INSUFFICIENT_RESOURCE)
	assert_int(ctx.spell_mana).is_equal(1)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_ember_bolt")).is_false()

func test_cooldown_blocks_recast_without_extra_mana_spend() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	var ctx = s.registry.get_context(1)
	var first: Dictionary = s.on_command(1, _cast_command(s, 0, 1))
	assert_bool(first["success"]).is_true()
	var mana_after_first: int = ctx.spell_mana
	var second: Dictionary = s.on_command(1, _cast_command(s, 0, 2))
	assert_bool(second["success"]).is_false()
	assert_str(second["error_code"]).is_equal(NP.ERR_COOLDOWN_ACTIVE)
	assert_int(ctx.spell_mana).is_equal(mana_after_first)

func test_duplicate_sequence_rejected_for_cast() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	var cmd := _cast_command(s, 0, 5)
	var first: Dictionary = s.on_command(1, cmd)
	assert_bool(first["success"]).is_true()
	var replay: Dictionary = s.on_command(1, cmd)
	assert_bool(replay["success"]).is_false()
	assert_str(replay["error_code"]).is_equal(NP.ERR_INVALID_SEQUENCE)

# ---------------------------------------------------------------------------
# P0-1-B：projectile 服务缺失/生成失败不得 commit；命中写回权威实体仓
# ---------------------------------------------------------------------------

func test_projectile_spawn_failure_rejects_before_commit() -> void:
	# P0-1-B：投射物生成失败（未注册 projectile_id → ProjectileService.spawn 返回 null）
	# → authority 执行 ok=false，SessionRoot 不扣法力/不提交冷却。
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	var ctx = s.registry.get_context(1)
	var mana_before: int = ctx.spell_mana
	# 构造未注册 projectile_id 的 effect_plan（真实 spawn 会返回 null）。
	var plan: Dictionary = ctx.spell_runtime._effect_plan({"implementation": "projectile", "spell": {"projectile_id": "__not_registered__"}})
	var ex: Dictionary = s.spell_auth.execute(ctx.player_node, {"ok": true, "spell_id": "spell_unregistered", "effect_plan": plan, "origin": Vector3.ZERO, "direction": Vector3.FORWARD, "visual_event": {}}, ctx.player_node.get_parent(), 1)
	assert_bool(bool(ex.get("ok", true))) \
		.override_failure_message("未注册投射物 id 必须令执行失败（reason=%s）" % str(ex.get("reason", ""))).is_false()
	assert_str(String(ex.get("reason", ""))).is_equal("projectile_spawn_failed")
	assert_int(ctx.spell_mana).is_equal(mana_before)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_ember_bolt")).is_false()

func test_projected_hit_writes_back_to_entity_registry_via_port() -> void:
	# P0-1-B：投射物命中带 entity_id 的目标 → 端口写回实体仓（存活扣血 / 死亡移除）。
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	s._ensure_spell_world_executor()
	s.set_entity(1001, {"kind": "enemy", "current_life": 15, "max_life": 15})
	var ex: Node = s.spell_auth.get_world_executor()
	var target := Node3D.new()
	target.set_meta("entity_id", 1001)
	add_child(target)
	# 直接经 outbox 包装端口调用（等价投射物命中路径）。
	var port: Callable = ex.make_outbox_port()
	var res: Dictionary = port.call(1001, 10, 1)
	assert_bool(bool(res["ok"])).is_true()
	assert_int(int(s._entities[1001]["current_life"])).is_equal(5)
	# 复制事件进入 outbox，可被会话排空。
	var events: Array = s.poll_spell_world_events()
	assert_bool(not events.is_empty()).is_true()
	# 致死 → 实体移除 + 掉落。
	var res2: Dictionary = port.call(1001, 10, 1)
	assert_bool(bool(res2["killed"])).is_true()
	assert_bool(s._entities.has(1001)).is_false()
	target.queue_free()

# ---------------------------------------------------------------------------
# P0-3：世界执行失败（预算满）→ 法力/冷却不得提交
# ---------------------------------------------------------------------------

func test_world_field_budget_full_rejects_before_any_resource_commit() -> void:
	# bhumi = ground 实施（field 路径）；预算满时世界执行返回 ok=false，
	# SessionRoot 必须在 commit 前拒绝：法力不变、冷却不提交。
	var s: SR = auto_free(_make_server())
	_spawn_caster(s, 1, [["bhumi", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]])
	_bind_caster(s)
	var ctx = s.registry.get_context(1)
	var first: Dictionary = s.on_command(1, _cast_command(s, 0, 1))
	assert_bool(first["success"]).is_true()  # 首次施放：world 执行成功
	var mana_after_first: int = ctx.spell_mana
	ctx.spell_runtime.clear_cooldowns()  # 避免冷却预检拦截第二次施放
	# 把会话执行器的 field 预算塞满（24 个有效实例）。
	var ex: Node = s.spell_auth.get_world_executor()
	assert_object(ex).is_not_null()
	var filler: Array = []
	while ex._fields.size() < 24:
		var f := Node3D.new()
		ex._fields.append(f)
		filler.append(f)
	var second: Dictionary = s.on_command(1, _cast_command(s, 0, 2))
	assert_bool(second["success"]).is_false()
	assert_str(second["error_code"]).is_equal(NP.ERR_INVALID_STATE)
	# 资源未被扣：法力保持首次施放后的值，冷却未重新提交。
	assert_int(ctx.spell_mana).is_equal(mana_after_first)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_stone_spike")).is_false()
	# 释放填充节点（避免 ObjectDB 泄漏 → gdUnit orphan 门禁）。
	for f in filler:
		f.free()

# ---------------------------------------------------------------------------
# P0-3：世界伤害写回权威实体仓（生命/死亡/掉落复制）
# ---------------------------------------------------------------------------

func test_spell_damage_writeback_kills_entity_and_drops_loot() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	# 服务器权威实体（与普通攻击相同的实体仓）。
	s.set_entity(1001, {"kind": "enemy", "label": "Rat", "current_life": 5, "max_life": 5,
		"loot_table": {"goblin_tooth": {"kind": "material", "weight": 10, "min": 1, "max": 2}}})
	var out: Dictionary = s._spell_damage_entity(1001, 5, 1)
	assert_bool(out["ok"]).is_true()
	assert_bool(out["killed"]).is_true()
	# 死亡 → 实体被移除（despawn 事件）。
	assert_bool(s._entities.has(1001)).is_false()
	# 掉落物已生成（entity_spawned 事件）。
	var has_loot: bool = false
	for ev in out["events"]:
		if ev.get("event", "") == NP.EVT_ENTITY_SPAWNED and ev.get("data", {}).get("item_id", "") == "goblin_tooth":
			has_loot = true
	assert_bool(has_loot).is_true()

func test_spell_damage_writeback_updates_nonlethal_life() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	s.set_entity(1002, {"kind": "enemy", "current_life": 10, "max_life": 10})
	var out: Dictionary = s._spell_damage_entity(1002, 3, 1)
	assert_bool(out["ok"]).is_true()
	assert_bool(out["killed"]).is_false()
	assert_int(int(s._entities[1002]["current_life"])).is_equal(7)
	assert_bool(s._entities.has(1002)).is_true()

func test_spell_damage_writeback_rejects_unknown_or_negative() -> void:
	var s: SR = auto_free(_make_server())
	_spawn_caster(s)
	_bind_caster(s)
	assert_bool(s._spell_damage_entity(9999, 5, 1)["ok"]).is_false()
	s.set_entity(1003, {"kind": "enemy", "current_life": 5, "max_life": 5})
	assert_bool(s._spell_damage_entity(1003, -1, 1)["ok"]).is_false()
	assert_int(int(s._entities[1003]["current_life"])).is_equal(5)

# ---------------------------------------------------------------------------
# P0-3/P1-1：世界执行器为会话实例（不再 static 跨会话共享）
# ---------------------------------------------------------------------------

func test_world_executor_is_session_owned_not_static_shared() -> void:
	var s1: SR = auto_free(_make_server())
	_spawn_caster(s1, 1, [["bhumi", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]])
	_bind_caster(s1)
	var r: Dictionary = s1.on_command(1, _cast_command(s1, 0, 1))
	assert_bool(r["success"]).is_true()
	var ex1: Node = s1.spell_auth.get_world_executor()
	assert_object(ex1).is_not_null()
	# 执行器由 SessionRoot 拥有（挂为其子节点）→ 生命周期随会话释放。
	assert_object(ex1.get_parent()).is_equal(s1)
	# 独立会话互不共享执行器（字段/召唤预算、节点归属隔离）。
	var s2: SR = auto_free(_make_server())
	assert_object(s2.spell_auth.get_world_executor()).is_null()
	# 两会话执行器不是同一实例（旧实现 static var 共享的回归门禁）。
	_spawn_caster(s2, 1, [["bhumi", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]])
	_bind_caster(s2)
	var r2: Dictionary = s2.on_command(1, _cast_command(s2, 0, 1))
	assert_bool(r2["success"]).is_true()
	var ex2: Node = s2.spell_auth.get_world_executor()
	assert_object(ex2).is_not_null()
	assert_int(ex1.get_instance_id()).is_not_equal(ex2.get_instance_id())
