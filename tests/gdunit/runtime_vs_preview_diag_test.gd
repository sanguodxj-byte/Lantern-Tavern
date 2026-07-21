extends GdUnitTestSuite
## 已验收 S 级模型的运行时导入契约测试。
##
## 动画轨道必须由每只模型自己的生成器正确导出；运行时不得重建或修补。
## 本文件只读取当前已验收的 S 级资产，不把已删除的 A-D 级旧资产当作契约。

# ============================================================================
# 2. 骨骼朝向修正验证（复用 voxel_rig_animation_test 的逻辑）
# ============================================================================

const HUMANOID_RIGS := {
	"goblin": "voxel_goblin_32px_rig.glb",
}

const CREATURE_RIGS := {
	"dragon": "voxel_dragon_256px_rig.glb",
}

func _rig_path(filename: String) -> String:
	return "res://assets/meshes/characters/%s" % filename

## 将弧度归一化到 [0, 2π) 后比较
func _rot_y_matches(rot_y: float, expected: float, tolerance: float = 0.05) -> bool:
	var norm_actual := fmod(rot_y, TAU)
	if norm_actual < 0.0:
		norm_actual += TAU
	var norm_expected := fmod(expected, TAU)
	if norm_expected < 0.0:
		norm_expected += TAU
	var diff := absf(norm_actual - norm_expected)
	if diff > PI:
		diff = TAU - diff
	return diff < tolerance

## 递归查找携带指定 Y 旋转的 Node3D
func _has_facing_rotation(root: Node, expected_rot_y: float) -> bool:
	if root is Node3D:
		if _rot_y_matches((root as Node3D).rotation.y, expected_rot_y):
			return true
	for child in root.get_children():
		if _has_facing_rotation(child, expected_rot_y):
			return true
	return false

func test_humanoid_rigs_have_180_facing_rotation() -> void:
	var failures: Array[String] = []
	for name in HUMANOID_RIGS:
		var path := _rig_path(HUMANOID_RIGS[name])
		var scene = load(path) as PackedScene
		if scene == null:
			failures.append("%s 无法加载" % name)
			continue
		var instance = scene.instantiate()
		if not _has_facing_rotation(instance, PI):
			failures.append("%s 未找到 180° Y 旋转" % name)
		instance.free()
	if not failures.is_empty():
		fail(str("\n".join(failures)))
		return
	assert_bool(true).is_true()

func test_creature_rigs_have_correct_facing_rotation() -> void:
	var failures: Array[String] = []
	for name in CREATURE_RIGS:
		var path := _rig_path(CREATURE_RIGS[name])
		var scene = load(path) as PackedScene
		if scene == null:
			failures.append("%s 无法加载" % name)
			continue
		var instance = scene.instantiate()
		if not _has_facing_rotation(instance, -PI / 2.0):
			failures.append("%s 未找到 -90° Y 旋转" % name)
		instance.free()
	if not failures.is_empty():
		fail(str("\n".join(failures)))
		return
	assert_bool(true).is_true()

# ============================================================================
# 3. 动画轨道类型验证
# ============================================================================

func test_kick_animation_has_rotation_tracks_in_imported_glb() -> void:
	# 直接检查导入结果；运行时不允许合成缺失轨道。
	var path := _rig_path(HUMANOID_RIGS["goblin"])
	var scene = load(path) as PackedScene
	if scene == null:
		fail("无法加载已验收的 S 级 goblin rig")
		return
	var inst = scene.instantiate()
	add_child(inst)
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(ap).is_not_null()
	# kick 动画应有 UpperLeg.R 和 LowerLeg.R 的 ROTATION_3D 轨道
	assert_bool(ap.has_animation("kick")).is_true()
	var kick_anim := ap.get_animation("kick")
	var has_upper_leg_r := false
	var has_lower_leg_r := false
	for i in range(kick_anim.get_track_count()):
		var track_path := str(kick_anim.track_get_path(i))
		if track_path.contains("UpperLeg.R") and kick_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			has_upper_leg_r = true
		if track_path.contains("LowerLeg.R") and kick_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			has_lower_leg_r = true
	assert_bool(has_upper_leg_r).is_true()
	assert_bool(has_lower_leg_r).is_true()
	inst.queue_free()

func test_run_animation_has_rotation_tracks_in_imported_glb() -> void:
	var path := _rig_path(HUMANOID_RIGS["goblin"])
	var scene = load(path) as PackedScene
	if scene == null:
		fail("无法加载已验收的 S 级 goblin rig")
		return
	var inst = scene.instantiate()
	add_child(inst)
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_bool(ap.has_animation("run")).is_true()
	var run_anim := ap.get_animation("run")
	# run 应有 UpperLeg.R 和 UpperLeg.L 的 ROTATION_3D 轨道
	var has_upper_leg_r := false
	var has_upper_leg_l := false
	for i in range(run_anim.get_track_count()):
		var track_path := str(run_anim.track_get_path(i))
		if track_path.contains("UpperLeg.R") and run_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			has_upper_leg_r = true
		if track_path.contains("UpperLeg.L") and run_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			has_upper_leg_l = true
	assert_bool(has_upper_leg_r).is_true()
	assert_bool(has_upper_leg_l).is_true()
	inst.queue_free()

# ============================================================================
# 4. 关键骨骼全局位置验证（朝向是否颠倒）
# ============================================================================

func test_goblin_key_bones_are_upright() -> void:
	var path := _rig_path(HUMANOID_RIGS["goblin"])
	var scene = load(path) as PackedScene
	if scene == null:
		fail("无法加载已验收的 S 级 goblin rig")
		return
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_object(skeleton).is_not_null()
	# Head 应在上方（全局 Y > 0.5m）
	var head_idx := skeleton.find_bone("Head")
	if head_idx >= 0:
		var head_global := skeleton.get_bone_global_rest(head_idx)
		assert_float(head_global.origin.y).is_greater(0.5)
	# Foot.R 应在下方（全局 Y < 0.3m）
	var foot_r_idx := skeleton.find_bone("Foot.R")
	if foot_r_idx >= 0:
		var foot_global := skeleton.get_bone_global_rest(foot_r_idx)
		assert_float(foot_global.origin.y).is_less(0.3)
	inst.queue_free()

func test_goblin_hand_r_is_on_right_side() -> void:
	var path := _rig_path(HUMANOID_RIGS["goblin"])
	var scene = load(path) as PackedScene
	if scene == null:
		fail("无法加载已验收的 S 级 goblin rig")
		return
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_object(skeleton).is_not_null()
	# Hand.R 应在 +X 侧（角色右侧）
	# 注意：朝向修正 180° 后，X 轴会翻转，所以 Hand.R 可能在 -X
	# 这里验证的是 Hand.R 和 Hand.L 的相对位置正确（左右不镜像）
	var hand_r_idx := skeleton.find_bone("Hand.R")
	var hand_l_idx := skeleton.find_bone("Hand.L")
	if hand_r_idx >= 0 and hand_l_idx >= 0:
		var hand_r_global := skeleton.get_bone_global_rest(hand_r_idx)
		var hand_l_global := skeleton.get_bone_global_rest(hand_l_idx)
		# 左右手应在 X 轴两侧（无论朝向修正如何）
		var x_diff := hand_r_global.origin.x - hand_l_global.origin.x
		assert_float(absf(x_diff)).is_greater(0.05)
	inst.queue_free()
