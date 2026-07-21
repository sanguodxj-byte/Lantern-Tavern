extends Control

## Render-only layer for InventoryDragList.
##
## ItemList paints its native icons after its own _draw() method. Keeping the
## custom grid in a child Control makes the grid the final paint layer while
## mouse input remains on the ItemList itself.

var inventory_list: Node
var _last_item_count := -1
var _last_size := Vector2(-1.0, -1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(inventory_list):
		return
	var current_size: Vector2 = inventory_list.get("size")
	var current_item_count: int = int(inventory_list.get("item_count"))
	if current_size != _last_size or current_item_count != _last_item_count:
		_last_size = current_size
		_last_item_count = current_item_count
		queue_redraw()


func _draw() -> void:
	if is_instance_valid(inventory_list) and inventory_list.has_method("_draw_inventory_overlay"):
		inventory_list._draw_inventory_overlay(self)
