extends GdUnitTestSuite

# ExpeditionInventory 模块的单元测试
const ExpeditionInventory = preload("res://globals/core/state/expedition_inventory.gd")

func test_equipment_instance_preserves_rolled_affixes_for_inventory_detail() -> void:
	var inv = ExpeditionInventory.new()
	var rolled := WeaponData.new()
	rolled.id = "shortsword"
	rolled.affixes = ["sharp", "rusty"]
	rolled.tier_index = 2
	rolled.condition = 345
	assert_bool(inv.add_equipment_instance(rolled)).is_true()
	var stored: WeaponData = inv.get_equipment_instance("shortsword")
	assert_object(stored).is_not_null()
	assert_array(stored.affixes).contains("sharp")
	assert_array(stored.affixes).contains("rusty")
	assert_int(stored.tier_index).is_equal(2)
	assert_int(stored.condition).is_equal(345)


func test_add_and_remove_material() -> void:
	var inv = ExpeditionInventory.new()
	inv.space_limit = 10
	
	# 正常添加
	assert_bool(inv.add_material("rat_tail", 3)).is_true()
	assert_int(inv.get_space_used()).is_equal(3)
	assert_int(inv.get_space_free()).is_equal(7)
	assert_int(inv.materials.get("rat_tail", 0)).is_equal(3)
	
	# 累加
	assert_bool(inv.add_material("rat_tail", 2)).is_true()
	assert_int(inv.materials.get("rat_tail", 0)).is_equal(5)
	
	# 正常移除一部分
	assert_bool(inv.remove_material("rat_tail", 2)).is_true()
	assert_int(inv.materials.get("rat_tail", 0)).is_equal(3)
	
	# 移除完全部（清除 key）
	assert_bool(inv.remove_material("rat_tail", 3)).is_true()
	assert_bool(inv.materials.has("rat_tail")).is_false()
	assert_int(inv.get_space_used()).is_equal(0)

func test_invalid_arguments() -> void:
	var inv = ExpeditionInventory.new()
	
	# 空 ID 校验
	assert_bool(inv.add_material("", 5)).is_false()
	assert_bool(inv.add_rune("", 5)).is_false()
	assert_bool(inv.add_equipment("", 5)).is_false()
	
	# 非法数量校验 (<= 0)
	assert_bool(inv.add_material("rat_tail", 0)).is_false()
	assert_bool(inv.add_material("rat_tail", -1)).is_false()
	assert_bool(inv.remove_material("rat_tail", 0)).is_false()
	assert_bool(inv.remove_material("rat_tail", -5)).is_false()

func test_space_limit_constraints() -> void:
	var inv = ExpeditionInventory.new()
	inv.space_limit = 5
	
	# 正常添加不超过上限
	assert_bool(inv.add_material("blackberry", 3)).is_true()
	assert_bool(inv.add_rune("fire_rune", 2)).is_true()
	assert_int(inv.get_space_used()).is_equal(5)
	assert_int(inv.get_space_free()).is_equal(0)
	
	# 超过上限添加失败
	assert_bool(inv.add_material("rat_tail", 1)).is_false()
	assert_bool(inv.add_equipment("iron_sword", 1)).is_false()
	
	# 移出后又能继续添加
	assert_bool(inv.remove_rune("fire_rune", 1)).is_true()
	assert_bool(inv.add_equipment("iron_sword", 1)).is_true()
	assert_int(inv.get_space_used()).is_equal(5)

func test_remove_nonexistent_item() -> void:
	var inv = ExpeditionInventory.new()
	
	# 移除不存在的物品
	assert_bool(inv.remove_material("nonexistent", 1)).is_false()
	assert_bool(inv.remove_rune("nonexistent", 1)).is_false()
	assert_bool(inv.remove_equipment("nonexistent", 1)).is_false()
	
	# 移除超过现有数量的物品
	assert_bool(inv.add_material("rat_tail", 2)).is_true()
	assert_bool(inv.remove_material("rat_tail", 3)).is_false()
	assert_int(inv.materials.get("rat_tail", 0)).is_equal(2)

func test_serialization_and_deserialization() -> void:
	var inv = ExpeditionInventory.new()
	inv.space_limit = 15
	inv.add_material("rat_tail", 3)
	inv.add_rune("light_rune", 1)
	inv.add_equipment("wooden_shield", 2)
	
	var data = inv.to_dict()
	
	# 校验序列化字典
	assert_dict(data).is_not_empty()
	assert_int(data["space_limit"]).is_equal(15)
	assert_int(data["materials"]["rat_tail"]).is_equal(3)
	assert_int(data["runes"]["light_rune"]).is_equal(1)
	assert_int(data["equipment"]["wooden_shield"]).is_equal(2)
	
	# 反序列化回填
	var another_inv = ExpeditionInventory.new()
	another_inv.from_dict(data)
	
	assert_int(another_inv.space_limit).is_equal(15)
	assert_int(another_inv.get_space_used()).is_equal(6)
	assert_int(another_inv.materials.get("rat_tail", 0)).is_equal(3)
	assert_int(another_inv.runes.get("light_rune", 0)).is_equal(1)
	assert_int(another_inv.equipment.get("wooden_shield", 0)).is_equal(2)

func test_clear_all_items() -> void:
	var inv = ExpeditionInventory.new()
	inv.add_material("rat_tail", 2)
	inv.add_rune("fire_rune", 1)
	inv.add_equipment("iron_sword", 1)
	
	assert_int(inv.get_space_used()).is_equal(4)
	
	inv.clear()
	
	assert_int(inv.get_space_used()).is_equal(0)
	assert_bool(inv.materials.is_empty()).is_true()
	assert_bool(inv.runes.is_empty()).is_true()
	assert_bool(inv.equipment.is_empty()).is_true()
