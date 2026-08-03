extends UiScreen
## 区域地图选择页面。
## 地图只承载展示与选区交互；区域名称、描述、难度和颜色统一来自 ZoneManager。

const UI_ROUTES := preload("res://globals/ui/ui_route_catalog.gd")

const HOTSPOT_SIZE := Vector2(148.0, 44.0)
const HOTSPOT_POSITIONS: Dictionary = {
	0: Vector2(0.50, 0.52), # 幽暗地牢：地图中心的石砌入口
	1: Vector2(0.21, 0.36), # 寂静之森：左上林地
	2: Vector2(0.21, 0.78), # 深邃洞窟：左下洞穴
	3: Vector2(0.79, 0.37), # 荒芜墓园：右上墓园
	4: Vector2(0.79, 0.78), # 熔岩火山：右下火山
	5: Vector2(0.50, 0.28), # 古代遗迹：上方遗迹
}

@onready var zone_map_texture: TextureRect = %ZoneMapTexture
@onready var zone_hotspots: Control = %ZoneHotspots
@onready var zone_name: Label = %ZoneName
@onready var zone_description: Label = %ZoneDescription
@onready var difficulty_label: Label = %DifficultyLabel
@onready var zone_accent: ColorRect = %ZoneAccent
@onready var selected_status: Label = %SelectedStatus
@onready var back_btn: Button = %BackBtn
@onready var start_btn: Button = %StartBtn
@onready var title: Label = %Title

var _selected_zone: int = -1
var _preview_zone: int = -1
var _zone_manager: Node
var _hotspot_buttons: Array[Button] = []


func _ready() -> void:
	super._ready()
	add_to_group("character_panel")
	_zone_manager = _find_zone_manager()
	zone_map_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	title.text = tr("Select Expedition Zone")
	selected_status.text = tr("Select Expedition Zone")
	start_btn.text = tr("Start Expedition")
	start_btn.disabled = true
	start_btn.pressed.connect(_on_start_pressed)
	back_btn.text = tr("Back")
	back_btn.pressed.connect(_on_back_pressed)
	_populate_zones()


func _populate_zones() -> void:
	for child in zone_hotspots.get_children():
		child.queue_free()
	_hotspot_buttons.clear()
	if _zone_manager == null or not _zone_manager.has_method("all_zones"):
		return

	var zones: Array = _zone_manager.all_zones()
	for index in range(zones.size()):
		var zone_id := int(zones[index])
		var hotspot := _create_hotspot(zone_id, index)
		zone_hotspots.add_child(hotspot)
		_hotspot_buttons.append(hotspot)

	if not zones.is_empty():
		_preview_zone = int(zones[0])
		_render_zone(_preview_zone)


func _create_hotspot(zone_id: int, index: int) -> Button:
	var button := Button.new()
	button.name = "ZoneHotspot%d" % zone_id
	button.custom_minimum_size = HOTSPOT_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.toggle_mode = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text = _zone_manager.get_zone_name(zone_id)
	button.tooltip_text = _zone_manager.get_zone_desc(zone_id)
	button.add_theme_font_size_override("font_size", 15)
	button.set_meta("zone_id", zone_id)
	button.set_meta("zone_index", index)
	button.pressed.connect(_on_zone_pressed.bind(zone_id))
	button.mouse_entered.connect(_on_hotspot_preview.bind(zone_id))
	button.focus_entered.connect(_on_hotspot_preview.bind(zone_id))
	button.mouse_exited.connect(_on_hotspot_exited.bind(zone_id))
	button.focus_exited.connect(_on_hotspot_exited.bind(zone_id))

	var anchor: Vector2 = HOTSPOT_POSITIONS.get(zone_id, _fallback_position(index))
	button.anchor_left = anchor.x
	button.anchor_top = anchor.y
	button.anchor_right = anchor.x
	button.anchor_bottom = anchor.y
	button.offset_left = -HOTSPOT_SIZE.x * 0.5
	button.offset_top = -HOTSPOT_SIZE.y * 0.5
	button.offset_right = HOTSPOT_SIZE.x * 0.5
	button.offset_bottom = HOTSPOT_SIZE.y * 0.5
	_apply_hotspot_style(button, false, false)
	return button


func _fallback_position(index: int) -> Vector2:
	var column := index % 3
	var row := index / 3
	return Vector2(0.2 + float(column) * 0.3, 0.36 + float(row) * 0.4)


func _on_hotspot_preview(zone_id: int) -> void:
	_preview_zone = zone_id
	_render_zone(zone_id)


func _on_hotspot_exited(zone_id: int) -> void:
	if _preview_zone != zone_id:
		return
	if _selected_zone >= 0:
		_preview_zone = _selected_zone
		_render_zone(_selected_zone)


func _on_zone_pressed(zone_id: int) -> void:
	_selected_zone = zone_id
	_preview_zone = zone_id
	start_btn.disabled = false
	selected_status.text = _zone_manager.get_zone_name(zone_id)
	_render_zone(zone_id)
	for button in _hotspot_buttons:
		var is_selected := int(button.get_meta("zone_id", -1)) == zone_id
		button.button_pressed = is_selected
		_apply_hotspot_style(button, is_selected, false)


func _apply_hotspot_style(button: Button, selected: bool, hovered: bool) -> void:
	var zone_id := int(button.get_meta("zone_id", -1))
	var zone_color: Color = _zone_manager.get_zone_color(zone_id) if _zone_manager != null else Color(0.55, 0.38, 0.2)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.035, 0.026, 0.023, 0.94)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = zone_color.darkened(0.18)
	normal.corner_detail = 1
	normal.anti_aliasing = false
	normal.content_margin_left = 7.0
	normal.content_margin_right = 7.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = zone_color.darkened(0.35)
	hover.border_color = zone_color.lightened(0.32)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = zone_color.darkened(0.08)
	pressed.border_width_left = 3
	pressed.border_width_top = 3
	pressed.border_width_right = 3
	pressed.border_width_bottom = 3
	pressed.border_color = Color(1.0, 0.77, 0.32, 1.0)
	var focus := pressed.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.17, 0.12, 0.07, 0.96)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", normal)
	if selected:
		button.modulate = Color(1.08, 1.02, 0.9, 1.0)
	elif hovered:
		button.modulate = Color(1.05, 1.0, 0.9, 1.0)
	else:
		button.modulate = Color.WHITE


func _render_zone(zone_id: int) -> void:
	if _zone_manager == null:
		return
	zone_name.text = _zone_manager.get_zone_name(zone_id)
	zone_description.text = _zone_manager.get_zone_desc(zone_id)
	var difficulty := clampi(int(_zone_manager.get_zone_difficulty(zone_id)), 1, 6)
	var filled := "◆".repeat(difficulty)
	var empty := "◇".repeat(6 - difficulty)
	difficulty_label.text = "%s%s   %d/6" % [filled, empty, difficulty]
	var color: Color = _zone_manager.get_zone_color(zone_id)
	zone_accent.color = color
	zone_name.add_theme_color_override("font_color", color.lightened(0.35))
	difficulty_label.add_theme_color_override("font_color", color.lightened(0.2))


func get_selected_zone() -> int:
	return _selected_zone


func _on_start_pressed() -> void:
	if _selected_zone < 0:
		return
	if _zone_manager != null:
		_zone_manager.set_zone(_selected_zone)
	if TavernManager:
		TavernManager.start_expedition()
	else:
		var game_state: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
		if game_state != null and game_state.has_method("reset_dungeon_floor"):
			game_state.reset_dungeon_floor()
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _on_back_pressed() -> void:
	var world := _find_world()
	if world != null and world.has_method("close_overlay"):
		world.call("close_overlay")
	else:
		request_navigation(UI_ROUTES.MAIN_MENU)


func _on_cancel_input() -> void:
	_on_back_pressed()


func _find_zone_manager() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop.has_method("get_root"):
		return null
	return main_loop.get_root().get_node_or_null("ZoneManager")


func _find_world() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("load_space") and node.has_method("open_zone_select"):
			return node
		node = node.get_parent()
	return null
