class_name EquipmentSlotDropButton
extends Button

const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")

@export var slot_kind: String = "weapon"
@export var slot_index: int = 0
@export var armor_slot: String = ""

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _get_drag_data(_at_position: Vector2) -> Variant:
	var panel := _get_equipment_panel()
	if panel == null or not panel.has_method("collect_equipment_slot_drag_payload"):
		return null
	var data: Dictionary = panel.collect_equipment_slot_drag_payload(slot_kind, slot_index, armor_slot)
	if data.is_empty():
		return null
	# 拖拽预览必须显示装备图标（禁止纯文字）。
	var icon: Texture2D = DETAIL_POPUP_SCRIPT.icon_for_equipment_id(String(data.get("id", "")))
	set_drag_preview(DETAIL_POPUP_SCRIPT.build_drag_preview(icon, "x1"))
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel := _get_equipment_panel()
	return panel != null and panel.can_drop_equipment_slot_data(slot_kind, slot_index, armor_slot, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var panel := _get_equipment_panel()
	if panel != null:
		panel.drop_equipment_slot_data(slot_kind, slot_index, armor_slot, data)
		panel._ensure_mouse_visible()

func _on_mouse_entered() -> void:
	var panel := _get_equipment_panel()
	if panel != null and panel.has_method("show_equipment_slot_detail"):
		panel.show_equipment_slot_detail(slot_kind, slot_index, armor_slot, get_global_mouse_position())

func _on_mouse_exited() -> void:
	var panel := _get_equipment_panel()
	if panel != null and panel.has_method("hide_detail_popup"):
		panel.hide_detail_popup()

func _get_equipment_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("can_drop_equipment_slot_data"):
			return node
		node = node.get_parent()
	return null
