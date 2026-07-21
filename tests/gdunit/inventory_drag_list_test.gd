extends GdUnitTestSuite

## Unit tests for InventoryDragList — verifies that clicking on a weapon/armor
## item does NOT trigger box-select, preventing conflict with Godot's native
## drag (_get_drag_data) used to drag equipment to equipment slots.

const DRAG_LIST_SCRIPT := "res://scenes/ui/inventory_drag_list.gd"

func _create_list() -> ItemList:
	var list: ItemList = load(DRAG_LIST_SCRIPT).new()
	add_child(list)
	# item 0 — weapon
	list.add_item("Weapon", null, true)
	list.set_item_metadata(0, {"type": "weapon", "id": "sword", "category": "weapons"})
	# item 1 — armor
	list.add_item("Armor", null, true)
	list.set_item_metadata(1, {"type": "armor", "id": "leather_body", "category": "body"})
	# item 2 — material
	list.add_item("Material", null, true)
	list.set_item_metadata(2, {"type": "material", "id": "wild_glowcap"})
	return list

func _make_click(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

# ── _is_equipment_item_at ──────────────────────────────────────────

func test_is_equipment_item_at_weapon() -> void:
	var list := _create_list()
	assert_bool(list._is_equipment_item_at(0)).is_true()
	list.queue_free()

func test_is_equipment_item_at_armor() -> void:
	var list := _create_list()
	assert_bool(list._is_equipment_item_at(1)).is_true()
	list.queue_free()

func test_is_equipment_item_at_material_is_false() -> void:
	var list := _create_list()
	assert_bool(list._is_equipment_item_at(2)).is_false()
	list.queue_free()

func test_is_equipment_item_at_negative_index_is_false() -> void:
	var list := _create_list()
	assert_bool(list._is_equipment_item_at(-1)).is_false()
	list.queue_free()

func test_is_equipment_item_at_out_of_range_is_false() -> void:
	var list := _create_list()
	assert_bool(list._is_equipment_item_at(999)).is_false()
	list.queue_free()

func test_is_equipment_item_at_non_dict_metadata_is_false() -> void:
	var list := _create_list()
	list.add_item("plain", null, true)
	list.set_item_metadata(3, "not_a_dict")
	assert_bool(list._is_equipment_item_at(3)).is_false()
	list.queue_free()

# ── _gui_input: box-select on empty space ─────────────────────────

func test_click_on_empty_space_starts_box_select() -> void:
	var list := _create_list()
	# Click far outside any item — get_item_at_position returns -1
	list._gui_input(_make_click(Vector2(9999, 9999), true))
	assert_bool(list._drag_selecting).is_true() \
		.override_failure_message("点击空白区域时应启动框选")
	list.queue_free()

func test_mouse_release_stops_box_select() -> void:
	var list := _create_list()
	list._gui_input(_make_click(Vector2(9999, 9999), true))
	assert_bool(list._drag_selecting).is_true()
	list._gui_input(_make_click(Vector2(100, 100), false))
	assert_bool(list._drag_selecting).is_false()
	list.queue_free()

# ── source code verification ──────────────────────────────────────

func test_source_contains_equipment_check() -> void:
	var source: String = FileAccess.get_file_as_string(DRAG_LIST_SCRIPT)
	assert_bool(source.contains("_is_equipment_item_at")).is_true() \
		.override_failure_message("源码应包含 _is_equipment_item_at 方法")
	assert_bool(source.contains("not _is_equipment_item_at(idx)")).is_true() \
		.override_failure_message("源码应在 _gui_input 中抑制装备物品的框选")
	# Old unconditional behavior should be gone
	assert_bool(source.contains("_drag_selecting = event.pressed")).is_false() \
		.override_failure_message("不应保留无条件框选旧行为")


func test_source_contains_pixel_grid_and_custom_name_layer() -> void:
	var source: String = FileAccess.get_file_as_string(DRAG_LIST_SCRIPT)
	assert_bool(source.contains("GRID_MAX_COLUMNS := 6")).is_true()
	assert_bool(source.contains("_draw_inventory_grid")).is_true()
	assert_bool(source.contains("inventory_grid_overlay.gd")).is_true() \
		.override_failure_message("网格应由独立 Overlay 绘制在原生图标之上")
	var grid_call := source.find("_draw_inventory_grid(target)")
	var labels_call := source.find("_draw_item_labels(target)")
	assert_int(grid_call).is_greater(labels_call) \
		.override_failure_message("最终网格线必须在标签和角标之后绘制")
	assert_bool(source.contains("neighbor cannot overwrite")).is_true() \
		.override_failure_message("选中格高亮必须在基础网格之后绘制")
	assert_bool(source.contains("_draw_item_labels")).is_true()
	assert_bool(source.contains('metadata.get("_inventory_label", "")')).is_true()
	assert_bool(source.contains("draw_rect(badge")).is_false() \
		.override_failure_message("数量角标应保持无框")


func test_custom_cell_rect_matches_item_list_rect() -> void:
	var list := _create_list()
	list.size = Vector2(960.0, 600.0)
	await await_idle_frame()
	var native_rect := list.get_item_rect(0, true)
	var drawn_rect: Rect2 = list._cell_rect_for_index(0)
	assert_float(drawn_rect.position.x).is_equal_approx(native_rect.position.x, 0.1)
	assert_float(drawn_rect.position.y).is_equal_approx(native_rect.position.y, 0.1)
	assert_float(drawn_rect.size.x).is_equal_approx(native_rect.size.x, 0.1)
	assert_float(drawn_rect.size.y).is_equal_approx(native_rect.size.y, 0.1)
	list.queue_free()


func test_grid_overlay_is_above_native_item_list_rendering() -> void:
	var list := _create_list()
	await await_idle_frame()
	var overlay := list.get_node_or_null("GridOverlay") as Control
	assert_object(overlay).is_not_null() \
		.override_failure_message("网格线必须使用 ItemList 子级 Overlay 绘制")
	if overlay != null:
		assert_int(overlay.z_index).is_greater(0) \
			.override_failure_message("网格 Overlay 必须位于原生图标绘制层之上")
		assert_int(overlay.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE) \
			.override_failure_message("网格 Overlay 不得拦截背包点击和拖拽")
	list.queue_free()
