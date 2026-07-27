extends Control
## 通用拖放区域脚本。
## 附加到任意 Control 节点使其成为装备拖放目标。
## 通过 set_meta("drop_panel", panel) 和 set_meta("zone_id", id) 配置。
## 面板需实现 can_drop_to_zone(zone_id, data) -> bool 和 drop_to_zone(zone_id, data) -> void。

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var panel = get_meta("drop_panel", null)
	if panel == null or not is_instance_valid(panel):
		return false
	if not (data is Dictionary):
		return false
	var zone_id := String(get_meta("zone_id", ""))
	return panel.can_drop_to_zone(zone_id, data as Dictionary)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var panel = get_meta("drop_panel", null)
	if panel == null or not is_instance_valid(panel):
		return
	if data is Dictionary:
		var zone_id := String(get_meta("zone_id", ""))
		panel.drop_to_zone(zone_id, data as Dictionary)
