class_name EquipmentSlotDropButton
extends Button

@export var slot_kind: String = "weapon"
@export var slot_index: int = 0
@export var armor_slot: String = ""

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel := _get_equipment_panel()
	return panel != null and panel.can_drop_equipment_slot_data(slot_kind, slot_index, armor_slot, data)

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

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
