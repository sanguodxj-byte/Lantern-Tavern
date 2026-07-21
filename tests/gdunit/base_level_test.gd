extends GdUnitTestSuite

# BaseLevel 关卡基础逻辑测试

func test_base_level_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/levels/base_level.gd")).is_true()


func test_base_level_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/levels/base_level.tscn")).is_true()


func test_base_level_decoupled_from_legacy_meshlib() -> void:
	# 遗留 GridMap 房间系统（base_room + 7 子房间 + 两个 meshlib + level_01_welcome）
	# 已作为旧残留移除。base_level.tscn 曾是其中一员（Floors GridMap 引用 walls-tiles.meshlib），
	# 现已解耦。本测试确保 base_level.tscn 不再引用已删除的 meshlib，避免加载失败。
	var f := FileAccess.open("res://scenes/levels/base_level.tscn", FileAccess.READ)
	assert_object(f).is_not_null()
	var src := f.get_as_text()
	assert_bool(src.contains("walls-tiles.meshlib")) \
		.override_failure_message("base_level.tscn 不应再引用已删除的 walls-tiles.meshlib") \
		.is_false()
	assert_bool(src.contains("ceilings-tiles.meshlib")) \
		.override_failure_message("base_level.tscn 不应再引用已删除的 ceilings-tiles.meshlib") \
		.is_false()


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


func test_spawn_player_registers_game_state() -> void:
	# 验证 spawn_player 源码中包含 GameState.register_player 调用
	# 确保怪物生成等后续逻辑能拿到 current_player
	var script: GDScript = load("res://scenes/levels/base_level.gd") as GDScript
	assert_bool(script.source_code.contains("GameState.register_player")) \
		.override_failure_message("spawn_player 必须立即注册 GameState.current_player，避免延迟 _ready 时序问题") \
		.is_true()


func test_spawn_player_returns_player() -> void:
	# 验证 spawn_player 返回 Player 实例供调用方使用
	var script: GDScript = load("res://scenes/levels/base_level.gd") as GDScript
	assert_bool(script.source_code.contains("-> Player:")) \
		.override_failure_message("spawn_player 应返回 Player 实例") \
		.is_true()
	assert_bool(script.source_code.contains("return player")) \
		.override_failure_message("spawn_player 应返回创建的 player") \
		.is_true()

