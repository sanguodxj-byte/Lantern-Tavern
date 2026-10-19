## ZoneManager 存档分区（ADR-005 首个迁移领域——低风险验证协议）。
## 序列化/恢复/重置当前选定探险区域；保持与旧顶层 "selected_zone" 字段等价。
## 注意：extends 用路径字符串而非 SaveSection class_name——headless 全局类缓存
## 未刷新时新 class_name 无法解析（与 settlement_result 教训一致）。
extends "res://globals/core/state/save_section.gd"

const ZoneManagerClass := preload("res://globals/dungeon/zone_manager.gd")

func _init() -> void:
	section_key = "zone_manager"

func serialize() -> Dictionary:
	var zm: Node = _zone_manager()
	if zm == null:
		return {}
	return {"selected_zone": int(zm.selected_zone) if "selected_zone" in zm else 0}

func deserialize(data: Dictionary) -> void:
	var zm: Node = _zone_manager()
	if zm == null or not zm.has_method("set_zone"):
		return
	if data.has("selected_zone"):
		zm.set_zone(int(data["selected_zone"]))

func reset() -> void:
	var zm: Node = _zone_manager()
	if zm != null and zm.has_method("set_zone"):
		zm.set_zone(0)

func _zone_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("ZoneManager")
