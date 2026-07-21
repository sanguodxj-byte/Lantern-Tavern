extends GdUnitTestSuite

# Phase 1（docs/25 §4.1/§16）：SkillRuntime 经 init_defaults() 解耦 _ready，
# 可 .new() 独立使用；多实例状态隔离。

const SkillRuntimeClass := preload("res://globals/combat/skill_runtime.gd")

var _sr

func before() -> void:
	_sr = auto_free(SkillRuntimeClass.new())
	_sr.init_defaults()

func test_new_without_tree_then_init_defaults_binds_f_slot() -> void:
	# 独立实例（未入树）调用 init_defaults 后应绑定默认 F 槽"踢击"
	assert_str(_sr.get_slot_skill(_sr.SLOT_F_ACTION)).is_equal("踢击")

func test_init_defaults_is_idempotent() -> void:
	_sr.init_defaults()
	assert_str(_sr.get_slot_skill(_sr.SLOT_F_ACTION)).is_equal("踢击")
	_sr.unbind_slot(_sr.SLOT_F_ACTION)
	assert_str(_sr.get_slot_skill(_sr.SLOT_F_ACTION)).is_equal("")
	_sr.init_defaults()
	assert_str(_sr.get_slot_skill(_sr.SLOT_F_ACTION)).is_equal("踢击")

func test_two_instances_are_independent() -> void:
	var sr1 = auto_free(SkillRuntimeClass.new()); sr1.init_defaults()
	var sr2 = auto_free(SkillRuntimeClass.new()); sr2.init_defaults()
	sr1.bind_skill(sr1.SLOT_G_WEAPON, "冲撞")
	assert_str(sr1.get_slot_skill(sr1.SLOT_G_WEAPON)).is_equal("冲撞")
	assert_str(sr2.get_slot_skill(sr2.SLOT_G_WEAPON)).is_equal("")

func test_serialize_deserialize_roundtrip() -> void:
	_sr.bind_skill(_sr.SLOT_G_WEAPON, "冲撞")
	var data = _sr.serialize()
	var sr2 = auto_free(SkillRuntimeClass.new())
	sr2.deserialize(data)
	assert_str(sr2.get_slot_skill(sr2.SLOT_G_WEAPON)).is_equal("冲撞")

func test_mechanism_passives_independent() -> void:
	_sr.grant_mechanism_passive("charge", 1)
	var sr2 = auto_free(SkillRuntimeClass.new()); sr2.init_defaults()
	assert_bool(sr2.has_mechanism_passive("charge")).is_false()
