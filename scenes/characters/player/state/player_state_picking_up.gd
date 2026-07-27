class_name PlayerStatePickingUp
extends PlayerState

const CARRY_SPEED_MULTIPLIER := 0.2

var is_carrying := false
var pickup_animation_name := "pickup"

func _enter_tree() -> void:
	var pickable_object := player.current_pickable_focused_item
	if not pickable_object or not is_instance_valid(pickable_object):
		transition_state(Player.State.MOVING)
		return
	
	if pickable_object.weapon_data != null:
		# 旧版 .tres WeaponData（如酒馆内 shortsword.tres / axe.tres）缺少 id /
		# weapon_class / skill_school / proficiency_key 等字段，直接装备会导致技能系统、
		# 熟练度追踪、装备面板分类等功能异常。先通过 WeaponRegistry.resolve_weapon_data
		# 将其解析为注册表中的完整版本，确保拾取后"正常装备"。
		var resolved_data: WeaponData = pickable_object.weapon_data
		if WeaponRegistry != null and WeaponRegistry.has_method("resolve_weapon_data"):
			resolved_data = WeaponRegistry.resolve_weapon_data(pickable_object.weapon_data)
		# 护甲与武器共用 WeaponData 承载，但护甲走护甲槽（equip_armor）；
		# 走 equip_weapon 会被 _is_hand_equipment 拒绝，导致护甲拾取失败、留在地上。
		var is_armor_pickup := player.equipment.is_armor_equipment(resolved_data)
		var equipped_ok := false
		if is_armor_pickup:
			equipped_ok = player.equipment.equip_armor(resolved_data, pickable_object.global_transform)
		else:
			equipped_ok = player.equipment.equip_weapon(resolved_data, pickable_object.global_transform)
		if not equipped_ok:
			transition_state(Player.State.MOVING)
			return
		player.animation_player.play("pickup")
		player.animation_player.animation_finished.connect(on_animation_finished)
		if is_armor_pickup:
			AudioManager.play("pick-up", player.action_audio_stream_player)
			GameState.add_carried_weapon()
		elif _is_weapondata_shield(resolved_data):
			AudioManager.play("pick-up", player.action_audio_stream_player)
			GameState.add_carried_shield()
		else:
			AudioManager.play("sword-pickup", player.action_audio_stream_player)
			GameState.add_carried_weapon()
		if GameState.has_method("save_equipment_from_player"):
			GameState.save_equipment_from_player(player)
		pickable_object.queue_free()
		player.current_pickable_focused_item = null
	elif pickable_object.shield_data != null:
		player.animation_player.play("pickup")
		player.animation_player.animation_finished.connect(on_animation_finished)
		player.equipment.equip_shield(pickable_object.shield_data, pickable_object.global_transform)
		AudioManager.play("pick-up", player.action_audio_stream_player)
		GameState.add_carried_shield()
		if GameState.has_method("save_equipment_from_player"):
			GameState.save_equipment_from_player(player)
		pickable_object.queue_free()
		player.current_pickable_focused_item = null
	elif pickable_object.furniture_data != null:
		is_carrying = true
		AudioManager.play("lift", player.vocal_audio_stream_player)
		player.animation_player.play("lift")
		player.equipment.equip_furniture(pickable_object.furniture_data, pickable_object.global_transform)
		pickable_object.queue_free()
		player.current_pickable_focused_item = null
	elif pickable_object.material_id != "":
		# 材料先进入随身背包，回到酒馆后再由仓库面板手动转入仓库。
		if not GameState.add_carried_material(pickable_object.material_id, 1):
			transition_state(Player.State.MOVING)
			return
		AudioManager.play("key-pickup", player.action_audio_stream_player)
		pickable_object.queue_free()
		player.current_pickable_focused_item = null
		
		# Immediately return to moving state since materials are auto-bagged!
		transition_state(Player.State.MOVING)
	elif pickable_object.rune_id != "":
		if not GameState.add_carried_rune(pickable_object.rune_id, 1):
			transition_state(Player.State.MOVING)
			return
		AudioManager.play("key-pickup", player.action_audio_stream_player)
		pickable_object.queue_free()
		player.current_pickable_focused_item = null
		transition_state(Player.State.MOVING)

func _physics_process(delta: float) -> void:
	player.process_movement(delta, CARRY_SPEED_MULTIPLIER)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("action") and is_carrying:
		transition_state(Player.State.THROWING)

func on_animation_finished(anim_name: String) -> void:
	if anim_name != pickup_animation_name or player.state_node != self:
		return
	transition_state(Player.State.MOVING)

func _exit_tree() -> void:
	if player != null and is_instance_valid(player) and player.animation_player != null:
		if player.animation_player.animation_finished.is_connected(on_animation_finished):
			player.animation_player.animation_finished.disconnect(on_animation_finished)

func _is_weapondata_shield(data: WeaponData) -> bool:
	return data != null and (data.item_tag == "shield" or data.weapon_class == "shield" or data.equipment_category == "shields")
