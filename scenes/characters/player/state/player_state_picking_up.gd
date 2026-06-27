class_name PlayerStatePickingUp
extends PlayerState

const CARRY_SPEED_MULTIPLIER := 0.2

var is_carrying := false

func _enter_tree() -> void:
	var pickable_object := player.current_pickable_focused_item
	if pickable_object.weapon_data != null:
		player.animation_player.play("pickup")
		player.animation_player.animation_finished.connect(on_animation_finished)
		player.equipment.equip_weapon(pickable_object.weapon_data, pickable_object.global_transform)
		pickable_object.queue_free()
	elif pickable_object.shield_data != null:
		player.animation_player.play("pickup")
		player.animation_player.animation_finished.connect(on_animation_finished)
		player.equipment.equip_shield(pickable_object.shield_data, pickable_object.global_transform)
		pickable_object.queue_free()
	elif pickable_object.furniture_data != null:
		is_carrying = true
		player.animation_player.play("lift")
		player.equipment.equip_furniture(pickable_object.furniture_data, pickable_object.global_transform)
		pickable_object.queue_free()

func _physics_process(delta: float) -> void:
	player.process_movement(delta, CARRY_SPEED_MULTIPLIER)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("action") and is_carrying:
		transition_state(Player.State.THROWING)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)
