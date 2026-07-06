extends Control
## 区域选择界面。玩家从四个探险区域中选定一个，再进入地牢。

const ZONE_BUTTON_SCENE := "res://scenes/ui/zone_button.tscn"

@onready var zone_list: VBoxContainer = $Panel/ScrollContainer/ZoneList
@onready var back_btn: Button = $Panel/BackBtn
@onready var start_btn: Button = $Panel/StartBtn
@onready var title: Label = $Panel/Title

var _selected_zone: int = -1

func _ready() -> void:
	add_to_group("character_panel")
	title.text = tr("Select Expedition Zone")
	start_btn.text = tr("Start Expedition")
	start_btn.disabled = true
	start_btn.pressed.connect(_on_start_pressed)
	back_btn.text = tr("Back")
	back_btn.pressed.connect(_on_back_pressed)
	_populate_zones()

func _populate_zones() -> void:
	var zm: Node = Engine.get_main_loop().root.get_node_or_null("ZoneManager")
	if zm == null:
		return
	for zone_id in zm.all_zones():
		var btn: Button = Button.new()
		btn.text = "%s\n%s" % [zm.get_zone_name(zone_id), zm.get_zone_desc(zone_id)]
		btn.custom_minimum_size = Vector2(600, 100)
		btn.add_theme_font_size_override("font_size", 24)
		var color: Color = zm.get_zone_color(zone_id)
		btn.modulate = Color(1, 1, 1)
		# 用元数据传递 zone_id
		btn.set_meta("zone_id", zone_id)
		btn.pressed.connect(_on_zone_selected.bind(btn))
		zone_list.add_child(btn)

func _on_zone_selected(btn: Button) -> void:
	_selected_zone = btn.get_meta("zone_id", -1)
	# 视觉反馈：淡化未选中的按钮
	for child in zone_list.get_children():
		child.modulate.a = 0.4 if child != btn else 1.0
	start_btn.disabled = false

func _on_start_pressed() -> void:
	if _selected_zone < 0:
		return
	var zm: Node = Engine.get_main_loop().root.get_node_or_null("ZoneManager")
	if zm != null:
		zm.set_zone(_selected_zone)
	if TavernManager:
		TavernManager.start_expedition()
	else:
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")

func _on_back_pressed() -> void:
	var world := _find_world()
	if world != null and world.has_method("close_overlay"):
		world.call("close_overlay")
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _find_world() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("load_space") and node.has_method("open_zone_select"):
			return node
		node = node.get_parent()
	return null
