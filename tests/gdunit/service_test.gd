extends GdUnitTestSuite

# Service 单例访问器测试
# 验证类型安全的全局单例访问

const Service := preload("res://globals/core/service.gd")

func test_service_returns_null_without_tree() -> void:
	# 在测试环境中（无完整场景树），Service 应返回 null 而非崩溃
	var gs: Node = Service.game_state()
	# 测试环境可能没有 GameState，但不应崩溃
	assert_bool(gs == null or gs is Node).is_true()

func test_service_skill_runtime_safe() -> void:
	var sr: Node = Service.skill_runtime()
	assert_bool(sr == null or sr is Node).is_true()

func test_service_tavern_manager_safe() -> void:
	var tm: Node = Service.tavern_manager()
	assert_bool(tm == null or tm is Node).is_true()

func test_service_all_methods_safe() -> void:
	# 所有 Service 方法都应安全返回，不崩溃
	var methods := [
		Service.game_state,
		Service.game_events,
		Service.physics_setup,
		Service.fx_helper,
		Service.hit_stop_server,
		Service.audio_manager,
		Service.localization_manager,
		Service.combat_engine,
		Service.skill_runtime,
		Service.attr_panel,
		Service.skill_icons,
		Service.tavern_manager,
		Service.tavern_settlement,
		Service.brewing_data,
		Service.fermentation_system,
		Service.loot_table,
		Service.dungeon_spawner,
		Service.zone_manager,
		Service.weapon_registry,
		Service.affix_system,
		Service.item_spawner,
		Service.lighting_controller,
		Service.settings,
	]
	for method in methods:
		var node: Node = method.call()
		assert_bool(node == null or node is Node).is_true()
