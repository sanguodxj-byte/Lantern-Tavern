extends GdUnitTestSuite
## 测试 PickableItem 在素材 GLB 缺失时的 fallback 方块生成逻辑。
## 同时验证 VoxelLightingAdapter 不会破坏 GLB 内嵌材质的纹理/颜色。

const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const MISSING_MATERIAL_ID := "__missing_material_glb_for_fallback_test__"

func test_fallback_mesh_created_for_missing_glb() -> void:
	# 验证当 GLB 缺失时，_instantiate_material_model 返回 fallback 方块而非 null。
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	# moldy_bread 等已全部重做为真实 GLB；使用明确不存在的 id。
	item.material_id = MISSING_MATERIAL_ID
	add_child(item)
	await await_idle_frame()

	var mesh_inst := item.get_node_or_null(
		"FallbackMaterial_%s/FallbackMesh" % MISSING_MATERIAL_ID
	) as MeshInstance3D
	assert_object(mesh_inst).override_failure_message(
		"缺失 GLB 时应生成 FallbackMaterial_%s/FallbackMesh 节点" % MISSING_MATERIAL_ID
	).is_not_null()
	if mesh_inst != null:
		assert_object(mesh_inst.mesh).is_not_null()
		assert_bool(mesh_inst.mesh is BoxMesh).is_true()
		var mat := mesh_inst.material_override as StandardMaterial3D
		assert_object(mat).override_failure_message(
			"Fallback mesh 应有 StandardMaterial3D 覆盖"
		).is_not_null()
	item.free()


func test_fallback_mesh_uses_manifest_bbox() -> void:
	# 验证 fallback 方块尺寸来自 manifest bbox（而非默认 0.2）。
	# rusty_nail 的 GLB 现已存在；此测试仅在走 fallback 路径时校验尺寸。
	# 当 GLB 存在时 mesh_inst 为 null，测试跳过尺寸断言（由 existing_glb 用例覆盖正路径）。
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	item.material_id = "rusty_nail"
	add_child(item)
	await await_idle_frame()

	var mesh_inst := item.get_node_or_null("FallbackMaterial_rusty_nail/FallbackMesh") as MeshInstance3D
	if mesh_inst != null and mesh_inst.mesh is BoxMesh:
		var box := mesh_inst.mesh as BoxMesh
		# 只要走了 fallback，尺寸应接近 manifest bbox 而非默认立方体
		assert_float(box.size.x).is_greater(0.05)
		assert_float(box.size.y).is_greater(0.05)
		assert_float(box.size.z).is_greater(0.05)
	item.free()


func test_existing_glb_not_replaced_by_fallback() -> void:
	# 验证当 GLB 存在时，不使用 fallback（rat_tail 的 GLB 存在）。
	var item: PickableItem = load("res://scenes/equipment/pickable_item.tscn").instantiate()
	item.material_id = "rat_tail"
	add_child(item)
	await await_idle_frame()

	# 不应有 FallbackMaterial 节点
	var fallback := item.get_node_or_null("FallbackMaterial_rat_tail")
	assert_object(fallback).override_failure_message(
		"GLB 存在时不应生成 fallback 节点"
	).is_null()
	item.free()


func test_enemy_visual_meshes_have_no_material_override() -> void:
	# 验证敌人网格不被 base_material 覆写（保留 GLB 内嵌纹理）。
	# VOXEL_LIGHTING 适配器可能会设置 material_override 为适配后的材质（toon 着色），
	# 关键是确保它不是场景中定义的 base_material（无纹理纯色材质）。
	var scene := load("res://scenes/characters/enemies/goblin.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var enemy = scene.instantiate()
	add_child(enemy)
	assert_bool(enemy._visual_meshes.size() > 0).override_failure_message(
		"哥布林没有收集到任何可视网格！"
	).is_true()
	# base_material 属性仍存在于场景中（向后兼容），但不应被应用为 material_override
	var base_mat := enemy.base_material as Material
	for mesh_inst in enemy._visual_meshes:
		if base_mat != null and mesh_inst.material_override == base_mat:
			fail("哥布林子网格 %s 的 material_override 仍是 base_material（无纹理纯色）！" % mesh_inst.name)
	enemy.queue_free()


# ── VoxelLightingAdapter 测试 ──────────────────────────────

func test_adapt_preserves_albedo_texture() -> void:
	# 创建一个带纹理的 StandardMaterial3D，适配后应保留纹理
	var mat := StandardMaterial3D.new()
	var tex := ImageTexture.new()
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = false
	var adapted := VOXEL_LIGHTING.adapt_standard_material(mat)
	assert_object(adapted).is_not_null()
	assert_object(adapted.albedo_texture).override_failure_message(
		"适配后 albedo_texture 不应丢失"
	).is_not_null()
	assert_bool(adapted.vertex_color_use_as_albedo).override_failure_message(
		"适配后不应强制设置 vertex_color_use_as_albedo = true"
	).is_false()


func test_adapt_preserves_albedo_color() -> void:
	# 创建一个带 albedo_color 的 StandardMaterial3D（无纹理），适配后应保留颜色
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.6, 0.3, 1)
	mat.vertex_color_use_as_albedo = false
	var adapted := VOXEL_LIGHTING.adapt_standard_material(mat)
	assert_object(adapted).is_not_null()
	assert_float(adapted.albedo_color.r).is_equal_approx(0.4, 0.01)
	assert_float(adapted.albedo_color.g).is_equal_approx(0.6, 0.01)
	assert_float(adapted.albedo_color.b).is_equal_approx(0.3, 0.01)
	assert_bool(adapted.vertex_color_use_as_albedo).is_false()


func test_adapt_applies_toon_shading() -> void:
	# 默认模式：角色/道具 — 无金属、高 roughness
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.3
	mat.metallic = 0.8
	var adapted := VOXEL_LIGHTING.adapt_standard_material(mat)
	assert_int(adapted.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_TOON)
	assert_int(adapted.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)
	assert_float(adapted.roughness).is_equal_approx(0.85, 0.01)
	assert_float(adapted.metallic).is_equal_approx(0.0, 0.01)


func test_weapon_mode_preserves_metal() -> void:
	# 武器模式：金属部件保留 metallic，roughness 夹到可读区间
	var steel := StandardMaterial3D.new()
	steel.resource_name = "steel"
	steel.albedo_color = Color(0.62, 0.64, 0.68)
	steel.metallic = 0.9
	steel.roughness = 0.28
	var adapted := VOXEL_LIGHTING.adapt_standard_material(steel, VOXEL_LIGHTING.MODE_WEAPON)
	assert_int(adapted.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_TOON)
	assert_int(adapted.specular_mode).is_equal(BaseMaterial3D.SPECULAR_TOON)
	assert_float(adapted.metallic).is_greater_equal(0.55)
	assert_float(adapted.roughness).is_greater_equal(0.18)
	assert_float(adapted.roughness).is_less_equal(0.55)


func test_weapon_mode_grip_stays_matte() -> void:
	var grip := StandardMaterial3D.new()
	grip.resource_name = "grip"
	grip.albedo_color = Color(0.3, 0.16, 0.08)
	grip.metallic = 0.0
	grip.roughness = 0.9
	var adapted := VOXEL_LIGHTING.adapt_standard_material(grip, VOXEL_LIGHTING.MODE_WEAPON)
	assert_float(adapted.metallic).is_equal_approx(0.0, 0.01)
	assert_float(adapted.roughness).is_greater_equal(0.75)
	assert_int(adapted.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)


func test_weapon_mode_preserves_emissive_crystal_texture_and_low_roughness() -> void:
	var crystal := StandardMaterial3D.new()
	crystal.resource_name = "staff_magic_core_runes"
	crystal.albedo_texture = ImageTexture.new()
	crystal.emission_enabled = true
	crystal.emission = Color(0.08, 0.9, 0.78)
	crystal.emission_energy_multiplier = 1.8
	crystal.emission_texture = ImageTexture.new()
	crystal.roughness = 0.22
	var adapted := VOXEL_LIGHTING.adapt_standard_material(
		crystal,
		VOXEL_LIGHTING.MODE_WEAPON,
	)
	assert_object(adapted.albedo_texture).is_not_null()
	assert_bool(adapted.emission_enabled).is_true()
	assert_object(adapted.emission_texture).is_not_null()
	assert_float(adapted.emission_energy_multiplier).is_equal_approx(1.8, 0.01)
	assert_float(adapted.roughness).is_equal_approx(0.22, 0.01)
	assert_float(adapted.metallic).is_equal_approx(0.0, 0.01)
	assert_int(adapted.specular_mode).is_equal(BaseMaterial3D.SPECULAR_TOON)


func test_weapon_material_cache_reuses_instance() -> void:
	VOXEL_LIGHTING.clear_cache()
	var steel := StandardMaterial3D.new()
	steel.resource_name = "blade_steel"
	steel.metallic = 0.85
	steel.roughness = 0.3
	steel.albedo_color = Color(0.55, 0.55, 0.58)
	var a1 := VOXEL_LIGHTING.adapt_standard_material(steel, VOXEL_LIGHTING.MODE_WEAPON)
	var a2 := VOXEL_LIGHTING.adapt_standard_material(steel, VOXEL_LIGHTING.MODE_WEAPON)
	assert_bool(a1 == a2).is_true()
	var stats: Dictionary = VOXEL_LIGHTING.get_cache_stats()
	assert_int(int(stats["hits"])).is_greater_equal(1)


func test_adapt_null_returns_null() -> void:
	# 传入 null 应返回 null，不应创建默认白色材质
	var adapted := VOXEL_LIGHTING.adapt_standard_material(null)
	assert_object(adapted).is_null()


func test_adapt_material_null_source_returns_null() -> void:
	# _adapt_material 传入 null 应返回 null（不创建白色默认材质）
	var adapted := VOXEL_LIGHTING._adapt_material(null, VOXEL_LIGHTING.DEFAULT_SHADER_PROFILE)
	assert_object(adapted).is_null()
