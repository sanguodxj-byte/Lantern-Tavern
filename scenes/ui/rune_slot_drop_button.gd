class_name RuneSlotDropButton
extends Button

const RD := preload("res://globals/combat/rune_data.gd")

@export var skill_slot_index: int = 0
@export var rune_socket_index: int = 0

## 当前槽位上镶嵌的符文 id（空字符串 = 未镶嵌）。
## 由 TavernEquipmentPanel._refresh_rune_slots() 刷新。
var rune_id: String = ""

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

## 自定义富文本 tooltip：仅展示符文基础信息。
## 符文之语参与信息由装备面板在槽位下方独立展示。
## 当 tooltip_text 非空时 Godot 自动调用此方法。
func _make_custom_tooltip(_for_text: String) -> Object:
	if rune_id.is_empty():
		return null
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.custom_minimum_size = Vector2(300, 0)
	label.text = _build_tooltip_bbcode()
	return label

func _build_tooltip_bbcode() -> String:
	var rune: Dictionary = RD.get_rune(rune_id)
	if rune.is_empty():
		return rune_id

	var runic := String(rune.get("runic_name", ""))
	var desc := String(rune.get("desc", ""))
	var rarity := String(rune.get("rarity", "common"))
	var rune_color := RD.get_rune_color(rune_id)

	var lines: Array = []
	lines.append("[b][color=%s]%s[/color][/b]" % [rune_color, runic])
	lines.append("[color=#888888]稀有度: %s[/color]" % _rarity_label(rarity))
	if not desc.is_empty():
		lines.append("")
		lines.append(desc)

	return "\n".join(lines)

func _rarity_color(rarity: String) -> String:
	match rarity:
		"common": return "#FFFFFF"
		"uncommon": return "#6CFF6C"
		"rare": return "#FFB347"
		"epic": return "#C77DFF"
		"legendary": return "#FFD700"
		_: return "#FFFFFF"

func _rarity_label(rarity: String) -> String:
	match rarity:
		"common": return "普通"
		"uncommon": return "精良"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		_: return rarity

func _get_equipment_panel() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("can_drop_rune_socket_data"):
			return node
		node = node.get_parent()
	return null
