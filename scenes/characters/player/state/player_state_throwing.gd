class_name PlayerStateThrowing
extends PlayerState

## 投掷状态：家具或武器。
## 家具投掷流程：
##   1. 进入状态 → 播放 throw_furniture 动画（含向前抛出 + 向后收回）
##   2. 动画进行到 ~0.15s（手臂前伸释放点）→ 实际生成 ThrownItem 投出
##   3. 动画结束后 → 恢复武器可见性 → 切回 MOVING
## 武器投掷流程：
##   1. 进入状态 → 播放 throw_weapon 动画
##   2. 动画结束 → 朝准心方向投掷武器 → 切回 MOVING

## 家具释放延迟（秒）：动画中手臂前伸到释放点的时间
const FURNITURE_RELEASE_DELAY := 0.15

var has_thrown_furniture := false
var _furniture_timer: float = 0.0
var throw_animation_name := ""

func _enter_tree() -> void:
	if player.equipment.has_furniture():
		throw_animation_name = "throw_furniture"
		player.animation_player.play("throw_furniture")
		# 不立即投出——等待动画到达释放点
		has_thrown_furniture = false
		_furniture_timer = 0.0
	elif player.equipment.has_weapon():
		throw_animation_name = "throw_weapon"
		player.animation_player.play("throw_weapon")
	else:
		transition_state(Player.State.MOVING)
		return
	player.animation_player.animation_finished.connect(on_animation_finished)

func _physics_process(delta: float) -> void:
	player.process_movement(delta)
	# 家具投掷：在动画释放点投出
	if player.equipment.has_furniture() and not has_thrown_furniture:
		_furniture_timer += delta
		if _furniture_timer >= FURNITURE_RELEASE_DELAY:
			player.equipment.throw_furniture()
			has_thrown_furniture = true

func on_animation_finished(anim_name: String) -> void:
	if anim_name != throw_animation_name or player.state_node != self:
		return
	if not has_thrown_furniture and player.equipment.has_weapon():
		# 朝准心方向投掷武器
		var aim_point := player.get_aim_point()
		player.equipment.throw_weapon(false, aim_point)
	# 家具投掷动画结束后恢复武器可见性（向后收回动作完成）
	if has_thrown_furniture:
		player.equipment.show_weapon()
		player.equipment.show_shield()
	transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	if player != null and is_instance_valid(player) and player.animation_player != null:
		if player.animation_player.animation_finished.is_connected(on_animation_finished):
			player.animation_player.animation_finished.disconnect(on_animation_finished)
