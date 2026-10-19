extends GdUnitTestSuite

# Contract test: the desktop renderer must be explicitly Forward+ and the
# Android renderer must be explicitly Mobile. Relying on engine defaults is a
# silent portability hazard (finding A5), so these keys must be present in the
# RAW project.godot text, not merely derived from ConfigFile defaults.
# Reference: https://docs.godotengine.org/en/stable/classes/class_projectsettings.html

func test_project_godot_declares_forward_plus_desktop_renderer() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	assert_bool(text.contains('renderer/rendering_method="forward_plus"')).is_true()

func test_project_godot_declares_mobile_renderer_for_android() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	assert_bool(text.contains('renderer/rendering_method.mobile="mobile"')).is_true()

func test_occlusion_culling_setting_is_preserved() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	assert_bool(text.contains("occlusion_culling/use_occlusion_culling=true")).is_true()
