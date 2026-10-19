extends GdUnitTestSuite
## 客户端命令驱动单元测试：重点覆盖 Phase 7 心跳调度逻辑。
## 不依赖真实 NetworkManager / 场景树：通过 nm_override 注入最小 mock 直接驱动 _maybe_send_heartbeat。

const ClientDriverClass := preload("res://scenes/multiplayer/client_command_driver.gd")
const PlayerClass := preload("res://scenes/characters/player/player.gd")
const HealthClass := preload("res://scenes/characters/component/health_component.gd")
const ManaClass := preload("res://scenes/characters/component/mana_component.gd")

## 最小 mock NetworkManager：交互面与真实 NetworkManager 一致（is_active 属性 / is_client / is_host 方法 / send_heartbeat），
## 仅额外计数 send_heartbeat 调用次数，便于断言调度频率。
class MockNM extends RefCounted:
	var is_active: bool = true
	var _client: bool = true
	var _host: bool = false
	var heartbeat_calls: int = 0
	func is_client() -> bool: return _client
	func is_host() -> bool: return _host
	func send_heartbeat() -> void: heartbeat_calls += 1

func _make_driver() -> Node:
	return auto_free(ClientDriverClass.new())

func test_heartbeat_not_fired_before_interval() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(4.0, nm)   # 4.0 < 5.0 → 不触发
	assert_int(nm.heartbeat_calls).is_equal(0)

func test_heartbeat_fired_once_when_interval_crossed() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(4.0, nm)
	d._maybe_send_heartbeat(2.0, nm)   # 累计 6.0 >= 5.0 → 触发 1 次，累加器归零
	assert_int(nm.heartbeat_calls).is_equal(1)

func test_heartbeat_resets_accumulator_between_fires() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(4.0, nm)
	d._maybe_send_heartbeat(2.0, nm)   # 触发 1，归零
	d._maybe_send_heartbeat(4.0, nm)   # 4.0 < 5.0 → 不触发
	assert_int(nm.heartbeat_calls).is_equal(1)
	d._maybe_send_heartbeat(2.0, nm)   # 累计 6.0 → 触发 2
	assert_int(nm.heartbeat_calls).is_equal(2)

func test_heartbeat_skipped_when_not_client() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	nm._client = false     # 房主 / 非客户端：不应向自己 ping
	d._maybe_send_heartbeat(20.0, nm)
	assert_int(nm.heartbeat_calls).is_equal(0)

func test_heartbeat_skipped_when_inactive() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	nm.is_active = false   # 网络未激活：不 ping
	d._maybe_send_heartbeat(20.0, nm)
	assert_int(nm.heartbeat_calls).is_equal(0)

func test_heartbeat_fires_only_once_on_large_delta() -> void:
	var d: Node = _make_driver()
	var nm := MockNM.new()
	d._maybe_send_heartbeat(100.0, nm)   # 单帧超大 delta：只触发 1 次（不补发多次）
	assert_int(nm.heartbeat_calls).is_equal(1)

## 端到端（服务器权威侧）：客户端心跳经 send_heartbeat→服务器 heartbeat→刷新 last_seen，
## 使 check_timeout 在超时窗口内恢复为 false。验证调度器的下游闭环有效。
func test_heartbeat_refreshes_server_last_seen() -> void:
	var ca := preload("res://globals/multiplayer/connection_authority.gd").new()
	ca.register_online(7, "guid_7", 0.0)
	assert_bool(ca.check_timeout(7, 16.0)).is_true()      # 16s 无心跳 → 超时
	ca.touch(7, 16.0)                                      # 等价于客户端心跳到达
	assert_bool(ca.check_timeout(7, 18.0)).is_false()      # 刷新后 2s 内仍在线

# ============================================================================
# P1/A3 修复：客户端 combat-state 镜像原子入口（Player.apply_authoritative_combat_state）
# 只读镜像：health max+current / mana / shield→damage_absorb / buffs 服务器剩余时间 / revision 门禁。
# ============================================================================

## 构造一个最小镜像 Player：注入 HealthComponent 子节点 + ManaComponent 子节点（与真实场景一致）。
func _make_mirror_player() -> Node:
	var p := PlayerClass.new()
	var health := HealthClass.new()
	health.name = "HealthComponent"
	p.add_child(health)
	p.health = health
	var mana := ManaClass.new()
	mana.name = "ManaComponent"
	p.add_child(mana)
	return auto_free(p)

func _combat_state(current_life: int, max_life: int, shield: int = 0, buffs: Dictionary = {}, mana: int = 100) -> Dictionary:
	return {
		"current_life": current_life,
		"max_life": max_life,
		"shield": shield,
		"buffs": buffs,
		"spell_mana": mana,
		"spell_max_mana": 100,
	}

func test_combat_state_syncs_max_and_current_life_and_mana() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	d._apply_combat_state(_combat_state(120, 150, 0, {}, 40), 1)
	assert_int(p.health.max_life).is_equal(150)
	assert_int(p.health.current_life).is_equal(120)
	assert_int(p.get_node("ManaComponent").current_mana).is_equal(40)
	assert_int(p.get_node("ManaComponent").max_mana).is_equal(100)

func test_combat_state_applies_shield_as_scalar_absorb() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	d._apply_combat_state(_combat_state(100, 100, 40), 1)
	var buffs: Dictionary = p.buffs.get_buffs_dict()
	assert_bool(buffs.has("damage_absorb")).is_true()
	assert_float(float(buffs["damage_absorb"]["value"])).is_equal_approx(40.0, 0.001)

func test_combat_state_shield_absorb_scalar_consumable() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	d._apply_combat_state(_combat_state(100, 100, 40), 1)
	# 标量百分比可直接被 consume_damage_absorb 消费（无 {"percent": ...} 类型错误）
	var reduced: int = p.buffs.consume_damage_absorb(30, 100)
	assert_int(reduced).is_equal(0)

func test_combat_state_clears_shield_when_server_clears() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	d._apply_combat_state(_combat_state(100, 100, 25), 1)
	assert_bool(p.buffs.get_buffs_dict().has("damage_absorb")).is_true()
	d._apply_combat_state(_combat_state(100, 100, 0), 2)
	assert_bool(p.buffs.get_buffs_dict().has("damage_absorb")).is_false()

func test_combat_state_uses_server_remaining_buff_time() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	var expiry: int = Time.get_ticks_msec() + 12000
	d._apply_combat_state(_combat_state(100, 100, 0, {"spell_power": expiry}), 1)
	var buffs: Dictionary = p.buffs.get_buffs_dict()
	assert_bool(buffs.has("spell_power")).is_true()
	var remaining := float(buffs["spell_power"]["remaining"])
	assert_float(remaining).is_greater_equal(11.0)
	assert_float(remaining).is_less_equal(13.0)
	# 服务器剩余时间优先：不再固定重建为 6 秒
	assert_bool(remaining > 6.0).is_true()

func test_combat_state_applies_spell_power_buff() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	var expiry: int = Time.get_ticks_msec() + 5000
	d._apply_combat_state(_combat_state(100, 100, 0, {"spell_power": expiry}), 1)
	assert_bool(p.buffs.has("spell_power")).is_true()

func test_combat_state_clears_buff_no_longer_in_server_set() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	var expiry: int = Time.get_ticks_msec() + 8000
	d._apply_combat_state(_combat_state(100, 100, 0, {"spell_power": expiry}), 1)
	assert_bool(p.buffs.has("spell_power")).is_true()
	d._apply_combat_state(_combat_state(100, 100, 0, {}), 2)
	assert_bool(p.buffs.has("spell_power")).is_false()

func test_combat_state_rejects_stale_revision() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	d._apply_combat_state(_combat_state(80, 100), 5)
	assert_int(p.health.current_life).is_equal(80)
	d._apply_combat_state(_combat_state(20, 100), 3)
	assert_int(p.health.current_life).is_equal(80)

func test_combat_state_guards_out_of_order() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	d._apply_combat_state(_combat_state(50, 100), 2)
	d._apply_combat_state(_combat_state(90, 100), 7)
	d._apply_combat_state(_combat_state(10, 100), 4)
	assert_int(p.health.current_life).is_equal(90)
	d._apply_combat_state(_combat_state(30, 100), 8)
	assert_int(p.health.current_life).is_equal(30)

func test_combat_state_mirror_preserves_local_buffs() -> void:
	var p: Node = _make_mirror_player()
	var d: Node = _make_driver()
	d.player = p
	p.buffs.add("def_and_evade_up", 5.0, {"def": 4, "evade": 5})
	d._apply_combat_state(_combat_state(100, 100), 1)
	assert_bool(p.buffs.has("def_and_evade_up")).is_true()

func test_apply_authoritative_combat_state_returns_gate_result() -> void:
	var p := PlayerClass.new()
	var health := HealthClass.new()
	p.add_child(health)
	p.health = health
	var applied_ok: bool = p.apply_authoritative_combat_state(_combat_state(60, 100), 4)
	assert_bool(applied_ok).is_true()
	var rejected: bool = p.apply_authoritative_combat_state(_combat_state(30, 100), 2)
	assert_bool(rejected).is_false()
	assert_int(p.health.current_life).is_equal(60)
	p.free()
