class_name PlayerState
extends Node

signal transition_requested(new_state: Player.State, source_data: PlayerStateData)

var state_data: PlayerStateData
var player: Player

## 受保护退出标志：_begin_exit 后置为 true，防止旧状态在 queue_free 延迟窗口内重入切换。
var _is_exiting: bool = false

func _init(source_player: Player, source_data: PlayerStateData = PlayerStateData.new()) -> void:
	player = source_player
	state_data = source_data

func transition_state(new_state: Player.State, source_data: PlayerStateData = PlayerStateData.new()) -> void:
	# 退出中的状态不得再请求切换，防止 queue_free 延迟窗口内重入 switch_state
	if _is_exiting:
		return
	transition_requested.emit(new_state, source_data)

## 受保护退出钩子：switch_state 在创建新状态前同步调用。
## 断开 transition_requested 信号、禁用处理循环、调用子类 _on_exit 做同步清理。
## 此后旧状态不再能触发重入切换，queue_free 在帧末完成实际释放。
func _begin_exit() -> void:
	if _is_exiting:
		return
	_is_exiting = true
	set_process(false)
	set_physics_process(false)
	# 断开 transition_requested → switch_state 信号，防止旧状态在 queue_free 延迟窗口内重入
	if transition_requested.is_connected(Callable(player, "switch_state")):
		transition_requested.disconnect(Callable(player, "switch_state"))
	# 子类同步清理钩子（断开动画信号、停用 hitbox 等），在 queue_free 前执行
	_on_exit()

## 子类可覆盖的同步退出清理。在 _begin_exit 中、queue_free 前调用。
## 用于立即断开动画信号、停用 hitbox 等需要在新状态 _enter_tree 前完成的清理。
func _on_exit() -> void:
	pass

func can_get_hurt() -> bool:
	return true

func can_die() -> bool:
	return true
