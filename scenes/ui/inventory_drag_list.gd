class_name InventoryDragList
extends ItemList

const INVENTORY_ICON_SIZE := 96
const GRID_COLUMN_WIDTH := 148
const GRID_MAX_COLUMNS := 6
const FIXED_GRID_ROW_HEIGHT := 136.0
const GRID_FALLBACK_ROW_HEIGHT := 164.0
const CELL_FRAME_INSET := 6.0
const GRID_OVERLAY_SCRIPT := preload("res://scenes/ui/inventory_grid_overlay.gd")
const VIEW_MODEL := preload("res://scenes/ui/equipment_screen_view_model.gd")
const BADGE_SIZE := Vector2(44, 22)
const BADGE_FONT_SIZE := 16
const PIXEL_FONT := preload("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf")
const CELL_BORDER := Color(0.32, 0.23, 0.17, 0.88)
const CELL_SELECTED_BORDER := Color(0.96, 0.63, 0.25, 1.0)
const CELL_HOVER_BORDER := Color(0.68, 0.70, 0.74, 1.0)

@export var inventory_source: String = ""
@export var fixed_grid_cells := false

var _drag_selecting := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _hovered_index := -1
var _grid_overlay: Control

func _ready() -> void:
	select_mode = ItemList.SELECT_MULTI
	allow_reselect = true
	icon_mode = ItemList.ICON_MODE_TOP
	fixed_icon_size = Vector2i(INVENTORY_ICON_SIZE, INVENTORY_ICON_SIZE)
	fixed_column_width = GRID_COLUMN_WIDTH
	max_columns = GRID_MAX_COLUMNS
	same_column_width = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_font_size_override("font_size", 20)
	# The selection frame is drawn below from the exact ItemList cell rect.
	# An empty native style prevents a second, differently-sized frame from
	# being painted on top of it.
	var empty_style := StyleBoxEmpty.new()
	add_theme_stylebox_override("selected", empty_style)
	add_theme_stylebox_override("selected_focus", empty_style)
	add_theme_stylebox_override("focus", empty_style)
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_grid_overlay = GRID_OVERLAY_SCRIPT.new()
	_grid_overlay.name = "GridOverlay"
	_grid_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid_overlay.inventory_list = self
	add_child(_grid_overlay)
	mouse_exited.connect(_on_mouse_exited)
	item_selected.connect(func(_index: int): _queue_overlay_redraw())

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
		_queue_overlay_redraw()
	elif event is InputEventMouseMotion and _drag_selecting:
		_drag_current = event.position
		_select_items_in_rect(_selection_rect())
		_queue_overlay_redraw()
	elif event is InputEventMouseMotion:
		_update_hovered_item(event.position)

## 判断指定索引处的物品是否为装备（武器或防具）。
## 装备类物品通过原生拖拽单独拖动，不参与框选。
func _is_equipment_item_at(idx: int) -> bool:
	if idx < 0 or idx >= item_count:
		return false
	var meta = get_item_metadata(idx)
	if typeof(meta) != TYPE_DICTIONARY:
		return false
	var t: String = String(meta.get("type", ""))
	return t == "weapon" or t == "armor"

func _draw() -> void:
	# Custom inventory paint is delegated to GridOverlay so it appears after
	# ItemList's native icon paint.
	pass


func _draw_inventory_overlay(target: CanvasItem) -> void:
	if _drag_selecting:
		target.draw_rect(_selection_rect(), Color(0.976, 0.639, 0.105, 0.18), true)
	_draw_fixed_grid_icons(target)
	for i in range(item_count):
		var cell := _visual_cell_rect(i)
		var meta = get_item_metadata(i)
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var amount := int(meta.get("amount", 0))
		if amount <= 0:
			continue
		var badge_position := cell.position + Vector2(
			maxf(0.0, cell.size.x - BADGE_SIZE.x - 4.0),
			maxf(0.0, minf(cell.size.y - BADGE_SIZE.y - 4.0, float(INVENTORY_ICON_SIZE) - BADGE_SIZE.y - 4.0))
		)
		var badge := Rect2(badge_position, BADGE_SIZE)
		var badge_text := "x%d" % amount
		var text_position := badge.position + Vector2(0.0, 16.0)
		target.draw_string(PIXEL_FONT, text_position + Vector2(1.0, 1.0), badge_text, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, BADGE_FONT_SIZE, Color(0.0, 0.0, 0.0, 0.85))
		target.draw_string(PIXEL_FONT, text_position, badge_text, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, BADGE_FONT_SIZE, Color(0.92, 0.86, 0.72, 1.0))
	_draw_item_labels(target)
	# This is deliberately the final normal paint pass. It must sit above
	# native icons, custom labels and quantity badges at cell boundaries.
	_draw_inventory_grid(target)
	if _drag_selecting:
		target.draw_rect(_selection_rect(), Color(0.976, 0.639, 0.105, 0.8), false, 1.0)


func _draw_inventory_grid(target: CanvasItem) -> void:
	if size.x <= 16.0 or size.y <= 16.0:
		return
	var column_count := _visible_column_count()
	var metrics := _grid_metrics(column_count)
	var row_height: float = metrics.row_height
	# Only occupied rows receive frames. Drawing every possible row made the
	# unused half of the list look like a second, empty inventory screen.
	var row_count := maxi(1, int(ceil(float(item_count) / float(column_count))))
	for row in range(row_count):
		for column in range(column_count):
			var item_index := _item_index_for_grid_cell(row, column, column_count)
			if item_index < 0:
				continue
			var cell := _grid_cell_rect(row, column, column_count, metrics)
			if cell.position.x >= size.x or cell.position.y >= size.y:
				continue
			target.draw_rect(_cell_frame_rect(cell), CELL_BORDER, false, 2.0)
			_draw_quality_marker(target, cell, get_item_metadata(item_index))
	# Draw emphasis after the complete base grid so a neighbor cannot overwrite
	# the selected cell's right or bottom edge.
	for row in range(row_count):
		for column in range(column_count):
			var item_index := _item_index_for_grid_cell(row, column, column_count)
			if item_index < 0:
				continue
			var border := CELL_SELECTED_BORDER if is_selected(item_index) else CELL_BORDER
			if item_index == _hovered_index:
				border = CELL_HOVER_BORDER
			if border != CELL_BORDER:
				target.draw_rect(_cell_frame_rect(_grid_cell_rect(row, column, column_count, metrics)), border, false, 2.0)


func _draw_item_labels(target: CanvasItem) -> void:
	for index in range(item_count):
		var metadata := get_item_metadata(index)
		if typeof(metadata) != TYPE_DICTIONARY:
			continue
		var label := String(metadata.get("_inventory_label", ""))
		if label.is_empty():
			continue
		var cell := _visual_cell_rect(index)
		var label_top := float(INVENTORY_ICON_SIZE - 6)
		var label_rect := Rect2(
			cell.position + Vector2(4.0, label_top),
			Vector2(maxf(24.0, cell.size.x - 8.0), maxf(56.0, cell.size.y - label_top))
		)
		# 覆盖 ItemList 默认的省略文本，再以像素字体绘制可控的双行名称。
		target.draw_rect(label_rect, Color(0.038, 0.03, 0.039, 0.98), true)
		var lines := label.split("\n", false)
		var label_color := Color(0.96, 0.84, 0.62, 1.0)
		var quality_tier := String(metadata.get("quality_tier", ""))
		if not quality_tier.is_empty():
			label_color = VIEW_MODEL.quality_color_for_tier(quality_tier)
		if is_selected(index):
			label_color = Color(1.0, 0.72, 0.32, 1.0)
		elif index == _hovered_index:
			label_color = Color(0.92, 0.93, 0.96, 1.0)
		for line_index in range(mini(2, lines.size())):
			var baseline := label_rect.position.y + 18.0 + line_index * 20.0
			target.draw_string(PIXEL_FONT, Vector2(label_rect.position.x, baseline), String(lines[line_index]), HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x, 19, label_color)


func _draw_quality_marker(target: CanvasItem, cell: Rect2, metadata: Variant) -> void:
	if inventory_source == "rune_warehouse":
		return
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	var tier := String(metadata.get("quality_tier", ""))
	if tier.is_empty():
		return
	var color := VIEW_MODEL.quality_color_for_tier(tier)
	var marker := Rect2(cell.position + Vector2(9.0, 9.0), Vector2(maxf(20.0, cell.size.x - 18.0), 4.0))
	target.draw_rect(marker, color, true)


func _draw_fixed_grid_icons(target: CanvasItem) -> void:
	if not fixed_grid_cells:
		return
	for index in range(item_count):
		var metadata := get_item_metadata(index)
		if typeof(metadata) != TYPE_DICTIONARY:
			continue
		var icon := metadata.get("_inventory_icon", null) as Texture2D
		if icon == null:
			continue
		var cell := _visual_cell_rect(index)
		var icon_size := Vector2(72.0, 72.0)
		var icon_rect := Rect2(cell.position + Vector2((cell.size.x - icon_size.x) * 0.5, 10.0), icon_size)
		target.draw_texture_rect(icon, icon_rect, false)


func _queue_overlay_redraw() -> void:
	if is_instance_valid(_grid_overlay):
		_grid_overlay.queue_redraw()


## Single source of truth for every occupied inventory cell.
## ItemList owns the icon, hit-test and selection geometry; custom borders,
## labels and badges must all use this same rectangle.
func _cell_rect_for_index(index: int) -> Rect2:
	if index < 0 or index >= item_count:
		return Rect2()
	return get_item_rect(index, true)


func _visual_cell_rect(index: int) -> Rect2:
	var cell := _cell_rect_for_index(index)
	if not fixed_grid_cells or item_count <= 0:
		return cell
	var first := _cell_rect_for_index(0)
	var column := index % GRID_MAX_COLUMNS
	var row := index / GRID_MAX_COLUMNS
	return Rect2(first.position + Vector2(column * float(GRID_COLUMN_WIDTH), row * FIXED_GRID_ROW_HEIGHT), Vector2(float(GRID_COLUMN_WIDTH), FIXED_GRID_ROW_HEIGHT))


func _visible_column_count() -> int:
	return mini(GRID_MAX_COLUMNS, maxi(1, int(floor((size.x - 12.0) / float(GRID_COLUMN_WIDTH)))))


func _grid_metrics(column_count: int) -> Dictionary:
	var origin := Vector2(6.0, 6.0)
	var cell_size := Vector2(float(GRID_COLUMN_WIDTH - 8), GRID_FALLBACK_ROW_HEIGHT - 8.0)
	var column_pitch := float(GRID_COLUMN_WIDTH)
	var row_height := GRID_FALLBACK_ROW_HEIGHT
	if item_count <= 0:
		return {"origin": origin, "cell_size": cell_size, "column_pitch": column_pitch, "row_height": row_height}

	var first := _visual_cell_rect(0)
	origin = first.position
	cell_size = first.size
	if item_count > 1:
		var second := _visual_cell_rect(1)
		if is_equal_approx(first.position.y, second.position.y):
			column_pitch = second.position.x - first.position.x
	if column_pitch <= 0.0:
		column_pitch = float(GRID_COLUMN_WIDTH)

	var next_row_index := column_count
	if next_row_index < item_count:
		var next_row := _visual_cell_rect(next_row_index)
		row_height = next_row.position.y - first.position.y
	if row_height <= 0.0:
		row_height = maxf(first.size.y, GRID_FALLBACK_ROW_HEIGHT)
	return {"origin": origin, "cell_size": cell_size, "column_pitch": column_pitch, "row_height": row_height}


func _grid_cell_rect(row: int, column: int, column_count: int, metrics: Dictionary) -> Rect2:
	var item_index := _item_index_for_grid_cell(row, column, column_count)
	if item_index >= 0:
		return _visual_cell_rect(item_index)
	var origin: Vector2 = metrics.origin
	var cell_size: Vector2 = metrics.cell_size
	var column_pitch: float = metrics.column_pitch
	var row_height: float = metrics.row_height
	return Rect2(origin + Vector2(column * column_pitch, row * row_height), cell_size)


func _cell_frame_rect(cell: Rect2) -> Rect2:
	return cell.grow(-CELL_FRAME_INSET)


func _item_index_for_grid_cell(row: int, column: int, column_count: int) -> int:
	var index := row * column_count + column
	return index if index >= 0 and index < item_count else -1

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
	_queue_overlay_redraw()
	var panel: Node = _get_inventory_panel()
	if panel == null:
		return
	if idx >= 0 and panel.has_method("show_inventory_item_detail"):
		panel.show_inventory_item_detail(inventory_source, idx, get_global_mouse_position())
	elif panel.has_method("hide_detail_popup"):
		panel.hide_detail_popup()

func _on_mouse_exited() -> void:
	_hovered_index = -1
	_queue_overlay_redraw()
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
