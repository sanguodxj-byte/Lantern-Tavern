class_name PixelBar
extends Control

## 像素风格数值条（血量 / 蓝量通用）。
## 使用纯色方块绘制，关闭抗锯齿，配合 ark-pixel 字体实现像素风。

@export var bar_color: Color = Color.RED
@export var bg_color: Color = Color(0.035, 0.037, 0.043, 0.94)
@export var frame_color: Color = Color(0.72, 0.43, 0.20, 0.96)
@export var label_text: String = ""
@export var show_numeric: bool = true
@export var pixel_size: int = 4  # 每个"像素方块"的屏幕像素边长

var _current: int = 0
var _max: int = 100
var _display_ratio: float = 1.0  # 平滑插值用

@onready var _label: Label = get_node_or_null("Label") as Label


func _ready() -> void:
	custom_minimum_size = Vector2(320, 36)
	if _label:
		_label.add_theme_font_override("font", _pixel_font())
		_label.add_theme_font_size_override("font_size", 18)


func _pixel_font() -> Font:
	return load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf") as Font


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var frame_w := 2

	# 外框
	draw_rect(rect, frame_color, false, frame_w)

	# 背景
	var bg_rect := rect.grow_individual(-frame_w, -frame_w, -frame_w, -frame_w)
	draw_rect(bg_rect, bg_color, true)

	# 填充
	var fill_w := int(bg_rect.size.x * _display_ratio)
	# 对齐到 pixel_size 网格
	fill_w = floori(fill_w / pixel_size) * pixel_size
	if fill_w > 0:
		var fill_rect := Rect2(bg_rect.position, Vector2(fill_w, bg_rect.size.y))
		# 像素风：用方块逐块绘制边缘锯齿
		draw_rect(fill_rect, bar_color, true)
		# 顶部高光（1px 亮色）
		var hl := bar_color.lightened(0.3)
		draw_rect(
			Rect2(fill_rect.position, Vector2(fill_rect.size.x, pixel_size)),
			hl, true
		)
		# 稀疏的阶梯纹理让大色块保留体素/像素质感，同时不干扰读数。
		var texture_color := bar_color.darkened(0.16)
		texture_color.a = 0.55
		for x in range(pixel_size * 4, fill_w, pixel_size * 6):
			var block_y := pixel_size * (2 if int(x / pixel_size) % 2 == 0 else 4)
			draw_rect(Rect2(bg_rect.position + Vector2(x, block_y), Vector2(pixel_size * 2, pixel_size)), texture_color, true)


func set_values(current: int, maximum: int) -> void:
	current = maxi(current, 0)
	maximum = maxi(maximum, 1)
	# 值未变时跳过字符串格式化与重绘，避免每帧无意义开销
	if current == _current and maximum == _max:
		return
	_current = current
	_max = maximum
	var target := float(_current) / float(_max)
	_display_ratio = target
	if show_numeric and _label:
		_label.text = "%s  %d / %d" % [label_text, _current, _max]
	queue_redraw()


func set_label(text: String) -> void:
	label_text = text
	if _label:
		_label.text = "%s  %d / %d" % [label_text, _current, _max]
	queue_redraw()
