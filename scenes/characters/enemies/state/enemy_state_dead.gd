class_name EnemyStateDead
extends EnemyState

func _enter_tree() -> void:
	if enemy.voxel_ragdoll != null:
		# 体素碎裂碎片冻结（避免一直翻滚）
		enemy.voxel_ragdoll.freeze()

func can_die() -> bool:
	return false

func can_get_hurt() -> bool:
	return false
