extends GdUnitTestSuite
## 第一人称弓弩动作真实播放验证（gdUnit 环境：autoload 已注册，view_model.gd 正常编译）。
## 目的：确认弓/弩的第一人称动作在真实播放路径（begin_weapon_hold/play_action）
## 下确实随时间播放，而非静态姿态。这是对捕获工具静态采样审查的补充验证。

const VIEW_MODEL_SCENE := preload("res://scenes/characters/player/view_model.tscn")
const BOW_SCENE := preload("res://assets/meshes/weapons/weapons_voxel_longbow.glb")
const CROSSBOW_SCENE := preload("res://assets/meshes/weapons/weapons_voxel_crossbow.glb")

var _viewport: SubViewport
var _view_model: ViewModel
var _camera: Camera3D


func before() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(480, 270)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.current = true
	_viewport.add_child(_camera)
	_view_model = VIEW_MODEL_SCENE.instantiate() as ViewModel
	_view_model.use_weapon_camera = false
	_view_model.weapon_sway_strength = 0.0
	_camera.add_child(_view_model)
	await get_tree().process_frame


func after() -> void:
	if _view_model != null and is_instance_valid(_view_model):
		_view_model.queue_free()
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()


## 弓 release 动作：play_action 后 ActionPivot 应随时间移动（动画真实播放）。
func test_bow_release_animates_action_pivot() -> void:
	var weapon := WeaponData.new()
	weapon.id = "longbow"
	weapon.weapon_class = "longbow"
	weapon.attack_type = "ranged"
	weapon.skill_school = "longbow"
	weapon.view_model_profile = "bow"
	weapon.glb_mesh = BOW_SCENE
	_view_model.set_weapon(weapon)
	_view_model.set_weapon_animation_variant("standard")
	await get_tree().process_frame

	var action_pivot := _view_model.get_node_or_null("BobPivot/AimPivot/ActionPivot") as Node3D
	assert_object(action_pivot).is_not_null()
	if action_pivot == null:
		return

	_view_model.begin_weapon_hold()
	await get_tree().process_frame
	var p0 := action_pivot.position
	_view_model.play_action(&"vm_bow_release")
	await get_tree().process_frame
	var moved := false
	for frame_index in 15:
		await get_tree().process_frame
		if not is_instance_valid(action_pivot):
			break
		if action_pivot.position.distance_to(p0) > 0.0005:
			moved = true
			break
	assert_bool(moved) \
		.override_failure_message("vm_bow_release 播放后 ActionPivot 应随时间移动（动作未生效）p0=%s" % p0) \
		.is_true()


## 弩 fire + reload 动作：真实播放应驱动 ActionPivot 移动。
func test_crossbow_fire_and_reload_animate_action_pivot() -> void:
	var weapon := WeaponData.new()
	weapon.id = "crossbow"
	weapon.weapon_class = "crossbow"
	weapon.attack_type = "ranged"
	weapon.skill_school = "light_crossbow"
	weapon.view_model_profile = "crossbow"
	weapon.glb_mesh = CROSSBOW_SCENE
	_view_model.set_weapon(weapon)
	_view_model.set_weapon_animation_variant("standard")
	await get_tree().process_frame

	var action_pivot := _view_model.get_node_or_null("BobPivot/AimPivot/ActionPivot") as Node3D
	assert_object(action_pivot).is_not_null()
	if action_pivot == null:
		return

	_view_model.begin_weapon_hold()
	await get_tree().process_frame
	for action_name in [&"vm_crossbow_fire", &"vm_crossbow_reload"]:
		var p0 := action_pivot.position
		_view_model.play_action(action_name)
		await get_tree().process_frame
		var moved := false
		for frame_index in 15:
			await get_tree().process_frame
			if not is_instance_valid(action_pivot):
				break
			if action_pivot.position.distance_to(p0) > 0.0005:
				moved = true
				break
		assert_bool(moved) \
			.override_failure_message("%s 播放后 ActionPivot 应随时间移动（动作未生效）p0=%s" % [action_name, p0]) \
			.is_true()


## 弓 hold 姿态应为垂直握持（弓臂上下）而非横置。
func test_bow_hold_is_vertical() -> void:
	var weapon := WeaponData.new()
	weapon.id = "longbow"
	weapon.weapon_class = "longbow"
	weapon.attack_type = "ranged"
	weapon.skill_school = "longbow"
	weapon.view_model_profile = "bow"
	weapon.glb_mesh = BOW_SCENE
	_view_model.set_weapon(weapon)
	_view_model.set_weapon_animation_variant("standard")
	await get_tree().process_frame

	_view_model.begin_weapon_hold()
	await get_tree().process_frame
	var socket := _view_model.get_node_or_null("BobPivot/AimPivot/ActionPivot/WeaponSocket") as Node3D
	assert_object(socket).is_not_null()
	if socket == null:
		return
	var mesh_instance := _find_first_mesh(socket)
	assert_object(mesh_instance).is_not_null()
	if mesh_instance == null:
		return
	var bounds: AABB = mesh_instance.get_aabb()
	# 弓臂沿上下（Y 长）而非左右（X 长）：竖握而非横握
	assert_float(bounds.size.y) \
		.override_failure_message("弓 hold 应为垂直握持（弓臂上下），AABB=%s" % bounds) \
		.is_greater(bounds.size.x)


## 递归查找第一个 MeshInstance3D（GLB 通常有中间节点）。
func _find_first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null
