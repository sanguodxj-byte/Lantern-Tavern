class_name PlayerStateBlocking
extends PlayerState

## 动作控制版格挡状态
## 根据装备流派区分格挡方式：
##   - 持盾：持续格挡（按住右键保持），进入后 0.3s 内为「完美格挡窗口」，
##     受到伤害不消耗盾牌耐久。0.3s 后受到伤害正常消耗盾牌耐久。
##   - 双手武器：仅按下右键后的 0.3s 内可格挡（精确格挡窗口），到期自动退出。
##   - 单手武器 / 远程武器：无法进入此状态（由 can_block_with_active_equipment 拦截）。

const GROUND_FRICTION := 10.0

## 精确格挡 / 完美格挡窗口（秒）
const BLOCK_WINDOW_SEC := 0.3

## 格挡模式
enum BlockMode { SHIELD, TWO_HAND }

var block_mode: int = BlockMode.SHIELD
var block_start_msec: int = 0

func _enter_tree() -> void:
	block_start_msec = Time.get_ticks_msec()
	block_mode = _determine_block_mode()
	player.animation_player.play("block")
	player.animation_player.animation_finished.connect(on_animation_finished)

func _determine_block_mode() -> int:
	if player.equipment != null and player.equipment.has_shield():
		return BlockMode.SHIELD
	return BlockMode.TWO_HAND

func _process(_delta: float) -> void:
	if player.is_character_panel_visible():
		transition_state(Player.State.MOVING)
		return
	# 双手武器：0.3s 窗口到期后自动退出格挡
	if block_mode == BlockMode.TWO_HAND:
		var elapsed := float(Time.get_ticks_msec() - block_start_msec) / 1000.0
		if elapsed >= BLOCK_WINDOW_SEC:
			transition_state(Player.State.MOVING)
			return
	# 持盾：松开右键退出格挡
	if block_mode == BlockMode.SHIELD:
		if not Input.is_action_pressed("block"):
			transition_state(Player.State.MOVING)
			return

func _physics_process(delta: float) -> void:
	player.velocity = player.velocity.move_toward(Vector3.ZERO, delta * GROUND_FRICTION)

func on_animation_finished(_anim_name: String) -> void:
	# 双手武器动画播完即退出（动画时长 ≈ 0.3s 窗口）
	if block_mode == BlockMode.TWO_HAND:
		transition_state(Player.State.MOVING)
		return
	# 持盾：动画播完后若仍按住右键则保持，否则退出
	if not Input.is_action_pressed("block"):
		transition_state(Player.State.MOVING)

## 是否处于完美格挡窗口（0.3s 内）
func is_in_grace_window() -> bool:
	var elapsed := float(Time.get_ticks_msec() - block_start_msec) / 1000.0
	return elapsed < BLOCK_WINDOW_SEC

## 当前格挡模式
func get_block_mode() -> int:
	return block_mode

func can_get_hurt() -> bool:
	# 格挡状态下不直接扣血（伤害由 try_receive_hit_result 的 BLOCKING 分支处理）
	return false
