class_name EnemyStateDead
extends EnemyState

func _enter_tree() -> void:
	for child in enemy.skeleton_simulator.get_children():
		if child is PhysicalBone3D:
			var bone := child as PhysicalBone3D
			var bone_rid := bone.get_rid() as RID
			PhysicsServer3D.body_set_state(bone_rid, PhysicsServer3D.BODY_STATE_SLEEPING, true)
