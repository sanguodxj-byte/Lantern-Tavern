class_name PlayerStatePickingUp
extends PlayerState

func _enter_tree() -> void:
	var pickable_object := player.current_pickable_focused_item
	if pickable_object.weapon_data != null:
		player.equipment.equip_weapon(pickable_object.weapon_data, pickable_object.global_transform)
		pickable_object.queue_free()
	transition_state(Player.State.MOVING)
