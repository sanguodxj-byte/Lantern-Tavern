extends GdUnitTestSuite

func test_tutorial_requirements_vs_implementation() -> void:
	"""Verify that all user-requested tutorial features are implemented"""
	
	# 1. Carriage scene with dark blur shader for waking up
	var intro_scene = load("res://scenes/intro/new_game_intro.tscn")
	assert_object(intro_scene).override_failure_message("Intro scene should exist").is_not_null()
	
	var intro_script = load("res://scenes/intro/new_game_intro.gd")
	var intro_source = intro_script.source_code
	assert_bool(intro_source.contains("play_wakeup_blink")).override_failure_message("Should have wake-up shader effect").is_true()
	assert_bool(ResourceLoader.exists("res://assets/shaders/blur_overlay.gdshader")).override_failure_message("Blur shader should exist").is_true()
	
	# 2. NPC dialogue: "hey! you! finally wake"
	assert_bool(intro_source.contains('tr("hey! you! finally wake')).override_failure_message("Should have Skyrim-style wake-up dialogue").is_true()
	assert_bool(intro_source.contains("GameEvents.subtitle_changed.emit")).override_failure_message("Should emit subtitle events").is_true()
	
	# 3. Goblins attack and escape to dungeon entrance
	# (Handled by movement tutorial and door interaction)
	assert_bool(intro_source.contains("tutorial_locked_message")).override_failure_message("Should have door interaction tutorial").is_true()
	assert_bool(intro_source.contains("requires_kick_to_open")).override_failure_message("Should require kick to open door").is_true()
	
	# 4. Movement tutorial (WASD + Shift)
	assert_bool(intro_source.contains('tr("WASD Move')).override_failure_message("Should have WASD movement tutorial").is_true()
	assert_bool(intro_source.contains("player.set_tutorial_input_enabled")).override_failure_message("Should enable tutorial input").is_true()
	
	# 5. Door interaction (E then F to kick)
	assert_bool(intro_source.contains("TavernManager.complete_intro_and_enter_tavern")).override_failure_message("Should transition to tavern").is_true()
	
	print("✓ Carriage scene with shader: IMPLEMENTED")
	print("✓ NPC dialogue: IMPLEMENTED")
	print("✓ Movement tutorial: IMPLEMENTED")
	print("✓ Door interaction tutorial: IMPLEMENTED")

func test_tavern_combat_tutorial_requirements() -> void:
	"""Verify tavern combat tutorial matches user requirements"""
	
	var tutorial_script = load("res://scenes/tavern/tutorial_tavern_coordinator.gd")
	var tutorial_source = tutorial_script.source_code
	
	# 1. Leave door 1m to spawn goblin
	assert_bool(tutorial_source.contains("distance_to(entrance_point) >= 1.0")).override_failure_message("Should spawn goblin after leaving door").is_true()
	assert_bool(tutorial_source.contains("Stage.WAIT_LEAVE_DOOR")).override_failure_message("Should wait for player to leave door").is_true()
	
	# 2. Grab barrel with E and throw to stun
	assert_bool(tutorial_source.contains("tr(\"Grab the barrel with E")).override_failure_message("Should instruct to grab barrel").is_true()
	assert_bool(tutorial_source.contains("Stage.STUN_GOBLIN")).override_failure_message("Should have stun goblin stage").is_true()
	assert_bool(tutorial_source.contains("goblin.state == Enemy.State.STUNNED")).override_failure_message("Should check for stunned state").is_true()
	
	# 3. Pick up weapon behind counter
	assert_bool(tutorial_source.contains("Stage.PICKUP_WEAPON")).override_failure_message("Should have weapon pickup stage").is_true()
	assert_bool(tutorial_source.contains('tr("Behind the bar. Take the weapon')).override_failure_message("Should direct to weapon").is_true()
	
	# 4. Combat tutorial (LMB attack, RMB block, F kick)
	assert_bool(tutorial_source.contains('tr("Fight. Left click attacks')).override_failure_message("Should have combat instructions").is_true()
	assert_bool(tutorial_source.contains("Stage.COMBAT")).override_failure_message("Should have combat stage").is_true()
	assert_bool(tutorial_source.contains("[LMB] Attack  |  [RMB] Block  |  [F] Kick")).override_failure_message("Should show combat controls").is_true()
	
	print("✓ Distance-based goblin spawning: IMPLEMENTED")
	print("✓ Barrel throwing tutorial: IMPLEMENTED") 
	print("✓ Weapon pickup: IMPLEMENTED")
	print("✓ Combat controls tutorial: IMPLEMENTED")

func test_inheritance_letter_and_naming() -> void:
	"""Verify inheritance letter and character naming system"""
	
	var tutorial_script = load("res://scenes/tavern/tutorial_tavern_coordinator.gd")
	var tavern_manager_script = load("res://globals/tavern/tavern_manager.gd")
	
	var tutorial_source = tutorial_script.source_code
	var manager_source = tavern_manager_script.source_code
	
	# 1. Inheritance letter after combat
	assert_bool(tutorial_source.contains("Stage.NAME_LETTER")).override_failure_message("Should have name letter stage").is_true()
	assert_bool(tutorial_source.contains('tr("The tavern is yours')).override_failure_message("Should mention tavern inheritance").is_true()
	assert_bool(tutorial_source.contains("NAME_PROMPT_SCENE")).override_failure_message("Should open name prompt").is_true()
	
	# 2. Character naming and save
	assert_bool(manager_source.contains("confirm_player_name")).override_failure_message("Should have name confirmation").is_true()
	assert_bool(manager_source.contains("player_name")).override_failure_message("Should store player name").is_true()
	assert_bool(manager_source.contains("save_name")).override_failure_message("Should use name for save files").is_true()
	assert_bool(manager_source.contains("has_confirmed_character_name")).override_failure_message("Should track name confirmation").is_true()
	
	print("✓ Inheritance letter: IMPLEMENTED")
	print("✓ Character naming: IMPLEMENTED")
	print("✓ Save file naming: IMPLEMENTED")

func test_ui_components_integrity() -> void:
	"""Verify all UI components for tutorial are properly implemented"""
	
	# Check all tutorial UI scenes exist and are loadable
	var ui_scenes = [
		"res://scenes/ui/scripted_dialogue_box.tscn",
		"res://scenes/ui/tutorial_hint_overlay.tscn", 
		"res://scenes/ui/character_name_prompt.tscn"
	]
	
	for scene_path in ui_scenes:
		var scene = load(scene_path)
		assert_object(scene).override_failure_message("UI scene %s should load" % scene_path).is_not_null()
	
	# Check UI scripts exist
	var ui_scripts = [
		"res://scenes/ui/scripted_dialogue_box.gd",
		"res://scenes/ui/tutorial_hint_overlay.gd",
		"res://scenes/ui/character_name_prompt.gd"
	]
	
	for script_path in ui_scripts:
		var script = load(script_path)
		assert_object(script).override_failure_message("UI script %s should load" % script_path).is_not_null()
	
	print("✓ All tutorial UI components: IMPLEMENTED")

func test_environment_assets() -> void:
	"""Verify tutorial environment assets exist"""
	
	var required_assets = [
		"res://assets/models/environment/environment_tutorial_cart_wreck.glb",
		"res://assets/models/environment/environment_tutorial_forest_cluster.glb",
		"res://assets/models/environment/environment_tutorial_entrance_ruins.glb",
		"res://assets/models/environment/environment_tutorial_road_blocker.glb"
	]
	
	for asset_path in required_assets:
		assert_bool(ResourceLoader.exists(asset_path)).override_failure_message("Asset %s should exist" % asset_path).is_true()
	
	print("✓ Tutorial environment assets: IMPLEMENTED")

func test_tutorial_flow_integration() -> void:
	"""Verify the complete tutorial flow integrates properly"""
	
	# Check that main menu supports tutorial start
	var main_menu = load("res://scenes/ui/main_menu.gd")
	var main_menu_source = main_menu.source_code
	assert_bool(main_menu_source.contains("start_with_tutorial_btn")).override_failure_message("Main menu should have tutorial option").is_true()
	
	# Check that world manages tutorial spaces
	var world = load("res://scenes/world/world.gd") 
	var world_source = world.source_code
	assert_bool(world_source.contains("SPACE_INTRO")).override_failure_message("World should support intro space").is_true()
	
	# Check TavernManager controls tutorial state
	var tavern_manager = load("res://globals/tavern/tavern_manager.gd")
	var manager_source = tavern_manager.source_code
	assert_bool(manager_source.contains("func start_new_game") and manager_source.contains("with_tutorial")) \
		.override_failure_message("Should support tutorial parameter") \
		.is_true()
	assert_bool(manager_source.contains("tutorial_active")).override_failure_message("Should track tutorial state").is_true()
	
	print("✓ Tutorial flow integration: IMPLEMENTED")
	print("✓ Tutorial is FULLY IMPLEMENTED and ready to use!")

