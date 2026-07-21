extends GdUnitTestSuite

const DETAIL_POPUP := preload("res://scenes/ui/equipment_detail_popup.gd")
const RD := preload("res://globals/combat/rune_data.gd")

var _saved_locale := ""

func before() -> void:
	# 强制英文 locale，使以下对 detail 字典的断言与语言无关（详情字符串在构建期已本地化）
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")

func after() -> void:
	TranslationServer.set_locale(_saved_locale)

func test_detail_popup_builds_weapon_details() -> void:
	# 盾牌已取消概率格挡，详情只展示物理防御 + 耐久等（对齐 WeaponData 注释）
	var detail: Dictionary = DETAIL_POPUP.detail_for_equipment_id("shield")
	assert_str(detail.get("title", "")).is_not_empty()
	assert_str(detail.get("category", "")).is_equal("Shield")
	assert_array(detail.get("lines", [])).contains("Shield Def +1")
	assert_bool(_lines_contain(detail.get("lines", []), "Block")).is_false()


func test_detail_popup_can_show_and_hide() -> void:
	var popup: Control = auto_free(DETAIL_POPUP.new())
	add_child(popup)
	popup.show_for_equipment_id("shortsword", Vector2(20, 20))
	assert_bool(popup.visible).is_true()
	popup.hide_detail()
	assert_bool(popup.visible).is_false()


func test_detail_popup_is_text_only_without_images() -> void:
	var popup: Control = auto_free(DETAIL_POPUP.new())
	add_child(popup)
	popup.show_for_equipment_id("plate_armor", Vector2(20, 20))
	var image_nodes := popup.find_children("*", "TextureRect", true, false)
	assert_int(image_nodes.size()) \
		.override_failure_message("详情悬浮窗只允许显示文字，不应包含 TextureRect 图像节点") \
		.is_equal(0)


func test_detail_popup_uses_compact_text_bounds() -> void:
	var popup: Control = auto_free(DETAIL_POPUP.new())
	add_child(popup)
	popup.show_for_material_id("wild_glowcap", 99, Vector2(20, 20))
	assert_bool(popup.custom_minimum_size.x <= 280.0).is_true()
	assert_bool(popup.size.x <= 360.0) \
		.override_failure_message("详情悬浮窗宽度过大，会遮挡背包/场景画面") \
		.is_true()


func test_material_detail_uses_inventory_amount() -> void:
	var detail: Dictionary = DETAIL_POPUP.detail_for_material_id("wild_glowcap", 3)
	assert_str(detail.get("category", "")).is_equal("Material")
	assert_array(detail.get("lines", [])).contains("Qty x3")


func test_material_detail_localizes_brewing_material_name() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var detail: Dictionary = DETAIL_POPUP.detail_for_material_id("blackberry", 2)
	assert_str(detail.get("title", "")).is_equal("黑莓")
	# 数量行随 locale 本地化
	assert_bool(_lines_contain(detail.get("lines", []), "数量 x2") or _lines_contain(detail.get("lines", []), "Qty x2")).is_true()
	TranslationServer.set_locale(prev)


func test_material_detail_localizes_monster_drop_name() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var detail: Dictionary = DETAIL_POPUP.detail_for_material_id("soul_gem", 1)
	assert_str(detail.get("title", "")).is_equal("灵魂宝石")
	TranslationServer.set_locale(prev)


func test_rune_detail_uses_runic_name_and_pixel_icon_path() -> void:
	var detail: Dictionary = DETAIL_POPUP.detail_for_rune_id("ember", 2)
	assert_str(detail.get("title", "")).is_equal("ᛖᛗᛒᛖᚱ")
	assert_str(detail.get("category", "")).is_equal("Rune")
	assert_array(detail.get("lines", [])).contains("Qty x2")
	assert_str(detail.get("icon_path", "")).is_equal("res://assets/textures/icons/runes/ember.png")


func test_rune_icon_loads_pixel_png_within_128px() -> void:
	var tex: Texture2D = DETAIL_POPUP.icon_for_rune("ember")
	assert_object(tex).is_not_null()
	assert_bool(tex.get_width() <= 128 and tex.get_height() <= 128).is_true()
	var path: String = DETAIL_POPUP.rune_icon_path(String("ember"))
	assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(path))).is_true()


func test_soul_gem_ui_icon_has_no_purple_pixels() -> void:
	var tex: Texture2D = DETAIL_POPUP.icon_for_material("soul_gem")
	assert_object(tex).is_not_null()
	var image := tex.get_image()
	var purple_pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.01 and color.b > color.r + 0.12 and color.b > color.g + 0.08:
				purple_pixels += 1
	assert_int(purple_pixels).is_equal(0)


func test_all_rune_pixel_png_assets_exist_and_fit_128px() -> void:
	for rune_id in RD.get_all_rune_ids():
		var path: String = DETAIL_POPUP.rune_icon_path(String(rune_id))
		assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path(path))) \
			.override_failure_message("缺少符文像素图标: %s" % path) \
			.is_true()
		var image := Image.new()
		assert_int(image.load(path)).is_equal(OK)
		assert_bool(image.get_width() <= 128 and image.get_height() <= 128) \
			.override_failure_message("%s 超过 128px" % path) \
			.is_true()


func test_armor_detail_shows_move_speed_penalty() -> void:
	var detail: Dictionary = DETAIL_POPUP.detail_for_equipment_id("plate_armor")
	assert_str(detail.get("title", "")).is_equal("钢板半身铠")
	assert_array(detail.get("lines", [])).contains("Phys Def +10")
	assert_array(detail.get("lines", [])).contains("Move Spd -12%")


func test_weapon_detail_shows_all_runtime_combat_modifiers() -> void:
	var weapon := WeaponData.new()
	weapon.name_zh = "测试战矛"
	weapon.damage_min = 4
	weapon.damage_max = 11
	weapon.armor_pierce_percent = 18.0
	weapon.knockback_m = 2.5
	weapon.stun_sec = 1.25
	weapon.carry_weight_mult = 1.3
	weapon.is_broken = true
	var detail := DETAIL_POPUP.detail_for_weapon_data(weapon)
	var lines: Array = detail.get("lines", [])
	assert_array(lines).contains("Armor Pierce +18%")
	assert_array(lines).contains("Knockback +2.5m")
	assert_array(lines).contains("Stun +1.25s")
	assert_array(lines).contains("Carry Weight +30%")
	assert_array(lines).contains("Broken")


func test_weapon_detail_runtime_modifiers_localize_to_chinese() -> void:
	var weapon := WeaponData.new()
	weapon.armor_pierce_percent = 18.0
	weapon.knockback_m = 2.5
	weapon.stun_sec = 1.25
	weapon.carry_weight_mult = 1.3
	weapon.is_broken = true
	TranslationServer.set_locale("zh")
	var lines: Array = DETAIL_POPUP.detail_for_weapon_data(weapon).get("lines", [])
	assert_bool(_lines_contain(lines, "护甲穿透 +18%")).is_true()
	assert_bool(_lines_contain(lines, "击退 +2.5米")).is_true()
	assert_bool(_lines_contain(lines, "已损坏")).is_true()


## 本地化正确性：同一份数据在不同 locale 下应使用对应语言的模板（验证详情悬浮窗真正走 tr()）
func test_detail_popup_lines_localize_by_locale() -> void:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var en_detail: Dictionary = DETAIL_POPUP.detail_for_equipment_id("shield")
	TranslationServer.set_locale("zh")
	var zh_detail: Dictionary = DETAIL_POPUP.detail_for_equipment_id("shield")
	TranslationServer.set_locale(prev)
	assert_bool(_lines_contain(en_detail.get("lines", []), "Shield Def")).is_true()
	assert_bool(_lines_contain(zh_detail.get("lines", []), "盾防")).is_true()


func _lines_contain(lines: Array, substr: String) -> bool:
	for line in lines:
		if substr in String(line):
			return true
	return false
