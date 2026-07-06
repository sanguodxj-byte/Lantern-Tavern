class_name PlayerStateAiming
extends PlayerState

## 远程武器瞄准状态（望远镜效果）。
## 进入时开启 FOV 缩放 + 灵敏度降低。
## 左键按下 → 进入 ATTACK_PREPARING（保持瞄准缩放，不关闭）。
## 松开右键 → 回到 MOVING（关闭瞄准缩放）。

func _enter_tree() -> void:
	player.set_weapon_aiming(true)

func _process(_delta: float) -> void:
	if player.is_character_panel_visible():
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)
		return
	# 左键按下：进入攻击准备（瞄准状态保持，不关闭 FOV 缩放）
	if Input.is_action_just_pressed("action") and player.get_primary_weapon_action_state() != -1:
		transition_state(player.get_primary_weapon_action_state(), player.make_primary_weapon_attack_data())
		return
	# 松开右键：退出瞄准
	if not Input.is_action_pressed("block"):
		player.set_weapon_aiming(false)
		transition_state(Player.State.MOVING)

func _physics_process(delta: float) -> void:
	player.process_movement(delta, 0.45)
