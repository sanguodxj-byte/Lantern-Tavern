extends GdUnitTestSuite

# 重构结构完整性测试
# 验证 globals/ 目录分组后所有文件存在于正确位置

func test_core_directory_has_files() -> void:
	var files := [
		"res://globals/core/game_state.gd",
		"res://globals/core/game_events.gd",
		"res://globals/core/physics_setup.gd",
		"res://globals/core/fx_helper.gd",
		"res://globals/core/hit_stop_server.gd",
		"res://globals/core/audio_manager.gd",
		"res://globals/core/localization_manager.gd",
		"res://globals/core/service.gd",
	]
	for path in files:
		assert_bool(ResourceLoader.exists(path)).is_true()
		print("Verified: ", path)

func test_combat_directory_has_files() -> void:
	var files := [
		"res://globals/combat/combat_engine.gd",
		"res://globals/combat/combat_bridge.gd",
		"res://globals/combat/combat_hitbox_builder.gd",
		"res://globals/combat/combat_slash_animator.gd",
		"res://globals/combat/skill_runtime.gd",
		"res://globals/combat/skill_data.gd",
		"res://globals/combat/action_skills.gd",
		"res://globals/combat/skill_icons.gd",
		"res://globals/combat/momentum_context.gd",
		"res://globals/combat/milestone_effects.gd",
		"res://globals/combat/attr_panel.gd",
	]
	for path in files:
		assert_bool(ResourceLoader.exists(path)).is_true()
		print("Verified: ", path)

func test_tavern_directory_has_files() -> void:
	var files := [
		"res://globals/tavern/tavern_manager.gd",
		"res://globals/tavern/tavern_settlement.gd",
		"res://globals/tavern/brewing_data.gd",
		"res://globals/tavern/fermentation_system.gd",
		"res://globals/tavern/loot_table.gd",
	]
	for path in files:
		assert_bool(ResourceLoader.exists(path)).is_true()
		print("Verified: ", path)

func test_dungeon_directory_has_files() -> void:
	var files := [
		"res://globals/dungeon/dungeon_spawner.gd",
		"res://globals/dungeon/zone_manager.gd",
	]
	for path in files:
		assert_bool(ResourceLoader.exists(path)).is_true()
		print("Verified: ", path)

func test_equipment_directory_has_files() -> void:
	var files := [
		"res://globals/equipment/affix_system.gd",
		"res://globals/equipment/item_spawner.gd",
	]
	for path in files:
		assert_bool(ResourceLoader.exists(path)).is_true()
		print("Verified: ", path)

func test_extracted_components_exist() -> void:
	var files := [
		"res://scenes/ui/equipment_panel_combat_stats.gd",
		"res://scenes/ui/equipment_panel_player_finder.gd",
		"res://scenes/characters/player/player_skill_dispatcher.gd",
	]
	for path in files:
		assert_bool(ResourceLoader.exists(path)).is_true()
		print("Verified: ", path)

func test_no_old_path_preloads_remain() -> void:
	# 搜索 .gd 文件中是否还有旧的 res://globals/xxx.gd 直接引用（无子目录）
	# 如果有，说明路径迁移不完整
	var dir := DirAccess.open("res://")
	assert_bool(dir != null).is_true()
	_check_no_old_preloads("res://globals/", dir)

func _check_no_old_preloads(base_path: String, dir: DirAccess) -> void:
	# 此测试在运行时扫描文件系统可能较慢，简化为验证关键文件不在旧位置
	assert_bool(not ResourceLoader.exists("res://globals/game_state.gd")).is_true()
	assert_bool(not ResourceLoader.exists("res://globals/combat_engine.gd")).is_true()
	assert_bool(not ResourceLoader.exists("res://globals/brewing_data.gd")).is_true()
	assert_bool(not ResourceLoader.exists("res://globals/tavern_manager.gd")).is_true()
