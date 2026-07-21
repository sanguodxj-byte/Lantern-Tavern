extends GdUnitTestSuite

## 测试词缀在 UI 中的显示（颜色名称、词缀详情行、品质标签）
## 以及 WeaponData 词缀工具方法的正确性

const POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")

# ============================================================================
# 1. WeaponData 词缀工具方法测试
# ============================================================================

func test_affix_quality_positive() -> void:
	assert_str(WeaponData.affix_quality("sharp")).is_equal("positive")
	assert_str(WeaponData.affix_quality("lightweight")).is_equal("positive")
	assert_str(WeaponData.affix_quality("focused")).is_equal("positive")
	assert_str(WeaponData.affix_quality("furious")).is_equal("positive")
	assert_str(WeaponData.affix_quality("sturdy")).is_equal("positive")
	assert_str(WeaponData.affix_quality("blessed")).is_equal("positive")


func test_affix_quality_negative() -> void:
	assert_str(WeaponData.affix_quality("rusty")).is_equal("negative")
	assert_str(WeaponData.affix_quality("clunky")).is_equal("negative")
	assert_str(WeaponData.affix_quality("worn")).is_equal("negative")
	assert_str(WeaponData.affix_quality("inferior")).is_equal("negative")
	assert_str(WeaponData.affix_quality("cracked")).is_equal("negative")
	assert_str(WeaponData.affix_quality("dim")).is_equal("negative")


func test_affix_quality_unknown() -> void:
	assert_str(WeaponData.affix_quality("nonexistent")).is_equal("")


func test_affix_effect_description_sharp() -> void:
	var desc := WeaponData.affix_effect_description("sharp")
	assert_bool(desc.contains("10%")).is_true()
	assert_bool(desc.contains("暴击")).is_true()


func test_affix_effect_description_rusty() -> void:
	var desc := WeaponData.affix_effect_description("rusty")
	assert_bool(desc.contains("-15%")).is_true()


func test_affix_effect_description_unknown() -> void:
	assert_str(WeaponData.affix_effect_description("nonexistent")).is_empty()


func test_get_affix_color_no_affixes() -> void:
	var color := WeaponData.get_affix_color([])
	assert_float(color.r).is_equal_approx(1.0, 0.01)
	assert_float(color.g).is_equal_approx(1.0, 0.01)
	assert_float(color.b).is_equal_approx(1.0, 0.01)


func test_get_affix_color_positive_only() -> void:
	var color := WeaponData.get_affix_color(["sharp"])
	# 绿色：R 低、G 高、B 低
	assert_float(color.g).is_greater(color.r)
	assert_float(color.g).is_greater(color.b)


func test_get_affix_color_negative_only() -> void:
	var color := WeaponData.get_affix_color(["rusty"])
	# 红色：R 高、G 低、B 低
	assert_float(color.r).is_greater(color.g)
	assert_float(color.r).is_greater(color.b)


func test_get_affix_color_mixed() -> void:
	var color := WeaponData.get_affix_color(["sharp", "rusty"])
	# 银白色：R≈G≈B，且非纯白
	assert_float(color.r).is_equal_approx(color.g, 0.05)
	assert_float(color.g).is_equal_approx(color.b, 0.05)


func test_get_affix_quality_label_no_affixes() -> void:
	assert_str(WeaponData.get_affix_quality_label([])).is_empty()


func test_get_affix_quality_label_positive() -> void:
	var label := WeaponData.get_affix_quality_label(["sharp"])
	assert_bool(not label.is_empty()).is_true()


func test_get_affix_quality_label_negative() -> void:
	var label := WeaponData.get_affix_quality_label(["rusty"])
	assert_bool(not label.is_empty()).is_true()


func test_get_affix_quality_label_mixed() -> void:
	var label := WeaponData.get_affix_quality_label(["sharp", "rusty"])
	assert_bool(not label.is_empty()).is_true()
	# 权衡标签应该和正向/负向不同
	assert_str(label).is_not_equal(WeaponData.get_affix_quality_label(["sharp"]))
	assert_str(label).is_not_equal(WeaponData.get_affix_quality_label(["rusty"]))


func test_get_affix_detail_lines_no_affixes() -> void:
	var lines := WeaponData.get_affix_detail_lines([])
	assert_array(lines).has_size(0)


func test_get_affix_detail_lines_one_affix() -> void:
	var lines := WeaponData.get_affix_detail_lines(["sharp"])
	assert_array(lines).has_size(1)
	assert_bool(lines[0].contains("锋利的")).is_true()


func test_get_affix_detail_lines_two_affixes() -> void:
	var lines := WeaponData.get_affix_detail_lines(["sharp", "rusty"])
	assert_array(lines).has_size(2)
	assert_bool(lines[0].contains("锋利的")).is_true()
	assert_bool(lines[1].contains("生锈的")).is_true()


# ============================================================================
# 2. WeaponData.get_full_display_name() 词缀前缀测试
# ============================================================================

func test_get_full_display_name_with_affix() -> void:
	var wd := WeaponData.new()
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "青铜短剑"
	wd.affixes = ["sharp"]
	var name := wd.get_full_display_name()
	assert_bool(name.contains("青铜短剑")).is_true()
	assert_bool(name.contains("锋利的")).is_true()


func test_get_full_display_name_no_affix() -> void:
	var wd := WeaponData.new()
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "青铜短剑"
	var name := wd.get_full_display_name()
	assert_str(name).is_equal("青铜短剑")


func test_get_full_display_name_two_affixes() -> void:
	var wd := WeaponData.new()
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "精钢长剑"
	wd.affixes = ["sharp", "rusty"]
	var name := wd.get_full_display_name()
	assert_bool(name.contains("锋利的")).is_true()
	assert_bool(name.contains("生锈的")).is_true()
	assert_bool(name.contains("精钢长剑")).is_true()


# ============================================================================
# 3. EquipmentDetailPopup 词缀显示测试（通过 preload 脚本调用静态方法）
# ============================================================================

func test_detail_for_weapon_data_includes_affix_in_title() -> void:
	var wd := WeaponData.new()
	wd.id = "sword"
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "青铜短剑"
	wd.damage_min = 3
	wd.damage_max = 9
	wd.affixes = ["sharp"]
	wd.damage_mult = 1.1
	var detail: Dictionary = POPUP_SCRIPT.detail_for_weapon_data(wd)
	assert_bool(String(detail["title"]).contains("锋利的")).is_true()
	assert_bool(String(detail["title"]).contains("青铜短剑")).is_true()


func test_detail_for_weapon_data_includes_affix_lines() -> void:
	var wd := WeaponData.new()
	wd.id = "sword"
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "青铜短剑"
	wd.damage_min = 3
	wd.damage_max = 9
	wd.affixes = ["sharp", "rusty"]
	var detail: Dictionary = POPUP_SCRIPT.detail_for_weapon_data(wd)
	var lines: Array = detail["lines"]
	# 应包含品质标签行 + 2 个词缀效果行
	var has_quality_label := false
	var has_sharp_line := false
	var has_rusty_line := false
	for line in lines:
		var s := String(line)
		if s.contains("锋利的"):
			has_sharp_line = true
		if s.contains("生锈的"):
			has_rusty_line = true
		if s.begins_with("["):
			has_quality_label = true
	assert_bool(has_quality_label).is_true()
	assert_bool(has_sharp_line).is_true()
	assert_bool(has_rusty_line).is_true()


func test_detail_for_weapon_data_includes_affix_color() -> void:
	var wd := WeaponData.new()
	wd.id = "sword"
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "青铜短剑"
	wd.damage_min = 3
	wd.damage_max = 9
	wd.affixes = ["sharp"]
	var detail: Dictionary = POPUP_SCRIPT.detail_for_weapon_data(wd)
	assert_bool(detail.has("affix_color")).is_true()
	var color: Color = detail["affix_color"]
	# 正向词缀 → 绿色
	assert_float(color.g).is_greater(color.r)


func test_detail_for_weapon_data_no_affix_color_is_white() -> void:
	var wd := WeaponData.new()
	wd.id = "sword"
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "青铜短剑"
	wd.damage_min = 3
	wd.damage_max = 9
	var detail: Dictionary = POPUP_SCRIPT.detail_for_weapon_data(wd)
	assert_bool(detail.has("affix_color")).is_true()
	var color: Color = detail["affix_color"]
	assert_float(color.r).is_equal_approx(1.0, 0.01)
	assert_float(color.g).is_equal_approx(1.0, 0.01)
	assert_float(color.b).is_equal_approx(1.0, 0.01)


func test_detail_for_weapon_data_includes_crit_from_affix() -> void:
	var wd := WeaponData.new()
	wd.id = "sword"
	wd.name = "Sword"
	wd.name_zh = "短剑"
	wd.tier_name = "青铜短剑"
	wd.damage_min = 3
	wd.damage_max = 9
	wd.affixes = ["focused"]
	wd.crit_bonus_percent = 10.0
	var detail: Dictionary = POPUP_SCRIPT.detail_for_weapon_data(wd)
	var lines: Array = detail["lines"]
	var has_crit_line := false
	for line in lines:
		if String(line).contains("Crit"):
			has_crit_line = true
			break
	assert_bool(has_crit_line).is_true()
