extends GdUnitTestSuite

const WORLD_SCENE := preload("res://scenes/world/world.tscn")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")

func test_pixel_view_filter_defaults_disabled_without_changing_material_shader() -> void:
	var material_shader_enabled := VOXEL_LIGHTING.is_pixel_shader_enabled()
	var world := WORLD_SCENE.instantiate()
	var pixel_view := world.get_node("PixelView") as PixelView

	assert_bool(pixel_view.filter_enabled).is_false()
	assert_bool(VOXEL_LIGHTING.is_pixel_shader_enabled()).is_equal(material_shader_enabled)

	world.free()

func test_pixel_view_filter_does_not_create_render_viewport_when_disabled() -> void:
	var pixel_view := PixelView.new()
	pixel_view.filter_enabled = false
	add_child(pixel_view)

	assert_bool(pixel_view.visible).is_false()
	assert_int(pixel_view.get_child_count()).is_equal(0)

	pixel_view.queue_free()

func test_pixel_view_capture_tool_supports_unfiltered_tavern_capture() -> void:
	var source := (load("res://tools/pixel_view_ingame_capture.gd") as GDScript).source_code

	assert_str(source).contains("--pixel-filter")
	assert_str(source).contains("--tavern")
	assert_str(source).contains("pixel_view.filter_enabled = capture_filter_enabled")
	assert_str(source).contains("VOXEL_LIGHTING.set_pixel_shader_enabled(true)")
	assert_str(source).contains("dungeon_ingame_unfiltered.png")
	assert_str(source).contains("tavern_ingame_unfiltered.png")
	assert_str(source).contains("world.get(\"current_loaded_level\") != null")
	assert_str(source).contains("String(world.get(\"current_space\")) == target_space")
	assert_str(source).contains("if not capture_tavern:")
