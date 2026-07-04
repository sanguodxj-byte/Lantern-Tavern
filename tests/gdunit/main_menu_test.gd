extends GdUnitTestSuite

# Tests for MainMenu scene loading and shortcuts

# We test scene references directly without instantiating MainMenu,
# because MainMenu depends on @onready scene node references


func test_start_game_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/expedition/procedural_dungeon.tscn")) \
		.override_failure_message("Procedural dungeon scene not found") \
		.is_true()


func test_continue_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/tavern_ui.tscn")).is_true()


func test_gallery_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/model_viewer.tscn")).is_true()


func test_settings_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_panel.tscn")).is_true()

