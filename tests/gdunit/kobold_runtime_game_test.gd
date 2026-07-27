extends GdUnitTestSuite
## Real Godot in-game runtime test for Kobold enemy scene.

const KOBOLD_SCENE_PATH := "res://scenes/characters/enemies/kobold.tscn"
const WEAPON_PATH := "res://data/weapons/shortsword.tres"


func test_kobold_runtime_scene_instantiation_and_components() -> void:
	var packed := load(KOBOLD_SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var runtime := auto_free(packed.instantiate()) as CharacterBody3D
	assert_object(runtime).is_not_null()

	var anim_player := _find_animation_player(runtime)
	assert_object(anim_player).is_not_null()
	assert_bool(anim_player.has_animation("run")).is_true()
	assert_bool(anim_player.has_animation("idle")).is_true()


func test_kobold_runtime_equipment_attachment() -> void:
	var packed := load(KOBOLD_SCENE_PATH) as PackedScene
	var runtime := auto_free(packed.instantiate()) as CharacterBody3D

	var equipment := runtime.get_node_or_null("EquipmentComponent")
	assert_object(equipment).is_not_null()

	var weapon_attach := runtime.find_child("WeaponBoneAttachment", true, false) as BoneAttachment3D
	assert_object(weapon_attach).is_not_null()
	assert_str(weapon_attach.bone_name).is_equal("Hand.R")


func test_kobold_runtime_walk_animation_movement() -> void:
	var packed := load(KOBOLD_SCENE_PATH) as PackedScene
	var runtime := auto_free(packed.instantiate()) as CharacterBody3D

	var anim_player := _find_animation_player(runtime)
	assert_object(anim_player).is_not_null()

	var skeleton := _find_skeleton(runtime)
	assert_object(skeleton).is_not_null()

	# Play "run" animation (in-game walk locomotion)
	anim_player.play("run")
	var anim := anim_player.get_animation("run")

	# Sample Stride Right (15% progress)
	anim_player.seek(anim.length * 0.15, true)
	anim_player.advance(0.0)
	var right_leg_pose := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperLeg.R"))
	assert_bool(right_leg_pose != Quaternion.IDENTITY).is_true()

	# Sample Stride Left (75% progress)
	anim_player.seek(anim.length * 0.75, true)
	anim_player.advance(0.0)
	var left_leg_pose := skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperLeg.L"))
	assert_bool(left_leg_pose != Quaternion.IDENTITY).is_true()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
