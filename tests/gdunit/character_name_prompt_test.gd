extends GdUnitTestSuite

func test_character_name_prompt_scene_and_script_exist() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_name_prompt.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_name_prompt.gd")).is_true()

func test_character_name_prompt_confirms_name_through_tavern_manager() -> void:
	var script := load("res://scenes/ui/character_name_prompt.gd") as GDScript
	var source := script.source_code
	assert_bool(source.contains("signal name_confirmed")).is_true()
	assert_bool(source.contains("TavernManager.confirm_player_name")).is_true()
	assert_bool(source.contains("Please write your name.")).is_true()
	assert_bool(source.contains("handprint.visible = true")).is_true()
