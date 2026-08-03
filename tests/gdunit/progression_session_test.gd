extends GdUnitTestSuite

## SessionRoot 权威成长闭环测试（架构审查 P1-4）：
## 击杀经验只授予 killer 的 per-peer 上下文；升级选择意图由服务器应用并广播；
## 符文候选按 player_guid 确定性掷出；存档摘要恢复 attributes/skills。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")

func _make_server() -> SR:
	var s: SR = SR.new()
	add_child(s)
	s.init_server()
	return s

func _spawn(s: SR, peer_id: int, guid: String, save_state: Dictionary = {}) -> void:
	s.handle_spawn_request(peer_id, save_state, guid)

func test_kill_awards_xp_only_to_killer_context() -> void:
	var s: SR = auto_free(_make_server())
	_spawn(s, 1, "alpha")
	_spawn(s, 2, "beta")
	var ctx1 = s.registry.get_context(1)
	var ctx2 = s.registry.get_context(2)
	s.set_entity(7001, {"kind": "enemy", "max_life": 20, "current_life": 20, "position": Vector3.ZERO})
	var events: Array = s._on_entity_killed(7001, 1)
	# killer(peer 1) 获得经验；peer 2 不受影响（per-peer 隔离）。
	assert_int(int(ctx1.attributes.level_exp)).is_equal(PA.compute_kill_reward(20))
	assert_int(int(ctx2.attributes.level_exp)).is_equal(0)
	# 广播 EVT_PROGRESSION_CHANGED（killer 视角）。
	var has_prog := false
	for ev in events:
		if ev is Dictionary and String(ev.get("event", "")) == NP.EVT_PROGRESSION_CHANGED \
				and int(ev.get("peer_id", 0)) == 1:
			has_prog = true
	assert_bool(has_prog).is_true()

func test_elite_and_boss_flags_scale_reward() -> void:
	var s: SR = auto_free(_make_server())
	_spawn(s, 1, "alpha")
	var ctx1 = s.registry.get_context(1)
	s.set_entity(7002, {"kind": "enemy", "max_life": 10, "current_life": 10, "is_boss": true, "position": Vector3.ZERO})
	s._on_entity_killed(7002, 1)
	assert_int(int(ctx1.attributes.level_exp)).is_equal(PA.compute_kill_reward(10, false, true))

func test_level_up_choice_applied_by_server_and_broadcast() -> void:
	var s: SR = auto_free(_make_server())
	_spawn(s, 1, "alpha")
	var ctx1 = s.registry.get_context(1)
	ctx1.attributes.accumulate_level_exp(120)  # 1 次待升级
	var str_before: int = int(ctx1.attributes.attrs["str"])
	var events: Array = []
	s.session_event.connect(func(evt): events.append(evt))
	var cmd := {
		"type": NP.CMD_LEVEL_UP_CHOICE, "kind": "attribute", "attr_key": "str",
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1,
	}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_true()
	assert_str(r["event"]["event"]).is_equal(NP.EVT_PROGRESSION_CHANGED)
	assert_int(int(ctx1.attributes.attrs["str"])).is_equal(str_before + 1)
	assert_int(int(ctx1.attributes.get_pending_level_choices())).is_equal(0)
	assert_bool(not events.is_empty()).is_true()

func test_level_up_choice_without_pending_rejected() -> void:
	var s: SR = auto_free(_make_server())
	_spawn(s, 1, "alpha")
	var ctx1 = s.registry.get_context(1)
	var cmd := {
		"type": NP.CMD_LEVEL_UP_CHOICE, "kind": "attribute", "attr_key": "str",
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1,
	}
	var r: Dictionary = s.on_command(1, cmd)
	assert_bool(r["success"]).is_false()
	assert_str(r["error_code"]).is_equal(NP.ERR_INVALID_TARGET)
	assert_int(int(ctx1.attributes.attrs["str"])).is_equal(5)

func test_rune_candidates_command_is_deterministic() -> void:
	var s: SR = auto_free(_make_server())
	_spawn(s, 1, "alpha")
	var ctx1 = s.registry.get_context(1)
	ctx1.attributes.accumulate_level_exp(120)
	var seen: Array = []
	for seq in [1, 2]:
		var cmd := {
			"type": NP.CMD_LEVEL_UP_RUNE_CANDIDATES,
			"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": seq,
		}
		var r: Dictionary = s.on_command(1, cmd)
		assert_bool(r["success"]).is_true()
		assert_str(r["event"]["event"]).is_equal(NP.EVT_PROGRESSION_RUNE_CANDIDATES)
		seen.append(r["event"]["candidates"])
	assert_array(seen[0]).is_equal(seen[1])

func test_rune_choice_command_grants_rune_to_authoritative_inventory() -> void:
	var s: SR = auto_free(_make_server())
	_spawn(s, 1, "alpha")
	var ctx1 = s.registry.get_context(1)
	ctx1.attributes.accumulate_level_exp(120)
	var cand_cmd := {
		"type": NP.CMD_LEVEL_UP_RUNE_CANDIDATES,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 1,
	}
	var cand_r: Dictionary = s.on_command(1, cand_cmd)
	var rune_id := String((cand_r["event"]["candidates"] as Array)[0])
	var pick_cmd := {
		"type": NP.CMD_LEVEL_UP_CHOICE, "kind": "rune", "rune_id": rune_id,
		"protocol_version": 1, "world_revision": s.world.world_revision, "sequence": 2,
	}
	var r: Dictionary = s.on_command(1, pick_cmd)
	assert_bool(r["success"]).is_true()
	assert_int(int(ctx1.inventory.runes.get(rune_id, 0))).is_equal(1)
	assert_int(int(ctx1.attributes.get_pending_level_choices())).is_equal(0)

func test_save_state_restores_attributes_and_skills() -> void:
	var s: SR = auto_free(_make_server())
	var save_state := {
		"attributes": {
			"attrs": {"str": 12, "dex": 7, "mag": 5, "con": 5, "agi": 5, "per": 5},
			"level": 4, "level_exp": 33,
			"weapon_proficiency": {"sword": 40},
		},
		"skills": {"slots": ["重击", "", "", "", "", "", ""]},
	}
	_spawn(s, 1, "alpha", save_state)
	var ctx1 = s.registry.get_context(1)
	assert_int(int(ctx1.attributes.attrs["str"])).is_equal(12)
	assert_int(int(ctx1.attributes.get_level())).is_equal(4)
	assert_int(int(ctx1.attributes.level_exp)).is_equal(33)
	assert_int(int(ctx1.attributes.weapon_proficiency.get("sword", 0))).is_equal(40)
	assert_str(String(ctx1.skills.slots[0])).is_equal("重击")

func test_settlement_carries_authoritative_attributes() -> void:
	var s: SR = auto_free(_make_server())
	_spawn(s, 1, "alpha")
	var ctx1 = s.registry.get_context(1)
	ctx1.attributes.accumulate_level_exp(120)
	var settlement: Dictionary = s._compute_settlement(1)
	assert_bool(settlement.has("attributes")).is_true()
	assert_int(int((settlement["attributes"] as Dictionary).get("level", 0))).is_equal(2)

const PA := preload("res://globals/multiplayer/progression_authority.gd")
