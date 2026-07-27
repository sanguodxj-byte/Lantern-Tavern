extends GdUnitTestSuite

const CAPTURE_TOOL := "res://tools/dungeon_hazard_visual_capture.gd"
const CAPTURE_PATH := "res://reports/dungeon_hazards_preview/dungeon_hazards_real3d.png"
const GENERATOR := preload("res://scenes/expedition/dungeon_generator.gd")
const CONFIG := preload("res://scenes/expedition/dungeon_generation_config.gd")
const HAZARD_PLANNER := preload("res://scenes/expedition/dungeon_hazard_planner.gd")
const BUILDER := preload("res://scenes/expedition/dungeon_scene_builder.gd")
const HAZARD_SCENES := [
	"res://scenes/traps/spikes_trap.tscn",
	"res://scenes/traps/acid_trap.tscn",
	"res://scenes/traps/flame_vent_trap.tscn",
]

func test_hazard_prefabs_have_real_visual_meshes() -> void:
	for path in HAZARD_SCENES:
		var scene := load(path) as PackedScene
		assert_object(scene).is_not_null()
		var instance := scene.instantiate()
		assert_int(_count_meshes(instance)).override_failure_message("陷阱没有可见 Mesh: %s" % path).is_greater_equal(1)
		instance.free()

func test_hazard_capture_tool_targets_real_3d_scenes() -> void:
	assert_bool(FileAccess.file_exists(CAPTURE_TOOL)).is_true()
	var source := FileAccess.get_file_as_string(CAPTURE_TOOL)
	assert_str(source).contains("SubViewport")
	assert_str(source).contains("Camera3D")
	assert_str(source).contains("save_png")
	assert_str(source).contains("spikes_trap.tscn")
	assert_str(source).contains("acid_trap.tscn")
	assert_str(source).contains("flame_vent_trap.tscn")

func test_built_hazards_are_registered_for_visual_streaming() -> void:
	var config := CONFIG.new()
	config.seed = 94021
	var layout: DungeonLayout = GENERATOR.new().generate(config)
	HAZARD_PLANNER.new().plan(layout)
	var parent := Node3D.new()
	add_child(parent)
	var result: DungeonBuildResult = BUILDER.new().build(layout, parent)
	assert_int(result.hazards_root.get_child_count()).is_equal(layout.hazard_anchors.size())
	for hazard in result.hazards_root.get_children():
		assert_bool(result.streamed_visual_nodes.has(hazard)).is_true()
	parent.free()

func test_hazard_real_3d_capture_artifact_is_readable_when_present() -> void:
	if not FileAccess.file_exists(CAPTURE_PATH):
		print("缺少实机陷阱截图，请运行 dungeon_hazard_visual_capture.gd")
		return
	var image := Image.new()
	assert_int(image.load(CAPTURE_PATH)).is_equal(OK)
	assert_int(image.get_width()).is_greater_equal(640)
	assert_int(image.get_height()).is_greater_equal(360)
	assert_int(_count_lit_pixels(image)).is_greater(120)

func _count_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		count += 1
	for child in node.get_children():
		count += _count_meshes(child)
	return count

func _count_lit_pixels(image: Image) -> int:
	var count := 0
	var step_x := maxi(1, image.get_width() / 80)
	var step_y := maxi(1, image.get_height() / 60)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			if color.a > 0.05 and color.r + color.g + color.b > 0.2:
				count += 1
	return count
