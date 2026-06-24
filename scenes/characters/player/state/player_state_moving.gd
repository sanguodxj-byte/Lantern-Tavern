class_name PlayerStateMoving
extends PlayerState

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("use") and player.can_pickup_object():
		transition_state(Player.State.PICKING_UP)
	elif Input.is_action_just_pressed("throw") and player.equipment.has_weapon():
		transition_state(Player.State.THROWING)
	elif Input.is_action_just_pressed("action") and player.equipment.has_weapon():
		transition_state(Player.State.SLASHING)
	elif Input.is_action_just_pressed("kick"):
		transition_state(Player.State.KICKING)
	elif Input.is_action_just_pressed("block") and player.equipment.has_shield():
		transition_state(Player.State.BLOCKING)
		
func _physics_process(delta: float) -> void:
	player.process_movement(delta)
	var horizontal_velocity := Vector3(player.velocity.x, 0, player.velocity.z)
	if horizontal_velocity.length_squared() > 0.1 and player.is_on_floor():
		player.animation_player.play("run")
	else:
		player.animation_player.play("idle")
