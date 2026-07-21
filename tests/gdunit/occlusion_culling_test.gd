extends GdUnitTestSuite

## 遮挡剔除（P0）回归测试。
## 墙体遮挡由 DungeonSceneBuilder 按 streaming chunk 合并，避免每面墙一个节点。

const BUILDER_PATH := "res://scenes/expedition/dungeon_scene_builder.gd"

func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func test_project_enables_occlusion_culling() -> void:
	# 项目开关必须开启，否则 OccluderInstance3D 不生效
	assert_bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)) \
		.override_failure_message("project.godot 必须设置 rendering/occlusion_culling/use_occlusion_culling=true") \
		.is_true()

func test_dungeon_builds_wall_occluders() -> void:
	var source := _read_source(BUILDER_PATH)
	assert_bool(source.contains("func _build_wall_occluders")) \
		.override_failure_message("缺少 _build_wall_occluders 函数") \
		.is_true()
	assert_bool(source.contains("OccluderInstance3D.new()")) \
		.override_failure_message("必须创建 OccluderInstance3D") \
		.is_true()
	assert_bool(source.contains("ArrayOccluder3D.new()")) \
		.override_failure_message("遮挡体应按区块合并为 ArrayOccluder3D") \
		.is_true()
	assert_bool(source.contains("result.terrain_chunks")) \
		.override_failure_message("合并遮挡体必须注册到 terrain chunk 流送") \
		.is_true()

func test_dungeon_occluders_gate_on_project_setting() -> void:
	# _build_wall_occluders 必须在开关关闭时直接返回，避免无谓节点
	var source := _read_source(BUILDER_PATH)
	assert_bool(source.contains("if not ProjectSettings.get_setting(\"rendering/occlusion_culling/use_occlusion_culling\", false):")) \
		.override_failure_message("遮挡体生成必须受项目开关保护") \
		.is_true()

func test_array_occluder_api_usable() -> void:
	var occ := OccluderInstance3D.new()
	var array := ArrayOccluder3D.new()
	array.set_arrays(
		PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP]),
		PackedInt32Array([0, 1, 2])
	)
	occ.occluder = array
	var root := Node3D.new()
	root.add_child(occ)
	assert_object(occ.occluder).is_instanceof(ArrayOccluder3D)
	assert_object(array).is_instanceof(Occluder3D)
	root.free()


func test_generated_dungeon_has_at_most_one_occluder_per_chunk() -> void:
	var cfg := DungeonGenerationConfig.new()
	cfg.seed = 94021
	var layout := DungeonGenerator.new().generate(cfg)
	var parent := Node3D.new()
	add_child(parent)
	var result := DungeonSceneBuilder.new().build(layout, parent)
	var occluders := result.terrain_root.find_children("*", "OccluderInstance3D", true, false)
	assert_int(occluders.size()).is_greater(0)
	assert_int(occluders.size()).is_less_equal(result.terrain_chunks.size())
	for occluder in occluders:
		assert_object((occluder as OccluderInstance3D).occluder).is_instanceof(ArrayOccluder3D)
		var chunk: Vector2i = occluder.get_meta("stream_terrain_chunk", Vector2i(999999, 999999))
		assert_bool(result.terrain_chunks.has(chunk)).is_true()
		assert_bool((result.terrain_chunks[chunk] as Array).has(occluder)).is_true()
	result.dispose()
	parent.queue_free()
