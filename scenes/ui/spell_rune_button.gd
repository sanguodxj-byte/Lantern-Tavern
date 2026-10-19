class_name SpellRuneButton
extends Button
## 技能界面（SpellInterface）的符文按钮：符文列表项与符文槽位共用。
## - 列表按钮：rune_id 非空、spell_slot_index = -1 → 拖拽源（符文拖出装备）。
## - 槽位按钮：spell_slot_index >= 0 → 拖拽源（移动）+ 拖放目标（拖入装备）。
## 拖拽数据格式与装备面板一致（{"kind":"rune","id":...}），跨界面互通。

## 按钮代表的符文 id（空 = 空槽）。
var rune_id: String = ""
## 所属法术槽位；-1 表示右侧符文列表项（非槽位）。
var spell_slot_index: int = -1
## 槽位内的符文序号（0..2）。
var rune_index: int = 0


func _get_drag_data(_at_position: Vector2) -> Variant:
	if rune_id.is_empty():
		return null
	var host := _host()
	if host == null or not host.has_method("rune_button_get_drag_data"):
		return null
	return host.rune_button_get_drag_data(self)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if spell_slot_index < 0:
		return false
	var host := _host()
	if host == null or not host.has_method("rune_button_can_drop"):
		return false
	return host.rune_button_can_drop(self, data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if spell_slot_index < 0:
		return
	var host := _host()
	if host == null or not host.has_method("rune_button_drop"):
		return
	host.rune_button_drop(self, data)


func _host() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("rune_button_can_drop"):
			return node
		node = node.get_parent()
	return null
