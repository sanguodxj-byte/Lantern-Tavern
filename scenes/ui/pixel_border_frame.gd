class_name PixelBorderFrame
extends Control

## Non-layout decorative frame for dark-fantasy UI surfaces.
## The source texture is sampled from the equipment screen's parchment texture,
## then brightened and tinted only along the frame ring. The center remains
## transparent, so this node never obscures content or changes container layout.

@export var border_texture: Texture2D
@export var target_path: NodePath
@export var border_inset := 4.0
@export var border_width := 8.0
@export var corner_size := 18.0
@export var texture_tint := Color(1.04, 0.74, 0.32, 0.16)
@export var outer_line_color := Color(0.42, 0.25, 0.12, 0.92)
@export var inner_line_color := Color(0.20, 0.12, 0.07, 0.78)
@export var highlight_color := Color(0.62, 0.38, 0.15, 0.48)
@export var shadow_color := Color(0.025, 0.014, 0.01, 0.94)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(not target_path.is_empty())
	if not target_path.is_empty():
		call_deferred("_sync_to_target")
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _process(_delta: float) -> void:
	_sync_to_target()


func _sync_to_target() -> void:
	if target_path.is_empty():
		return
	var target := get_node_or_null(target_path) as Control
	if target == null or not is_instance_valid(target):
		visible = false
		return
	visible = target.visible and target.is_visible_in_tree()
	if not visible:
		return
	var target_rect := target.get_global_rect()
	global_position = target_rect.position
	size = target_rect.size


func _draw() -> void:
	var inset := maxf(0.0, border_inset)
	var outer := Rect2(Vector2(inset, inset), size - Vector2.ONE * (inset * 2.0))
	if outer.size.x <= 4.0 or outer.size.y <= 4.0:
		return
	var width := minf(border_width, minf(outer.size.x, outer.size.y) * 0.25)
	_draw_texture_ring(outer, width)

	# A dark under-stroke prevents the bright texture from dissolving into the UI.
	draw_rect(outer.grow(1.0), shadow_color, false, 2.0)
	draw_rect(outer, outer_line_color, false, 1.0)
	var inner := outer.grow(-width)
	draw_rect(inner, inner_line_color, false, 1.0)
	draw_line(inner.position + Vector2(2.0, 1.0), Vector2(inner.end.x - 2.0, inner.position.y + 1.0), highlight_color, 1.0)
	draw_line(inner.position + Vector2(1.0, 2.0), Vector2(inner.position.x + 1.0, inner.end.y - 2.0), highlight_color.darkened(0.28), 1.0)
	_draw_corners(outer)


func _draw_texture_ring(rect: Rect2, width: float) -> void:
	if border_texture == null:
		return
	var texture_width := float(border_texture.get_width())
	var texture_height := float(border_texture.get_height())
	if texture_width <= 0.0 or texture_height <= 0.0:
		return
	var source_band_x := minf(64.0, texture_width)
	var source_band_y := minf(64.0, texture_height)
	var middle_height := maxf(1.0, rect.size.y - width * 2.0)
	var bottom_band := Rect2(0.0, texture_height - source_band_y, texture_width, source_band_y)
	var bottom_corner_band := Rect2(0.0, texture_height - source_band_y, source_band_x, source_band_y)

	# Reuse the darkened bottom edge of the equipment background as the
	# material sample for every side, keeping the frame visually unified.
	draw_texture_rect_region(border_texture, Rect2(rect.position, Vector2(rect.size.x, width)), bottom_band, texture_tint)
	draw_texture_rect_region(border_texture, Rect2(Vector2(rect.position.x, rect.end.y - width), Vector2(rect.size.x, width)), bottom_band, texture_tint.darkened(0.18))
	draw_texture_rect_region(border_texture, Rect2(Vector2(rect.position.x, rect.position.y + width), Vector2(width, middle_height)), bottom_corner_band, texture_tint.darkened(0.10))
	draw_texture_rect_region(border_texture, Rect2(Vector2(rect.end.x - width, rect.position.y + width), Vector2(width, middle_height)), bottom_corner_band, texture_tint.darkened(0.28))


func _draw_corners(rect: Rect2) -> void:
	var extent := minf(corner_size, minf(rect.size.x, rect.size.y) * 0.22)
	_draw_corner(rect.position, 1.0, 1.0, extent)
	_draw_corner(Vector2(rect.end.x, rect.position.y), -1.0, 1.0, extent)
	_draw_corner(Vector2(rect.position.x, rect.end.y), 1.0, -1.0, extent)
	_draw_corner(rect.end, -1.0, -1.0, extent)


func _draw_corner(origin: Vector2, x_sign: float, y_sign: float, extent: float) -> void:
	var shadow_points := PackedVector2Array([
		origin + Vector2(0.0, y_sign * extent),
		origin,
		origin + Vector2(x_sign * extent, 0.0),
	])
	var highlight_points := PackedVector2Array([
		origin + Vector2(0.0, y_sign * (extent - 3.0)),
		origin + Vector2(x_sign * 3.0, y_sign * 3.0),
		origin + Vector2(x_sign * (extent - 3.0), 0.0),
	])
	draw_polyline(shadow_points, shadow_color, 4.0, true)
	draw_polyline(highlight_points, highlight_color, 2.0, true)

	var jewel_center := origin + Vector2(x_sign * 7.0, y_sign * 7.0)
	draw_rect(Rect2(jewel_center - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), shadow_color, true)
	draw_rect(Rect2(jewel_center - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), outer_line_color, true)
	draw_rect(Rect2(jewel_center - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), highlight_color, true)
