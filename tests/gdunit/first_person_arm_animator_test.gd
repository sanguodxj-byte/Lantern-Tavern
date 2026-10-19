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

## 回归测试：格挡姿态必须与握持姿态不同（Dictionary.merge 默认 overwrite=false
## 会丢弃 guard 覆盖的骨骼键，导致格挡退化为握持 —— 见 _guard_pose 的 merge(..., true)）。
## 注意：盾牌/部分风格只覆盖单侧手臂，因此必须对比双臂姿态的"整体"是否变化。
func test_arm_animator_guard_pose_differs_from_hold_pose_for_every_style() -> void:
	for profile in [&"unarmed", &"sword", &"dagger", &"greatsword", &"axe", &"spear", &"bow", &"crossbow", &"shield"]:
		var skeleton := Skeleton3D.new()
		for bone_name in ARM_ANIMATOR.ARM_BONES:
			skeleton.add_bone(String(bone_name))
		add_child(skeleton)
		var animator := ARM_ANIMATOR.new()
		animator.bind(skeleton)
		animator.set_weapon_profile(profile)
		animator.sample_action(StringName("vm_%s_hold" % profile), 0.0)
		var hold_r := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.R"))
		var hold_l := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.L"))
		animator.sample_action(StringName("vm_%s_guard" % profile), 0.5)
		var guard_r := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.R"))
		var guard_l := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperArm.L"))
		assert_bool(hold_r != guard_r or hold_l != guard_l).is_true()
		skeleton.queue_free()
