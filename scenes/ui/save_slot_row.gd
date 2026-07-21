extends Control
class_name SaveSlotRow

## 存档槽位行组件（由 SaveLoadPanel 实例化使用）。
## 显示单个槽位的存档信息，提供存档/读档/删除操作。

@onready var slot_label: Label = %SlotLabel
@onready var info_label: Label = %InfoLabel
@onready var timestamp_label: Label = %TimestampLabel
@onready var action_btn: Button = %ActionBtn
@onready var delete_btn: Button = %DeleteBtn

var slot_index: int = 0
var has_data: bool = false

signal slot_activated
signal delete_requested

const SAVE_MODE: int = 0
const LOAD_MODE: int = 1

func _ready() -> void:
	action_btn.pressed.connect(_on_action_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)

func set_slot_index(index: int) -> void:
	slot_index = index
	slot_label.text = tr("Slot %d") % (index + 1)

func set_info(info: Dictionary) -> void:
	has_data = bool(info.get("exists", false))
	if has_data:
		var save_name: String = String(info.get("save_name", ""))
		var player_name: String = String(info.get("player_name", ""))
		var day: int = int(info.get("day", 0))
		var gold: int = int(info.get("gold", 0))
		var display_name := save_name if not save_name.is_empty() else player_name
		if display_name.is_empty():
			display_name = tr("Unknown Hero")
		info_label.text = "%s  |  %s %d  |  %s %d" % [display_name, tr("Day"), day, tr("Gold"), gold]
		timestamp_label.text = String(info.get("timestamp", ""))
		timestamp_label.visible = true
		delete_btn.visible = true
	else:
		info_label.text = tr("Empty Slot")
		timestamp_label.visible = false
		delete_btn.visible = false

func set_mode(mode: int) -> void:
	match mode:
		SAVE_MODE:
			action_btn.text = tr("Save") if not has_data else tr("Overwrite")
		LOAD_MODE:
			action_btn.text = tr("Load")
			action_btn.disabled = not has_data

func _on_action_pressed() -> void:
	slot_activated.emit()

func _on_delete_pressed() -> void:
	delete_requested.emit()
