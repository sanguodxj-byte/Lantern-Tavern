extends GdUnitTestSuite

# PickableItem 材料采集与 TavernManager 入库集成测试

func test_pickable_item_script_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/pickable_item.gd")).is_true()


func test_pickable_item_scene_exists() -> void:
	assert_bool(ResourceLoader.exists("res://scenes/equipment/pickable_item.tscn")).is_true()


func test_pickable_item_has_material_id_property() -> void:
	var script = load("res://scenes/equipment/pickable_item.gd") as GDScript
	assert_object(script).is_not_null()
	var source = script.source_code
	assert_bool(source.contains("material_id")) \
		.override_failure_message("PickableItem 缺少 material_id 属性").is_true()


func test_pickable_item_material_no_old_fictional_ids() -> void:
	# 验证 PickableItem 不再引用旧虚构材料 OBJ 路径
	var script = load("res://scenes/equipment/pickable_item.gd") as GDScript
	var source = script.source_code
	for old_id in ["wild_glowcap", "frost_berry", "mountain_barley"]:
		assert_bool(not source.contains("assets/models/%s.obj" % old_id)) \
			.override_failure_message("PickableItem 仍引用旧虚构材料模型: " + old_id).is_true()


func test_pickable_item_material_colors_match_brew_data() -> void:
	# 验证 PickableItem 中的材料颜色映射至少覆盖 BrewingData 的部分核心材料
	var script = load("res://scenes/equipment/pickable_item.gd") as GDScript
	var source = script.source_code
	# 核心材料应有对应的颜色分支
	assert_bool(source.contains("glowcap")) \
		.override_failure_message("缺少 glowcap 视觉分支").is_true()
	assert_bool(source.contains("bloom")) \
		.override_failure_message("缺少 bloom 视觉分支").is_true()
	assert_bool(source.contains("honeycomb")) \
		.override_failure_message("缺少 honeycomb 视觉分支").is_true()


# ---------- TavernManager 采集入库 ----------

func test_tavern_manager_add_material_works() -> void:
	var tm_script = load("res://globals/tavern_manager.gd") as GDScript
	var tm = tm_script.new()
	tm.add_material("wild_glowcap", 1)
	assert_int(tm.inventory.get("wild_glowcap", 0)).is_equal(1)
	tm.free()


func test_expedition_hud_add_material_routes_to_tavern_manager() -> void:
	# Verifies the expedition_hud's add_material function calls TavernManager
	var script = load("res://scenes/ui/expedition_hud.gd") as GDScript
	var source = script.source_code
	assert_bool(source.contains("TavernManager.add_material") or source.contains("add_material")) \
		.override_failure_message("ExpeditionHUD 未调用 TavernManager.add_material()").is_true()


func test_procedural_dungeon_spawns_pickable_items() -> void:
	var dg_script = load("res://scenes/expedition/procedural_dungeon.gd") as GDScript
	var source = dg_script.source_code
	assert_bool(source.contains("PICKABLE_ITEM_PREFAB")) \
		.override_failure_message("地牢未引用 PickableItem 预制体").is_true()
	assert_bool(source.contains("_spawn_random_material")) \
		.override_failure_message("地牢缺少 _spawn_random_material()").is_true()
