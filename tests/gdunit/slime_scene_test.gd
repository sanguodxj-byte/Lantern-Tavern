extends GdUnitTestSuite

const SCENE_PATH := "res://scenes/characters/enemies/slime.tscn"
const RIG_PATH := "res://assets/meshes/characters/voxel_slime_24px_rig.glb"
const CLAW_PATH := "res://data/weapons/claw.tres"

const EXPECTED_BONES := [
	"Root", "Torso", "Head", "Face", "Core", "Pseudopod.L", "Pseudopod.R",
]

const EXPECTED_ANIMATIONS := [
	"idle", "run", "hurt", "stunned", "death", "kick", "lift", "pickup",
	"throw_weapon", "throw_furniture", "block", "slash", "claw_swipe", "default",
]


func test_slime_scene_is_standalone_and_uses_only_its_fixed_rig() -> void:
	assert_bool(FileAccess.file_exists(SCENE_PATH)).is_true()
	var source := FileAccess.get_file_as_string(SCENE_PATH)
	assert_str(source).contains('[node name="Slime" type="CharacterBody3D"]')
	assert_str(source).contains("res://scenes/characters/enemies/enemy.gd")
	assert_str(source).contains(RIG_PATH)
	assert_str(source).contains(CLAW_PATH)
	assert_int(source.count(".glb")).is_equal(1)
	assert_str(source.to_lower()).not_contains("goblin")
	assert_str(source).not_contains('node name="Slime" instance=')


func test_slime_data_sources_point_only_to_the_new_24px_assets() -> void:
	var roster := FileAccess.get_file_as_string("res://data/enemy_roster.json")
	var preferences := FileAccess.get_file_as_string("res://data/monster_preferences.json")
	assert_str(roster).contains('"rig": "voxel_slime_24px_rig.glb"')
	assert_str(roster).not_contains("voxel_slime_18px")
	assert_str(preferences).contains(
		'"voxel_model": "res://assets/meshes/characters/voxel_slime_24px.glb"'
	)
	assert_str(preferences).not_contains("voxel_slime_18px")


func test_slime_scene_instantiates_small_stats_and_low_wide_collision() -> void:
	var slime := _instantiate_scene()
	if slime == null:
		return
	assert_bool(slime is Enemy).is_true()
	assert_float(float(slime.get("speed"))).is_equal_approx(1.5, 0.001)
	assert_str(String(slime.get("body_size"))).is_equal("small")
	var health := slime.get_node_or_null("HealthComponent") as HealthComponent
	assert_object(health).is_not_null()
	if health != null:
		assert_int(health.max_life).is_equal(6)
		assert_int(health.current_life).is_equal(6)
	var collision := slime.get_node_or_null("CollisionShape") as CollisionShape3D
	assert_object(collision).is_not_null()
	if collision != null:
		var capsule := collision.shape as CapsuleShape3D
		assert_object(capsule).is_not_null()
		if capsule != null:
			assert_float(capsule.radius).is_equal_approx(0.375, 0.0001)
			assert_float(capsule.height).is_equal_approx(0.75, 0.0001)
		assert_float(collision.position.y).is_equal_approx(0.375, 0.0001)
	slime.free()


func test_slime_scene_wires_enemy_components_without_humanoid_weapon_mounts() -> void:
	var slime := _instantiate_scene()
	if slime == null:
		return
	for required_path in [
		"CollisionShape", "EquipmentComponent", "HealthComponent", "NavigationAgent3D",
		"PlayerDetectionArea", "PlayerDetectionArea/CollisionShape3D", "WeaponReachRaycast",
		"ActionAudioStreamPlayer", "FootstepAudioStreamPlayer", "VocalAudioStreamPlayer",
	]:
		assert_object(slime.get_node_or_null(required_path)) \
			.override_failure_message("slime missing runtime node: %s" % required_path).is_not_null()
	var equipment := slime.get_node_or_null("EquipmentComponent") as EquipmentComponent
	assert_object(equipment).is_not_null()
	if equipment != null:
		assert_object(equipment.weapon_data).is_not_null()
		if equipment.weapon_data != null:
			assert_str(equipment.weapon_data.resource_path).is_equal(CLAW_PATH)
		assert_object(equipment.shield_data).is_null()
		assert_object(equipment.weapon_placeholder).is_null()
		assert_object(equipment.shield_placeholder).is_null()
	assert_object(slime.get_node_or_null("character/Armature/Skeleton3D/WeaponBoneAttachment")).is_null()
	assert_object(slime.get_node_or_null("character/Armature/Skeleton3D/ShieldBoneAttachment")).is_null()
	slime.free()


func test_slime_scene_preserves_native_creature_bones_and_animations() -> void:
	var slime := _instantiate_scene()
	if slime == null:
		return
	var skeleton := slime.get_node_or_null("character/Armature/Skeleton3D") as Skeleton3D
	var animation_player := slime.get_node_or_null("character/AnimationPlayer") as AnimationPlayer
	assert_object(skeleton).is_not_null()
	assert_object(animation_player).is_not_null()
	if skeleton != null:
		assert_int(skeleton.get_bone_count()).is_equal(EXPECTED_BONES.size())
		for bone_name in EXPECTED_BONES:
			assert_int(skeleton.find_bone(bone_name)).is_greater_equal(0)
	if animation_player != null:
		for animation_name in EXPECTED_ANIMATIONS:
			assert_bool(animation_player.has_animation(animation_name)) \
				.override_failure_message("slime rig missing animation: %s" % animation_name).is_true()
	slime.free()


func test_slime_scene_exposes_head_and_torso_physical_bones() -> void:
	var slime := _instantiate_scene()
	if slime == null:
		return
	var simulator := slime.get_node_or_null("%PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
	var head := slime.get_node_or_null("%Physical Bone Head") as PhysicalBone3D
	var torso := slime.get_node_or_null("%Physical Bone Torso") as PhysicalBone3D
	assert_object(simulator).is_not_null()
	assert_object(head).is_not_null()
	assert_object(torso).is_not_null()
	if head != null:
		assert_str(head.bone_name).is_equal("Head")
		assert_object(head.get_node_or_null("CollisionShape3D")).is_instanceof(CollisionShape3D)
	if torso != null:
		assert_str(torso.bone_name).is_equal("Torso")
		assert_object(torso.get_node_or_null("CollisionShape3D")).is_instanceof(CollisionShape3D)
	slime.free()


func test_slime_natural_claw_attack_needs_no_visible_equipment_child() -> void:
	var slime := _instantiate_scene()
	if slime == null:
		return
	slime.set_script(null)
	add_child(slime)
	await get_tree().process_frame
	var equipment := slime.get_node("EquipmentComponent") as EquipmentComponent
	assert_bool(equipment.has_weapon()).is_true()
	assert_object(equipment.weapon_data).is_not_null()
	assert_object(equipment.weapon_placeholder).is_null()
	assert_object(equipment.shield_placeholder).is_null()
	slime.queue_free()
	await get_tree().process_frame


func test_slime_enemy_ready_resolves_complete_runtime_contract() -> void:
	var slime := _instantiate_scene() as Enemy
	if slime == null:
		return
	add_child(slime)
	await get_tree().process_frame
	assert_bool(slime.is_inside_tree()).is_true()
	assert_bool(slime.is_in_group("enemies")).is_true()
	assert_int(slime.state).is_equal(Enemy.State.MOVING)
	assert_object(slime.animation_player).is_instanceof(AnimationPlayer)
	assert_object(slime.collision_shape).is_instanceof(CollisionShape3D)
	assert_object(slime.equipment).is_instanceof(EquipmentComponent)
	assert_object(slime.health).is_instanceof(HealthComponent)
	assert_object(slime.nav_agent).is_instanceof(NavigationAgent3D)
	assert_object(slime.skeleton_simulator).is_instanceof(PhysicalBoneSimulator3D)
	assert_object(slime.physical_bone_head).is_instanceof(PhysicalBone3D)
	assert_object(slime.physical_bone_torso).is_instanceof(PhysicalBone3D)
	assert_bool(slime.equipment.has_weapon()).is_true()
	slime.queue_free()
	await get_tree().process_frame


func _instantiate_scene() -> CharacterBody3D:
	assert_bool(FileAccess.file_exists(RIG_PATH)).is_true()
	var packed := load(SCENE_PATH) as PackedScene
	assert_object(packed).override_failure_message("failed to load standalone slime scene").is_not_null()
	if packed == null:
		return null
	var slime := packed.instantiate() as CharacterBody3D
	assert_object(slime).is_not_null()
	return slime
