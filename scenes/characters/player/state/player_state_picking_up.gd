class_name PlayerStatePickingUp
extends PlayerState

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
		player.animation_player.play("lift")
		player.equipment.equip_furniture(pickable_object.furniture_data, pickable_object.global_transform)
		pickable_object.queue_free()

func _physics_process(delta: float) -> void:
	player.process_movement(delta)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)
