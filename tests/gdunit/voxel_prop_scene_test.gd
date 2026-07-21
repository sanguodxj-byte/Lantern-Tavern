extends GdUnitTestSuite

const VOXEL_PROP_SCRIPT := "res://scenes/props/voxel_prop.gd"
const VOXEL_PROP_ATLAS := "res://assets/textures/props/voxel/voxel_prop_material_atlas_32px.png"
const VOXEL_PROP_META := "res://assets/textures/props/voxel/voxel_prop_material_atlas_32px.json"
const VOXEL_WORKFLOW_DOC := "res://docs/17-体素建模工作流.md"
const VOXEL_THREE_VIEW_TOOL := "res://tools/voxel_prop_three_view_capture.gd"
const VOXEL_MATERIAL_RENDER_TOOL := "res://tools/voxel_prop_material_render_preview.gd"
const VOXEL_PROP_SCENES := [
	"res://scenes/props/decor/table.tscn",
	"res://scenes/props/decor/chair.tscn",
	"res://scenes/props/decor/bench.tscn",
	"res://scenes/props/decor/bucket.tscn",
	"res://scenes/props/decor/candles.tscn",
	"res://scenes/props/decor/lit_candles.tscn",
	"res://scenes/props/decor/tankard.tscn",
	"res://scenes/props/decor/goblet.tscn",
	"res://scenes/props/decor/bottle_set.tscn",
	"res://scenes/props/decor/wall_notice.tscn",
	"res://scenes/props/decor/chandelier.tscn",
	"res://scenes/props/decor/wall_lantern.tscn",
	"res://scenes/props/decor/grate.tscn",
	"res://scenes/props/decor/jail.tscn",
	"res://scenes/props/decor/fireplace.tscn",
	"res://scenes/props/decor/banner.tscn",
	"res://scenes/props/decor/bones.tscn",
	"res://scenes/props/decor/ruble.tscn",
	"res://scenes/props/decor/plank.tscn",
	"res://scenes/props/crates/small_crate.tscn",
	"res://scenes/props/crates/large_crate.tscn",
	"res://scenes/props/structures/pillar.tscn",
	"res://scenes/props/decor/weapon_rack.tscn",
]
const VOXEL_VISUAL_SCENES := [
	"res://scenes/props/barrel/barrel.tscn",
	"res://scenes/props/chest/chest.tscn",
	"res://scenes/props/chest/boss_chest.tscn",
	"res://scenes/props/torch/torch.tscn",
]


func test_rebuilt_prop_scenes_use_voxel_prop_script_not_glb_instances() -> void:
	var script := load(VOXEL_PROP_SCRIPT)
	for scene_path in VOXEL_PROP_SCENES + VOXEL_VISUAL_SCENES:
		var source := FileAccess.get_file_as_string(scene_path)
		assert_bool(source.contains(".glb") or source.contains(".obj")) \
			.override_failure_message("%s 不能再实例化旧 GLB/OBJ 模型" % scene_path) \
			.is_false()
		var has_forbidden_round_mesh: bool = source.contains("CylinderMesh") or source.contains("SphereMesh") or source.contains("CapsuleShape3D") or source.contains("CylinderShape3D")
		var allows_dynamic_flame: bool = scene_path in [
			"res://scenes/props/torch/torch.tscn",
			"res://scenes/props/decor/lit_candles.tscn",
			"res://scenes/props/decor/fireplace.tscn",
			"res://scenes/props/decor/chandelier.tscn",
			"res://scenes/props/decor/wall_lantern.tscn",
		]
		var has_forbidden_quad: bool = source.contains("QuadMesh") and not allows_dynamic_flame
		assert_bool(has_forbidden_round_mesh or has_forbidden_quad) \
			.override_failure_message("%s 不能再使用圆柱/球/胶囊等非体素形状" % scene_path) \
			.is_false()

		var inst := (load(scene_path) as PackedScene).instantiate()
		if scene_path in VOXEL_PROP_SCENES:
			assert_object(inst.get_script()).is_equal(script)
		else:
			assert_bool(_has_voxel_prop_node(inst, script)) \
				.override_failure_message("%s 必须包含体素视觉子节点，同时保留原交互根节点" % scene_path) \
				.is_true()
		inst.free()


func test_voxel_modeling_workflow_requires_scale_attachment_and_three_views() -> void:
	assert_bool(FileAccess.file_exists(VOXEL_WORKFLOW_DOC)) \
		.override_failure_message("缺少体素建模工作流文档") \
		.is_true()
	var doc := FileAccess.get_file_as_string(VOXEL_WORKFLOW_DOC)
	assert_str(doc).contains("1m = 32px")
	assert_str(doc).contains("附着")
	assert_str(doc).contains("三视图")
	assert_str(doc).contains("tools/voxel_prop_three_view_capture.gd")
	assert_str(doc).contains("禁止正体积重叠")
	assert_str(doc).contains("character_voxel_overlap_test")
	assert_str(doc).contains("voxel_overlap_guard")
	assert_str(doc).contains("真·重做门槛")

	var agents := FileAccess.get_file_as_string("res://AGENTS.md")
	assert_str(agents).contains("Voxel Modeling Workflow")
	assert_str(agents).contains("front/side/top screenshots")


func test_voxel_three_view_capture_tool_defines_required_views() -> void:
	assert_bool(FileAccess.file_exists(VOXEL_THREE_VIEW_TOOL)) \
		.override_failure_message("缺少体素三视图截图工具") \
		.is_true()
	var source := FileAccess.get_file_as_string(VOXEL_THREE_VIEW_TOOL)
	assert_str(source).contains('"front"')
	assert_str(source).contains('"side"')
	assert_str(source).contains('"top"')
	assert_str(source).contains("reports/props_preview")
	assert_str(source).contains("boss_chest")
	assert_str(source) \
		.override_failure_message("三视图只允许显示静态体素本体；火焰必须由运行时粒子负责，不能画成静态预览块") \
		.not_contains("FlamePreview")
	assert_str(source).not_contains("_effect_boxes")


func test_voxel_material_render_preview_tool_covers_new_decor_materials() -> void:
	assert_bool(FileAccess.file_exists(VOXEL_MATERIAL_RENDER_TOOL)) \
		.override_failure_message("缺少体素材质真实渲染预览工具") \
		.is_true()
	var source := FileAccess.get_file_as_string(VOXEL_MATERIAL_RENDER_TOOL)
	assert_str(source).contains("tavern_decor_material_contact_sheet.png")
	assert_str(source).contains("SubViewport")
	assert_str(source).contains("DirectionalLight3D")
	for scene_path in [
		"res://scenes/props/decor/tankard.tscn",
		"res://scenes/props/decor/goblet.tscn",
		"res://scenes/props/decor/bottle_set.tscn",
		"res://scenes/props/decor/wall_notice.tscn",
		"res://scenes/props/decor/chandelier.tscn",
		"res://scenes/props/decor/wall_lantern.tscn",
	]:
		assert_str(source) \
			.override_failure_message("材质预览工具必须覆盖新增酒馆陈设: %s" % scene_path) \
			.contains(scene_path)


func test_voxel_prop_material_atlas_defines_pixel_style_tiles() -> void:
	assert_bool(FileAccess.file_exists(VOXEL_PROP_ATLAS)).is_true()
	assert_bool(FileAccess.file_exists(VOXEL_PROP_META)).is_true()
	var image := Image.load_from_file(VOXEL_PROP_ATLAS)
	assert_int(image.get_width()).is_equal(256)
	assert_int(image.get_height()).is_equal(128)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VOXEL_PROP_META))
	assert_int(int(meta["tile_px"][0])).is_equal(32)
	assert_int(int(meta["voxel_px_per_meter"])).is_equal(32)
	var tiles: Dictionary = meta["tiles"]
	for tile_name in [
		"wood_mid",
		"wood_dark",
		"black_iron",
		"cut_stone",
		"wax",
		"flame",
		"bone",
		"red_cloth",
		"tankard_aged_oak",
		"tankard_dark_iron",
		"ale_foam",
		"goblet_worn_silver",
		"goblet_wine_glow",
		"bottle_green_glass",
		"bottle_amber_glass",
		"bottle_cork",
		"notice_aged_parchment",
		"notice_frame_wood",
		"ink_dark",
		"chandelier_oiled_wood",
		"warm_bronze",
		"lantern_smoked_glass",
		"soot_dark",
		"wax_warm_drip",
	]:
		assert_bool(tiles.has(tile_name)) \
			.override_failure_message("体素道具材质图集缺少 tile: %s" % tile_name) \
			.is_true()
		var rect: Array = tiles[tile_name]["pixel_rect"]
		assert_int(_count_unique_sampled_colors(image, Rect2i(rect[0], rect[1], rect[2], rect[3]))) \
			.override_failure_message("材质 tile %s 不能是纯色块，需要有做旧/阴影/高光像素变化" % tile_name) \
			.is_greater_equal(8)


func test_voxel_prop_scenes_generate_one_pixel_aligned_box_meshes() -> void:
	for scene_path in VOXEL_PROP_SCENES + VOXEL_VISUAL_SCENES:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		var meshes := _collect_meshes(inst)
		assert_int(meshes.size()) \
			.override_failure_message("%s 必须生成多个体素盒 mesh" % scene_path) \
			.is_greater_equal(3)
		for mesh_instance in meshes:
			var box := mesh_instance.mesh as BoxMesh
			assert_object(box) \
				.override_failure_message("%s/%s 必须是 BoxMesh" % [scene_path, mesh_instance.name]) \
				.is_not_null()
			for size in [box.size.x, box.size.y, box.size.z]:
				assert_float(size) \
					.override_failure_message("%s/%s 体素盒尺寸不能为 0: %s" % [scene_path, mesh_instance.name, str(box.size)]) \
					.is_greater(0.0)
				assert_bool(_is_voxel_aligned(size)) \
					.override_failure_message("%s/%s 尺寸未对齐 1px=1/32m: %s" % [scene_path, mesh_instance.name, str(box.size)]) \
					.is_true()
			var material := mesh_instance.material_override as ShaderMaterial
			assert_object(material) \
				.override_failure_message("%s/%s 不能使用平色材质，必须贴像素风材质图" % [scene_path, mesh_instance.name]) \
				.is_not_null()
			assert_str((material.get_shader_parameter("atlas") as Texture2D).resource_path) \
				.is_equal(VOXEL_PROP_ATLAS)
		inst.free()


func test_voxel_props_keep_odd_width_centerline_details() -> void:
	for scene_path in VOXEL_PROP_SCENES + VOXEL_VISUAL_SCENES:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		var found_odd_detail := false
		for mesh_instance in _collect_meshes(inst):
			var name := String(mesh_instance.name)
			if not _is_centerline_detail(name):
				continue
			var box := mesh_instance.mesh as BoxMesh
			for size in [box.size.x, box.size.y, box.size.z]:
				if int(roundf(size * 32.0)) % 2 == 1:
					found_odd_detail = true
					break
		assert_bool(found_odd_detail) \
			.override_failure_message("%s 小型体素细节应至少有一处使用 1px/3px/5px 奇数宽度" % scene_path) \
			.is_true()
		inst.free()


func test_voxel_prop_scale_contracts_use_32_px_per_meter() -> void:
	var table := (load("res://scenes/props/decor/table.tscn") as PackedScene).instantiate()
	add_child(table)
	await await_idle_frame()
	var table_bounds := _combined_mesh_aabb(_collect_meshes(table))
	assert_float(table_bounds.size.x) \
		.override_failure_message("桌子长度必须按 1m=32px 建模，目标约 2m") \
		.is_equal_approx(2.0, 0.001)
	assert_float(table_bounds.size.z) \
		.override_failure_message("桌子宽度必须按 1m=32px 建模，目标约 1.06m") \
		.is_equal_approx(34.0 / 32.0, 0.001)
	assert_float(table_bounds.size.y) \
		.override_failure_message("桌子高度必须接近真实桌高，不能和火把同量级") \
		.is_equal_approx(26.0 / 32.0, 0.001)

	var torch := (load("res://scenes/props/torch/torch.tscn") as PackedScene).instantiate()
	add_child(torch)
	await await_idle_frame()
	var torch_bounds := _combined_mesh_aabb(_collect_meshes(torch))
	assert_float(torch_bounds.size.y) \
		.override_failure_message("火把静态本体必须是小型壁挂件，不能接近桌子高度") \
		.is_less_equal(14.0 / 32.0)
	assert_float(torch_bounds.size.x) \
		.override_failure_message("火把宽度必须明显小于桌子") \
		.is_less_equal(0.25)
	assert_float(torch_bounds.size.z) \
		.override_failure_message("火把伸出墙面深度必须小于桌宽") \
		.is_less_equal(0.55)
	assert_float(table_bounds.size.x / maxf(torch_bounds.size.x, 0.001)) \
		.override_failure_message("桌子应显著大于火把，不应视觉同尺寸") \
		.is_greater_equal(8.0)
	table.free()
	torch.free()


func test_voxel_box_meshes_form_one_attached_component() -> void:
	for scene_path in VOXEL_PROP_SCENES + VOXEL_VISUAL_SCENES:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		var boxes := _voxel_boxes(_collect_meshes(inst))
		assert_int(boxes.size()) \
			.override_failure_message("%s 没有可验证的体素盒" % scene_path) \
			.is_greater_equal(1)
		assert_int(_count_attached_components(boxes)) \
			.override_failure_message("%s 存在分离体素块；所有静态体素必须通过面接触附着成一个整体（正体积重叠不算附着）" % scene_path) \
			.is_equal(1)
		inst.free()


func test_lit_candles_keep_warm_light_after_voxel_rebuild() -> void:
	var inst := (load("res://scenes/props/decor/lit_candles.tscn") as PackedScene).instantiate()
	add_child(inst)
	await await_idle_frame()
	assert_int(_count_nodes_of_type(inst, "OmniLight3D")).is_greater_equal(1)
	assert_int(_count_nodes_of_type(inst, "GPUParticles3D")).is_greater_equal(3)
	for mesh_instance in _collect_meshes(inst):
		assert_bool(String(mesh_instance.name).begins_with("Flame")) \
			.override_failure_message("蜡烛静态模型不应包含火焰 mesh: %s" % mesh_instance.name) \
			.is_false()
	inst.free()


func test_voxel_prop_rebuild_clears_generated_children_immediately() -> void:
	var inst := (load("res://scenes/props/decor/chair.tscn") as PackedScene).instantiate()
	add_child(inst)
	await await_idle_frame()

	inst.rebuild()
	inst.rebuild()

	assert_int(_collect_meshes(inst).size()) \
		.override_failure_message("同一帧连续 rebuild 不应保留排队删除的旧体素 Mesh") \
		.is_equal(8)
	inst.free()


func test_tavern_decor_props_match_reference_contracts() -> void:
	for scene_path in [
		"res://scenes/props/decor/tankard.tscn",
		"res://scenes/props/decor/goblet.tscn",
		"res://scenes/props/decor/bottle_set.tscn",
		"res://scenes/props/decor/wall_notice.tscn",
	]:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		var bounds := _combined_mesh_aabb(_collect_meshes(inst))
		assert_float(bounds.size.y) \
			.override_failure_message("%s 必须保持为酒馆小型/墙面陈设，不应接近角色尺寸" % scene_path) \
			.is_less_equal(1.0)
		assert_float(bounds.size.x) \
			.override_failure_message("%s 宽度不应超过 1.5m" % scene_path) \
			.is_less_equal(1.5)
		assert_bool(_has_flame_mesh(inst)) \
			.override_failure_message("%s 不应包含静态火焰 mesh" % scene_path) \
			.is_false()
		inst.free()


func test_chandelier_and_wall_lantern_use_dynamic_fire_only() -> void:
	for scene_path in [
		"res://scenes/props/decor/chandelier.tscn",
		"res://scenes/props/decor/wall_lantern.tscn",
	]:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		assert_int(_count_nodes_of_type(inst, "GPUParticles3D")) \
			.override_failure_message("%s 必须用粒子火焰，不允许静态火焰模型" % scene_path) \
			.is_greater_equal(1)
		assert_int(_count_nodes_of_type(inst, "OmniLight3D")) \
			.override_failure_message("%s 必须带暖色动态光源" % scene_path) \
			.is_greater_equal(1)
		assert_bool(_has_flame_mesh(inst)) \
			.override_failure_message("%s 静态模型不应包含火焰 mesh" % scene_path) \
			.is_false()
		inst.free()


func test_new_tavern_props_use_object_specific_material_tiles() -> void:
	var expected := {
		"res://scenes/props/decor/tankard.tscn": [Vector2(0, 1), Vector2(1, 1), Vector2(2, 1)],
		"res://scenes/props/decor/goblet.tscn": [Vector2(3, 1), Vector2(4, 1)],
		"res://scenes/props/decor/bottle_set.tscn": [Vector2(5, 1), Vector2(6, 1), Vector2(7, 1), Vector2(4, 1)],
		"res://scenes/props/decor/wall_notice.tscn": [Vector2(0, 2), Vector2(1, 2), Vector2(2, 2)],
		"res://scenes/props/decor/chandelier.tscn": [Vector2(3, 2), Vector2(4, 2), Vector2(7, 2)],
		"res://scenes/props/decor/wall_lantern.tscn": [Vector2(4, 2), Vector2(5, 2), Vector2(6, 2)],
	}
	for scene_path in expected.keys():
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		var used_tiles := _collect_material_tile_coords(inst)
		for coord in expected[scene_path]:
			assert_bool(_has_tile_coord(used_tiles, coord)) \
				.override_failure_message("%s 未使用专属材质 tile: %s" % [scene_path, str(coord)]) \
				.is_true()
		inst.free()


func test_fireplace_uses_dynamic_flame_shader_instead_of_static_flame_meshes() -> void:
	var inst := (load("res://scenes/props/decor/fireplace.tscn") as PackedScene).instantiate()
	add_child(inst)
	await await_idle_frame()
	var particles := inst.get_node("FlameParticles") as GPUParticles3D
	assert_object(particles) \
		.override_failure_message("壁炉必须使用动态火焰粒子") \
		.is_not_null()
	assert_bool(particles.emitting).is_true()
	assert_int(particles.amount).is_greater_equal(30)
	var mat := particles.draw_pass_1.material as ShaderMaterial
	assert_object(mat) \
		.override_failure_message("火焰粒子必须使用 fire_flame_particle ShaderMaterial") \
		.is_not_null()
	assert_str(mat.shader.resource_path) \
		.override_failure_message("火焰应为程序化 fire_flame_particle.gdshader") \
		.is_equal("res://shaders/fire_flame_particle.gdshader")
	inst.free()


func test_pickable_barrel_keeps_furniture_data_and_collision_after_voxel_rebuild() -> void:
	var inst := (load("res://scenes/props/barrel/barrel.tscn") as PackedScene).instantiate() as PickableItem
	add_child(inst)
	await await_idle_frame()
	assert_object(inst.furniture_data).is_not_null()
	assert_object(inst.mesh_node).is_not_null()
	assert_object(inst.get_node("CollisionShape").shape).is_not_null()
	inst.free()


func test_barrel_uses_stepped_round_voxel_silhouette() -> void:
	var inst := (load("res://scenes/props/barrel/barrel.tscn") as PackedScene).instantiate()
	add_child(inst)
	await await_idle_frame()
	var slice_depths: Array[int] = []
	for mesh_instance in _collect_meshes(inst):
		if not String(mesh_instance.name).begins_with("MiddleWoodSlice_"):
			continue
		var box := mesh_instance.mesh as BoxMesh
		slice_depths.append(roundi(box.size.z * 32.0))
	assert_int(slice_depths.size()) \
		.override_failure_message("酒桶必须由多段体素切片组成，顶部投影才像圆桶") \
		.is_greater_equal(5)
	slice_depths.sort()
	assert_int(slice_depths[-1] - slice_depths[0]) \
		.override_failure_message("酒桶切片深度必须有明显阶梯，不能还是方箱轮廓") \
		.is_greater_equal(10)
	inst.free()


func test_barrel_voxel_boxes_do_not_overlap_positive_volume() -> void:
	var inst := (load("res://scenes/props/barrel/barrel.tscn") as PackedScene).instantiate()
	add_child(inst)
	await await_idle_frame()
	var boxes := _voxel_boxes(_collect_meshes(inst))
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			assert_bool(_boxes_overlap_with_positive_volume(boxes[i], boxes[j])) \
				.override_failure_message("酒桶体素盒不能正体积重叠，避免重叠处闪烁: %s vs %s" % [boxes[i]["name"], boxes[j]["name"]]) \
				.is_false()
	inst.free()


func test_reported_voxel_props_do_not_overlap_positive_volume() -> void:
	for scene_path in [
		"res://scenes/props/decor/chair.tscn",
		"res://scenes/props/decor/chandelier.tscn",
		"res://scenes/props/torch/torch.tscn",
	]:
		var inst := (load(scene_path) as PackedScene).instantiate()
		add_child(inst)
		await await_idle_frame()
		var boxes := _voxel_boxes(_collect_meshes(inst))
		for i in range(boxes.size()):
			for j in range(i + 1, boxes.size()):
				assert_bool(_boxes_overlap_with_positive_volume(boxes[i], boxes[j])) \
					.override_failure_message("%s 体素盒不能正体积重叠，避免重叠处闪烁: %s vs %s" % [scene_path, boxes[i]["name"], boxes[j]["name"]]) \
					.is_false()
		inst.free()


func test_boss_chest_is_large_voxel_chest_with_triple_loot_multiplier() -> void:
	var regular := (load("res://scenes/props/chest/chest.tscn") as PackedScene).instantiate()
	var boss := (load("res://scenes/props/chest/boss_chest.tscn") as PackedScene).instantiate() as Chest
	add_child(regular)
	add_child(boss)
	await await_idle_frame()
	assert_int(boss.loot_multiplier).is_equal(3)
	assert_bool(_has_voxel_prop_kind(boss, "boss_chest")) \
		.override_failure_message("boss 奖励箱必须使用 boss_chest 体素视觉") \
		.is_true()
	var regular_bounds := _combined_mesh_aabb(_collect_meshes(regular))
	var boss_bounds := _combined_mesh_aabb(_collect_meshes(boss))
	assert_float(boss_bounds.size.x).is_greater(regular_bounds.size.x * 1.4)
	assert_float(boss_bounds.size.y).is_greater(regular_bounds.size.y * 1.2)
	assert_float(boss_bounds.size.z).is_greater(regular_bounds.size.z * 1.25)
	assert_bool(_has_mesh_named_with(boss, "BossIronCorner")) \
		.override_failure_message("boss 奖励箱需要普通箱没有的重型黑铁角柱") \
		.is_true()
	assert_bool(_has_mesh_named_with(boss, "BossSideHandle")) \
		.override_failure_message("boss 奖励箱需要普通箱没有的侧把手轮廓") \
		.is_true()
	assert_bool(_has_mesh_named_with(boss, "BossRewardSeal")) \
		.override_failure_message("boss 奖励箱需要普通箱没有的正面封印/奖励标记") \
		.is_true()
	regular.free()
	boss.free()


func test_thrown_barrel_uses_voxel_visual_when_furniture_glb_is_unavailable() -> void:
	var thrown := (load("res://scenes/equipment/thrown_item.tscn") as PackedScene).instantiate() as ThrownItem
	var furniture := (load("res://data/furniture/barrel.tres") as FurnitureData).duplicate()
	furniture.glb_mesh = null
	thrown.furniture_data = furniture
	add_child(thrown)
	await await_idle_frame()
	assert_bool(_has_voxel_prop_kind(thrown, "barrel")) \
		.override_failure_message("投掷酒桶在无 GLB 时应生成同款 voxel 酒桶视觉") \
		.is_true()
	assert_object(thrown.get_node("CollisionShape").shape) \
		.override_failure_message("投掷 voxel 酒桶必须从视觉整体 AABB 生成碰撞") \
		.is_not_null()
	assert_float(thrown.linear_velocity.length()) \
		.override_failure_message("投掷 voxel 酒桶应保留 FurnitureData 的飞行速度") \
		.is_greater(0.0)

func test_barrel_furniture_data_does_not_reference_legacy_glb_assets() -> void:
	var furniture := load("res://data/furniture/barrel.tres") as FurnitureData
	assert_object(furniture.glb_mesh).is_null()
	assert_object(furniture.glb_fragments_mesh).is_null()


func test_destructible_item_generates_voxel_fragments_without_fragment_glb() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/props/destructible_item.gd")
	assert_bool(source.contains("glb_fragments_mesh") or source.contains(".glb")) \
		.override_failure_message("破碎物不能再依赖碎片 GLB，应生成体素碎块") \
		.is_false()
	var inst := (load("res://scenes/props/destructible_item.tscn") as PackedScene).instantiate() as DestructibleItem
	add_child(inst)
	await await_idle_frame()
	var fragments := inst.get_node("VoxelFragments")
	assert_object(fragments).is_not_null()
	assert_int(_count_nodes_of_type(fragments, "RigidBody3D")).is_greater_equal(6)
	for fragment in fragments.get_children():
		var body := fragment as RigidBody3D
		assert_object(body).is_not_null()
		var mesh_instance := body.get_node("VoxelMesh") as MeshInstance3D
		assert_object(mesh_instance).is_not_null()
		var box := mesh_instance.mesh as BoxMesh
		assert_object(box).is_not_null()
		var material := mesh_instance.material_override as ShaderMaterial
		assert_object(material).is_not_null()
		assert_str((material.get_shader_parameter("atlas") as Texture2D).resource_path).is_equal(VOXEL_PROP_ATLAS)
		for size in [box.size.x, box.size.y, box.size.z]:
			assert_bool(_is_voxel_aligned(size)).is_true()
	inst.free()


func test_destructible_item_explode_builds_and_wakes_voxel_fragments_immediately() -> void:
	var inst := (load("res://scenes/props/destructible_item.tscn") as PackedScene).instantiate() as DestructibleItem
	inst.explode()
	var fragments := inst.get_node("VoxelFragments")
	assert_object(fragments) \
		.override_failure_message("explode() 即使早于 _ready() 也必须先构建体素碎片") \
		.is_not_null()
	var moving_fragments := 0
	for fragment in fragments.get_children():
		var body := fragment as RigidBody3D
		if body == null:
			continue
		if body.linear_velocity.length() > 0.01 or body.angular_velocity.length() > 0.01 or not body.sleeping:
			moving_fragments += 1
	assert_int(moving_fragments) \
		.override_failure_message("explode() 必须唤醒并推动碎片，而不是只生成静态盒子") \
		.is_greater_equal(3)
	inst.free()


func test_torch_restores_dynamic_flame_shader_on_voxel_model() -> void:
	var inst := (load("res://scenes/props/torch/torch.tscn") as PackedScene).instantiate()
	add_child(inst)
	await await_idle_frame()
	var particles := inst.get_node("FlameParticles") as GPUParticles3D
	assert_object(particles) \
		.override_failure_message("火把必须恢复动态火焰粒子") \
		.is_not_null()
	var mat := particles.draw_pass_1.material as ShaderMaterial
	assert_object(mat) \
		.override_failure_message("火焰粒子必须使用 fire_flame_particle ShaderMaterial") \
		.is_not_null()
	assert_str(mat.shader.resource_path) \
		.override_failure_message("火焰应为程序化 fire_flame_particle.gdshader") \
		.is_equal("res://shaders/fire_flame_particle.gdshader")
	var bounds := _combined_mesh_aabb(_collect_meshes(inst))
	assert_float(particles.position.y) \
		.override_failure_message("动态火焰必须位于火把杯口上方") \
		.is_greater(bounds.end.y)
	assert_float(particles.position.z) \
		.override_failure_message("动态火焰必须与火把杯口深度对齐") \
		.is_equal_approx(-8.0 / 32.0, 0.001)
	inst.free()


func test_torch_voxel_model_is_compact_and_has_no_static_flame_meshes() -> void:
	var inst := (load("res://scenes/props/torch/torch.tscn") as PackedScene).instantiate()
	add_child(inst)
	await await_idle_frame()
	var meshes := _collect_meshes(inst)
	assert_int(meshes.size()).is_greater_equal(6)
	var bounds := _combined_mesh_aabb(meshes)
	assert_float(bounds.size.y) \
		.override_failure_message("火把本体过高；静态模型应只是小型墙托架，火焰交给动态粒子") \
		.is_less_equal(1.05)
	assert_float(bounds.size.x) \
		.override_failure_message("火把本体过宽") \
		.is_less_equal(0.35)
	assert_float(bounds.size.z) \
		.override_failure_message("火把本体伸出墙面过深") \
		.is_less_equal(0.55)
	for mesh_instance in meshes:
		assert_bool(String(mesh_instance.name).begins_with("Flame")) \
			.override_failure_message("火把静态模型不应包含火焰 mesh: %s" % mesh_instance.name) \
			.is_false()
	inst.free()


func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root as MeshInstance3D)
	for child in root.get_children():
		result.append_array(_collect_meshes(child))
	return result


func _combined_mesh_aabb(meshes: Array[MeshInstance3D]) -> AABB:
	var combined := AABB()
	var initialized := false
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var aabb := mesh_instance.get_aabb()
		aabb.position += mesh_instance.position
		if initialized:
			combined = combined.merge(aabb)
		else:
			combined = aabb
			initialized = true
	return combined if initialized else AABB()


func _voxel_boxes(meshes: Array[MeshInstance3D]) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var aabb := mesh_instance.get_aabb()
		var min_v := (mesh_instance.global_position + aabb.position) * 64.0
		var max_v := (mesh_instance.global_position + aabb.position + aabb.size) * 64.0
		boxes.append({
			"name": String(mesh_instance.name),
			"min": Vector3i(roundi(min_v.x), roundi(min_v.y), roundi(min_v.z)),
			"max": Vector3i(roundi(max_v.x), roundi(max_v.y), roundi(max_v.z)),
		})
	return boxes


func _count_attached_components(boxes: Array[Dictionary]) -> int:
	var visited: Array[bool] = []
	visited.resize(boxes.size())
	var components := 0
	for i in range(boxes.size()):
		if visited[i]:
			continue
		components += 1
		var queue: Array[int] = [i]
		visited[i] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			for j in range(boxes.size()):
				if visited[j]:
					continue
				if _boxes_are_attached(boxes[current], boxes[j]):
					visited[j] = true
					queue.append(j)
	return components


func _boxes_are_attached(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3i = a["min"]
	var amax: Vector3i = a["max"]
	var bmin: Vector3i = b["min"]
	var bmax: Vector3i = b["max"]
	var overlaps := [
		mini(amax.x, bmax.x) - maxi(amin.x, bmin.x),
		mini(amax.y, bmax.y) - maxi(amin.y, bmin.y),
		mini(amax.z, bmax.z) - maxi(amin.z, bmin.z),
	]
	var positive_axes := 0
	var touching_axes := 0
	for overlap in overlaps:
		if overlap > 0:
			positive_axes += 1
		elif overlap == 0:
			touching_axes += 1
		else:
			return false
	# docs/17: attachment is face-contact only; positive volume overlap does not attach.
	return positive_axes == 2 and touching_axes == 1


func _boxes_overlap_with_positive_volume(a: Dictionary, b: Dictionary) -> bool:
	var amin: Vector3i = a["min"]
	var amax: Vector3i = a["max"]
	var bmin: Vector3i = b["min"]
	var bmax: Vector3i = b["max"]
	return mini(amax.x, bmax.x) - maxi(amin.x, bmin.x) > 0 \
		and mini(amax.y, bmax.y) - maxi(amin.y, bmin.y) > 0 \
		and mini(amax.z, bmax.z) - maxi(amin.z, bmin.z) > 0


func _count_nodes_of_type(root: Node, type_name: String) -> int:
	var count := 1 if root.is_class(type_name) else 0
	for child in root.get_children():
		count += _count_nodes_of_type(child, type_name)
	return count


func _has_voxel_prop_node(root: Node, script: Script) -> bool:
	if root.get_script() == script:
		return true
	for child in root.get_children():
		if _has_voxel_prop_node(child, script):
			return true
	return false


func _has_voxel_prop_kind(root: Node, prop_kind: String) -> bool:
	if root is VoxelProp and (root as VoxelProp).prop_kind == prop_kind:
		return true
	for child in root.get_children():
		if _has_voxel_prop_kind(child, prop_kind):
			return true
	return false


func _has_mesh_named_with(root: Node, marker: String) -> bool:
	if root is MeshInstance3D and String(root.name).contains(marker):
		return true
	for child in root.get_children():
		if _has_mesh_named_with(child, marker):
			return true
	return false


func _has_flame_mesh(root: Node) -> bool:
	for mesh_instance in _collect_meshes(root):
		if String(mesh_instance.name).begins_with("Flame"):
			return true
	return false


func _collect_material_tile_coords(root: Node) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for mesh_instance in _collect_meshes(root):
		var material := mesh_instance.material_override as ShaderMaterial
		if material == null:
			continue
		result.append(material.get_shader_parameter("tile_col_row") as Vector2)
	return result


func _has_tile_coord(coords: Array[Vector2], expected: Vector2) -> bool:
	for coord in coords:
		if coord.is_equal_approx(expected):
			return true
	return false


func _count_unique_sampled_colors(image: Image, rect: Rect2i) -> int:
	var colors := {}
	for y in range(rect.position.y, rect.position.y + rect.size.y, 4):
		for x in range(rect.position.x, rect.position.x + rect.size.x, 4):
			var color := image.get_pixel(x, y)
			var key := "%d,%d,%d" % [
				roundi(color.r * 255.0),
				roundi(color.g * 255.0),
				roundi(color.b * 255.0),
			]
			colors[key] = true
	return colors.size()


func _is_voxel_aligned(value: float) -> bool:
	return is_equal_approx(value * 32.0, roundf(value * 32.0))


func _is_centerline_detail(node_name: String) -> bool:
	for marker in ["Leg", "Bar", "Post", "Candle", "Flame", "Rail", "Band", "Crate", "Chest", "Lock", "Pillar", "Jamb", "Banner", "Bone", "Stone", "Plank"]:
		if node_name.contains(marker):
			return true
	return false
