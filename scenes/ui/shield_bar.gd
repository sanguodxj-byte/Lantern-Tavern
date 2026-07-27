extends Control

## 护盾条 UI 组件 —— 与 HP/MP 像素条同款视觉：相同尺寸 (320×36)、
## 相同外框颜色、相同内部阶梯纹理、相同文字样式。
## 两种类型：
##   - MAGIC（法术/技能护盾）：蓝色，来自 damage_absorb buff
##   - PHYSICAL（持盾格挡）：金属灰白色，来自盾牌装备耐久
##
## 唯一的样式差异：填充色用护盾专属颜色，文字前缀区分。
## 视觉框架、字体、阶梯纹理完全复刻 PixelBar，保证尺寸/样式对齐。

enum ShieldType { MAGIC, PHYSICAL }

const COLOR_MAGIC := Color(0.32, 0.58, 1.0, 1.0)
const COLOR_PHYSICAL := Color(0.78, 0.74, 0.62, 1.0)
## 与 HP/MP 像素条严格统一：宽 320、高 36、2px 外框
const BAR_SIZE := Vector2(320, 36)
const FRAME_W := 2
const PIXEL_SIZE := 4
const FADE_DURATION := 0.25
const SLIDE_OFFSET := -12.0

@export var shield_type: int = ShieldType.MAGIC

var _current: int = 0
var _max: int = 100
var _display_ratio: float = 0.0
var _active: bool = false
var _fade_t: float = 0.0  # 0=隐藏, 1=完全显示
var _bar_color: Color = COLOR_MAGIC
var _label: Label
var _base_y: float = 0.0  # 原始布局位置，用于滑入动画基准


func _ready() -> void:
	custom_minimum_size = BAR_SIZE
	_bar_color = COLOR_MAGIC if shield_type == ShieldType.MAGIC else COLOR_PHYSICAL
	_base_y = position.y
	modulate.a = 0.0
	position.y = _base_y + SLIDE_OFFSET
	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 10.0
	_label.offset_top = 8.0
	_label.offset_right = -10.0
	_label.offset_bottom = -8.0
	_label.add_theme_font_override("font", load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"))
	_label.add_theme_font_size_override("font_size", 18)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _process(delta: float) -> void:
	# 渐入/渐出动画
	var target_t := 1.0 if _active else 0.0
	if _fade_t < target_t:
		_fade_t = minf(_fade_t + delta / FADE_DURATION, target_t)
	elif _fade_t > target_t:
		_fade_t = maxf(_fade_t - delta / FADE_DURATION, target_t)
	modulate.a = _fade_t
	# 从上方滑入
	position.y = _base_y + SLIDE_OFFSET * (1.0 - _fade_t)
	queue_redraw()


func _draw() -> void:
	if _fade_t <= 0.01:
		return
	var rect := Rect2(Vector2.ZERO, size)
	# 与 PixelBar 一致：HP/MP 用的外框色 (0.72, 0.43, 0.20, 0.96) 是暖橙，
	# 护盾条也用同款外框色，让四个条看起来出自同一 UI 组件族
	var frame_color := Color(0.72, 0.43, 0.20, 0.96)
	# 外框
	draw_rect(rect, frame_color, false, FRAME_W)
	# 背景
	var bg_rect := rect.grow_individual(-FRAME_W, -FRAME_W, -FRAME_W, -FRAME_W)
	draw_rect(bg_rect, Color(0.035, 0.037, 0.043, 0.94), true)
	# 填充
	var fill_w := int(bg_rect.size.x * _display_ratio)
	# 对齐到 4px 像素网格（与 PixelBar 一致）
	fill_w = floori(fill_w / PIXEL_SIZE) * PIXEL_SIZE
	if fill_w > 0:
		var fill_rect := Rect2(bg_rect.position, Vector2(fill_w, bg_rect.size.y))
		# 像素风：用方块逐块绘制边缘锯齿
		draw_rect(fill_rect, _bar_color, true)
		# 顶部高光（4px 亮色，与 PixelBar 一致）
		var hl := _bar_color.lightened(0.3)
		draw_rect(
			Rect2(fill_rect.position, Vector2(fill_rect.size.x, PIXEL_SIZE)),
			hl, true
		)
		# 阶梯纹理（与 PixelBar 完全一致：每隔 24px 画 8×4 暗块，
		# 错位 2 行让大色块保留体素/像素质感，同时不干扰读数）
		var texture_color := _bar_color.darkened(0.16)
		texture_color.a = 0.55
		for x in range(PIXEL_SIZE * 4, fill_w, PIXEL_SIZE * 6):
			var block_y := PIXEL_SIZE * (2 if int(x / PIXEL_SIZE) % 2 == 0 else 4)
			draw_rect(Rect2(bg_rect.position + Vector2(x, block_y), Vector2(PIXEL_SIZE * 2, PIXEL_SIZE)), texture_color, true)


## 设置护盾值并激活显示
func set_values(current: int, maximum: int) -> void:
	_current = maxi(current, 0)
	_max = maxi(maximum, 1)
	_display_ratio = float(_current) / float(_max)
	_active = _current > 0
	if _label:
		var prefix := "SHIELD" if shield_type == ShieldType.PHYSICAL else "M.SHIELD"
		_label.text = "%s  %d / %d" % [prefix, _current, _max]
		_label.modulate = Color(1, 1, 1, 0.9)
	queue_redraw()


## 强制隐藏（无护盾时）
func deactivate() -> void:
	_active = false
	_current = 0
	_display_ratio = 0.0
	if _label:
		_label.text = ""
	queue_redraw()


## 当前是否处于激活状态
func is_active() -> bool:
	return _active


## 当前渐入进度（0~1）
func get_fade_progress() -> float:
	return _fade_t
