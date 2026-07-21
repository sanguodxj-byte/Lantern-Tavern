extends GdUnitTestSuite
## roster 保留重建声明；只对已验收模型要求运行时场景与 rig。

const MODEL_TIERS := preload("res://data/character_model_tiers.gd")
const ENEMY_SCENE_DIR := "res://scenes/characters/enemies"


func test_enemy_scene_root_contains_only_accepted_models() -> void:
	var scene_files: Array[String] = []
	for file_name in DirAccess.get_files_at(ENEMY_SCENE_DIR):
		if String(file_name).ends_with(".tscn"):
			scene_files.append(String(file_name))
	scene_files.sort()
	var accepted_scene_files: Array[String] = []
	for enemy_id in _accepted_roster_ids():
		accepted_scene_files.append("%s.tscn" % enemy_id)
	accepted_scene_files.sort()
	assert_array(scene_files).is_equal(accepted_scene_files)

func _accepted_roster_ids() -> Array:
	var file := FileAccess.open("res://data/enemy_roster.json", FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var ids: Array = []
	for entry in json.data.get("enemies", []):
		var enemy_id := String(entry["id"])
		if MODEL_TIERS.is_accepted(enemy_id):
			ids.append(enemy_id)
	ids.sort()
	return ids


func _roster_rig(enemy_id: String) -> String:
	var file := FileAccess.open("res://data/enemy_roster.json", FileAccess.READ)
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	for entry in json.data.get("enemies", []):
		if String(entry["id"]) == enemy_id:
			return String(entry["rig"])
	return ""


func test_all_accepted_enemy_scenes_exist() -> void:
	for enemy_id in _accepted_roster_ids():
		var path := "res://scenes/characters/enemies/%s.tscn" % enemy_id
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("敌人场景不存在: %s" % path).is_true()


func test_goblin_uses_voxel_rig_not_character_glb() -> void:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var goblin := auto_free(scene.instantiate()) as CharacterBody3D
	var character := goblin.get_node_or_null("character")
	assert_object(character).is_not_null()
	var anim := goblin.get_node_or_null("character/AnimationPlayer")
	assert_object(anim).is_not_null()
	assert_bool(anim is AnimationPlayer).is_true()


func test_goblin_has_skeleton_at_correct_path() -> void:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := auto_free(scene.instantiate()) as CharacterBody3D
	var skeleton := _find_skeleton(goblin)
	assert_object(skeleton).is_not_null()
	assert_bool(skeleton is Skeleton3D).is_true()


func test_goblin_has_physical_bone_simulator() -> void:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := auto_free(scene.instantiate()) as CharacterBody3D
	var skeleton := _find_skeleton(goblin)
	assert_object(skeleton).is_not_null()
	var simulator := skeleton.find_child("PhysicalBoneSimulator3D", true, false) if skeleton else null
	assert_object(simulator).is_not_null()
	assert_bool(simulator is PhysicalBoneSimulator3D).is_true()


func test_goblin_has_weapon_bone_attachment() -> void:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := auto_free(scene.instantiate()) as CharacterBody3D
	var attach := goblin.find_child("WeaponBoneAttachment", true, false)
	assert_object(attach).is_not_null()
	assert_bool(attach is BoneAttachment3D).is_true()
	var bone_attach := attach as BoneAttachment3D
	assert_str(bone_attach.bone_name).is_equal("Hand.R")


func test_all_accepted_enemy_scenes_bind_their_roster_rig() -> void:
	for enemy_id in _accepted_roster_ids():
		var scene_path := "res://scenes/characters/enemies/%s.tscn" % enemy_id
		var scene := load(scene_path) as PackedScene
		assert_object(scene).override_failure_message("missing scene %s" % enemy_id).is_not_null()

		var rig_name := _roster_rig(enemy_id)
		assert_str(rig_name).override_failure_message("missing roster rig for %s" % enemy_id).is_not_empty()
		var rig_path := "res://assets/meshes/characters/%s" % rig_name
		var bound_rig := _scene_instance_at(scene.get_state(), "./character")
		assert_object(bound_rig) \
			.override_failure_message("%s scene has no character rig instance" % enemy_id).is_not_null()
		assert_str(bound_rig.resource_path) \
			.override_failure_message("%s scene binds the wrong rig" % enemy_id).is_equal(rig_path)

		var rig_scene := load(rig_path) as PackedScene
		assert_object(rig_scene).override_failure_message("missing rig %s" % rig_path).is_not_null()
		var rig_state := rig_scene.get_state()
		for required_type in ["Skeleton3D", "AnimationPlayer", "MeshInstance3D"]:
			assert_bool(_scene_state_has_node_type(rig_state, required_type)) \
				.override_failure_message("%s rig has no %s" % [enemy_id, required_type]).is_true()


func test_all_accepted_rig_glb_files_exist() -> void:
	for enemy_id in _accepted_roster_ids():
		var rig := _roster_rig(enemy_id)
		var path := "res://assets/meshes/characters/%s" % rig
		assert_bool(ResourceLoader.exists(path) or FileAccess.file_exists(path)) \
			.override_failure_message("体素骨骼 GLB 不存在: %s" % path).is_true()


func test_spawner_reports_only_accepted_roster_subset() -> void:
	var spawner: Node = Engine.get_main_loop().root.get_node("DungeonSpawner")
	if spawner.has_method("_load_roster"):
		spawner.call("_load_roster")
	var all_types: Array = spawner.get_all_enemy_types()
	var expected_enemy_ids := _accepted_roster_ids()
	assert_int(all_types.size()).is_equal(expected_enemy_ids.size())
	for enemy_id in expected_enemy_ids:
		assert_bool(all_types.has(enemy_id)).is_true()


func test_future_accepted_player_does_not_create_an_enemy_scene_requirement() -> void:
	assert_bool(_accepted_roster_ids().has("player")).is_false()
	if MODEL_TIERS.is_accepted("player"):
		assert_bool(ResourceLoader.exists("res://scenes/characters/enemies/player.tscn")).is_false()


func test_goblin_collects_visual_meshes_without_material_override() -> void:
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var enemy := auto_free(scene.instantiate())
	assert_bool(enemy.has_method("_collect_visual_meshes")).is_true()
	enemy.call("_collect_visual_meshes")
	var meshes: Array = enemy.get("_visual_meshes")
	assert_int(meshes.size()).is_greater(0)
	for mesh in meshes:
		assert_object((mesh as MeshInstance3D).material_override).is_null()


func _scene_instance_at(state: SceneState, node_path: String) -> PackedScene:
	for node_index in state.get_node_count():
		if String(state.get_node_path(node_index)) == node_path:
			return state.get_node_instance(node_index) as PackedScene
	return null


func _scene_state_has_node_type(state: SceneState, expected_type: String) -> bool:
	for node_index in state.get_node_count():
		if String(state.get_node_type(node_index)) == expected_type:
			return true
	return false


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
