extends GdUnitTestSuite

# Phase 1（docs/25 §4.1/§16）：PlayerContext.for_peer() 为每个 peer 创建独立状态；
# 单机兼容桥 bind_to_globals() 仍返回有效上下文（指向全局单例）。

const AttrPanelClass := preload("res://globals/combat/attr_panel.gd")
const SkillRuntimeClass := preload("res://globals/combat/skill_runtime.gd")
const InventoryClass := preload("res://globals/core/state/expedition_inventory.gd")
const LoadoutClass := preload("res://globals/core/state/equipment_loadout.gd")
const PlayerContextClass := preload("res://globals/core/player_context.gd")

func _make_states() -> Array:
	var ap = auto_free(AttrPanelClass.new()); ap.init_defaults()
	var sk = auto_free(SkillRuntimeClass.new()); sk.init_defaults()
	var inv = auto_free(InventoryClass.new())
	var lo = auto_free(LoadoutClass.new())
	return [ap, sk, inv, lo]

func test_for_peer_creates_independent_contexts() -> void:
	var s1 = _make_states()
	var s2 = _make_states()
	var c1 = auto_free(PlayerContextClass.for_peer(s1[0], s1[1], s1[2], s1[3]))
	var c2 = auto_free(PlayerContextClass.for_peer(s2[0], s2[1], s2[2], s2[3]))
	# 注：gdUnit 的 assert_object.is_not_equal 对内容相同的对象做值比较，
	# 两个全新实例内容一致会被误判为"相等"。per-peer 隔离应比较实例身份。
	assert_int(c1.attributes.get_instance_id()).is_not_equal(c2.attributes.get_instance_id())
	assert_int(c1.skills.get_instance_id()).is_not_equal(c2.skills.get_instance_id())
	assert_int(c1.inventory.get_instance_id()).is_not_equal(c2.inventory.get_instance_id())
	assert_int(c1.loadout.get_instance_id()).is_not_equal(c2.loadout.get_instance_id())

func test_for_peer_context_isolated_mutation() -> void:
	var s1 = _make_states()
	var s2 = _make_states()
	var c1 = auto_free(PlayerContextClass.for_peer(s1[0], s1[1], s1[2], s1[3]))
	var c2 = auto_free(PlayerContextClass.for_peer(s2[0], s2[1], s2[2], s2[3]))
	c1.attributes.accumulate_attr("str", 200)
	assert_int(c1.attributes.get_attr("str")).is_greater(5)
	assert_int(c2.attributes.get_attr("str")).is_equal(5)

func test_for_peer_stores_player_node() -> void:
	var s = _make_states()
	var dummy = auto_free(Node3D.new())
	var c = auto_free(PlayerContextClass.for_peer(s[0], s[1], s[2], s[3], dummy))
	assert_object(c.player_node).is_equal(dummy)

func test_bind_to_globals_returns_valid_context() -> void:
	# 单机兼容：bind_to_globals 返回非空上下文，且 attributes 指向全局 AttrPanel
	var c = PlayerContextClass.bind_to_globals()
	assert_object(c).is_not_null()
	assert_object(c.attributes).is_equal(AttrPanel)
	assert_object(c.skills).is_equal(SkillRuntime)

func test_context_aggregates_state() -> void:
	var s = _make_states()
	var c = auto_free(PlayerContextClass.for_peer(s[0], s[1], s[2], s[3]))
	assert_int(c.attributes.get_attr("per")).is_equal(5)
	assert_int(c.skills.get_slot_type(c.skills.SLOT_F_ACTION)).is_equal(c.skills.SlotType.F_ACTION)
