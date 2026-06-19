class_name Enemy
extends CharacterBody3D

const DURATION_RAGDOLL_SIMULATION := 3.0
const EQUIPED_ITEM_PREFAB := preload("res://scenes/equipment/equiped_item.tscn")
const IMPALE_INTENSITY := 100.0

@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var skeleton_simulator: PhysicalBoneSimulator3D = %PhysicalBoneSimulator3D
@onready var physical_bone_torso: PhysicalBone3D = %"Physical Bone Torso"

func impale(thrown_item: ThrownItem, item_basis: Basis) -> void:
	var impaled_item := EQUIPED_ITEM_PREFAB.instantiate() as EquipedItem
	impaled_item.weapon_data = thrown_item.weapon_data
	physical_bone_torso.add_child(impaled_item)
	impaled_item.global_transform.basis = item_basis
	impaled_item.translate_object_local(impaled_item.weapon_data.impale_local_translation)
	impaled_item.rotate_object_local(Vector3.UP, impaled_item.weapon_data.impale_local_rotation)
	thrown_item.queue_free()
	register_death(item_basis * Vector3.FORWARD * IMPALE_INTENSITY + Vector3.UP * IMPALE_INTENSITY)

func register_death(impulse: Vector3 = Vector3.ZERO) -> void:
	collision_shape.disabled = true
	skeleton_simulator.active = true
	skeleton_simulator.physical_bones_start_simulation()
	physical_bone_torso.apply_impulse(impulse)
	var timer := get_tree().create_timer(DURATION_RAGDOLL_SIMULATION)
	timer.timeout.connect(freeze_ragdoll)

func freeze_ragdoll() -> void:
	for child in skeleton_simulator.get_children():
		if child is PhysicalBone3D:
			var bone := child as PhysicalBone3D
			var bone_rid := bone.get_rid() as RID
			PhysicsServer3D.body_set_state(bone_rid, PhysicsServer3D.BODY_STATE_SLEEPING, true)
