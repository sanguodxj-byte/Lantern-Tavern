class_name SkillDragList
extends ItemList

@export var drag_source: String = "available_skills"

func _ready() -> void:
	allow_reselect = true

func _get_drag_data(_at_position: Vector2) -> Variant:
	var panel := _get_equipment_panel()
	if panel == null:
		return null
	var data: Dictionary = panel.collect_skill_drag_payload(drag_source)
	if data.is_empty():
		return null
	var preview := Label.new()
	preview.text = tr(String(data.get("id", "Skill")))
	set_drag_preview(preview)
	return data

# 拖放接口：仅当本列表用作技能槽展示（drag_source == "skill_slots"）时生效。
# 当 drag_source == "available_skills" 时不接收拖放，仅作为拖拽源。
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if drag_source != "skill_slots":
		return false
	var panel := _get_equipment_panel()
	return panel != null and panel.can_drop_skill_slot_data(_slot_index_at_position(at_position), data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if drag_source != "skill_slots":
		return
	var panel := _get_equipment_panel()
	if panel != null:
		panel.drop_skill_slot_data(_slot_index_at_position(at_position), data)

func _slot_index_at_position(at_position: Vector2) -> int:
	var item_index := get_item_at_position(at_position, true)
	if item_index < 0:
		var selected := get_selected_items()
		if selected.is_empty():
			return -1
		item_index = selected[0]
	var meta = get_item_metadata(item_index)
	return int(meta) if typeof(meta) == TYPE_INT else -1

func _get_equipment_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("collect_skill_drag_payload"):
			return node
		node = node.get_parent()
	return null
