extends GdUnitTestSuite

# EquipmentLoadout 模块的单元测试
const EquipmentLoadout = preload("res://globals/core/state/equipment_loadout.gd")

func test_weapon_slots() -> void:
	var loadout = EquipmentLoadout.new()
	
	# 初始化全空
	for i in range(4):
		assert_str(loadout.get_weapon_slot(i)).is_empty()
		
	# 正常设置
	assert_bool(loadout.set_weapon_slot(0, "iron_sword")).is_true()
	assert_bool(loadout.set_weapon_slot(3, "wooden_shield")).is_true()
	assert_str(loadout.get_weapon_slot(0)).is_equal("iron_sword")
	assert_str(loadout.get_weapon_slot(3)).is_equal("wooden_shield")
	
	# 边界检查
	assert_bool(loadout.set_weapon_slot(-1, "sword")).is_false()
	assert_bool(loadout.set_weapon_slot(4, "sword")).is_false()
	assert_str(loadout.get_weapon_slot(-1)).is_empty()
	assert_str(loadout.get_weapon_slot(4)).is_empty()

func test_armor_slots() -> void:
	var loadout = EquipmentLoadout.new()
	
	# 初始化全空
	assert_str(loadout.get_armor_slot("head")).is_empty()
	assert_str(loadout.get_armor_slot("body")).is_empty()
	
	# 正常设置
	assert_bool(loadout.set_armor_slot("head", "iron_helmet")).is_true()
	assert_bool(loadout.set_armor_slot("body", "leather_armor")).is_true()
	assert_str(loadout.get_armor_slot("head")).is_equal("iron_helmet")
	assert_str(loadout.get_armor_slot("body")).is_equal("leather_armor")
	
	# 边界与非法槽名检查
	assert_bool(loadout.set_armor_slot("invalid_slot", "shield")).is_false()
	assert_str(loadout.get_armor_slot("invalid_slot")).is_empty()

func test_active_weapon_slot() -> void:
	var loadout = EquipmentLoadout.new()
	
	# 默认激活为 0
	assert_int(loadout.active_weapon_slot).is_equal(0)
	
	# 正常设置
	assert_bool(loadout.set_active_weapon_slot(2)).is_true()
	assert_int(loadout.active_weapon_slot).is_equal(2)
	
	# 越界检查
	assert_bool(loadout.set_active_weapon_slot(-1)).is_false()
	assert_bool(loadout.set_active_weapon_slot(4)).is_false()
	assert_int(loadout.active_weapon_slot).is_equal(2)

func test_serialization_and_deserialization() -> void:
	var loadout = EquipmentLoadout.new()
	loadout.set_weapon_slot(1, "greatsword")
	loadout.set_armor_slot("feet", "leather_boots")
	loadout.set_active_weapon_slot(1)
	
	var data = loadout.to_dict()
	
	# 校验序列化字典
	assert_dict(data).is_not_empty()
	assert_str(data["weapon_slots"][1]).is_equal("greatsword")
	assert_str(data["armor_slots"]["feet"]).is_equal("leather_boots")
	assert_int(data["active_weapon_slot"]).is_equal(1)
	
	# 反序列化
	var another = EquipmentLoadout.new()
	another.from_dict(data)
	
	assert_str(another.get_weapon_slot(1)).is_equal("greatsword")
	assert_str(another.get_armor_slot("feet")).is_equal("leather_boots")
	assert_int(another.active_weapon_slot).is_equal(1)
	assert_str(another.get_weapon_slot(0)).is_empty()
	assert_str(another.get_armor_slot("head")).is_empty()
