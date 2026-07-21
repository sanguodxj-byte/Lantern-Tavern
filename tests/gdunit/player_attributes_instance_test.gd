extends GdUnitTestSuite

# Phase 1（docs/25 §4.1/§16）：验证 AttrPanel 可脱离场景树独立实例化，
# 且多个实例之间状态互不干扰（per-peer 隔离）。

const AttrPanelClass := preload("res://globals/combat/attr_panel.gd")

var _ap

func before() -> void:
	_ap = auto_free(AttrPanelClass.new())

func test_new_without_tree_has_defaults() -> void:
	# 不加入场景树，.new() 即应拥有完整默认状态
	assert_int(_ap.get_attr("str")).is_equal(5)
	assert_int(_ap.get_level()).is_equal(1)

func test_init_defaults_is_safe_and_idempotent() -> void:
	# 全新实例默认 str=5
	assert_int(_ap.get_attr("str")).is_equal(5)
	# init_defaults 不应改变已有默认值，且多次调用幂等
	_ap.init_defaults()
	_ap.init_defaults()
	assert_int(_ap.get_attr("str")).is_equal(5)
	# 注入已升级进度后，init_defaults 仅补默认键、不回退已有进度
	_ap.attrs["str"] = 12
	_ap.init_defaults()
	assert_int(_ap.get_attr("str")).is_equal(12)
	# 累积经验不应被 init_defaults 清空
	_ap.accumulate_attr("str", 1)
	_ap.init_defaults()
	assert_int(int(_ap.attr_exp["str"])).is_greater(0)

func test_two_instances_are_independent() -> void:
	var ap1 = auto_free(AttrPanelClass.new())
	var ap2 = auto_free(AttrPanelClass.new())
	# 直接修改 ap1 的内部状态，验证 ap2 不受影响（per-peer 隔离）
	ap1.attrs["str"] = 99
	assert_int(ap1.get_attr("str")).is_equal(99)
	assert_int(ap2.get_attr("str")).is_equal(5)
	ap2.attrs["mag"] = 77
	assert_int(ap2.get_attr("mag")).is_equal(77)
	assert_int(ap1.get_attr("mag")).is_equal(5)

func test_serialize_deserialize_does_not_mutate_source() -> void:
	_ap.accumulate_attr("dex", 50)
	var dex_before: int = _ap.get_attr("dex")
	var data = _ap.serialize()
	var ap2 = auto_free(AttrPanelClass.new())
	ap2.deserialize(data)
	assert_int(ap2.get_attr("dex")).is_equal(dex_before)
	# 反序列化后修改副本不应影响源
	ap2.accumulate_attr("dex", 50)
	assert_int(_ap.get_attr("dex")).is_equal(dex_before)
