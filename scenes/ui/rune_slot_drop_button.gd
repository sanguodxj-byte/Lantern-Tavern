class_name RuneSlotDropButton
extends Button

@export var skill_slot_index: int = 0
@export var rune_socket_index: int = 0

func _ready() -> void:
	pressed.connect(_on_pressed)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel := _get_equipment_panel()
	return panel != null and panel.can_drop_rune_socket_data(skill_slot_index, rune_socket_index, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var panel := _get_equipment_panel()
	if panel != null:
		panel.drop_rune_socket_data(skill_slot_index, rune_socket_index, data)

func _on_pressed() -> void:
	var panel := _get_equipment_panel()
	if panel != null and panel.has_method("select_skill_slot"):
		panel.select_skill_slot(skill_slot_index)

func _get_equipment_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("can_drop_rune_socket_data"):
			return node
		node = node.get_parent()
	return null
