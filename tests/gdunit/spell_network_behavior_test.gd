extends GdUnitTestSuite
## 法术网络行为测试（08-02 审查 P2 落地）：补强源码字符串检查之外的
## 真实行为断言——空 caster 不扣资源、资格拒绝、成功事务扣法力/提交冷却、
## 双 peer 法力隔离。覆盖 12:40/17:47/19:52 审查提出的行为缺口。

const SR := preload("res://globals/multiplayer/session_root.gd")
const NP := preload("res://globals/multiplayer/network_protocol.gd")
const EL := preload("res://globals/core/state/equipment_loadout.gd")

var _events: Array = []

func before_test() -> void:
	_events.clear()

func _make_server() -> SR:
	var s: SR = SR.new()
	s.init_server()
	return s

## 构造可施法 peer：fireball 配方（ember+force+launch）装备法杖并绑定真实 Player 实体。
func _setup_peer(s: SR, peer_id: int, bind_player: bool, with_staff: bool) -> RefCounted:
	var ctx = s.handle_spawn_request(peer_id)
	ctx.spell_loadout.set_rune_inventory({"ember": 1, "force": 1, "launch": 1})
	ctx.spell_loadout.set_rune(0, 0, "ember")
	ctx.spell_loadout.set_rune(0, 1, "force")
	ctx.spell_loadout.set_rune(0, 2, "launch")
	ctx.spell_mana = 100
	if with_staff:
		ctx.loadout = EL.new()
		ctx.loadout.set_weapon_slot(0, "staff")
		ctx.loadout.set_active_weapon_slot(0)
	if bind_player:
		var world := Node3D.new()
		world.name = "World"
		add_child(world)
		var player := Node3D.new()
		player.name = "Player"
		world.add_child(player)
		ctx.player_node = player
	# P2（0643 审查）：_setup_peer 可能被同一 session 调用多次（双 peer 测试），
	# 连接前必须判重，避免重复连接同一信号产生 Godot ERROR。
	if not s.session_event.is_connected(_on_session_event):
		s.session_event.connect(_on_session_event)
	return ctx

func _on_session_event(evt: Dictionary) -> void:
	_events.append(evt)

func _cast(s: SR, peer_id: int, sequence: int) -> Dictionary:
	return s.on_command(peer_id, {
		"type": NP.CMD_CAST_SPELL,
		"protocol_version": 1,
		"world_revision": s.world.world_revision,
		"sequence": sequence,
		"slot_index": 0,
	})

# ---------------------------------------------------------------------------
# P0-3/P0-4（19:52 审查）：caster 未绑定 → 任何资源 commit 前拒绝
# ---------------------------------------------------------------------------

func test_cast_without_bound_player_rejects_and_keeps_resources() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = _setup_peer(s, 1, false, true)
	var r: Dictionary = _cast(s, 1, 1)
	assert_bool(bool(r.get("success", false))).is_false()
	assert_str(String(r.get("error_code", ""))).is_equal(NP.ERR_PLAYER_NOT_READY)
	# 零资源副作用：法力未扣、冷却未提交
	assert_int(ctx.spell_mana).is_equal(100)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_fireball")).is_false()

# ---------------------------------------------------------------------------
# P0-5（19:52 审查）：服务端施法资格校验（无媒介 → 拒绝且不扣资源）
# ---------------------------------------------------------------------------

func test_cast_without_qualifying_weapon_rejects() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = _setup_peer(s, 1, true, false)  # 绑定实体但空手
	var r: Dictionary = _cast(s, 1, 1)
	assert_bool(bool(r.get("success", false))).is_false()
	assert_str(String(r.get("error_code", ""))).is_equal(NP.ERR_INVALID_TARGET)
	assert_int(ctx.spell_mana).is_equal(100)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_fireball")).is_false()

# ---------------------------------------------------------------------------
# 成功事务：扣法力 + 提交冷却 + 广播 EVT_SPELL_RESOLVED
# ---------------------------------------------------------------------------

func test_successful_cast_consumes_mana_and_commits_cooldown() -> void:
	var s: SR = auto_free(_make_server())
	var ctx = _setup_peer(s, 1, true, true)
	var r: Dictionary = _cast(s, 1, 1)
	assert_bool(bool(r.get("success", false))).is_true()
	assert_int(ctx.spell_mana).is_less(100)
	assert_bool(ctx.spell_runtime.is_on_cooldown("spell_fireball")).is_true()
	var resolved: Array = _events.filter(func(ev): return String(ev.get("event", "")) == NP.EVT_SPELL_RESOLVED)
	assert_int(resolved.size()).is_equal(1)
	assert_str(String(resolved[0].get("spell_id", ""))).is_equal("spell_fireball")
	assert_int(int(resolved[0].get("mana_spent", 0))).is_greater(0)
	# 冷却生效：同槽位重复施法被拒绝且不二次扣法力
	var mana_after_first: int = ctx.spell_mana
	var r2: Dictionary = _cast(s, 1, 2)
	assert_bool(bool(r2.get("success", false))).is_false()
	assert_str(String(r2.get("error_code", ""))).is_equal(NP.ERR_COOLDOWN_ACTIVE)
	assert_int(ctx.spell_mana).is_equal(mana_after_first)

# ---------------------------------------------------------------------------
# 双 peer 隔离（12:40/17:47 审查要求）：法力/冷却互不串线
# ---------------------------------------------------------------------------

func test_two_peers_mana_and_cooldown_isolated() -> void:
	var s: SR = auto_free(_make_server())
	var ctx1 = _setup_peer(s, 1, true, true)
	var ctx2 = _setup_peer(s, 2, true, true)
	var r1: Dictionary = _cast(s, 1, 1)
	assert_bool(bool(r1.get("success", false))).is_true()
	assert_int(ctx1.spell_mana).is_less(100)
	assert_bool(ctx1.spell_runtime.is_on_cooldown("spell_fireball")).is_true()
	# peer2 完全不受影响
	assert_int(ctx2.spell_mana).is_equal(100)
	assert_bool(ctx2.spell_runtime.is_on_cooldown("spell_fireball")).is_false()
	# peer2 可正常施法
	var r2: Dictionary = _cast(s, 2, 1)
	assert_bool(bool(r2.get("success", false))).is_true()
