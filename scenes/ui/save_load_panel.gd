extends Control
class_name SaveLoadPanel

## 存档/读档面板组件。
## 三槽位 UI，可工作于 SaveMode（存档）或 LoadMode（读档）。
## 由主菜单、暂停菜单等场景实例化使用。

enum Mode { SAVE, LOAD }

@onready var title_label: Label = %TitleLabel
@onready var slot_container: VBoxContainer = %SlotContainer
@onready var back_btn: Button = %BackBtn

var mode: int = Mode.SAVE
var slot_rows: Array = []

signal back_pressed
signal slot_action_completed(action: String, slot_index: int)

const SLOT_ROW_SCENE := preload("res://scenes/ui/save_slot_row.tscn")

func _ready() -> void:
	back_btn.pressed.connect(_on_back_pressed)
	_refresh_slots()

func set_mode(new_mode: int) -> void:
	mode = new_mode
	if is_node_ready():
		_refresh_slots()

## 刷新所有槽位显示。
func refresh() -> void:
	_refresh_slots()

func _refresh_slots() -> void:
	_update_title()
	# 清除旧行
	for child in slot_container.get_children():
		child.queue_free()
	slot_rows.clear()
	# 获取存档信息
	var infos := SaveManager.get_all_slot_infos()
	# 创建新行
	for i in range(SaveManager.SLOT_COUNT):
		var row: Control = SLOT_ROW_SCENE.instantiate()
		slot_container.add_child(row)
		slot_rows.append(row)
		var info: Dictionary = infos[i]
		_setup_row(row, i, info)

func _update_title() -> void:
	match mode:
		Mode.SAVE:
			title_label.text = tr("Save Game")
		Mode.LOAD:
			title_label.text = tr("Load Game")

func _setup_row(row: Control, slot_index: int, info: Dictionary) -> void:
	row.set_slot_index(slot_index)
	row.set_info(info)
	row.set_mode(mode)
	row.slot_activated.connect(_on_slot_activated.bind(slot_index))
	row.delete_requested.connect(_on_delete_requested.bind(slot_index))

func _on_slot_activated(slot_index: int) -> void:
	match mode:
		Mode.SAVE:
			var ok := SaveManager.save_to_slot(slot_index)
			if ok:
				slot_action_completed.emit("save", slot_index)
				_refresh_slots()
		Mode.LOAD:
			if SaveManager.has_save(slot_index):
				var ok := SaveManager.load_from_slot(slot_index)
				if ok:
					slot_action_completed.emit("load", slot_index)

func _on_delete_requested(slot_index: int) -> void:
	SaveManager.delete_save(slot_index)
	slot_action_completed.emit("delete", slot_index)
	_refresh_slots()

func _on_back_pressed() -> void:
	back_pressed.emit()
