extends Control

## 单个 Buff 图标显示。
## 显示 buff 颜色方块 + 剩余时间文字。
## 当剩余时间 ≤ BLINK_THRESHOLD 时开始淡出淡入闪烁提醒。
## 加大尺寸：64×80 (icon 64 + timer 16)，比 HP/MP 略小但视觉重量足够。

const BLINK_THRESHOLD := 3.0
const BLINK_SPEED := 6.0
const ICON_SIZE := 64
const TIMER_HEIGHT := 20
const FONT_SIZE_NAME := 16
const FONT_SIZE_TIMER := 15

## buff 类型 → 显示颜色
const BUFF_COLORS := {
	"def_and_evade_up": Color(0.3, 0.6, 1.0),
	"slow_and_haste": Color(0.9, 0.7, 0.2),
	"damage_absorb": Color(0.68, 0.70, 0.74),
	"poison": Color(0.4, 0.8, 0.2),
	"stun": Color(1.0, 0.9, 0.3),
	"burn": Color(0.95, 0.4, 0.2),
	"haste": Color(0.9, 0.7, 0.2),
	"shield_aura": Color(0.55, 0.72, 0.95),
}
const BUFF_ICON_NAMES := {
	"def_and_evade_up": "DEF",
	"slow_and_haste": "HASTE",
	"damage_absorb": "ABS",
	"poison": "PSN",
	"stun": "STUN",
	"burn": "BURN",
	"haste": "HASTE",
	"shield_aura": "AURA",
}

var buff_type: String = ""
var remaining: float = 0.0
var _blink_time: float = 0.0

var _icon_rect: ColorRect
var _border_rect: ColorRect
var _name_label: Label
var _timer_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE + TIMER_HEIGHT)
	_build_ui()


func _build_ui() -> void:
	# 外框（2px 边，与 HP/MP 像素条统一风格 — 暖橙外框色）
	_border_rect = ColorRect.new()
	_border_rect.color = Color(0.72, 0.43, 0.20, 0.96)
	_border_rect.size = Vector2(ICON_SIZE, ICON_SIZE)
	_border_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border_rect.show_behind_parent = true
	add_child(_border_rect)

	_icon_rect = ColorRect.new()
	_icon_rect.position = Vector2(2, 2)
	_icon_rect.size = Vector2(ICON_SIZE - 4, ICON_SIZE - 4)
	_icon_rect.color = Color(0.15, 0.16, 0.18, 1.0)
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_rect)

	# 中心缩写（叠加在 icon_rect 上）
	_name_label = Label.new()
	_name_label.anchor_left = 0.0
	_name_label.anchor_top = 0.0
	_name_label.anchor_right = 1.0
	_name_label.anchor_bottom = 1.0
	_name_label.offset_left = 2.0
	_name_label.offset_top = 0.0
	_name_label.offset_right = -2.0
	_name_label.offset_bottom = 0.0
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"))
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE_NAME)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_name_label.add_theme_constant_override("outline_size", 2)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_timer_label = Label.new()
	_timer_label.position = Vector2(0, ICON_SIZE + 1)
	_timer_label.size = Vector2(ICON_SIZE, TIMER_HEIGHT - 1)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_override("font", load("res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"))
	_timer_label.add_theme_font_size_override("font_size", FONT_SIZE_TIMER)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.82, 1.0))
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_timer_label.add_theme_constant_override("outline_size", 2)
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timer_label)


func _process(delta: float) -> void:
	if remaining <= BLINK_THRESHOLD and remaining > 0.0:
		_blink_time += delta
		var alpha: float = 0.25 + 0.75 * abs(sin(_blink_time * BLINK_SPEED))
		modulate.a = alpha
	else:
		modulate.a = 1.0
	if _timer_label:
		if remaining > 0.0:
			_timer_label.text = "%.1f" % remaining
		else:
			_timer_label.text = ""


## 设置 buff 信息并刷新显示
func setup(type: String, remain: float) -> void:
	buff_type = type
	remaining = remain
	if _icon_rect:
		var c: Color = BUFF_COLORS.get(type, Color(0.7, 0.7, 0.7))
		_icon_rect.color = c
	if _name_label:
		_name_label.text = BUFF_ICON_NAMES.get(type, type.substr(0, 4).to_upper())


## 判断当前是否处于闪烁状态
func is_blinking() -> bool:
	return remaining <= BLINK_THRESHOLD and remaining > 0.0
