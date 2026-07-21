extends GdUnitTestSuite
## 统一运行场景转场测试。
## 酒馆与地牢是 World 根场景下的空间切换，不再作为彼此独立的顶层游戏场景。

func test_world_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/world/world.tscn")).is_true()

func test_world_loads_intro_tavern_and_dungeon_as_spaces() -> void:
	var script := load("res://scenes/world/world.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("SPACE_INTRO")).is_true()
	assert_bool(source.contains("res://scenes/intro/new_game_intro.tscn")).is_true()
	assert_bool(source.contains("func transition_to_tavern")).is_true()
	assert_bool(source.contains("func transition_to_dungeon")).is_true()
	assert_bool(source.contains("func load_space")).is_true()
	assert_bool(source.contains("res://scenes/tavern/tavern.tscn")).is_true()
	assert_bool(source.contains("res://scenes/expedition/procedural_dungeon.tscn")).is_true()

func test_tavern_manager_routes_phase_changes_through_world() -> void:
	var script := load("res://globals/tavern/tavern_manager.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("WORLD_SCENE_PATH")).is_true()
	assert_bool(source.contains("_go_to_world_space")).is_true()
	assert_bool(source.contains("complete_intro_and_enter_tavern")).is_true()
	assert_bool(source.contains('_go_to_world_space("intro"')).is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/tavern/tavern.tscn")')) \
		.override_failure_message("TavernManager 不应直接切酒馆子场景").is_false()
	assert_bool(source.contains('change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")')) \
		.override_failure_message("TavernManager 不应直接切地牢子场景").is_false()

func test_zone_select_uses_transition_api_for_expedition() -> void:
	var script := load("res://scenes/ui/zone_select.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("TavernManager.start_expedition")).is_true()
	assert_bool(source.contains('change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")')).is_false()

func test_expedition_prompt_opens_zone_select_overlay_when_in_world() -> void:
	var script := load("res://scenes/ui/expedition_prompt.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("open_zone_select")).is_true()
	assert_bool(source.contains("_find_world")).is_true()

func test_dungeon_does_not_duplicate_shared_ui_under_world() -> void:
	var script := load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_is_running_under_world")).is_true()
	assert_bool(source.contains("World.tscn owns the shared in-game UI")).is_true()

func test_player_skill_input_is_available_in_tavern_and_dungeon() -> void:
	var script := load("res://scenes/characters/player/player.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("_is_skill_input_enabled")) \
		.override_failure_message("F/G 技能输入不应按场景禁用，酒馆和地牢都要可用").is_false()
	assert_bool(source.contains('Input.is_action_just_pressed("kick")')).is_true()
	assert_bool(source.contains('Input.is_action_just_pressed("skill_g")')).is_true()

func test_depart_prompt_does_not_use_f_skill_input() -> void:
	var script := load("res://scenes/ui/expedition_prompt.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains('DEPART_ACTION := "depart"')).is_true()
	assert_bool(source.contains('Input.is_action_pressed("kick")')) \
		.override_failure_message("出发提示不应占用 F/kick，F 是技能栏动作槽").is_false()
