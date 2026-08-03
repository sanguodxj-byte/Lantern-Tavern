extends GdUnitTestSuite

const DECOR_SCENES := [
	"res://scenes/props/dungeon/decor/floor_candelabrum.tscn",
	"res://scenes/props/dungeon/decor/wall_candelabrum.tscn",
	"res://scenes/props/dungeon/decor/iron_bar_grate.tscn",
	"res://scenes/props/dungeon/decor/stalagmite_cluster.tscn",
	"res://scenes/props/dungeon/decor/sarcophagus.tscn",
	"res://scenes/props/dungeon/decor/wall_chain.tscn",
	"res://scenes/props/dungeon/decor/fungus_patch.tscn",
]
const CONFIG_PATH := "res://data/item_placement_config.json"
const MATERIAL_CAPTURE_SCENE := "res://tools/dungeon_decor_material_capture.tscn"


func test_new_dungeon_decor_scenes_are_modeled_scene_objects() -> void:
	for scene_path in DECOR_SCENES:
		var packed := load(scene_path) as PackedScene
		assert_object(packed) \
			.override_failure_message("缺少地牢装饰场景: %s" % scene_path) \
			.is_not_null()
		var inst := packed.instantiate()
		add_child(inst)
		await await_idle_frame()
		if inst.has_method("rebuild"):
			inst.rebuild()
		assert_bool(inst is Node3D).is_true()
		var modeled_count := _count_nodes_of_type(inst, "MeshInstance3D")
		if inst.has_method("collect_box_bounds"):
			modeled_count = inst.collect_box_bounds().size()
			inst.rebuild()
		assert_int(modeled_count) \
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

func test_dungeon_decor_meshes_use_textured_atlas_materials() -> void:
	for scene_path in DECOR_SCENES:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		if inst.has_method("rebuild"):
			inst.rebuild()
		for mesh_instance in _collect_meshes(inst):
			var material := mesh_instance.material_override as ShaderMaterial
			if material == null:
				material = mesh_instance.get_surface_override_material(0) as ShaderMaterial
			assert_object(material) \
				.override_failure_message("%s/%s 不能使用纯色实体材质" % [scene_path, mesh_instance.name]) \
				.is_not_null()
			assert_object(material.get_shader_parameter("atlas")) \
				.override_failure_message("%s/%s 必须绑定像素图集" % [scene_path, mesh_instance.name]) \
				.is_not_null()
			assert_float(material.get_shader_parameter("world_aligned_uv_enabled")) \
				.override_failure_message("%s/%s 必须按世界米制采样，避免细柱纹理拉伸" % [scene_path, mesh_instance.name]) \
				.is_equal(1.0)
		inst.free()

func test_dungeon_decor_material_resources_are_shader_backed() -> void:
	for path in [
		"res://scenes/props/dungeon/decor/dungeon_iron_atlas_mat.tres",
		"res://scenes/props/dungeon/decor/dungeon_wax_atlas_mat.tres",
	]:
		var material := load(path) as ShaderMaterial
		assert_object(material).is_not_null()
		assert_object(material.get_shader_parameter("atlas")).is_not_null()
		assert_float(material.get_shader_parameter("specular")).is_equal_approx(0.0, 0.001)

func test_voxel_prop_material_factory_uses_world_aligned_atlas_sampling() -> void:
	var prop := VoxelProp.new()
	var material := prop._make_prop_mat("wood_mid", 0.9, 0.0)
	assert_object(material.get_shader_parameter("atlas")).is_not_null()
	assert_float(material.get_shader_parameter("world_aligned_uv_enabled")).is_equal(1.0)
	assert_float(material.get_shader_parameter("meters_per_tile")).is_equal_approx(0.5, 0.001)
	prop.free()

func test_decor_material_capture_uses_the_three_production_scenes() -> void:
	assert_object(load(MATERIAL_CAPTURE_SCENE) as PackedScene).is_not_null()
	var source := FileAccess.get_file_as_string("res://tools/dungeon_decor_material_capture.gd")
	for scene_path in DECOR_SCENES:
		assert_str(source).contains(scene_path)
	assert_str(source).contains("make_terrain_mat(\"BARONY_FLOOR\"")

func test_three_view_capture_allowlists_each_changed_decor_asset() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	for asset_id in ["floor_candelabrum", "wall_candelabrum", "iron_bar_grate", "stalagmite_cluster", "sarcophagus", "wall_chain", "fungus_patch"]:
		assert_str(source).contains("\"%s\"" % asset_id)


func test_three_view_capture_uses_source_voxel_boxes_before_merged_mesh_aabb() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(source).contains("collect_box_bounds")
	assert_str(source).contains("source_boxes")


func test_new_dungeon_decor_uses_one_pixel_voxel_boxes() -> void:
	for scene_path in DECOR_SCENES:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		if inst.has_method("collect_box_bounds"):
			# VoxelProp 合并后运行时网格是 ArrayMesh；用源体素盒验证尺寸，
			# 避免把按材质合并的 AABB 误当成单个自由几何体。
			var bounds: Array = inst.collect_box_bounds()
			assert_int(bounds.size()).is_greater_equal(4)
			for source_box in bounds:
				var min_v: Vector3 = source_box["min"]
				var max_v: Vector3 = source_box["max"]
				var size := max_v - min_v
				var center := (min_v + max_v) * 0.5
				assert_bool(_is_voxel_size(size.x)).is_true()
				assert_bool(_is_voxel_size(size.y)).is_true()
				assert_bool(_is_voxel_size(size.z)).is_true()
				assert_bool(_is_half_voxel_position(center.x)).is_true()
				assert_bool(_is_half_voxel_position(center.y)).is_true()
				assert_bool(_is_half_voxel_position(center.z)).is_true()
			if inst.has_method("rebuild"):
				inst.rebuild()
		else:
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
		add_child(inst)
		await await_idle_frame()
		if inst.has_method("rebuild"):
			inst.rebuild()
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
		"res://scenes/props/dungeon/decor/floor_candelabrum.tscn",
		"res://scenes/props/dungeon/decor/wall_candelabrum.tscn",
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
	var inst := (load("res://scenes/props/dungeon/decor/iron_bar_grate.tscn") as PackedScene).instantiate()
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
	for marker in ["Bar", "Stem", "Arm", "Candle", "Flame", "Stalagmite", "Sarcophagus", "Chain", "Fungus", "Cap", "Seal"]:
		if node_name.contains(marker):
			return true
	return false
