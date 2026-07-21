extends GdUnitTestSuite

# PlayerRegistry（docs/25 §3.3/§4.3）：peer→(PlayerContext/Player/PlayerSession) 映射、
# 生成状态、独立性。
# 注意：每个用例自建全新 registry，避免依赖 before() 的调用频次语义，
# 也确保 per-instance 隔离被独立验证。

const PR := preload("res://globals/multiplayer/player_registry.gd")
const PC := preload("res://globals/core/player_context.gd")

func _new_reg():
	return auto_free(PR.new())

func _ctx(peer_id: int) -> PC:
	var ap = auto_free(load("res://globals/combat/attr_panel.gd").new()); ap.init_defaults()
	var sk = auto_free(load("res://globals/combat/skill_runtime.gd").new()); sk.init_defaults()
	var inv = auto_free(load("res://globals/core/state/expedition_inventory.gd").new())
	var lo = auto_free(load("res://globals/core/state/equipment_loadout.gd").new())
	return PC.for_peer(ap, sk, inv, lo)

func test_register_and_get_context() -> void:
	var reg = _new_reg()
	var c = _ctx(1)
	reg.register_peer(1, c)
	assert_int(reg.get_context(1).get_instance_id()).is_equal(c.get_instance_id())
	assert_bool(reg.has_peer(1)).is_true()

func test_register_creates_session() -> void:
	var reg = _new_reg()
	reg.register_peer(2, _ctx(2))
	assert_object(reg.get_session(2)).is_not_null()
	assert_int(reg.get_session(2).peer_id).is_equal(2)

func test_two_peers_independent() -> void:
	var reg = _new_reg()
	reg.register_peer(1, _ctx(1))
	reg.register_peer(2, _ctx(2))
	assert_int(reg.get_context(1).get_instance_id()).is_not_equal(reg.get_context(2).get_instance_id())
	assert_int(reg.peer_ids().size()).is_equal(2)

func test_spawned_state() -> void:
	var reg = _new_reg()
	reg.register_peer(3, _ctx(3))
	assert_bool(reg.is_spawned(3)).is_false()
	reg.set_spawned(3, true)
	assert_bool(reg.is_spawned(3)).is_true()

func test_unregister_removes_everything() -> void:
	var reg = _new_reg()
	reg.register_peer(4, _ctx(4))
	reg.set_spawned(4, true)
	reg.unregister_peer(4)
	assert_bool(reg.has_peer(4)).is_false()
	assert_bool(reg.is_spawned(4)).is_false()
	assert_int(reg.peer_count()).is_equal(0)

func test_get_player_stored() -> void:
	var reg = _new_reg()
	var p = auto_free(Node3D.new())
	reg.register_peer(5, _ctx(5), p)
	assert_int(reg.get_player(5).get_instance_id()).is_equal(p.get_instance_id())
