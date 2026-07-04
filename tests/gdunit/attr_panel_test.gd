extends GdUnitTestSuite

# AttrPanel 属性面板系统测试：属性、经验、里程碑、技能领悟

var _ap

func before() -> void:
	# auto_free 实例 new() 时 attrs 已初始化为全 5；不调 reset() 避免钩子内异常中断套件
	_ap = auto_free(load("res://globals/attr_panel.gd").new())


func test_initial_attrs_all_5() -> void:
	for key in ["str", "dex", "mag", "con", "agi", "per"]:
		assert_int(_ap.get_attr(key)).is_equal(5)


func test_initial_level_1() -> void:
	assert_int(_ap.get_level()).is_equal(1)


func test_get_player_attrs_returns_dict() -> void:
	var d = _ap.get_player_attrs()
	assert_bool(d is Dictionary).is_true()
	assert_int(d.size()).is_equal(6)


func test_accumulate_attr_adds_exp() -> void:
	_ap.accumulate_attr("str", 10)
	assert_int(_ap.attr_exp["str"]).is_equal(10)


func test_accumulate_attr_levels_up_at_threshold() -> void:
	# CE 升级门槛是 100
	for i in range(10):
		_ap.accumulate_attr("str", 10)
	assert_int(_ap.get_attr("str")).is_equal(6)


func test_accumulate_attr_wrong_key_returns_false() -> void:
	var ok = _ap.accumulate_attr("invalid", 10)
	assert_bool(ok).is_false()


func test_accumulate_proficiency_adds_exp() -> void:
	_ap.accumulate_proficiency("one_hand_melee", 15)
	assert_int(_ap.get_proficiency("one_hand_melee")).is_equal(15)


func test_accumulate_level_exp_levels_up() -> void:
	_ap.accumulate_level_exp(150)
	assert_int(_ap.get_level()).is_greater_equal(2)


func test_compute_max_hp_base() -> void:
	_ap.reset()
	var hp = _ap.compute_max_hp()
	# 100 + 体质5*10 + 等级1*5 = 155
	assert_int(hp).is_equal(155)


func test_compute_max_hp_with_milestone() -> void:
	# 里程碑"强健体魄" +20HP，但默认未解锁
	var hp_before = _ap.compute_max_hp()
	_ap.unlocked_milestones.append("强健体魄")
	var hp_after = _ap.compute_max_hp()
	assert_int(hp_after).is_equal(hp_before + 20)


func test_compute_carry_weight() -> void:
	_ap.reset()
	# 50 + 体质5*2 = 60
	assert_int(_ap.compute_carry_weight()).is_equal(60)


func test_compute_evade_rate() -> void:
	_ap.reset()
	# 灵巧5*1% = 5%
	assert_float(_ap.compute_evade_rate()).is_equal(5.0)


func test_check_skill_unlocks_empty_initially() -> void:
	_ap.reset()
	var unlocked = _ap.check_skill_unlocks()
	# 初始属性5，不足以解锁任何技能（门槛最低 T1 需15）
	assert_bool(unlocked.is_empty()).is_true()


func test_serialize_deserialize() -> void:
	_ap.accumulate_attr("dex", 30)
	_ap.accumulate_proficiency("bow", 20)
	_ap.accumulate_level_exp(50)
	var data = _ap.serialize()

	var ap2 = auto_free(load("res://globals/attr_panel.gd").new())
	ap2.deserialize(data)
	assert_int(ap2.get_attr("dex")).is_equal(_ap.get_attr("dex"))
	assert_int(ap2.get_proficiency("bow")).is_equal(20)
	assert_int(ap2.get_level()).is_equal(_ap.get_level())


func test_reset_clears_all() -> void:
	_ap.accumulate_attr("str", 100)
	_ap.accumulate_proficiency("two_hand", 50)
	_ap.reset()
	assert_int(_ap.get_attr("str")).is_equal(5)
	assert_int(_ap.get_proficiency("two_hand")).is_equal(0)
	assert_int(_ap.get_level()).is_equal(1)


func test_has_milestone() -> void:
	assert_bool(_ap.has_milestone("nonexistent")).is_false()
	_ap.unlocked_milestones.append("强健体魄")
	assert_bool(_ap.has_milestone("强健体魄")).is_true()


func test_get_milestone_returns_empty_if_not_unlocked() -> void:
	var ms = _ap.get_milestone("str", 1)
	assert_bool(ms.is_empty()).is_true()
