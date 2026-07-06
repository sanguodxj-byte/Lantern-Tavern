class_name InteractionHintBase
extends PanelContainer
## 交互提示悬浮窗基类。
## 提供通用功能：屏幕定位、淡入/即隐动画、统一样式。
## 子类通过 _build_content() 自定义额外内容，通过 show_hint() 显示。

const FONT_PATH := "res://assets/fonts/ark-pixel-12px-proportional-zh_cn.ttf"
## 悬浮窗相对射线命中点（物体表面）的偏移：正 X = 物体右侧，负 Y = 垂直居中略偏上。
## 所有交互提示统一显示在物体右侧（不再有底部提示）。
const HINT_OFFSET := Vector2(28, -22)
const FADE_IN_DURATION := 0.12

var _content_container: VBoxContainer
var _hint_label: Label
var _fade_tween: Tween

func _ready() -> void:
	_build_ui()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200

func _build_ui() -> void:
	if _hint_label != null:
		return
	# 统一样式：深色半透明背景 + 金色边框 + 圆角
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.094, 0.078, 0.145, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.95, 0.72, 0.35, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	_content_container = VBoxContainer.new()
	_content_container.custom_minimum_size = Vector2(140, 0)
	_content_container.add_theme_constant_override("separation", 4)
	add_child(_content_container)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_container.add_child(_hint_label)

	# 子类可添加额外内容
	_build_content()

## 子类重写以添加额外内容节点（如图标行、进度条等）
func _build_content() -> void:
	pass

## 显示悬浮窗。text 为提示文本，screen_position 为目标物体的屏幕坐标。
## auto_position=false 时不自动定位（由调用方手动设置 global_position，
## 例如把拾取提示放到详情悬浮窗正下方）。
## 仅在从隐藏切换到显示时播放淡入动画；准星持续停留在同一物体上时
## 每帧仅更新文本/位置，不再重置透明度，避免提示闪烁/不可见。
func show_hint(text: String, screen_position: Vector2, auto_position := true) -> void:
	if text.is_empty():
		hide_hint()
		return
	var was_visible := visible
	_hint_label.text = text
	visible = true
	if not was_visible:
		_play_fade_in()
	if auto_position:
		_position_near(screen_position)

## 立即隐藏悬浮窗（视角离开即退出，无渐隐延迟）
func hide_hint() -> void:
	visible = false
	modulate.a = 0.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

## 将悬浮窗定位到屏幕坐标附近，自动钳制到视口范围内
func _position_near(screen_position: Vector2) -> void:
	var target := screen_position + HINT_OFFSET
	await get_tree().process_frame
	var viewport_size := get_viewport_rect().size
	var popup_size := size
	target.x = clampf(target.x, 12.0, maxf(12.0, viewport_size.x - popup_size.x - 12.0))
	target.y = clampf(target.y, 12.0, maxf(12.0, viewport_size.y - popup_size.y - 12.0))
	global_position = target

func _play_fade_in() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION)

## 当前是否正在显示
func is_hint_visible() -> bool:
	return visible
