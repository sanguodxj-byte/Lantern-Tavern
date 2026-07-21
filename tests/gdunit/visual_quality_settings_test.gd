extends GdUnitTestSuite

# Regression guards for the scene readability tuning.

const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"


func test_main_menu_overlay_preserves_background_readability() -> void:
	var menu: Control = load(MAIN_MENU_PATH).instantiate()
	add_child(menu)
	var overlay: ColorRect = menu.get_node("ColorRectOverlay")
	assert_bool(overlay.color.a <= 0.35).is_true()
	assert_bool(overlay.color.a > 0.0).is_true()
	remove_child(menu)
	menu.free()

func test_desktop_renderer_is_explicitly_forward_plus() -> void:
	assert_str(str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))).is_equal("forward_plus")


func test_tavern_environment_keeps_lighting_readable() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/tavern/tavern.tscn")
	assert_str(scene_source).contains("ambient_light_energy = 0.34")
	assert_str(scene_source).contains("fog_density = 0.006")
