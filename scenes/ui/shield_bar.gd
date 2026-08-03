extends Control

## 护盾资源条：与 HP/MP 共用厚重像素仪表语言，但使用独立徽记和护盾框饰。
## 仅改变绘制；set_values/deactivate/is_active 与 CombatHUD 的既有调用保持兼容。

enum ShieldType { MAGIC, PHYSICAL }

const BAR_SIZE := Vector2(320, 40)
const PIXEL := 4
const PLATE_WIDTH := 48
const CUT := 8
const OUTER := Color("#090A0F")
const FRAME_DARK := Color("#272A32")
const WELL := Color("#14161E")
const WELL_DARK := Color("#090B10")
const FADE_DURATION := 0.25
const SLIDE_OFFSET := -12.0
const COLOR_MAGIC := Color("#318CDE")
const COLOR_PHYSICAL := Color("#C5C0AB")

@export var shield_type: int = ShieldType.MAGIC

var _current: int = 0
var _max: int = 100
var _display_ratio: float = 0.0
var _active: bool = false
var _fade_t: float = 0.0
var _bar_color: Color = COLOR_MAGIC
var _frame_color: Color = Color("#527FA6")
var _label: Label
var _base_y: float = 0.0


func _ready() -> void:
	custom_minimum_size = BAR_SIZE
	_bar_color = COLOR_MAGIC if shield_type == ShieldType.MAGIC else COLOR_PHYSICAL
	_frame_color = Color("#527FA6") if shield_type == ShieldType.MAGIC else Color("#8B909B")
	_base_y = position.y
	modulate.a = 0.0
	position.y = _base_y + SLIDE_OFFSET
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = PLATE_WIDTH + 10
	_label.offset_top = 9
	_label.offset_right = -14
	_label.offset_bottom = -7
	_label.add_theme_font_override("font", load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"))
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color("#EFF7FF"))
	_label.add_theme_color_override("font_shadow_color", Color("#08090D"))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	queue_redraw()


func _process(delta: float) -> void:
	var target_t := 1.0 if _active else 0.0
	if _fade_t < target_t:
		_fade_t = minf(_fade_t + delta / FADE_DURATION, target_t)
	elif _fade_t > target_t:
		_fade_t = maxf(_fade_t - delta / FADE_DURATION, target_t)
	modulate.a = _fade_t
	position.y = _base_y + SLIDE_OFFSET * (1.0 - _fade_t)
	queue_redraw()


func _draw() -> void:
	if _fade_t <= 0.01:
		return
	var bar_size := Vector2(size.x, maxf(size.y, BAR_SIZE.y))
	var plate := PackedVector2Array([
		Vector2(CUT, 0), Vector2(bar_size.x - CUT, 0), Vector2(bar_size.x - 1, CUT),
		Vector2(bar_size.x - 1, bar_size.y - CUT), Vector2(bar_size.x - CUT, bar_size.y - 1),
		Vector2(CUT, bar_size.y - 1), Vector2(0, bar_size.y - CUT), Vector2(0, CUT),
	])
	draw_colored_polygon(plate, OUTER)
	var inner := Rect2(Vector2(4, 4), bar_size - Vector2(8, 8))
	draw_rect(inner, FRAME_DARK, true)
	draw_rect(Rect2(inner.position + Vector2(2, 2), inner.size - Vector2(4, 4)), _frame_color, true)

	var plate_rect := Rect2(Vector2(6, 6), Vector2(PLATE_WIDTH - 10, bar_size.y - 12))
	draw_rect(plate_rect, _frame_color.darkened(0.50), true)
	draw_rect(Rect2(plate_rect.position + Vector2(2, 2), plate_rect.size - Vector2(4, 4)), FRAME_DARK, true)
	_draw_shield_glyph(plate_rect)

	var well_rect := Rect2(Vector2(PLATE_WIDTH, 8), Vector2(bar_size.x - PLATE_WIDTH - 10, bar_size.y - 16))
	draw_rect(well_rect, WELL_DARK, true)
	draw_rect(Rect2(well_rect.position + Vector2(2, 2), well_rect.size - Vector2(4, 4)), WELL, true)
	var fill_rect := Rect2(well_rect.position + Vector2(4, 4), well_rect.size - Vector2(8, 8))
	var fill_w := floori((fill_rect.size.x * clampf(_display_ratio, 0.0, 1.0)) / float(PIXEL)) * PIXEL
	if fill_w > 0:
		var value_rect := Rect2(fill_rect.position, Vector2(fill_w, fill_rect.size.y))
		draw_rect(value_rect, _bar_color.darkened(0.24), true)
		draw_rect(Rect2(value_rect.position + Vector2(0, PIXEL), Vector2(fill_w, maxf(0.0, value_rect.size.y - PIXEL * 2))), _bar_color, true)
		draw_rect(Rect2(value_rect.position, Vector2(fill_w, PIXEL)), _bar_color.lightened(0.34), true)
		draw_rect(Rect2(value_rect.position + Vector2(0, value_rect.size.y - PIXEL), Vector2(fill_w, PIXEL)), _bar_color.darkened(0.44), true)
		for x in range(int(value_rect.position.x) + 12, int(value_rect.end.x) - 4, 24):
			var row_y := value_rect.position.y + (8 if int(x / 24) % 2 == 0 else 12)
			draw_rect(Rect2(Vector2(x, row_y), Vector2(8, 4)), _bar_color.darkened(0.36), true)
	for x in range(int(fill_rect.position.x) + 28, int(fill_rect.end.x), 28):
		draw_rect(Rect2(Vector2(x, fill_rect.position.y), Vector2(2, fill_rect.size.y)), WELL_DARK, true)
	for x in [10, int(bar_size.x) - 14]:
		draw_rect(Rect2(Vector2(x, 2), Vector2(4, 4)), _frame_color.lightened(0.28), true)


func _draw_shield_glyph(rect: Rect2) -> void:
	var color := _bar_color.lightened(0.38)
	var x := rect.position.x + 8
	var y := rect.position.y + 5
	if shield_type == ShieldType.MAGIC:
		# 奥术六角盾印。
		for segment in [Rect2(x + 8, y, 8, 4), Rect2(x + 4, y + 4, 16, 4), Rect2(x, y + 8, 24, 8), Rect2(x + 4, y + 16, 16, 4), Rect2(x + 8, y + 20, 8, 4)]:
			draw_rect(segment, color, true)
		draw_rect(Rect2(x + 9, y + 9, 6, 6), Color("#E0F5FF"), true)
	else:
		# 金属塔盾与横向束带。
		draw_rect(Rect2(x + 4, y, 16, 4), color, true)
		draw_rect(Rect2(x, y + 4, 24, 16), color, true)
		draw_rect(Rect2(x + 4, y + 20, 16, 4), color, true)
		draw_rect(Rect2(x, y + 10, 24, 4), Color("#F4F1DA"), true)


func set_values(current: int, maximum: int) -> void:
	_current = maxi(current, 0)
	_max = maxi(maximum, 1)
	_display_ratio = float(_current) / float(_max)
	_active = _current > 0
	if _label:
		var prefix := "A.SHIELD" if shield_type == ShieldType.MAGIC else "P.SHIELD"
		_label.text = "%s  %d / %d" % [prefix, _current, _max]
	queue_redraw()


func deactivate() -> void:
	_active = false
	_current = 0
	_display_ratio = 0.0
	if _label:
		_label.text = ""
	queue_redraw()


func is_active() -> bool:
	return _active


func get_fade_progress() -> float:
	return _fade_t
