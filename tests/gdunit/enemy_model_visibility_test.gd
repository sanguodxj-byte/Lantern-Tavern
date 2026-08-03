extends GdUnitTestSuite
## 敌人模型渲染层级回归测试
## 玩家补光只照地形，因此敌人必须使用独立视觉层，同时仍被玩家相机渲染。

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

func test_player_camera_cull_mask_includes_terrain_and_enemy_layers() -> void:
	var player_scene := load("res://scenes/characters/player/player.tscn") as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	add_child(player)
	var camera := player.get_node("MainCamera") as Camera3D
	assert_int(camera.cull_mask).is_equal(3) \
		.override_failure_message("玩家相机必须同时渲染地形层 1 和怪物层 2")
	player.queue_free()

# ============================================================
# 2. 敌人 Character 网格 layers 验证
# ============================================================

func _visual_meshes(enemy: CharacterBody3D) -> Array[Node]:
	var character := enemy.get_node_or_null("character")
	if character == null:
		return []
	return character.find_children("*", "MeshInstance3D", true, false)


func test_goblin_character_meshes_use_enemy_only_render_layer() -> void:
	var goblin_scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := goblin_scene.instantiate() as CharacterBody3D
	add_child(goblin)
	var meshes := _visual_meshes(goblin)
	assert_int(meshes.size()).override_failure_message("goblin 必须包含可视网格").is_greater(0)
	for node in meshes:
		var mesh := node as MeshInstance3D
		assert_int(mesh.layers) \
			.override_failure_message("敌人可视网格 %s 必须仅使用怪物层 2" % mesh.name) \
			.is_equal(2)
	goblin.queue_free()

func test_goblin_character_meshes_remain_visible_to_player_camera() -> void:
	var goblin_scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := goblin_scene.instantiate() as CharacterBody3D
	add_child(goblin)
	var player := (load("res://scenes/characters/player/player.tscn") as PackedScene).instantiate()
	var camera := player.get_node("MainCamera") as Camera3D
	var meshes := _visual_meshes(goblin)
	assert_int(meshes.size()).override_failure_message("goblin 必须包含可视网格").is_greater(0)
	for node in meshes:
		var mesh := node as MeshInstance3D
		assert_bool((mesh.layers & camera.cull_mask) != 0) \
			.override_failure_message("敌人可视网格 %s 的怪物层必须包含在玩家相机掩码中" % mesh.name).is_true()
	player.free()
	goblin.queue_free()

func test_goblin_imposter_uses_enemy_only_render_layer() -> void:
	var goblin_scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	var goblin := goblin_scene.instantiate() as CharacterBody3D
	add_child(goblin)
	var imposter := goblin.get_node_or_null("ImposterSprite") as Sprite3D
	assert_object(imposter).is_not_null()
	assert_int(imposter.layers).is_equal(2)
	goblin.queue_free()

# ============================================================
# 3. 场景文件源码验证（防止回归）
# ============================================================

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
	assert_bool(cam_section.contains("cull_mask = 3")) \
		.override_failure_message("玩家相机必须在场景资源中启用地形层 1 和怪物层 2").is_true()
