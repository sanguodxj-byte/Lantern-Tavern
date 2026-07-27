extends GdUnitTestSuite

const ARM_ANIMATOR := preload("res://scenes/characters/player/first_person_arm_animator.gd")

func test_arm_animator_writes_only_the_first_person_skeleton() -> void:
	var skeleton := Skeleton3D.new()
	for bone_name in ARM_ANIMATOR.ARM_BONES:
		skeleton.add_bone(String(bone_name))
	add_child(skeleton)
	var animator := ARM_ANIMATOR.new()
	animator.bind(skeleton)
	animator.set_weapon_profile(&"greatsword")
	animator.sample_action(&"vm_greatsword_heavy_swing", 0.5)
	assert_bool(skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.R")) != Quaternion.IDENTITY).is_true()
	assert_bool(skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.L")) != Quaternion.IDENTITY).is_true()
	skeleton.queue_free()

func test_arm_animator_resets_all_arm_bones_on_visual_cleanup() -> void:
	var skeleton := Skeleton3D.new()
	for bone_name in ARM_ANIMATOR.ARM_BONES:
		skeleton.add_bone(String(bone_name))
	add_child(skeleton)
	var animator := ARM_ANIMATOR.new()
	animator.bind(skeleton)
	animator.set_weapon_profile(&"sword")
	animator.sample_action(&"vm_sword_slash", 0.5)
	animator.reset_pose()
	for bone_name in ARM_ANIMATOR.ARM_BONES:
		assert_bool(skeleton.get_bone_pose_rotation(skeleton.find_bone(bone_name)) == Quaternion.IDENTITY).is_true()
		skeleton.queue_free()

func test_arm_animator_samples_hold_progress_into_style_charge_pose() -> void:
	var skeleton := Skeleton3D.new()
	for bone_name in ARM_ANIMATOR.ARM_BONES:
		skeleton.add_bone(String(bone_name))
	add_child(skeleton)
	var animator := ARM_ANIMATOR.new()
	animator.bind(skeleton)
	animator.set_weapon_profile(&"sword")
	animator.sample_action(&"vm_sword_hold", 0.0)
	var ready_rotation := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.R"))
	animator.sample_action(&"vm_sword_hold", 1.0)
	var charged_rotation := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.R"))
	assert_bool(ready_rotation != charged_rotation).is_true()
	skeleton.queue_free()
