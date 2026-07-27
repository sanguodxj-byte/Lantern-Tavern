class_name EnemyStateImpaling
extends EnemyState

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")
const IMPALE_INTENSITY := 100.0

func _enter_tree() -> void:
	enemy.health.current_life = 0
	AudioManager.play("impale", enemy.action_audio_stream_player)
	var impaled_item := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	if impaled_item == null:
		push_error("EnemyStateImpaling: failed to instantiate EquipedItem")
		enemy.request_death()
		return
	if state_data.thrown_item == null:
		push_warning("EnemyStateImpaling: thrown_item is null in state_data, skipping impale visuals")
		enemy.request_death()
		return
	impaled_item.weapon_data = state_data.thrown_item.weapon_data
	var impale_parent: Node3D = enemy.physical_bone_torso \
		if enemy.physical_bone_torso != null and enemy.physical_bone_torso.is_inside_tree() else enemy
	impale_parent.add_child(impaled_item)
	impaled_item.global_transform.basis = state_data.thrown_item_basis
	impaled_item.translate_object_local(impaled_item.weapon_data.impale_local_translation)
	impaled_item.rotate_object_local(Vector3.UP, impaled_item.weapon_data.impale_local_rotation)
	state_data.thrown_item.queue_free()
	var impulse := state_data.thrown_item_basis * Vector3.FORWARD * IMPALE_INTENSITY + Vector3.UP * IMPALE_INTENSITY
	var blood_transform := enemy.physical_bone_head.global_transform \
		if enemy.physical_bone_head != null and enemy.physical_bone_head.is_inside_tree() else enemy.global_transform
	FxHelper.call_deferred("create_blood_fx", blood_transform)
	enemy.request_death(EnemyStateData.new().set_impulse(impulse))
