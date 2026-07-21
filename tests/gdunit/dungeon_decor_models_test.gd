extends GdUnitTestSuite

const DECOR_SCENES := [
	"res://scenes/props/decor/floor_candelabrum.tscn",
	"res://scenes/props/decor/wall_candelabrum.tscn",
	"res://scenes/props/decor/iron_bar_grate.tscn",
]
const CONFIG_PATH := "res://data/item_placement_config.json"


func test_new_dungeon_decor_scenes_are_modeled_scene_objects() -> void:
	for scene_path in DECOR_SCENES:
		var packed := load(scene_path) as PackedScene
		assert_object(packed) \
			.override_failure_message("缺少地牢装饰场景: %s" % scene_path) \
			.is_not_null()
		var inst := packed.instantiate()
		assert_bool(inst is Node3D).is_true()
		assert_int(_count_nodes_of_type(inst, "MeshInstance3D")) \
			.override_failure_message("%s 必须由多个体素 mesh 组成，而不是空节点" % scene_path) \
			.is_greater_equal(4)
		assert_int(int(inst.get_meta("voxel_unit_px", 0))) \
			.override_failure_message("%s 必须声明 1px 体素单位" % scene_path) \
			.is_equal(1)
		assert_int(int(inst.get_meta("voxel_px_per_meter", 0))) \
			.override_failure_message("%s 必须声明 32px = 1m" % scene_path) \
			.is_equal(32)
		var body := _find_static_body(inst)
		assert_object(body) \
			.override_failure_message("%s 必须带 StaticBody3D 碰撞" % scene_path) \
			.is_not_null()
		assert_bool((body.collision_layer & PhysicsSetup.LAYER_SCENE_OBJECT) != 0).is_true()
		assert_object(body.find_child("CollisionShape3D", true, false)).is_not_null()
		assert_str(String(inst.get_meta("topdown_kind"))) \
			.override_failure_message("%s 必须可被俯视调试图识别为地形装饰" % scene_path) \
			.is_equal("terrain_feature")
		inst.free()


func test_new_dungeon_decor_uses_one_pixel_voxel_boxes() -> void:
	for scene_path in DECOR_SCENES:
		var inst := (load(scene_path) as PackedScene).instantiate()
		for mesh_instance in _collect_meshes(inst):
			var box := mesh_instance.mesh as BoxMesh
			assert_object(box) \
				.override_failure_message("%s/%s 必须使用 BoxMesh 体素块，不能再用圆柱/球体自由几何" % [scene_path, mesh_instance.name]) \
				.is_not_null()
			assert_bool(_is_voxel_size(box.size.x)).is_true()
			assert_bool(_is_voxel_size(box.size.y)).is_true()
			assert_bool(_is_voxel_size(box.size.z)).is_true()
			assert_bool(_is_half_voxel_position(mesh_instance.position.x)).is_true()
			assert_bool(_is_half_voxel_position(mesh_instance.position.y)).is_true()
			assert_bool(_is_half_voxel_position(mesh_instance.position.z)).is_true()
		inst.free()


func test_small_voxel_decor_details_use_odd_widths_for_center_lines() -> void:
	for scene_path in DECOR_SCENES:
		var inst := (load(scene_path) as PackedScene).instantiate()
		for mesh_instance in _collect_meshes(inst):
			var node_name := String(mesh_instance.name)
			if not _is_small_centered_detail(node_name):
				continue
			var box := mesh_instance.mesh as BoxMesh
			var odd_axes := 0
			for count in [_voxel_count(box.size.x), _voxel_count(box.size.y), _voxel_count(box.size.z)]:
				if count % 2 == 1:
					odd_axes += 1
			assert_int(odd_axes) \
				.override_failure_message("%s/%s 小型细节应使用 1px/3px/5px 等奇数 voxel 宽度，避免中心线偏半格" % [scene_path, node_name]) \
				.is_greater_equal(2)
		inst.free()


func test_candelabrum_decor_has_warm_light_and_dynamic_flame_particles() -> void:
	for scene_path in [
		"res://scenes/props/decor/floor_candelabrum.tscn",
		"res://scenes/props/decor/wall_candelabrum.tscn",
	]:
		var inst := (load(scene_path) as PackedScene).instantiate()
		assert_int(_count_nodes_of_type(inst, "OmniLight3D")) \
			.override_failure_message("%s 必须自带暖色烛光" % scene_path) \
			.is_greater_equal(1)
		assert_int(_count_nodes_of_type(inst, "GPUParticles3D")) \
			.override_failure_message("%s 必须使用动态火焰粒子" % scene_path) \
			.is_greater_equal(1)
		for mesh_instance in _collect_meshes(inst):
			assert_bool(String(mesh_instance.name).begins_with("Flame")) \
				.override_failure_message("%s 不应再包含静态火焰 mesh: %s" % [scene_path, mesh_instance.name]) \
				.is_false()
		inst.free()


func test_iron_bar_grate_reads_as_barred_iron_not_solid_wall() -> void:
	var inst := (load("res://scenes/props/decor/iron_bar_grate.tscn") as PackedScene).instantiate()
	var vertical_bars := 0
	var crossbars := 0
	for node in _collect_meshes(inst):
		if String(node.name).begins_with("Bar"):
			vertical_bars += 1
		elif String(node.name).begins_with("Crossbar"):
			crossbars += 1
	assert_int(vertical_bars).is_greater_equal(5)
	assert_int(crossbars).is_greater_equal(2)
	inst.free()


func test_new_dungeon_decor_is_in_spawn_pools() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_bool(parsed is Array).is_true()
	var decor_paths := []
	for entry in parsed:
		if String(entry.get("tag", "")) != "decor":
			continue
		for item in entry.get("item_scene_paths", []):
			decor_paths.append(String(item.get("path", "")))

	for scene_path in DECOR_SCENES:
		assert_array(decor_paths) \
			.override_failure_message("%s 必须进入数据驱动装饰生成池" % scene_path) \
			.contains(scene_path)

	# fallback 装饰池已迁入 DungeonRuntimeConfig（builder 消费）
	var runtime_cfg_src := (load("res://scenes/expedition/dungeon_runtime_config.gd") as GDScript).source_code
	var builder_src := (load("res://scenes/expedition/dungeon_scene_builder.gd") as GDScript).source_code
	for scene_path in DECOR_SCENES:
		assert_bool(runtime_cfg_src.contains(scene_path) or builder_src.contains(scene_path)) \
			.override_failure_message("%s 必须进入 RuntimeConfig/Builder 装饰池" % scene_path) \
			.is_true()


func _find_static_body(root: Node) -> StaticBody3D:
	if root is StaticBody3D:
		return root as StaticBody3D
	for child in root.get_children():
		var found := _find_static_body(child)
		if found != null:
			return found
	return null


func _count_nodes_of_type(root: Node, type_name: String) -> int:
	var count := 1 if root.is_class(type_name) else 0
	for child in root.get_children():
		count += _count_nodes_of_type(child, type_name)
	return count


func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		meshes.append_array(_collect_meshes(child))
	return meshes


func _is_voxel_size(value: float) -> bool:
	return is_equal_approx(value * 32.0, roundf(value * 32.0))


func _is_half_voxel_position(value: float) -> bool:
	return is_equal_approx(value * 64.0, roundf(value * 64.0))


func _voxel_count(value: float) -> int:
	return int(roundf(value * 32.0))


func _is_small_centered_detail(node_name: String) -> bool:
	for marker in ["Bar", "Stem", "Arm", "Candle", "Flame"]:
		if node_name.contains(marker):
			return true
	return false
