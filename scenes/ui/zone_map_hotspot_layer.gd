extends Control
class_name ZoneMapHotspotLayer

## 地图区域交互层。区域由归一化多边形定义，地图贴图本身不承载文字按钮。

signal zone_hovered(zone_id: int)
signal zone_exited(zone_id: int)
signal zone_pressed(zone_id: int)

var _zone_region_polygons: Dictionary = {
	# 西南海岸的低难度入口区域。
	0: PackedVector2Array([
		Vector2(0.05, 0.64), Vector2(0.19, 0.61), Vector2(0.36, 0.72),
		Vector2(0.37, 0.93), Vector2(0.18, 0.97), Vector2(0.07, 0.87),
	]),
	# 西部河湖森林低地。
	1: PackedVector2Array([
		Vector2(0.04, 0.17), Vector2(0.31, 0.14), Vector2(0.46, 0.28),
		Vector2(0.47, 0.46), Vector2(0.36, 0.63), Vector2(0.20, 0.66),
		Vector2(0.07, 0.60), Vector2(0.03, 0.38),
	]),
	# 北部山脊与洞窟。
	2: PackedVector2Array([
		Vector2(0.27, 0.04), Vector2(0.62, 0.03), Vector2(0.72, 0.19),
		Vector2(0.63, 0.34), Vector2(0.49, 0.39), Vector2(0.32, 0.31),
		Vector2(0.24, 0.18),
	]),
	# 东部干旱盆地。
	3: PackedVector2Array([
		Vector2(0.62, 0.30), Vector2(0.95, 0.26), Vector2(0.98, 0.57),
		Vector2(0.84, 0.66), Vector2(0.63, 0.57), Vector2(0.58, 0.42),
	]),
	# 东南火山半岛。
	4: PackedVector2Array([
		Vector2(0.60, 0.57), Vector2(0.84, 0.59), Vector2(0.98, 0.55),
		Vector2(0.99, 0.91), Vector2(0.78, 0.99), Vector2(0.61, 0.84),
	]),
	# 东北高地遗迹。
	5: PackedVector2Array([
		Vector2(0.62, 0.05), Vector2(0.94, 0.06), Vector2(0.98, 0.25),
		Vector2(0.84, 0.37), Vector2(0.66, 0.31), Vector2(0.57, 0.20),
	]),
}

var _zone_landmark_points: Dictionary = {
	0: Vector2(0.17, 0.80),
	1: Vector2(0.25, 0.47),
	2: Vector2(0.50, 0.18),
	3: Vector2(0.78, 0.47),
	4: Vector2(0.81, 0.76),
	5: Vector2(0.78, 0.16),
}

const DEFAULT_ZONE_COLOR := Color(0.55, 0.38, 0.20, 1.0)
const NORMAL_DASH_LENGTH := 7.0
const HOVER_DASH_LENGTH := 8.0

var _zone_ids: Array[int] = []
var _zone_colors: Dictionary = {}
var _hovered_zone: int = -1
var _selected_zone: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_exited.connect(_on_mouse_exited)


func configure(zone_ids: Array, zone_colors: Dictionary) -> void:
	_zone_ids.clear()
	for raw_zone_id in zone_ids:
		var zone_id := int(raw_zone_id)
		if _zone_region_polygons.has(zone_id):
			_zone_ids.append(zone_id)
	_zone_colors = zone_colors.duplicate()
	_hovered_zone = -1
	_selected_zone = -1
	queue_redraw()


func get_zone_ids() -> Array[int]:
	return _zone_ids.duplicate()


func get_zone_landmark_point(zone_id: int) -> Vector2:
	return _zone_landmark_points.get(zone_id, Vector2(-1.0, -1.0))


func get_zone_at_normalized(normalized_point: Vector2) -> int:
	for zone_id in _zone_ids:
		var polygon: PackedVector2Array = _zone_region_polygons.get(zone_id, PackedVector2Array())
		if Geometry2D.is_point_in_polygon(normalized_point, polygon):
			return zone_id
	return -1


func set_selected_zone(zone_id: int) -> void:
	_selected_zone = zone_id if _zone_ids.has(zone_id) else -1
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hovered_zone(_zone_at_position(event.position))
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var zone_id := _zone_at_position(mouse_event.position)
			if zone_id >= 0:
				zone_pressed.emit(zone_id)
				accept_event()


func _zone_at_position(position: Vector2) -> int:
	if size.x <= 0.0 or size.y <= 0.0:
		return -1
	return get_zone_at_normalized(Vector2(
		clampf(position.x / size.x, 0.0, 1.0),
		clampf(position.y / size.y, 0.0, 1.0),
	))


func _update_hovered_zone(zone_id: int) -> void:
	if zone_id == _hovered_zone:
		return
	if _hovered_zone >= 0:
		zone_exited.emit(_hovered_zone)
	_hovered_zone = zone_id
	if _hovered_zone >= 0:
		zone_hovered.emit(_hovered_zone)
	queue_redraw()


func _on_mouse_exited() -> void:
	_update_hovered_zone(-1)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for zone_id in _zone_ids:
		var normalized_polygon: PackedVector2Array = _zone_region_polygons.get(zone_id, PackedVector2Array())
		if normalized_polygon.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for normalized_point in normalized_polygon:
			polygon.append(Vector2(normalized_point.x * size.x, normalized_point.y * size.y))

		var zone_color: Color = _zone_colors.get(zone_id, DEFAULT_ZONE_COLOR)
		var is_selected := zone_id == _selected_zone
		var is_hovered := zone_id == _hovered_zone
		if is_selected or is_hovered:
			var fill_alpha := 0.16 if is_selected else 0.10
			draw_colored_polygon(polygon, Color(zone_color.r, zone_color.g, zone_color.b, fill_alpha))

		var edge_color := Color(zone_color.r, zone_color.g, zone_color.b, 0.32)
		var edge_width := 2.0
		var dash_length := NORMAL_DASH_LENGTH
		if is_selected:
			edge_color = Color(1.0, 0.76, 0.30, 0.98)
			edge_width = 4.0
			dash_length = HOVER_DASH_LENGTH
		elif is_hovered:
			edge_color = zone_color.lightened(0.38)
			edge_color.a = 0.96
			edge_width = 3.0
			dash_length = HOVER_DASH_LENGTH

		for point_index in range(polygon.size()):
			var from := polygon[point_index]
			var to := polygon[(point_index + 1) % polygon.size()]
			draw_dashed_line(from, to, edge_color, edge_width, dash_length, true)
