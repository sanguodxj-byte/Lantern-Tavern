extends GdUnitTestSuite

func test_main_menu_tutorial_options() -> void:
	var main_menu_script := load("res://scenes/ui/main_menu.gd") as GDScript
	var source := main_menu_script.source_code
	
	# Check main menu has tutorial flow
	assert_bool(source.contains("tutorial_choice_panel")).is_true()
	assert_bool(source.contains("start_with_tutorial_btn")).is_true()
	assert_bool(source.contains("skip_tutorial_btn")).is_true()
	assert_bool(source.contains("TavernManager.start_new_game"))

func test_world_space_tutorial_integration() -> void:
	var world_script := load("res://scenes/world/world.gd") as GDScript
	var source := world_script.source_code
	
	# Check world space management
	assert_bool(source.contains("SPACE_INTRO")).is_true()
	assert_bool(source.contains("SPACE_TAVERN")).is_true()
	assert_bool(source.contains("SPACE_DUNGEON")).is_true()
	assert_bool(source.contains("INTRO_SCENE_PATH")).is_true()
	assert_bool(source.contains("load_space"))

func test_tutorial_localization_support() -> void:
	# Test that tutorial dialogue uses translation system
	var intro_script := load("res://scenes/intro/new_game_intro.gd") as GDScript
	var tutorial_script := load("res://scenes/tavern/tutorial_tavern_coordinator.gd") as GDScript
	
	var intro_source := intro_script.source_code
	var tutorial_source := tutorial_script.source_code
	
	# Check for translation calls
	assert_bool(intro_source.contains('tr("hey! you! finally wake')).is_true()
	assert_bool(intro_source.contains('tr("WASD Move')).is_true()
	assert_bool(tutorial_source.contains('tr("Move away from the door')).is_true()
	assert_bool(tutorial_source.contains('tr("Grab the barrel')).is_true()
