extends GdUnitTestSuite

const THEME_PATH := "res://scenes/ui/lantern_theme.tres"
const PIXEL_UI_SCENES := [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/tavern_ui.tscn",
	"res://scenes/ui/character_panel.tscn",
	"res://scenes/ui/tavern_equipment_panel.tscn",
	"res://scenes/ui/skill_bar.tscn",
	"res://scenes/ui/combat_hud.tscn",
	"res://scenes/ui/expedition_hud.tscn",
]


func test_shared_theme_has_pixel_roguelike_variations() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_object(theme).is_not_null()
	for variation in ["ScreenTitle", "SectionTitle", "MutedLabel", "CrystalLabel", "PrimaryButton", "SlotButton", "HUDPanel"]:
		assert_bool(theme.get_type_variation_base(variation) != &"") \
			.override_failure_message("缺少统一 UI 变体：%s" % variation).is_true()

	var button_style := theme.get_stylebox("normal", "Button") as StyleBoxFlat
	assert_object(button_style).is_not_null()
	assert_bool(button_style.anti_aliasing).is_false()
	assert_int(button_style.border_width_left).is_greater_equal(2)
	assert_int(button_style.shadow_size).is_greater_equal(3)

	var label_color := theme.get_color("font_color", "Label")
	assert_float(label_color.get_luminance()).is_greater(0.62)


func test_ui_theme_purple_accents_are_neutral_gray() -> void:
	var theme := load(THEME_PATH) as Theme
	var styleboxes := [
		theme.get_stylebox("pressed", "Button"),
		theme.get_stylebox("focus", "Button"),
		theme.get_stylebox("hover", "SlotButton"),
		theme.get_stylebox("pressed", "SlotButton"),
		theme.get_stylebox("selected", "ItemList"),
		theme.get_stylebox("tab_fg", "TabContainer"),
		theme.get_stylebox("pressed", "CheckButton"),
		theme.get_stylebox("grabber_highlight", "HSlider"),
		theme.get_stylebox("grabber_highlight", "ScrollBar"),
		theme.get_stylebox("panel", "PopupPanel"),
	]
	for style in styleboxes:
		assert_object(style).is_not_null()
		var flat := style as StyleBoxFlat
		assert_object(flat).is_not_null()
		assert_bool(_is_neutral_gray(flat.bg_color)).is_true()

	var border_styleboxes := [
		theme.get_stylebox("pressed", "Button"),
		theme.get_stylebox("focus", "Button"),
		theme.get_stylebox("hover", "SlotButton"),
		theme.get_stylebox("selected", "ItemList"),
		theme.get_stylebox("tab_fg", "TabContainer"),
		theme.get_stylebox("pressed", "CheckButton"),
		theme.get_stylebox("grabber_highlight", "ScrollBar"),
		theme.get_stylebox("panel", "PopupPanel"),
	]
	for style in border_styleboxes:
		var flat := style as StyleBoxFlat
		assert_object(flat).is_not_null()
		assert_bool(_is_neutral_gray(flat.border_color)).is_true()

	for color in [
		theme.get_color("font_pressed_color", "Button"),
		theme.get_color("font_hovered_color", "TabContainer"),
		theme.get_color("font_color", "CrystalLabel"),
		theme.get_color("font_hover_color", "SlotButton"),
	]:
		assert_bool(_is_neutral_gray(color)).is_true()


func test_all_primary_ui_scenes_reference_shared_theme() -> void:
	for scene_path in PIXEL_UI_SCENES:
		var source := FileAccess.get_file_as_string(scene_path)
		assert_str(source).contains("res://scenes/ui/lantern_theme.tres")


func test_tavern_management_uses_readable_three_zone_layout() -> void:
	var ui := load("res://scenes/ui/tavern_ui.tscn").instantiate() as Control
	ui.size = Vector2(1920, 1080)
	add_child(ui)
	await await_idle_frame()

	var orders := ui.get_node("OrderPanel") as Control
	var inventory := ui.get_node("InventoryPanel") as Control
	var controls := ui.get_node("ControlPanel") as Control
	assert_float(orders.size.x).is_greater(1000.0)
	assert_float(inventory.size.x).is_greater(620.0)
	assert_float(orders.size.x).is_greater(inventory.size.x * 1.45)
	assert_float(orders.position.x).is_greater_equal(70.0)
	assert_float(controls.size.y).is_greater(90.0)
	assert_bool(absf(controls.position.x - orders.position.x) < 1.0).is_true()
	assert_float(inventory.position.x).is_greater(orders.position.x + orders.size.x)

	ui.queue_free()


func test_combat_hud_uses_large_pixel_readouts() -> void:
	var hud := load("res://scenes/ui/combat_hud.tscn").instantiate() as CombatHUD
	add_child(hud)
	await await_idle_frame()

	assert_float(hud.hp_bar.size.x).is_greater_equal(320.0)
	assert_float(hud.hp_bar.size.y).is_greater_equal(34.0)
	assert_int(hud.combat_log.line_height).is_greater_equal(20)
	assert_int(hud.combat_log.max_lines).is_equal(7)
	assert_bool(hud.combat_log.size.y >= 160.0 and hud.combat_log.size.y <= 180.0).is_true()
	assert_float(hud.hp_bar.global_position.x).is_greater_equal(20.0)
	assert_int(hud.time_label.get_theme_font_size("font_size")).is_greater_equal(20)

	hud.queue_free()


func test_inventory_and_skill_slots_share_pixel_variations() -> void:
	var character := load("res://scenes/ui/character_panel.tscn").instantiate() as Control
	add_child(character)
	await await_idle_frame()
	for slot_name in ["SlotHead", "SlotBody", "SlotHands", "SlotFeet", "SlotMainHand", "SlotOffHand", "SlotBack", "SlotRing"]:
		var slot := character.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipmentSlots/%s" % slot_name) as Button
		assert_str(String(slot.theme_type_variation)).is_equal("SlotButton")
	character.queue_free()

	var skill_bar := load("res://scenes/ui/skill_bar.tscn").instantiate() as Control
	add_child(skill_bar)
	await await_idle_frame()
	assert_object(skill_bar.get_node_or_null("Backdrop")).is_not_null()
	assert_str(String(skill_bar.get_node("Backdrop").theme_type_variation)).is_equal("HUDPanel")
	assert_bool(skill_bar.size.x >= 390.0 and skill_bar.size.x <= 420.0).is_true()
	assert_float(skill_bar.size.y).is_greater_equal(100.0)
	skill_bar.queue_free()


func test_equipment_screen_uses_pixel_slots_and_icon_grid() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var equipment := load("res://scenes/ui/tavern_equipment_panel.tscn").instantiate() as TavernEquipmentPanel
	host.add_child(equipment)
	equipment.visible = true
	await await_idle_frame()

	var left_column := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn") as Control
	var right_tabs := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs") as Control
	var equip_top := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipTop") as Control
	var bottom_info := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/BottomInfo") as Control
	var gear_list := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/物品/ItemsBox/GearList") as ItemList
	var filter_bar := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/物品/ItemsBox/FilterBar") as HBoxContainer
	var detail_panel := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/物品/ItemsBox/ItemDetailPanel") as PanelContainer
	assert_int(filter_bar.get_child_count()).is_equal(7)
	assert_bool(filter_bar.visible).is_true()
	assert_bool((equipment.get_node("%FilterAll") as Button).button_pressed).is_true()
	assert_bool(detail_panel.visible).is_true()
	assert_float(detail_panel.custom_minimum_size.y).is_greater_equal(180.0)
	assert_str((equipment.get_node("%ItemDetailTitle") as Label).text).is_equal("选择物品")
	assert_object(equipment.get_node_or_null("%ItemDetailCompare")).is_not_null()
	assert_bool((equipment.get_node("%EquipSelectedBtn") as Button).disabled).is_true()
	var preview_canvas := equipment.get_node("%PreviewFrame/PreviewCanvas") as Control
	var model_viewer := preview_canvas.get_node("ModelViewer") as Control
	assert_float(model_viewer.size.x).is_greater(200.0)
	assert_object(preview_canvas.get_node_or_null("DungeonBackground")).is_not_null()
	assert_object(equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/BottomInfo/StatsPanel/属性/StatsScroll/StatsBox/StatsVisual")).is_not_null()
	assert_bool((equipment.get_node("%CharacterStatsText") as Label).visible).is_false()
	assert_float(right_tabs.size.x).is_greater(left_column.size.x * 1.35)
	assert_int(gear_list.max_columns).is_equal(6)
	assert_int(gear_list.icon_mode).is_equal(ItemList.ICON_MODE_TOP)
	assert_int(gear_list.fixed_icon_size.x).is_equal(96)
	assert_int(gear_list.fixed_icon_size.y).is_equal(96)
	assert_int(gear_list.fixed_column_width).is_equal(148)
	assert_int(gear_list.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_int(gear_list.get_theme_font_size("font_size")).is_greater_equal(20)
	var preview_frame := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipTop/ModelPlaceholder/PreviewInfoBox/PreviewFrame") as PanelContainer
	assert_object(preview_frame.get_theme_stylebox("panel")).is_instanceof(StyleBoxTexture)
	assert_bool((preview_frame.get_theme_stylebox("panel") as StyleBoxTexture).draw_center).is_true()
	assert_bool((equipment.get_node("%EqSubViewport") as SubViewport).transparent_bg).is_true()
	assert_int(equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipTop/ArmorSlots").get_child_count()).is_equal(5)
	assert_int(equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipTop/WeaponSlots").get_child_count()).is_equal(5)
	for slot_name in ["SlotHead", "SlotBody", "SlotHands", "SlotFeet", "SlotWeapon1", "SlotWeapon2", "SlotWeapon3", "SlotWeapon4"]:
		var slot := equipment.get_node("%%%s" % slot_name) as Button
		assert_float(slot.custom_minimum_size.x).is_equal(96.0)
		assert_str(slot.text).is_empty()
		assert_object(slot.icon).is_null()
		assert_bool(slot.toggle_mode).is_true()
		assert_int(slot.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_object(slot.get_theme_stylebox("normal")).is_instanceof(StyleBoxTexture)
		var background_style := slot.get_theme_stylebox("normal") as StyleBoxTexture
		assert_bool(background_style.draw_center).is_true()
		assert_str(background_style.texture.resource_path).contains("slot_background_")
		var background_image: Image = background_style.texture.get_image()
		assert_int(background_image.get_width()).is_equal(96)
		var tone_values := {}
		for y in background_image.get_height():
			for x in background_image.get_width():
				var pixel: Color = background_image.get_pixel(x, y)
				if pixel.a <= 0.01:
					continue
				tone_values[int(round(pixel.r * 255.0))] = true
		# 纯色槽位底 + 单色轮廓通常只有两个主要色阶，关键是不能整块同色。
		assert_int(tone_values.size()).is_greater(1)
	var colored_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	colored_image.fill(Color(0.86, 0.14, 0.08, 1.0))
	var colored_texture := ImageTexture.create_from_image(colored_image)
	var preserved_icon := equipment._scaled_slot_icon(colored_texture)
	var preserved_pixel := preserved_icon.get_image().get_pixel(40, 40)
	assert_bool(preserved_pixel.r > preserved_pixel.g + 0.2).is_true()
	assert_bool(preserved_pixel.r > preserved_pixel.b + 0.2).is_true()
	assert_bool(equip_top.size.y >= 440.0 and equip_top.size.y <= 470.0).is_true()
	assert_float(bottom_info.size.y).is_greater(430.0)
	assert_float((equipment.get_node("PanelContainer/VBoxContainer/MainLayout/LeftColumn/BottomInfo/StatsPanel/属性/StatsScroll/StatsBox/StatsVisual") as Control).custom_minimum_size.y).is_greater_equal(360.0)
	var equipment_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	for attribute_label in ["力量 STR", "敏捷 DEX", "体质 CON", "智力 MAG", "灵巧 AGI", "感知 PER"]:
		assert_str(equipment_source).contains(attribute_label)
	host.queue_free()


func test_equipment_skill_tab_uses_compact_three_zone_layout() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var equipment := load("res://scenes/ui/tavern_equipment_panel.tscn").instantiate() as TavernEquipmentPanel
	host.add_child(equipment)
	equipment.visible = true
	await await_idle_frame()

	var workspace := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillWorkspaceRuntime") as VBoxContainer
	var skill_layout := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillWorkspaceRuntime/SkillLayout") as HBoxContainer
	var pyramid := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillWorkspaceRuntime/SkillLayout/SkillPyramidPanel") as Control
	var available_panel := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillWorkspaceRuntime/SkillLayout/AvailableSkillsPanel") as Control
	var available := equipment.find_child("AvailableSkillsList", true, false) as ItemList
	var details_panel := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillWorkspaceRuntime/SkillLayout/SkillPanel") as Control
	var warehouse_row := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillWorkspaceRuntime/SkillWarehouseRow") as HBoxContainer
	var warehouse := equipment.get_node("PanelContainer/VBoxContainer/MainLayout/RightTabs/技能/SkillWorkspaceRuntime/SkillWarehouseRow/RuneWarehousePanel") as Control
	assert_int(workspace.get_child_count()).is_equal(2)
	assert_int(skill_layout.get_child_count()).is_equal(3)
	assert_int(warehouse_row.get_child_count()).is_equal(1)
	assert_float(pyramid.custom_minimum_size.x).is_greater_equal(520.0)
	assert_float(available_panel.custom_minimum_size.x).is_greater_equal(300.0)
	assert_float(details_panel.custom_minimum_size.x).is_greater_equal(340.0)
	assert_float(warehouse.custom_minimum_size.y).is_equal(330.0)
	assert_object(equipment.find_child("AvailableSkillsTitle", true, false)).is_not_null()
	assert_object(equipment.find_child("SkillDetailsTitle", true, false)).is_not_null()
	assert_int(available.get_theme_font_size("font_size")).is_greater_equal(20)
	assert_int(available.fixed_icon_size.x).is_equal(44)
	assert_int(available.icon_mode).is_equal(ItemList.ICON_MODE_LEFT)
	var rune_warehouse := equipment.find_child("RuneWarehouseList", true, false) as ItemList
	assert_int(rune_warehouse.icon_mode).is_equal(ItemList.ICON_MODE_TOP)
	assert_int(rune_warehouse.fixed_icon_size.x).is_equal(72)
	assert_int(rune_warehouse.fixed_column_width).is_equal(148)
	assert_int(rune_warehouse.max_columns).is_equal(6)
	assert_bool(rune_warehouse.same_column_width).is_true()
	assert_bool(bool(rune_warehouse.get("fixed_grid_cells"))).is_true()
	var inventory_source := FileAccess.get_file_as_string("res://scenes/ui/inventory_drag_list.gd")
	assert_str(inventory_source).contains("const FIXED_GRID_ROW_HEIGHT := 136.0")
	for index in range(7):
		var skill_slot := equipment.find_child("SkillSlot%d" % index, true, false) as Button
		var expected_size := 150.0 if index < 2 else 92.0
		assert_float(skill_slot.custom_minimum_size.x).is_equal(expected_size)
		assert_float(skill_slot.custom_minimum_size.y).is_equal(expected_size)
	var rune_slots := equipment.find_children("RuneSlot*", "Button", true, false)
	assert_int(rune_slots.size()).is_equal(16)
	for rune_slot in rune_slots:
		assert_float((rune_slot as Button).custom_minimum_size.x).is_equal(44.0)
		assert_float((rune_slot as Button).custom_minimum_size.y).is_equal(44.0)
	host.queue_free()


func test_expedition_status_rail_does_not_cover_combat_log() -> void:
	var hud := load("res://scenes/ui/expedition_hud.tscn").instantiate() as Control
	hud.size = Vector2(1920, 1080)
	add_child(hud)
	await await_idle_frame()
	var top_hud := hud.get_node("TopHUD") as Control
	var middle_hud := hud.get_node("MiddleHUD") as Control
	assert_float(top_hud.position.x).is_greater(1600.0)
	assert_float(middle_hud.position.x).is_greater(1600.0)
	assert_str(String(top_hud.theme_type_variation)).is_equal("HUDPanel")
	hud.queue_free()


func _is_neutral_gray(color: Color) -> bool:
	var channel_range := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
	return channel_range <= 0.10
