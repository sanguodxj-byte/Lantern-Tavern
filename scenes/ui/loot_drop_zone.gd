extends Control
## 通用拖放区域脚本。
## 附加到任意 Control 节点使其成为战利品拖放目标。
## 通过 set_meta("drop_panel", panel) 和 set_meta("zone_id", id) 配置。
## 面板需实现 can_drop_to_zone(zone_id, data) -> bool 和 drop_to_zone(zone_id, data) -> void。

const ACCEPT_COLOR := Color(1.0, 0.78, 0.32, 1.0)
const REJECT_COLOR := Color(0.96, 0.35, 0.3, 1.0)
const ACCEPT_MODULATE := Color(1.08, 0.97, 0.78, 1.0)
const REJECT_MODULATE := Color(0.92, 0.62, 0.58, 1.0)

var _drag_feedback_active := false
var _base_modulate := Color.WHITE


func _ready() -> void:
	_base_modulate = modulate
	mouse_exited.connect(_clear_drop_feedback)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_feedback()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel = get_meta("drop_panel", null)
	if panel == null or not is_instance_valid(panel):
		_clear_drop_feedback()
		return false
	if not (data is Dictionary):
		_show_drop_feedback(false)
		return false
	var zone_id := String(get_meta("zone_id", ""))
	var accepted := bool(panel.can_drop_to_zone(zone_id, data as Dictionary))
	_show_drop_feedback(accepted)
	return accepted


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var panel = get_meta("drop_panel", null)
	if panel == null or not is_instance_valid(panel):
		_clear_drop_feedback()
		return
	if data is Dictionary:
		var zone_id := String(get_meta("zone_id", ""))
		panel.drop_to_zone(zone_id, data as Dictionary)
	_clear_drop_feedback()


func _show_drop_feedback(accepted: bool) -> void:
	_drag_feedback_active = true
	modulate = ACCEPT_MODULATE if accepted else REJECT_MODULATE
	var color := ACCEPT_COLOR if accepted else REJECT_COLOR
	var class_name_text := get_class()
	if class_name_text == "ItemList":
		add_theme_color_override("guide_color", color)
	elif class_name_text == "Button":
		add_theme_color_override("font_color", color)
	else:
		add_theme_constant_override("h_separation", 6 if accepted else 2)
		add_theme_constant_override("v_separation", 6 if accepted else 2)


func _clear_drop_feedback() -> void:
	if not _drag_feedback_active:
		return
	_drag_feedback_active = false
	modulate = _base_modulate
	var class_name_text := get_class()
	if class_name_text == "ItemList":
		remove_theme_color_override("guide_color")
	elif class_name_text == "Button":
		remove_theme_color_override("font_color")
	else:
		remove_theme_constant_override("h_separation")
		remove_theme_constant_override("v_separation")
