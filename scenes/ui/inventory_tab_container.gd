class_name InventoryTabContainer
extends TabContainer

const ITEMS_TAB_INDEX := 0
const WAREHOUSE_TAB_INDEX := 2

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel: Node = _get_inventory_panel()
	var target := _target_source_for_hovered_tab()
	return panel != null and target != "" and panel.can_drop_inventory_data(target, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var panel: Node = _get_inventory_panel()
	var target := _target_source_for_hovered_tab()
	if panel != null and target != "":
		panel.drop_inventory_data(target, data)
		current_tab = WAREHOUSE_TAB_INDEX if target == "warehouse" else ITEMS_TAB_INDEX

func _target_source_for_hovered_tab() -> String:
	var tab_index := _hovered_tab_index()
	match tab_index:
		ITEMS_TAB_INDEX:
			return "items"
		WAREHOUSE_TAB_INDEX:
			return "warehouse"
	return ""

func _hovered_tab_index() -> int:
	var tab_bar := get_tab_bar()
	if tab_bar != null and tab_bar.get_global_rect().has_point(get_global_mouse_position()):
		return tab_bar.get_tab_idx_at_point(tab_bar.get_local_mouse_position())
	return current_tab

func _get_inventory_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("can_drop_inventory_data"):
			return node
		node = node.get_parent()
	return null
