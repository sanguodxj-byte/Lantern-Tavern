class_name SkillSlotDropButton
extends Button

const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")

@export var slot_index: int = 0

func _ready() -> void:
	pressed.connect(_on_pressed)

func _get_drag_data(_at_position: Vector2) -> Variant:
	var panel := _get_equipment_panel()
	if panel == null or not panel.has_method("collect_skill_slot_drag_payload"):
		return null
	var data: Dictionary = panel.collect_skill_slot_drag_payload(slot_index)
	if data.is_empty():
		return null
	# 拖拽预览显示技能图标（SkillIcons autoload），避免纯文字展示。
	var skill_id := String(data.get("id", ""))
	var icon: Texture2D = null
	var icons: Node = Engine.get_main_loop().root.get_node_or_null("SkillIcons")
	if icons != null and icons.has_method("get_icon"):
		icon = icons.get_icon(skill_id) as Texture2D
	set_drag_preview(DETAIL_POPUP_SCRIPT.build_drag_preview(icon, tr(skill_id)))
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel := _get_equipment_panel()
	return panel != null and panel.can_drop_skill_slot_data(slot_index, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var panel := _get_equipment_panel()
	if panel != null:
		panel.drop_skill_slot_data(slot_index, data)

func _on_pressed() -> void:
	var panel := _get_equipment_panel()
	if panel != null and panel.has_method("select_skill_slot"):
		panel.select_skill_slot(slot_index)

func _get_equipment_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("can_drop_skill_slot_data"):
			return node
		node = node.get_parent()
	return null
