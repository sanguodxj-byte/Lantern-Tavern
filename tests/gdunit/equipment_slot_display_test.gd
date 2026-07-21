extends GdUnitTestSuite

## 装备槽显示优化测试：
## 1. 装备槽统一使用图标，名称通过 tooltip 提供
## 2. 角色预览保持 45° 侧前视角（225° / 215°）

# ── tavern_equipment_panel.gd: 武器槽有装备时仅显示图标 ──────────────────

func test_tavern_weapon_slot_hides_text_when_icon_present() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _refresh_equipment_slots()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _refresh_items()")
	var func_body := source.substr(func_start, func_end - func_start)
	# 槽位始终使用图标，装备名放入 tooltip；空槽也有语义图标。
	assert_bool(func_body.contains('button.text = ""')).is_true()
	assert_bool(func_body.contains('button.tooltip_text = tr("手持槽 %d\\n%s")')).is_true()


func test_tavern_weapon_slot_has_no_legacy_empty_text_branch() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _refresh_equipment_slots()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _refresh_items()")
	var func_body := source.substr(func_start, func_end - func_start)
	# 空槽使用生成的像素图标，不再依赖旧的多行文字标签。
	assert_bool(func_body.contains('_empty_slot_icon("weapon", data_index)')).is_true()
	assert_bool(func_body.contains('item_label := tr("空")')).is_true()


func test_tavern_weapon_hand_slots_merge_for_two_hand_loadouts() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	assert_bool(source.contains("func _weapon_slot_occupies_both_hands(data: Variant) -> bool")).is_true()
	assert_bool(source.contains("func _two_hand_group_slot_index(eq: Node) -> int")).is_true()
	assert_bool(source.contains("button.visible = false")).is_true()
	assert_bool(source.contains("EQUIPMENT_SLOT_SIZE.y * 2.0 + 6.0")).is_true()
	assert_bool(source.contains("selected_weapon_slot = _normalise_weapon_slot_index(slot_index)")).is_true()
	assert_bool(source.contains("func _weapon_slot_data_index_for_visual(slot_index: int) -> int")).is_true()
	assert_bool(source.contains("source_slot_index\": _weapon_slot_data_index_for_visual(slot_index)")).is_true()
	assert_bool(source.contains("A merged two-hand group is removed through the inventory path")).is_true()
	assert_bool(source.contains("weapon_hand_link.visible = two_hand_slot < 0")).is_true()
	var scene_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.tscn")
	assert_bool(scene_source.contains('[node name="WeaponHandLink" type="Control" parent="PanelContainer/VBoxContainer/MainLayout/LeftColumn/EquipTop/WeaponSlots/SlotWeapon1"')).is_true()
	assert_bool(scene_source.contains("offset_top = 84.0")).is_true()
	assert_bool(scene_source.contains("z_index = 20")).is_true()
	assert_bool(scene_source.contains('path="res://scenes/ui/weapon_hand_link_visual.gd"')).is_true()


func test_tavern_weapon_hand_link_is_pixel_drawn_and_non_interactive() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/weapon_hand_link_visual.gd")
	assert_bool(source.contains("func _draw() -> void")).is_true()
	assert_bool(source.contains("func _draw_chain_link(center: Vector2, direction: int) -> void")).is_true()
	assert_bool(source.contains("Control.MOUSE_FILTER_IGNORE")).is_true()


func test_tavern_feet_hint_is_centered_pair_instead_of_skewed_source() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	assert_bool(source.contains('const SLOT_HINT_ASSET_VERSION := "v4"')).is_true()
	assert_bool(source.contains('slot_background_feet_generated_v4.png')).is_true()
	assert_bool(source.contains("image = _build_solid_slot_hint_image(image)")).is_true()


func test_tavern_weapon_hand_classification_matches_equipment_rules() -> void:
	var panel: TavernEquipmentPanel = (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).new() as TavernEquipmentPanel
	var one_hand: WeaponData = (load("res://data/weapon_data.gd") as GDScript).new() as WeaponData
	one_hand.hands = "one_hand"
	one_hand.attack_type = "melee"
	one_hand.weapon_class = "one_hand_melee"
	var ranged: WeaponData = (load("res://data/weapon_data.gd") as GDScript).new() as WeaponData
	ranged.hands = "two_hand"
	ranged.attack_type = "ranged"
	var spell: WeaponData = (load("res://data/weapon_data.gd") as GDScript).new() as WeaponData
	spell.attack_type = "spell"
	assert_bool(panel._weapon_slot_occupies_both_hands(one_hand)).is_false()
	assert_bool(panel._weapon_slot_occupies_both_hands(ranged)).is_true()
	assert_bool(panel._weapon_slot_occupies_both_hands(spell)).is_true()
	panel.free()


# ── tavern_equipment_panel.gd: 防具槽有装备时仅显示图标 ──────────────────

func test_tavern_armor_slot_hides_text_when_icon_present() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _refresh_armor_slot_button")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _refresh_character_summary")
	var func_body := source.substr(func_start, func_end - func_start)
	# 防具槽与武器槽保持同一图标优先契约。
	assert_bool(func_body.contains('button.text = ""')).is_true()
	assert_bool(func_body.contains('button.tooltip_text = "%s%s\\n%s"')).is_true()


func test_tavern_armor_slot_has_no_legacy_empty_text_branch() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _refresh_armor_slot_button")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _refresh_character_summary")
	var func_body := source.substr(func_start, func_end - func_start)
	# 空槽由生成的槽位图标表达，文本只保留在 tooltip。
	assert_bool(func_body.contains('button.icon = _empty_slot_icon(slot_name)')).is_true()
	assert_bool(func_body.contains('item_label := tr("空")')).is_true()


func test_tavern_empty_equipment_slots_use_pale_role_hints() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	# 空槽使用 Button 原生 icon 绘制同一套浅色像素剪影，避免提示被按钮背景遮挡。
	assert_bool(source.contains("const SLOT_HINT_COLOR := Color(0.94, 0.82, 0.64, 0.55)")).is_true()
	assert_bool(source.contains("ImageTexture.create_from_image(image)")).is_true()
	assert_bool(source.contains("func _build_solid_slot_hint_image(source_image: Image) -> Image")).is_true()
	assert_bool(source.contains("_queue_slot_hint_exterior")).is_true()
	assert_bool(source.contains("button.icon = _empty_slot_icon(slot_name)")).is_true()
	assert_bool(source.contains("button.icon = icon")).is_true()


func test_tavern_equipment_slots_use_regenerated_pixel_assets() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	assert_bool(source.contains('const SLOT_HINT_ASSET_VERSION := "v4"')).is_true()
	assert_bool(source.contains('"empty_hint_%s_%s" % [SLOT_HINT_ASSET_VERSION, slot_kind]')).is_true()
	for slot_kind in ["head", "body", "hands", "feet", "weapon"]:
		var version := "v4" if slot_kind == "feet" else "v3"
		var asset_path := "res://assets/textures/icons/equipment/generated/slot_background_%s_generated_%s.png" % [slot_kind, version]
		assert_bool(FileAccess.file_exists(asset_path)).is_true()
		assert_bool(source.contains(asset_path)).is_true()


func test_tavern_preview_caption_is_removed() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.tscn")
	var label_start := scene_source.find("[node name=\"ModelLabel\"")
	assert_int(label_start).is_greater(-1)
	var label_end := scene_source.find("[node name=\"BottomInfo\"", label_start)
	var label_body := scene_source.substr(label_start, label_end - label_start)
	assert_bool(label_body.contains("visible = false")).is_true()
	assert_bool(label_body.contains("text = \"装备预览\"")).is_false()


func test_tavern_equipment_panel_uses_parchment_texture_background() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.tscn")
	assert_bool(FileAccess.file_exists("res://assets/textures/ui/equipment_panel_background_parchment_v2.png")).is_true()
	assert_bool(scene_source.contains('type="TextureRect" parent="."')).is_true()
	assert_bool(scene_source.contains('path="res://assets/textures/ui/equipment_panel_background_parchment_v2.png"')).is_true()
	assert_bool(scene_source.contains('texture = ExtResource("11_panel_background")')).is_true()
	assert_bool(scene_source.contains('theme_override_styles/panel = SubResource("EquipmentRootPanel")')).is_true()
	assert_bool(scene_source.contains('bg_color = Color(0, 0, 0, 0)')).is_true()
	assert_bool(scene_source.contains('id="EquipmentSectionPanel"')).is_true()
	assert_bool(scene_source.contains('id="EquipmentListPanel"')).is_true()
	assert_bool(scene_source.contains('theme_override_styles/panel = SubResource("EquipmentListPanel")')).is_true()
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _remove_internal_information_fills() -> void")).is_true()
	assert_bool(source.contains('add_theme_stylebox_override("panel", panel_style)')).is_true()
	assert_bool(scene_source.contains('[node name="StatsPanel" type="TabContainer"')).is_true()
	var stats_source := (load("res://scenes/ui/equipment_stats_visual.gd") as GDScript).source_code
	assert_bool(stats_source.contains('draw_rect(row, Color(0, 0, 0, 0), true)')).is_true()


# ── tavern_equipment_panel.gd: 角色预览改为侧前视角 ──────────────────────

func test_tavern_preview_rotation_is_front_side() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _spawn_preview_character")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _prepare_equipment_slot_buttons")
	var func_body := source.substr(func_start, func_end - func_start)
	# 应使用 215° (= 180° + 35°) 使角色面向摄像机，呈侧前视角
	assert_bool(func_body.contains("deg_to_rad(215)")).is_true()
	# 不应使用旧的 35° 背视角
	assert_bool(func_body.contains("deg_to_rad(35)")).is_false()


# ── character_panel.gd: 主手/副手槽有装备时仅显示图标 ────────────────────

func test_char_panel_main_hand_hides_text_when_icon_present() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	var func_start := source.find("func _setup_slots_text()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _load_attributes()")
	var func_body := source.substr(func_start, func_end - func_start)
	# 有图标时应清空 text
	assert_bool(func_body.contains("if icon != null:")).is_true()
	assert_bool(func_body.contains("slot_main_hand.text = \"\"")).is_true()
	assert_bool(func_body.contains("slot_main_hand.tooltip_text = display_name")).is_true()


func test_char_panel_off_hand_hides_text_when_icon_present() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	var func_start := source.find("func _setup_slots_text()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _load_attributes()")
	var func_body := source.substr(func_start, func_end - func_start)
	# 副手有图标时应清空 text
	assert_bool(func_body.contains("if s_icon != null:")).is_true()
	assert_bool(func_body.contains("slot_off_hand.text = \"\"")).is_true()
	assert_bool(func_body.contains("slot_off_hand.tooltip_text = s_display")).is_true()


func test_char_panel_slots_show_text_when_no_equipment() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	var func_start := source.find("func _setup_slots_text()")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _load_attributes()")
	var func_body := source.substr(func_start, func_end - func_start)
	# 无武器时应显示文字
	assert_bool(func_body.contains('tr("Main Hand\\n[Fists]")')).is_true()
	# 无盾牌时应显示文字
	assert_bool(func_body.contains('tr("Off Hand\\n[Empty]")')).is_true()


# ── character_panel.gd: 角色预览改为侧前视角 ──────────────────────────────

func test_char_panel_preview_rotation_is_front_side() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	var func_start := source.find("func _spawn_preview_character")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _remove_preview_unnecessary")
	var func_body := source.substr(func_start, func_end - func_start)
	# 应使用 225° (= 180° + 45°) 使角色面向摄像机，呈侧前视角
	assert_bool(func_body.contains("deg_to_rad(225)")).is_true()
	# 不应使用旧的 45° 背视角
	assert_bool(func_body.contains("deg_to_rad(45)")).is_false()


# ── character_panel.gd: 槽位按钮图标显示属性配置 ──────────────────────────

func test_char_panel_has_slot_icon_display_setup() -> void:
	var source := (load("res://scenes/ui/character_panel.gd") as GDScript).source_code
	# 应有 _setup_slot_icon_display 辅助函数
	assert_bool(source.contains("func _setup_slot_icon_display")).is_true()
	assert_bool(source.contains("button.expand_icon = true")).is_true()
	assert_bool(source.contains("button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER")).is_true()


# ── equipment_screen_capture.gd: 属性熟练度页截图入口 ─────────────────────

func test_equipment_capture_supports_proficiency_page() -> void:
	var source := FileAccess.get_file_as_string("res://tools/equipment_screen_capture.gd")
	assert_bool(source.contains("var capture_proficiency := false")).is_true()
	assert_bool(source.contains('argument == "--proficiency"')).is_true()
	assert_bool(source.contains("after_proficiency.png")).is_true()
	assert_bool(source.contains("stats_panel.current_tab = 1")).is_true()


func test_tavern_proficiency_uses_weapon_catalog_and_no_armor_tracks() -> void:
	var panel_source := FileAccess.get_file_as_string("res://scenes/ui/tavern_equipment_panel.gd")
	var visual_source := FileAccess.get_file_as_string("res://scenes/ui/equipment_stats_visual.gd")
	var capture_source := FileAccess.get_file_as_string("res://tools/equipment_screen_capture.gd")
	assert_bool(panel_source.contains("WEAPON_PROFICIENCY_CATALOG.entries()")).is_true()
	assert_bool(panel_source.contains("value_for(prof, key)")).is_true()
	assert_bool(visual_source.contains("PROFICIENCY_ICON_PATHS")).is_true()
	assert_bool(visual_source.contains('"剑": "res://assets/textures/icons/equipment/weapons_sword.png"')).is_true()
	assert_bool(capture_source.contains("剑 42\n匕首 35\n斧 28")).is_true()
	assert_bool(capture_source.contains("轻甲")).is_false()
	assert_bool(capture_source.contains("炼金")).is_false()
