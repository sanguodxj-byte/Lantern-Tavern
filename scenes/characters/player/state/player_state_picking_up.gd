class_name PlayerStatePickingUp
extends PlayerState

const CARRY_SPEED_MULTIPLIER := 0.2

var is_carrying := false

func _enter_tree() -> void:
	var pickable_object := player.current_pickable_focused_item
	if not pickable_object:
		transition_state(Player.State.MOVING)
		return
	
	if pickable_object.weapon_data != null:
		if not player.equipment.equip_weapon(pickable_object.weapon_data, pickable_object.global_transform):
			transition_state(Player.State.MOVING)
			return
		player.animation_player.play("pickup")
		player.animation_player.animation_finished.connect(on_animation_finished)
		if _is_weapondata_shield(pickable_object.weapon_data):
			AudioManager.play("pick-up", player.action_audio_stream_player)
			GameState.add_carried_shield()
		else:
			AudioManager.play("sword-pickup", player.action_audio_stream_player)
			GameState.add_carried_weapon()
		if GameState.has_method("save_equipment_from_player"):
			GameState.save_equipment_from_player(player)
		pickable_object.queue_free()
	elif pickable_object.shield_data != null:
		player.animation_player.play("pickup")
		player.animation_player.animation_finished.connect(on_animation_finished)
		player.equipment.equip_shield(pickable_object.shield_data, pickable_object.global_transform)
		AudioManager.play("pick-up", player.action_audio_stream_player)
		GameState.add_carried_shield()
		if GameState.has_method("save_equipment_from_player"):
			GameState.save_equipment_from_player(player)
		pickable_object.queue_free()
	elif pickable_object.furniture_data != null:
		is_carrying = true
		AudioManager.play("lift", player.vocal_audio_stream_player)
		player.animation_player.play("lift")
		player.equipment.equip_furniture(pickable_object.furniture_data, pickable_object.global_transform)
		pickable_object.queue_free()
	elif pickable_object.material_id != "":
		# 材料先进入随身背包，回到酒馆后再由仓库面板手动转入仓库。
		if not GameState.add_carried_material(pickable_object.material_id, 1):
			transition_state(Player.State.MOVING)
			return
		AudioManager.play("key-pickup", player.action_audio_stream_player)
		pickable_object.queue_free()
		
		# Immediately return to moving state since materials are auto-bagged!
		transition_state(Player.State.MOVING)
	elif pickable_object.rune_id != "":
		if not GameState.add_carried_rune(pickable_object.rune_id, 1):
			transition_state(Player.State.MOVING)
			return
		AudioManager.play("key-pickup", player.action_audio_stream_player)
		pickable_object.queue_free()
		transition_state(Player.State.MOVING)

func _physics_process(delta: float) -> void:
	player.process_movement(delta, CARRY_SPEED_MULTIPLIER)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("action") and is_carrying:
		transition_state(Player.State.THROWING)

func on_animation_finished(_anim_name: String) -> void:
	transition_state(Player.State.MOVING)

func _is_weapondata_shield(data: WeaponData) -> bool:
	return data != null and (data.item_tag == "shield" or data.weapon_class == "shield" or data.equipment_category == "shields")
