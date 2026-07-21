class_name WeaponHandLinkVisual
extends Control

## Small pixel-art connector between the main-hand and off-hand slots.
## It is a visual relationship marker, not an interactive drop target.

const LINK_SHADOW := Color(0.08, 0.045, 0.025, 0.9)
const LINK_COLOR := Color(0.78, 0.56, 0.30, 0.95)
const LINK_HIGHLIGHT := Color(0.96, 0.78, 0.46, 0.9)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "主手 / 副手"
	queue_redraw()

func _draw() -> void:
	var center := Vector2(round(size.x * 0.5), round(size.y * 0.5))
	_draw_chain_link(center + Vector2(-2, -3), -1)
	_draw_chain_link(center + Vector2(2, 3), 1)
	# A short dark interlock seam keeps the two rings readable against the
	# parchment texture without introducing a filled rectangle.
	draw_line(center + Vector2(-4, 0), center + Vector2(4, 0), LINK_SHADOW, 3.0, false)
	draw_line(center + Vector2(-3, 0), center + Vector2(3, 0), LINK_HIGHLIGHT, 1.0, false)

func _draw_chain_link(center: Vector2, direction: int) -> void:
	var points := PackedVector2Array([
		center + Vector2(-4, -4),
		center + Vector2(3, -4),
		center + Vector2(5, -2),
		center + Vector2(5, 2),
		center + Vector2(3, 4),
		center + Vector2(-4, 4),
		center + Vector2(-5, 2),
		center + Vector2(-5, -2),
		center + Vector2(-4, -4),
	])
	var shadow_points := PackedVector2Array()
	for point in points:
		shadow_points.append(point + Vector2(1, 1))
	draw_polyline(shadow_points, LINK_SHADOW, 3.0, false)
	draw_polyline(points, LINK_COLOR, 2.0, false)
	# One-pixel highlight on the outer edge gives the chain the same raised
	# metal treatment as the slot borders.
	var highlight_start := center + Vector2(-3, -4 if direction < 0 else 3)
	var highlight_end := center + Vector2(2, -4 if direction < 0 else 3)
	draw_line(highlight_start, highlight_end, LINK_HIGHLIGHT, 1.0, false)
