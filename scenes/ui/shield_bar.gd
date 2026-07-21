extends Control

## 护盾条 UI 组件 —— 在 HP 条上方显示，生效时从上方渐入。
## 两种类型：
##   - MAGIC（法术/技能护盾）：蓝色，来自 damage_absorb buff
##   - PHYSICAL（持盾格挡）：金属灰白色，来自盾牌装备耐久

enum ShieldType { MAGIC, PHYSICAL }

const COLOR_MAGIC := Color(0.3, 0.55, 1.0)
const COLOR_PHYSICAL := Color(0.75, 0.72, 0.68)
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
	custom_minimum_size = Vector2(280, 22)
	_bar_color = COLOR_MAGIC if shield_type == ShieldType.MAGIC else COLOR_PHYSICAL
	_base_y = position.y
	modulate.a = 0.0
	position.y = _base_y + SLIDE_OFFSET
	_label = Label.new()
	_label.offset_left = 8.0
	_label.offset_top = 3.0
	_label.offset_right = 272.0
	_label.offset_bottom = 19.0
	_label.add_theme_font_size_override("font_size", 12)
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
	var frame_w := 2
	var frame_color := _bar_color.darkened(0.3)
	# 外框
	draw_rect(rect, frame_color, false, frame_w)
	# 背景
	var bg_rect := rect.grow_individual(-frame_w, -frame_w, -frame_w, -frame_w)
	draw_rect(bg_rect, Color(0.08, 0.082, 0.09, 0.85), true)
	# 填充
	var fill_w := int(bg_rect.size.x * _display_ratio)
	fill_w = floori(fill_w / 4) * 4
	if fill_w > 0:
		var fill_rect := Rect2(bg_rect.position, Vector2(fill_w, bg_rect.size.y))
		draw_rect(fill_rect, _bar_color, true)
		# 顶部高光
		draw_rect(
			Rect2(fill_rect.position, Vector2(fill_rect.size.x, 4)),
			_bar_color.lightened(0.3), true
		)


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
