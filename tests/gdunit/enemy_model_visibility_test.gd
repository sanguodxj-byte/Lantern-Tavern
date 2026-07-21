extends GdUnitTestSuite
## 敌人模型渲染层级回归测试
## 验证修复：敌人 Character 网格的 layers 必须与玩家相机的 cull_mask 匹配，否则模型不可见

# ============================================================
# 1. 玩家相机 cull_mask 验证
# ============================================================

func test_player_camera_cull_mask_includes_layer_1() -> void:
	var player_scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	add_child(player)
	var camera := player.get_node("MainCamera") as Camera3D
	# cull_mask 的 bit 0（值 1）对应视觉层 1
	assert_bool((camera.cull_mask & 1) != 0) \
		.override_failure_message("玩家相机 cull_mask 必须包含层 1（bit 0）").is_true()
	player.queue_free()

func test_player_camera_cull_mask_value() -> void:
	var player_scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	add_child(player)
	var camera := player.get_node("MainCamera") as Camera3D
	assert_int(camera.cull_mask).is_equal(1) \
		.override_failure_message("玩家相机 cull_mask 应为 1（仅渲染层 1）")
	player.queue_free()

# ============================================================
# 2. 敌人 Character 网格 layers 验证
# ============================================================

func _visual_meshes(enemy: CharacterBody3D) -> Array[Node]:
	var character := enemy.get_node_or_null("character")
	if character == null:
		return []
	return character.find_children("*", "MeshInstance3D", true, false)


func test_goblin_character_mesh_layers_matches_camera() -> void:
	var goblin_scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := goblin_scene.instantiate() as CharacterBody3D
	add_child(goblin)
	var meshes := _visual_meshes(goblin)
	assert_int(meshes.size()).override_failure_message("goblin 必须包含可视网格").is_greater(0)
	for node in meshes:
		var mesh := node as MeshInstance3D
		assert_bool((mesh.layers & 1) != 0) \
			.override_failure_message("敌人可视网格 %s 必须包含层 1（与相机 cull_mask=1 匹配）" % mesh.name).is_true()
	goblin.queue_free()

func test_goblin_character_mesh_layers_not_only_layer_2() -> void:
	var goblin_scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := goblin_scene.instantiate() as CharacterBody3D
	add_child(goblin)
	var meshes := _visual_meshes(goblin)
	assert_int(meshes.size()).override_failure_message("goblin 必须包含可视网格").is_greater(0)
	for node in meshes:
		var mesh := node as MeshInstance3D
		assert_bool(mesh.layers != 2) \
			.override_failure_message("敌人可视网格 %s 不能仅使用层 2（相机不渲染层 2）" % mesh.name).is_true()
	goblin.queue_free()

# ============================================================
# 3. 场景文件源码验证（防止回归）
# ============================================================

func test_goblin_tscn_does_not_override_character_to_layer_2() -> void:
	var file := FileAccess.open("res://scenes/characters/enemies/goblin.tscn", FileAccess.READ)
	assert_object(file).is_not_null()
	var content := file.get_as_text()
	file.close()
	assert_bool(not content.contains("layers = 2")) \
		.override_failure_message("goblin.tscn Character 节点不能设置 layers = 2（相机不渲染层 2）").is_true()

func test_player_camera_cull_mask_in_tscn() -> void:
	var file := FileAccess.open("res://scenes/characters/player/player.tscn", FileAccess.READ)
	assert_object(file).is_not_null()
	var content := file.get_as_text()
	file.close()
	var cam_idx := content.find('[node name="MainCamera"')
	assert_int(cam_idx).is_greater(-1)
	var next_node_idx := content.find("\n[node", cam_idx + 1)
	if next_node_idx == -1:
		next_node_idx = content.length()
	var cam_section := content.substr(cam_idx, next_node_idx - cam_idx)
	assert_bool(cam_section.contains("cull_mask = 1")) \
		.override_failure_message("玩家相机 cull_mask 应为 1").is_true()
