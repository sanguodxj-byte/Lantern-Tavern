extends GdUnitTestSuite

# GameEvents 信号定义完整性测试
# 以及全局 autoload 基础测试

func test_game_events_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://globals/game_events.gd")).is_true()


func test_impact_intensity_enum() -> void:
	assert_int(GameEvents.ImpactIntensity.LOW).is_equal(0)
	assert_int(GameEvents.ImpactIntensity.MEDIUM).is_equal(1)
	assert_int(GameEvents.ImpactIntensity.HIGH).is_equal(2)


func test_game_events_has_core_signals() -> void:
	var script = load("res://globals/game_events.gd") as GDScript
	var source = script.source_code
	var required_signals = [
		"signal impact_felt",
		"signal current_keys_changed",
		"signal level_restarted",
		"signal player_dead",
		"signal player_hurt",
		"signal player_spawned",
		"signal possible_action_changed",
		"signal shield_changed",
		"signal weapon_changed",
	]
	for sig in required_signals:
		assert_bool(source.contains(sig)) \
			.override_failure_message("缺少信号: " + sig).is_true()


func test_autoloads_exist() -> void:
	var autoloads = ["TavernManager", "GameState", "GameEvents", "ZoneManager", "BrewingData", "CombatEngine"]
	for name in autoloads:
		assert_bool(Engine.get_main_loop().root.has_node(name)) \
			.override_failure_message("autoload 缺失: " + name).is_true()


func test_audio_manager_autoload_exists() -> void:
	assert_bool(Engine.get_main_loop().root.has_node("AudioManager")).is_true()


func test_fx_helper_autoload_exists() -> void:
	assert_bool(Engine.get_main_loop().root.has_node("FxHelper")).is_true()


func test_hit_stop_server_autoload_exists() -> void:
	assert_bool(Engine.get_main_loop().root.has_node("HitStopServer")).is_true()


func test_localization_manager_autoload_exists() -> void:
	assert_bool(Engine.get_main_loop().root.has_node("LocalizationManager")).is_true()
