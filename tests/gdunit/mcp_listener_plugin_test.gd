extends GdUnitTestSuite

func test_mcp_listener_plugin_is_installed_and_enabled() -> void:
	assert_bool(FileAccess.file_exists("res://addons/mcp_listener/plugin.cfg")).is_true()
	assert_bool(FileAccess.file_exists("res://addons/mcp_listener/McpEditorPlugin.cs")).is_true()
	var project_source := FileAccess.get_file_as_string("res://project.godot")
	assert_bool(project_source.contains("config/features=PackedStringArray(\"4.7\", \"C#\")")).is_true()
	assert_bool(project_source.contains("res://addons/mcp_listener/plugin.cfg")).is_true()

func test_mcp_listener_project_builds_as_godot_net_project() -> void:
	assert_bool(FileAccess.file_exists("res://LanternTavern.csproj")).is_true()
	var project_source := FileAccess.get_file_as_string("res://LanternTavern.csproj")
	assert_bool(project_source.contains("Godot.NET.Sdk/4.7.0")).is_true()
	assert_bool(project_source.contains("addons\\mcp_listener\\*.cs")).is_true()
