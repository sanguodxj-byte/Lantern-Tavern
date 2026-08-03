class_name PixelBar
extends Control

## 厚重像素资源条（生命 / 蓝量）。
## 数据接口保持 set_values() 不变；绘制采用切角仪表底板、左侧铭牌、
## 双层金属框、4px 分段填充与硬边高光，不使用渐变或抗锯齿。

enum BarKind { HEALTH, MANA }

const BAR_SIZE := Vector2(320, 40)
const PIXEL := 4
const PLATE_WIDTH := 48
const CUT := 8
const OUTER := Color("#090A0F")
const FRAME_DARK := Color("#342B2B")
const FRAME_LIGHT := Color("#A06737")
const WELL := Color("#171820")
const WELL_DARK := Color("#0C0D12")

@export var bar_kind: int = BarKind.HEALTH
@export var bar_color: Color = Color("#D33A32")
@export var bg_color: Color = WELL
@export var frame_color: Color = FRAME_LIGHT
@export var label_text: String = ""
@export var show_numeric: bool = true
@export var pixel_size: int = PIXEL

var _current: int = 0
var _max: int = 100
var _display_ratio: float = 1.0

@onready var _label: Label = get_node_or_null("Label") as Label


func _ready() -> void:
	custom_minimum_size = BAR_SIZE
	_apply_kind_defaults()
	if _label:
		_label.add_theme_font_override("font", _pixel_font())
		_label.add_theme_font_size_override("font_size", 18)
		_label.add_theme_color_override("font_color", Color("#FFF2D5"))
		_label.add_theme_color_override("font_shadow_color", Color("#08090D"))
		_label.add_theme_constant_override("shadow_offset_x", 2)
		_label.add_theme_constant_override("shadow_offset_y", 2)
		_label.position.x = PLATE_WIDTH + 10
		_label.size.x = maxf(0.0, size.x - PLATE_WIDTH - 18)
	queue_redraw()


func _pixel_font() -> Font:
	return load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf") as Font


func _apply_kind_defaults() -> void:
	if bar_kind == BarKind.MANA:
		bar_color = Color("#2585D8")
		frame_color = Color("#537FA8")
		if label_text.is_empty():
			label_text = "MP"
	else:
		bar_color = Color("#D33A32")
		frame_color = Color("#A06737")
		if label_text.is_empty():
			label_text = "HP"


func _draw() -> void:
	var bar_size := Vector2(size.x, maxf(size.y, BAR_SIZE.y))
	var plate := PackedVector2Array([
		Vector2(CUT, 0), Vector2(bar_size.x - CUT, 0), Vector2(bar_size.x - 1, CUT),
		Vector2(bar_size.x - 1, bar_size.y - CUT), Vector2(bar_size.x - CUT, bar_size.y - 1),
		Vector2(CUT, bar_size.y - 1), Vector2(0, bar_size.y - CUT), Vector2(0, CUT),
	])
	draw_colored_polygon(plate, OUTER)

	var inner := Rect2(Vector2(4, 4), bar_size - Vector2(8, 8))
	draw_rect(inner, FRAME_DARK, true)
	draw_rect(Rect2(inner.position + Vector2(2, 2), inner.size - Vector2(4, 4)), frame_color, true)

	# 左侧类型铭牌，刻出 H/M 几何徽记。
	var plate_rect := Rect2(Vector2(6, 6), Vector2(PLATE_WIDTH - 10, bar_size.y - 12))
	draw_rect(plate_rect, frame_color.darkened(0.46), true)
	draw_rect(Rect2(plate_rect.position + Vector2(2, 2), plate_rect.size - Vector2(4, 4)), FRAME_DARK, true)
	_draw_kind_glyph(plate_rect)

	var well_rect := Rect2(Vector2(PLATE_WIDTH, 8), Vector2(bar_size.x - PLATE_WIDTH - 10, bar_size.y - 16))
	draw_rect(well_rect, WELL_DARK, true)
	draw_rect(Rect2(well_rect.position + Vector2(2, 2), well_rect.size - Vector2(4, 4)), bg_color, true)

	var fill_rect := Rect2(well_rect.position + Vector2(4, 4), well_rect.size - Vector2(8, 8))
	var fill_w := floori((fill_rect.size.x * clampf(_display_ratio, 0.0, 1.0)) / float(PIXEL)) * PIXEL
	if fill_w > 0:
		var value_rect := Rect2(fill_rect.position, Vector2(fill_w, fill_rect.size.y))
		draw_rect(value_rect, bar_color.darkened(0.20), true)
		draw_rect(Rect2(value_rect.position + Vector2(0, PIXEL), Vector2(fill_w, maxf(0.0, value_rect.size.y - PIXEL * 2))), bar_color, true)
		draw_rect(Rect2(value_rect.position, Vector2(fill_w, PIXEL)), bar_color.lightened(0.34), true)
		draw_rect(Rect2(value_rect.position + Vector2(0, value_rect.size.y - PIXEL), Vector2(fill_w, PIXEL)), bar_color.darkened(0.42), true)
		_draw_fill_texture(value_rect)

	# 固定分段刻度覆盖在填充与空槽上，保证读数有机械感。
	var segment_step := 28
	for x in range(int(fill_rect.position.x) + segment_step, int(fill_rect.end.x), segment_step):
		draw_rect(Rect2(Vector2(x, fill_rect.position.y), Vector2(2, fill_rect.size.y)), WELL_DARK, true)

	# 顶部铆钉与右端状态刻线。
	for x in [10, int(bar_size.x) - 14]:
		draw_rect(Rect2(Vector2(x, 2), Vector2(4, 4)), frame_color.lightened(0.25), true)
	for y in [12, 20, 28]:
		draw_rect(Rect2(Vector2(bar_size.x - 6, y), Vector2(4, 2)), frame_color.lightened(0.15), true)


func _draw_kind_glyph(rect: Rect2) -> void:
	var color := bar_color.lightened(0.42)
	var x := rect.position.x + 10
	var y := rect.position.y + 7
	if bar_kind == BarKind.MANA:
		# 阶梯水晶/法力滴。
		draw_rect(Rect2(Vector2(x + 8, y), Vector2(4, 4)), color, true)
		draw_rect(Rect2(Vector2(x + 4, y + 4), Vector2(12, 4)), color, true)
		draw_rect(Rect2(Vector2(x, y + 8), Vector2(20, 8)), color, true)
		draw_rect(Rect2(Vector2(x + 4, y + 16), Vector2(12, 4)), color, true)
		draw_rect(Rect2(Vector2(x + 8, y + 20), Vector2(4, 4)), color, true)
	else:
		# 像素心脏，不依赖字体。
		draw_rect(Rect2(Vector2(x, y + 4), Vector2(8, 12)), color, true)
		draw_rect(Rect2(Vector2(x + 12, y + 4), Vector2(8, 12)), color, true)
		draw_rect(Rect2(Vector2(x + 4, y), Vector2(12, 20)), color, true)
		draw_rect(Rect2(Vector2(x + 8, y + 20), Vector2(4, 4)), color, true)


func _draw_fill_texture(rect: Rect2) -> void:
	var texture_color := bar_color.darkened(0.34)
	for x in range(int(rect.position.x) + 12, int(rect.end.x) - 4, 24):
		var row_y := rect.position.y + (8 if int(x / 24) % 2 == 0 else 12)
		draw_rect(Rect2(Vector2(x, row_y), Vector2(8, 4)), texture_color, true)


func set_values(current: int, maximum: int) -> void:
	current = maxi(current, 0)
	maximum = maxi(maximum, 1)
	if current == _current and maximum == _max:
		return
	_current = current
	_max = maximum
	_display_ratio = float(_current) / float(_max)
	if show_numeric and _label:
		_label.text = "%s  %d / %d" % [label_text, _current, _max]
	queue_redraw()


func set_label(text: String) -> void:
	label_text = text
	if _label:
		_label.text = "%s  %d / %d" % [label_text, _current, _max]
	queue_redraw()
