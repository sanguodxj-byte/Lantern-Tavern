class_name TavernDungeonEntrance
extends Area3D

## 酒馆内地牢入口触发区。
## 玩家走入触发区时，在白天探险阶段打开区域选择界面（而非直接跳转地牢）。
## 区域选择 → TavernManager.start_expedition() → 地牢加载。

var _transitioning := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _transitioning or not _is_player_body(body):
		return
	# 仅在白天探险阶段允许进入地牢
	var tm: Node = Engine.get_main_loop().root.get_node_or_null("TavernManager")
	if tm == null or tm.current_phase != tm.Phase.DAY_EXPEDITION:
		return
	var world := _find_world()
	if world == null or not world.has_method("open_zone_select"):
		return
	_transitioning = true
	world.call_deferred("open_zone_select")
	# 延迟重置标记，允许玩家取消区域选择后重新触发
	_reset_transition_flag()


func _reset_transition_flag() -> void:
	await get_tree().create_timer(1.5).timeout
	_transitioning = false


func _is_player_body(body: Node) -> bool:
	if body == null:
		return false
	if body.name == "Player":
		return true
	return body.is_in_group("player")


func _find_world() -> Node:
	var node: Node = self
	while node != null:
		if node.has_method("load_space") and node.has_method("open_zone_select"):
			return node
		node = node.get_parent()
	return null
