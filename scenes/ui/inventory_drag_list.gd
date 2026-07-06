class_name InventoryDragList
extends ItemList

const INVENTORY_ICON_SIZE := 104

@export var inventory_source: String = ""

var _drag_selecting := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _hovered_index := -1

func _ready() -> void:
	select_mode = ItemList.SELECT_MULTI
	allow_reselect = true
	icon_mode = ItemList.ICON_MODE_TOP
	fixed_icon_size = Vector2i(INVENTORY_ICON_SIZE, INVENTORY_ICON_SIZE)
	max_columns = 0
	same_column_width = true
	mouse_exited.connect(_on_mouse_exited)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_start = event.position
		_drag_current = event.position
		if event.pressed:
			var idx: int = get_item_at_position(event.position, true)
			if idx >= 0 and not is_selected(idx):
				select(idx, false)
			# 装备（武器/防具）通过 Godot 原生拖拽（_get_drag_data）单独拖动到装备槽，
			# 不启动框选，避免框选矩形与拖拽预览冲突。
			_drag_selecting = not _is_equipment_item_at(idx)
		else:
			_drag_selecting = false
		queue_redraw()
	elif event is InputEventMouseMotion and _drag_selecting:
		_drag_current = event.position
		_select_items_in_rect(_selection_rect())
		queue_redraw()
	elif event is InputEventMouseMotion:
		_update_hovered_item(event.position)

## 判断指定索引处的物品是否为装备（武器或防具）。
## 装备类物品通过原生拖拽单独拖动，不参与框选。
func _is_equipment_item_at(idx: int) -> bool:
	if idx < 0:
		return false
	var meta = get_item_metadata(idx)
	if typeof(meta) != TYPE_DICTIONARY:
		return false
	var t: String = String(meta.get("type", ""))
	return t == "weapon" or t == "armor"

func _draw() -> void:
	if _drag_selecting:
		draw_rect(_selection_rect(), Color(0.976, 0.639, 0.105, 0.18), true)
		draw_rect(_selection_rect(), Color(0.976, 0.639, 0.105, 0.8), false, 1.0)

func _selection_rect() -> Rect2:
	return Rect2(_drag_start, _drag_current - _drag_start).abs()

func _select_items_in_rect(rect: Rect2) -> void:
	for i in range(item_count):
		if rect.intersects(get_item_rect(i, true)):
			select(i, false)

func _get_drag_data(_at_position: Vector2) -> Variant:
	var panel: Node = _get_inventory_panel()
	if panel == null:
		return null
	var data: Dictionary = panel.collect_drag_payload(inventory_source)
	if data.is_empty():
		return null
	var preview := Label.new()
	preview.text = "x%d" % data.get("count", 0)
	set_drag_preview(preview)
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel: Node = _get_inventory_panel()
	return panel != null and panel.can_drop_inventory_data(inventory_source, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var panel: Node = _get_inventory_panel()
	if panel != null:
		panel.drop_inventory_data(inventory_source, data)

func _update_hovered_item(local_position: Vector2) -> void:
	var idx := get_item_at_position(local_position, true)
	if idx == _hovered_index:
		return
	_hovered_index = idx
	var panel: Node = _get_inventory_panel()
	if panel == null:
		return
	if idx >= 0 and panel.has_method("show_inventory_item_detail"):
		panel.show_inventory_item_detail(inventory_source, idx, get_global_mouse_position())
	elif panel.has_method("hide_detail_popup"):
		panel.hide_detail_popup()

func _on_mouse_exited() -> void:
	_hovered_index = -1
	var panel: Node = _get_inventory_panel()
	if panel != null and panel.has_method("hide_detail_popup"):
		panel.hide_detail_popup()

func _get_inventory_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("collect_drag_payload"):
			return node
		node = node.get_parent()
	return null
