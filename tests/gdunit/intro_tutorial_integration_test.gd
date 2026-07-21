extends GdUnitTestSuite

func test_complete_tutorial_integration() -> void:
	# Test that all tutorial components work together
	assert_bool(ResourceLoader.exists("res://scenes/intro/new_game_intro.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/intro/new_game_intro.gd")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/tavern/tutorial_tavern_coordinator.gd")).is_true()
	
	# Test UI components exist
	assert_bool(ResourceLoader.exists("res://scenes/ui/scripted_dialogue_box.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/ui/tutorial_hint_overlay.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_name_prompt.tscn")).is_true()
	
	# Test tutorial assets exist
	assert_bool(ResourceLoader.exists("res://assets/models/environment/environment_tutorial_cart_wreck.glb")).is_true()
	assert_bool(ResourceLoader.exists("res://assets/models/environment/environment_tutorial_forest_cluster.glb")).is_true()
	assert_bool(ResourceLoader.exists("res://assets/models/environment/environment_tutorial_entrance_ruins.glb")).is_true()
	assert_bool(ResourceLoader.exists("res://assets/models/environment/environment_tutorial_road_blocker.glb")).is_true()
	
	# Test shader exists
	assert_bool(ResourceLoader.exists("res://assets/shaders/blur_overlay.gdshader")).is_true()

func test_tutorial_scripts_have_required_methods() -> void:
	var intro_script := load("res://scenes/intro/new_game_intro.gd") as GDScript
	var intro_source := intro_script.source_code
	
	# Check intro sequence methods
	assert_bool(intro_source.contains("_run_intro_sequence")).is_true()
	assert_bool(intro_source.contains("dialogue_box.show_line")).is_true()
	assert_bool(intro_source.contains("hint_overlay.show_hint")).is_true()
	assert_bool(intro_source.contains("player.set_tutorial_input_enabled")).is_true()
	
	var tutorial_script := load("res://scenes/tavern/tutorial_tavern_coordinator.gd") as GDScript
	var tutorial_source := tutorial_script.source_code
	
	# Check tutorial flow methods
	assert_bool(tutorial_source.contains("Stage.WAIT_LEAVE_DOOR")).is_true()
	assert_bool(tutorial_source.contains("_spawn_tutorial_goblin")).is_true()
	assert_bool(tutorial_source.contains("_spawn_barrel")).is_true()
	assert_bool(tutorial_source.contains("_spawn_weapon_pickup")).is_true()
	assert_bool(tutorial_source.contains("_open_name_prompt")).is_true()

func test_tavern_manager_tutorial_integration() -> void:
	var tavern_manager_script := load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source := tavern_manager_script.source_code
	
	# Check tutorial management methods
	assert_bool(source.contains("tutorial_active")).is_true()
	assert_bool(source.contains("tutorial_completed")).is_true()
	assert_bool(source.contains("start_new_game"))
	assert_bool(source.contains("complete_intro_and_enter_tavern")).is_true()
	assert_bool(source.contains("confirm_player_name")).is_true()

func test_player_tutorial_input_management() -> void:
	var player_script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := player_script.source_code
	
	# Check tutorial input control
	assert_bool(source.contains("movement_input_enabled")).is_true()
	assert_bool(source.contains("interaction_input_enabled")).is_true()
	assert_bool(source.contains("combat_input_enabled")).is_true()
	assert_bool(source.contains("set_tutorial_input_enabled")).is_true()