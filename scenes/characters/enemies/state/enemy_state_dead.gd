class_name EnemyStateDead
extends EnemyState

func _enter_tree() -> void:
	if enemy.voxel_ragdoll != null:
		# 体素碎裂碎片冻结（避免一直翻滚）
		enemy.voxel_ragdoll.freeze()
	elif enemy.skeleton_simulator != null:
		for child in enemy.skeleton_simulator.get_children():
			if child is PhysicalBone3D:
				var bone := child as PhysicalBone3D
				var bone_rid := bone.get_rid() as RID
				PhysicsServer3D.body_set_state(bone_rid, PhysicsServer3D.BODY_STATE_SLEEPING, true)

func can_die() -> bool:
	return false

func can_get_hurt() -> bool:
	return false
