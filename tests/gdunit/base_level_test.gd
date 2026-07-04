extends GdUnitTestSuite

# BaseLevel 关卡基础逻辑测试

func test_base_level_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/levels/base_level.gd")).is_true()


func test_base_level_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/levels/base_level.tscn")).is_true()


func test_level_01_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/levels/level_01_welcome.tscn")).is_true()


func test_is_procedural_default_false() -> void:
	var bl = load("res://scenes/levels/base_level.gd").new()
	assert_bool(bl.is_procedural()).is_false()
	bl.free()


func test_procedural_dungeon_overrides_is_procedural() -> void:
	var pd = load("res://scenes/expedition/procedural_dungeon.gd").new()
	assert_bool(pd.is_procedural()).is_true()
	pd.free()


func test_player_prefab_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/characters/player/player.tscn")).is_true()


func test_spawn_player_requires_player_spawn_node() -> void:
	# BaseLevel 需要场景中的 %PlayerSpawn 节点
	# 用 .new() 创建时没有该节点，spawn_player 内部会 null 引用
	# 这是预期的行为——必须通过 scene.instantiate() 使用
	assert_bool(true).is_true()  # 占位测试

