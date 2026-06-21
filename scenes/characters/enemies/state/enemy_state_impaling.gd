class_name EnemyStateImpaling
extends EnemyState

const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")
const IMPALE_INTENSITY := 100.0

func _enter_tree() -> void:
	GameEvents.impact_felt.emit(GameEvents.ImpactIntensity.MEDIUM)
	var impaled_item := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	impaled_item.weapon_data = state_data.thrown_item.weapon_data
	enemy.physical_bone_torso.add_child(impaled_item)
	impaled_item.global_transform.basis = state_data.thrown_item_basis
	impaled_item.translate_object_local(impaled_item.weapon_data.impale_local_translation)
	impaled_item.rotate_object_local(Vector3.UP, impaled_item.weapon_data.impale_local_rotation)
	state_data.thrown_item.queue_free()
	var impulse := state_data.thrown_item_basis * Vector3.FORWARD * IMPALE_INTENSITY + Vector3.UP * IMPALE_INTENSITY
	transition_state(Enemy.State.DYING, EnemyStateData.new().set_impulse(impulse))
