extends Control

## 单个 Buff 图标显示。
## 显示 buff 颜色方块 + 剩余时间文字。
## 当剩余时间 ≤ BLINK_THRESHOLD 时开始淡出淡入闪烁提醒。

const BLINK_THRESHOLD := 3.0
const BLINK_SPEED := 6.0
const ICON_SIZE := 36

## buff 类型 → 显示颜色
const BUFF_COLORS := {
	"def_and_evade_up": Color(0.3, 0.6, 1.0),
	"slow_and_haste": Color(0.9, 0.7, 0.2),
	"damage_absorb": Color(0.68, 0.70, 0.74),
	"poison": Color(0.4, 0.8, 0.2),
	"stun": Color(1.0, 0.9, 0.3),
}

var buff_type: String = ""
var remaining: float = 0.0
var _blink_time: float = 0.0

var _icon_rect: ColorRect
var _timer_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE + 14)
	_build_ui()


func _build_ui() -> void:
	_icon_rect = ColorRect.new()
	_icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon_rect.size = Vector2(ICON_SIZE, ICON_SIZE)
	add_child(_icon_rect)

	_timer_label = Label.new()
	_timer_label.position = Vector2(0, ICON_SIZE + 1)
	_timer_label.size = Vector2(ICON_SIZE, 13)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 11)
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
		_icon_rect.color = BUFF_COLORS.get(type, Color(0.7, 0.7, 0.7))


## 判断当前是否处于闪烁状态
func is_blinking() -> bool:
	return remaining <= BLINK_THRESHOLD and remaining > 0.0
