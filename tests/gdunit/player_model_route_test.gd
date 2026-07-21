extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")

const PLAYER_MODEL_ID := "player"
const PLAYER_MODEL_ROUTE := "res://scenes/characters/player/player_visual_model.tscn"
const PLAYER_SCENE := "res://scenes/characters/player/player.tscn"
const PLAYER_RIG := "res://assets/meshes/characters/voxel_player_54px_rig.glb"
const ORC_FALLBACK_RIG := "res://assets/meshes/characters/voxel_orc_raider_48px_rig.glb"
const FORMAL_ROUTE_CALLERS: Array[String] = [
	"res://scenes/ui/tavern_equipment_panel.gd",
	"res://tools/equipment_screen_capture.gd",
]


func test_player_route_uses_one_accepted_a_tier_54px_rig() -> void:
	assert_bool(TIERS.is_accepted(PLAYER_MODEL_ID)).is_true()
	assert_str(TIERS.tier_for(PLAYER_MODEL_ID)).is_equal(TIERS.A)

	var route_source := FileAccess.get_file_as_string(PLAYER_MODEL_ROUTE)
	assert_str(route_source).contains(PLAYER_RIG)
	assert_int(route_source.count(".glb")).is_equal(1)
	assert_str(route_source).contains('node name="PlayerVisualModel"')
	assert_str(route_source).not_contains(ORC_FALLBACK_RIG)
	assert_str(route_source).not_contains("voxel_player_48px")
	assert_str(route_source).not_contains("Pending")
	assert_str(route_source.to_lower()).not_contains("fallback")


func test_player_route_callers_use_formal_constant_without_direct_rig_bypass() -> void:
	for path in FORMAL_ROUTE_CALLERS:
		var source := FileAccess.get_file_as_string(path)
		assert_str(source) \
			.override_failure_message("player caller lacks the formal route constant: %s" % path) \
			.contains('const PLAYER_MODEL_ROUTE := preload("%s")' % PLAYER_MODEL_ROUTE)
		assert_str(source) \
			.override_failure_message("pending player constant remains in caller: %s" % path) \
			.not_contains("PENDING_PLAYER_MODEL_ROUTE")
		assert_str(source) \
			.override_failure_message("player caller bypasses the stable route: %s" % path) \
			.not_contains(PLAYER_RIG)
		assert_str(source).not_contains(ORC_FALLBACK_RIG)
		assert_str(source).not_contains("voxel_player_48px")

	var player_source := FileAccess.get_file_as_string(PLAYER_SCENE)
	assert_str(player_source).contains(PLAYER_MODEL_ROUTE)
	assert_str(player_source).contains('id="2_player_visual"')
	assert_str(player_source).contains('instance=ExtResource("2_player_visual")')
	assert_str(player_source).not_contains("pending_player_visual")
	assert_str(player_source).not_contains(ORC_FALLBACK_RIG)
	assert_str(player_source).not_contains("voxel_player_48px")


func test_player_runtime_preserves_skeleton_animation_and_both_hand_mounts() -> void:
	var route_packed := load(PLAYER_MODEL_ROUTE) as PackedScene
	assert_object(route_packed).is_not_null()
	if route_packed == null:
		return
	var route_model := auto_free(route_packed.instantiate())
	assert_object(route_model.get_node_or_null("Armature/Skeleton3D")).is_instanceof(Skeleton3D)
	assert_object(route_model.get_node_or_null("AnimationPlayer")).is_instanceof(AnimationPlayer)

	var player_packed := load(PLAYER_SCENE) as PackedScene
	assert_object(player_packed).is_not_null()
	if player_packed == null:
		return
	var player := auto_free(player_packed.instantiate())
	assert_object(player.get_node_or_null("character/Armature/Skeleton3D")).is_instanceof(Skeleton3D)
	assert_object(player.get_node_or_null("character/AnimationPlayer")).is_instanceof(AnimationPlayer)

	var weapon_attachment := player.get_node_or_null(
		"character/Armature/Skeleton3D/WeaponBoneAttachment"
	) as BoneAttachment3D
	var shield_attachment := player.get_node_or_null(
		"character/Armature/Skeleton3D/ShieldBoneAttachment"
	) as BoneAttachment3D
	assert_object(weapon_attachment).is_not_null()
	assert_object(shield_attachment).is_not_null()
	if weapon_attachment == null or shield_attachment == null:
		return
	assert_str(weapon_attachment.bone_name).is_equal("Hand.R")
	assert_str(shield_attachment.bone_name).is_equal("Hand.L")
	assert_object(weapon_attachment.get_node_or_null("WeaponPlaceholder")).is_not_null()
	assert_object(shield_attachment.get_node_or_null("ShieldPlaceholder")).is_not_null()

	var player_source := FileAccess.get_file_as_string(PLAYER_SCENE)
	assert_str(player_source).contains(
		'weapon_placeholder = NodePath("../character/Armature/Skeleton3D/WeaponBoneAttachment/WeaponPlaceholder")'
	)
	assert_str(player_source).contains(
		'shield_placeholder = NodePath("../character/Armature/Skeleton3D/ShieldBoneAttachment/ShieldPlaceholder")'
	)
