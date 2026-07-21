extends GdUnitTestSuite

# ============================================================================
# Bug 修复回归测试 — 装备面板与装备系统
# 覆盖 Bug 1~20 的修复验证
# ============================================================================

# ── Bug 20: WeaponData 默认值 ──────────────────────────────────────────────

func test_weapon_data_has_safe_default_condition() -> void:
	var data := WeaponData.new()
	# 耐久已整体上调：默认 800（设计变更）
	assert_int(data.condition).is_equal(800)
	assert_int(data.max_condition).is_equal(800)


func test_weapon_data_has_safe_default_damage() -> void:
	var data := WeaponData.new()
	assert_int(data.damage_min).is_equal(1)
	assert_int(data.damage_max).is_equal(3)


func test_weapon_data_has_safe_default_reach() -> void:
	var data := WeaponData.new()
	assert_float(data.reach).is_equal(3.0)


func test_weapon_data_has_safe_default_throw_speeds() -> void:
	var data := WeaponData.new()
	assert_float(data.throw_rotation_speed).is_equal(40.0)
	assert_float(data.throw_movement_speed).is_equal(10.0)


func test_weapon_data_has_safe_default_name() -> void:
	var data := WeaponData.new()
	assert_str(data.name).is_equal("")


func test_weapon_data_decrease_condition_with_defaults() -> void:
	var data := WeaponData.new()
	data.decrease_condition(5)
	# 默认耐久 800，扣 5 后为 795
	assert_int(data.condition).is_equal(795)


func test_weapon_data_decrease_condition_clamps_to_zero_with_defaults() -> void:
	var data := WeaponData.new()
	# 默认耐久 800，扣超过上限后钳到 0
	data.decrease_condition(900)
	assert_int(data.condition).is_equal(0)
	assert_bool(data.is_broken).is_true()


# ── Bug 19: apply_armor_damage 冗余赋值 ────────────────────────────────────

func test_apply_armor_damage_modifies_condition() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	var armor := _make_armor("Leather", 2, 3.0)
	armor.condition = 10
	armor.max_condition = 10
	eq.configure_armor_slot("body", armor)
	assert_bool(eq.apply_armor_damage("body", 4)).is_true()
	var slot_data = eq.get_armor_slot_data("body")
	assert_int(slot_data.condition).is_equal(6)


func test_apply_armor_damage_returns_false_for_empty_slot() -> void:
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	assert_bool(eq.apply_armor_damage("body", 4)).is_false()


# ── Bug 2: throw_furniture / drop_shield current_level 空指针 ──────────────

func test_throw_furniture_safe_when_no_level() -> void:
	# 验证 throw_furniture 在 current_level 为 null 时不会崩溃，且不丢弃家具数据
	var eq = auto_free(load("res://scenes/characters/component/equipment_component.tscn").instantiate())
	eq.furniture_placeholder = Node3D.new()
	eq.add_child(eq.furniture_placeholder)
	var furniture := FurnitureData.new()
	furniture.name = "Barrel"
	furniture.throw_rotation_speed = 5.0
	furniture.throw_movement_speed = 8.0
	eq.furniture_data = furniture
	# 添加子节点到 placeholder 使 has_furniture() 返回 true
	var dummy := Node3D.new()
	eq.furniture_placeholder.add_child(dummy)
	# 不应崩溃；无 level 时 early-return，家具保留在手上
	eq.throw_furniture(false)
	assert_object(eq.furniture_data).is_not_null()


# ── Bug 3: _preview_hit_rate 安全字典访问 ──────────────────────────────────

func test_preview_hit_rate_uses_safe_dict_access() -> void:
	# 命中预览已抽到 equipment_panel_combat_stats.gd；验证使用 .get() 安全访问
	var source := (load("res://scenes/ui/equipment_panel_combat_stats.gd") as GDScript).source_code
	# 确认不再有 CE.STYLE_META[attack.style] 的直接访问
	assert_bool(source.contains("CE.STYLE_META[attack.style]")).is_false()
	# 确认使用了安全访问
	assert_bool(source.contains("CE.STYLE_META.get(attack.style, {})")).is_true()


# ── Bug 4: configure_armor_slot 当 eq 为 null 时返回 false ────────────────

func test_configure_armor_slot_source_has_null_check() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	# 确认 configure_armor_slot 中 eq == null 时 return false
	var func_start := source.find("func configure_armor_slot(slot_name")
	assert_int(func_start).is_greater(-1)
	var func_body := source.substr(func_start, 600)
	assert_bool(func_body.contains("if eq == null:")).is_true()
	assert_bool(func_body.contains("return false")).is_true()


# ── Bug 7: _spawn_preview_character 不再操作 GameState.current_player ──────

func test_spawn_preview_does_not_touch_gamestate() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _spawn_preview_character")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _prepare_equipment_slot_buttons")
	var func_body := source.substr(func_start, func_end - func_start)
	# 不应包含 previous_player 或 gs.set("current_player" 的恢复操作
	assert_bool(func_body.contains("previous_player")).is_false()
	assert_bool(func_body.contains('gs.set("current_player"')).is_false()
	assert_bool(source.contains("PLAYER_PREVIEW_MODEL")).is_true()
	assert_bool(source.contains("func _spawn_fallback_preview_model")).is_true()


# ── Bug 8: equipment_detail_popup 不再手动调用 _ready() ────────────────────

func test_detail_popup_does_not_call_ready_manually() -> void:
	var source := (load("res://scenes/ui/equipment_detail_popup.gd") as GDScript).source_code
	# show_detail 中不应再调用 _ready()
	var func_start := source.find("func show_detail")
	var func_end := source.find("func hide_detail")
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("_ready()")).is_false()
	# 应调用 _build_ui()
	assert_bool(func_body.contains("_build_ui()")).is_true()


func test_detail_popup_has_build_ui_method() -> void:
	var source := (load("res://scenes/ui/equipment_detail_popup.gd") as GDScript).source_code
	assert_bool(source.contains("func _build_ui()")).is_true()


# ── Bug 10: _scaled_slot_icon 使用缓存 ─────────────────────────────────────

func test_scaled_slot_icon_has_cache() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	assert_bool(source.contains("_slot_icon_cache")).is_true()


func test_empty_equipment_slots_use_generated_pixel_icons() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _empty_slot_icon")).is_true()
	assert_bool(source.contains("GENERATED_SLOT_BACKGROUND_TEXTURES")).is_true()
	assert_bool(source.contains("slot_background_head.png")).is_true()
	assert_bool(source.contains("slot_background_body.png")).is_true()
	assert_bool(source.contains("slot_background_hands.png")).is_true()
	assert_bool(source.contains("slot_background_feet.png")).is_true()
	assert_bool(source.contains("slot_background_weapon.png")).is_true()
	assert_bool(source.contains('gear_list.max_columns = INVENTORY_GRID_COLUMNS')).is_true()
	assert_bool(source.contains('theme_type_variation = &"SlotButton"')).is_true()
	assert_bool(source.contains("StyleBoxTexture")).is_true()
	assert_bool(source.contains("_slot_background_style")).is_true()
	assert_bool(source.contains("_prepare_preview_frame")).is_true()
	assert_bool(source.contains("_format_inventory_label")).is_true()
	assert_bool(source.contains("Older hand-authored versions keep ModelViewer directly under PreviewFrame")).is_true()
	assert_bool(source.contains('preview_canvas = Control.new()')).is_true()
	assert_bool(source.contains('preview_frame.remove_child(legacy_model_viewer)')).is_true()
	assert_bool(source.contains("_apply_single_tone")).is_false()


func test_inventory_grid_uses_named_items_and_quantity_badges() -> void:
	var source := (load("res://scenes/ui/inventory_drag_list.gd") as GDScript).source_code
	assert_bool(source.contains("fixed_column_width = GRID_COLUMN_WIDTH")).is_true()
	assert_bool(source.contains('add_theme_font_size_override("font_size", 20)')).is_true()
	assert_bool(source.contains("BADGE_SIZE")).is_true()
	assert_bool(source.contains("INVENTORY_ICON_SIZE) - BADGE_SIZE.y")).is_true()
	assert_bool(source.contains("draw_string(PIXEL_FONT")).is_true()
	assert_bool(source.contains('meta.get("amount", 0)')).is_true()
	assert_bool(source.contains('draw_rect(badge')).is_false()


# ── Bug 11: _can_bind_skill_to_slot 使用枚举常量 ───────────────────────────

func test_can_bind_skill_uses_enum_constants() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _can_bind_skill_to_slot")
	assert_int(func_start).is_greater(-1)
	var func_end := source.find("func _attr_panel_has_skill")
	var func_body := source.substr(func_start, func_end - func_start)
	# 不应使用硬编码整数 0: 1: 2:
	assert_bool(func_body.contains("\n\t\t0:")).is_false()
	assert_bool(func_body.contains("\n\t\t1:")).is_false()
	assert_bool(func_body.contains("\n\t\t2:")).is_false()
	# 应使用 SkillRuntime.SlotType 枚举
	assert_bool(func_body.contains("SkillRuntime.SlotType.F_ACTION")).is_true()
	assert_bool(func_body.contains("SkillRuntime.SlotType.G_WEAPON")).is_true()
	assert_bool(func_body.contains("SkillRuntime.SlotType.PASSIVE")).is_true()


# ── Bug 13: hide_panel 检查暂停状态 ────────────────────────────────────────

func test_hide_panel_checks_paused_state() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func hide_panel")
	var func_end := source.find("func _input")
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("get_tree().paused")).is_true()


# ── Bug 14: 预览清理使用 % 语法 ─────────────────────────────────────────────

func test_preview_cleanup_uses_unique_names() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _spawn_preview_character")
	var func_end := source.find("func _prepare_equipment_slot_buttons")
	var func_body := source.substr(func_start, func_end - func_start)
	# 不应使用旧的硬编码路径
	assert_bool(func_body.contains('"MainCamera/SelectRaycast"')).is_false()
	assert_bool(func_body.contains('"MainCamera/KickRaycast"')).is_false()
	# 应使用 % 语法
	assert_bool(func_body.contains('%SelectRaycast')).is_true()
	assert_bool(func_body.contains('%KickRaycast')).is_true()


# ── Bug 16: 死代码 _armor_slot_label 已删除 ────────────────────────────────

func test_armor_slot_label_dead_code_removed() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _armor_slot_label")).is_false()


# ── Bug 17: 死代码 _inspect_armor_slot 已删除 ──────────────────────────────

func test_inspect_armor_slot_dead_code_removed() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	assert_bool(source.contains("func _inspect_armor_slot")).is_false()


# ── Bug 15: on_sleep 校验数据 ──────────────────────────────────────────────

func test_on_sleep_checks_null_data() -> void:
	var source := (load("res://scenes/equipment/thrown_item.gd") as GDScript).source_code
	var func_start := source.find("func on_sleep")
	var func_end := source.find("func _get_spawn_parent")
	var func_body := source.substr(func_start, func_end - func_start)
	# 应包含对 weapon_data == null and shield_data == null 的检查
	assert_bool(func_body.contains("weapon_data == null and shield_data == null")).is_true()


# ── Bug 1: thrown_item 碰撞形状空指针保护 ──────────────────────────────────

func test_thrown_item_mesh_null_check() -> void:
	var source := (load("res://scenes/equipment/thrown_item.gd") as GDScript).source_code
	# 碰撞形状生成前必须校验 mesh_node / mesh 非空（当前用正逻辑短路）
	assert_bool(source.contains("mesh_node != null") or source.contains("mesh_node == null")).is_true()
	assert_bool(
		source.contains("mesh_node.mesh != null")
		or source.contains("mesh_node.mesh == null")
		or source.contains("mesh_instance.mesh == null")
	).is_true()


# ── Bug 6: _equip_gear_metadata 自动推断防具槽位 ──────────────────────────

func test_equip_gear_infers_armor_slot() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _equip_gear_metadata")
	var func_end := source.find("func _refresh_skill_slots")
	var func_body := source.substr(func_start, func_end - func_start)
	# 应包含从 armor_data 推断 target_slot 的逻辑
	assert_bool(func_body.contains("armor_data.armor_slot")).is_true()


# ── Bug 12: 绑定技能失败有反馈 ─────────────────────────────────────────────

func test_bind_skill_failure_shows_message() -> void:
	var source := (load("res://scenes/ui/tavern_equipment_panel.gd") as GDScript).source_code
	var func_start := source.find("func _on_bind_skill_pressed")
	var func_end := source.find("func _on_unbind_skill_pressed")
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains("无法绑定到该槽位")).is_true()


# ── Bug 18: skill_drag_list 添加了防护注释和 guard ─────────────────────────

func test_skill_drag_list_has_drop_guard() -> void:
	var source := (load("res://scenes/ui/skill_drag_list.gd") as GDScript).source_code
	# _drop_data 应在 drag_source != "skill_slots" 时 return
	var func_start := source.find("func _drop_data")
	var func_end := source.find("func _slot_index_at_position")
	var func_body := source.substr(func_start, func_end - func_start)
	assert_bool(func_body.contains('drag_source != "skill_slots"')).is_true()


# ── 辅助函数 ────────────────────────────────────────────────────────────────

func _make_armor(label: String, phys_def: int, evade: float, move_speed_mult: float = 1.0) -> WeaponData:
	var data := WeaponData.new()
	data.id = label.to_lower()
	data.name = label
	data.item_tag = "armor_light"
	data.equipment_category = "armor_light"
	data.armor_slot = "body"
	data.armor_phys_def = phys_def
	data.armor_move_speed_mult = move_speed_mult
	data.condition = 10
	data.max_condition = 10
	return data
