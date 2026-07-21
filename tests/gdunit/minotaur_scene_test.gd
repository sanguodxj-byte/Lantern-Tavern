extends GdUnitTestSuite

const SCENE_PATH := "res://scenes/characters/enemies/minotaur.tscn"
const RIG_PATH := "res://assets/meshes/characters/voxel_minotaur_72px_rig.glb"
const AXE_PATH := "res://data/weapons/axe.tres"

const EXPECTED_BONES := [
	"Root", "Pelvis", "Torso", "Neck", "Head",
	"UpperArm.R", "LowerArm.R", "Hand.R",
	"UpperArm.L", "LowerArm.L", "Hand.L",
	"UpperLeg.R", "LowerLeg.R", "Foot.R",
	"UpperLeg.L", "LowerLeg.L", "Foot.L",
]

const EXPECTED_ANIMATIONS := [
	"idle", "run", "slash", "block", "hurt", "stunned", "death", "kick",
	"lift", "pickup", "throw_weapon", "throw_furniture",
	"default", "hold_weapon", "slash_one_hand", "slash_heavy", "slash_dagger",
	"thrust_spear", "bash_shield", "claw_swipe",
]


func test_minotaur_scene_is_standalone_and_uses_only_its_fixed_rig() -> void:
	assert_bool(FileAccess.file_exists(SCENE_PATH)).is_true()
	var source := FileAccess.get_file_as_string(SCENE_PATH)
	assert_str(source).contains('[node name="Minotaur" type="CharacterBody3D"]')
	assert_str(source).contains("res://scenes/characters/enemies/enemy.gd")
	assert_str(source).contains(RIG_PATH)
	assert_str(source).contains(AXE_PATH)
	assert_int(source.count(".glb")).is_equal(1)
	assert_str(source.to_lower()).not_contains("goblin")
	assert_str(source).not_contains('node name="Minotaur" instance=')


func test_minotaur_scene_instantiates_large_elite_boss_stats_and_collision() -> void:
	var minotaur := _instantiate_scene()
	if minotaur == null:
		return
	assert_bool(minotaur is Enemy).is_true()
	assert_float(float(minotaur.get("speed"))).is_equal_approx(1.2, 0.001)
	assert_bool(bool(minotaur.get("is_elite"))).is_true()
	assert_bool(bool(minotaur.get("is_boss_type"))).is_true()
	assert_str(String(minotaur.get("body_size"))).is_equal("large")

	var health := minotaur.get_node_or_null("HealthComponent") as HealthComponent
	assert_object(health).is_not_null()
	if health != null:
		assert_int(health.max_life).is_equal(28)
		assert_int(health.current_life).is_equal(28)

	var collision := minotaur.get_node_or_null("CollisionShape") as CollisionShape3D
	assert_object(collision).is_not_null()
	if collision != null:
		var capsule := collision.shape as CapsuleShape3D
		assert_object(capsule).is_not_null()
		if capsule != null:
			assert_float(capsule.radius).is_equal_approx(0.4375, 0.0001)
			assert_float(capsule.height).is_equal_approx(2.25, 0.0001)
		assert_float(collision.position.y).is_equal_approx(1.125, 0.0001)
	minotaur.free()


func test_minotaur_scene_wires_required_enemy_components_and_node_paths() -> void:
	var minotaur := _instantiate_scene()
	if minotaur == null:
		return
	for required_path in [
		"CollisionShape",
		"EquipmentComponent",
		"HealthComponent",
		"NavigationAgent3D",
		"PlayerDetectionArea",
		"PlayerDetectionArea/CollisionShape3D",
		"WeaponReachRaycast",
		"ActionAudioStreamPlayer",
		"FootstepAudioStreamPlayer",
		"VocalAudioStreamPlayer",
	]:
		assert_object(minotaur.get_node_or_null(required_path)) \
			.override_failure_message("minotaur missing required runtime node: %s" % required_path) \
			.is_not_null()

	var equipment := minotaur.get_node_or_null("EquipmentComponent") as EquipmentComponent
	assert_object(equipment).is_not_null()
	if equipment != null:
		assert_object(equipment.weapon_data).is_not_null()
		if equipment.weapon_data != null:
			assert_str(equipment.weapon_data.resource_path).is_equal(AXE_PATH)
		assert_object(equipment.shield_data).is_null()
		assert_bool(equipment.weapon_placeholder == minotaur.get_node_or_null(
			"character/Armature/Skeleton3D/WeaponBoneAttachment/WeaponPlaceholder"
		)).is_true()
		assert_bool(equipment.shield_placeholder == minotaur.get_node_or_null(
			"character/Armature/Skeleton3D/ShieldBoneAttachment/ShieldPlaceholder"
		)).is_true()
		assert_bool(equipment.weapon_reach_raycast == minotaur.get_node_or_null(
			"WeaponReachRaycast"
		)).is_true()
	minotaur.free()


func test_minotaur_scene_preserves_native_skeleton_animations_and_hand_mounts() -> void:
	var minotaur := _instantiate_scene()
	if minotaur == null:
		return
	var skeleton := minotaur.get_node_or_null("character/Armature/Skeleton3D") as Skeleton3D
	var animation_player := minotaur.get_node_or_null("character/AnimationPlayer") as AnimationPlayer
	assert_object(skeleton).is_not_null()
	assert_object(animation_player).is_not_null()
	if skeleton != null:
		assert_int(skeleton.get_bone_count()).is_equal(EXPECTED_BONES.size())
		for bone_name in EXPECTED_BONES:
			assert_int(skeleton.find_bone(bone_name)) \
				.override_failure_message("minotaur rig missing bone: %s" % bone_name) \
				.is_greater_equal(0)
	if animation_player != null:
		for animation_name in EXPECTED_ANIMATIONS:
			assert_bool(animation_player.has_animation(animation_name)) \
				.override_failure_message("minotaur rig missing animation: %s" % animation_name) \
				.is_true()

	var weapon_attachment := minotaur.get_node_or_null(
		"character/Armature/Skeleton3D/WeaponBoneAttachment"
	) as BoneAttachment3D
	var shield_attachment := minotaur.get_node_or_null(
		"character/Armature/Skeleton3D/ShieldBoneAttachment"
	) as BoneAttachment3D
	assert_object(weapon_attachment).is_not_null()
	assert_object(shield_attachment).is_not_null()
	if weapon_attachment != null and skeleton != null:
		assert_bool(weapon_attachment.get_parent() == skeleton).is_true()
		assert_str(weapon_attachment.bone_name).is_equal("Hand.R")
		assert_object(weapon_attachment.get_node_or_null("WeaponPlaceholder")).is_not_null()
	if shield_attachment != null and skeleton != null:
		assert_bool(shield_attachment.get_parent() == skeleton).is_true()
		assert_str(shield_attachment.bone_name).is_equal("Hand.L")
		var shield_placeholder := shield_attachment.get_node_or_null("ShieldPlaceholder")
		assert_object(shield_placeholder).is_not_null()
		if shield_placeholder != null:
			assert_int(shield_placeholder.get_child_count()).is_equal(0)
	minotaur.free()


func test_minotaur_scene_exposes_head_and_torso_physical_bones() -> void:
	var minotaur := _instantiate_scene()
	if minotaur == null:
		return
	var skeleton := minotaur.get_node_or_null("character/Armature/Skeleton3D") as Skeleton3D
	var simulator := minotaur.get_node_or_null("%PhysicalBoneSimulator3D") as PhysicalBoneSimulator3D
	var head := minotaur.get_node_or_null("%Physical Bone Head") as PhysicalBone3D
	var torso := minotaur.get_node_or_null("%Physical Bone Torso") as PhysicalBone3D
	assert_object(simulator).is_not_null()
	assert_object(head).is_not_null()
	assert_object(torso).is_not_null()
	if simulator != null and skeleton != null:
		assert_bool(simulator.get_parent() == skeleton).is_true()
	if head != null and simulator != null:
		assert_bool(head.get_parent() == simulator).is_true()
		assert_str(head.bone_name).is_equal("Head")
		assert_object(head.get_node_or_null("CollisionShape3D")).is_instanceof(CollisionShape3D)
	if torso != null and simulator != null:
		assert_bool(torso.get_parent() == simulator).is_true()
		assert_str(torso.bone_name).is_equal("Torso")
		assert_object(torso.get_node_or_null("CollisionShape3D")).is_instanceof(CollisionShape3D)
	minotaur.free()


func test_minotaur_equipment_mounts_only_the_external_axe_on_tree_entry() -> void:
	var minotaur := _instantiate_scene()
	if minotaur == null:
		return
	# Disable Enemy AI while preserving child _ready calls, so this test isolates equipment wiring.
	minotaur.set_script(null)
	add_child(minotaur)
	await get_tree().process_frame
	var equipment := minotaur.get_node("EquipmentComponent") as EquipmentComponent
	var weapon_placeholder := minotaur.get_node(
		"character/Armature/Skeleton3D/WeaponBoneAttachment/WeaponPlaceholder"
	) as Node3D
	var shield_placeholder := minotaur.get_node(
		"character/Armature/Skeleton3D/ShieldBoneAttachment/ShieldPlaceholder"
	) as Node3D
	assert_bool(equipment.has_weapon()).is_true()
	assert_int(weapon_placeholder.get_child_count()).is_equal(1)
	assert_int(shield_placeholder.get_child_count()).is_equal(0)
	if weapon_placeholder.get_child_count() == 1:
		var mounted_weapon := weapon_placeholder.get_child(0)
		assert_object(mounted_weapon).is_instanceof(EquipedItem)
		var mounted_data := mounted_weapon.get("weapon_data") as WeaponData
		assert_object(mounted_data).is_not_null()
		if mounted_data != null:
			assert_str(mounted_data.id).is_equal("axe")
			assert_object(mounted_data.glb_mesh).is_not_null()
			if mounted_data.glb_mesh != null:
				assert_str(mounted_data.glb_mesh.resource_path).is_equal(
					"res://assets/meshes/weapons/weapons_voxel_axe.glb"
				)
	minotaur.queue_free()
	await get_tree().process_frame


func test_minotaur_enemy_ready_resolves_the_complete_runtime_contract() -> void:
	var minotaur := _instantiate_scene() as Enemy
	if minotaur == null:
		return
	add_child(minotaur)
	await get_tree().process_frame
	assert_bool(minotaur.is_inside_tree()).is_true()
	assert_bool(minotaur.is_in_group("enemies")).is_true()
	assert_int(minotaur.state).is_equal(Enemy.State.MOVING)
	assert_object(minotaur.state_node).is_not_null()
	assert_object(minotaur.animation_player).is_instanceof(AnimationPlayer)
	assert_object(minotaur.collision_shape).is_instanceof(CollisionShape3D)
	assert_object(minotaur.equipment).is_instanceof(EquipmentComponent)
	assert_object(minotaur.health).is_instanceof(HealthComponent)
	assert_object(minotaur.nav_agent).is_instanceof(NavigationAgent3D)
	assert_object(minotaur.player_detection_area).is_instanceof(Area3D)
	assert_object(minotaur.weapon_reach_raycast).is_instanceof(RayCast3D)
	assert_object(minotaur.skeleton_simulator).is_instanceof(PhysicalBoneSimulator3D)
	assert_object(minotaur.physical_bone_head).is_instanceof(PhysicalBone3D)
	assert_object(minotaur.physical_bone_torso).is_instanceof(PhysicalBone3D)
	assert_bool(minotaur.equipment.has_weapon()).is_true()
	assert_object(minotaur.equipment.shield_data).is_null()
	assert_int(minotaur.equipment.weapon_placeholder.get_child_count()).is_equal(1)
	assert_int(minotaur.equipment.shield_placeholder.get_child_count()).is_equal(0)
	minotaur.queue_free()
	await get_tree().process_frame


func _instantiate_scene() -> CharacterBody3D:
	assert_bool(FileAccess.file_exists(RIG_PATH)) \
		.override_failure_message("minotaur rig has not been generated yet: %s" % RIG_PATH) \
		.is_true()
	if not FileAccess.file_exists(RIG_PATH):
		return null
	var packed := load(SCENE_PATH) as PackedScene
	assert_object(packed) \
		.override_failure_message("failed to load standalone minotaur scene") \
		.is_not_null()
	if packed == null:
		return null
	var minotaur := packed.instantiate() as CharacterBody3D
	assert_object(minotaur).is_not_null()
	return minotaur
