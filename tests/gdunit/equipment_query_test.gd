extends GdUnitTestSuite
## EquipmentComponent 新增装备查询方法单元测试
## 验证从 player.gd 下沉到 EquipmentComponent 的查询逻辑

const CB_LIB := preload("res://globals/combat/combat_bridge.gd")

# ============================================================================
# 1. get_active_weapon_data
# ============================================================================

func test_get_active_weapon_data_returns_weapon_when_equipped() -> void:
	var eq := _make_equipment_with_weapon("Sword", "one_hand_melee", "melee", "one_hand")
	assert_object(eq.get_active_weapon_data()).is_not_null()
	assert_str(eq.get_active_weapon_data().name).is_equal("Sword")
	eq.free()

func test_get_active_weapon_data_returns_null_when_empty() -> void:
	var eq := _make_empty_equipment()
	assert_object(eq.get_active_weapon_data()).is_null()
	eq.free()

# ============================================================================
# 2. is_active_weapon_ranged
# ============================================================================

func test_is_active_weapon_ranged_true_for_bow() -> void:
	var eq := _make_equipment_with_weapon("Longbow", "longbow", "ranged", "two_hand")
	assert_bool(eq.is_active_weapon_ranged()).is_true()
	eq.free()

func test_is_active_weapon_ranged_false_for_sword() -> void:
	var eq := _make_equipment_with_weapon("Sword", "one_hand_melee", "melee", "one_hand")
	assert_bool(eq.is_active_weapon_ranged()).is_false()
	eq.free()

func test_is_active_weapon_ranged_false_when_empty() -> void:
	var eq := _make_empty_equipment()
	assert_bool(eq.is_active_weapon_ranged()).is_false()
	eq.free()

# ============================================================================
# 3. is_active_weapon_two_handed
# ============================================================================

func test_is_two_handed_true_for_greatsword() -> void:
	var eq := _make_equipment_with_weapon("Greatsword", "two_hand", "melee", "two_hand")
	assert_bool(eq.is_active_weapon_two_handed()).is_true()
	eq.free()

func test_is_two_handed_true_for_longbow() -> void:
	var eq := _make_equipment_with_weapon("Longbow", "longbow", "ranged", "two_hand")
	assert_bool(eq.is_active_weapon_two_handed()).is_true()
	eq.free()

func test_is_two_handed_false_for_dagger() -> void:
	var eq := _make_equipment_with_weapon("Dagger", "one_hand_melee", "melee", "one_hand")
	assert_bool(eq.is_active_weapon_two_handed()).is_false()
	eq.free()

func test_is_two_handed_false_when_empty() -> void:
	var eq := _make_empty_equipment()
	assert_bool(eq.is_active_weapon_two_handed()).is_false()
	eq.free()

# ============================================================================
# 4. can_block
# ============================================================================

func test_can_block_true_with_shield() -> void:
	var eq := _make_equipment_with_shield("Buckler")
	assert_bool(eq.can_block()).is_true()
	eq.free()

func test_can_block_true_with_two_handed() -> void:
	var eq := _make_equipment_with_weapon("Greatsword", "two_hand", "melee", "two_hand")
	assert_bool(eq.can_block()).is_true()
	eq.free()

func test_can_block_false_with_ranged() -> void:
	var eq := _make_equipment_with_weapon("Longbow", "longbow", "ranged", "two_hand")
	assert_bool(eq.can_block()).is_false()
	eq.free()

func test_can_block_false_with_one_hand_no_shield() -> void:
	var eq := _make_equipment_with_weapon("Dagger", "one_hand_melee", "melee", "one_hand")
	assert_bool(eq.can_block()).is_false()
	eq.free()

# ============================================================================
# 5. can_dual_wield
# ============================================================================

func test_can_dual_wield_true_for_dagger() -> void:
	var eq := _make_equipment_with_weapon("Dagger", "one_hand_melee", "melee", "one_hand")
	assert_bool(eq.can_dual_wield()).is_true()
	eq.free()

func test_can_dual_wield_false_for_two_handed() -> void:
	var eq := _make_equipment_with_weapon("Greatsword", "two_hand", "melee", "two_hand")
	assert_bool(eq.can_dual_wield()).is_false()
	eq.free()

func test_can_dual_wield_false_for_ranged() -> void:
	var eq := _make_equipment_with_weapon("Longbow", "longbow", "ranged", "two_hand")
	assert_bool(eq.can_dual_wield()).is_false()
	eq.free()

func test_can_dual_wield_false_with_shield() -> void:
	var eq := _make_equipment_with_shield("Buckler")
	# Shield weapon can block, so dual wield is false
	assert_bool(eq.can_dual_wield()).is_false()
	eq.free()

# ============================================================================
# 6. player.gd 薄代理验证
# ============================================================================

func test_player_delegates_equipment_queries() -> void:
	var source := _source("res://scenes/characters/player/player.gd")
	# 验证 player.gd 中的方法是薄代理
	assert_bool(source.contains("equipment.has_hand_equipment()")).is_true()
	assert_bool(source.contains("equipment.get_active_weapon_data()")).is_true()
	assert_bool(source.contains("equipment.is_active_weapon_ranged()")).is_true()
	assert_bool(source.contains("equipment.is_active_weapon_two_handed()")).is_true()
	assert_bool(source.contains("equipment.can_block()")).is_true()
	assert_bool(source.contains("equipment.can_dual_wield()")).is_true()

func test_equipment_component_has_query_methods() -> void:
	var source := _source("res://scenes/characters/component/equipment_component.gd")
	assert_bool(source.contains("func get_active_weapon_data")).is_true()
	assert_bool(source.contains("func get_active_weapon_attack_type")).is_true()
	assert_bool(source.contains("func is_active_weapon_ranged")).is_true()
	assert_bool(source.contains("func is_active_weapon_two_handed")).is_true()
	assert_bool(source.contains("func can_block")).is_true()
	assert_bool(source.contains("func can_dual_wield")).is_true()

# ============================================================================
# 辅助
# ============================================================================

func _make_empty_equipment() -> EquipmentComponent:
	var eq := EquipmentComponent.new()
	eq.weapon_placeholder = Node3D.new()
	eq.weapon_reach_raycast = RayCast3D.new()
	eq.weapon_spawn_position = Node3D.new()
	eq.add_child(eq.weapon_placeholder)
	eq.add_child(eq.weapon_reach_raycast)
	eq.add_child(eq.weapon_spawn_position)
	return eq

func _make_equipment_with_weapon(label: String, weapon_class: String, attack_type: String, hands: String) -> EquipmentComponent:
	var eq := _make_empty_equipment()
	var data := _make_weapon(label, weapon_class, attack_type, hands)
	eq.equip_weapon(data)
	return eq

func _make_equipment_with_shield(label: String) -> EquipmentComponent:
	var eq := _make_empty_equipment()
	var data := _make_weapon(label, "shield", "shield", "off_hand")
	data.item_tag = "shield"
	data.equipment_category = "shields"
	data.shield_phys_def = 1
	data.reach = 1.0
	eq.equip_weapon(data)
	return eq

func _make_weapon(label: String, weapon_class: String, attack_type: String, hands: String) -> WeaponData:
	var data := WeaponData.new()
	data.id = label.to_lower().replace(" ", "_")
	data.name = label
	data.item_tag = "weapon"
	data.equipment_category = "weapons"
	data.weapon_class = weapon_class
	data.attack_type = attack_type
	data.hands = hands
	data.condition = 10
	data.max_condition = 10
	data.damage_min = 1
	data.damage_max = 3
	data.damage_dice_count = 1
	data.damage_dice_sides = 4
	data.reach = 2.0
	return data

static func _source(path: String) -> String:
	var script := load(path) as GDScript
	return script.source_code
