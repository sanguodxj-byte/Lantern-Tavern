extends GdUnitTestSuite

const SWORD_GLB := "res://assets/meshes/weapons/weapons_voxel_sword.glb"
const DAGGER_GLB := "res://assets/meshes/weapons/weapons_voxel_dagger.glb"
const SHORTSWORD_GLB := "res://assets/meshes/weapons/weapons_voxel_shortsword.glb"
const GREATSWORD_GLB := "res://assets/meshes/weapons/weapons_voxel_greatsword.glb"
const REQUIRED_ACTIONS: Array[StringName] = [
	&"vm_sword_hold",
	&"vm_melee_charge",
	&"vm_sword_slash",
	&"vm_sword_guard",
]


func test_sword_glb_contains_weapon_only_armature_and_actions() -> void:
	var scene := load(SWORD_GLB) as PackedScene
	assert_object(scene).is_not_null()
	var instance := auto_free(scene.instantiate()) as Node
	assert_object(instance).is_not_null()
	if instance == null:
		return
	var rig_root := instance.find_child("SwordRig", true, false) as Node3D
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_object(rig_root).is_not_null()
	assert_object(skeleton).is_not_null()
	if skeleton != null:
		assert_int(skeleton.get_bone_count()).is_equal(1)
		assert_str(String(skeleton.get_bone_name(0))).is_equal("WeaponRoot")
	for forbidden_name in ["Hand", "Arm", "Body", "Character"]:
		assert_object(instance.find_child("*%s*" % forbidden_name, true, false)).is_null()
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(animation_player).is_not_null()
	if animation_player == null:
		return
	for action_name in REQUIRED_ACTIONS:
		assert_bool(_has_action(animation_player, action_name)) \
			.override_failure_message("sword GLB missing action: %s" % action_name) \
			.is_true()


func test_shortsword_glb_contains_weapon_only_armature_and_actions() -> void:
	_assert_weapon_rig(
		SHORTSWORD_GLB,
		"ShortswordRig",
		[&"vm_shortsword_hold", &"vm_melee_charge", &"vm_shortsword_thrust", &"vm_shortsword_guard"]
	)


func test_greatsword_glb_contains_weapon_only_armature_and_actions() -> void:
	_assert_weapon_rig(
		GREATSWORD_GLB,
		"GreatswordRig",
		[&"vm_greatsword_hold", &"vm_melee_charge", &"vm_greatsword_attack", &"vm_greatsword_guard"]
	)


func test_dagger_glb_contains_weapon_only_armature_and_actions() -> void:
	var scene := load(DAGGER_GLB) as PackedScene
	assert_object(scene).is_not_null()
	var instance := auto_free(scene.instantiate()) as Node
	assert_object(instance).is_not_null()
	if instance == null:
		return
	var rig_root := instance.find_child("DaggerRig", true, false) as Node3D
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_object(rig_root).is_not_null()
	assert_object(skeleton).is_not_null()
	if skeleton != null:
		assert_int(skeleton.get_bone_count()).is_equal(1)
		assert_str(String(skeleton.get_bone_name(0))).is_equal("WeaponRoot")
	for forbidden_name in ["Hand", "Arm", "Body", "Character"]:
		assert_object(instance.find_child("*%s*" % forbidden_name, true, false)).is_null()
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(animation_player).is_not_null()
	if animation_player == null:
		return
	for action_name in [&"vm_dagger_hold", &"vm_melee_charge", &"vm_stab_dagger", &"vm_dagger_guard"]:
		assert_bool(_has_action(animation_player, action_name)) \
			.override_failure_message("dagger GLB missing action: %s" % action_name) \
			.is_true()


func test_dagger_stab_has_authored_acceleration_contact_and_recovery() -> void:
	var scene := load(DAGGER_GLB) as PackedScene
	var instance := auto_free(scene.instantiate()) as Node
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(animation_player).is_not_null()
	if animation_player == null:
		return
	var action_name := _resolved_action_name(animation_player, &"vm_stab_dagger")
	var animation := animation_player.get_animation(action_name)
	assert_object(animation).is_not_null()
	if animation == null:
		return
	var track_path := NodePath("weapons_voxel_dagger/DaggerRig/Skeleton3D:WeaponRoot")
	var position_track := animation.find_track(track_path, Animation.TYPE_POSITION_3D)
	var rotation_track := animation.find_track(track_path, Animation.TYPE_ROTATION_3D)
	assert_int(position_track).is_greater_equal(0)
	assert_int(rotation_track).is_greater_equal(0)
	if position_track < 0 or rotation_track < 0:
		return
	assert_int(animation.track_get_key_count(position_track)).is_greater_equal(6)
	assert_int(animation.track_get_key_count(rotation_track)).is_greater_equal(6)
	var position_fingerprints := {}
	var rotation_fingerprints := {}
	for key_index in animation.track_get_key_count(position_track):
		position_fingerprints[str(animation.track_get_key_value(position_track, key_index))] = true
	for key_index in animation.track_get_key_count(rotation_track):
		rotation_fingerprints[str(animation.track_get_key_value(rotation_track, key_index))] = true
	assert_int(position_fingerprints.size()).is_greater_equal(5)
	assert_int(rotation_fingerprints.size()).is_greater_equal(5)


func test_sword_slash_has_distinct_windup_contact_followthrough_and_recovery() -> void:
	var scene := load(SWORD_GLB) as PackedScene
	var instance := auto_free(scene.instantiate()) as Node
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(skeleton).is_not_null()
	assert_object(animation_player).is_not_null()
	if skeleton == null or animation_player == null:
		return
	var action_name := _resolved_action_name(animation_player, &"vm_sword_slash")
	var animation := animation_player.get_animation(action_name)
	assert_object(animation).is_not_null()
	if animation == null:
		return
	var position_track := animation.find_track(
		NodePath("weapons_voxel_sword/SwordRig/Skeleton3D:WeaponRoot"),
		Animation.TYPE_POSITION_3D
	)
	var rotation_track := animation.find_track(
		NodePath("weapons_voxel_sword/SwordRig/Skeleton3D:WeaponRoot"),
		Animation.TYPE_ROTATION_3D
	)
	assert_int(position_track).is_greater_equal(0)
	assert_int(rotation_track).is_greater_equal(0)
	if position_track < 0 or rotation_track < 0:
		return
	assert_int(animation.track_get_key_count(position_track)).is_greater_equal(7)
	assert_int(animation.track_get_key_count(rotation_track)).is_greater_equal(7)
	var position_fingerprints := {}
	var rotation_fingerprints := {}
	for key_index in animation.track_get_key_count(position_track):
		position_fingerprints[str(animation.track_get_key_value(position_track, key_index))] = true
	for key_index in animation.track_get_key_count(rotation_track):
		rotation_fingerprints[str(animation.track_get_key_value(rotation_track, key_index))] = true
	assert_int(position_fingerprints.size()).is_greater_equal(5)
	assert_int(rotation_fingerprints.size()).is_greater_equal(5)
	var last_position := animation.track_get_key_value(
		position_track,
		animation.track_get_key_count(position_track) - 1
	) as Vector3
	var last_rotation := animation.track_get_key_value(
		rotation_track,
		animation.track_get_key_count(rotation_track) - 1
	) as Quaternion
	assert_float(last_position.x).is_equal_approx(0.0, 0.001)
	assert_float(last_position.z).is_equal_approx(0.0, 0.001)
	assert_float(absf(last_rotation.normalized().dot(Quaternion.IDENTITY))).is_less(0.001)


func test_view_model_drives_imported_rig_without_using_it_for_combat_authority() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/characters/player/view_model.gd")
	assert_str(source).contains("_find_imported_animation_player")
	assert_str(source).contains("_sample_imported_weapon_rig")
	assert_str(source).contains("_play_imported_weapon_rig")
	assert_str(source).contains("if imported_sampled:")
	assert_str(source).contains("if imported_played:")
	assert_str(source).contains("animator.sample_action(resolve_hold_action(), 0.0)")
	assert_str(source).contains("visual_only")
	assert_str(source).not_contains("resolve_player_attack")
	assert_str(source).not_contains("prepare_attack_hitbox")


func _assert_weapon_rig(
	path: String,
	rig_name: String,
	action_names: Array[StringName]
) -> void:
	var scene := load(path) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return
	var instance := auto_free(scene.instantiate()) as Node
	var rig_root := instance.find_child(rig_name, true, false) as Node3D
	var skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	assert_object(rig_root).is_not_null()
	assert_object(skeleton).is_not_null()
	if skeleton != null:
		assert_int(skeleton.get_bone_count()).is_equal(1)
		assert_str(String(skeleton.get_bone_name(0))).is_equal("WeaponRoot")
	for forbidden_name in ["Hand", "Arm", "Body", "Character"]:
		assert_object(instance.find_child("*%s*" % forbidden_name, true, false)).is_null()
	var animation_player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(animation_player).is_not_null()
	if animation_player == null:
		return
	for action_name in action_names:
		assert_bool(_has_action(animation_player, action_name)).is_true()


func _has_action(player: AnimationPlayer, action_name: StringName) -> bool:
	return not _resolved_action_name(player, action_name).is_empty()


func _resolved_action_name(player: AnimationPlayer, action_name: StringName) -> StringName:
	if player.has_animation(action_name):
		return action_name
	var global_name := StringName("global/%s" % String(action_name))
	if player.has_animation(global_name):
		return global_name
	return &""
