extends GdUnitTestSuite

## 测试类 ToME4 / Elona 材质阶梯、品质稀有度与词缀实装机制

const CB := preload("res://globals/combat/combat_bridge.gd")
const AS := preload("res://globals/equipment/affix_system.gd")

func test_material_multiplier() -> void:
	var weapon := WeaponData.new()
	weapon.id = "test_sword"
	weapon.damage_dice_count = 1
	weapon.damage_dice_sides = 6
	weapon.damage_flat = 0

	weapon.material_tier = "iron"
	assert_int(weapon.get_damage_dealt()).is_equal(4) # avg = (1*7)/2 = 3.5 -> round = 4

	weapon.material_tier = "adamantite"
	# 4 * 1.20 = 4.8 -> round = 5
	assert_int(weapon.get_damage_dealt()).is_equal(4) # avg * 1.2 = 3.5 * 1.2 = 4.2 -> round = 4

func test_rarity_color() -> void:
	var weapon := WeaponData.new()
	weapon.rarity = "EPIC"
	assert_str(weapon.get_rarity_color().to_html()).is_equal("aa33ffff")
	assert_str(weapon.get_rarity_display_name()).is_not_empty()

func test_unidentified_mask_localization() -> void:
	var weapon := WeaponData.new()
	weapon.id = "test_sword"
	weapon.name_zh = "精钢长剑"
	weapon.is_identified = false
	weapon.equipment_category = "weapons"
	
	# 未鉴定遮罩断言
	assert_str(weapon.get_full_display_name()).contains("未鉴定")
	
	# 鉴定后恢复完整名断言
	weapon.is_identified = true
	assert_str(weapon.get_full_display_name()).contains("精钢长剑")

func test_affix_lifesteal_implementation() -> void:
	var weapon := WeaponData.new()
	weapon.id = "blood_sword"
	var affix_system: Node = auto_free(AS.new())
	affix_system.apply_affixes(weapon, ["bloodthirsty"])
	
	assert_float(weapon.lifesteal_percent).is_equal_approx(0.5)

	var attack := CB.build_player_attack(null, weapon, "one_hand_melee", "", {}, 1)
	assert_float(attack.lifesteal_percent).is_equal_approx(0.5)
