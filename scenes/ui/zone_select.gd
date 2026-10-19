extends UiScreen
## 区域地图选择页面。
## 地图只承载展示与选区交互；区域名称、描述、难度和颜色统一来自 ZoneManager。

const UI_ROUTES := preload("res://globals/ui/ui_route_catalog.gd")

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


func _ready() -> void:
	super._ready()
	add_to_group("modal_gameplay_blocker")
	_zone_manager = _find_zone_manager()
	zone_map_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	title.text = tr("Select Expedition Zone")
	selected_status.text = tr("Select Expedition Zone")
	start_btn.text = tr("Start Expedition")
	start_btn.disabled = true
	start_btn.pressed.connect(_on_start_pressed)
	back_btn.text = tr("Back")
	back_btn.pressed.connect(_on_back_pressed)
	zone_hotspots.connect("zone_hovered", Callable(self, "_on_hotspot_preview"))
	zone_hotspots.connect("zone_exited", Callable(self, "_on_hotspot_exited"))
	zone_hotspots.connect("zone_pressed", Callable(self, "_on_zone_pressed"))
	_populate_zones()


func _populate_zones() -> void:
	if _zone_manager == null or not _zone_manager.has_method("all_zones"):
		return

	var zones: Array = _zone_manager.all_zones()
	var zone_colors: Dictionary = {}
	for raw_zone_id in zones:
		var zone_id := int(raw_zone_id)
		zone_colors[zone_id] = _zone_manager.get_zone_color(zone_id)
	zone_hotspots.call("configure", zones, zone_colors)

	if not zones.is_empty():
		_preview_zone = int(zones[0])
		_render_zone(_preview_zone)


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
	zone_hotspots.call("set_selected_zone", zone_id)
	_render_zone(zone_id)


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
