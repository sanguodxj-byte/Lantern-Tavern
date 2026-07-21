extends GdUnitTestSuite

## 集成测试：体素敌人在实例化时挂载伪布娃娃组件，
## 并能走 activate（死亡碎裂）/ freeze（冻结休眠）/ clear_fragments 完整流程而不报错。
## 验证「给全部敌人加布娃娃」需求对体素敌人成立。
##
## 注意：体素怪物使用 _rig.glb（Blender 合并的单蒙皮网格 + 骨架），
## skeleton_simulator 非 null（继承自 goblin.tscn 的 PhysicalBoneSimulator3D），
## 但骨骼布娃娃对体素模型无效。所有敌人现在始终创建 voxel_ragdoll，
## 死亡时优先走体素碎裂路径。

const ACCEPTED_ENEMY := preload("res://scenes/characters/enemies/goblin.tscn")


func test_voxel_enemy_attaches_ragdoll_and_runs_lifecycle() -> void:
	var inst := ACCEPTED_ENEMY.instantiate()
	add_child(inst)
	await get_tree().physics_frame
	var enemy := inst as Enemy
	assert_object(enemy).is_not_null()
	# 所有敌人现在始终挂载 voxel_ragdoll（无论是否有 skeleton_simulator）
	assert_object(enemy.voxel_ragdoll).is_not_null()
	# 走完整死亡流程：碎裂 -> 冻结 -> 清理
	var char_node := enemy.get_node_or_null("character")
	enemy.voxel_ragdoll.activate(char_node, Vector3(0, 1, 0), 4.0)
	await get_tree().physics_frame
	enemy.voxel_ragdoll.freeze()
	await get_tree().physics_frame
	enemy.voxel_ragdoll.clear_fragments()
	inst.queue_free()
	await get_tree().physics_frame
	assert_bool(true).is_true()
