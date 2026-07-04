extends GdUnitTestSuite

# Integration sanity checks: key scenes exist and reference the registry correctly.

func test_model_viewer_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/model_viewer.tscn")).is_true()


func test_character_panel_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/ui/character_panel.tscn")).is_true()


func test_weapon_registry_autoload_registered() -> void:
	assert_bool(WeaponRegistry != null).is_true()
	assert_int(WeaponRegistry.get_all_ids().size()).is_greater_equal(10)


func test_model_viewer_uses_weapon_registry() -> void:
	var script = load("res://scenes/ui/model_viewer.gd")
	var source = script.source_code
	assert_bool(source.contains("WeaponRegistry")).is_true()


func test_character_panel_gear_list_exists() -> void:
	var script = load("res://scenes/ui/character_panel.gd")
	var source = script.source_code
	# The panel has a gear_list ItemList and calls _load_gear_list
	assert_bool(source.contains("_load_gear_list")).is_true()
