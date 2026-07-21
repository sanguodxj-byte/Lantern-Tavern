extends GdUnitTestSuite

func test_intro_scene_and_script_exist() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/intro/new_game_intro.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/intro/new_game_intro.gd")).is_true()

func test_intro_script_contains_dialogue_hint_and_tavern_handoff() -> void:
	var script := load("res://scenes/intro/new_game_intro.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("play_wakeup_blink")).is_true()
	assert_bool(source.contains("GameEvents.subtitle_changed.emit")).is_true()
	assert_bool(source.contains("GameEvents.tutorial_hint_changed.emit")).is_true()
	assert_bool(source.contains("TavernManager.complete_intro_and_enter_tavern")).is_true()
	assert_bool(source.contains("tutorial_locked_message")).is_true()
