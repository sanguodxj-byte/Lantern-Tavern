extends GdUnitTestSuite

## 测试装备真实掉落、Zone 深度阶位锁与丰富词缀系统

const LT := preload("res://globals/tavern/loot_table.gd")
const AS := preload("res://globals/equipment/affix_system.gd")

func test_zone_0_tier_lock() -> void:
	# 验证在 Zone 0 (地牢一层) 抽取的 100 件装备，其 tier_index 绝对只能是 0 (一阶)
	var loot_table: Node = auto_free(LT.new())
	for i in range(100):
		var loot: Dictionary = loot_table.roll_weapon(0)
		if not loot.is_empty():
			assert_int(int(loot.get("tier_index", -1))).is_equal(0)

func test_affix_system_expanded_pool() -> void:
	# 验证扩充词缀库包含新的元素/状态词缀
	assert_bool(AS.POSITIVE_AFFIXES.has("flamereached")).is_true()
	assert_bool(AS.POSITIVE_AFFIXES.has("bloodthirsty")).is_true()
	assert_bool(AS.NEGATIVE_AFFIXES.has("cursed_vampiric")).is_true()
	assert_bool(AS.SUFFIXES.has("of_slaying")).is_true()

func test_affix_application() -> void:
	var weapon_data := WeaponData.new()
	weapon_data.id = "test_sword"
	weapon_data.name = "测试长剑"
	weapon_data.damage_flat = 10
	weapon_data.damage_mult = 1.0

	var affix_system: Node = auto_free(AS.new())
	affix_system.apply_affixes(weapon_data, ["flamereached"])
	
	assert_float(weapon_data.damage_mult).is_equal_approx(1.04)
